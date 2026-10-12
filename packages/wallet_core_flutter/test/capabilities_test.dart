// Holds `lib/src/capabilities.dart` — the Exposed column of the capability
// matrix — to the code it describes, and keeps `docs/capability_exposed.json`,
// the snapshot `tools/matrix` reads, byte-identical to it. Pure Dart: no native
// library.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/src/capabilities.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';

import 'support/host_library.dart';

/// `flutter test --dart-define=WCF_UPDATE_CAPABILITY_SNAPSHOT=true` rewrites
/// the snapshot instead of comparing against it.
const String _updateVariable = 'WCF_UPDATE_CAPABILITY_SNAPSHOT';
const bool _update = bool.fromEnvironment(_updateVariable);

const String _address = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8';

/// The three EVM request builders, by the matrix variant each one is.
final Map<String, EvmTransactionRequest Function(Coin)> _builders = {
  'eip1559': (coin) => EvmTransactionRequest.transfer(
    coin: coin,
    chainId: 1,
    nonce: BigInt.zero,
    to: _address,
    valueWei: BigInt.one,
    maxFeePerGas: BigInt.two,
    maxPriorityFeePerGas: BigInt.one,
    gasLimit: BigInt.from(21000),
  ),
  'legacy': (coin) => EvmTransactionRequest.legacyTransfer(
    coin: coin,
    chainId: 1,
    nonce: BigInt.zero,
    to: _address,
    valueWei: BigInt.one,
    gasPrice: BigInt.two,
    gasLimit: BigInt.from(21000),
  ),
  'contract_call': (coin) => EvmTransactionRequest.contractCall(
    coin: coin,
    chainId: 1,
    nonce: BigInt.zero,
    to: _address,
    data: Uint8List.fromList(const [1, 2, 3]),
    maxFeePerGas: BigInt.two,
    maxPriorityFeePerGas: BigInt.one,
    gasLimit: BigInt.from(100000),
  ),
};

/// The EVM message request builders, by the matrix variant each one is.
final Map<String, EvmMessageRequest Function(Coin)> _messageBuilders = {
  'personal': (coin) =>
      EvmMessageRequest.personal(Uint8List.fromList(const [0x46]), coin: coin),
  'eip712': (coin) => EvmMessageRequest.typedData('{}', coin: coin),
};

/// The snapshot document for [groups]: sorted, two-space indent, trailing
/// newline. `coins` is the string `"all"` for a group that covers the whole
/// pinned registry.
String snapshotOf(List<CapabilityGroup> groups) {
  final sorted = [...groups]
    ..sort((a, b) {
      final byOperation = a.operation.compareTo(b.operation);
      return byOperation != 0 ? byOperation : a.variant.compareTo(b.variant);
    });
  final document = <String, Object?>{
    'schema': 1,
    'groups': [
      for (final group in sorted)
        {
          'operation': group.operation,
          'variant': group.variant,
          'exposure': group.exposure.name,
          'coins': group.coins == null ? 'all' : ([...group.coins!]..sort()),
        },
    ],
  };
  return '${const JsonEncoder.withIndent('  ').convert(document)}\n';
}

void main() {
  final evmCoins = Coin.byFamily(ChainFamily.evm).map((coin) => coin.id);

  group('the registry matches the facade', () {
    test('every coin the facade accepts for EVM signing appears, and no other '
        'coin does', () {
      expect(evmCoinIds.toSet(), hasLength(evmCoinIds.length));
      expect(evmCoinIds, [...evmCoinIds]..sort());
      expect(evmCoinIds, evmCoins.toList());
    });

    test('no entry names a coin the facade rejects', () {
      for (final group in capabilityGroups) {
        for (final id in group.coins ?? const <String>[]) {
          final coin = Coin.find(id);
          expect(coin, isNotNull, reason: '$id does not resolve');
          expect(coin!.status, isNot(CoinStatus.removedUpstream), reason: id);
        }
      }
    });

    test('operations and variants are the matrix vocabulary, once each', () {
      final keys = <String>{};
      for (final group in capabilityGroups) {
        expect(const {
          'address',
          'sign',
          'sign_message',
        }, contains(group.operation));
        expect(
          keys.add('${group.operation}/${group.variant}'),
          isTrue,
          reason: 'duplicate ${group.operation}/${group.variant}',
        );
      }
      expect(
        capabilityGroups
            .where((g) => g.operation == 'sign')
            .map((g) => g.variant)
            .toSet(),
        _builders.keys.toSet(),
      );
    });

    test('every sign variant has a builder the listed coins accept and every '
        'other coin rejects', () {
      for (final group in capabilityGroups.where(
        (g) => g.operation == 'sign',
      )) {
        final build = _builders[group.variant]!;
        for (final coin in Coin.all) {
          if (group.coins!.contains(coin.id)) {
            expect(
              () => build(coin),
              returnsNormally,
              reason: '${coin.id} ${group.variant}',
            );
          } else {
            expect(
              () => build(coin),
              throwsA(isA<InvalidInputError>()),
              reason: '${coin.id} ${group.variant}',
            );
          }
        }
      }
    });

    test('every sign_message variant has a builder the listed coins accept and '
        'every other coin rejects', () {
      final groups = capabilityGroups.where(
        (g) => g.operation == 'sign_message',
      );
      expect(
        groups.map((g) => g.variant).toSet(),
        _messageBuilders.keys.toSet(),
      );
      for (final group in groups) {
        final build = _messageBuilders[group.variant]!;
        for (final coin in Coin.all) {
          if (group.coins!.contains(coin.id)) {
            expect(
              () => build(coin),
              returnsNormally,
              reason: '${coin.id} ${group.variant}',
            );
          } else {
            expect(
              () => build(coin),
              throwsA(isA<InvalidInputError>()),
              reason: '${coin.id} ${group.variant}',
            );
          }
        }
      }
    });

    test('address derivation covers every coin of the pinned registry', () {
      final address = capabilityGroups.singleWhere(
        (g) => g.operation == 'address',
      );
      expect(address.coins, isNull);
      expect(address.variant, 'n/a');
      for (final coin in Coin.all) {
        expect(coin.status, isNot(CoinStatus.removedUpstream), reason: coin.id);
        expect(coin.defaultDerivationPath, returnsNormally, reason: coin.id);
      }
    });
  });

  group('docs/capability_exposed.json', () {
    test('is the snapshot of capabilityGroups', () {
      final root = repositoryRoot();
      if (root == null) {
        markTestSkipped('repository root not found from ${Directory.current}');
        return;
      }
      final file = File('${root.path}/docs/capability_exposed.json');
      final expected = snapshotOf(capabilityGroups);
      if (_update) {
        file.writeAsStringSync(expected);
        return;
      }
      expect(
        file.existsSync(),
        isTrue,
        reason: 'run with --dart-define=$_updateVariable=true to write it',
      );
      expect(
        file.readAsStringSync(),
        expected,
        reason: 'stale snapshot; run with --dart-define=$_updateVariable=true',
      );
    });
  });
}
