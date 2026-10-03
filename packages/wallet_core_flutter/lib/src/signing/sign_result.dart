/// [SignResult]: what a signer produced, sealed and per family
/// (`docs/architecture/signing.md` §4, DECISION-13 §4.6).
///
/// A result is not key-bearing: a signed transaction carries signatures and
/// public data, never the private key that produced them.
library;

import 'dart:typed_data';

import '../coin/coin.dart';
import 'key_locator.dart';

/// What a signer produced. Sealed and per-family, because upstream's outputs
/// differ by chain in both shape and type.
///
/// There is deliberately no common `encoded` member: it could only be typed
/// `Object`, which would push a cast onto every caller. Switch exhaustively
/// instead.
sealed class SignResult {
  /// The coin the transaction was signed for.
  Coin get coin;

  /// The locators actually consumed to produce this result. Lets a caller, a
  /// test, or an audit log assert exactly which keys signed, without any key
  /// material being exposed.
  ///
  /// **Retaining these retains the wallets they name.** A `KeyLocator.hdPath`
  /// holds its `WalletRef`, and a `WalletRef` keeps its `Wallet` proxy
  /// reachable, so a result kept — in an audit log, say — keeps the proxy's
  /// finalizer from ever releasing the wallet's native handle (its seed)
  /// until the wallet is closed or the session shut down. Close wallets
  /// explicitly, or record `toString()` of a locator rather than the
  /// locator itself.
  Set<KeyLocator> get usedKeys;
}

/// The result of signing an EVM transaction.
///
/// Every byte list is the result's own copy, exposed as a read-only view.
final class EvmSignResult implements SignResult {
  /// Creates a result, copying every list.
  EvmSignResult({
    required this.coin,
    required Uint8List encoded,
    required Uint8List v,
    required Uint8List r,
    required Uint8List s,
    Uint8List? preHash,
    required Set<KeyLocator> usedKeys,
  }) : _encoded = Uint8List.fromList(encoded),
       _v = Uint8List.fromList(v),
       _r = Uint8List.fromList(r),
       _s = Uint8List.fromList(s),
       _preHash = preHash == null ? null : Uint8List.fromList(preHash),
       usedKeys = Set<KeyLocator>.unmodifiable(usedKeys);

  @override
  final Coin coin;

  @override
  final Set<KeyLocator> usedKeys;

  final Uint8List _encoded;
  final Uint8List _v;
  final Uint8List _r;
  final Uint8List _s;
  final Uint8List? _preHash;

  /// The signed, encoded transaction, ready to broadcast.
  Uint8List get encoded => _encoded.asUnmodifiableView();

  /// The signature's `v` component, big-endian, as upstream returns it.
  Uint8List get v => _v.asUnmodifiableView();

  /// The signature's `r` component, big-endian.
  Uint8List get r => _r.asUnmodifiableView();

  /// The signature's `s` component, big-endian.
  Uint8List get s => _s.asUnmodifiableView();

  /// The pre-hash upstream reports, when it reports one.
  Uint8List? get preHash => _preHash?.asUnmodifiableView();

  /// The coin, the encoded length, and how many keys signed. The bytes are
  /// public, but a log line has no use for them.
  @override
  String toString() =>
      'EvmSignResult(${coin.id}, encoded: ${_encoded.length} bytes, '
      'usedKeys: ${usedKeys.length})';
}

/// [result] with [usedKeys] in place of its own. **Internal**; never
/// exported.
///
/// The session's half of the `Signed` reply: the executor cannot name the
/// caller's locators — they hold session-side objects that do not cross an
/// isolate — so the session puts them back on the result it returns.
SignResult withUsedKeys(SignResult result, Set<KeyLocator> usedKeys) =>
    switch (result) {
      EvmSignResult() => EvmSignResult(
        coin: result.coin,
        encoded: result._encoded,
        v: result._v,
        r: result._r,
        s: result._s,
        preHash: result._preHash,
        usedKeys: usedKeys,
      ),
    };
