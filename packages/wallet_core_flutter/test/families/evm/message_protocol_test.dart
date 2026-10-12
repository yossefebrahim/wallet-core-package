// The `SignMessage` and `MessageSigned` protocol values and `EvmMessageSignResult`:
// plain, immutable, key-less, and rendered without the message. No library
// needed.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/src/errors/boundary.dart'
    show NativeResultError;
import 'package:wallet_core_flutter/src/signing/key_locator.dart'
    show issueKeyRef;
import 'package:wallet_core_flutter/src/signing/sign_result.dart'
    show withUsedKeys;
import 'package:wallet_core_flutter/src/worker/handler.dart'
    show softNativeFailure;
import 'package:wallet_core_flutter/src/worker/protocol.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';

HdLocatorSpec _hd({int ref = 1, KeyRole? role}) => HdLocatorSpec(
  sessionToken: 3,
  walletRef: ref,
  coin: Coin.ethereum,
  derivationPath: "m/44'/60'/0'/0/0",
  role: role,
);

EvmMessageRequest _request(String text) => EvmMessageRequest.personal(
  Uint8List.fromList(utf8.encode(text)),
  coin: Coin.ethereum,
);

void main() {
  test('SignMessage renders the request by length and every locator name, '
      'never the message', () {
    final sign = SignMessage(
      9,
      request: _request('a private note'),
      keys: {
        _hd(),
        const ExternalLocatorSpec(deviceId: 'ledger-1'),
      },
    );
    expect(
      sign.toString(),
      'SignMessage(#9, EvmMessageRequest.personal(ethereum, 14 bytes), '
      "keys: hdPath(session: 3, wallet: 1, ethereum, m/44'/60'/0'/0/0), "
      'external(ledger-1))',
    );
    expect(sign.toString(), isNot(contains('private note')));
    expect(sign.operation, 'signMessage');
    expect(sign.isControl, isFalse);
  });

  test('SignMessage copies its key set and exposes it unmodifiable', () {
    final keys = <LocatorSpec>{_hd()};
    final sign = SignMessage(1, request: _request('Foo'), keys: keys);
    keys.add(_hd(ref: 2));
    expect(sign.keys, {_hd()});
    expect(() => sign.keys.add(_hd(ref: 3)), throwsUnsupportedError);
  });

  test('a soft native failure of SignMessage is the malformed-output '
      'SigningError, as for Sign', () {
    final error = softNativeFailure(
      SignMessage(2, request: _request('Foo'), keys: {_hd()}),
      const NativeResultError('TWMessageSignerSign returned nullptr'),
    );
    expect(
      error,
      isA<SigningError>()
          .having(
            (e) => e.upstreamCode,
            'upstreamCode',
            SigningError.malformedOutputCode,
          )
          .having((e) => e.message, 'message', contains('unusable result')),
    );
  });

  test('withUsedKeys puts the locators back on an EvmMessageSignResult and '
      'changes nothing else', () {
    final wire = EvmMessageSignResult(
      coin: Coin.ethereum,
      messageType: EvmMessageType.typedData,
      signature: Uint8List.fromList(List<int>.generate(65, (i) => i)),
      usedKeys: const <KeyLocator>{},
    );
    final locator = KeyLocator.imported(issueKeyRef(1));
    final back = withUsedKeys(wire, {locator});
    expect(back, isA<EvmMessageSignResult>());
    final result = back as EvmMessageSignResult;
    expect(result.usedKeys, {locator});
    expect(result.signature, wire.signature);
    expect(result.messageType, EvmMessageType.typedData);
    expect(result.coin, Coin.ethereum);
    expect(() => result.usedKeys.add(locator), throwsUnsupportedError);
  });

  test('EvmMessageSignResult copies its signature and renders it as '
      'lowercase hexadecimal', () {
    final source = Uint8List.fromList(List<int>.filled(65, 0xAB));
    final result = EvmMessageSignResult(
      coin: Coin.ethereum,
      messageType: EvmMessageType.personal,
      signature: source,
      usedKeys: const <KeyLocator>{},
    );
    source[0] = 0;
    expect(result.signature.first, 0xAB);
    expect(result.signatureHex, 'ab' * 65);
    expect(() => result.signature[0] = 1, throwsUnsupportedError);
  });

  test('MessageSigned renders its result', () {
    final reply = MessageSigned(
      4,
      EvmMessageSignResult(
        coin: Coin.ethereum,
        messageType: EvmMessageType.personal,
        signature: Uint8List(65),
        usedKeys: const <KeyLocator>{},
      ),
    );
    expect(
      reply.toString(),
      'MessageSigned(#4, EvmMessageSignResult(ethereum, personal, '
      'signature: 65 bytes, usedKeys: 0))',
    );
  });
}
