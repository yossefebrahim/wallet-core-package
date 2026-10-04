/// How the session reaches its executor: the [WorkerTransport] seam, and the
/// M0 [InProcessTransport]. **Internal**: never exported.
library;

import 'dart:async';

import '../errors/errors.dart';
import 'handler.dart';
import 'protocol.dart';
import 'worker_loop.dart';

/// Called with each reply the executor posts, in the order it posted them.
typedef ReplyListener = void Function(WorkerReply reply);

/// Called once if the executor dies.
typedef TerminationListener = void Function(WorkerTerminatedError error);

/// Builds the transport a new session talks through.
typedef TransportFactory = WorkerTransport Function({
  required ReplyListener onReply,
  required TerminationListener onTerminated,
});

/// The session's side of the channel to the executor that owns the handles.
///
/// The session sends [WorkerRequest]s and receives [WorkerReply]s through the
/// listeners it registered; it never sees the executor itself. That is the
/// whole seam T2.1 replaces: its isolate transport spawns a worker isolate
/// running the same `WorkerLoop` over the same `RequestHandler`, sends over a
/// `SendPort`, reports replies from its `ReceivePort`, and turns the
/// isolate's `onError` and `onExit` into [TerminationListener] calls with
/// `uncaughtDartError` and `isolateExited`. Neither the session nor the
/// protocol changes.
abstract interface class WorkerTransport {
  /// Posts [request], and the [deadline] of an operation with it, so that the
  /// executor can drop a result that would arrive too late (DECISION-12
  /// §3.9). Never handles it synchronously, never throws.
  ///
  /// **The executor receives its own copy** of any secret buffer [request]
  /// owns ([executorCopy]) — an isolate boundary copies, and the in-process
  /// transport copies to match — and **the sender's copy is overwritten
  /// before this returns** ([overwriteOwnedSecrets]), on the delivered path
  /// and on the closed path alike. The executor overwrites its own copy once
  /// it has handled or dropped the request.
  void send(WorkerRequest request, {OperationDeadline? deadline});

  /// Forces the executor down without waiting for it: the expiry of the
  /// shutdown grace period (DECISION-12 §3.8 step 4). Idempotent.
  void kill();

  /// Releases the transport after the executor finished or died. Nothing is
  /// delivered afterwards. Idempotent.
  void close();
}

/// The M0 executor: the session protocol, run on the calling isolate's event
/// loop (DECISION-12 §1, "In M0 the worker is an in-process executor").
///
/// Asynchronous both ways, like an isolate boundary: a sent request reaches
/// the loop in a later microtask and is handled in a later event-loop turn,
/// and every reply and the termination report reach the session in a later
/// microtask, in the order they were posted. So no request ever runs inside
/// the public call that submitted it, and no reply is delivered inside one.
///
/// What it cannot emulate: native work blocks the calling isolate while it
/// runs, so no timer fires during it. Deadlines are therefore also checked
/// by the executor itself, before an operation starts and after it ends, and
/// by the session when the reply arrives. And [kill] can still release what
/// the executor owned, which a killed isolate cannot.
final class InProcessTransport implements WorkerTransport {
  /// Creates a transport whose executor runs [handler].
  InProcessTransport(
    this.handler, {
    required this._onReply,
    required this._onTerminated,
  }) {
    _loop = WorkerLoop(handler, post: _deliver, onFault: _fault);
  }

  /// A [TransportFactory] for [handler].
  static TransportFactory factory(RequestHandler handler) =>
      ({required onReply, required onTerminated}) => InProcessTransport(
        handler,
        onReply: onReply,
        onTerminated: onTerminated,
      );

  /// The handler the executor drives. Exposed for the internal test seam.
  final RequestHandler handler;

  final ReplyListener _onReply;
  final TerminationListener _onTerminated;
  late final WorkerLoop _loop;
  bool _closed = false;

  @override
  void send(WorkerRequest request, {OperationDeadline? deadline}) {
    if (_closed) {
      overwriteOwnedSecrets(request);
      return;
    }
    final delivered = executorCopy(request);
    // The sender's copy, now that the executor has its own.
    overwriteOwnedSecrets(request);
    scheduleMicrotask(() {
      if (_closed) {
        overwriteOwnedSecrets(delivered);
        return;
      }
      _loop.receive(delivered, deadline: deadline);
    });
  }

  @override
  void kill() {
    _loop.kill();
    _closed = true;
  }

  @override
  void close() {
    _loop.kill();
    _closed = true;
  }

  void _deliver(WorkerReply reply) {
    scheduleMicrotask(() {
      if (!_closed) _onReply(reply);
    });
  }

  void _fault(WorkerTerminatedError error) {
    scheduleMicrotask(() {
      if (!_closed) _onTerminated(error);
    });
  }
}
