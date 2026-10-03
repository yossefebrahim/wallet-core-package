/// The step from the coin facade to the generated foreign-function enums.
/// **Internal**: never exported.
///
/// `Coin → CoinType` is the facade's own table lookup (`registryCoinTypeOf`);
/// `CoinType → TWCoinType` is one enum lookup, because the generated
/// foreign-function enum's value *is* the registry's `coinId`
/// (DECISION-11 §4.2). `(Coin, Network, AddressStyle) → TWDerivation` resolves
/// the registry derivation in pure Dart first, so an unsupported combination
/// fails before any native call.
library;

import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart';

import '../coin/coin.dart';
import '../errors/errors.dart';

/// The foreign-function coin type behind [coin].
///
/// Throws `UnsupportedOperationError` for a coin upstream removed.
TWCoinType twCoinTypeOf(Coin coin) =>
    TWCoinType.fromValue(registryCoinTypeOf(coin).coinId);

/// The foreign-function derivation value for a [derivation] of [coin].
///
/// The coin's default derivation is `TWDerivationDefault`. A named one is the
/// variant upstream generates from the same registry entry,
/// `TWDerivation<CoinType><Name>` — `bitcoin`'s `testnet` is
/// `TWDerivationBitcoinTestnet`, `smartchain`'s `stable_account` is
/// `TWDerivationSmartChainStableAccount`. A test checks that every named
/// derivation in the pinned registry has its variant.
///
/// Throws [UnsupportedOperationError] (`'derivation:<name>'`) when the
/// headers have no such variant.
TWDerivation twDerivationOf(Coin coin, ResolvedDerivation derivation) {
  if (derivation.isDefault) return TWDerivation.TWDerivationDefault;
  final name = derivation.name;
  if (name != null) {
    final wanted = twDerivationNameFor(twCoinTypeOf(coin), name);
    for (final value in TWDerivation.values) {
      if (value.name == wanted) return value;
    }
  }
  throw UnsupportedOperationError(coin, 'derivation:${name ?? 'unnamed'}');
}

/// The name upstream gives the derivation variant [registryName] of [type].
String twDerivationNameFor(TWCoinType type, String registryName) {
  const prefix = 'TWCoinType';
  final coinPart = type.name.startsWith(prefix)
      ? type.name.substring(prefix.length)
      : type.name;
  final namePart = registryName
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join();
  return 'TWDerivation$coinPart$namePart';
}
