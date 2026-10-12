/// The message path of the Approach A signing core against the real host
/// library: both EVM message vectors byte for byte through
/// `TWMessageSignerSign` (the protobuf entry point), the key prepended and
/// borrowed exactly as for transactions, the tamper check before any key is
/// read, upstream's refusals as typed errors, and zero undisposed resources
/// after every call.
///
/// **Which entry point the vectors were asserted through.** Both vectors are
/// asserted upstream through the C `TWEthereumMessageSigner` API, the legacy
/// variant; the personal one is also asserted through the protobuf entry
/// point by upstream's own Rust twin test. These tests are the proof for the
/// typed-data vector, which upstream has no protobuf test for: the protobuf
/// path with `MessageType_typed` and no chain id gives the C API's signature
/// byte for byte.
///
/// Skips when the library is absent; `WCF_NATIVE_REQUIRED=1` turns that into
/// a failure (see `../../support/host_library.dart`).
@Tags(['native'])
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/advanced.dart';
import 'package:wallet_core_flutter/src/engine/handles.dart';
import 'package:wallet_core_flutter/src/errors/errors.dart';
import 'package:wallet_core_flutter/src/families/evm/message_family.dart';
import 'package:wallet_core_flutter/src/requests/requests.dart';
import 'package:wallet_core_flutter/src/signing/key_locator.dart';
import 'package:wallet_core_flutter/src/signing/sign_result.dart';
import 'package:wallet_core_flutter/src/signing/signing_core.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart' show Coin;
// ignore: implementation_imports
import 'package:wallet_core_flutter_bindings/src/generated/proto/Ethereum.pb.dart'
    as eth;

import '../../signing/signing_support.dart';
import '../../support/host_library.dart';
import 'message_vector.dart';

void main() {
  final skip = hostLibrarySkipReason();

  group('SyncSigningCore.signMessage against the host library', skip: skip, () {
    late WalletCoreBindings bindings;
    late MessageVector personal;
    late MessageVector typed;

    late LeakTracker tracker;
    late SyncSigningCore core;
    late int messageSignerCalls;
    late int anySignerCalls;
    final handles = <PrivateKeyHandle>[];

    setUpAll(() {
      bindings = openHostBindings();
      personal = MessageVector.load(personalVectorId);
      typed = MessageVector.load(typedDataVectorId);
    });

    setUp(() {
      tracker = LeakTracker.maybeCreate()!;
      final context = NativeContext(bindings, observer: tracker);
      messageSignerCalls = 0;
      anySignerCalls = 0;
      core = SyncSigningCore(
        context,
        anySignerSign: (Pointer<Void> data, TWCoinType coin) {
          anySignerCalls++;
          return bindings.TWAnySignerSign(data, coin);
        },
        messageSignerSign: (TWCoinType coin, Pointer<Void> data) {
          messageSignerCalls++;
          return bindings.TWMessageSignerSign(coin, data);
        },
      );
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

    PrivateKeyHandle handleOf(MessageVector vector) {
      final handle = privateKeyHandleOf(
        core.context,
        unhex(vector.privateKeyHex),
      );
      handles.add(handle);
      return handle;
    }

    final usedKeys = {KeyLocator.imported(issueKeyRef(1))};
    const roles = [KeyRole.primary];

    EvmMessageSignResult signPersonal(
      MessageVector vector, {
      SyncSigningCore? with_,
    }) {
      final request = personalRequest(vector);
      return (with_ ?? core).signMessage(
        evmPersonalMessageFamily.encodeKeylessInput(request),
        family: evmPersonalMessageFamily,
        coin: Coin.ethereum,
        requiredRoles: roles,
        keys: {KeyRole.primary: handleOf(vector)},
        usedKeys: usedKeys,
      );
    }

    test('personal: reproduces the vector signature byte for byte — 65 bytes, '
        'v = 0x1b, through the message signer and not the transaction '
        'signer', () {
      final keys = {KeyRole.primary: handleOf(personal)};
      final disposedBefore = tracker.report.disposed;
      final result = core.signMessage(
        evmPersonalMessageFamily.encodeKeylessInput(personalRequest(personal)),
        family: evmPersonalMessageFamily,
        coin: Coin.ethereum,
        requiredRoles: roles,
        keys: keys,
        usedKeys: usedKeys,
      );
      expect(result.signatureHex, personal.signature);
      expect(result.signature, hasLength(65));
      expect(result.signature.last, 0x1b);
      expect(result.messageType, EvmMessageType.personal);
      expect(result.coin, Coin.ethereum);
      expect(result.usedKeys, usedKeys);
      expect(messageSignerCalls, 1);
      expect(anySignerCalls, 0);
      // The key's TWData, the keyed input and the output: created inside the
      // call, disposed before it returned. The handle is borrowed.
      expect(tracker.report.disposed - disposedBefore, 3);
      expect(keys[KeyRole.primary]!.isDisposed, isFalse);
    });

    test('typed data: reproduces the vector signature byte for byte — '
        'MessageType_typed, no chain id, v = 0x1c', () {
      final result = core.signMessage(
        evmTypedDataMessageFamily.encodeKeylessInput(typedDataRequest(typed)),
        family: evmTypedDataMessageFamily,
        coin: Coin.ethereum,
        requiredRoles: roles,
        keys: {KeyRole.primary: handleOf(typed)},
        usedKeys: usedKeys,
      );
      expect(result.signatureHex, typed.signature);
      expect(result.signature, hasLength(65));
      expect(result.signature.last, 0x1c);
      expect(result.messageType, EvmMessageType.typedData);
      expect(messageSignerCalls, 1);
      expect(anySignerCalls, 0);
    });

    test('the same key signs twice with the same bytes', () {
      final first = signPersonal(personal);
      final second = signPersonal(personal);
      expect(listEquals(first.signature, second.signature), isTrue);
      expect(first.signatureHex, personal.signature);
    });

    test('the keyed input upstream receives is the key field (1), then the '
        'key-less bytes: prepended, as for transactions', () {
      Uint8List? received;
      final capturing = SyncSigningCore(
        core.context,
        messageSignerSign: (TWCoinType coin, Pointer<Void> data) {
          final size = bindings.TWDataSize(data);
          received = Uint8List.fromList(
            bindings.TWDataBytes(data).asTypedList(size),
          );
          return bindings.TWMessageSignerSign(coin, data);
        },
      );
      final keyless = evmPersonalMessageFamily.encodeKeylessInput(
        personalRequest(personal),
      );
      final key = unhex(personal.privateKeyHex);
      final result = capturing.signMessage(
        keyless,
        family: evmPersonalMessageFamily,
        coin: Coin.ethereum,
        requiredRoles: roles,
        keys: {KeyRole.primary: handleOf(personal)},
        usedKeys: usedKeys,
      );
      expect(result.signatureHex, personal.signature);
      final header = lengthDelimitedHeader(1, key.length);
      final bytes = received!;
      expect(bytes.length, header.length + key.length + keyless.length);
      // Compared as booleans, so a failure prints no key byte.
      expect(listEquals(bytes.sublist(0, header.length), header), isTrue);
      expect(
        listEquals(
          bytes.sublist(header.length, header.length + key.length),
          key,
        ),
        isTrue,
      );
      expect(
        listEquals(bytes.sublist(header.length + key.length), keyless),
        isTrue,
      );
      bytes.fillRange(0, bytes.length, 0);
      key.fillRange(0, key.length, 0);
    });

    test('rejects key-less bytes carrying private_key before the key reaches '
        'native code', () {
      final planted = Uint8List(32)..fillRange(0, 32, 0x11);
      final tampered = eth.MessageSigningInput(
        message: 'Foo',
        privateKey: planted,
      ).writeToBuffer();
      final keys = {KeyRole.primary: handleOf(personal)};
      final disposedBefore = tracker.report.disposed;
      expect(
        () => core.signMessage(
          tampered,
          family: evmPersonalMessageFamily,
          coin: Coin.ethereum,
          requiredRoles: roles,
          keys: keys,
          usedKeys: usedKeys,
        ),
        throwsA(
          isA<InvalidInputError>().having(
            (e) => e.inputName,
            'inputName',
            'signingInput',
          ),
        ),
      );
      expect(messageSignerCalls, 0);
      expect(tracker.report.disposed - disposedBefore, 0);
    });

    test('a transaction input is not accepted as a message input', () {
      final transaction = eth.SigningInput(privateKey: Uint8List(32))
          .writeToBuffer();
      expect(
        () => core.signMessage(
          transaction,
          family: evmPersonalMessageFamily,
          coin: Coin.ethereum,
          requiredRoles: roles,
          keys: {KeyRole.primary: handleOf(personal)},
          usedKeys: usedKeys,
        ),
        throwsA(isA<InvalidInputError>()),
      );
      expect(messageSignerCalls, 0);
    });

    test(
      'a coin outside the EVM family is rejected before any native call',
      () {
        expect(
          () => core.signMessage(
            evmPersonalMessageFamily.encodeKeylessInput(
              personalRequest(personal),
            ),
            family: evmPersonalMessageFamily,
            coin: Coin.bitcoin,
            requiredRoles: roles,
            keys: {KeyRole.primary: handleOf(personal)},
            usedKeys: usedKeys,
          ),
          throwsA(
            isA<InvalidInputError>().having(
              (e) => e.inputName,
              'inputName',
              'coin',
            ),
          ),
        );
        expect(messageSignerCalls, 0);
      },
    );

    test('role defects are StateErrors before any key is read', () {
      final keyless = evmPersonalMessageFamily.encodeKeylessInput(
        personalRequest(personal),
      );
      expect(
        () => core.signMessage(
          keyless,
          family: evmPersonalMessageFamily,
          coin: Coin.ethereum,
          requiredRoles: roles,
          keys: const <KeyRole, PrivateKeyHandle>{},
          usedKeys: usedKeys,
        ),
        throwsStateError,
      );
      expect(
        () => core.signMessage(
          keyless,
          family: evmPersonalMessageFamily,
          coin: Coin.ethereum,
          requiredRoles: const [KeyRole.primary, KeyRole.feePayer],
          keys: {
            KeyRole.primary: handleOf(personal),
            KeyRole.feePayer: handleOf(personal),
          },
          usedKeys: usedKeys,
        ),
        throwsStateError,
      );
      expect(messageSignerCalls, 0);
    });

    test("upstream's refusal of a document that is not EIP-712 is a "
        "SigningError with upstream's own code and message, and nothing "
        'leaks', () {
      final request = EvmMessageRequest.typedData('{}', coin: Coin.ethereum);
      expect(
        () => core.signMessage(
          evmTypedDataMessageFamily.encodeKeylessInput(request),
          family: evmTypedDataMessageFamily,
          coin: Coin.ethereum,
          requiredRoles: roles,
          keys: {KeyRole.primary: handleOf(typed)},
          usedKeys: usedKeys,
        ),
        throwsA(
          isA<SigningError>()
              .having(
                (e) => e.upstreamCode,
                'upstreamCode',
                isNot(SigningError.malformedOutputCode),
              )
              .having((e) => e.upstreamCode, 'upstreamCode', greaterThan(0))
              .having((e) => e.message, 'message', isNotEmpty),
        ),
      );
      expect(messageSignerCalls, 1);
    });

    test('a null from the message signer is a SigningError that names it', () {
      final nulling = SyncSigningCore(
        core.context,
        messageSignerSign: (TWCoinType coin, Pointer<Void> data) => nullptr,
      );
      expect(
        () => signPersonal(personal, with_: nulling),
        throwsA(
          isA<SigningError>()
              .having(
                (e) => e.upstreamCode,
                'upstreamCode',
                SigningError.malformedOutputCode,
              )
              .having(
                (e) => e.message,
                'message',
                'TWMessageSignerSign returned no output',
              ),
        ),
      );
    });
  });
}
