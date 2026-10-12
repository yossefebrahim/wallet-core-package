/// The M1 UTXO clauses (PRD §18) asserted on a device, debug and release:
///
/// 1. the P2WPKH vectors — plan and sign — byte for byte, at the signing-core
///    level (`bitcoin-plan-p2wpkh-1`, `bitcoin-sign-p2wpkh-1`);
/// 2. the multi-input vectors — plan and sign — byte for byte **with two key
///    handles under `input(0)` and `input(1)`**: the multi-key proof
///    (`bitcoin-plan-multi_input-1`, `bitcoin-sign-multi_input-1`);
/// 3. through the public session, two inputs from two HD paths of one
///    mnemonic: the address vectors (`bitcoin-address-n/a-1`, `-2`) and a
///    signature whose bytes are checked **structurally only** — no upstream
///    vector signs from two HD paths, so nothing here compares those bytes to
///    an expected transaction.
///
/// Every expected value comes from `m1_utxo_vectors.dart`, which a host test
/// holds equal to `test_vectors/bitcoin/vectors.yaml`. The library is always
/// the one the build hook bundled into the app: no test passes a host path.
///
/// **Written for the orchestrator to run; not run by its author** (no device
/// reaches the implementer's sandbox).
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
// The public surface has no raw-key import (PRD §10.2: signers take
// `KeyLocator`s), and the byte-for-byte vectors are signed by raw upstream test
// keys. So the first two tests import the SDK's internals, the way the SDK's
// own host tests do (`test/families/utxo/utxo_vectors_native_test.dart`); the
// third uses the public surface for HD derivation and signing.
// ignore_for_file: implementation_imports
import 'package:wallet_core_flutter/advanced.dart'
    show
        LeakTracker,
        NativeContext,
        NoopResourceObserver,
        TWDataHandle,
        WalletCoreBindings,
        runScope;
import 'package:wallet_core_flutter/src/engine/coin_bridge.dart'
    show twCoinTypeOf;
import 'package:wallet_core_flutter/src/engine/handles.dart'
    show PrivateKeyHandle;
import 'package:wallet_core_flutter/src/families/utxo/utxo_family.dart';
import 'package:wallet_core_flutter/src/families/utxo/utxo_native.dart';
import 'package:wallet_core_flutter/src/session/testing.dart'
    show debugLeakReportOf, initializeForTesting;
import 'package:wallet_core_flutter/src/signing/key_locator.dart';
import 'package:wallet_core_flutter/src/signing/signing_core.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:wallet_core_flutter_native/wallet_core_flutter_native.dart'
    show WalletCoreNative;

import 'm1_utxo_vectors.dart' as v;
import 'vector_results.dart';

const Timeout _timeout = Timeout(Duration(minutes: 5));

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _unhex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

String _reversedHex(String hex) => _hex(_unhex(hex).reversed.toList());

/// A request from vector values, plus the raw key behind each distinct
/// locator. Every input uses a `KeyLocator.imported` stand-in per distinct
/// raw key, so equal keys share a locator and the request de-duplicates them.
({UtxoTransactionRequest request, Map<KeyLocator, String> keys}) _requestOf({
  required List<v.VectorUtxo> utxos,
  required bool wireOrderTxids,
  required String byteFee,
  required String amount,
  required bool useMaxAmount,
  required String toAddress,
  required String changeAddress,
}) {
  final locatorOfKey = <String, KeyLocator>{};
  final inputs = <UtxoInput>[
    for (final utxo in utxos)
      UtxoInput(
        outPoint: OutPoint(
          transactionId: wireOrderTxids ? _reversedHex(utxo.txid) : utxo.txid,
          index: int.parse(utxo.index),
        ),
        amount: int.parse(utxo.amount),
        script: _unhex(utxo.scriptPubKey),
        addressStyle: utxo.scriptPubKey.length == 44
            ? AddressStyle.segwit
            : AddressStyle.legacy,
        keyLocator: locatorOfKey.putIfAbsent(
          utxo.privateKey,
          () => KeyLocator.imported(issueKeyRef(locatorOfKey.length + 1)),
        ),
      ),
  ];
  final request = UtxoTransactionRequest(
    coin: Coin.bitcoin,
    toAddress: toAddress,
    amount: int.parse(amount),
    feeRatePerByte: int.parse(byteFee),
    changeAddress: changeAddress,
    inputs: inputs,
    useMaxAmount: useMaxAmount,
  );
  return (
    request: request,
    keys: {for (final e in locatorOfKey.entries) e.value: e.key},
  );
}

/// What a segwit transaction's witnesses say, read and not interpreted: the
/// public key of each input's witness, or a failed expectation when the bytes
/// are not a segwit transaction of [inputs] inputs, each witness a signature
/// and a 33-byte public key.
List<String> _witnessKeys(Uint8List bytes, {required int inputs}) {
  var at = 0;
  int u8() => bytes[at++];
  int varint() {
    final first = u8();
    if (first < 0xFD) return first;
    final width = first == 0xFD ? 2 : (first == 0xFE ? 4 : 8);
    var value = 0;
    for (var i = 0; i < width; i++) {
      value |= u8() << (8 * i);
    }
    return value;
  }

  Uint8List take(int n) {
    final out = Uint8List.sublistView(bytes, at, at + n);
    at += n;
    return out;
  }

  take(4); // version
  expect(bytes[at], 0, reason: 'segwit marker');
  expect(bytes[at + 1], 1, reason: 'segwit flag');
  at += 2;
  expect(varint(), inputs, reason: 'input count');
  for (var i = 0; i < inputs; i++) {
    take(32 + 4);
    take(varint());
    take(4);
  }
  final outputs = varint();
  for (var i = 0; i < outputs; i++) {
    take(8);
    take(varint());
  }
  final keys = <String>[];
  for (var i = 0; i < inputs; i++) {
    expect(varint(), 2, reason: 'witness $i has a signature and a key');
    final signature = take(varint());
    expect(signature.length, inInclusiveRange(70, 73));
    final key = take(varint());
    expect(key.length, 33);
    keys.add(_hex(key));
  }
  take(4); // lock time
  expect(at, bytes.length, reason: 'the transaction was read to its end');
  return keys;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// The bundled library, opened as the session's executor opens it, a
  /// signing core over it, and the handles a test made, to release at the end.
  Future<void> withCore(
    Future<void> Function(
      NativeContext context,
      SyncSigningCore core,
      PrivateKeyHandle Function(String rawKeyHex) handleOf,
    )
    body,
  ) async {
    final bindings = WalletCoreBindings(WalletCoreNative.load());
    final tracker = LeakTracker.maybeCreate();
    final context = NativeContext(
      bindings,
      observer: tracker ?? const NoopResourceObserver(),
    );
    final handles = <PrivateKeyHandle>[];
    PrivateKeyHandle handleOf(String rawKeyHex) {
      final keyData = TWDataHandle.fromBytes(context, _unhex(rawKeyHex));
      try {
        final handle = PrivateKeyHandle.adopt(
          context,
          bindings.TWPrivateKeyCreateWithData(keyData.pointer),
        );
        handles.add(handle);
        return handle;
      } finally {
        keyData.dispose();
      }
    }

    try {
      await body(context, SyncSigningCore(context), handleOf);
    } finally {
      for (final handle in handles) {
        handle.dispose();
      }
      if (tracker != null) {
        expect(tracker.report.live, 0, reason: '${tracker.report}');
        expect(tracker.report.finalizedWithoutDispose, 0);
        tracker.stop();
      }
    }
  }

  /// Signs [request] at the core level with one handle per role of the
  /// request's locators, from the raw key [rawKeys] names for the stand-in
  /// each locator was made from.
  UtxoSignResult signWithHandles(
    SyncSigningCore core,
    UtxoTransactionRequest request,
    Map<KeyLocator, String> rawKeys,
    PrivateKeyHandle Function(String) handleOf,
  ) {
    final byRole = <KeyRole, PrivateKeyHandle>{};
    for (final locator in request.keyLocators) {
      final key = (locator as ImportedKeyLocator).key;
      final raw = rawKeys.entries
          .singleWhere((e) => (e.key as ImportedKeyLocator).key == key)
          .value;
      byRole[locator.role!] = handleOf(raw);
    }
    return core.sign(
      utxoFamily.encodeKeylessInput(request),
      family: utxoFamily,
      coin: Coin.bitcoin,
      requiredRoles: utxoFamily.requiredRoles(request),
      keys: byRole,
      usedKeys: request.keyLocators,
    );
  }

  UtxoPlan planOf(NativeContext context, UtxoTransactionRequest request) =>
      utxoFamily.parsePlan(
        UtxoNative(context)
            .plan(utxoFamily.encodeKeylessInput(request), Coin.bitcoin),
        request: request,
      );

  testWidgets('clause 1: the P2WPKH plan and signed transaction equal the '
      'vectors byte for byte (bitcoin-plan-p2wpkh-1, bitcoin-sign-p2wpkh-1)', (
    WidgetTester tester,
  ) async {
    final built = _requestOf(
      utxos: v.p2wpkhUtxos,
      wireOrderTxids: false,
      byteFee: v.p2wpkhByteFee,
      amount: v.p2wpkhAmount,
      useMaxAmount: v.p2wpkhUseMaxAmount,
      toAddress: v.p2wpkhToAddress,
      changeAddress: v.p2wpkhChangeAddress,
    );
    await withCore((context, core, handleOf) async {
      final plan = planOf(context, built.request);
      expect(
        plan.selectedInputs.map((i) => i.amount.toString()).toList(),
        v.p2wpkhPlanSelectedAmounts,
      );
      expect(plan.amount.toString(), v.p2wpkhPlanAmount);
      expect(plan.fee.toString(), v.p2wpkhPlanFee);
      expect(plan.availableAmount.toString(), v.p2wpkhPlanAvailableAmount);
      expect(plan.change.toString(), v.p2wpkhPlanChange);

      // Three inputs, one key: one locator, one role.
      expect(built.request.keyLocators, hasLength(1));
      final result = signWithHandles(core, built.request, built.keys, handleOf);
      expect(_hex(result.encoded), v.p2wpkhSignExpectedEncoded);
      expect(result.transactionId, v.p2wpkhSignExpectedTxid);

      // And the plan, signed: the same bytes.
      final planned = built.request.withPlan(plan);
      final again = signWithHandles(core, planned, built.keys, handleOf);
      expect(_hex(again.encoded), v.p2wpkhSignExpectedEncoded);
    });
    // After `withCore`, which also asserts the leak report.
    recordVectorPass('bitcoin-plan-p2wpkh-1');
    recordVectorPass('bitcoin-sign-p2wpkh-1');
  }, timeout: _timeout);

  testWidgets('clause 2: two key handles under input(0) and input(1) plan and '
      'sign the multi-input vectors byte for byte (bitcoin-plan-multi_input-1, '
      'bitcoin-sign-multi_input-1)', (WidgetTester tester) async {
    final built = _requestOf(
      utxos: v.multiUtxos,
      wireOrderTxids: true,
      byteFee: v.multiByteFee,
      amount: v.multiAmount,
      useMaxAmount: v.multiUseMaxAmount,
      toAddress: v.multiToAddress,
      changeAddress: v.multiChangeAddress,
    );
    await withCore((context, core, handleOf) async {
      final plan = planOf(context, built.request);
      expect(
        plan.selectedInputs.map((i) => i.amount.toString()).toList(),
        v.multiPlanSelectedAmounts,
      );
      expect(plan.amount.toString(), v.multiPlanAmount);
      expect(plan.fee.toString(), v.multiPlanFee);
      expect(plan.availableAmount.toString(), v.multiPlanAvailableAmount);
      expect(plan.change.toString(), v.multiPlanChange);

      // Two different keys: one role each, in input order.
      expect(utxoFamily.requiredRoles(built.request), [
        KeyRole.input(0),
        KeyRole.input(1),
      ]);
      expect(v.multiUtxos[0].privateKey == v.multiUtxos[1].privateKey, isFalse);
      final result = signWithHandles(core, built.request, built.keys, handleOf);
      expect(_hex(result.encoded), v.multiSignExpectedEncoded);
      expect(result.usedKeys, built.request.keyLocators);
    });
    recordVectorPass('bitcoin-plan-multi_input-1');
    recordVectorPass('bitcoin-sign-multi_input-1');
  }, timeout: _timeout);

  testWidgets('clause 3: two inputs from two HD paths of one mnemonic are '
      'signed through the public surface (bitcoin-address-n/a-1, -2; '
      'structural facts only)', (WidgetTester tester) async {
    final core = await initializeForTesting();
    final bindings = WalletCoreBindings(WalletCoreNative.load());
    final helper = NativeContext(bindings);
    try {
      final wallet = await core.wallets.importMnemonic(v.addressMnemonic);
      final account0 = await wallet.account(Coin.bitcoin, path: v.addressPath0);
      final account1 = await wallet.account(Coin.bitcoin, path: v.addressPath1);
      expect(account0.address.value, v.addressExpected0);
      expect(account1.address.value, v.addressExpected1);
      expect(_hex(account0.publicKey), v.publicKeyExpected0);
      expect(_hex(account1.publicKey), v.publicKeyExpected1);

      // The locking scripts upstream builds for the two addresses.
      Uint8List lockScriptFor(String address) => runScope(helper, (scope) {
        final text = scope.string(address);
        final script = bindings.TWBitcoinScriptLockScriptForAddress(
          text.pointer,
          twCoinTypeOf(Coin.bitcoin),
        );
        try {
          return scope
              .use(
                TWDataHandle.adopt(
                  helper,
                  bindings.TWBitcoinScriptData(script),
                ),
              )
              .copyBytes();
        } finally {
          bindings.TWBitcoinScriptDelete(script);
        }
      });

      final locator0 = KeyLocator.hdPath(
        wallet.ref,
        Coin.bitcoin,
        v.addressPath0,
      );
      final locator1 = KeyLocator.hdPath(
        wallet.ref,
        Coin.bitcoin,
        v.addressPath1,
      );
      UtxoInput input(int n, String address, KeyLocator locator, int amount) =>
          UtxoInput(
            outPoint: OutPoint(
              transactionId: n.toRadixString(16).padLeft(64, 'a'),
              index: n,
            ),
            amount: amount,
            script: lockScriptFor(address),
            addressStyle: AddressStyle.segwit,
            keyLocator: locator,
          );
      final request = UtxoTransactionRequest(
        coin: Coin.bitcoin,
        toAddress: v.p2wpkhToAddress,
        amount: 90000,
        feeRatePerByte: 2,
        changeAddress: v.addressExpected0,
        inputs: [
          input(0, v.addressExpected0, locator0, 60000),
          input(1, v.addressExpected1, locator1, 70000),
        ],
      );

      final plan = await core.signer.plan(request);
      expect(plan.selectedInputs, hasLength(2));
      final result = await core.signer.sign(
        request,
        request.keyLocators,
      ) as UtxoSignResult;
      expect(result.usedKeys, request.keyLocators);
      expect(result.transactionId, matches(RegExp(r'^[0-9a-f]{64}$')));

      // Structural facts: a segwit transaction with two inputs and two
      // witnesses of a signature and a key — upstream reported no error — and
      // the key in each witness is the public key of one of the two paths.
      final keys = _witnessKeys(result.encoded, inputs: 2);
      expect(keys.toSet(), {v.publicKeyExpected0, v.publicKeyExpected1});

      await wallet.close();
      final report = debugLeakReportOf(core);
      if (report != null) expect(report.live, 0, reason: '$report');
      recordVectorPass('bitcoin-address-n/a-1');
      recordVectorPass('bitcoin-address-n/a-2');
    } finally {
      await core.shutdown();
    }
  }, timeout: _timeout);
}
