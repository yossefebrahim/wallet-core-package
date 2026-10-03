/// [SessionSigner]: the [LocalSigner] behind `WalletCore.signer`.
/// **Internal**: the public type is [LocalSigner].
library;

import '../coin/coin.dart';
import '../errors/errors.dart';
import '../requests/requests.dart';
import '../session/session.dart';
import '../wallet/wallet.dart';
import '../worker/protocol.dart';
import 'key_locator.dart';
import 'sign_result.dart';
import 'signer.dart';

/// Signs through the session's owning isolate.
///
/// Holds the session and nothing else: no key, no handle, no result of any
/// call it made. Each call sends one [Sign] — the request and the names of
/// the keys — and the owning isolate derives the key, signs, releases the
/// key, and only then replies (DECISION-12 §3.9).
///
/// Before submitting it runs only the checks that need no native call and
/// that it can answer exactly: the session is `ready`, and each wallet
/// reference belongs to this session and names an open wallet. The owning
/// isolate repeats every check itself and relies on none of these.
final class SessionSigner implements LocalSigner {
  /// Creates the signer of [_session].
  SessionSigner(this._session);

  final WalletCoreSession _session;

  @override
  Future<SignResult> sign(
    TransactionRequest request,
    Set<KeyLocator> keys,
  ) async {
    _session.checkReady('sign');
    // A snapshot: the caller may change its set after this call returns.
    final locators = Set<KeyLocator>.of(keys);
    final specs = <LocatorSpec>{
      for (final locator in locators) _specOf(locator),
    };
    return _session.submit(
      (id) => Sign(id, request: request, keys: specs),
      timeout: _session.timeouts.signing,
      parse: (reply) => switch (reply) {
        Signed(:final result) => withUsedKeys(result, locators),
        _ => throw StateError('unexpected reply ${reply.runtimeType}'),
      },
    );
  }

  @override
  Future<SignResult> signWithKey(TransactionRequest request, KeyLocator key) =>
      sign(request, <KeyLocator>{key});

  /// Not at this version: no [MessageRequest] exists yet. EVM message signing
  /// is T2.7's.
  @override
  Future<SignResult> signMessage(
    MessageRequest request,
    Set<KeyLocator> keys,
  ) async => throw UnsupportedOperationError(request.coin, 'signMessage');

  LocatorSpec _specOf(KeyLocator locator) => switch (locator) {
    HdKeyLocator(
      :final wallet,
      :final coin,
      :final derivationPath,
      :final role,
    ) =>
      _hdSpec(wallet, coin, derivationPath, role),
    ImportedKeyLocator(:final key, :final role) => ImportedLocatorSpec(
      keyRef: keyRefNumber(key),
      role: role,
    ),
    ExternalKeyLocator(:final deviceId, :final role) => ExternalLocatorSpec(
      deviceId: deviceId,
      role: role,
    ),
  };

  HdLocatorSpec _hdSpec(
    WalletRef wallet,
    Coin coin,
    String derivationPath,
    KeyRole? role,
  ) {
    resolveWalletRef(_session, wallet);
    final spec = walletRefSpec(wallet);
    return HdLocatorSpec(
      sessionToken: spec.sessionToken,
      walletRef: spec.walletRef,
      coin: coin,
      derivationPath: derivationPath,
      role: role,
    );
  }
}
