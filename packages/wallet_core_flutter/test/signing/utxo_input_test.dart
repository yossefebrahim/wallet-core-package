/// `OutPoint` and `UtxoInput` (`lib/src/requests/base.dart`): pure values that
/// name a key by locator and hold no key material.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/src/errors/errors.dart';
import 'package:wallet_core_flutter/src/requests/requests.dart';
import 'package:wallet_core_flutter/src/signing/key_locator.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart' show AddressStyle;

const String _txid =
    'fff7f7881a8099afa6940d42d1e7f6362bec38171ea3edf433541db4e4ad969f';

/// One instance: a `KeyRef` is equal by identity, so two `issueKeyRef(1)`
/// are two different keys.
final KeyLocator _sharedLocator = KeyLocator.imported(issueKeyRef(1));

Matcher _invalid(String inputName) => throwsA(
  isA<InvalidInputError>().having((e) => e.inputName, 'inputName', inputName),
);

UtxoInput _input({
  Uint8List? script,
  int amount = 625000000,
  KeyLocator? locator,
}) => UtxoInput(
  outPoint: OutPoint(transactionId: _txid, index: 0),
  amount: amount,
  script: script ?? Uint8List.fromList([0x00, 0x14, 0x1d, 0x0f]),
  addressStyle: AddressStyle.segwit,
  keyLocator: locator ?? _sharedLocator,
);

void main() {
  group('OutPoint', () {
    test('accepts a 64-digit transaction id and a 32-bit index', () {
      final outPoint = OutPoint(transactionId: _txid, index: 0xFFFFFFFF);
      expect(outPoint.transactionId, _txid);
      expect(outPoint.index, 0xFFFFFFFF);
    });

    test(
      'rejects a malformed id or an out-of-range index, naming the input',
      () {
        expect(
          () => OutPoint(transactionId: 'abc', index: 0),
          _invalid('transactionId'),
        );
        expect(
          () => OutPoint(transactionId: '${_txid}0', index: 0),
          _invalid('transactionId'),
        );
        expect(
          () => OutPoint(transactionId: 'g' * 64, index: 0),
          _invalid('transactionId'),
        );
        expect(
          () => OutPoint(transactionId: _txid, index: -1),
          _invalid('index'),
        );
        expect(
          () => OutPoint(transactionId: _txid, index: 0x100000000),
          _invalid('index'),
        );
      },
    );

    test('equality ignores the case of the id', () {
      expect(
        OutPoint(transactionId: _txid, index: 1),
        OutPoint(transactionId: _txid.toUpperCase(), index: 1),
      );
      expect(
        OutPoint(transactionId: _txid, index: 1),
        isNot(OutPoint(transactionId: _txid, index: 2)),
      );
    });
  });

  group('UtxoInput', () {
    test('holds the locator it was given and has no key material: its only '
        'bytes are the locking script', () {
      final locator = KeyLocator.imported(
        issueKeyRef(7),
        role: KeyRole.input(3),
      );
      final input = _input(locator: locator);
      expect(input.keyLocator, same(locator));
      expect(input.amount, 625000000);
      expect(input.addressStyle, AddressStyle.segwit);
      expect(input.outPoint.index, 0);
      expect(input.script, [0x00, 0x14, 0x1d, 0x0f]);
    });

    test('copies the script on the way in and exposes a read-only view', () {
      final source = Uint8List.fromList([1, 2, 3]);
      final input = _input(script: source);
      source[0] = 9;
      expect(input.script, [1, 2, 3]);
      expect(() => input.script[0] = 9, throwsUnsupportedError);
    });

    test('rejects a negative amount, naming it', () {
      expect(() => _input(amount: -1), _invalid('amount'));
      expect(_input(amount: 0).amount, 0);
    });

    test('is a value: equal inputs are equal, any difference is not', () {
      expect(_input(), _input());
      expect(_input().hashCode, _input().hashCode);
      expect(_input(), isNot(_input(amount: 1)));
      expect(_input(), isNot(_input(script: Uint8List.fromList([0]))));
      expect(
        _input(),
        isNot(_input(locator: KeyLocator.imported(issueKeyRef(2)))),
      );
    });

    test('toString names the outpoint and the locator and renders no script '
        'bytes', () {
      final text = _input(script: Uint8List.fromList([0xde, 0xad])).toString();
      expect(text, contains(_txid));
      expect(text, contains('KeyRef(#1)'));
      expect(text, contains('2 bytes'));
      expect(text, isNot(contains('dead')));
      expect(text, isNot(contains('222')));
    });
  });
}
