// The EVM message family without native code: key-less encoding of both
// vectors, the key-field check on it, the injection slot, the dispatch, the
// EIP-155 refusal, and the parsing of upstream's output — an error first, then
// every shape of malformed output. Pure Dart.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;
// ignore: implementation_imports
import 'package:wallet_core_flutter_bindings/src/generated/proto/Ethereum.pb.dart'
    as eth;
// ignore: implementation_imports
import 'package:wallet_core_flutter_bindings/src/generated/proto/Common.pbenum.dart'
    as common;
import 'package:wallet_core_flutter/src/families/evm/evm_family.dart';
import 'package:wallet_core_flutter/src/families/evm/message_family.dart';
import 'package:wallet_core_flutter/src/families/families.dart';
import 'package:wallet_core_flutter/src/requests/requests.dart';
import 'package:wallet_core_flutter/src/signing/key_field_check.dart';
import 'package:wallet_core_flutter/src/signing/key_locator.dart';
import 'package:wallet_core_flutter/src/signing/sign_result.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart'
    show Coin, InvalidInputError, SigningError, UnsupportedOperationError;

import '../../support/host_library.dart';
import 'message_vector.dart';

Matcher _malformed() => throwsA(
  isA<SigningError>().having(
    (e) => e.upstreamCode,
    'upstreamCode',
    SigningError.malformedOutputCode,
  ),
);

Uint8List _output(eth.MessageSigningOutput output) => output.writeToBuffer();

void main() {
  late MessageVector personal;
  late MessageVector typed;

  setUpAll(() {
    personal = MessageVector.load(personalVectorId);
    typed = MessageVector.load(typedDataVectorId);
  });

  group('encodeKeylessInput', () {
    test(
      'personal: the vector message, type legacy, no key and no chain id',
      () {
        final bytes = evmPersonalMessageFamily.encodeKeylessInput(
          personalRequest(personal),
        );
        final decoded = eth.MessageSigningInput.fromBuffer(bytes);
        expect(decoded.message, personal.input['message']);
        expect(decoded.messageType, eth.MessageType.MessageType_legacy);
        expect(decoded.hasChainId(), isFalse);
        expect(decoded.privateKey, isEmpty);
        expect(decoded.unknownFields.isEmpty, isTrue);
        // The whole of it: field 2 (the message), then field 4 (the message
        // type) set explicitly to 0, `MessageType_legacy`.
        final message = utf8.encode(personal.input['message'] as String);
        expect(bytes, [0x12, message.length, ...message, 0x20, 0x00]);
      },
    );

    test('typed data: the vector document, type typed, no key and no chain '
        'id', () {
      final bytes = evmTypedDataMessageFamily.encodeKeylessInput(
        typedDataRequest(typed),
      );
      final decoded = eth.MessageSigningInput.fromBuffer(bytes);
      expect(decoded.message, typed.input['typed_data']);
      expect(decoded.messageType, eth.MessageType.MessageType_typed);
      expect(decoded.hasChainId(), isFalse);
      expect(decoded.privateKey, isEmpty);
      expect(decoded.unknownFields.isEmpty, isTrue);
    });

    test('both encodings pass the key-field check of their family', () {
      checkKeylessInput(
        evmPersonalMessageFamily.encodeKeylessInput(personalRequest(personal)),
        evmPersonalMessageFamily,
      );
      checkKeylessInput(
        evmTypedDataMessageFamily.encodeKeylessInput(typedDataRequest(typed)),
        evmTypedDataMessageFamily,
      );
    });

    test('a personal message with a byte order mark is encoded with it', () {
      final request = EvmMessageRequest.personal(
        Uint8List.fromList([0xEF, 0xBB, 0xBF, 0x41]),
        coin: Coin.ethereum,
      );
      // Read on the wire, not through the Dart decoder, which drops a
      // leading byte order mark when it reads a string.
      expect(evmPersonalMessageFamily.encodeKeylessInput(request), [
        0x12, 0x04, 0xEF, 0xBB, 0xBF, 0x41, 0x20, 0x00, //
      ]);
    });

    test('an EIP-155 variant is UnsupportedOperationError before anything is '
        'encoded', () {
      expect(
        () => evmPersonalMessageFamily.encodeKeylessInput(
          personalRequest(personal, chainId: 1),
        ),
        throwsA(
          isA<UnsupportedOperationError>()
              .having((e) => e.capability, 'capability', 'messageType:eip155')
              .having((e) => e.coin, 'coin', Coin.ethereum),
        ),
      );
      expect(
        () => evmTypedDataMessageFamily.encodeKeylessInput(
          typedDataRequest(typed, chainId: 1),
        ),
        throwsA(
          isA<UnsupportedOperationError>().having(
            (e) => e.capability,
            'capability',
            'messageType:typed_eip155',
          ),
        ),
      );
    });

    test('a request of the other kind is a defect of the caller', () {
      expect(
        () => evmTypedDataMessageFamily.encodeKeylessInput(
          personalRequest(personal),
        ),
        throwsArgumentError,
      );
      expect(
        () => evmPersonalMessageFamily.encodeKeylessInput(
          typedDataRequest(typed),
        ),
        throwsArgumentError,
      );
    });
  });

  group('the key slot', () {
    test('one primary role, injected into MessageSigningInput.private_key '
        '(field 1) — the generated key_fields.json says the same', () {
      for (final family in [
        evmPersonalMessageFamily,
        evmTypedDataMessageFamily,
      ]) {
        expect(family.requiredRoles(personalRequest(personal)), [
          KeyRole.primary,
        ]);
        final field = family.injectionField(KeyRole.primary);
        expect(field.messagePath, 'TW.Ethereum.Proto.MessageSigningInput');
        expect(family.signingInputMessage, field.messagePath);
        expect(field.fieldName, 'private_key');
        expect(field.fieldNumber, 1);
        expect(field.repeated, isFalse);
        expect(
          () => family.injectionField(KeyRole.feePayer),
          throwsArgumentError,
        );
        expect(
          () => family.injectionField(KeyRole.input(0)),
          throwsArgumentError,
        );
      }
      final root = repositoryRoot()!;
      final generated = jsonDecode(
        File(
          '${root.path}/packages/wallet_core_flutter_bindings/lib/src/'
          'generated/proto/key_fields.json',
        ).readAsStringSync(),
      ) as Map<String, dynamic>;
      final fields =
          ((generated['messages']
                      as Map<
                        String,
                        dynamic
                      >)['TW.Ethereum.Proto.MessageSigningInput']
                  as Map<String, dynamic>)['fields']
              as List<dynamic>;
      expect(fields, hasLength(1));
      expect((fields.single as Map)['protoName'], 'private_key');
      expect((fields.single as Map)['number'], 1);
    });

    test('the same reviewed list serves transactions and messages', () {
      expect(
        identical(evmPersonalMessageFamily.keyFields, evmFamily.keyFields),
        isTrue,
      );
      expect(evmPersonalMessageFamily.chainFamily, evmFamily.chainFamily);
    });

    test('the check rejects message bytes that already carry the key', () {
      final keyed = eth.MessageSigningInput(
        message: 'Foo',
        privateKey: List<int>.filled(32, 7),
      ).writeToBuffer();
      expect(
        () => checkKeylessInput(keyed, evmPersonalMessageFamily),
        throwsA(
          isA<InvalidInputError>()
              .having((e) => e.inputName, 'inputName', 'signingInput')
              .having(
                (e) => e.message,
                'message',
                contains('MessageSigningInput.private_key'),
              ),
        ),
      );
    });

    test('the check rejects a transaction input given to the message family '
        'by its decode', () {
      // A SigningInput with a field 9 (private_key) decodes as an unknown
      // field of MessageSigningInput and is refused as opaque.
      final transaction = eth.SigningInput(privateKey: List<int>.filled(32, 7))
          .writeToBuffer();
      expect(
        () => checkKeylessInput(transaction, evmPersonalMessageFamily),
        throwsA(isA<InvalidInputError>()),
      );
    });
  });

  group('familyForMessage', () {
    test('is the personal family for a personal request and the typed-data '
        'family for a typed one', () {
      expect(
        familyForMessage(personalRequest(personal)),
        same(evmPersonalMessageFamily),
      );
      expect(
        familyForMessage(typedDataRequest(typed)),
        same(evmTypedDataMessageFamily),
      );
    });
  });

  group('parseSigningOutput', () {
    late Set<KeyLocator> noKeys;
    setUp(() => noKeys = const <KeyLocator>{});

    EvmMessageSignResult parse(EvmMessageFamily family, Uint8List bytes) =>
        family.parseSigningOutput(bytes, coin: Coin.ethereum, usedKeys: noKeys);

    test('the personal vector signature: 65 bytes as upstream returns it, '
        'kind personal', () {
      final result = parse(
        evmPersonalMessageFamily,
        _output(eth.MessageSigningOutput(signature: personal.signature)),
      );
      expect(result.signature, hasLength(65));
      expect(result.signature, unhex(personal.signature));
      expect(result.signatureHex, personal.signature);
      expect(result.messageType, EvmMessageType.personal);
      expect(result.coin, Coin.ethereum);
      expect(result.usedKeys, isEmpty);
      expect(() => result.signature[0] = 0, throwsUnsupportedError);
    });

    test('the typed-data vector signature, kind typedData; upper-case hex '
        'decodes to the same bytes', () {
      final result = parse(
        evmTypedDataMessageFamily,
        _output(eth.MessageSigningOutput(signature: typed.signature)),
      );
      expect(result.signature, unhex(typed.signature));
      expect(result.messageType, EvmMessageType.typedData);
      final upper = parse(
        evmTypedDataMessageFamily,
        _output(
          eth.MessageSigningOutput(signature: typed.signature.toUpperCase()),
        ),
      );
      expect(upper.signature, result.signature);
    });

    test('the rendering names the length, never the signature', () {
      final result = parse(
        evmPersonalMessageFamily,
        _output(eth.MessageSigningOutput(signature: personal.signature)),
      );
      expect(
        result.toString(),
        'EvmMessageSignResult(ethereum, personal, signature: 65 bytes, '
        'usedKeys: 0)',
      );
    });

    test('an upstream error is read first and surfaces verbatim, even with a '
        'signature beside it', () {
      final output = eth.MessageSigningOutput(
        signature: personal.signature,
        error: common.SigningError.Error_internal,
        errorMessage: 'upstream says no',
      );
      expect(
        () => parse(evmPersonalMessageFamily, _output(output)),
        throwsA(
          isA<SigningError>()
              .having(
                (e) => e.upstreamCode,
                'code',
                common.SigningError.Error_internal.value,
              )
              .having((e) => e.message, 'message', 'upstream says no'),
        ),
      );
    });

    test('an error code this build does not know is an error, not OK', () {
      final unknown = Uint8List.fromList([
        0x10, // field 2, varint
        0xE7, 0x07, // 999
        0x1A, 0x02, 0x6E, 0x6F, // field 3: "no"
      ]);
      expect(
        () => parse(evmPersonalMessageFamily, unknown),
        throwsA(
          isA<SigningError>()
              .having((e) => e.upstreamCode, 'code', 999)
              .having((e) => e.message, 'message', 'no'),
        ),
      );
      // The wrong wire type for the error field is malformed, not an error.
      expect(
        () => parse(
          evmPersonalMessageFamily,
          Uint8List.fromList([0x12, 0x01, 0x00]),
        ),
        _malformed(),
      );
    });

    test('an output with no signature, or a wrong-sized or non-hex one, is '
        'malformed', () {
      for (final bad in <String>[
        '',
        personal.signature.substring(2),
        '${personal.signature}00',
        '${personal.signature.substring(0, 128)}zz',
        '0x${personal.signature.substring(2)}',
        personal.signature.replaceRange(4, 6, '  '),
      ]) {
        expect(
          () => parse(
            evmPersonalMessageFamily,
            _output(eth.MessageSigningOutput(signature: bad)),
          ),
          _malformed(),
          reason: 'length ${bad.length}',
        );
      }
      expect(() => parse(evmPersonalMessageFamily, Uint8List(0)), _malformed());
    });

    test('an unknown field makes the output malformed', () {
      final withExtra = Uint8List.fromList([
        ..._output(eth.MessageSigningOutput(signature: personal.signature)),
        0x2A, 0x01, 0x00, // field 5
      ]);
      expect(() => parse(evmPersonalMessageFamily, withExtra), _malformed());
    });

    test('garbage and truncated bytes are malformed and nothing else', () {
      final random = Random(7);
      final good = _output(
        eth.MessageSigningOutput(signature: personal.signature),
      );
      for (var i = 0; i < 200; i++) {
        final garbage = Uint8List.fromList(
          List<int>.generate(
            1 + random.nextInt(200),
            (_) => random.nextInt(256),
          ),
        );
        try {
          parse(evmPersonalMessageFamily, garbage);
        } on SigningError {
          // Malformed, or an upstream-shaped error: both are typed.
        }
      }
      for (var cut = 1; cut < good.length; cut++) {
        expect(
          () => parse(evmPersonalMessageFamily, good.sublist(0, cut)),
          throwsA(isA<SigningError>()),
          reason: 'cut at $cut',
        );
      }
    });
  });

  test('a GeneratedMessage decode of the wrong bytes is not mistaken for the '
      'input', () {
    final GeneratedMessage decoded = evmPersonalMessageFamily
        .decodeSigningInput(
          eth.MessageSigningInput(message: 'x').writeToBuffer(),
        );
    expect(
      decoded.info_.qualifiedMessageName,
      evmPersonalMessageFamily.signingInputMessage,
    );
  });
}
