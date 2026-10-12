/// `UtxoTransactionRequest` and `UtxoPlan` (`lib/src/requests/utxo/`): what is
/// validated at construction, which locators a request names and under which
/// roles, and `withPlan`. Pure Dart: no native library.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/src/errors/errors.dart';
import 'package:wallet_core_flutter/src/requests/requests.dart';
import 'package:wallet_core_flutter/src/signing/key_locator.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart'
    show AddressStyle, Coin, Network;

const String _to = 'bc1q2dsdlq3343vk29runkgv4yc292hmq53jedfjmp';
const String _change = 'bc1qvrt7ukvhvmdny0a3j9k8l8jasx92lrqm30t2u2';

/// `OP_0 <20 bytes>`: the shape of a P2WPKH script. Never inspected here.
final Uint8List _script = Uint8List.fromList([
  0x00,
  0x14,
  ...List.filled(20, 7),
]);

final KeyLocator _keyA = KeyLocator.imported(issueKeyRef(1));
final KeyLocator _keyB = KeyLocator.imported(issueKeyRef(2));

String _txid(int n) => n.toRadixString(16).padLeft(64, '0');

UtxoInput _input(
  int n, {
  KeyLocator? locator,
  int amount = 10000,
  Uint8List? script,
  AddressStyle style = AddressStyle.segwit,
}) => UtxoInput(
  outPoint: OutPoint(transactionId: _txid(n), index: 0),
  amount: amount,
  script: script ?? _script,
  addressStyle: style,
  keyLocator: locator ?? _keyA,
);

UtxoTransactionRequest _request({
  Coin? coin,
  String to = _to,
  String change = _change,
  int amount = 5000,
  int feeRate = 2,
  List<UtxoInput>? inputs,
  bool useMax = false,
}) => UtxoTransactionRequest(
  coin: coin ?? Coin.bitcoin,
  toAddress: to,
  amount: amount,
  feeRatePerByte: feeRate,
  changeAddress: change,
  inputs: inputs ?? [_input(1)],
  useMaxAmount: useMax,
);

Matcher _invalid(String inputName) => throwsA(
  isA<InvalidInputError>().having((e) => e.inputName, 'inputName', inputName),
);

Matcher _unsupported(String capability) => throwsA(
  isA<UnsupportedOperationError>().having(
    (e) => e.capability,
    'capability',
    capability,
  ),
);

void main() {
  group('construction', () {
    test('accepts a Bitcoin spend and exposes what it was given', () {
      final inputs = [_input(1), _input(2, locator: _keyB)];
      final request = _request(inputs: inputs, useMax: true);
      expect(request.coin, Coin.bitcoin);
      expect(request.network, Network.mainnet);
      expect(request.toAddress, _to);
      expect(request.changeAddress, _change);
      expect(request.amount, 5000);
      expect(request.feeRatePerByte, 2);
      expect(request.useMaxAmount, isTrue);
      expect(request.inputs, inputs);
      expect(request.plan, isNull);
    });

    test('copies its inputs: the list cannot be changed from outside or '
        'through the request', () {
      final inputs = [_input(1)];
      final request = _request(inputs: inputs);
      inputs.add(_input(2));
      expect(request.inputs, hasLength(1));
      expect(() => request.inputs.add(_input(3)), throwsUnsupportedError);
    });

    test('a coin outside the UTXO family is an InvalidInputError', () {
      expect(() => _request(coin: Coin.ethereum), _invalid('coin'));
      expect(() => _request(coin: Coin.solana), _invalid('coin'));
    });

    test('a UTXO coin other than Bitcoin is unsupported, by name', () {
      final litecoin = Coin.byId('litecoin');
      expect(() => _request(coin: litecoin), _unsupported('utxo-transaction'));
    });

    test('addresses are 1 to 90 letters and digits', () {
      for (final bad in ['', 'bc1 q', 'bc1q\u0000', 'a' * 91, 'bc1q-x', 'é']) {
        expect(() => _request(to: bad), _invalid('toAddress'), reason: bad);
        expect(
          () => _request(change: bad),
          _invalid('changeAddress'),
          reason: bad,
        );
      }
      expect(() => _request(to: 'a' * 90), returnsNormally);
    });

    test('amount is 1 to 2.1e15, fee rate 1 to 1 000 000', () {
      for (final bad in [0, -1, maxUtxoAmount + 1]) {
        expect(() => _request(amount: bad), _invalid('amount'));
      }
      expect(() => _request(amount: maxUtxoAmount), returnsNormally);
      for (final bad in [0, -1, maxUtxoFeeRatePerByte + 1]) {
        expect(() => _request(feeRate: bad), _invalid('feeRatePerByte'));
      }
      expect(() => _request(feeRate: maxUtxoFeeRatePerByte), returnsNormally);
    });

    test('inputs: at least one, at most $maxUtxoInputs, each output once', () {
      expect(() => _request(inputs: []), _invalid('inputs'));
      expect(
        () => _request(
          inputs: [for (var i = 1; i <= maxUtxoInputs + 1; i++) _input(i)],
        ),
        _invalid('inputs'),
      );
      expect(
        () => _request(
          inputs: [for (var i = 1; i <= maxUtxoInputs; i++) _input(i)],
        ),
        returnsNormally,
      );
      expect(
        () => _request(inputs: [_input(1), _input(1, amount: 20000)]),
        _invalid('inputs'),
      );
    });

    test('an input amount above the supply or a script out of bounds is '
        'rejected', () {
      expect(
        () => _request(inputs: [_input(1, amount: maxUtxoAmount + 1)]),
        _invalid('inputs'),
      );
      expect(
        () => _request(inputs: [_input(1, script: Uint8List(0))]),
        _invalid('inputs'),
      );
      expect(
        () => _request(
          inputs: [_input(1, script: Uint8List(maxUtxoScriptBytes + 1))],
        ),
        _invalid('inputs'),
      );
      expect(
        () => _request(
          inputs: [_input(1, script: Uint8List(maxUtxoScriptBytes))],
        ),
        returnsNormally,
      );
    });

    test('an input whose locator names a role is rejected: the request '
        'assigns the roles', () {
      final named = KeyLocator.imported(issueKeyRef(3), role: KeyRole.input(0));
      expect(
        () => _request(inputs: [_input(1, locator: named)]),
        _invalid('inputs'),
      );
    });

    test('a taproot input is unsupported by address style', () {
      expect(
        () => _request(inputs: [_input(1, style: AddressStyle.taproot)]),
        _unsupported('addressStyle:taproot'),
      );
    });

    test('toString names the request and no key', () {
      final text = _request().toString();
      expect(text, contains('UtxoTransactionRequest(bitcoin'));
      expect(text, contains('inputs: 1'));
      expect(text, contains('keys: 1'));
    });
  });

  group('the locators of a request', () {
    test('one per distinct key, in order of first use, each in the role '
        'of the first input that uses it', () {
      final request = _request(
        inputs: [
          _input(1, locator: _keyA),
          _input(2, locator: _keyB),
          _input(3, locator: _keyA),
          _input(4, locator: _keyB),
        ],
      );
      final locators = request.keyLocators.toList();
      expect(locators, hasLength(2));
      expect(
        locators[0],
        KeyLocator.imported(
          (_keyA as ImportedKeyLocator).key,
          role: KeyRole.input(0),
        ),
      );
      expect(
        locators[1],
        KeyLocator.imported(
          (_keyB as ImportedKeyLocator).key,
          role: KeyRole.input(1),
        ),
      );
    });

    test('a request with one key has one locator in role input(0), '
        'whatever the number of inputs', () {
      final request = _request(inputs: [_input(1), _input(2), _input(3)]);
      expect(request.keyLocators.map((l) => l.role), [KeyRole.input(0)]);
    });

    test('the set is unmodifiable and the same each time', () {
      final request = _request(
        inputs: [
          _input(1),
          _input(2, locator: _keyB),
        ],
      );
      expect(() => request.keyLocators.clear(), throwsUnsupportedError);
      expect(request.keyLocators, same(request.keyLocators));
    });

    test('an external locator keeps its device and public key', () {
      final device = KeyLocator.external('dev-1', Uint8List.fromList([1, 2]));
      final request = _request(inputs: [_input(1, locator: device)]);
      final stamped = request.keyLocators.single as ExternalKeyLocator;
      expect(stamped.deviceId, 'dev-1');
      expect(stamped.publicKey, [1, 2]);
      expect(stamped.role, KeyRole.input(0));
    });
  });

  group('withPlan', () {
    UtxoPlan planOf(List<UtxoInput> selected) => UtxoPlan(
      selectedInputs: selected,
      amount: 5000,
      availableAmount: 20000,
      fee: 300,
      change: 14700,
    );

    test('signs the plan: its inputs, in its order, and only their keys', () {
      final a = _input(1, locator: _keyA);
      final b = _input(2, locator: _keyB);
      final c = _input(3, locator: _keyA);
      final request = _request(inputs: [a, b, c]);
      expect(request.keyLocators.map((l) => l.role), [
        KeyRole.input(0),
        KeyRole.input(1),
      ]);

      final planned = request.withPlan(planOf([b]));
      expect(planned.plan!.selectedInputs, [b]);
      expect(planned.inputs, [a, b, c]);
      expect(planned.keyLocators, hasLength(1));
      expect(
        planned.keyLocators.single,
        KeyLocator.imported(
          (_keyB as ImportedKeyLocator).key,
          role: KeyRole.input(0),
        ),
      );
      // The request it came from is unchanged.
      expect(request.plan, isNull);
      expect(request.keyLocators, hasLength(2));
    });

    test('a plan that selects an input the request does not have is '
        'rejected', () {
      final request = _request(inputs: [_input(1)]);
      expect(() => request.withPlan(planOf([_input(9)])), _invalid('plan'));
    });
  });

  group('UtxoPlan', () {
    test('needs at least one input and amounts within the supply', () {
      expect(
        () => UtxoPlan(
          selectedInputs: [],
          amount: 1,
          availableAmount: 1,
          fee: 0,
          change: 0,
        ),
        _invalid('plan'),
      );
      for (final bad in [-1, maxUtxoAmount + 1]) {
        expect(
          () => UtxoPlan(
            selectedInputs: [_input(1)],
            amount: 1,
            availableAmount: 1,
            fee: bad,
            change: 0,
          ),
          _invalid('plan'),
        );
      }
    });

    test('copies its inputs and renders without them', () {
      final inputs = [_input(1)];
      final plan = UtxoPlan(
        selectedInputs: inputs,
        amount: 5000,
        availableAmount: 10000,
        fee: 100,
        change: 4900,
      );
      inputs.clear();
      expect(plan.selectedInputs, hasLength(1));
      expect(
        plan.toString(),
        'UtxoPlan(inputs: 1, amount: 5000, fee: 100, change: 4900, '
        'available: 10000)',
      );
    });
  });
}
