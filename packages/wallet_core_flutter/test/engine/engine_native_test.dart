/// The engine against the real host library: wallet creation and import,
/// mnemonic export, account derivation against the Ethereum vectors, address
/// and mnemonic validation, the disposal contract, and leak accounting.
///
/// Skips when the library is absent; `WCF_NATIVE_REQUIRED=1` turns that into
/// a failure (see `../support/host_library.dart`).
@Tags(['native'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/advanced.dart';
import 'package:wallet_core_flutter/src/coin/coin.dart' show testnetBech32Hrp;
import 'package:wallet_core_flutter/src/engine/engine.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';
import 'package:wcf_tool_vectors/inventory.dart';

import '../support/fixtures.dart';
import '../support/host_library.dart';

Matcher _invalid(String inputName) => throwsA(
  isA<InvalidInputError>().having((e) => e.inputName, 'inputName', inputName),
);

String _hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Which input each `invalid_input` vector's `expected.error` names.
const Map<String, String> _inputNameForVectorError = <String, String>{
  'invalid_mnemonic': 'mnemonic',
  'invalid_address': 'address',
  'invalid_derivation_path': 'derivationPath',
};

void main() {
  final skip = hostLibrarySkipReason();

  group('WalletEngine against the host library', skip: skip, () {
    late WalletCoreBindings bindings;
    late Inventory inventory;

    setUpAll(() {
      bindings = openHostBindings();
      inventory = loadInventory();
    });

    NativeContext newContext({ResourceObserver? observer}) => NativeContext(
      bindings,
      observer: observer ?? const NoopResourceObserver(),
    );

    group('wallet creation', () {
      test('strength 128 gives 12 words and 256 gives 24', () {
        final engine = WalletEngine(newContext());
        for (final (strength, words) in [(128, 12), (256, 24)]) {
          final wallet = engine.createWallet(strength: strength);
          try {
            final mnemonic = engine.exportMnemonic(wallet);
            expect(mnemonic.split(' '), hasLength(words));
            expect(engine.isValidMnemonic(mnemonic), isTrue);
          } finally {
            wallet.dispose();
          }
        }
      });

      test('every BIP-39 strength creates a valid wallet', () {
        final context = newContext();
        for (final strength in [128, 160, 192, 224, 256]) {
          final wallet = HDWallet.create(context, strength: strength);
          try {
            expect(
              wallet.exportMnemonic().split(' '),
              hasLength(strength * 3 ~/ 32),
            );
          } finally {
            wallet.dispose();
          }
        }
      });

      test('two wallets get different mnemonics', () {
        final engine = WalletEngine(newContext());
        final a = engine.createWallet();
        final b = engine.createWallet();
        try {
          expect(engine.exportMnemonic(a) == engine.exportMnemonic(b), isFalse);
        } finally {
          a.dispose();
          b.dispose();
        }
      });
    });

    group('ethereum-address-n/a-1', () {
      test('the imported vector mnemonic derives the vector address and '
          'public key at the vector path', () {
        final vector = vectorById(inventory, 'ethereum-address-n/a-1');
        final input = vector.input as Map;
        final expected = vector.expected as Map;
        final coin = Coin.byId(vector.coin);
        final engine = WalletEngine(newContext());

        final wallet = engine.importMnemonic(input['mnemonic'] as String);
        try {
          final account = engine.deriveAccount(
            wallet,
            coin,
            path: input['derivation_path'] as String,
          );
          expect(account.address.value, expected['address']);
          expect(_hex(account.publicKey), expected['public_key']);
          expect(account.coin, Coin.ethereum);
          expect(account.network, Network.mainnet);
          expect(account.addressStyle, AddressStyle.standard);
          expect(account.derivationPath, input['derivation_path']);
          expect(
            () => account.publicKey[0] = 0,
            throwsUnsupportedError,
            reason: 'the returned public key is an unmodifiable copy',
          );
          expect(engine.exportMnemonic(wallet), input['mnemonic']);
        } finally {
          wallet.dispose();
        }
      });

      test('the default path is the registry path', () {
        final vector = vectorById(inventory, 'ethereum-address-n/a-1');
        final engine = WalletEngine(newContext());
        final wallet = engine.importMnemonic(
          (vector.input as Map)['mnemonic'] as String,
        );
        try {
          final account = engine.deriveAccount(wallet, Coin.ethereum);
          expect(account.derivationPath, "m/44'/60'/0'/0/0");
          expect(
            Address.looksWellFormed(account.address.value, coin: Coin.ethereum),
            isTrue,
          );
          expect(
            engine.isValidAddress(account.address.value, Coin.ethereum),
            isTrue,
          );
        } finally {
          wallet.dispose();
        }
      });
    });

    group('invalid_input vectors raise their typed errors', () {
      for (final id in [
        'ethereum-invalid_input-n/a-1',
        'ethereum-invalid_input-n/a-2',
        'ethereum-invalid_input-n/a-3',
      ]) {
        test(id, () {
          final vector = vectorById(inventory, id);
          final input = vector.input as Map;
          final inputName =
              _inputNameForVectorError[(vector.expected as Map)['error']]!;
          final coin = Coin.byId(vector.coin);
          final engine = WalletEngine(newContext());
          switch (inputName) {
            case 'mnemonic':
              final mnemonic = input['mnemonic'] as String;
              expect(
                () => engine.importMnemonic(mnemonic),
                _invalid(inputName),
              );
              expect(engine.isValidMnemonic(mnemonic), isFalse);
              try {
                engine.importMnemonic(mnemonic);
              } on InvalidInputError catch (error) {
                expectRedacted(error, [mnemonic]);
              }
            case 'address':
              final address = input['address'] as String;
              expect(engine.isValidAddress(address, coin), isFalse);
              expect(
                () => engine.parseAddress(address, coin),
                _invalid(inputName),
              );
            case 'derivationPath':
              final wallet = engine.createWallet();
              try {
                expect(
                  () => engine.deriveAccount(
                    wallet,
                    coin,
                    path: input['derivation_path'] as String,
                  ),
                  _invalid(inputName),
                );
              } finally {
                wallet.dispose();
              }
            default:
              fail('unmapped vector error $inputName');
          }
        });
      }
    });

    group('addresses', () {
      test('a valid and an invalid Ethereum address', () {
        final engine = WalletEngine(newContext());
        const valid = '0x996891c410FB76C19DBA72C6f6cEFF2d9DD069b1';
        expect(engine.isValidAddress(valid, Coin.ethereum), isTrue);
        expect(
          engine.parseAddress(valid, Coin.ethereum),
          isA<Address>()
              .having((a) => a.value, 'value', valid)
              .having((a) => a.coin, 'coin', Coin.ethereum),
        );
        expect(
          engine.isValidAddress(
            '0x996891c410FB76C19DBA72C6f6cEFF2d9DD069b',
            Coin.ethereum,
          ),
          isFalse,
        );
        expect(engine.isValidAddress('not an address', Coin.ethereum), isFalse);
      });

      test('testnet derivation and validation are separate from mainnet', () {
        final vector = vectorById(inventory, 'ethereum-address-n/a-1');
        final engine = WalletEngine(newContext());
        final wallet = engine.importMnemonic(
          (vector.input as Map)['mnemonic'] as String,
        );
        try {
          for (final coin in [Coin.bitcoin, Coin.byId('pactus')]) {
            final mainnet = engine.deriveAccount(wallet, coin);
            final testnet = engine.deriveAccount(
              wallet,
              coin,
              network: Network.testnet,
            );
            final hrp = testnetBech32Hrp[coin.id]!;
            expect(
              testnet.address.value,
              startsWith('${hrp}1'),
              reason:
                  'upstream derives ${coin.id} testnet addresses with '
                  'the prefix the facade validates them with',
            );
            expect(
              engine.isValidAddress(
                testnet.address.value,
                coin,
                network: Network.testnet,
              ),
              isTrue,
              reason: '${coin.id} testnet address on testnet',
            );
            expect(
              engine.isValidAddress(
                mainnet.address.value,
                coin,
                network: Network.testnet,
              ),
              isFalse,
              reason: 'a mainnet address for a testnet account (TM-21)',
            );
            expect(
              engine.isValidAddress(testnet.address.value, coin),
              isFalse,
              reason: 'a testnet address for a mainnet account',
            );
          }
        } finally {
          wallet.dispose();
        }
      });

      test('every registry coin derives its default address or raises a '
          'typed error', () {
        final vector = vectorById(inventory, 'ethereum-address-n/a-1');
        final engine = WalletEngine(newContext());
        final wallet = engine.importMnemonic(
          (vector.input as Map)['mnemonic'] as String,
        );
        final failures = <String>[];
        try {
          for (final coin in Coin.all) {
            try {
              final account = engine.deriveAccount(wallet, coin);
              expect(account.address.value, isNotEmpty, reason: coin.id);
              expect(account.publicKey, isNotEmpty, reason: coin.id);
              expect(
                engine.isValidAddress(account.address.value, coin),
                isTrue,
                reason: coin.id,
              );
            } on WalletCoreException catch (error) {
              failures.add('${coin.id}: $error');
            }
          }
        } finally {
          wallet.dispose();
        }
        // Recorded, not hidden: a coin upstream cannot derive from a public
        // key alone surfaces as a typed error, never as a crash.
        printOnFailure(failures.join('\n'));
        expect(failures, isEmpty);
      });
    });

    group('mnemonics', () {
      test('entropy import reproduces the BIP-39 reference mnemonic', () {
        final engine = WalletEngine(newContext());
        // BIP-39 reference vector: 16 zero bytes.
        final wallet = engine.importEntropy(Uint8List(16));
        try {
          expect(engine.exportMnemonic(wallet), '${'abandon ' * 11}about');
        } finally {
          wallet.dispose();
        }
      });

      test('the passphrase changes the derived account', () {
        final engine = WalletEngine(newContext());
        final mnemonic = '${'abandon ' * 11}about';
        final plain = engine.importMnemonic(mnemonic);
        final salted = engine.importMnemonic(mnemonic, passphrase: 'TREZOR');
        try {
          expect(
            engine.deriveAccount(plain, Coin.ethereum).address,
            isNot(engine.deriveAccount(salted, Coin.ethereum).address),
          );
        } finally {
          plain.dispose();
          salted.dispose();
        }
      });

      test('word validation and suggestions come from upstream', () {
        final engine = WalletEngine(newContext());
        expect(engine.isValidMnemonicWord('abandon'), isTrue);
        expect(engine.isValidMnemonicWord('abandonx'), isFalse);
        final suggestions = engine.suggestMnemonicWords('aba');
        expect(suggestions, contains('abandon'));
        expect(suggestions.every((w) => w.startsWith('aba')), isTrue);
        expect(engine.suggestMnemonicWords('zzzz'), isEmpty);
      });
    });

    group('disposal contract (PRD §11.2)', () {
      test('double dispose is a no-op', () {
        final wallet = HDWallet.create(newContext());
        expect(wallet.isFinalizerAttached, isTrue);
        wallet.dispose();
        expect(wallet.isDisposed, isTrue);
        expect(wallet.isFinalizerAttached, isFalse);
        wallet.dispose();
        expect(wallet.isDisposed, isTrue);
      });

      test("use after dispose raises the SDK's DisposedError", () {
        final wallet = HDWallet.create(newContext());
        wallet.dispose();
        final disposed = throwsA(
          isA<DisposedError>().having(
            (e) => e.resourceType,
            'resourceType',
            'HDWallet',
          ),
        );
        expect(wallet.exportMnemonic, disposed);
        expect(() => wallet.deriveAccount(Coin.ethereum), disposed);
        expect(wallet.toString(), 'HDWallet(disposed: true)');
      });

      test('a scope that creates, derives and disposes leaves the leak '
          'tracker at zero undisposed', () {
        final tracker = LeakTracker.maybeCreate()!;
        final context = newContext(observer: tracker);
        final engine = WalletEngine(context);
        runScope(context, (scope) {
          final wallet = scope.use(engine.createWallet(strength: 256));
          engine.deriveAccount(wallet, Coin.ethereum);
          engine.deriveAccount(wallet, Coin.bitcoin, network: Network.testnet);
          engine.exportMnemonic(wallet);
          engine.isValidAddress(
            '0x996891c410FB76C19DBA72C6f6cEFF2d9DD069b1',
            Coin.ethereum,
          );
          expect(tracker.report.live, 1, reason: 'only the wallet is live');
        });
        final report = tracker.report;
        expect(report.live, 0, reason: '$report');
        expect(report.finalizedWithoutDispose, 0, reason: '$report');
        expect(report.disposed, greaterThan(10));
      });

      test('a throwing body still releases everything', () {
        final tracker = LeakTracker.maybeCreate()!;
        final context = newContext(observer: tracker);
        final engine = WalletEngine(context);
        late HDWallet escaped;
        expect(
          () => runScope(context, (scope) {
            escaped = scope.use(engine.createWallet());
            engine.deriveAccount(escaped, Coin.ethereum);
            throw StateError('body failed');
          }),
          throwsStateError,
        );
        expect(escaped.isDisposed, isTrue);
        expect(tracker.report.live, 0, reason: '${tracker.report}');
      });

      test('a failing derivation releases its temporaries', () {
        final tracker = LeakTracker.maybeCreate()!;
        final context = newContext(observer: tracker);
        final wallet = HDWallet.create(context);
        try {
          expect(
            () => wallet.deriveAccount(Coin.ethereum, path: 'm/44/60/invalid'),
            _invalid('derivationPath'),
          );
          expect(
            () => wallet.deriveAccount(Coin.ethereum, network: Network.testnet),
            throwsA(isA<UnsupportedOperationError>()),
          );
          expect(
            () => HDWallet.fromMnemonic(context, '${'abandon ' * 11}abandon'),
            _invalid('mnemonic'),
          );
          expect(tracker.report.live, 1, reason: '${tracker.report}');
        } finally {
          wallet.dispose();
        }
        expect(tracker.report.live, 0);
      });
    });
  });
}
