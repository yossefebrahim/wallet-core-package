/// The executor's message loop: the single FIFO queue, cancellation, the
/// shutdown sequence, the control-path bounds, and the fault rule
/// (DECISION-12 §3.4–§3.10). **Internal**: never exported.
library;

import 'dart:async';
import 'dart:collection';

import '../errors/errors.dart';
import '../lifecycle/session_state.dart';
import 'handler.dart';
import 'protocol.dart';

/// The fixed part of the reserved control capacity (DECISION-12 §3.4 rule 3).
const int controlReserve = 8;

/// The [WorkerTerminatedError.cause] the executor reports when it dies of an
/// error nobody mapped.
///
/// It names the error's **type only**. An arbitrary error's text can quote
/// its input — a `FormatException` carries the bytes it failed to decode,
/// which on the export path are a mnemonic — so the original is not kept
/// (threat model TM-09, TM-31).
final class WorkerFault implements Exception {
  /// Creates the cause for an error of [errorType].
  const WorkerFault(this.errorType);

  /// The runtime type of the error, by name.
  final String errorType;

  @override
  String toString() =>
      'WorkerFault: the session executor ended on an unexpected $errorType '
      '(its message is withheld because it may quote input)';
}

/// Drives a [RequestHandler] one request at a time, in arrival order, in the
/// isolate that owns the native handles.
///
/// The same loop runs inside the M0 in-process transport and, from T2.1,
/// inside the worker isolate: a transport only has to call [receive] for each
/// arriving request and carry what [post] and [onFault] report back.
///
/// * **Never synchronous.** [receive] only enqueues; each request is handled
///   in its own later turn of the event loop, scheduled with [schedule].
/// * **Operations and `DisposeRef` share one FIFO**, so a `close()` queued
///   behind work on the same wallet runs after it (DECISION-12 §3.8, §4.2).
/// * **`Cancel` is decided on arrival** and never queued (§3.6).
/// * **`Shutdown`** rejects every queued operation with [SessionStateError]
///   on arrival, lets queued `DisposeRef`s and the one running operation
///   finish, then runs last (§3.8). Afterwards nothing is answered.
/// * **The control path is bounded** (§3.4): one pending `DisposeRef` per
///   reference, repeats folded into it; `Cancel` never pending; and the
///   pending control set asserted against `queueLimit + liveRefs +`
///   [controlReserve]. The operation count is asserted against `queueLimit`
///   too. A failed assertion is a bug in the session's admission, and the
///   loop fails rather than grows.
/// * **The fault rule.** When the handler rethrows an error it could not map,
///   the loop stops for good: it releases every handle the handler owns
///   (best effort), answers nothing more — neither the request that faulted
///   nor anything queued — and reports [WorkerTerminatedError] through
///   [onFault]: kind `initializationFailed` during `Init`,
///   `uncaughtDartError` otherwise. That is what a dying worker isolate looks
///   like from outside, so the session reacts identically in M0 and from
///   T2.1. Nothing is retried.
final class WorkerLoop {
  /// Creates a loop over [handler].
  WorkerLoop(
    this._handler, {
    required this.post,
    required this.onFault,
    this._schedule = Timer.run,
  });

  final RequestHandler _handler;

  /// Carries one reply back to the session.
  final void Function(WorkerReply reply) post;

  /// Reports that the loop has died.
  final void Function(WorkerTerminatedError error) onFault;

  final void Function(void Function()) _schedule;

  final Queue<WorkerRequest> _queue = Queue<WorkerRequest>();

  /// Extra request ids folded into the one pending `DisposeRef` per reference.
  final Map<int, List<int>> _pendingDisposals = <int, List<int>>{};

  final List<int> _shutdownIds = <int>[];
  int _queueLimit = 1;
  bool _drainScheduled = false;
  bool _shutdownRequested = false;
  bool _finished = false;

  /// Whether the loop has stopped: shut down, faulted, or killed.
  bool get isFinished => _finished;

  /// How many requests are waiting, operations and `DisposeRef`s together.
  int get queuedCount => _queue.length;

  /// Accepts one arriving request.
  void receive(WorkerRequest request) {
    if (_finished) {
      // After shutdown, or once dead, nothing is answered (§3.7): a worker
      // isolate would have exited and the runtime would drop the message.
      overwriteOwnedSecrets(request);
      return;
    }
    switch (request) {
      case Cancel():
        _cancel(request);
        return;
      case Shutdown():
        _shutdown(request);
      case DisposeRef(:final walletRef):
        final folded = _pendingDisposals[walletRef];
        if (folded != null) {
          folded.add(request.id);
          return;
        }
        _pendingDisposals[walletRef] = <int>[];
        _queue.add(request);
        final capacity = _queueLimit + _handler.liveRefCount + controlReserve;
        if (_pendingDisposals.length > capacity) {
          _fault(StateError('control capacity exceeded'), SessionState.ready);
          return;
        }
      default:
        if (_shutdownRequested) {
          post(
            Failed(
              request.id,
              SessionStateError(
                SessionState.closing,
                attempted: request.operation,
              ),
            ),
          );
          overwriteOwnedSecrets(request);
          return;
        }
        if (request is Init) _queueLimit = request.queueLimit;
        _queue.add(request);
        if (_operationCount > _queueLimit) {
          _fault(StateError('operation bound exceeded'), SessionState.ready);
          return;
        }
    }
    _scheduleDrain();
  }

  /// Stops the loop without a reply and releases what the handler owns. The
  /// in-process stand-in for killing a worker isolate when the shutdown grace
  /// period expires; unlike a killed isolate, it can still release.
  void kill() {
    if (_finished) return;
    _stop();
  }

  int get _operationCount => _queue.where((r) => !r.isControl).length;

  void _cancel(Cancel request) {
    final target = request.target;
    WorkerRequest? queued;
    for (final candidate in _queue) {
      if (candidate.id == target && !candidate.isControl) {
        queued = candidate;
        break;
      }
    }
    if (queued == null) {
      post(NotCancellable(request.id, target: target));
      return;
    }
    _queue.remove(queued);
    overwriteOwnedSecrets(queued);
    post(Failed(target, OperationCancelledError(target)));
    post(Cancelled(request.id, target: target));
  }

  void _shutdown(Shutdown request) {
    _shutdownIds.add(request.id);
    if (_shutdownRequested) return;
    _shutdownRequested = true;
    final kept = <WorkerRequest>[];
    for (final queued in _queue) {
      if (queued is DisposeRef) {
        kept.add(queued);
        continue;
      }
      post(
        Failed(
          queued.id,
          SessionStateError(SessionState.closing, attempted: queued.operation),
        ),
      );
      overwriteOwnedSecrets(queued);
    }
    _queue
      ..clear()
      ..addAll(kept)
      ..add(request);
  }

  void _scheduleDrain() {
    if (_drainScheduled || _finished || _queue.isEmpty) return;
    _drainScheduled = true;
    _schedule(_drainOne);
  }

  void _drainOne() {
    _drainScheduled = false;
    if (_finished || _queue.isEmpty) return;
    final request = _queue.removeFirst();
    final WorkerReply reply;
    try {
      reply = _handler.handle(request);
    } on Object catch (error) {
      _fault(
        error,
        request is Init ? SessionState.initializing : SessionState.ready,
      );
      return;
    }
    // The handler has parsed and released; only now is the reply posted
    // (DECISION-12 §3.9).
    post(reply);
    switch (request) {
      case DisposeRef(:final walletRef):
        for (final id in _pendingDisposals.remove(walletRef) ?? const <int>[]) {
          post(Disposed(id, walletRef: walletRef));
        }
      case Shutdown():
        final count = reply is ShutdownComplete ? reply.disposedCount : 0;
        for (final id in _shutdownIds.skip(1)) {
          post(ShutdownComplete(id, disposedCount: count));
        }
        _finished = true;
        _queue.clear();
        return;
      default:
    }
    _scheduleDrain();
  }

  void _fault(Object error, SessionState during) {
    _stop();
    onFault(
      WorkerTerminatedError(
        during == SessionState.initializing
            ? WorkerTerminationKind.initializationFailed
            : WorkerTerminationKind.uncaughtDartError,
        cause: WorkerFault(error.runtimeType.toString()),
      ),
    );
  }

  void _stop() {
    _finished = true;
    for (final queued in _queue) {
      overwriteOwnedSecrets(queued);
    }
    _queue.clear();
    _pendingDisposals.clear();
    _handler.releaseAll();
  }
}
