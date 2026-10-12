// SolanaTransactionRequest: what is checked at construction, with no native
// code, and what the request is (a pure value with no key and no CoinType).
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/src/capabilities.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';

import '../../support/fixtures.dart';
import 'solana_support.dart';

Matcher _invalid(String inputName) => throwsA(
  isA<InvalidInputError>().having((e) => e.inputName, 'inputName', inputName),
);

void main() {
  late Map<dynamic, dynamic> input;

  setUpAll(() {
    input = vectorById(loadInventory(), signVectorId).input as Map;
  });

  SolanaTransactionRequest transfer({
    String? to,
    int? lamports,
    String? recentBlockhash,
  }) => SolanaTransactionRequest.transfer(
    to: to ?? input['to_address'] as String,
    lamports: lamports ?? 42,
    recentBlockhash: recentBlockhash ?? input['recent_blockhash'] as String,
  );

  test("the vector's inputs build a request on Solana mainnet with no key "
      'locator and no key', () {
    final request = vectorRequest(input);
    expect(request.to, input['to_address']);
    expect(request.lamports, int.parse(input['lamports'] as String));
    expect(request.recentBlockhash, input['recent_blockhash']);
    expect(request.coin, Coin.solana);
    expect(request.network, Network.mainnet);
    expect(request.keyLocators, isEmpty);
    expect(request, isA<TransactionRequest>());
    expect(request.toString(), contains('SolanaTransactionRequest.transfer'));
    // The request holds no key, so no key can appear in what it renders;
    // the vector's key is the one thing the test can look for.
    expect(
      request.toString().contains(input['private_key_base58'] as String),
      isFalse,
    );
  });

  test('the capability registry lists exactly the Solana-family coins for '
      'sign/legacy, which is the vector solana-sign-legacy-1', () {
    expect(
      solanaCoinIds,
      Coin.byFamily(ChainFamily.solana).map((coin) => coin.id).toList(),
    );
    final vector = vectorById(loadInventory(), signVectorId);
    expect(
      (vector.coin, vector.operation, vector.variant),
      ('solana', 'sign', 'legacy'),
    );
    final groups = capabilityGroups.where(
      (g) => g.coins?.contains('solana') ?? true,
    );
    expect(groups.where((g) => g.operation == 'sign').map((g) => g.variant), [
      'legacy',
    ]);
    expect(
      groups.singleWhere((g) => g.variant == 'legacy').exposure,
      Exposure.typed,
    );
  });

  group('to', () {
    test('accepts 32 to 44 base58 characters', () {
      expect(() => transfer(to: '1' * 32), returnsNormally);
      expect(() => transfer(to: 'z' * 44), returnsNormally);
    });

    test('rejects a length outside 32..44, naming the input', () {
      expect(() => transfer(to: ''), _invalid('to'));
      expect(() => transfer(to: '1' * 31), _invalid('to'));
      expect(() => transfer(to: '1' * 45), _invalid('to'));
    });

    test('rejects a character outside the base58 alphabet', () {
      final valid = input['to_address'] as String;
      for (final bad in ['0', 'O', 'I', 'l', ' ', '-', '\n', 'é']) {
        expect(
          () => transfer(to: '${valid.substring(0, 43)}$bad'),
          _invalid('to'),
          reason: 'U+${bad.runes.first.toRadixString(16)}',
        );
      }
      expect(
        () => transfer(to: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8'),
        _invalid('to'),
        reason: 'an EVM address',
      );
    });
  });

  group('lamports', () {
    test('accepts 0 and the largest signed 64-bit value', () {
      expect(transfer(lamports: 0).lamports, 0);
      expect(
        transfer(lamports: 0x7FFFFFFFFFFFFFFF).lamports,
        0x7FFFFFFFFFFFFFFF,
      );
    });

    test('rejects a negative amount, naming the input', () {
      expect(() => transfer(lamports: -1), _invalid('lamports'));
      expect(
        () => transfer(lamports: -0x8000000000000000),
        _invalid('lamports'),
      );
    });
  });

  group('recentBlockhash', () {
    test('accepts 32 to 44 base58 characters', () {
      expect(() => transfer(recentBlockhash: '1' * 32), returnsNormally);
      expect(() => transfer(recentBlockhash: 'z' * 44), returnsNormally);
    });

    test('rejects the wrong length and non-base58 characters, naming the '
        'input', () {
      for (final bad in [
        '',
        '1' * 31,
        '1' * 45,
        '${'1' * 31}0',
        '${'1' * 31} ',
      ]) {
        expect(
          () => transfer(recentBlockhash: bad),
          _invalid('recentBlockhash'),
          reason: '"$bad"',
        );
      }
    });
  });

  test('the first invalid input is the one named: to, then lamports, then '
      'recentBlockhash', () {
    expect(
      () => SolanaTransactionRequest.transfer(
        to: '',
        lamports: -1,
        recentBlockhash: '',
      ),
      _invalid('to'),
    );
    expect(
      () => SolanaTransactionRequest.transfer(
        to: input['to_address'] as String,
        lamports: -1,
        recentBlockhash: '',
      ),
      _invalid('lamports'),
    );
  });
}
