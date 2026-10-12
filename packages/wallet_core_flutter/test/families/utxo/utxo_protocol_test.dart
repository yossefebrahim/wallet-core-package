/// The `Plan` and `Planned` protocol values, `UtxoSignResult`, and the
/// session's `plan` path with a fake executor: no library needed.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/src/session/testing.dart';
import 'package:wallet_core_flutter/src/signing/key_locator.dart'
    show issueKeyRef;
import 'package:wallet_core_flutter/src/signing/sign_result.dart'
    show withUsedKeys;
import 'package:wallet_core_flutter/src/worker/protocol.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';

import '../../support/fake_handler.dart';

const String _txid =
    '5d6bf53576a54be4d92cd8abf58d28ecc9ea7956eaf970d24d6bfcb9fcfe9855';

UtxoTransactionRequest _request() => UtxoTransactionRequest(
  coin: Coin.bitcoin,
  toAddress: 'bc1q2dsdlq3343vk29runkgv4yc292hmq53jedfjmp',
  amount: 5000,
  feeRatePerByte: 2,
  changeAddress: 'bc1qvrt7ukvhvmdny0a3j9k8l8jasx92lrqm30t2u2',
  inputs: [
    UtxoInput(
      outPoint: OutPoint(transactionId: _txid, index: 1),
      amount: 10000,
      script: Uint8List.fromList([0x00, 0x14, ...List.filled(20, 7)]),
      addressStyle: AddressStyle.segwit,
      keyLocator: KeyLocator.imported(issueKeyRef(1)),
    ),
  ],
);

void main() {
  test('Plan renders the request, is an operation named plan, and carries '
      'no key', () {
    final plan = Plan(4, request: _request());
    expect(plan.operation, 'plan');
    expect(plan.isControl, isFalse);
    expect(
      plan.toString(),
      'Plan(#4, UtxoTransactionRequest(bitcoin, '
      'to: bc1q2dsdlq3343vk29runkgv4yc292hmq53jedfjmp, amount: 5000, '
      'feeRatePerByte: 2, change: bc1qvrt7ukvhvmdny0a3j9k8l8jasx92lrqm30t2u2, '
      'inputs: 1, keys: 1))',
    );
  });

  test('Planned renders the plan by counts and amounts', () {
    final request = _request();
    final planned = Planned(
      4,
      UtxoPlan(
        selectedInputs: request.inputs,
        amount: 5000,
        availableAmount: 10000,
        fee: 300,
        change: 4700,
      ),
    );
    expect(
      planned.toString(),
      'Planned(#4, UtxoPlan(inputs: 1, amount: 5000, fee: 300, change: 4700, '
      'available: 10000))',
    );
  });

  test('UtxoSignResult copies its bytes, shows its id and size only, and '
      'withUsedKeys replaces only the keys', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final result = UtxoSignResult(
      coin: Coin.bitcoin,
      encoded: bytes,
      transactionId: _txid,
      usedKeys: const <KeyLocator>{},
    );
    bytes[0] = 9;
    expect(result.encoded, [1, 2, 3]);
    expect(() => result.encoded.add(1), throwsUnsupportedError);
    expect(
      result.toString(),
      'UtxoSignResult(bitcoin, id: $_txid, encoded: 3 bytes, usedKeys: 0)',
    );
    final key = KeyLocator.imported(issueKeyRef(1));
    final again = withUsedKeys(result, {key}) as UtxoSignResult;
    expect(again.usedKeys, {key});
    expect(again.encoded, [1, 2, 3]);
    expect(again.transactionId, _txid);
    expect(again.coin, Coin.bitcoin);
    final described = switch (result as SignResult) {
      UtxoSignResult() => 'utxo',
      EvmSignResult() => 'evm',
      SolanaSignResult() => 'solana',
      EvmMessageSignResult() => 'evmMessage',
    };
    expect(described, 'utxo');
  });

  test('signer.plan sends one Plan with no keys and returns the Planned '
      'plan', () async {
    final handler = FakeHandler();
    final core = await initializeForTesting(handler: handler);
    final request = _request();
    final plan = await core.signer.plan(request);
    expect(handler.operations, ['initialize', 'plan']);
    final sent = handler.handled.last as Plan;
    expect(sent.request, same(request));
    expect(plan.selectedInputs, request.inputs);
    await core.shutdown();
  });

  test('signer.plan on a closed session is a typed session error', () async {
    final core = await initializeForTesting(handler: FakeHandler());
    await core.shutdown();
    await expectLater(
      core.signer.plan(_request()),
      throwsA(isA<WalletCoreException>()),
    );
  });
}
