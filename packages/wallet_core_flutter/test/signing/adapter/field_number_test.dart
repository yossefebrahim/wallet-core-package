/// The adapter's key field number, held equal in three places: the C
/// `#define` in `wcf_sign.h` (read as text — Dart cannot include a header),
/// the Dart mirror `adapterPrivateKeyField`, and the generated
/// `key_fields.json`'s `TW.Ethereum.Proto.SigningInput.private_key`. Also
/// the EVM family's reviewed injection field, which the adapter core checks
/// at every call. Pure: no native library.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/src/families/evm/evm_family.dart';
import 'package:wallet_core_flutter/src/signing/adapter/adapter_signing_core.dart';
import 'package:wallet_core_flutter/src/signing/key_locator.dart';

import '../../support/host_library.dart' show repositoryRoot;

const String _defineName = 'WCF_ETHEREUM_SIGNING_INPUT_PRIVATE_KEY_FIELD';

void main() {
  late Directory root;

  setUpAll(() => root = repositoryRoot()!);

  String read(String relative) =>
      File('${root.path}${Platform.pathSeparator}$relative').readAsStringSync();

  int headerFieldNumber() {
    final header = read(
      'packages/wallet_core_flutter_native/src/shim/wcf_sign.h',
    );
    final matches = RegExp(
      '^#define[ \\t]+$_defineName[ \\t]+([0-9]+)[ \\t]*\$',
      multiLine: true,
    ).allMatches(header).toList();
    expect(matches, hasLength(1), reason: 'exactly one #define $_defineName');
    return int.parse(matches.single.group(1)!);
  }

  int generatedFieldNumber() {
    final json =
        jsonDecode(
              read(
                'packages/wallet_core_flutter_bindings/lib/src/generated/'
                'proto/key_fields.json',
              ),
            )
            as Map<String, dynamic>;
    final message =
        (json['messages'] as Map<String, dynamic>)[adapterSigningInputMessage]
            as Map<String, dynamic>;
    final fields = [
      for (final field in message['fields'] as List<dynamic>)
        if ((field as Map<String, dynamic>)['protoName'] == 'private_key')
          field,
    ];
    expect(fields, hasLength(1));
    expect(fields.single['repeated'], isFalse);
    expect(fields.single['type'], 'bytes');
    return fields.single['number'] as int;
  }

  test('the C #define equals key_fields.json', () {
    expect(headerFieldNumber(), generatedFieldNumber());
  });

  test("the Dart mirror equals the C #define", () {
    expect(adapterPrivateKeyField, headerFieldNumber());
  });

  test("the EVM family's injection field is the one the adapter writes", () {
    final field = evmFamily.injectionField(KeyRole.primary);
    expect(field.messagePath, adapterSigningInputMessage);
    expect(evmFamily.signingInputMessage, adapterSigningInputMessage);
    expect(field.fieldName, 'private_key');
    expect(field.fieldNumber, adapterPrivateKeyField);
  });
}
