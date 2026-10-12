/// The Bitcoin vectors against the host library, byte for byte, **at the
/// signing-core level**: the UTXO family encodes the key-less input, the
/// engine plans it, and `SyncSigningCore` signs it with one native key handle
/// per `KeyRole` — two handles, under `input(0)` and `input(1)`, for
/// `bitcoin-sign-multi_input-1`, which is the multi-key proof of the M1 exit
/// criterion.
///
/// The raw keys of the vectors are upstream's published test keys; they become
/// `PrivateKeyHandle`s here, in the test, and never reach a request. The
/// expected values are the vectors' own; none is computed.
///
/// Skips when the library is absent; `WCF_NATIVE_REQUIRED=1` turns that into a
/// failure (see `../../support/host_library.dart`).
@Tags(['native'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/advanced.dart'
    show LeakTracker, NativeContext;
import 'package:wallet_core_flutter/src/engine/handles.dart';
import 'package:wallet_core_flutter/src/errors/errors.dart';
import 'package:wallet_core_flutter/src/families/utxo/utxo_family.dart';
import 'package:wallet_core_flutter/src/families/utxo/utxo_native.dart';
import 'package:wallet_core_flutter/src/requests/requests.dart';
import 'package:wallet_core_flutter/src/signing/key_locator.dart';
import 'package:wallet_core_flutter/src/signing/sign_result.dart';
import 'package:wallet_core_flutter/src/signing/signing_core.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart' show Coin;
import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart'
    show TWDataHandle;
// ignore: implementation_imports
import 'package:wallet_core_flutter_bindings/src/generated/proto/Bitcoin.pb.dart'
    as btc;

import '../../signing/signing_support.dart';
import '../../support/fixtures.dart';
import '../../support/host_library.dart';
import 'utxo_vector.dart';

void main() {
  final skip = hostLibrarySkipReason();

  group('UTXO family against the host library', skip: skip, () {
    late NativeContext context;
    late LeakTracker tracker;
    late SyncSigningCore core;
    final handles = <PrivateKeyHandle>[];

    late Map<dynamic, dynamic> p2wpkhPlan;
    late Map<dynamic, dynamic> p2wpkhPlanExpected;
    late Map<dynamic, dynamic> p2wpkhSign;
    late Map<dynamic, dynamic> p2wpkhSignExpected;
    late Map<dynamic, dynamic> multiPlan;
    late Map<dynamic, dynamic> multiPlanExpected;
    late Map<dynamic, dynamic> multiSign;
    late Map<dynamic, dynamic> multiSignExpected;

    setUpAll(() {
      final inventory = loadInventory();
      Map<dynamic, dynamic> input(String id) =>
          vectorById(inventory, id).input as Map<dynamic, dynamic>;
      Map<dynamic, dynamic> expected(String id) =>
          vectorById(inventory, id).expected as Map<dynamic, dynamic>;
      p2wpkhPlan = input('bitcoin-plan-p2wpkh-1');
      p2wpkhPlanExpected = expected('bitcoin-plan-p2wpkh-1');
      p2wpkhSign = input('bitcoin-sign-p2wpkh-1');
      p2wpkhSignExpected = expected('bitcoin-sign-p2wpkh-1');
      multiPlan = input('bitcoin-plan-multi_input-1');
      multiPlanExpected = expected('bitcoin-plan-multi_input-1');
      multiSign = input('bitcoin-sign-multi_input-1');
      multiSignExpected = expected('bitcoin-sign-multi_input-1');
    });

    setUp(() {
      tracker = LeakTracker.maybeCreate()!;
      context = NativeContext(openHostBindings(), observer: tracker);
      core = SyncSigningCore(context);
    });

    tearDown(() {
      for (final handle in handles) {
        handle.dispose();
      }
      handles.clear();
      final report = tracker.report;
      expect(report.live, 0, reason: '$report');
      expect(report.finalizedWithoutDispose, 0, reason: '$report');
      tracker.stop();
    });

    /// One handle per role of [request], from the raw key the vector names
    /// for the locator that holds the role.
    Map<KeyRole, PrivateKeyHandle> handlesOf(
      VectorRequest vector,
      UtxoTransactionRequest request,
    ) {
      final keys = <KeyRole, PrivateKeyHandle>{};
      for (final locator in request.keyLocators) {
        final handle = privateKeyHandleOf(
          context,
          unhex(vector.keyOfRoleLocator(locator)),
        );
        handles.add(handle);
        keys[locator.role!] = handle;
      }
      return keys;
    }

    UtxoSignResult sign(
      VectorRequest vector,
      UtxoTransactionRequest request, {
      Uint8List? keyless,
    }) => core.sign(
      keyless ?? utxoFamily.encodeKeylessInput(request),
      family: utxoFamily,
      coin: Coin.bitcoin,
      requiredRoles: utxoFamily.requiredRoles(request),
      keys: handlesOf(vector, request),
      usedKeys: request.keyLocators,
    );

    UtxoPlan plan(UtxoTransactionRequest request) => utxoFamily.parsePlan(
      UtxoNative(context)
          .plan(utxoFamily.encodeKeylessInput(request), Coin.bitcoin),
      request: request,
    );

    void expectPlan(
      UtxoPlan plan,
      Map<dynamic, dynamic> expected,
      UtxoTransactionRequest request,
    ) {
      expect(
        plan.selectedInputs.map((i) => i.amount.toString()).toList(),
        (expected['selected_utxo_amounts'] as List<dynamic>).cast<String>(),
      );
      expect(plan.amount.toString(), expected['amount']);
      expect(plan.fee.toString(), expected['fee']);
      expect(plan.availableAmount.toString(), expected['available_amount']);
      expect(plan.change.toString(), expected['change']);
      // Every selected input is the request's own, so it keeps its locator.
      for (final selected in plan.selectedInputs) {
        expect(request.inputs, contains(selected));
      }
    }

    group('bitcoin-plan-p2wpkh-1 / bitcoin-sign-p2wpkh-1 (one key)', () {
      test('the plan equals the vector: inputs, amount, fee, change, '
          'available', () {
        final vector = VectorRequest.of(p2wpkhPlan);
        expectPlan(plan(vector.request), p2wpkhPlanExpected, vector.request);
      });

      test('the signed transaction equals the vector byte for byte, and so '
          'does its id', () {
        final vector = VectorRequest.of(p2wpkhSign);
        // Three inputs, one key: one locator, one role, one derived key.
        expect(vector.request.keyLocators, hasLength(1));
        expect(utxoFamily.requiredRoles(vector.request), [KeyRole.input(0)]);
        final result = sign(vector, vector.request);
        expect(hexOf(result.encoded), p2wpkhSignExpected['encoded']);
        expect(result.transactionId, p2wpkhSignExpected['txid']);
        expect(result.usedKeys, vector.request.keyLocators);
        expect(result.coin, Coin.bitcoin);
      });

      test('signing the plan gives the same bytes, and needs only the keys of '
          'the selected inputs', () {
        final vector = VectorRequest.of(p2wpkhSign);
        final planned = vector.request.withPlan(plan(vector.request));
        expect(planned.plan!.selectedInputs, hasLength(2));
        final result = sign(vector, planned);
        expect(hexOf(result.encoded), p2wpkhSignExpected['encoded']);
        expect(result.transactionId, p2wpkhSignExpected['txid']);
      });
    });

    group('bitcoin-plan-multi_input-1 / bitcoin-sign-multi_input-1 (two '
        'keys)', () {
      test('the plan equals the vector', () {
        final vector = VectorRequest.of(multiPlan, wireOrderTxids: true);
        expectPlan(plan(vector.request), multiPlanExpected, vector.request);
      });

      test('two key handles under input(0) and input(1) sign the vector '
          'byte for byte', () {
        final vector = VectorRequest.of(multiSign, wireOrderTxids: true);
        final request = vector.request;
        // Two distinct keys: one role each, in input order.
        expect(utxoFamily.requiredRoles(request), [
          KeyRole.input(0),
          KeyRole.input(1),
        ]);
        final locators = request.keyLocators.toList();
        expect(locators.map((l) => l.role), [
          KeyRole.input(0),
          KeyRole.input(1),
        ]);
        expect(
          vector.keyOfRoleLocator(locators[0]),
          vector.inputKeys[0],
          reason: 'input(0) is the key of the P2PK input',
        );
        expect(
          vector.keyOfRoleLocator(locators[1]),
          vector.inputKeys[1],
          reason: 'input(1) is the key of the P2WPKH input',
        );
        expect(
          vector.inputKeys[0] == vector.inputKeys[1],
          isFalse,
          reason: 'the two inputs are owned by two different keys',
        );

        final result = sign(vector, request);
        expect(hexOf(result.encoded), multiSignExpected['encoded']);
        expect(result.usedKeys, request.keyLocators);
      });

      test('the redeem-script map of the vector changes nothing: upstream '
          'reads `scripts` only for P2SH and P2WSH inputs', () {
        final vector = VectorRequest.of(multiSign, wireOrderTxids: true);
        final request = vector.request;
        final message = btc.SigningInput.fromBuffer(
          utxoFamily.encodeKeylessInput(request),
        );
        for (final script in multiSign['redeem_scripts'] as List<dynamic>) {
          final fields = script as Map<dynamic, dynamic>;
          expect(fields['script_type'], 'p2pkh');
          // The vector's own redeem script, as upstream's test builds it —
          // `Script::buildPayToPublicKeyHash(<key hash>)` — from upstream's
          // helper, never by hand.
          final hash = unhex(fields['key_hash'] as String);
          message.scripts[fields['key_hash'] as String] = _payToPublicKeyHash(
            context,
            hash,
          );
        }
        expect(message.scripts, isNotEmpty);
        final result = sign(vector, request, keyless: message.writeToBuffer());
        expect(hexOf(result.encoded), multiSignExpected['encoded']);
      });

      test('signing the plan gives the same bytes', () {
        final vector = VectorRequest.of(multiSign, wireOrderTxids: true);
        final planned = vector.request.withPlan(plan(vector.request));
        expect(planned.keyLocators, hasLength(2));
        final result = sign(vector, planned);
        expect(hexOf(result.encoded), multiSignExpected['encoded']);
      });
    });

    group('what upstream says about a request', () {
      test('a request whose only input is below the dust threshold is '
          "upstream's own error, for the plan and for the signature", () {
        final vector = VectorRequest.of(p2wpkhPlan);
        final r = vector.request;
        // The third UTXO of the vector, 300 satoshis: "filtered out as less
        // than dust" (the vector's own comment).
        final dust = UtxoTransactionRequest(
          coin: r.coin,
          toAddress: r.toAddress,
          amount: 100,
          feeRatePerByte: r.feeRatePerByte,
          changeAddress: r.changeAddress,
          inputs: [r.inputs.last],
        );
        Matcher upstreamError() => throwsA(
          isA<SigningError>().having(
            (e) => e.upstreamCode,
            'upstreamCode',
            greaterThan(0),
          ),
        );
        expect(() => plan(dust), upstreamError());
        expect(() => sign(vector, dust), upstreamError());
      });
    });
  });
}

/// `TWBitcoinScriptBuildPayToPublicKeyHash(hash)`, copied out as bytes.
Uint8List _payToPublicKeyHash(NativeContext context, Uint8List hash) {
  final bindings = context.bindings;
  final data = TWDataHandle.fromBytes(context, hash);
  try {
    final script = bindings.TWBitcoinScriptBuildPayToPublicKeyHash(
      data.pointer,
    );
    try {
      final encoded = bindings.TWBitcoinScriptData(script);
      final handle = TWDataHandle.adopt(context, encoded);
      try {
        return handle.copyBytes();
      } finally {
        handle.dispose();
      }
    } finally {
      bindings.TWBitcoinScriptDelete(script);
    }
  } finally {
    data.dispose();
  }
}
