/// [WalletCoreSession]: the session's side of the protocol — admission, the
/// queue bound, deadlines, the state machine, shutdown. **Internal**: the
/// public type is [WalletCore].
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:wallet_core_flutter_native/wallet_core_flutter_native.dart'
    show ManifestIdentity;

import '../address/address_facade.dart';
import '../errors/errors.dart';
import '../lifecycle/session_state.dart';
import '../mnemonic/mnemonic_facade.dart';
import '../signing/local_signer.dart';
import '../signing/signer.dart';
import '../wallet/wallet.dart';
import '../worker/handler.dart';
import '../worker/protocol.dart';
import '../worker/transport.dart';
import 'scope.dart';
import 'wallet_core.dart';

/// Starts a session and returns it once `ready`.
///
/// The public [WalletCore.initialize] calls this with the defaults only.
/// [hostLibraryPath], [expectedIdentity], [manifestBytes], and [transport] are
/// the internal seams the test entry point (`testing.dart`) sets; the public
/// surface can reach none of them (threat model TM-13).
Future<WalletCoreSession> startSession({
  required int queueLimit,
  required OperationTimeouts timeouts,
  String? hostLibraryPath,
  ManifestIdentity expectedIdentity = ManifestIdentity.embedded,
  Uint8List? manifestBytes,
  TransportFactory? transport,
}) async {
  if (queueLimit < 1) {
    throw const InvalidInputError(
      'queueLimit must be at least 1',
      inputName: 'queueLimit',
    );
  }
  for (final timeout in [
    timeouts.initialize,
    timeouts.walletOperation,
    timeouts.derivation,
    timeouts.signing,
    timeouts.shutdownGrace,
  ]) {
    if (timeout <= Duration.zero) {
      throw const InvalidInputError(
        'every timeout must be positive',
        inputName: 'timeouts',
      );
    }
  }
  final session = WalletCoreSession._(
    queueLimit: queueLimit,
    timeouts: timeouts,
    transport: transport ?? InProcessTransport.factory(EngineRequestHandler()),
  );
  await session._initialize(
    hostLibraryPath: hostLibraryPath,
    expectedIdentity: expectedIdentity,
    manifestBytes: manifestBytes,
  );
  return session;
}

/// One request the session is waiting on a reply for.
final class _Pending {
  _Pending({
    required this.operation,
    required this.isOperation,
    required this.timeout,
    required this.onReply,
    required this.onError,
  }) : stopwatch = Stopwatch()..start();

  final String operation;

  /// Counted against `queueLimit`. Control messages are not.
  final bool isOperation;

  /// The deadline, from submission; `null` for control messages.
  final Duration? timeout;
  final void Function(WorkerReply reply) onReply;
  final void Function(Object error) onError;
  final Stopwatch stopwatch;
  Timer? timer;

  /// The caller's future has completed — by its reply, its deadline, or the
  /// session ending. A reply that arrives afterwards is discarded.
  bool settled = false;

  bool get expired => timeout != null && stopwatch.elapsed > timeout!;

  void fail(Object error) {
    if (settled) return;
    settled = true;
    timer?.cancel();
    onError(error);
  }
}

/// The session behind [WalletCore].
///
/// Allocates request ids, admits or rejects operations, keeps the table of
/// replies it is waiting for, enforces deadlines, and runs the state machine
/// of DECISION-12 §3.1. It never holds a native handle and never calls
/// native code; it reaches the executor only through a [WorkerTransport].
///
/// It holds no strong reference to any `Wallet` proxy, so that a proxy the
/// application drops can be collected and its finalizer can run.
final class WalletCoreSession implements WalletCore {
  WalletCoreSession._({
    required this.queueLimit,
    required this.timeouts,
    required TransportFactory transport,
  }) {
    _transport = transport(onReply: _onReply, onTerminated: _onTerminated);
  }

  /// The bound on queued plus in-flight operations.
  final int queueLimit;

  /// The deadlines.
  final OperationTimeouts timeouts;

  static int _nextSessionToken = 1;

  /// This session's number among the sessions of this isolate: positive,
  /// never reused. Every wallet reference it issues crosses to the executor
  /// with it, and the executor, told it by [Init], refuses a locator that
  /// carries another (`KeyResolutionReason.foreignRef`). Not a secret.
  final int sessionToken = _nextSessionToken++;

  late final WorkerTransport _transport;

  /// The transport, for the internal test seam.
  WorkerTransport get transport => _transport;

  SessionState _state = SessionState.initializing;

  /// Asynchronous delivery, so a listener cannot re-enter the state machine
  /// in the middle of a transition.
  final StreamController<SessionState> _states =
      StreamController<SessionState>.broadcast();

  int _nextId = 1;
  final Map<int, _Pending> _pending = <int, _Pending>{};
  int _outstanding = 0;
  final Set<int> _cancelsSent = <int>{};

  WorkerTerminatedError? _termination;
  Future<void>? _shutdown;
  bool _forcedTermination = false;
  int? _disposedAtShutdown;

  @override
  late final WalletFacade wallets = WalletFacadeImpl(this);

  @override
  late final AddressFacade addresses = AddressFacadeImpl(this);

  @override
  late final MnemonicFacade mnemonics = MnemonicFacadeImpl(this);

  @override
  late final LocalSigner signer = SessionSigner(this);

  @override
  SessionState get state => _state;

  @override
  Stream<SessionState> get states => _states.stream;

  /// Queued plus in-flight operations, as the bound counts them: from
  /// submission until the reply arrives, whether or not the caller's future
  /// has already completed on its deadline.
  int get outstandingOperations => _outstanding;

  /// How many wallets the executor released at shutdown, once it has
  /// acknowledged; `null` before, or when shutdown was forced.
  int? get disposedAtShutdown => _disposedAtShutdown;

  /// Whether shutdown had to force the executor down.
  bool get forcedTermination => _forcedTermination;

  // --- lifecycle --------------------------------------------------------------

  Future<void> _initialize({
    required String? hostLibraryPath,
    required ManifestIdentity expectedIdentity,
    required Uint8List? manifestBytes,
  }) async {
    try {
      await _send<void>(
        Init(
          _nextId++,
          queueLimit: queueLimit,
          expectedIdentity: expectedIdentity,
          manifestBytes: manifestBytes,
          hostLibraryPath: hostLibraryPath,
          sessionToken: sessionToken,
        ),
        timeout: timeouts.initialize,
        parse: (reply) => reply is InitOk ? null : throw _unexpected(reply),
      );
    } on Object {
      // initializing → failed. The session is never handed out, so it is
      // also torn down here: there is nothing for anybody to close.
      if (_state == SessionState.initializing) {
        _transition(SessionState.failed);
      }
      _failAllPending(_termination ?? const ClosedError('WalletCore'));
      _transport.close();
      await _states.close();
      rethrow;
    }
    _transition(SessionState.ready);
  }

  @override
  Future<T> scope<T>(Future<T> Function(SessionScope scope) body) =>
      runInScope(this, body);

  @override
  Future<void> shutdown() {
    final existing = _shutdown;
    if (existing != null) return existing;
    switch (_state) {
      case SessionState.closed:
        return Future<void>.value();
      case SessionState.failed:
        // failed → closed: the executor is already gone; only the Dart side
        // is torn down.
        return _shutdown = _finishClosed();
      case SessionState.initializing:
        return Future<void>.error(
          const SessionStateError(
            SessionState.initializing,
            attempted: 'shutdown',
          ),
        );
      case SessionState.ready:
      case SessionState.closing:
        return _shutdown = _runShutdown();
    }
  }

  Future<void> _runShutdown() async {
    _transition(SessionState.closing);
    final acknowledged = Completer<int>();
    final grace = Timer(timeouts.shutdownGrace, () {
      if (acknowledged.isCompleted) return;
      // DECISION-12 §3.8 step 4: no acknowledgement within the grace period.
      _forcedTermination = true;
      _transport.kill();
      acknowledged.completeError(
        const WorkerTerminatedError(WorkerTerminationKind.isolateExited),
      );
    });
    _sendControl<int>(
      (id) => Shutdown(id, grace: timeouts.shutdownGrace),
      parse: (reply) => reply is ShutdownComplete
          ? reply.disposedCount
          : throw _unexpected(reply),
    ).then(
      (count) {
        if (!acknowledged.isCompleted) acknowledged.complete(count);
      },
      onError: (Object error) {
        if (!acknowledged.isCompleted) acknowledged.completeError(error);
      },
    );
    try {
      _disposedAtShutdown = await acknowledged.future;
    } on WorkerTerminatedError {
      if (!_forcedTermination) {
        // The executor died during shutdown (closing → failed): handles may
        // not have been released, and the caller is told so.
        await _finishClosed();
        rethrow;
      }
    } finally {
      grace.cancel();
    }
    await _finishClosed();
  }

  Future<void> _finishClosed() async {
    if (_state == SessionState.closed) return;
    _failAllPending(
      _forcedTermination
          ? const WorkerTerminatedError(WorkerTerminationKind.isolateExited)
          : const ClosedError('WalletCore'),
    );
    _transport.close();
    _transition(SessionState.closed);
    await _states.close();
  }

  void _onTerminated(WorkerTerminatedError error) {
    if (_state == SessionState.closed || _state == SessionState.failed) return;
    _termination = error;
    _transition(SessionState.failed);
    _failAllPending(error);
    _transport.close();
  }

  void _transition(SessionState next) {
    if (_state == next) return;
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  // --- admission --------------------------------------------------------------

  /// Throws the error DECISION-12 §3.1 assigns to [attempted] in the current
  /// state, or returns when the session is `ready`.
  void checkReady(String attempted) {
    switch (_state) {
      case SessionState.ready:
        return;
      case SessionState.initializing:
      case SessionState.closing:
        throw SessionStateError(_state, attempted: attempted);
      case SessionState.closed:
        throw const ClosedError('WalletCore');
      case SessionState.failed:
        throw _termination ??
            const WorkerTerminatedError(WorkerTerminationKind.isolateExited);
    }
  }

  /// Submits one operation and returns its parsed reply.
  ///
  /// Rejects it synchronously — as a thrown error; nothing is sent — unless
  /// the session is `ready` and fewer than [queueLimit] operations are
  /// outstanding. The deadline [timeout] starts now. A rejected request's id
  /// is spent, never reused; ids only need to be unique and increasing.
  Future<T> submit<T>(
    WorkerRequest Function(int id) build, {
    required Duration timeout,
    required T Function(WorkerReply reply) parse,
  }) {
    final request = build(_nextId++);
    try {
      checkReady(request.operation);
      if (_outstanding >= queueLimit) throw QueueFullError(queueLimit);
    } on Object {
      overwriteOwnedSecrets(request);
      rethrow;
    }
    return _send(request, timeout: timeout, parse: parse);
  }

  Future<T> _send<T>(
    WorkerRequest request, {
    required Duration timeout,
    required T Function(WorkerReply reply) parse,
  }) {
    final id = request.id;
    final completer = Completer<T>();
    // Taken before the session's own stopwatch starts, so the executor's
    // deadline is never later than the session's.
    final deadline = OperationDeadline.after(timeout);
    final pending = _Pending(
      operation: request.operation,
      isOperation: true,
      timeout: timeout,
      onReply: (reply) => _complete(completer, reply, parse),
      onError: completer.completeError,
    );
    _pending[id] = pending;
    _outstanding++;
    pending.timer = Timer(timeout, () => _expire(id));
    _transport.send(request, deadline: deadline);
    return completer.future;
  }

  /// Sends a control message whose reply somebody awaits. Never rejected for
  /// a full queue; no deadline (DECISION-12 §3.4, §3.5).
  Future<T> _sendControl<T>(
    WorkerRequest Function(int id) build, {
    required T Function(WorkerReply reply) parse,
  }) {
    final id = _nextId++;
    final request = build(id);
    final completer = Completer<T>();
    _pending[id] = _Pending(
      operation: request.operation,
      isOperation: false,
      timeout: null,
      onReply: (reply) => _complete(completer, reply, parse),
      onError: completer.completeError,
    );
    _transport.send(request);
    return completer.future;
  }

  /// Sends a control message nobody awaits. Its reply arrives under an id
  /// with no pending entry and is dropped.
  void _post(WorkerRequest Function(int id) build) {
    _transport.send(build(_nextId++));
  }

  void _complete<T>(
    Completer<T> completer,
    WorkerReply reply,
    T Function(WorkerReply reply) parse,
  ) {
    if (reply is Failed) {
      completer.completeError(reply.error);
      return;
    }
    final T value;
    try {
      value = parse(reply);
    } on Object catch (error) {
      completer.completeError(error);
      return;
    }
    completer.complete(value);
  }

  void _onReply(WorkerReply reply) {
    final pending = _pending.remove(reply.id);
    if (pending == null) return;
    if (pending.isOperation) _outstanding--;
    pending.timer?.cancel();
    if (!pending.settled && pending.expired) {
      // The executor blocked the event loop past the deadline (M0), or the
      // reply crossed the expiry: the deadline wins and the result is
      // discarded (DECISION-12 §3.5).
      pending.fail(OperationTimeoutError(pending.operation, pending.timeout!));
    }
    if (pending.settled) {
      _discardLate(reply);
      return;
    }
    pending.settled = true;
    pending.onReply(reply);
  }

  void _expire(int id) {
    final pending = _pending[id];
    if (pending == null || pending.settled) return;
    pending.fail(OperationTimeoutError(pending.operation, pending.timeout!));
    // Still queued? Then it need never run. The entry stays until the reply
    // arrives, so the bound keeps counting it while the executor holds it.
    if (_state == SessionState.ready && _cancelsSent.add(id)) {
      _post((cancelId) => Cancel(cancelId, target: id));
    }
  }

  /// A result nobody will receive. **A backstop**: the executor drops a
  /// result whose deadline passed before posting it (`WorkerLoop`), so this
  /// sees one only when the session's timer and the executor's clock
  /// disagree at the edge. A wallet created for a caller who already got
  /// [OperationTimeoutError] is released at once rather than left to
  /// shutdown; anything else is simply dropped.
  void _discardLate(WorkerReply reply) {
    if (reply is WalletCreated && _state == SessionState.ready) {
      _post((id) => DisposeRef(id, walletRef: reply.walletRef));
    }
  }

  void _failAllPending(Object error) {
    final pending = _pending.values.toList();
    _pending.clear();
    _outstanding = 0;
    for (final entry in pending) {
      entry.fail(error);
    }
  }

  // --- wallet lifecycle ---------------------------------------------------------

  /// Releases the wallet [walletRef] in the executor and awaits the
  /// acknowledgement — with no deadline (DECISION-12 §3.5).
  ///
  /// In `closing` the acknowledgement is shutdown's; in `closed` there is
  /// nothing left to release; after a failure — in `failed`, or in `closed`
  /// reached from `failed` — the session's termination error is the answer.
  Future<void> releaseWallet(int walletRef) {
    switch (_state) {
      case SessionState.ready:
        return _sendControl<void>(
          (id) => DisposeRef(id, walletRef: walletRef),
          parse: (reply) => reply is Disposed ? null : throw _unexpected(reply),
        );
      case SessionState.closing:
        // Shutdown's acknowledgement is this wallet's — unless the executor
        // was forced down, in which case nothing acknowledged its release
        // (lifecycle.md §2: the isolate ended first).
        final shutdown = _shutdown;
        if (shutdown == null) return Future<void>.value();
        return shutdown.then((_) {
          if (_forcedTermination) {
            throw const WorkerTerminatedError(
              WorkerTerminationKind.isolateExited,
            );
          }
        });
      case SessionState.closed:
        // Closed after a failure (failed → closed): the executor died before
        // shutdown, so nothing confirmed this wallet's release either.
        final termination = _termination;
        if (termination != null) return Future<void>.error(termination);
        if (_forcedTermination) {
          return Future<void>.error(
            const WorkerTerminatedError(WorkerTerminationKind.isolateExited),
          );
        }
        return Future<void>.value();
      case SessionState.failed:
      case SessionState.initializing:
        return Future<void>.sync(() => checkReady('close'));
    }
  }

  /// The proxy finalizer's callback (PRD §11.2 item 8; lifecycle.md §5).
  ///
  /// May run at any time; **posts** `DisposeRef` only while the session is
  /// `ready`, and in every other state does nothing — shutdown already
  /// released every handle. Awaits nothing, never throws, never reports.
  void postFinalizerDispose(int walletRef) {
    if (_state != SessionState.ready) return;
    try {
      _post((id) => DisposeRef(id, walletRef: walletRef));
    } on Object {
      // Nothing to tell anybody, and nobody to tell it to.
    }
  }

  /// Asks the executor to withdraw the queued request [target]. Answered
  /// without a round trip when [target] is not awaiting a reply (DECISION-12
  /// §3.4 rule 2), and at most once per target (rule 1). Returns whether a
  /// `Cancel` was sent.
  bool cancel(int target) {
    final pending = _pending[target];
    if (pending == null || !pending.isOperation || pending.settled) {
      return false;
    }
    if (_state != SessionState.ready || !_cancelsSent.add(target)) {
      return false;
    }
    _post((id) => Cancel(id, target: target));
    return true;
  }

  /// The id the next request will carry.
  int get nextRequestId => _nextId;

  static StateError _unexpected(WorkerReply reply) =>
      StateError('unexpected reply ${reply.runtimeType}');
}
