// The Dart-side derivation-path grammar (PRD §16 S5). Pure Dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/src/account/derivation_path.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';
import 'package:wallet_core_flutter_bindings/registry.dart';

import '../support/fixtures.dart';

Matcher _rejectsPath() => throwsA(
  isA<InvalidInputError>().having(
    (e) => e.inputName,
    'inputName',
    'derivationPath',
  ),
);

void main() {
  test('accepts well-formed BIP-32 paths', () {
    for (final path in [
      "m/44'/60'/0'/0/0",
      "m/44'/60'/0'/0/1",
      "m/84'/0'/0'/0/0",
      "m/44'/501'/0'",
      'm/0',
      "m/2147483647'",
      'm/${List.filled(255, '0').join('/')}',
    ]) {
      expect(checkDerivationPath(path), path);
      expect(isValidDerivationPath(path), isTrue, reason: path);
    }
  });

  test('accepts every default path in the pinned registry', () {
    for (final info in coinInfo.values) {
      for (final derivation in info.derivation) {
        expect(
          isValidDerivationPath(derivation.path),
          isTrue,
          reason: derivation.path,
        );
      }
    }
  });

  test('rejects the invalid_derivation_path vector', () {
    final vector = vectorById(loadInventory(), 'ethereum-invalid_input-n/a-3');
    expect(vector.expected['error'], 'invalid_derivation_path');
    final path = vector.input['derivation_path'] as String;
    expect(path, 'm/44/60/invalid');
    expect(() => checkDerivationPath(path), _rejectsPath());
  });

  test('rejects malformed paths', () {
    for (final path in [
      '',
      'm',
      'm/',
      "44'/60'",
      "M/44'",
      'm//0',
      "m/44'/",
      "m/44''",
      'm/44h',
      'm/-1',
      'm/+1',
      'm/01',
      'm/2147483648',
      "m/2147483648'",
      'm/99999999999',
      'm/0 ',
      ' m/0',
      'm/${List.filled(256, '0').join('/')}',
      'm/${'1' * 2000}',
    ]) {
      expect(() => checkDerivationPath(path), _rejectsPath(), reason: path);
      expect(isValidDerivationPath(path), isFalse, reason: path);
    }
  });

  test('the error never quotes the path', () {
    const path = "m/44'/60'/zebra-secret-words";
    try {
      checkDerivationPath(path);
      fail('accepted');
    } on InvalidInputError catch (error) {
      expectRedacted(error, ['zebra-secret-words']);
    }
  });
}
