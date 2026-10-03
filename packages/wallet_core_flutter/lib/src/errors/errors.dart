/// The sealed error hierarchy of the public SDK (PRD §10.2, DECISION-11 §5,
/// DECISION-12 §6, `docs/architecture/lifecycle.md` §3).
///
/// Every member is declared in this one library because the base is
/// `sealed`: a caller can `switch` exhaustively over [WalletCoreException],
/// and adding a member is a breaking change taken deliberately.
///
/// **No secret ever appears in an error** (threat model TM-09, TM-31). No
/// [WalletCoreException.message] and no `toString()` here contains a mnemonic,
/// entropy, a passphrase, a private key, or the rejected input itself when that
/// input could be one of those. Errors name *which* input was rejected and
/// *why*, never *what* it was.
library;

import 'package:wallet_core_flutter_native/wallet_core_flutter_native.dart'
    show ManifestCheck;

import '../coin/coin.dart';
import '../lifecycle/session_state.dart';

/// Base of every error this SDK raises. Sealed: a caller can switch
/// exhaustively, and a new member is a breaking change we take deliberately.
sealed class WalletCoreException implements Exception {
  const WalletCoreException();

  /// What went wrong, in one sentence. Never contains key material or a
  /// rejected secret input.
  String get message;

  /// The type name and [message]. Nothing else, for the reason [message]
  /// gives.
  @override
  String toString() => '${_typeName(this)}: $message';
}

/// Stable type names for [WalletCoreException.toString], independent of
/// `runtimeType` (which an obfuscated build renames).
String _typeName(WalletCoreException error) => switch (error) {
  UnknownCoinError() => 'UnknownCoinError',
  InvalidInputError() => 'InvalidInputError',
  UnsupportedOperationError() => 'UnsupportedOperationError',
  SigningError() => 'SigningError',
  KeyResolutionError() => 'KeyResolutionError',
  DisposedError() => 'DisposedError',
  ClosedError() => 'ClosedError',
  WorkerTerminatedError() => 'WorkerTerminatedError',
  NativeLoadError() => 'NativeLoadError',
  ManifestMismatchError() => 'ManifestMismatchError',
  SessionStateError() => 'SessionStateError',
  QueueFullError() => 'QueueFullError',
  OperationTimeoutError() => 'OperationTimeoutError',
  OperationCancelledError() => 'OperationCancelledError',
};

/// Input rejected by this SDK before reaching native code — or rejected by
/// upstream, which this SDK reports the same way (PRD §16 S5).
///
/// [inputName] names the input (`'mnemonic'`, `'derivationPath'`, `'address'`,
/// `'strength'`, …). The input's *value* is never carried: it may be a secret,
/// and an error is exactly the thing that reaches a log (threat model TM-09).
final class InvalidInputError extends WalletCoreException {
  /// Creates an error explaining why the input named [inputName] was
  /// rejected. [message] must not quote the input.
  const InvalidInputError(this.message, {this.inputName});

  @override
  final String message;

  /// Which input was rejected, e.g. `'mnemonic'`. Never its value.
  final String? inputName;
}

/// The requested coin id is not known at the pinned upstream tag, and is not a
/// recognised alias for one that is.
final class UnknownCoinError extends InvalidInputError {
  /// Creates an error for the unresolvable [coinId].
  const UnknownCoinError(this.coinId)
    : super(
        'no coin has this id at the pinned upstream tag',
        inputName: 'coin',
      );

  /// The id that did not resolve. A coin id is configuration, not a secret.
  final String coinId;

  /// The message and the id, the id shortened if it is implausibly long.
  @override
  String toString() {
    final shown = coinId.length <= 64 ? coinId : '${coinId.substring(0, 64)}…';
    return 'UnknownCoinError: $message: "$shown"';
  }
}

/// The coin, capability, variant, or combination is not offered at this version
/// or at the pinned upstream tag. Carries the coin and a capability string, e.g.
/// `'network:testnet'`, `'multisig'`, `'psbt'`, `'external-signer'`.
///
/// The coin facade produces `'network:<id>'`, `'addressStyle:<id>'`, and
/// `'coin:removedUpstream'` (`docs/architecture/public_model.md` §5), and the
/// engine produces `'deriveAddress'` when upstream cannot derive an address
/// for a coin at all.
final class UnsupportedOperationError extends WalletCoreException {
  /// Creates an error saying [coin] does not offer [capability].
  const UnsupportedOperationError(this.coin, this.capability);

  /// The coin the operation was asked of.
  final Coin coin;

  /// What it does not offer, e.g. `'network:testnet'`.
  final String capability;

  @override
  String get message =>
      '${coin.id} does not offer $capability at this version or at the '
      'pinned upstream tag';
}

/// Upstream reported a signing failure. Carries upstream's numeric code and its
/// message, verbatim and unmodified; never the input that caused it.
final class SigningError extends WalletCoreException {
  /// Creates an error from upstream's [upstreamCode] and [message].
  const SigningError(this.upstreamCode, this.message);

  /// Upstream's `SigningOutput.error` value.
  final int upstreamCode;

  /// Upstream's `SigningOutput.error_message`, verbatim.
  @override
  final String message;
}

/// The named keys could not be resolved into the set the operation needs:
/// a missing role, an unused locator, a reference from another session, or an
/// account with no key behind it.
final class KeyResolutionError extends WalletCoreException {
  /// Creates an error explaining which key could not be resolved.
  const KeyResolutionError(this.message);

  @override
  final String message;
}

/// An **internal** native-backed object was used after `dispose()`.
/// Never raised by the public surface; visible through `advanced.dart`.
///
/// The bindings package raises its own `DisposedError` (an `Error`, from a
/// package below this one, which cannot join this sealed hierarchy); the SDK
/// converts it to this type at its boundary, keeping [resourceType].
final class DisposedError extends WalletCoreException {
  /// Creates an error naming the disposed [resourceType], e.g. `'HDWallet'`.
  const DisposedError(this.resourceType);

  /// The Dart type name of the resource that was used. Never its contents.
  final String resourceType;

  @override
  String get message => '$resourceType used after dispose()';
}

/// A **public** resource was used after `close()`.
final class ClosedError extends WalletCoreException {
  /// Creates an error naming the closed [resourceType], e.g. `'Wallet'`.
  const ClosedError(this.resourceType);

  /// The public type that was used after `close()`.
  final String resourceType;

  @override
  String get message => '$resourceType used after close()';
}

/// The session's owning isolate ended. Every reference is invalid and the
/// session must be re-initialized. Nothing is ever retried silently.
final class WorkerTerminatedError extends WalletCoreException {
  /// Creates an error for a termination of [kind], with the [cause] when one
  /// was observed.
  const WorkerTerminatedError(this.kind, {this.cause});

  /// Why the owning isolate ended.
  final WorkerTerminationKind kind;

  /// The error the isolate reported, when it reported one.
  ///
  /// Kept for the application to inspect; [message] names only its type,
  /// so that rendering this error never renders whatever the cause carried.
  final Object? cause;

  @override
  String get message {
    final what = switch (kind) {
      WorkerTerminationKind.initializationFailed =>
        'the session failed to initialize',
      WorkerTerminationKind.uncaughtDartError =>
        'the session isolate ended with an uncaught error',
      WorkerTerminationKind.isolateExited => 'the session isolate exited',
    };
    final cause = this.cause;
    return cause == null ? what : '$what (${cause.runtimeType})';
  }
}

/// Why the owning isolate ended.
///
/// There is deliberately no member for a hard native crash: such a crash ends
/// the whole process, so no code of ours survives to report it. The application's
/// platform crash reporter is the only observer of that case.
enum WorkerTerminationKind {
  /// Loading, identity verification, or symbol lookup failed during `Init`.
  initializationFailed,

  /// The isolate's error port reported an uncaught Dart error.
  uncaughtDartError,

  /// The isolate exited without reporting an error.
  isolateExited,
}

/// The native library could not be located, loaded, or resolved — including the
/// case where the build-identity symbol is absent, which means the loaded
/// library is not one of ours.
final class NativeLoadError extends WalletCoreException {
  /// Creates an error with the loader's [message], every location it tried,
  /// and the underlying [cause] when there was one.
  NativeLoadError(
    this.message, {
    List<NativeLoadAttempt> attempts = const <NativeLoadAttempt>[],
    this.cause,
  }) : attempts = List<NativeLoadAttempt>.unmodifiable(attempts);

  @override
  final String message;

  /// Every location the loader tried, in order, with why each failed. Empty
  /// when the failure was not a load failure (a missing symbol, say).
  final List<NativeLoadAttempt> attempts;

  /// The underlying error, when there was one.
  final Object? cause;

  /// The message and every attempted location. Library paths and loader
  /// errors are not secrets, and a developer needs them to fix the failure.
  @override
  String toString() {
    final buffer = StringBuffer('NativeLoadError: $message');
    for (final attempt in attempts) {
      buffer.write('\n  tried ${attempt.location}: ${attempt.reason}');
    }
    return buffer.toString();
  }
}

/// One location the native loader tried, and why it did not work.
final class NativeLoadAttempt {
  /// Creates a record of one attempt.
  const NativeLoadAttempt({required this.location, required this.reason});

  /// What was tried, in words a developer can act on.
  final String location;

  /// Why it failed.
  final String reason;

  @override
  String toString() => '$location: $reason';
}

/// The shipped manifest, the three packages' embedded release-set ids, and the
/// loaded library's build identity do not agree. [check] names which comparison
/// failed.
final class ManifestMismatchError extends WalletCoreException {
  /// Creates an error for the failed [check], with the value that was
  /// [expected], the value found ([actual]), and optional [detail].
  const ManifestMismatchError({
    required this.check,
    required this.expected,
    required this.actual,
    this.detail = '',
  });

  /// Which comparison failed.
  final ManifestCheck check;

  /// The value the manifest, or the embedded constant, said it should be.
  final String expected;

  /// The value actually found.
  final String actual;

  /// Optional extra context, such as which package carried the odd value.
  final String detail;

  @override
  String get message {
    final described = switch (check) {
      ManifestCheck.releaseSetMismatch =>
        'release-set ids disagree across the three packages',
      ManifestCheck.manifestHashMismatch =>
        'the shipped manifest does not hash to the embedded digest',
      ManifestCheck.artifactSetMismatch =>
        'the loaded library belongs to another artifact set',
      ManifestCheck.upstreamCommitMismatch =>
        'the loaded library was built from another upstream commit',
    };
    final suffix = detail.isEmpty ? '' : ' ($detail)';
    return '$described: expected "$expected", found "$actual"$suffix';
  }
}

// --- added by DECISION-12 §6 ------------------------------------------------

/// An operation was attempted in a session state that does not accept it.
final class SessionStateError extends WalletCoreException {
  /// Creates an error for [attempted] while the session was [actual].
  const SessionStateError(this.actual, {this.attempted = 'operation'});

  /// The state the session was in.
  final SessionState actual;

  /// The operation that was attempted, by name.
  final String attempted;

  @override
  String get message =>
      '$attempted is not accepted while the session is ${actual.name}';
}

/// The bounded queue was full. The operation was not queued and did not run.
final class QueueFullError extends WalletCoreException {
  /// Creates an error for a queue bounded at [limit].
  const QueueFullError(this.limit);

  /// The queue bound: queued plus in-flight operations.
  final int limit;

  @override
  String get message =>
      'the session queue is full ($limit pending); the operation did not run';
}

/// The operation's deadline elapsed. Work already running in native code was not
/// aborted; its result was discarded and its temporaries released.
final class OperationTimeoutError extends WalletCoreException {
  /// Creates an error for [operation], whose deadline was [timeout].
  const OperationTimeoutError(this.operation, this.timeout);

  /// The operation that timed out, by name.
  final String operation;

  /// The deadline, measured from submission.
  final Duration timeout;

  @override
  String get message =>
      '$operation did not complete within ${timeout.inMilliseconds} ms of '
      'submission';
}

/// The operation was cancelled before it started. It never ran and no key was
/// derived for it.
final class OperationCancelledError extends WalletCoreException {
  /// Creates an error for the cancelled request [requestId].
  const OperationCancelledError(this.requestId);

  /// The session-scoped id of the request that was cancelled.
  final int requestId;

  @override
  String get message => 'request $requestId was cancelled before it started';
}
