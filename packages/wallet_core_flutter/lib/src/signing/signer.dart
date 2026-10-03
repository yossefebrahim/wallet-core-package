/// [Signer] and [LocalSigner]: the interfaces a caller signs through
/// (`docs/architecture/signing.md` §1, DECISION-13 §4.1).
///
/// The session's [LocalSigner] is `WalletCore.signer`. `plan` — UTXO
/// planning in the design sketch — is not declared at this version: there is
/// no UTXO request to plan yet.
library;

import '../errors/errors.dart';
import '../requests/requests.dart';
import 'key_locator.dart';
import 'sign_result.dart';

/// Signs requests with keys named by [KeyLocator]s.
///
/// The 1.0 implementation is [LocalSigner], which resolves keys inside the
/// session's owning isolate. The interface is shaped so that a future signer
/// backed by a hardware device or a remote service implements it without any
/// change to the request types.
abstract interface class Signer {
  /// Signs [request] with the keys named by [keys].
  ///
  /// [keys] is a set because order is meaningless — upstream matches keys to
  /// transaction inputs by script, not by position — and because a duplicate
  /// locator should be harmless. A single-key chain takes one locator; a spend
  /// from several derivation paths takes one per path.
  ///
  /// Resolution happens before any native call and before any key is derived.
  /// Throws [KeyResolutionError] when a role the family needs has no locator,
  /// when a locator no role consumes was supplied, or when a locator names a
  /// reference from another session; [SigningError] when upstream reports a
  /// signing failure.
  ///
  /// The result's `usedKeys` is the set of locators given, duplicates
  /// folded.
  Future<SignResult> sign(TransactionRequest request, Set<KeyLocator> keys);

  /// Convenience for the single-key case. Exactly equivalent to
  /// `sign(request, {key})`; it is sugar over the set, not an alternative
  /// path.
  Future<SignResult> signWithKey(TransactionRequest request, KeyLocator key);

  /// Signs a message request (personal-style or typed structured data).
  ///
  /// No [MessageRequest] exists at this version, so there is nothing to call
  /// this with; the session's signer fails it with
  /// [UnsupportedOperationError].
  Future<SignResult> signMessage(MessageRequest request, Set<KeyLocator> keys);
}

/// The 1.0 signer: keys live in the session's owning isolate, are derived for
/// a single operation, and are released before that operation's result is
/// returned.
///
/// Obtained from `WalletCore.signer`. Every failure is a typed
/// [WalletCoreException]: [KeyResolutionError] and [UnsupportedOperationError]
/// (`'external-signer'`) from resolving the locators, [InvalidInputError]
/// for a recipient upstream rejects (`inputName: 'to'`), a malformed path
/// (`'derivationPath'`), or a locator for another coin (`'keys'`),
/// [ClosedError] for a closed wallet, [SigningError] from upstream, and the
/// session's own errors — [QueueFullError], [OperationTimeoutError] after
/// `OperationTimeouts.signing`, [SessionStateError], [ClosedError],
/// [WorkerTerminatedError]. Nothing is retried.
abstract interface class LocalSigner implements Signer {}
