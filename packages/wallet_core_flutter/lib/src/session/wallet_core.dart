/// [WalletCore], the session, and [OperationTimeouts]
/// (`docs/architecture/lifecycle.md` §1, DECISION-12 §3).
library;

import 'dart:typed_data';

import '../address/address_facade.dart';
import '../errors/errors.dart';
import '../lifecycle/session_state.dart';
import '../mnemonic/mnemonic_facade.dart';
import '../wallet/wallet.dart';
import 'session.dart';

/// A session: one loaded native library, one owning isolate, and the handles
/// that isolate holds.
///
/// A session is the unit of teardown. `close()` on a single wallet frees that
/// wallet; [shutdown] frees everything and ends the session. There is no
/// "lock" flag: locking an application is [shutdown], and unlocking is a new
/// [initialize] followed by re-importing from an encrypted keystore.
///
/// Every operation is asynchronous and accepted only while [state] is
/// [SessionState.ready]: in `initializing` and `closing` it fails with
/// [SessionStateError], after [shutdown] with [ClosedError], and after the
/// owning isolate ended with [WorkerTerminatedError]. Nothing is retried.
///
/// Signing — `signer` in the design sketch — is not part of this version.
abstract interface class WalletCore {
  /// Loads the native library in the session's owning isolate, verifies the
  /// build identity against the shipped manifest, runs a symbol-lookup health
  /// check, and returns only once the session is [SessionState.ready].
  ///
  /// Throws [NativeLoadError] when the library cannot be loaded, the build
  /// identity symbol is absent, or a symbol is missing, and
  /// [ManifestMismatchError] when the identity does not match the manifest.
  /// In either case no session is returned and nothing needs closing.
  ///
  /// [queueLimit] bounds queued plus in-flight operations, at least 1;
  /// submitting beyond it throws [QueueFullError] rather than queueing
  /// without bound. [timeouts] sets the per-operation deadlines.
  ///
  /// Takes no library path and reads no environment variable: where the
  /// library comes from is the packaging mechanism's business, never a value
  /// chosen at run time (threat model TM-13).
  static Future<WalletCore> initialize({
    int queueLimit = 32,
    OperationTimeouts timeouts = const OperationTimeouts(),
  }) => startSession(queueLimit: queueLimit, timeouts: timeouts);

  /// The current state. Synchronous and always safe to read.
  SessionState get state;

  /// State changes, as a broadcast stream, so an application can react to
  /// [SessionState.failed] without polling. Closes after
  /// [SessionState.closed].
  Stream<SessionState> get states;

  /// Creating and importing wallets.
  WalletFacade get wallets;

  /// Validating and parsing addresses.
  AddressFacade get addresses;

  /// Validating mnemonics and suggesting mnemonic words.
  MnemonicFacade get mnemonics;

  /// Runs [body] and closes every public resource created through its
  /// [SessionScope], in reverse order of creation, whether [body] returns or
  /// throws.
  ///
  /// When [body] throws, that error is what this throws; an error closing a
  /// resource does not replace it. When [body] returns and a close fails, the
  /// first close error is thrown after every resource has been closed.
  Future<T> scope<T>(Future<T> Function(SessionScope scope) body);

  /// Stops accepting work, rejects queued operations with
  /// [SessionStateError], lets the one in-flight operation finish, releases
  /// every handle, and ends the session.
  ///
  /// Idempotent: concurrent and repeated calls await the same completion.
  /// If the owning isolate does not acknowledge within
  /// [OperationTimeouts.shutdownGrace] it is forced down; the session still
  /// moves to [SessionState.closed].
  Future<void> shutdown();
}

/// Per-operation deadlines. A deadline starts when the operation is
/// *submitted*, so time spent queued counts against it.
///
/// A deadline does not abort work already running in native code — there is
/// no mechanism to do that. The operation runs to completion, its key
/// material and temporaries are released as usual, and its result is
/// discarded; the caller's future completes with [OperationTimeoutError].
///
/// There is deliberately **no** deadline for releasing a resource.
/// [Wallet.close] waits without one, because no bound on it could be
/// enforced (DECISION-12 §3.5). [shutdownGrace] is the only bound on
/// teardown, and the only recovery.
final class OperationTimeouts {
  /// Creates a set of deadlines; every one must be positive.
  const OperationTimeouts({
    this.initialize = const Duration(seconds: 30),
    this.walletOperation = const Duration(seconds: 20),
    this.derivation = const Duration(seconds: 5),
    this.signing = const Duration(seconds: 15),
    this.shutdownGrace = const Duration(seconds: 10),
  });

  /// [WalletCore.initialize].
  final Duration initialize;

  /// Creating, importing, and exporting the mnemonic of a wallet.
  final Duration walletOperation;

  /// Deriving an account, and the stateless address and mnemonic checks.
  final Duration derivation;

  /// Signing. No operation of this version uses it.
  final Duration signing;

  /// Bounds teardown as a whole. This one **does** expire: on expiry the
  /// owning isolate is forced down and the session moves to
  /// [SessionState.closed]. A forced stop does not wipe what that isolate
  /// owned.
  final Duration shutdownGrace;

  @override
  String toString() =>
      'OperationTimeouts(initialize: ${initialize.inMilliseconds} ms, '
      'walletOperation: ${walletOperation.inMilliseconds} ms, '
      'derivation: ${derivation.inMilliseconds} ms, '
      'signing: ${signing.inMilliseconds} ms, '
      'shutdownGrace: ${shutdownGrace.inMilliseconds} ms)';
}

/// A scope that closes what was created inside it; see [WalletCore.scope].
///
/// Every member throws [ClosedError] once the scope's body has returned or
/// thrown.
abstract interface class SessionScope {
  /// [WalletFacade.create], closed when the scope ends.
  Future<Wallet> createWallet({int strength = 128, String passphrase = ''});

  /// [WalletFacade.importMnemonic], closed when the scope ends.
  Future<Wallet> importMnemonic(String mnemonic, {String passphrase = ''});

  /// [WalletFacade.importEntropy], closed when the scope ends.
  Future<Wallet> importEntropy(Uint8List entropy, {String passphrase = ''});
}
