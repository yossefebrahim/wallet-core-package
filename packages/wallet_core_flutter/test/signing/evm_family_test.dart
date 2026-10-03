// The EVM family and the key-field check, without native code: key-less
// encoding against the T1.10 vector's inputs, the reviewed key-field list
// against the generated one, the tamper check on bytes, and output parsing
// on hand-built, empty, and garbage outputs. Pure Dart.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/protobuf.dart' show BuilderInfo, GeneratedMessage;
// ignore: implementation_imports
import 'package:wallet_core_flutter_bindings/src/generated/proto/Ethereum.pb.dart'
    as eth;
import 'package:wallet_core_flutter/src/errors/errors.dart';
import 'package:wallet_core_flutter/src/families/evm/evm_family.dart';
import 'package:wallet_core_flutter/src/families/families.dart';
import 'package:wallet_core_flutter/src/families/family.dart';
import 'package:wallet_core_flutter/src/requests/requests.dart';
import 'package:wallet_core_flutter/src/signing/key_field_check.dart';
import 'package:wallet_core_flutter/src/signing/key_locator.dart';
import 'package:wallet_core_flutter/src/signing/sign_result.dart';
import 'package:wallet_core_flutter/src/signing/signing_core.dart'
    show lengthDelimitedHeader;
import 'package:wallet_core_flutter/wallet_core_flutter.dart' show Coin;

import '../support/fixtures.dart';
import '../support/host_library.dart';
import 'evm_vector.dart';

const String _vectorId = 'ethereum-sign-eip1559-1';

Matcher _malformed() => throwsA(
  isA<SigningError>().having(
    (e) => e.upstreamCode,
    'upstreamCode',
    SigningError.malformedOutputCode,
  ),
);

Matcher _tampered() => throwsA(
  isA<InvalidInputError>().having(
    (e) => e.inputName,
    'inputName',
    'signingInput',
  ),
);

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _concat(List<List<int>> parts) =>
    Uint8List.fromList([for (final part in parts) ...part]);

/// Upstream's `store(uint256_t(n))` for the test's own expectations.
List<int> _store(String decimal) {
  var value = BigInt.parse(decimal);
  if (value == BigInt.zero) return [0];
  final bytes = <int>[];
  while (value > BigInt.zero) {
    bytes.insert(0, (value & BigInt.from(0xff)).toInt());
    value >>= 8;
  }
  return bytes;
}

void main() {
  late Map<dynamic, dynamic> input;

  setUpAll(() {
    final vector = vectorById(loadInventory(), _vectorId);
    input = vector.input as Map<dynamic, dynamic>;
  });

  group('encodeKeylessInput', () {
    test("re-decodes to the vector's inputs, built as upstream's test builds "
        'them', () {
      final request = vectorRequest(input);
      final bytes = evmFamily.encodeKeylessInput(request);
      final decoded = eth.SigningInput.fromBuffer(bytes);
      expect(decoded.chainId, _store(input['chain_id'] as String));
      expect(decoded.nonce, _store(input['nonce'] as String));
      expect(decoded.txMode, eth.TransactionMode.Enveloped);
      expect(decoded.gasLimit, _store(input['gas_limit'] as String));
      expect(
        decoded.maxInclusionFeePerGas,
        _store(input['max_priority_fee_per_gas'] as String),
      );
      expect(decoded.maxFeePerGas, _store(input['max_fee_per_gas'] as String));
      expect(decoded.toAddress, input['to_address']);
      expect(decoded.hasGasPrice(), isFalse);
      expect(
        decoded.transaction.transfer.amount,
        _store(input['value'] as String),
      );
      expect(input['data'], '');
      expect(decoded.transaction.transfer.data, isEmpty);
      expect(decoded.unknownFields.isEmpty, isTrue);
    });

    test('sets no key field: the generated accessor, the reviewed list, and '
        'the wire tag all agree', () {
      final bytes = evmFamily.encodeKeylessInput(vectorRequest(input));
      final decoded = eth.SigningInput.fromBuffer(bytes);
      expect(decoded.hasPrivateKey(), isFalse);
      expect(decoded.getFieldOrNull(9), isNull);
      expect(evmFamily.keyFields.presentIn(decoded), isEmpty);
      expect(() => checkKeylessInput(bytes, evmFamily), returnsNormally);
    });

    test('a legacy transfer is Legacy mode with a gas price', () {
      final request = EvmTransactionRequest.legacyTransfer(
        coin: Coin.ethereum,
        chainId: 1,
        nonce: BigInt.zero,
        to: input['to_address'] as String,
        valueWei: BigInt.zero,
        gasPrice: BigInt.from(20000000000),
        gasLimit: BigInt.from(21000),
      );
      final decoded = eth.SigningInput.fromBuffer(
        evmFamily.encodeKeylessInput(request),
      );
      expect(decoded.txMode, eth.TransactionMode.Legacy);
      expect(decoded.gasPrice, _store('20000000000'));
      expect(decoded.hasMaxFeePerGas(), isFalse);
      expect(decoded.hasMaxInclusionFeePerGas(), isFalse);
      expect(decoded.nonce, [0]);
      expect(decoded.transaction.transfer.amount, [0]);
    });

    test('a contract call is a ContractGeneric with the calldata', () {
      final request = EvmTransactionRequest.contractCall(
        coin: Coin.ethereum,
        chainId: 1,
        nonce: BigInt.from(256),
        to: input['to_address'] as String,
        data: Uint8List.fromList([0xa9, 0x05, 0x9c, 0xbb]),
        maxFeePerGas: BigInt.two,
        maxPriorityFeePerGas: BigInt.one,
        gasLimit: BigInt.from(60000),
      );
      final decoded = eth.SigningInput.fromBuffer(
        familyFor(request).encodeKeylessInput(request),
      );
      expect(decoded.txMode, eth.TransactionMode.Enveloped);
      expect(decoded.nonce, [1, 0]);
      expect(decoded.transaction.hasContractGeneric(), isTrue);
      expect(decoded.transaction.contractGeneric.data, [
        0xa9,
        0x05,
        0x9c,
        0xbb,
      ]);
      expect(decoded.transaction.contractGeneric.amount, [0]);
    });

    test('a 256-bit value encodes as 32 big-endian bytes', () {
      final max = (BigInt.one << 256) - BigInt.one;
      final request = EvmTransactionRequest.transfer(
        coin: Coin.ethereum,
        chainId: 1,
        nonce: BigInt.zero,
        to: input['to_address'] as String,
        valueWei: max,
        maxFeePerGas: BigInt.one,
        maxPriorityFeePerGas: BigInt.one,
        gasLimit: BigInt.one,
      );
      final decoded = eth.SigningInput.fromBuffer(
        evmFamily.encodeKeylessInput(request),
      );
      expect(decoded.transaction.transfer.amount, List<int>.filled(32, 0xff));
    });

    test('the family needs exactly the primary role', () {
      expect(evmFamily.requiredRoles(vectorRequest(input)), [KeyRole.primary]);
      expect(
        evmFamily.injectionField(KeyRole.primary).fieldNumber,
        eth.SigningInput.getDefault().info_.byName['privateKey']!.tagNumber,
      );
      expect(
        () => evmFamily.injectionField(KeyRole.feePayer),
        throwsArgumentError,
      );
    });
  });

  group('the reviewed key-field list', () {
    test('equals the generated key_fields.json for every Ethereum message '
        'and every message reachable from the signing input', () {
      final root = repositoryRoot()!;
      final generated =
          jsonDecode(
                File(
                  '${root.path}/packages/wallet_core_flutter_bindings/lib/src/'
                  'generated/proto/key_fields.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final messages = generated['messages'] as Map<String, dynamic>;
      final byFile = generated['byFile'] as Map<String, dynamic>;

      // Every message reachable from the signing input, by a recursive walk
      // of the generated schema — a key field one message down would be
      // missed by a top-level scan (DECISION-13 §3.1).
      final reachable = <String>{};
      void walk(BuilderInfo info) {
        if (!reachable.add(info.qualifiedMessageName)) return;
        for (final field in info.byIndex) {
          final sub = field.subBuilder;
          if (sub != null) walk(sub().info_);
        }
      }

      walk(eth.SigningInput.getDefault().info_);
      expect(reachable, contains('TW.Ethereum.Proto.Transaction.Transfer'));

      final wanted = <String>{
        ...(byFile['Ethereum.proto'] as List<dynamic>).cast<String>(),
        ...reachable.where(messages.containsKey),
      };
      final expected = <KeyFieldEntry>{
        for (final message in wanted)
          for (final field
              in (messages[message] as Map<String, dynamic>)['fields']
                  as List<dynamic>)
            KeyFieldEntry(
              messagePath: message,
              fieldName: (field as Map<String, dynamic>)['protoName'] as String,
              fieldNumber: field['number'] as int,
              repeated: field['repeated'] as bool,
            ),
      };
      expect(evmFamily.keyFields.entries.toSet(), expected);
      expect(evmFamily.keyFields.entries, hasLength(expected.length));
    });
  });

  group('the key-field check on bytes', () {
    late Uint8List keyless;

    setUp(() => keyless = evmFamily.encodeKeylessInput(vectorRequest(input)));

    test('rejects bytes carrying private_key, without naming its value', () {
      final key = List<int>.generate(32, (i) => 0x40 + i);
      final tampered = _concat([
        keyless,
        lengthDelimitedHeader(9, key.length),
        key,
      ]);
      expect(() => checkKeylessInput(tampered, evmFamily), _tampered());
      try {
        checkKeylessInput(tampered, evmFamily);
      } on InvalidInputError catch (error) {
        expect(error.message, contains('private_key'));
        expectRedacted(error, [_hex(key)]);
      }
    });

    test('rejects private_key set by the generated setter and serialized', () {
      final message = eth.SigningInput.fromBuffer(keyless)
        ..privateKey = List<int>.filled(32, 1);
      expect(
        () => checkKeylessInput(message.writeToBuffer(), evmFamily),
        _tampered(),
      );
    });

    test('rejects a present but empty private_key, and one with the wrong '
        'wire type', () {
      expect(
        () => checkKeylessInput(
          _concat([keyless, lengthDelimitedHeader(9, 0)]),
          evmFamily,
        ),
        _tampered(),
      );
      // Field 9 as a varint (wire type 0): tag 0x48, value 1.
      expect(
        () => checkKeylessInput(
          _concat([
            keyless,
            [0x48, 0x01],
          ]),
          evmFamily,
        ),
        _tampered(),
      );
    });

    test('walks nested messages', () {
      // A list naming a field one message down, to prove the walk recurses:
      // Transaction.Transfer.amount is set in every encoded transfer.
      const nested = KeyFieldList(<KeyFieldEntry>[
        KeyFieldEntry(
          messagePath: 'TW.Ethereum.Proto.Transaction.Transfer',
          fieldName: 'amount',
          fieldNumber: 1,
          repeated: false,
        ),
      ]);
      expect(
        nested.presentIn(eth.SigningInput.fromBuffer(keyless)),
        nested.entries,
      );
      const repeatedNested = KeyFieldList(<KeyFieldEntry>[
        KeyFieldEntry(
          messagePath: 'TW.Ethereum.Proto.Access',
          fieldName: 'stored_keys',
          fieldNumber: 2,
          repeated: true,
        ),
      ]);
      final withAccess = eth.SigningInput.fromBuffer(keyless)
        ..accessList.add(eth.Access(storedKeys: [List<int>.filled(32, 7)]));
      expect(repeatedNested.presentIn(withAccess), repeatedNested.entries);
      expect(
        repeatedNested.presentIn(eth.SigningInput.fromBuffer(keyless)),
        isEmpty,
      );
    });

    test('rejects a group, or any unknown field, that could hide a key field '
        'from the walk, without naming its contents', () {
      final key = List<int>.generate(32, (i) => 0x40 + i);
      // Field 9 nested in an unknown group (wire type 3): field 100's
      // start-group tag (100 << 3 | 3 = 803), field 9 as bytes, and field
      // 100's end-group tag (100 << 3 | 4 = 804). The walk sees only fields
      // the schema names, so without this rule the key would pass.
      final inGroup = _concat([
        keyless,
        [0xA3, 0x06],
        lengthDelimitedHeader(9, key.length),
        key,
        [0xA4, 0x06],
      ]);
      expect(() => checkKeylessInput(inGroup, evmFamily), _tampered());
      try {
        checkKeylessInput(inGroup, evmFamily);
      } on InvalidInputError catch (error) {
        expect(error.message, contains('unknown field'));
        expectRedacted(error, [_hex(key)]);
      }
      // A group under a known field number (10, `transaction`, a message):
      // the wire-type mismatch leaves it unknown, and it is rejected too.
      expect(
        () => checkKeylessInput(
          _concat([
            keyless,
            [0x53],
            lengthDelimitedHeader(9, key.length),
            key,
            [0x54],
          ]),
          evmFamily,
        ),
        _tampered(),
      );
      // A harmless unknown varint is rejected as well: nothing unseen passes.
      expect(
        () => checkKeylessInput(
          _concat([
            keyless,
            [0xA0, 0x06, 0x01],
          ]),
          evmFamily,
        ),
        _tampered(),
      );
      // At depth: field 9 as an unknown field of the nested Transfer.
      final nested = eth.SigningInput.fromBuffer(keyless);
      nested.transaction.transfer.unknownFields.mergeLengthDelimitedField(
        9,
        key,
      );
      expect(
        () => checkKeylessInput(nested.writeToBuffer(), evmFamily),
        _tampered(),
      );
      // The unaltered key-less input still passes.
      expect(() => checkKeylessInput(keyless, evmFamily), returnsNormally);
    });

    test('rejects bytes that do not decode, and never throws anything '
        'else on random bytes', () {
      expect(
        () => checkKeylessInput(Uint8List.fromList([0x0a, 0x05, 1]), evmFamily),
        _tampered(),
      );
      final random = Random(9);
      for (var i = 0; i < 2000; i++) {
        final bytes = Uint8List.fromList(
          List<int>.generate(random.nextInt(64), (_) => random.nextInt(256)),
        );
        try {
          checkKeylessInput(bytes, evmFamily);
        } on InvalidInputError {
          // expected
        }
      }
    });
  });

  group('parseSigningOutput', () {
    final usedKeys = {KeyLocator.imported(issueKeyRef(1))};

    EvmSignResultParse parse(List<int> bytes) =>
        () => evmFamily.parseSigningOutput(
          Uint8List.fromList(bytes),
          coin: Coin.ethereum,
          usedKeys: usedKeys,
        );

    test('maps an error code to SigningError with upstream code and message '
        'verbatim, even beside a plausible encoded', () {
      final output = eth.SigningOutput(
        encoded: [0x02, 0xf8],
        r: List<int>.filled(32, 1),
        errorMessage: 'Invalid private key',
      );
      // Field 6 (varint) = 15, `Error_invalid_private_key` in Common.proto.
      final bytes = _concat([
        output.writeToBuffer(),
        [0x30, 0x0f],
      ]);
      expect(eth.SigningOutput.fromBuffer(bytes).error.value, 15);
      expect(
        parse(bytes),
        throwsA(
          isA<SigningError>()
              .having((e) => e.upstreamCode, 'upstreamCode', 15)
              .having((e) => e.message, 'message', 'Invalid private key'),
        ),
      );
    });

    test('maps an error code this build does not know, which would '
        'otherwise read as OK', () {
      // Field 6 (varint) = 999, field 7 = "x", and an encoded.
      final bytes = _concat([
        [0x0a, 0x01, 0x02],
        [0x30, 0xe7, 0x07],
        [0x3a, 0x01, 0x78],
      ]);
      expect(eth.SigningOutput.fromBuffer(bytes).error.value, 0);
      expect(
        parse(bytes),
        throwsA(
          isA<SigningError>()
              .having((e) => e.upstreamCode, 'upstreamCode', 999)
              .having((e) => e.message, 'message', 'x'),
        ),
      );
    });

    test('rejects empty bytes: success with nothing encoded', () {
      expect(parse(const []), _malformed());
    });

    test('rejects bytes that do not decode', () {
      expect(parse(const [0x0a, 0x05, 0x01]), _malformed());
      expect(parse(const [0xff, 0xff, 0xff, 0xff, 0xff, 0xff]), _malformed());
    });

    test('rejects an over-long signature component', () {
      final output = eth.SigningOutput(
        encoded: [0x02],
        r: List<int>.filled(33, 1),
      );
      expect(parse(output.writeToBuffer()), _malformed());
    });

    test('rejects a field an Ethereum SigningOutput does not have', () {
      final output = eth.SigningOutput(encoded: [0x02]);
      expect(
        parse(_concat([output.writeToBuffer(), lengthDelimitedHeader(20, 0)])),
        _malformed(),
      );
    });

    test('rejects an error field of the wrong wire type', () {
      // Field 6 as fixed32 (wire type 5): tag 0x35 and four bytes.
      expect(
        parse(
          _concat([
            [0x0a, 0x01, 0x02],
            [0x35, 0x01, 0x00, 0x00, 0x00],
          ]),
        ),
        _malformed(),
      );
    });

    test('parses a well-formed output into a result with its own copies', () {
      final output = eth.SigningOutput(
        encoded: [0x02, 0xf8, 0x71],
        v: [0],
        r: List<int>.filled(32, 0x92),
        s: List<int>.filled(32, 0x64),
        preHash: List<int>.filled(32, 0xaa),
      );
      final result = parse(output.writeToBuffer())();
      expect(result.encoded, [0x02, 0xf8, 0x71]);
      expect(result.v, [0]);
      expect(result.r, List<int>.filled(32, 0x92));
      expect(result.s, List<int>.filled(32, 0x64));
      expect(result.preHash, List<int>.filled(32, 0xaa));
      expect(result.coin, Coin.ethereum);
      expect(result.usedKeys, usedKeys);
    });

    test('random bytes only ever produce a result or a SigningError', () {
      final random = Random(1442);
      for (var i = 0; i < 2000; i++) {
        final bytes = List<int>.generate(
          random.nextInt(64),
          (_) => random.nextInt(256),
        );
        try {
          parse(bytes)();
        } on SigningError {
          // expected
        }
      }
    });
  });

  test('lengthDelimitedHeader writes the tag and length varints', () {
    expect(lengthDelimitedHeader(9, 32), [0x4a, 0x20]);
    expect(lengthDelimitedHeader(1, 300), [0x0a, 0xac, 0x02]);
    expect(lengthDelimitedHeader(17, 0), [0x8a, 0x01, 0x00]);
    expect(() => lengthDelimitedHeader(0, 1), throwsRangeError);
  });

  test('decodeSigningInput yields the named message', () {
    final GeneratedMessage message = evmFamily.decodeSigningInput(
      evmFamily.encodeKeylessInput(vectorRequest(input)),
    );
    expect(message.info_.qualifiedMessageName, evmFamily.signingInputMessage);
  });
}

typedef EvmSignResultParse = EvmSignResult Function();
