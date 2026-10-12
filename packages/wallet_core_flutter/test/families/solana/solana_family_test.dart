// The Solana family and the key-field check, without native code: key-less
// encoding against the vector's inputs, the reviewed key-field list against
// the generated one, the tamper check on bytes (the nested nonce-account key
// included), the fee-payer slot, and output parsing on hand-built, empty and
// garbage outputs. Pure Dart.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/protobuf.dart' show BuilderInfo, GeneratedMessage;
// ignore: implementation_imports
import 'package:wallet_core_flutter_bindings/src/generated/proto/Solana.pb.dart'
    as sol;
// ignore: implementation_imports
import 'package:wallet_core_flutter_bindings/src/generated/proto/Solana.pbenum.dart'
    as sol_enum;
import 'package:wallet_core_flutter/src/errors/errors.dart';
import 'package:wallet_core_flutter/src/families/families.dart';
import 'package:wallet_core_flutter/src/families/family.dart';
import 'package:wallet_core_flutter/src/families/solana/solana_family.dart';
import 'package:wallet_core_flutter/src/requests/requests.dart';
import 'package:wallet_core_flutter/src/signing/key_field_check.dart';
import 'package:wallet_core_flutter/src/signing/key_locator.dart';
import 'package:wallet_core_flutter/src/signing/sign_result.dart';
import 'package:wallet_core_flutter/src/signing/signing_core.dart'
    show lengthDelimitedHeader;
import 'package:wallet_core_flutter/wallet_core_flutter.dart' show Coin;

import '../../support/fixtures.dart';
import '../../support/host_library.dart';
import 'solana_support.dart';

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

Uint8List _concat(List<List<int>> parts) =>
    Uint8List.fromList([for (final part in parts) ...part]);

void main() {
  late Map<dynamic, dynamic> input;
  late Map<dynamic, dynamic> expected;

  setUpAll(() {
    final vector = vectorById(loadInventory(), signVectorId);
    input = vector.input as Map;
    expected = vector.expected as Map;
  });

  group('encodeKeylessInput', () {
    test("re-decodes to the vector's inputs: a transfer, a blockhash and "
        'nothing else', () {
      final bytes = solanaFamily.encodeKeylessInput(vectorRequest(input));
      final decoded = sol.SigningInput.fromBuffer(bytes);
      expect(
        decoded.whichTransactionType(),
        sol.SigningInput_TransactionType.transferTransaction,
      );
      expect(decoded.transferTransaction.recipient, input['to_address']);
      expect(
        decoded.transferTransaction.value.toInt(),
        int.parse(input['lamports'] as String),
      );
      expect(decoded.transferTransaction.memo, isEmpty);
      expect(decoded.transferTransaction.references, isEmpty);
      expect(decoded.recentBlockhash, input['recent_blockhash']);
      // Everything else stays at upstream's default: base58, a legacy
      // message, no sender, no durable nonce, no fee payer, no priority fee.
      expect(decoded.txEncoding, sol_enum.Encoding.Base58);
      expect(decoded.v0Msg, isFalse);
      expect(decoded.sender, isEmpty);
      expect(decoded.nonceAccount, isEmpty);
      expect(decoded.feePayer, isEmpty);
      expect(decoded.hasPriorityFeePrice(), isFalse);
      expect(decoded.hasPriorityFeeLimit(), isFalse);
      expect(decoded.hasRawMessage(), isFalse);
      expect(decoded.hasTransferToFeePayer(), isFalse);
      expect(decoded.unknownFields.isEmpty, isTrue);
    });

    test('the wire bytes are the blockhash (field 2) then the transfer '
        '(field 4: recipient 1, value 2), as upstream\'s test builds it', () {
      final request = vectorRequest(input);
      final to = utf8.encode(request.to);
      final hash = utf8.encode(request.recentBlockhash);
      final transfer = [
        0x0a, to.length, ...to, // recipient
        0x10, request.lamports, // value, a one-byte varint for 42
      ];
      expect(request.lamports, lessThan(128));
      expect(solanaFamily.encodeKeylessInput(request), [
        0x12, hash.length, ...hash, //
        0x22, transfer.length, ...transfer,
      ]);
    });

    test('sets no key field: the generated accessor, the reviewed list and '
        'the wire tag all agree', () {
      final bytes = solanaFamily.encodeKeylessInput(vectorRequest(input));
      final decoded = sol.SigningInput.fromBuffer(bytes);
      expect(decoded.hasPrivateKey(), isFalse);
      expect(decoded.hasFeePayerPrivateKey(), isFalse);
      expect(decoded.getFieldOrNull(1), isNull);
      expect(decoded.getFieldOrNull(17), isNull);
      expect(solanaFamily.keyFields.presentIn(decoded), isEmpty);
      expect(() => checkKeylessInput(bytes, solanaFamily), returnsNormally);
    });

    test('a zero amount and the largest amount encode exactly', () {
      for (final lamports in [0, 127, 128, 0x7FFFFFFFFFFFFFFF]) {
        final request = SolanaTransactionRequest.transfer(
          to: input['to_address'] as String,
          lamports: lamports,
          recentBlockhash: input['recent_blockhash'] as String,
        );
        final decoded = sol.SigningInput.fromBuffer(
          familyFor(request).encodeKeylessInput(request),
        );
        expect(
          decoded.transferTransaction.value.toInt(),
          lamports,
          reason: '$lamports',
        );
      }
    });

    test('is deterministic', () {
      final request = vectorRequest(input);
      expect(
        solanaFamily.encodeKeylessInput(request),
        solanaFamily.encodeKeylessInput(request),
      );
    });
  });

  group('the roles and the key slots', () {
    test('a transfer needs exactly the primary role', () {
      expect(solanaFamily.requiredRoles(vectorRequest(input)), [
        KeyRole.primary,
      ]);
    });

    test('familyFor maps the request to the Solana family', () {
      expect(familyFor(vectorRequest(input)), same(solanaFamily));
      expect(solanaFamily.chainFamily.id, 'solana');
      expect(solanaFamily.signingInputMessage, 'TW.Solana.Proto.SigningInput');
    });

    test('primary is private_key (1) and feePayer is fee_payer_private_key '
        '(17), both of the signing input itself; any other role has no '
        'slot', () {
      final info = sol.SigningInput.getDefault().info_;
      final primary = solanaFamily.injectionField(KeyRole.primary);
      final feePayer = solanaFamily.injectionField(KeyRole.feePayer);
      expect(primary.fieldNumber, info.byName['privateKey']!.tagNumber);
      expect(primary.fieldNumber, 1);
      expect(
        feePayer.fieldNumber,
        info.byName['feePayerPrivateKey']!.tagNumber,
      );
      expect(feePayer.fieldNumber, 17);
      for (final entry in [primary, feePayer]) {
        expect(entry.messagePath, solanaFamily.signingInputMessage);
        expect(entry.repeated, isFalse);
        expect(solanaFamily.keyFields.entries, contains(entry));
      }
      expect(primary, isNot(feePayer));
      expect(
        () => solanaFamily.injectionField(KeyRole.input(0)),
        throwsArgumentError,
      );
    });
  });

  group('the reviewed key-field list', () {
    test('equals the generated key_fields.json for every Solana message and '
        'every message reachable from the signing input', () {
      final root = repositoryRoot()!;
      final generated = jsonDecode(
        File(
          '${root.path}/packages/wallet_core_flutter_bindings/lib/src/'
          'generated/proto/key_fields.json',
        ).readAsStringSync(),
      ) as Map<String, dynamic>;
      final messages = generated['messages'] as Map<String, dynamic>;
      final byFile = generated['byFile'] as Map<String, dynamic>;

      // Every message reachable from the signing input, by a recursive walk
      // of the generated schema — Solana's nonce-account key is one message
      // down, and a top-level scan would miss it (DECISION-13 §3.1).
      final reachable = <String>{};
      void walk(BuilderInfo info) {
        if (!reachable.add(info.qualifiedMessageName)) return;
        for (final field in info.byIndex) {
          final sub = field.subBuilder;
          if (sub != null) walk(sub().info_);
        }
      }

      walk(sol.SigningInput.getDefault().info_);
      expect(reachable, contains('TW.Solana.Proto.CreateNonceAccount'));

      final wanted = <String>{
        ...(byFile['Solana.proto'] as List<dynamic>).cast<String>(),
        ...reachable.where(messages.containsKey),
      };
      final expectedEntries = <KeyFieldEntry>{
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
      expect(solanaFamily.keyFields.entries.toSet(), expectedEntries);
      expect(solanaFamily.keyFields.entries, hasLength(expectedEntries.length));
      // Pinned by name as well: the two injected fields and the nested one.
      expect(
        solanaFamily.keyFields.entries.map((e) => e.toString()),
        containsAll(<String>[
          'TW.Solana.Proto.SigningInput.private_key = 1',
          'TW.Solana.Proto.SigningInput.fee_payer_private_key = 17',
          'TW.Solana.Proto.CreateNonceAccount.nonce_account_private_key = 3',
        ]),
      );
    });
  });

  group('the key-field check on bytes', () {
    late Uint8List keyless;
    final key = List<int>.generate(32, (i) => 0x40 + i);

    setUp(
      () => keyless = solanaFamily.encodeKeylessInput(vectorRequest(input)),
    );

    test('rejects bytes carrying private_key, without naming its value', () {
      final tampered = _concat([
        keyless,
        lengthDelimitedHeader(1, key.length),
        key,
      ]);
      expect(() => checkKeylessInput(tampered, solanaFamily), _tampered());
      try {
        checkKeylessInput(tampered, solanaFamily);
      } on InvalidInputError catch (error) {
        expect(error.message, contains('private_key'));
        expectRedacted(error, [
          key.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
          String.fromCharCodes(key),
        ]);
      }
    });

    test('rejects bytes carrying fee_payer_private_key', () {
      final tampered = _concat([
        keyless,
        lengthDelimitedHeader(17, key.length),
        key,
      ]);
      expect(() => checkKeylessInput(tampered, solanaFamily), _tampered());
      try {
        checkKeylessInput(tampered, solanaFamily);
      } on InvalidInputError catch (error) {
        expect(error.message, contains('fee_payer_private_key'));
      }
    });

    test('rejects the nested nonce_account_private_key, which only a '
        'recursive walk finds', () {
      final message = sol.SigningInput.fromBuffer(keyless)
        ..createNonceAccount = sol.CreateNonceAccount(
          nonceAccount: input['to_address'] as String,
          nonceAccountPrivateKey: key,
        );
      final tampered = message.writeToBuffer();
      expect(() => checkKeylessInput(tampered, solanaFamily), _tampered());
      try {
        checkKeylessInput(tampered, solanaFamily);
      } on InvalidInputError catch (error) {
        expect(error.message, contains('nonce_account_private_key'));
      }
      // The same message without the key passes the key check: the oneof's
      // other members are not what is being refused.
      final withoutKey = sol.SigningInput.fromBuffer(keyless)
        ..createNonceAccount = sol.CreateNonceAccount(
          nonceAccount: input['to_address'] as String,
        );
      expect(
        solanaFamily.keyFields.presentIn(withoutKey),
        isEmpty,
        reason: 'no key field is set',
      );
    });

    test('rejects private_key set by the generated setters and serialized', () {
      final message = sol.SigningInput.fromBuffer(keyless)
        ..privateKey = List<int>.filled(32, 1);
      expect(
        () => checkKeylessInput(message.writeToBuffer(), solanaFamily),
        _tampered(),
      );
      final feePayer = sol.SigningInput.fromBuffer(keyless)
        ..feePayerPrivateKey = List<int>.filled(32, 1);
      expect(
        () => checkKeylessInput(feePayer.writeToBuffer(), solanaFamily),
        _tampered(),
      );
    });

    test('rejects a present but empty key field, and a zero-byte input', () {
      for (final number in [1, 17]) {
        expect(
          () => checkKeylessInput(
            _concat([keyless, lengthDelimitedHeader(number, 0)]),
            solanaFamily,
          ),
          _tampered(),
          reason: 'field $number',
        );
      }
      expect(() => checkKeylessInput(Uint8List(0), solanaFamily), _tampered());
    });

    test('rejects bytes that do not decode, and never throws anything else '
        'on random bytes', () {
      expect(
        () => checkKeylessInput(
          Uint8List.fromList([0x0a, 0x05, 1]),
          solanaFamily,
        ),
        _tampered(),
      );
      final random = Random(9);
      for (var i = 0; i < 2000; i++) {
        final bytes = Uint8List.fromList(
          List<int>.generate(random.nextInt(64), (_) => random.nextInt(256)),
        );
        try {
          checkKeylessInput(bytes, solanaFamily);
        } on InvalidInputError {
          // expected
        }
      }
    });
  });

  group('parseSigningOutput', () {
    final usedKeys = {KeyLocator.imported(issueKeyRef(1))};

    SolanaSignResult Function() parse(List<int> bytes) =>
        () => solanaFamily.parseSigningOutput(
          Uint8List.fromList(bytes),
          coin: Coin.solana,
          usedKeys: usedKeys,
        );

    test('maps an error code to SigningError with upstream code and message '
        'verbatim, even beside a plausible encoded', () {
      final output = sol.SigningOutput(
        encoded: input['to_address'] as String,
        errorMessage: 'Invalid private key',
      );
      // Field 2 (varint) = 15, `Error_invalid_private_key` in Common.proto.
      final bytes = _concat([
        output.writeToBuffer(),
        [0x10, 0x0f],
      ]);
      expect(sol.SigningOutput.fromBuffer(bytes).error.value, 15);
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
      // Encoded "1", error (field 2) = 999, message (field 3) = "x".
      final bytes = _concat([
        [0x0a, 0x01, 0x31],
        [0x10, 0xe7, 0x07],
        [0x1a, 0x01, 0x78],
      ]);
      expect(sol.SigningOutput.fromBuffer(bytes).error.value, 0);
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

    test('rejects an encoded or unsigned_tx that is not base58, or is '
        'too long', () {
      for (final bad in ['0OIl', 'abc def', 'ab+/=', '${'1' * 10}é']) {
        expect(
          parse(sol.SigningOutput(encoded: bad).writeToBuffer()),
          _malformed(),
          reason: 'encoded "$bad"',
        );
        expect(
          parse(
            sol.SigningOutput(encoded: '1', unsignedTx: bad).writeToBuffer(),
          ),
          _malformed(),
          reason: 'unsigned_tx "$bad"',
        );
      }
      expect(
        parse(
          sol.SigningOutput(encoded: '1' * (maxSolanaEncodedChars + 1))
              .writeToBuffer(),
        ),
        _malformed(),
      );
      expect(
        parse(
          sol.SigningOutput(
            encoded: '1',
            unsignedTx: '1' * (maxSolanaEncodedChars + 1),
          ).writeToBuffer(),
        ),
        _malformed(),
      );
      expect(
        parse(
          sol.SigningOutput(encoded: '1' * maxSolanaEncodedChars)
              .writeToBuffer(),
        )().encoded,
        hasLength(maxSolanaEncodedChars),
      );
    });

    test('rejects a field a Solana SigningOutput does not have', () {
      final output = sol.SigningOutput(encoded: '1');
      expect(
        parse(_concat([output.writeToBuffer(), lengthDelimitedHeader(20, 0)])),
        _malformed(),
      );
    });

    test('rejects an error field of the wrong wire type', () {
      // Field 2 as fixed32 (wire type 5): tag 0x15 and four bytes.
      expect(
        parse(
          _concat([
            [0x0a, 0x01, 0x31],
            [0x15, 0x01, 0x00, 0x00, 0x00],
          ]),
        ),
        _malformed(),
      );
    });

    test('bounds the reported signatures: count, length and alphabet', () {
      final good = sol.PubkeySignature(
        pubkey: input['to_address'] as String,
        signature: expected['encoded'].toString().substring(0, 88),
      );
      expect(
        parse(
          sol.SigningOutput(encoded: '1', signatures: [good]).writeToBuffer(),
        ),
        returnsNormally,
      );
      expect(
        parse(
          sol.SigningOutput(
            encoded: '1',
            signatures: List.filled(maxSolanaSignatures + 1, good),
          ).writeToBuffer(),
        ),
        _malformed(),
      );
      expect(
        parse(
          sol.SigningOutput(
            encoded: '1',
            signatures: [
              sol.PubkeySignature(pubkey: '1', signature: '1' * 129),
            ],
          ).writeToBuffer(),
        ),
        _malformed(),
      );
      expect(
        parse(
          sol.SigningOutput(
            encoded: '1',
            signatures: [sol.PubkeySignature(pubkey: '0', signature: '1')],
          ).writeToBuffer(),
        ),
        _malformed(),
      );
    });

    test('parses a well-formed output into a result carrying exactly '
        "upstream's strings, the vector's among them", () {
      final output = sol.SigningOutput(
        encoded: expected['encoded'] as String,
        unsignedTx: expected['unsigned_tx'] as String,
      );
      final result = parse(output.writeToBuffer())();
      expect(result.encoded, expected['encoded']);
      expect(result.unsignedTransaction, expected['unsigned_tx']);
      expect(result.encoding, SolanaEncoding.base58);
      expect(result.coin, Coin.solana);
      expect(result.usedKeys, usedKeys);
      expect(result.toString(), isNot(contains(result.encoded)));
    });

    test('an output without unsigned_tx has none', () {
      final result = parse(sol.SigningOutput(encoded: '1').writeToBuffer())();
      expect(result.unsignedTransaction, isNull);
    });

    test(
      'withUsedKeys puts the caller\'s locators back on a Solana result',
      () {
        final result = parse(
          sol.SigningOutput(encoded: '1', unsignedTx: '2').writeToBuffer(),
        )();
        final other = {KeyLocator.imported(issueKeyRef(2))};
        final swapped = withUsedKeys(result, other) as SolanaSignResult;
        expect(swapped.usedKeys, other);
        expect(swapped.encoded, '1');
        expect(swapped.unsignedTransaction, '2');
        expect(swapped.coin, Coin.solana);
        expect(
          () => swapped.usedKeys.add(KeyLocator.imported(issueKeyRef(3))),
          throwsUnsupportedError,
        );
      },
    );

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

  test('decodeSigningInput yields the named message', () {
    final GeneratedMessage message = solanaFamily.decodeSigningInput(
      solanaFamily.encodeKeylessInput(vectorRequest(input)),
    );
    expect(
      message.info_.qualifiedMessageName,
      solanaFamily.signingInputMessage,
    );
  });

  test('the family is a TransactionFamily of its own request and result', () {
    const TransactionFamily<SolanaTransactionRequest, SolanaSignResult> family =
        solanaFamily;
    expect(
      family,
      isA<TransactionFamily<SolanaTransactionRequest, SolanaSignResult>>(),
    );
  });
}
