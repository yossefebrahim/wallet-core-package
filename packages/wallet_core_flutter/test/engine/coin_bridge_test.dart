// The facade → foreign-function enum bridge, checked without loading the
// library: the generated `TWCoinType` and `TWDerivation` enums are plain Dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/advanced.dart';
import 'package:wallet_core_flutter/src/coin/coin.dart';
import 'package:wallet_core_flutter/src/engine/coin_bridge.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';

void main() {
  test('every coin maps to the TWCoinType with its coinId, one to one', () {
    expect(TWCoinType.values, hasLength(CoinType.values.length));
    final mapped = <TWCoinType>{};
    for (final coin in Coin.all) {
      final type = twCoinTypeOf(coin);
      expect(type.value, registryCoinTypeOf(coin).coinId, reason: coin.id);
      mapped.add(type);
    }
    expect(mapped, hasLength(TWCoinType.values.length));
  });

  test('every named registry derivation has its TWDerivation variant, and '
      'every variant but Default and Custom is reached', () {
    final reached = <TWDerivation>{};
    for (final type in CoinType.values) {
      final twType = TWCoinType.fromValue(type.coinId);
      for (final derivation in coinInfo[type]!.derivation) {
        final name = derivation.name;
        if (name == null) continue;
        final wanted = twDerivationNameFor(twType, name);
        final match = TWDerivation.values.where((v) => v.name == wanted);
        expect(match, hasLength(1), reason: wanted);
        reached.add(match.single);
      }
    }
    expect(
      reached,
      TWDerivation.values.toSet()..removeAll(const [
        TWDerivation.TWDerivationDefault,
        TWDerivation.TWDerivationCustom,
      ]),
    );
  });

  test('(coin, network, style) resolves to the expected variant', () {
    TWDerivation of(Coin coin, Network network, AddressStyle style) =>
        twDerivationOf(coin, resolveDerivation(coin, network, style));

    expect(
      of(Coin.ethereum, Network.mainnet, AddressStyle.standard),
      TWDerivation.TWDerivationDefault,
    );
    expect(
      of(Coin.bitcoin, Network.mainnet, AddressStyle.standard),
      TWDerivation.TWDerivationDefault,
    );
    expect(
      of(Coin.bitcoin, Network.mainnet, AddressStyle.legacy),
      TWDerivation.TWDerivationBitcoinLegacy,
    );
    expect(
      of(Coin.bitcoin, Network.mainnet, AddressStyle.taproot),
      TWDerivation.TWDerivationBitcoinTaproot,
    );
    expect(
      of(Coin.bitcoin, Network.testnet, AddressStyle.standard),
      TWDerivation.TWDerivationBitcoinTestnet,
    );
    expect(
      of(Coin.byId('pactus'), Network.testnet, AddressStyle.standard),
      TWDerivation.TWDerivationPactusTestnet,
    );
  });
}
