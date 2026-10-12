/// The device tests' EVM message vector constants
/// (integration_test/m1_evm_messages_vectors.dart) against the repository's
/// inventory, so the copy cannot drift from the single source
/// (test_vectors/ethereum/vectors.yaml).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import '../integration_test/m1_evm_messages_vectors.dart' as c;

void main() {
  late Map<String, Map<dynamic, dynamic>> byId;

  setUpAll(() {
    // `flutter test` runs with the package (example/) as the working
    // directory.
    final doc = loadYaml(
      File('../test_vectors/ethereum/vectors.yaml').readAsStringSync(),
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

  test('ethereum-sign_message-personal-1', () {
    final input = section('ethereum-sign_message-personal-1', 'input');
    expect(c.personalMessage, input['message']);
    expect(input['message_type'], 'legacy');
    // Compared as a boolean, so a failure prints no key.
    expect(c.messagePrivateKey == input['private_key'], isTrue);
    expect(
      c.personalExpectedSignature,
      section('ethereum-sign_message-personal-1', 'expected')['signature'],
    );
  });

  test('ethereum-sign_message-eip712-1', () {
    final input = section('ethereum-sign_message-eip712-1', 'input');
    expect(c.typedDataDocument, input['typed_data']);
    expect(input['message_type'], 'legacy');
    expect(c.messagePrivateKey == input['private_key'], isTrue);
    expect(
      c.typedDataExpectedSignature,
      section('ethereum-sign_message-eip712-1', 'expected')['signature'],
    );
  });

  test('ethereum-address-n/a-1 (the session path\'s HD key)', () {
    final input = section('ethereum-address-n/a-1', 'input');
    expect(c.addressMnemonic, input['mnemonic']);
    expect(c.addressPath, input['derivation_path']);
  });
}
