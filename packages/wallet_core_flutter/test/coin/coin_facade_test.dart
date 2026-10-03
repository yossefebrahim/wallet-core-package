// The coin facade of DECISION-11, against the generated registry and the
// committed copy of the pinned registry.json. Pure Dart: no native library.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/src/coin/aliases.dart';
import 'package:wallet_core_flutter/src/coin/coin.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';
import 'package:wallet_core_flutter_bindings/registry.dart';

import '../support/host_library.dart';

/// The pinned registry.json, upstream commit
/// d692ac27749d0c615e17c751b70ab4f0aa75c59b (tag 4.8.0), as committed under
/// the DECISION-11 evidence directory.
List<Map<String, Object?>> _pinnedRegistry() {
  final root = repositoryRoot()!;
  final file = File(
    '${root.path}/docs/decisions/evidence/prefetch-2026-09-07/upstream-src/'
    'registry.json',
  );
  return (jsonDecode(file.readAsStringSync()) as List<Object?>)
      .cast<Map<String, Object?>>();
}

void main() {
  group('lookup', () {
    test('every one of the 167 registry coins resolves by id', () {
      expect(CoinType.values, hasLength(167));
      expect(Coin.all, hasLength(167));
      for (final type in CoinType.values) {
        final coin = Coin.find(registryIdOf(type));
        expect(coin, isNotNull, reason: type.name);
        expect(registryCoinTypeOf(coin!), type);
      }
    });

    test('ids are unique and Coin.all is sorted by id', () {
      final ids = Coin.all.map((coin) => coin.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      expect(ids, [...ids]..sort());
    });

    test('every id of the pinned registry.json round-trips, with its '
        'coinId, name, symbol and decimals', () {
      final registry = _pinnedRegistry();
      expect(registry, hasLength(167));
      for (final entry in registry) {
        final id = entry['id']! as String;
        final coin = Coin.byId(id);
        expect(coin.id, id);
        expect(registryCoinTypeOf(coin).coinId, entry['coinId'], reason: id);
        expect(coin.name, entry['name'], reason: id);
        expect(coin.symbol, entry['symbol'], reason: id);
        expect(coin.decimals, entry['decimals'], reason: id);
        expect(coin.isDeprecated, entry['deprecated'] ?? false, reason: id);
      }
    });

    test('an id that only differs from the registry by case does not '
        'resolve', () {
      expect(Coin.find('Nebl'), isNotNull);
      expect(Coin.find('nebl'), isNull);
      expect(Coin.find('Ethereum'), isNull);
    });

    test('an unknown id is null from find and a typed error from byId', () {
      expect(Coin.find('no-such-chain'), isNull);
      expect(
        () => Coin.byId('no-such-chain'),
        throwsA(
          isA<UnknownCoinError>()
              .having((e) => e.coinId, 'coinId', 'no-such-chain')
              .having((e) => e.inputName, 'inputName', 'coin'),
        ),
      );
      expect(() => Coin.byId(''), throwsA(isA<InvalidInputError>()));
    });

    test('named constants are the coins lookup returns', () {
      expect(identical(Coin.byId('bitcoin'), Coin.bitcoin), isTrue);
      expect(identical(Coin.byId('ethereum'), Coin.ethereum), isTrue);
      expect(identical(Coin.byId('solana'), Coin.solana), isTrue);
    });

    test('coins are equal by id', () {
      expect(Coin.byId('ethereum'), Coin.ethereum);
      expect(Coin.byId('ethereum').hashCode, Coin.ethereum.hashCode);
      expect(Coin.ethereum, isNot(Coin.byId('base')));
      expect(Coin.ethereum.toString(), 'Coin(ethereum)');
    });
  });

  group('metadata', () {
    test('family follows the registry blockchain', () {
      expect(Coin.ethereum.family, ChainFamily.evm);
      expect(Coin.byId('base').family, ChainFamily.evm);
      expect(Coin.bitcoin.family, ChainFamily.utxo);
      expect(Coin.byId('litecoin').family, ChainFamily.utxo);
      expect(Coin.solana.family, ChainFamily.solana);
      expect(Coin.byId('cosmos').family, ChainFamily.other);
      expect(Coin.byFamily(ChainFamily.evm), hasLength(60));
      expect(
        ChainFamily.evm.hasRequestBuilders,
        isTrue,
        reason: 'EvmTransactionRequest exists',
      );
      expect(
        ChainFamily.utxo.hasRequestBuilders ||
            ChainFamily.solana.hasRequestBuilders ||
            ChainFamily.other.hasRequestBuilders,
        isFalse,
        reason: 'no other request builder exists at this version',
      );
    });

    test('EVM chain ids are integers; other chain ids are tags', () {
      expect(Coin.ethereum.evmChainId, 1);
      expect(Coin.byId('base').evmChainId, 8453);
      expect(Coin.ethereum.chainIdTag, isNull);
      expect(Coin.byId('cosmos').chainIdTag, 'cosmoshub-4');
      expect(Coin.byId('cosmos').evmChainId, isNull);
      expect(Coin.bitcoin.evmChainId, isNull);
      expect(Coin.bitcoin.chainIdTag, isNull);
      expect(Coin.all.where((c) => c.evmChainId != null), hasLength(60));
      expect(Coin.all.where((c) => c.chainIdTag != null), hasLength(39));
    });

    test('upstream-deprecated coins resolve, usable, and say so', () {
      for (final id in ['kin', 'bsc']) {
        final coin = Coin.byId(id);
        expect(coin.isDeprecated, isTrue);
        expect(coin.status, CoinStatus.deprecatedUpstream);
        expect(coin.defaultDerivationPath(), isNotEmpty);
      }
      expect(
        Coin.all.where((c) => c.status == CoinStatus.deprecatedUpstream),
        hasLength(2),
      );
      expect(Coin.ethereum.status, CoinStatus.active);
    });

    test('explorer URLs are formatted from the registry template', () {
      expect(
        Coin.bitcoin.explorerTransactionUrl('abc'),
        'https://mempool.space/tx/abc',
      );
    });
  });

  group('networks and address styles', () {
    test('testnet exists for exactly bitcoin and pactus', () {
      final withTestnet = Coin.all
          .where((coin) => coin.networks.contains(Network.testnet))
          .map((coin) => coin.id)
          .toList();
      expect(withTestnet, ['bitcoin', 'pactus']);
      for (final coin in Coin.all) {
        expect(coin.networks, contains(Network.mainnet));
      }
      expect(Coin.ethereum.networks, {Network.mainnet});
    });

    test('every coin with a testnet has a testnet address prefix', () {
      final withTestnet = Coin.all
          .where((coin) => coin.networks.contains(Network.testnet))
          .map((coin) => coin.id)
          .toSet();
      expect(testnetBech32Hrp.keys.toSet(), withTestnet);
    });

    test('a network the coin lacks is rejected, never mapped to mainnet', () {
      expect(
        () => Coin.ethereum.defaultDerivationPath(network: Network.testnet),
        throwsA(
          isA<UnsupportedOperationError>()
              .having((e) => e.coin, 'coin', Coin.ethereum)
              .having((e) => e.capability, 'capability', 'network:testnet'),
        ),
      );
    });

    test('bitcoin resolves each of its four registry derivations', () {
      expect(Coin.bitcoin.defaultDerivationPath(), "m/84'/0'/0'/0/0");
      expect(
        Coin.bitcoin.defaultDerivationPath(style: AddressStyle.segwit),
        "m/84'/0'/0'/0/0",
      );
      expect(
        Coin.bitcoin.defaultDerivationPath(style: AddressStyle.legacy),
        "m/44'/0'/0'/0/0",
      );
      expect(
        Coin.bitcoin.defaultDerivationPath(style: AddressStyle.taproot),
        "m/86'/0'/0'/0/0",
      );
      expect(
        Coin.bitcoin.defaultDerivationPath(network: Network.testnet),
        "m/84'/1'/0'/0/0",
      );
      expect(Coin.bitcoin.addressStyles, {
        AddressStyle.standard,
        AddressStyle.legacy,
        AddressStyle.segwit,
        AddressStyle.taproot,
      });
    });

    test('a combination upstream has no derivation for is rejected', () {
      expect(
        () => Coin.bitcoin.defaultDerivationPath(
          network: Network.testnet,
          style: AddressStyle.taproot,
        ),
        throwsA(
          isA<UnsupportedOperationError>().having(
            (e) => e.capability,
            'capability',
            'addressStyle:taproot',
          ),
        ),
      );
      expect(
        () => Coin.ethereum.defaultDerivationPath(style: AddressStyle.legacy),
        throwsA(
          isA<UnsupportedOperationError>().having(
            (e) => e.capability,
            'capability',
            'addressStyle:legacy',
          ),
        ),
      );
      expect(Coin.ethereum.addressStyles, {AddressStyle.standard});
      expect(Coin.byId('litecoin').addressStyles, {
        AddressStyle.standard,
        AddressStyle.legacy,
      });
    });

    test('values are equal by id', () {
      expect(Network.mainnet, isNot(Network.testnet));
      expect(Network.mainnet.id, 'mainnet');
      expect(AddressStyle.taproot.id, 'taproot');
      expect(ChainFamily.other.id, 'other');
    });
  });

  group('aliases and removals (DECISION-11 §4.3)', () {
    test('both tables are empty at the pinned tag', () {
      expect(renamedCoinIds, isEmpty);
      expect(removedCoins, isEmpty);
    });

    test('a renamed id resolves to the same chain with status renamed', () {
      final coin = resolveCoinId(
        'old-ethereum',
        renamed: const {'old-ethereum': 'ethereum'},
        removed: const {},
      )!;
      expect(coin.id, 'old-ethereum');
      expect(coin.status, CoinStatus.renamed);
      expect(registryCoinTypeOf(coin), CoinType.ethereum);
      expect(
        coin.defaultDerivationPath(),
        Coin.ethereum.defaultDerivationPath(),
      );
      expect(Coin.all.map((c) => c.id), isNot(contains('old-ethereum')));
    });

    test('a removed id resolves, and every operation on it is rejected', () {
      final coin = resolveCoinId(
        'gone',
        renamed: const {},
        removed: const {
          'gone': RemovedCoinRecord(
            name: 'Gone',
            symbol: 'GONE',
            decimals: 6,
            familyId: 'other',
          ),
        },
      )!;
      expect(coin.status, CoinStatus.removedUpstream);
      expect(coin.name, 'Gone');
      expect(coin.family, ChainFamily.other);
      expect(
        coin.defaultDerivationPath,
        throwsA(
          isA<UnsupportedOperationError>().having(
            (e) => e.capability,
            'capability',
            'coin:removedUpstream',
          ),
        ),
      );
      expect(
        () => Address.looksWellFormed('x', coin: coin),
        throwsA(isA<UnsupportedOperationError>()),
      );
    });
  });
}
