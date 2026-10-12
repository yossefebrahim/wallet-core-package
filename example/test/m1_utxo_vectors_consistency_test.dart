/// The UTXO device test's vector constants
/// (integration_test/m1_utxo_vectors.dart) against the repository's
/// inventory, so the copy cannot drift from the single source
/// (test_vectors/bitcoin/vectors.yaml).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import '../integration_test/m1_utxo_vectors.dart' as c;

void main() {
  late Map<String, Map<dynamic, dynamic>> byId;

  setUpAll(() {
    // `flutter test` runs with the package (example/) as the working
    // directory.
    final doc = loadYaml(
      File('../test_vectors/bitcoin/vectors.yaml').readAsStringSync(),
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

  /// The vector's `utxos`, compared field by field with the constants. Keys
  /// are compared as booleans, so a failure prints none.
  void expectUtxos(String id, List<c.VectorUtxo> constants) {
    final utxos = section(id, 'input')['utxos'] as List<dynamic>;
    expect(constants, hasLength(utxos.length), reason: id);
    for (var i = 0; i < utxos.length; i++) {
      final fields = utxos[i] as Map<dynamic, dynamic>;
      expect(constants[i].txid, fields['txid'], reason: '$id utxo $i');
      expect(constants[i].index, fields['index'], reason: '$id utxo $i');
      expect(constants[i].amount, fields['amount'], reason: '$id utxo $i');
      expect(
        constants[i].scriptPubKey,
        fields['script_pub_key'],
        reason: '$id utxo $i',
      );
      expect(
        constants[i].privateKey == fields['private_key'],
        isTrue,
        reason: '$id utxo $i private_key',
      );
    }
  }

  test('bitcoin-address-n/a-1 and -2', () {
    final first = section('bitcoin-address-n/a-1', 'input');
    final second = section('bitcoin-address-n/a-2', 'input');
    expect(c.addressMnemonic, first['mnemonic']);
    expect(c.addressMnemonic, second['mnemonic']);
    expect(c.addressPath0, first['derivation_path']);
    expect(c.addressPath1, second['derivation_path']);
    final expected0 = section('bitcoin-address-n/a-1', 'expected');
    final expected1 = section('bitcoin-address-n/a-2', 'expected');
    expect(c.addressExpected0, expected0['address']);
    expect(c.addressExpected1, expected1['address']);
    expect(c.publicKeyExpected0, expected0['public_key']);
    expect(c.publicKeyExpected1, expected1['public_key']);
  });

  for (final id in ['bitcoin-plan-p2wpkh-1', 'bitcoin-sign-p2wpkh-1']) {
    test('$id input', () {
      final input = section(id, 'input');
      expect(c.p2wpkhByteFee, input['byte_fee']);
      expect(c.p2wpkhAmount, input['amount']);
      expect(c.p2wpkhUseMaxAmount, input['use_max_amount']);
      expect(c.p2wpkhToAddress, input['to_address']);
      expect(c.p2wpkhChangeAddress, input['change_address']);
      expectUtxos(id, c.p2wpkhUtxos);
    });
  }

  test('bitcoin-plan-p2wpkh-1 expected', () {
    final expected = section('bitcoin-plan-p2wpkh-1', 'expected');
    expect(c.p2wpkhPlanSelectedAmounts, expected['selected_utxo_amounts']);
    expect(c.p2wpkhPlanAmount, expected['amount']);
    expect(c.p2wpkhPlanFee, expected['fee']);
    expect(c.p2wpkhPlanAvailableAmount, expected['available_amount']);
    expect(c.p2wpkhPlanChange, expected['change']);
  });

  test('bitcoin-sign-p2wpkh-1 expected', () {
    final expected = section('bitcoin-sign-p2wpkh-1', 'expected');
    expect(c.p2wpkhSignExpectedEncoded, expected['encoded']);
    expect(c.p2wpkhSignExpectedTxid, expected['txid']);
  });

  for (final id in [
    'bitcoin-plan-multi_input-1',
    'bitcoin-sign-multi_input-1',
  ]) {
    test('$id input', () {
      final input = section(id, 'input');
      expect(c.multiByteFee, input['byte_fee']);
      expect(c.multiAmount, input['amount']);
      expect(c.multiUseMaxAmount, input['use_max_amount']);
      expect(c.multiToAddress, input['to_address']);
      expect(c.multiChangeAddress, input['change_address']);
      expectUtxos(id, c.multiUtxos);
    });
  }

  test('bitcoin-plan-multi_input-1 expected', () {
    final expected = section('bitcoin-plan-multi_input-1', 'expected');
    expect(c.multiPlanSelectedAmounts, expected['selected_utxo_amounts']);
    expect(c.multiPlanAmount, expected['amount']);
    expect(c.multiPlanFee, expected['fee']);
    expect(c.multiPlanAvailableAmount, expected['available_amount']);
    expect(c.multiPlanChange, expected['change']);
  });

  test('bitcoin-sign-multi_input-1 expected', () {
    final expected = section('bitcoin-sign-multi_input-1', 'expected');
    expect(c.multiSignExpectedEncoded, expected['encoded']);
  });
}
