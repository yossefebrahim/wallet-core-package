/// The UTXO family, without native code: key-less encoding of a vector's
/// request, the reviewed key-field list against the generated one, the roles
/// and injection field, the tamper check, and parsing of upstream's signing
/// output and plan on hand-built, hostile, and garbage bytes. Pure Dart.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/protobuf.dart' show BuilderInfo;
import 'package:wallet_core_flutter/src/errors/errors.dart';
import 'package:wallet_core_flutter/src/families/families.dart';
import 'package:wallet_core_flutter/src/families/family.dart';
import 'package:wallet_core_flutter/src/families/utxo/utxo_family.dart';
import 'package:wallet_core_flutter/src/requests/requests.dart';
import 'package:wallet_core_flutter/src/signing/key_field_check.dart';
import 'package:wallet_core_flutter/src/signing/key_locator.dart';
import 'package:wallet_core_flutter/src/signing/sign_result.dart';
import 'package:wallet_core_flutter/src/signing/signing_core.dart'
    show lengthDelimitedHeader;
import 'package:wallet_core_flutter/wallet_core_flutter.dart' show Coin;
// ignore: implementation_imports
import 'package:wallet_core_flutter_bindings/src/generated/proto/Bitcoin.pb.dart'
    as btc;
// ignore: implementation_imports
import 'package:wallet_core_flutter_bindings/src/generated/proto/BitcoinV2.pb.dart'
    as v2;
// ignore: implementation_imports
import 'package:wallet_core_flutter_bindings/src/generated/proto/Common.pbenum.dart'
    as common;

import '../../support/fixtures.dart';
import '../../support/host_library.dart';
import 'utxo_vector.dart';

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

/// A zero `Int64` of the generated classes, so that the test needs no import
/// of `package:fixnum` either.
final _zero = btc.SigningInput().amount;

const String _goodTxid =
    '5d6bf53576a54be4d92cd8abf58d28ecc9ea7956eaf970d24d6bfcb9fcfe9855';

void main() {
  late Map<dynamic, dynamic> planInput;
  late Map<dynamic, dynamic> signInput;
  late Map<dynamic, dynamic> signExpected;

  setUpAll(() {
    final inventory = loadInventory();
    planInput = vectorById(inventory, 'bitcoin-plan-p2wpkh-1').input as Map;
    signInput = vectorById(inventory, 'bitcoin-sign-p2wpkh-1').input as Map;
    signExpected =
        vectorById(inventory, 'bitcoin-sign-p2wpkh-1').expected as Map;
  });

  UtxoTransactionRequest requestOf() => VectorRequest.of(signInput).request;

  group('the key-less input', () {
    test('is upstream\'s SigningInput for the vector\'s request: every '
        'field the family sets, and nothing else', () {
      final request = requestOf();
      final keyless = utxoFamily.encodeKeylessInput(request);
      final decoded = btc.SigningInput.fromBuffer(keyless);

      expect(decoded.hashType, 1, reason: 'SIGHASH_ALL');
      expect(decoded.amount.toString(), signInput['amount']);
      expect(decoded.byteFee.toString(), signInput['byte_fee']);
      expect(decoded.toAddress, signInput['to_address']);
      expect(decoded.changeAddress, signInput['change_address']);
      expect(decoded.useMaxAmount, signInput['use_max_amount']);
      expect(decoded.coinType, 0, reason: 'Bitcoin');
      expect(decoded.privateKey, isEmpty);
      expect(decoded.scripts, isEmpty);
      expect(decoded.hasPlan(), isFalse);
      expect(decoded.hasSigningV2(), isFalse);
      expect(decoded.hasFixedDustThreshold(), isFalse);
      expect(decoded.outputOpReturn, isEmpty);
      expect(decoded.extraOutputs, isEmpty);
      expect(decoded.lockTime, 0);

      final utxos = signInput['utxos'] as List<dynamic>;
      expect(decoded.utxo, hasLength(utxos.length));
      for (var i = 0; i < utxos.length; i++) {
        final fields = utxos[i] as Map<dynamic, dynamic>;
        final utxo = decoded.utxo[i];
        // The id is shown in the opposite order to the one upstream wants.
        expect(
          hexOf(utxo.outPoint.hash),
          reversedHex(fields['txid'] as String),
        );
        expect(utxo.outPoint.index.toString(), fields['index']);
        expect(utxo.outPoint.sequence, 0xFFFFFFFF);
        expect(hexOf(utxo.script), fields['script_pub_key']);
        expect(utxo.amount.toString(), fields['amount']);
      }
    });

    test('is a pure function of the request', () {
      final request = requestOf();
      expect(
        utxoFamily.encodeKeylessInput(request),
        utxoFamily.encodeKeylessInput(request),
      );
    });

    test('a request with a plan carries the plan and spends its inputs, in '
        'its order', () {
      final request = requestOf();
      final plan = UtxoPlan(
        selectedInputs: [request.inputs[1], request.inputs[0]],
        amount: 28035,
        availableAmount: 35132,
        fee: 7097,
        change: 0,
      );
      final decoded = btc.SigningInput.fromBuffer(
        utxoFamily.encodeKeylessInput(request.withPlan(plan)),
      );
      expect(decoded.hasPlan(), isTrue);
      expect(decoded.plan.amount.toString(), '28035');
      expect(decoded.plan.availableAmount.toString(), '35132');
      expect(decoded.plan.fee.toString(), '7097');
      expect(decoded.plan.change.toString(), '0');
      expect(decoded.plan.utxos.map((u) => u.amount.toString()), [
        '4863',
        '30269',
      ]);
      expect(decoded.utxo.map((u) => u.amount.toString()), ['4863', '30269']);
      expect(decoded.plan.hasError(), isFalse);
    });

    test('passes the key-field check: decodes, carries no key field', () {
      final keyless = utxoFamily.encodeKeylessInput(requestOf());
      expect(() => checkKeylessInput(keyless, utxoFamily), returnsNormally);
      expect(
        utxoFamily.keyFields.presentIn(utxoFamily.decodeSigningInput(keyless)),
        isEmpty,
      );
    });
  });

  group('routing, roles, and the injection field', () {
    test('familyFor maps a UTXO request to the UTXO family', () {
      expect(familyFor(requestOf()), same(utxoFamily));
    });

    test('the roles are one per distinct key, in the order of the '
        'request\'s locators', () {
      final request = requestOf();
      expect(utxoFamily.requiredRoles(request), [KeyRole.input(0)]);
      expect(
        utxoFamily.requiredRoles(request),
        request.keyLocators.map((l) => l.role),
      );
    });

    test('every input role injects into private_key (6, repeated) of the '
        'signing input; no other role has a slot', () {
      for (final n in [0, 1, 17, 999]) {
        final field = utxoFamily.injectionField(KeyRole.input(n));
        expect(field.messagePath, utxoFamily.signingInputMessage);
        expect(field.fieldName, 'private_key');
        expect(field.fieldNumber, 6);
        expect(field.repeated, isTrue);
        expect(
          field.fieldNumber,
          btc.SigningInput.getDefault().info_.byName['privateKey']!.tagNumber,
        );
      }
      expect(
        () => utxoFamily.injectionField(KeyRole.primary),
        throwsArgumentError,
      );
      expect(
        () => utxoFamily.injectionField(KeyRole.feePayer),
        throwsArgumentError,
      );
    });
  });

  group('the reviewed key-field list', () {
    test('equals the generated key_fields.json for every Bitcoin message '
        'and every message reachable from the signing input', () {
      final root = repositoryRoot()!;
      final generated = jsonDecode(
        File(
          '${root.path}/packages/wallet_core_flutter_bindings/lib/src/'
          'generated/proto/key_fields.json',
        ).readAsStringSync(),
      ) as Map<String, dynamic>;
      final messages = generated['messages'] as Map<String, dynamic>;
      final byFile = generated['byFile'] as Map<String, dynamic>;

      final reachable = <String>{};
      void walk(BuilderInfo info) {
        if (!reachable.add(info.qualifiedMessageName)) return;
        for (final field in info.byIndex) {
          final sub = field.subBuilder;
          if (sub != null) walk(sub().info_);
        }
      }

      walk(btc.SigningInput.getDefault().info_);
      // `signing_v2` reaches BitcoinV2's own signing input and its key field.
      expect(reachable, contains('TW.BitcoinV2.Proto.SigningInput'));

      final wanted = <String>{
        ...(byFile['Bitcoin.proto'] as List<dynamic>).cast<String>(),
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
      expect(utxoFamily.keyFields.entries.toSet(), expected);
      expect(utxoFamily.keyFields.entries, hasLength(expected.length));
    });
  });

  group('the key-field check on bytes', () {
    late Uint8List keyless;

    setUp(() => keyless = utxoFamily.encodeKeylessInput(requestOf()));

    test('rejects key-less bytes that already carry a private_key', () {
      final tampered = Uint8List.fromList([
        ...lengthDelimitedHeader(6, 32),
        ...List<int>.filled(32, 0xAB),
        ...keyless,
      ]);
      expect(() => checkKeylessInput(tampered, utxoFamily), _tampered());
    });

    test('rejects a BitcoinV2 signing input, whose own key field would '
        'be signed with', () {
      final message = btc.SigningInput.fromBuffer(keyless)
        ..signingV2 = v2.SigningInput(privateKeys: [List<int>.filled(32, 1)]);
      expect(
        () => checkKeylessInput(message.writeToBuffer(), utxoFamily),
        _tampered(),
      );
    });

    test('rejects bytes that do not decode', () {
      expect(
        () => checkKeylessInput(
          Uint8List.fromList([0x32, 0xFF, 0x01]),
          utxoFamily,
        ),
        _tampered(),
      );
    });
  });

  group('parseSigningOutput', () {
    UtxoSignResult parse(Uint8List bytes) => utxoFamily.parseSigningOutput(
      bytes,
      coin: Coin.bitcoin,
      usedKeys: const <KeyLocator>{},
    );

    Uint8List output({
      List<int>? encoded,
      String? id,
      common.SigningError? error,
      String? message,
    }) => btc.SigningOutput(
      encoded: encoded ?? [1, 2, 3],
      transactionId: id ?? _goodTxid,
      error: error,
      errorMessage: message,
    ).writeToBuffer();

    test('reads a well-formed output into a result', () {
      final result = parse(output(encoded: [9, 8, 7]));
      expect(result.encoded, [9, 8, 7]);
      expect(result.transactionId, _goodTxid);
      expect(result.coin, Coin.bitcoin);
      expect(result.usedKeys, isEmpty);
      expect(() => result.encoded.add(1), throwsUnsupportedError);
    });

    test('maps upstream\'s error, code and message verbatim, before reading '
        'anything else', () {
      expect(
        () => parse(
          output(
            encoded: [],
            id: 'not a txid',
            error: common.SigningError.Error_missing_private_key,
            message: 'Error_missing_private_key',
          ),
        ),
        throwsA(
          isA<SigningError>()
              .having(
                (e) => e.upstreamCode,
                'upstreamCode',
                common.SigningError.Error_missing_private_key.value,
              )
              .having((e) => e.message, 'message', 'Error_missing_private_key'),
        ),
      );
    });

    test('an error code this build does not know is still an error, not '
        'success', () {
      // Field 4 (error) as a varint: 0x20 0x7F is code 127.
      final bytes = Uint8List.fromList([
        0x20,
        0x7F,
        ...btc.SigningOutput(
          encoded: [1],
          transactionId: _goodTxid,
        ).writeToBuffer(),
      ]);
      expect(
        () => parse(bytes),
        throwsA(
          isA<SigningError>().having(
            (e) => e.upstreamCode,
            'upstreamCode',
            127,
          ),
        ),
      );
    });

    test('rejects what is not the output asked for, as malformed', () {
      expect(() => parse(output(encoded: [])), _malformed());
      expect(() => parse(Uint8List(0)), _malformed());
      expect(() => parse(output(id: 'ABC')), _malformed());
      expect(() => parse(output(id: _goodTxid.toUpperCase())), _malformed());
      expect(() => parse(output(id: '${_goodTxid}0')), _malformed());
      expect(
        () => parse(
          (btc.SigningOutput.fromBuffer(
            output(),
          )..signingResultV2 = v2.SigningOutput()).writeToBuffer(),
        ),
        _malformed(),
      );
      // An unknown field.
      expect(
        () => parse(Uint8List.fromList([...output(), 0x50, 0x01])),
        _malformed(),
      );
      // The error field (4) with the wrong wire type: as a fixed32, tag 0x25.
      expect(
        () => parse(Uint8List.fromList([0x25, 1, 2, 3, 4, ...output()])),
        _malformed(),
      );
    });

    test('never throws anything but SigningError, whatever the bytes', () {
      final random = Random(0xB17C01);
      for (var i = 0; i < 400; i++) {
        final bytes = Uint8List.fromList([
          for (var j = 0; j < random.nextInt(64); j++) random.nextInt(256),
        ]);
        try {
          parse(bytes);
        } on SigningError {
          // expected
        }
      }
    });
  });

  group('parsePlan', () {
    late UtxoTransactionRequest request;
    setUp(() => request = VectorRequest.of(planInput).request);

    btc.UnspentTransaction unspent(UtxoInput input, {int? amount}) =>
        btc.UnspentTransaction(
          outPoint: btc.OutPoint(
            hash: unhex(reversedHex(input.outPoint.transactionId)),
            index: input.outPoint.index,
            sequence: 0xFFFFFFFF,
          ),
          script: input.script,
          amount: _zero + (amount ?? input.amount),
        );

    btc.TransactionPlan planOf(
      List<UtxoInput> selected, {
      int amount = 28035,
      int available = 35132,
      int fee = 7097,
      int change = 0,
    }) => btc.TransactionPlan(
      amount: _zero + amount,
      availableAmount: _zero + available,
      fee: _zero + fee,
      change: _zero + change,
      utxos: selected.map(unspent),
    );

    UtxoPlan parse(btc.TransactionPlan plan) =>
        utxoFamily.parsePlan(plan.writeToBuffer(), request: request);

    test(
      'reads a plan into the request\'s own inputs, in upstream\'s order',
      () {
        final plan = parse(planOf([request.inputs[1], request.inputs[0]]));
        expect(plan.selectedInputs, [request.inputs[1], request.inputs[0]]);
        expect(plan.amount, 28035);
        expect(plan.availableAmount, 35132);
        expect(plan.fee, 7097);
        expect(plan.change, 0);
        // The very inputs the caller gave: they keep their locators.
        expect(identical(plan.selectedInputs[0], request.inputs[1]), isTrue);
      },
    );

    test('maps upstream\'s error, by name, before reading anything else', () {
      final bytes = btc.TransactionPlan(
        error: common.SigningError.Error_not_enough_utxos,
        utxos: [unspent(request.inputs[0], amount: 1)],
      ).writeToBuffer();
      expect(
        () => utxoFamily.parsePlan(bytes, request: request),
        throwsA(
          isA<SigningError>()
              .having(
                (e) => e.upstreamCode,
                'upstreamCode',
                common.SigningError.Error_not_enough_utxos.value,
              )
              .having((e) => e.message, 'message', 'Error_not_enough_utxos'),
        ),
      );
    });

    test('an error code this build does not know is still an error', () {
      // Field 7 (error) as a varint: 0x38 0x7F is code 127.
      final bytes = Uint8List.fromList([
        0x38,
        0x7F,
        ...planOf([request.inputs[0]]).writeToBuffer(),
      ]);
      expect(
        () => utxoFamily.parsePlan(bytes, request: request),
        throwsA(
          isA<SigningError>().having(
            (e) => e.upstreamCode,
            'upstreamCode',
            127,
          ),
        ),
      );
    });

    test('rejects a plan that selects what was not offered, twice, or '
        'something else, as malformed', () {
      final stranger = UtxoInput(
        outPoint: OutPoint(transactionId: 'ab' * 32, index: 0),
        amount: 1000,
        script: request.inputs[0].script,
        addressStyle: request.inputs[0].addressStyle,
        keyLocator: request.inputs[0].keyLocator,
      );
      expect(() => parse(planOf([stranger])), _malformed());
      expect(
        () => parse(planOf([request.inputs[0], request.inputs[0]])),
        _malformed(),
      );
      // Same outpoint, another amount.
      expect(
        () => parse(
          btc.TransactionPlan(utxos: [unspent(request.inputs[0], amount: 1)]),
        ),
        _malformed(),
      );
      // Same outpoint, another script.
      final otherScript = unspent(request.inputs[0])
        ..script = [0x00, 0x14, ...List.filled(20, 9)];
      expect(
        () => parse(btc.TransactionPlan(utxos: [otherScript])),
        _malformed(),
      );
      // A hash of the wrong length.
      final shortHash = unspent(request.inputs[0])..outPoint.hash = [1, 2, 3];
      expect(
        () => parse(btc.TransactionPlan(utxos: [shortHash])),
        _malformed(),
      );
    });

    test('rejects a plan that selects nothing, or whose amounts are out of '
        'range, or that carries fields this family never asks for', () {
      expect(() => parse(btc.TransactionPlan()), _malformed());
      expect(
        () => parse(planOf([request.inputs[0]], fee: maxUtxoAmount + 1)),
        _malformed(),
      );
      expect(
        () => parse(planOf([request.inputs[0]], change: -1)),
        _malformed(),
      );
      final withBranch = planOf([request.inputs[0]])..branchId = [1];
      expect(() => parse(withBranch), _malformed());
      final withV2 = planOf([request.inputs[0]])
        ..planningResultV2 = v2.TransactionPlan();
      expect(() => parse(withV2), _malformed());
      expect(
        () => utxoFamily.parsePlan(
          Uint8List.fromList([
            ...planOf([request.inputs[0]]).writeToBuffer(),
            0x50,
            0x01,
          ]),
          request: request,
        ),
        _malformed(),
      );
      // The error field (7) with the wrong wire type: as a fixed32, tag 0x3D.
      expect(
        () => utxoFamily.parsePlan(
          Uint8List.fromList([
            0x3D,
            1,
            2,
            3,
            4,
            ...planOf([request.inputs[0]]).writeToBuffer(),
          ]),
          request: request,
        ),
        _malformed(),
      );
    });

    test('never throws anything but SigningError, whatever the bytes', () {
      final random = Random(0x91A4);
      for (var i = 0; i < 400; i++) {
        final bytes = Uint8List.fromList([
          for (var j = 0; j < random.nextInt(64); j++) random.nextInt(256),
        ]);
        try {
          utxoFamily.parsePlan(bytes, request: request);
        } on SigningError {
          // expected
        }
      }
    });
  });

  test('the expected id of the p2wpkh vector is a well-formed one', () {
    // Guards the fixture of this file: `_goodTxid` is the vector's own id.
    expect(signExpected['txid'], _goodTxid);
  });
}
