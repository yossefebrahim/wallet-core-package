// Dart-side validation before any native call (PRD §16 S5), and redaction of
// every secret-bearing rejection (threat model TM-09, TM-31).
//
// Every test here runs against a context that resolves no upstream symbol: a
// native call would fail the test with an `ArgumentError` from the lookup, so a
// typed error here also proves nothing reached native code. No library needed.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/advanced.dart';
import 'package:wallet_core_flutter/src/account/derivation_path.dart';
import 'package:wallet_core_flutter/src/core/input_checks.dart';
import 'package:wallet_core_flutter/src/engine/engine.dart';
import 'package:wallet_core_flutter/src/engine/secret_buffers.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';

import '../support/fixtures.dart';

Matcher _invalid(String inputName) => throwsA(
  isA<InvalidInputError>().having((e) => e.inputName, 'inputName', inputName),
);

/// Runs [body], expects an [InvalidInputError] for [inputName], and asserts
/// its rendering contains none of [secrets].
void _expectRedactedRejection(
  String inputName,
  Iterable<String> secrets,
  void Function() body,
) {
  try {
    body();
  } on InvalidInputError catch (error) {
    expect(error.inputName, inputName);
    expectRedacted(error, secrets);
    return;
  }
  fail('no InvalidInputError for $inputName');
}

void main() {
  final context = unreachableNativeContext();
  final engine = WalletEngine(context);

  // Twelve words of this shape would be a plausible secret; eleven are not.
  const elevenWords =
      'zebra cabbage orbit velvet hammer quantum lantern meadow pistol '
      'saddle tunnel';
  const secretPassphrase = 'correct-horse-battery-staple-passphrase';

  group('creation', () {
    test('strength outside 128/160/192/224/256 is rejected', () {
      for (final strength in [0, 64, 127, 129, 512, -128]) {
        expect(
          () => HDWallet.create(context, strength: strength),
          _invalid('strength'),
          reason: '$strength',
        );
      }
    });

    test('an over-long passphrase is rejected without echoing it', () {
      final passphrase = '$secretPassphrase ${'x' * 1100}';
      _expectRedactedRejection('passphrase', [
        secretPassphrase,
      ], () => HDWallet.create(context, passphrase: passphrase));
    });
  });

  group('mnemonic import', () {
    test('a wrong word count is rejected without echoing the words', () {
      _expectRedactedRejection('mnemonic', [
        elevenWords,
      ], () => HDWallet.fromMnemonic(context, elevenWords));
      _expectRedactedRejection('mnemonic', [
        elevenWords,
      ], () => engine.importMnemonic('$elevenWords abandon abandon'));
    });

    test('an over-long or empty mnemonic is rejected', () {
      expect(() => HDWallet.fromMnemonic(context, ''), _invalid('mnemonic'));
      expect(
        () => HDWallet.fromMnemonic(context, '${'a ' * 11}${'b' * 600}'),
        _invalid('mnemonic'),
      );
    });

    test('a long passphrase is rejected even with a plausible mnemonic', () {
      _expectRedactedRejection(
        'passphrase',
        [secretPassphrase, elevenWords],
        () => HDWallet.fromMnemonic(
          context,
          '$elevenWords abandon',
          passphrase: '$secretPassphrase${'y' * 1100}',
        ),
      );
    });
  });

  group('entropy import', () {
    test('a length other than 16/20/24/28/32 bytes is rejected without '
        'echoing the bytes', () {
      for (final length in [0, 15, 17, 31, 33, 64]) {
        final entropy = Uint8List.fromList(
          List<int>.generate(length, (i) => 0xA0 + i % 16),
        );
        final hex = entropy
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        _expectRedactedRejection('entropy', [
          if (hex.isNotEmpty) hex,
        ], () => HDWallet.fromEntropy(context, entropy));
      }
    });
  });

  // A NUL would end the C string upstream reads and an unpaired surrogate would
  // reach it as U+FFFD: either way a different wallet than the one asked for,
  // with no error. Both are rejected before any native call.
  group('text that cannot reach native code unchanged', () {
    const nulPassphrase = 'a\u0000b';
    const loneHigh = 'secret\uD800pass';
    const loneLow = 'secret\uDC00pass';
    const twelveWords = '$elevenWords abandon';
    final nulMnemonic = twelveWords.replaceFirst('orbit', 'orb\u0000it');
    final surrogateMnemonic = twelveWords.replaceFirst('orbit', 'orb\uD83Dit');
    final entropy = Uint8List(16);

    test(
      'isNativeSafeString accepts paired surrogates and rejects the rest',
      () {
        expect(isNativeSafeString('wallet \u{1F512} ok'), isTrue);
        expect(isNativeSafeString(''), isTrue);
        for (final bad in [
          nulPassphrase,
          loneHigh,
          loneLow,
          '\uD800',
          'end\uD800',
          '\uDC00\uD800',
        ]) {
          expect(
            isNativeSafeString(bad),
            isFalse,
            reason: bad.codeUnits.join(),
          );
        }
      },
    );

    for (final (label, passphrase) in [
      ('a NUL', nulPassphrase),
      ('a lone high surrogate', loneHigh),
      ('a lone low surrogate', loneLow),
    ]) {
      test('a passphrase with $label is rejected by create, importMnemonic '
          'and importEntropy', () {
        final secrets = [passphrase];
        _expectRedactedRejection(
          'passphrase',
          secrets,
          () => engine.createWallet(passphrase: passphrase),
        );
        _expectRedactedRejection(
          'passphrase',
          secrets,
          () => engine.importMnemonic(twelveWords, passphrase: passphrase),
        );
        _expectRedactedRejection(
          'passphrase',
          secrets,
          () => engine.importEntropy(entropy, passphrase: passphrase),
        );
      });
    }

    test('a mnemonic with an embedded NUL or a lone surrogate is rejected', () {
      for (final mnemonic in [nulMnemonic, surrogateMnemonic]) {
        _expectRedactedRejection('mnemonic', [
          mnemonic,
          elevenWords,
        ], () => engine.importMnemonic(mnemonic));
        expect(engine.isValidMnemonic(mnemonic), isFalse);
      }
    });

    test('the staging helper itself refuses such text', () {
      expect(
        () => secretString(context, nulPassphrase, inputName: 'passphrase'),
        _invalid('passphrase'),
      );
      expect(
        () => secretString(context, loneHigh, inputName: 'mnemonic'),
        _invalid('mnemonic'),
      );
    });

    test('a word, prefix or address with a NUL is simply not valid', () {
      expect(engine.isValidMnemonicWord('abandon\u0000x'), isFalse);
      expect(engine.isValidMnemonicWord('aband\uD800'), isFalse);
      expect(engine.suggestMnemonicWords('ab\u0000'), isEmpty);
      const address = '0x996891c410FB76C19DBA72C6f6cEFF2d9DD069b1';
      expect(
        engine.isValidAddress('$address\u0000junk', Coin.ethereum),
        isFalse,
      );
      expect(engine.isValidAddress('$address\uDC00', Coin.ethereum), isFalse);
      expect(
        () => engine.parseAddress('$address\u0000junk', Coin.ethereum),
        _invalid('address'),
      );
    });

    test('a derivation path with a NUL is rejected by the path grammar', () {
      expect(isValidDerivationPath("m/44'/60'/0'/0/0\u0000"), isFalse);
      expect(isValidDerivationPath("m/44'/60'/0'/0/\uD8000"), isFalse);
    });
  });

  group('stateless checks', () {
    test('a mnemonic of the wrong shape is invalid without a native call', () {
      expect(engine.isValidMnemonic(elevenWords), isFalse);
      expect(engine.isValidMnemonic(''), isFalse);
      expect(engine.isValidMnemonic('a ' * 400), isFalse);
    });

    test('an empty or over-long word is invalid without a native call', () {
      expect(engine.isValidMnemonicWord(''), isFalse);
      expect(engine.isValidMnemonicWord('a' * 65), isFalse);
    });

    test('a prefix that cannot begin a word suggests nothing', () {
      for (final prefix in ['', 'AB', 'ab1', 'ab ', 'é', 'a' * 65]) {
        expect(engine.suggestMnemonicWords(prefix), isEmpty, reason: prefix);
      }
    });

    test('an empty or over-long address is invalid without a native call', () {
      expect(engine.isValidAddress('', Coin.ethereum), isFalse);
      expect(engine.isValidAddress('0x${'a' * 600}', Coin.ethereum), isFalse);
      expect(() => engine.parseAddress('', Coin.ethereum), _invalid('address'));
    });

    test('a network the coin lacks is rejected before native', () {
      expect(
        () => engine.isValidAddress(
          '0x996891c410FB76C19DBA72C6f6cEFF2d9DD069b1',
          Coin.ethereum,
          network: Network.testnet,
        ),
        throwsA(
          isA<UnsupportedOperationError>().having(
            (e) => e.capability,
            'capability',
            'network:testnet',
          ),
        ),
      );
    });
  });
}
