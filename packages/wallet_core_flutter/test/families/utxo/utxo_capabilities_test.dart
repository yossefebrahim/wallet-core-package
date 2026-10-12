/// Holds the UTXO groups of `lib/src/capabilities.dart` to the facade they
/// describe: the coins they list are exactly the ones `UtxoTransactionRequest`
/// accepts, and every other coin is rejected. Pure Dart: no native library.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/src/capabilities.dart';
import 'package:wallet_core_flutter/src/signing/key_locator.dart'
    show issueKeyRef;
import 'package:wallet_core_flutter/wallet_core_flutter.dart';

UtxoTransactionRequest _request(Coin coin) => UtxoTransactionRequest(
  coin: coin,
  toAddress: 'bc1q2dsdlq3343vk29runkgv4yc292hmq53jedfjmp',
  amount: 5000,
  feeRatePerByte: 2,
  changeAddress: 'bc1qvrt7ukvhvmdny0a3j9k8l8jasx92lrqm30t2u2',
  inputs: [
    UtxoInput(
      outPoint: OutPoint(transactionId: '1' * 64, index: 0),
      amount: 10000,
      script: Uint8List.fromList([0x00, 0x14, ...List.filled(20, 7)]),
      addressStyle: AddressStyle.segwit,
      keyLocator: KeyLocator.imported(issueKeyRef(1)),
    ),
  ],
);

void main() {
  final utxoGroups = capabilityGroups.where(
    (g) => const {'p2wpkh', 'multi_input'}.contains(g.variant),
  );

  test('the UTXO groups are plan and sign, for the two vector variants, '
      'typed, for Bitcoin alone', () {
    expect(utxoGroups.map((g) => '${g.operation}/${g.variant}').toSet(), {
      'plan/p2wpkh',
      'plan/multi_input',
      'sign/p2wpkh',
      'sign/multi_input',
    });
    for (final group in utxoGroups) {
      expect(group.exposure, Exposure.typed);
      expect(group.coins, ['bitcoin'], reason: group.operation);
    }
  });

  test('a request is accepted for exactly the listed coins', () {
    final listed = {for (final g in utxoGroups) ...g.coins!};
    for (final coin in Coin.all) {
      if (listed.contains(coin.id)) {
        expect(() => _request(coin), returnsNormally, reason: coin.id);
      } else {
        expect(
          () => _request(coin),
          throwsA(
            anyOf(isA<InvalidInputError>(), isA<UnsupportedOperationError>()),
          ),
          reason: coin.id,
        );
      }
    }
  });

  test('every UTXO-family coin but Bitcoin is refused by name, not as a '
      'wrong coin', () {
    for (final coin in Coin.byFamily(ChainFamily.utxo)) {
      if (coin == Coin.bitcoin) continue;
      expect(
        () => _request(coin),
        throwsA(isA<UnsupportedOperationError>()),
        reason: coin.id,
      );
    }
  });
}
