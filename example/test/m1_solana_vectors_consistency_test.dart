/// The device tests' Solana vector constants
/// (integration_test/m1_solana_vectors.dart) against the repository's
/// inventory, so the copy cannot drift from the single source
/// (test_vectors/solana/vectors.yaml).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import '../integration_test/m1_solana_vectors.dart' as c;

void main() {
  late Map<String, Map<dynamic, dynamic>> byId;

  setUpAll(() {
    // `flutter test` runs with the package (example/) as the working
    // directory.
    final doc = loadYaml(
      File('../test_vectors/solana/vectors.yaml').readAsStringSync(),
    ) as YamlMap;
    byId = {
      for (final entry in doc['vectors'] as YamlList)
        (entry as YamlMap)['id'] as String: entry,
    };
  });

  Map<dynamic, dynamic> section(String id, String name) {
    final entry = byId[id];
    expect(entry, isNotNull, reason: 'vector $id exists');
    return entry![name] as Map<dynamic, dynamic>;
  }

  test('solana-address-n/a-1', () {
    final input = section('solana-address-n/a-1', 'input');
    expect(c.addressMnemonic, input['mnemonic']);
    expect(c.addressPath, input['derivation_path']);
    expect(
      c.addressExpected,
      section('solana-address-n/a-1', 'expected')['address'],
    );
  });

  test('solana-sign-legacy-1 input', () {
    final input = section('solana-sign-legacy-1', 'input');
    // Compared as a boolean, so a failure prints no key.
    expect(c.signPrivateKeyBase58 == input['private_key_base58'], isTrue);
    expect(c.signToAddress, input['to_address']);
    expect(c.signLamports, input['lamports']);
    expect(c.signRecentBlockhash, input['recent_blockhash']);
  });

  test('solana-sign-legacy-1 expected', () {
    final expected = section('solana-sign-legacy-1', 'expected');
    expect(c.signExpectedEncoded, expected['encoded']);
    expect(c.signExpectedUnsignedTx, expected['unsigned_tx']);
  });

  test('the not-an-address stand-in is 33 base58 characters and not any '
      "vector's address", () {
    expect(c.notAnAddress, hasLength(33));
    expect(c.notAnAddress, matches(RegExp(r'^[1-9A-HJ-NP-Za-km-z]+$')));
    for (final entry in byId.values) {
      final input = entry['input'] as Map;
      expect(input.values.contains(c.notAnAddress), isFalse);
    }
  });
}
