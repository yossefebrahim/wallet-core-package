// The public signing value types: request validation and immutability,
// locators, roles, and results — and that none of them renders more than a
// name. Pure Dart.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/src/errors/errors.dart';
import 'package:wallet_core_flutter/src/requests/requests.dart';
import 'package:wallet_core_flutter/src/session/testing.dart';
import 'package:wallet_core_flutter/src/signing/key_locator.dart';
import 'package:wallet_core_flutter/src/signing/sign_result.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart'
    show ChainFamily, Coin;

import '../support/fake_handler.dart';

const String _to = '0xB9F5771C27664bF2282D98E09D7F50cEc7cB01a7';

Matcher _invalid(String inputName) => throwsA(
  isA<InvalidInputError>().having((e) => e.inputName, 'inputName', inputName),
);

EvmTransactionRequest _transfer({
  Coin coin = Coin.ethereum,
  int chainId = 1,
  BigInt? nonce,
  String to = _to,
  BigInt? valueWei,
  BigInt? maxFeePerGas,
  BigInt? maxPriorityFeePerGas,
  BigInt? gasLimit,
}) => EvmTransactionRequest.transfer(
  coin: coin,
  chainId: chainId,
  nonce: nonce ?? BigInt.zero,
  to: to,
  valueWei: valueWei ?? BigInt.one,
  maxFeePerGas: maxFeePerGas ?? BigInt.two,
  maxPriorityFeePerGas: maxPriorityFeePerGas ?? BigInt.one,
  gasLimit: gasLimit ?? BigInt.from(21000),
);

void main() {
  final maxUint256 = (BigInt.one << 256) - BigInt.one;

  group('EvmTransactionRequest validation, at construction', () {
    test('accepts the bounds of every integer', () {
      final request = _transfer(
        nonce: maxUint256,
        valueWei: BigInt.zero,
        maxFeePerGas: maxUint256,
        maxPriorityFeePerGas: BigInt.zero,
        gasLimit: BigInt.zero,
      );
      expect(request.nonce, maxUint256);
      expect(request.isLegacy, isFalse);
      expect(request.data, isNull);
    });

    test('rejects a non-EVM coin', () {
      expect(() => _transfer(coin: Coin.bitcoin), _invalid('coin'));
      expect(() => _transfer(coin: Coin.solana), _invalid('coin'));
    });

    test('rejects a chain id below 1', () {
      expect(() => _transfer(chainId: 0), _invalid('chainId'));
      expect(() => _transfer(chainId: -1), _invalid('chainId'));
    });

    test('rejects an address that is not 0x and forty hex digits', () {
      for (final to in [
        '',
        'B9F5771C27664bF2282D98E09D7F50cEc7cB01a7',
        '0XB9F5771C27664bF2282D98E09D7F50cEc7cB01a7',
        '0xB9F5771C27664bF2282D98E09D7F50cEc7cB01a',
        '0xB9F5771C27664bF2282D98E09D7F50cEc7cB01a77',
        '0xZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ',
        ' 0xB9F5771C27664bF2282D98E09D7F50cEc7cB01a7',
        '0xB9F5771C27664bF2282D98E09D7F50cEc7cB01a7\n',
      ]) {
        expect(() => _transfer(to: to), _invalid('to'), reason: to);
      }
    });

    test('rejects negative and over-wide integers, naming each', () {
      final negative = -BigInt.one;
      final tooWide = maxUint256 + BigInt.one;
      for (final bad in [negative, tooWide]) {
        expect(() => _transfer(nonce: bad), _invalid('nonce'));
        expect(() => _transfer(valueWei: bad), _invalid('valueWei'));
        expect(() => _transfer(gasLimit: bad), _invalid('gasLimit'));
        expect(() => _transfer(maxFeePerGas: bad), _invalid('maxFeePerGas'));
        expect(
          () => _transfer(maxPriorityFeePerGas: bad),
          _invalid('maxPriorityFeePerGas'),
        );
        expect(
          () => EvmTransactionRequest.legacyTransfer(
            coin: Coin.ethereum,
            chainId: 1,
            nonce: BigInt.zero,
            to: _to,
            valueWei: BigInt.zero,
            gasPrice: bad,
            gasLimit: BigInt.one,
          ),
          _invalid('gasPrice'),
        );
      }
    });

    test('accepts every EVM-family coin of the facade', () {
      final evm = Coin.all.where(
        (coin) => coin.family == ChainFamily.evm && coin.evmChainId != null,
      );
      expect(evm, isNotEmpty);
      for (final coin in evm) {
        expect(
          _transfer(coin: coin, chainId: coin.evmChainId!).coin,
          coin,
          reason: coin.id,
        );
      }
    });
  });

  group('EvmTransactionRequest values', () {
    test('a contract call copies its calldata and exposes it read-only', () {
      final data = Uint8List.fromList([0xa9, 0x05, 0x9c, 0xbb]);
      final request = EvmTransactionRequest.contractCall(
        coin: Coin.ethereum,
        chainId: 1,
        nonce: BigInt.one,
        to: _to,
        data: data,
        maxFeePerGas: BigInt.two,
        maxPriorityFeePerGas: BigInt.one,
        gasLimit: BigInt.from(60000),
      );
      data[0] = 0;
      expect(request.data, [0xa9, 0x05, 0x9c, 0xbb]);
      expect(() => request.data![0] = 1, throwsUnsupportedError);
      expect(request.valueWei, BigInt.zero);
    });

    test('a legacy transfer carries a gas price and no EIP-1559 fees', () {
      final request = EvmTransactionRequest.legacyTransfer(
        coin: Coin.ethereum,
        chainId: 1,
        nonce: BigInt.zero,
        to: _to,
        valueWei: BigInt.one,
        gasPrice: BigInt.from(20),
        gasLimit: BigInt.from(21000),
      );
      expect(request.isLegacy, isTrue);
      expect(request.maxFeePerGas, isNull);
      expect(request.maxPriorityFeePerGas, isNull);
    });

    test('has no key locators and is on mainnet', () {
      final request = _transfer();
      expect(request.keyLocators, isEmpty);
      expect(request.network.id, 'mainnet');
      expect(request, isA<TransactionRequest>());
    });

    test('toString names every field and shows calldata by length only', () {
      expect(
        _transfer().toString(),
        'EvmTransactionRequest.transfer(ethereum, chainId: 1, nonce: 0, '
        'to: $_to, valueWei: 1, gasLimit: 21000, maxFeePerGas: 2, '
        'maxPriorityFeePerGas: 1)',
      );
      final call = EvmTransactionRequest.contractCall(
        coin: Coin.ethereum,
        chainId: 1,
        nonce: BigInt.zero,
        to: _to,
        data: Uint8List.fromList(List<int>.filled(68, 0xab)),
        maxFeePerGas: BigInt.two,
        maxPriorityFeePerGas: BigInt.one,
        gasLimit: BigInt.one,
      );
      expect(
        call.toString(),
        startsWith('EvmTransactionRequest.contractCall('),
      );
      expect(call.toString(), endsWith('data: 68 bytes)'));
      expect(call.toString(), isNot(contains('abab')));
    });
  });

  group('KeyLocator', () {
    test('an external locator copies its public key and renders its length '
        'only', () {
      final publicKey = Uint8List.fromList(List<int>.generate(33, (i) => i));
      final locator = KeyLocator.external(
        'ledger-1',
        publicKey,
        role: KeyRole.primary,
      );
      publicKey[0] = 0xff;
      expect((locator as ExternalKeyLocator).publicKey[0], 0);
      expect(() => locator.publicKey[0] = 1, throwsUnsupportedError);
      expect(
        locator.toString(),
        'ExternalKeyLocator(ledger-1, publicKey: 33 bytes, role: primary)',
      );
      expect(
        locator,
        KeyLocator.external(
          'ledger-1',
          Uint8List.fromList(List<int>.generate(33, (i) => i)),
          role: KeyRole.primary,
        ),
      );
    });

    test('an HD locator renders its reference, coin, path and role, and is '
        'equal by all four', () async {
      final core = await initializeForTesting(handler: FakeHandler());
      try {
        final wallet = await core.wallets.create();
        const path = "m/44'/60'/0'/0/0";
        final locator = KeyLocator.hdPath(wallet.ref, Coin.ethereum, path);
        expect(
          locator.toString(),
          "HdKeyLocator(WalletRef(#1), ethereum, $path)",
        );
        expect(
          KeyLocator.hdPath(
            wallet.ref,
            Coin.ethereum,
            path,
            role: KeyRole.primary,
          ).toString(),
          endsWith(', role: primary)'),
        );
        expect(locator, KeyLocator.hdPath(wallet.ref, Coin.ethereum, path));
        expect(
          locator,
          isNot(
            KeyLocator.hdPath(wallet.ref, Coin.ethereum, "m/44'/60'/0'/0/1"),
          ),
        );
        expect(locator.role, isNull);
      } finally {
        await core.shutdown();
      }
    });

    test('imported locators are equal by reference and role', () {
      final ref = issueKeyRef(7);
      expect(KeyLocator.imported(ref), KeyLocator.imported(ref));
      expect(
        KeyLocator.imported(ref),
        isNot(KeyLocator.imported(ref, role: KeyRole.feePayer)),
      );
      expect(
        KeyLocator.imported(ref),
        isNot(KeyLocator.imported(issueKeyRef(7))),
      );
      expect(
        KeyLocator.imported(ref, role: KeyRole.feePayer).toString(),
        'ImportedKeyLocator(KeyRef(#7), role: feePayer)',
      );
      expect({
        KeyLocator.imported(ref),
        KeyLocator.imported(ref),
      }, hasLength(1));
    });

    test('the sealed hierarchy switches exhaustively', () {
      String describe(KeyLocator locator) => switch (locator) {
        HdKeyLocator() => 'hd',
        ImportedKeyLocator() => 'imported',
        ExternalKeyLocator() => 'external',
      };
      expect(describe(KeyLocator.imported(issueKeyRef(1))), 'imported');
    });
  });

  group('KeyRole', () {
    test('is equal by id', () {
      expect(KeyRole.input(3), KeyRole.input(3));
      expect(KeyRole.input(3), isNot(KeyRole.input(4)));
      expect(KeyRole.primary, isNot(KeyRole.feePayer));
      expect(KeyRole.input(0).id, 'input:0');
      expect(KeyRole.feePayer.toString(), 'KeyRole(feePayer)');
    });

    test('rejects a negative input index', () {
      expect(() => KeyRole.input(-1), _invalid('n'));
    });
  });

  group('EvmSignResult', () {
    test('copies its lists, exposes them read-only, and renders lengths '
        'only', () {
      final encoded = Uint8List.fromList([0x02, 0xf8, 0x71]);
      final result = EvmSignResult(
        coin: Coin.ethereum,
        encoded: encoded,
        v: Uint8List(1),
        r: Uint8List(32),
        s: Uint8List(32),
        usedKeys: {KeyLocator.imported(issueKeyRef(1))},
      );
      encoded[0] = 0;
      expect(result.encoded, [0x02, 0xf8, 0x71]);
      expect(() => result.encoded[0] = 1, throwsUnsupportedError);
      expect(result.preHash, isNull);
      expect(
        () => result.usedKeys.add(KeyLocator.imported(issueKeyRef(2))),
        throwsUnsupportedError,
      );
      expect(
        result.toString(),
        'EvmSignResult(ethereum, encoded: 3 bytes, usedKeys: 1)',
      );
      final described = switch (result as SignResult) {
        EvmSignResult() => 'evm',
      };
      expect(described, 'evm');
    });
  });

  group('errors', () {
    test('KeyResolutionError carries its reason', () {
      const error = KeyResolutionError(
        'no locator for the fee payer',
        reason: KeyResolutionReason.missingRole,
      );
      expect(error.reason, KeyResolutionReason.missingRole);
      expect(const KeyResolutionError('x').reason, isNull);
    });

    test('the malformed-output code cannot be an upstream code', () {
      expect(SigningError.malformedOutputCode, isNegative);
    });
  });
}
