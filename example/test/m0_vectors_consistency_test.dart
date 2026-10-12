/// The device tests' vector constants (integration_test/m0_vectors.dart)
/// against the repository's inventory, so the copy cannot drift from the
/// single source (test_vectors/ethereum/vectors.yaml).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import '../integration_test/m0_vectors.dart' as c;

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

  test('ethereum-sign-eip1559-1 input', () {
    final input = section('ethereum-sign-eip1559-1', 'input');
    expect(c.signChainId, input['chain_id']);
    expect(c.signNonce, input['nonce']);
    expect(c.signMaxPriorityFeePerGas, input['max_priority_fee_per_gas']);
    expect(c.signMaxFeePerGas, input['max_fee_per_gas']);
    expect(c.signGasLimit, input['gas_limit']);
    expect(c.signToAddress, input['to_address']);
    expect(c.signValue, input['value']);
    // Compared as a boolean, so a failure prints no key.
    expect(c.signPrivateKey == input['private_key'], isTrue);
  });

  test('ethereum-sign-eip1559-1 expected', () {
    final expected = section('ethereum-sign-eip1559-1', 'expected');
    expect(c.signExpectedEncoded, expected['encoded']);
    expect(c.signExpectedV, expected['v']);
    expect(c.signExpectedR, expected['r']);
    expect(c.signExpectedS, expected['s']);
  });

  test('the invalid-input vectors', () {
    expect(
      c.invalidMnemonic,
      section('ethereum-invalid_input-n/a-1', 'input')['mnemonic'],
    );
    expect(
      c.invalidAddress,
      section('ethereum-invalid_input-n/a-2', 'input')['address'],
    );
    expect(
      c.invalidDerivationPath,
      section('ethereum-invalid_input-n/a-3', 'input')['derivation_path'],
    );
  });

  test('ethereum-address-n/a-1', () {
    final input = section('ethereum-address-n/a-1', 'input');
    expect(c.addressMnemonic, input['mnemonic']);
    expect(c.addressPath, input['derivation_path']);
    expect(
      c.addressExpected,
      section('ethereum-address-n/a-1', 'expected')['address'],
    );
  });

  test('the pinned upstream commit is the manifest identity commit', () {
    final manifest = File('../compat_manifest.json').readAsStringSync();
    expect(manifest, contains('"upstream_commit": "${c.upstreamCommit}"'));
  });
}
