/// [Account]: a derived account, as a plain descriptor
/// (`docs/architecture/public_model.md` §4, DECISION-11 §4.6).
library;

import 'dart:typed_data';

import '../address/address.dart';
import '../coin/coin.dart';
import '../coin/network.dart';

/// A derived account: a plain descriptor.
///
/// An `Account` owns no native resource, holds no key, and grants no capability.
/// It is immutable, safe to persist, safe to log (it contains no secret), and
/// crosses isolate boundaries by copy. Signing with the key behind an account
/// requires naming that key separately — see `KeyLocator` in
/// `docs/architecture/signing.md`.
///
/// Two accounts are equal when every field is, the public key compared byte by
/// byte.
final class Account {
  /// Creates a descriptor. [publicKey] is held as given, not copied; the SDK
  /// hands out accounts whose public key is an unmodifiable copy.
  const Account({
    required this.coin,
    required this.network,
    required this.addressStyle,
    required this.derivationPath,
    required this.address,
    required this.publicKey,
  });

  /// The coin the account was derived for.
  final Coin coin;

  /// The network the account was derived for.
  final Network network;

  /// The address style the account was derived with.
  final AddressStyle addressStyle;

  /// The full BIP-32 path this account was derived at.
  final String derivationPath;

  /// The account's address.
  final Address address;

  /// The account's public key bytes. Never a private key: this SDK's default
  /// surface returns no private key material at all.
  final Uint8List publicKey;

  @override
  bool operator ==(Object other) {
    if (other is! Account ||
        other.coin != coin ||
        other.network != network ||
        other.addressStyle != addressStyle ||
        other.derivationPath != derivationPath ||
        other.address != address ||
        other.publicKey.length != publicKey.length) {
      return false;
    }
    for (var i = 0; i < publicKey.length; i++) {
      if (other.publicKey[i] != publicKey[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    coin,
    network,
    addressStyle,
    derivationPath,
    address,
    Object.hashAll(publicKey),
  );

  /// Coin, network, style, path, and address. All public data.
  @override
  String toString() =>
      'Account(${coin.id}, ${network.id}, ${addressStyle.id}, '
      '$derivationPath, ${address.value})';
}
