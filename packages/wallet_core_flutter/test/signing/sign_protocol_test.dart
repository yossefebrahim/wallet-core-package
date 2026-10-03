// The `Sign` and `Signed` protocol values: plain, immutable, key-less, and
// rendered without anything a log could not hold. No library needed.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/src/signing/key_locator.dart'
    show issueKeyRef;
import 'package:wallet_core_flutter/src/signing/sign_result.dart'
    show withUsedKeys;
import 'package:wallet_core_flutter/src/worker/protocol.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';

import 'signing_support.dart';

const String _to = '0xB9F5771C27664bF2282D98E09D7F50cEc7cB01a7';

HdLocatorSpec _hd({int token = 3, int ref = 1, KeyRole? role}) => HdLocatorSpec(
  sessionToken: token,
  walletRef: ref,
  coin: Coin.ethereum,
  derivationPath: "m/44'/60'/0'/0/0",
  role: role,
);

void main() {
  test('Sign renders the request and every locator name, and is an '
      'operation with the signing name', () {
    final sign = Sign(
      9,
      request: transferTo(_to),
      keys: {
        _hd(),
        const ImportedLocatorSpec(keyRef: 4, role: KeyRole.feePayer),
        const ExternalLocatorSpec(deviceId: 'ledger-1'),
      },
    );
    expect(
      sign.toString(),
      'Sign(#9, EvmTransactionRequest.transfer(ethereum, chainId: 1, '
      'nonce: 6, to: $_to, valueWei: 543210987654321, gasLimit: 21100, '
      'maxFeePerGas: 3000000000, maxPriorityFeePerGas: 2000000000), '
      "keys: hdPath(session: 3, wallet: 1, ethereum, m/44'/60'/0'/0/0), "
      'imported(key: 4, role: feePayer), external(ledger-1))',
    );
    expect(sign.operation, 'sign');
    expect(sign.isControl, isFalse);
  });

  test('Sign copies its key set and exposes it unmodifiable', () {
    final keys = <LocatorSpec>{_hd()};
    final sign = Sign(1, request: transferTo(_to), keys: keys);
    keys.add(_hd(ref: 2));
    expect(sign.keys, {_hd()});
    expect(() => sign.keys.add(_hd(ref: 3)), throwsUnsupportedError);
  });

  test('locator specs are equal by content, so equal names fold', () {
    expect(_hd(), _hd());
    expect(_hd().hashCode, _hd().hashCode);
    expect(_hd(), isNot(_hd(token: 4)));
    expect(_hd(), isNot(_hd(ref: 2)));
    expect(_hd(), isNot(_hd(role: KeyRole.primary)));
    expect({_hd(), _hd(), _hd(role: KeyRole.primary)}, hasLength(2));
    expect(
      const ImportedLocatorSpec(keyRef: 1),
      const ImportedLocatorSpec(keyRef: 1),
    );
    expect(
      const ExternalLocatorSpec(deviceId: 'd'),
      isNot(const ExternalLocatorSpec(deviceId: 'd', role: KeyRole.primary)),
    );
  });

  test('Signed renders the result by coin, length, and key count only', () {
    final signed = Signed(
      5,
      EvmSignResult(
        coin: Coin.ethereum,
        encoded: Uint8List.fromList(List<int>.filled(110, 0xab)),
        v: Uint8List(1),
        r: Uint8List.fromList(List<int>.filled(32, 0xcd)),
        s: Uint8List.fromList(List<int>.filled(32, 0xef)),
        usedKeys: const <KeyLocator>{},
      ),
    );
    expect(
      signed.toString(),
      'Signed(#5, EvmSignResult(ethereum, encoded: 110 bytes, usedKeys: 0))',
    );
    expect(signed.toString(), isNot(contains('abab')));
    expect(signed.toString(), isNot(contains('cdcd')));
  });

  test('withUsedKeys keeps every byte and replaces only usedKeys', () {
    final original = EvmSignResult(
      coin: Coin.ethereum,
      encoded: Uint8List.fromList([2, 3, 4]),
      v: Uint8List.fromList([1]),
      r: Uint8List.fromList([5]),
      s: Uint8List.fromList([6]),
      preHash: Uint8List.fromList([7]),
      usedKeys: const <KeyLocator>{},
    );
    final keys = {KeyLocator.imported(issueKeyRef(1))};
    final rebound = withUsedKeys(original, keys) as EvmSignResult;
    expect(rebound.encoded, original.encoded);
    expect(rebound.v, original.v);
    expect(rebound.r, original.r);
    expect(rebound.s, original.s);
    expect(rebound.preHash, original.preHash);
    expect(rebound.coin, original.coin);
    expect(rebound.usedKeys, keys);
    expect(original.usedKeys, isEmpty);
  });
}
