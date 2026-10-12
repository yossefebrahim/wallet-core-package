/// The Approach A signing core against the real host library: the T1.10
/// vector byte for byte, the tamper check before any key reaches native code,
/// upstream failures as typed errors, the borrowed key handle left as it was,
/// and zero undisposed resources after every call.
///
/// The multi-key injection has its own file, `signing_core_multikey_native_test.dart`.
///
/// Skips when the library is absent; `WCF_NATIVE_REQUIRED=1` turns that into
/// a failure (see `../support/host_library.dart`).
@Tags(['native'])
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/protobuf.dart' show CodedBufferReader;
import 'package:wallet_core_flutter/advanced.dart';
import 'package:wallet_core_flutter/src/engine/handles.dart';
import 'package:wallet_core_flutter/src/engine/secret_buffers.dart'
    show secretData;
import 'package:wallet_core_flutter/src/errors/errors.dart';
import 'package:wallet_core_flutter/src/families/evm/evm_family.dart';
import 'package:wallet_core_flutter/src/requests/requests.dart';
import 'package:wallet_core_flutter/src/signing/key_locator.dart';
import 'package:wallet_core_flutter/src/signing/sign_result.dart';
import 'package:wallet_core_flutter/src/signing/signing_core.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart' show Coin;
// ignore: implementation_imports
import 'package:wallet_core_flutter_bindings/src/generated/proto/Ethereum.pb.dart'
    as eth;

import '../support/fixtures.dart';
import '../support/host_library.dart';
import 'evm_vector.dart';
import 'signing_support.dart';

const String _vectorId = 'ethereum-sign-eip1559-1';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Whether [haystack] contains [needle] as a contiguous run. A boolean, so a
/// failing assertion prints neither.
bool _containsRun(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}

Uint8List _unhex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

void main() {
  final skip = hostLibrarySkipReason();

  group('SyncSigningCore against the host library', skip: skip, () {
    late WalletCoreBindings bindings;
    late Map<dynamic, dynamic> input;
    late Map<dynamic, dynamic> expected;

    late LeakTracker tracker;
    late SyncSigningCore core;
    late int nativeSignCalls;
    final handles = <PrivateKeyHandle>[];

    setUpAll(() {
      bindings = openHostBindings();
      final vector = vectorById(loadInventory(), _vectorId);
      input = vector.input as Map<dynamic, dynamic>;
      expected = vector.expected as Map<dynamic, dynamic>;
    });

    setUp(() {
      tracker = LeakTracker.maybeCreate()!;
      final context = NativeContext(bindings, observer: tracker);
      nativeSignCalls = 0;
      core = SyncSigningCore(
        context,
        anySignerSign: (Pointer<Void> data, TWCoinType coin) {
          nativeSignCalls++;
          return bindings.TWAnySignerSign(data, coin);
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

    /// The vector's published test key, in a fresh list per test.
    Uint8List vectorKey() => _unhex(input['private_key'] as String);

    /// A handle over [raw], disposed by `tearDown`.
    PrivateKeyHandle handleOf(Uint8List raw) {
      final handle = privateKeyHandleOf(core.context, raw);
      handles.add(handle);
      return handle;
    }

    /// The vector's key as the one primary key.
    Map<KeyRole, PrivateKeyHandle> vectorKeys() => {
      KeyRole.primary: handleOf(vectorKey()),
    };
    const roles = [KeyRole.primary];

    final usedKeys = {KeyLocator.imported(issueKeyRef(1))};

    test("reproduces the vector's encoded, v, r and s byte for byte", () {
      final keyless = evmFamily.encodeKeylessInput(vectorRequest(input));
      final keys = vectorKeys();
      final disposedBefore = tracker.report.disposed;
      final result = core.sign(
        keyless,
        family: evmFamily,
        coin: Coin.ethereum,
        requiredRoles: roles,
        keys: keys,
        usedKeys: usedKeys,
      );
      expect(_hex(result.encoded), expected['encoded']);
      expect(_hex(result.v), expected['v']);
      expect(_hex(result.r), expected['r']);
      expect(_hex(result.s), expected['s']);
      expect(result.coin, Coin.ethereum);
      expect(result.usedKeys, usedKeys);
      expect(nativeSignCalls, 1);
      // The key's TWData, the keyed input and the output: all created inside
      // the call, all disposed before it returned. The handle is borrowed and
      // is still the test's.
      expect(tracker.report.disposed - disposedBefore, 3);
      expect(keys[KeyRole.primary]!.isDisposed, isFalse);
    });

    test('the key handle is borrowed: still usable after the call, and '
        'signing again with it gives the same bytes', () {
      final keys = vectorKeys();
      final keyless = evmFamily.encodeKeylessInput(vectorRequest(input));
      EvmSignResult sign() => core.sign(
        keyless,
        family: evmFamily,
        coin: Coin.ethereum,
        requiredRoles: roles,
        keys: keys,
        usedKeys: usedKeys,
      );
      final first = sign();
      expect(keys[KeyRole.primary]!.isDisposed, isFalse);
      expect(listEquals(sign().encoded, first.encoded), isTrue);
      expect(_hex(first.encoded), expected['encoded']);
    });

    test('the keyed input upstream receives is the key field, then the '
        'key-less bytes: the key is prepended, not appended', () {
      Uint8List? received;
      final capturing = SyncSigningCore(
        core.context,
        anySignerSign: (Pointer<Void> data, TWCoinType coin) {
          final size = bindings.TWDataSize(data);
          received = Uint8List.fromList(
            bindings.TWDataBytes(data).asTypedList(size),
          );
          return bindings.TWAnySignerSign(data, coin);
        },
      );
      final keyless = evmFamily.encodeKeylessInput(vectorRequest(input));
      final key = vectorKey();
      final result = capturing.sign(
        keyless,
        family: evmFamily,
        coin: Coin.ethereum,
        requiredRoles: roles,
        keys: {KeyRole.primary: handleOf(Uint8List.fromList(key))},
        usedKeys: usedKeys,
      );
      expect(_hex(result.encoded), expected['encoded']);
      final header = lengthDelimitedHeader(9, key.length);
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
        reason: 'the key directly follows its tag and length',
      );
      expect(
        listEquals(bytes.sublist(header.length + key.length), keyless),
        isTrue,
        reason: 'the key-less bytes follow, unchanged',
      );
      bytes.fillRange(0, bytes.length, 0);
    });

    group('a key-less input that ends inside a length-delimited field', () {
      // A contract call whose calldata is exactly as long as the key field
      // (tag, length, 32-byte key), cut so that the bytes end right after the
      // calldata's length prefix. Appended, the key field would become the
      // calldata (REVIEW B finding 1).
      late Uint8List truncated;
      late int keyFieldLength;

      setUp(() {
        keyFieldLength = lengthDelimitedHeader(9, 32).length + 32;
        final complete = evmFamily.encodeKeylessInput(
          EvmTransactionRequest.contractCall(
            coin: Coin.ethereum,
            chainId: 1,
            nonce: BigInt.one,
            to: input['to_address'] as String,
            data: Uint8List(keyFieldLength)..fillRange(0, keyFieldLength, 0xaa),
            maxFeePerGas: BigInt.one,
            maxPriorityFeePerGas: BigInt.one,
            gasLimit: BigInt.from(60000),
          ),
        );
        truncated = Uint8List.sublistView(
          complete,
          0,
          complete.length - keyFieldLength,
        );
      });

      test('is rejected before the key is read or copied anywhere', () {
        final keys = vectorKeys();
        final disposedBefore = tracker.report.disposed;
        expect(
          () => core.sign(
            truncated,
            family: evmFamily,
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
        expect(nativeSignCalls, 0);
        expect(
          tracker.report.disposed - disposedBefore,
          0,
          reason: 'no key TWData, no staging, no TWData',
        );
      });

      test('even with the check bypassed, the keyed bytes put the key in its '
          'own field and never inside another', () {
        final key = vectorKey();
        final field = evmFamily.injectionField(KeyRole.primary);
        final keyed = Uint8List.fromList([
          for (final part in keyedInputParts(truncated, [(field, key)]))
            ...part,
        ]);
        // The first field on the wire is private_key, holding the key.
        final reader = CodedBufferReader(keyed);
        expect(reader.readTag(), (9 << 3) | 2);
        expect(listEquals(reader.readBytes(), key), isTrue);

        // The layout prepending replaced: the same bytes appended decode as a
        // complete message whose calldata *is* the key field.
        final appended = Uint8List.fromList([
          ...truncated,
          ...lengthDelimitedHeader(9, key.length),
          ...key,
        ]);
        final swallowed = evmFamily.decodeSigningInput(appended);
        expect(
          swallowed.hasField(9),
          isFalse,
          reason: 'appended, the key is not the private_key field',
        );

        // And upstream, handed the prepended bytes without the check, does
        // not produce a transaction carrying the key.
        final data = secretData(core.context, keyed);
        try {
          final out = TWDataHandle.adopt(
            core.context,
            bindings.TWAnySignerSign(
              data.pointer,
              TWCoinType.TWCoinTypeEthereum,
            ),
          );
          try {
            final output = out.copyBytes();
            expect(_containsRun(output, key), isFalse);
          } finally {
            out.dispose();
          }
        } finally {
          data.dispose();
        }
        keyed.fillRange(0, keyed.length, 0);
        appended.fillRange(0, appended.length, 0);
      });
    });

    test('rejects key-less bytes carrying private_key before the key reaches '
        'native code', () {
      final keyless = evmFamily.encodeKeylessInput(vectorRequest(input));
      final planted = Uint8List(32)..fillRange(0, 32, 0x11);
      final tampered = Uint8List.fromList([
        ...keyless,
        ...lengthDelimitedHeader(9, planted.length),
        ...planted,
      ]);
      final keys = vectorKeys();
      final disposedBefore = tracker.report.disposed;
      Object? caught;
      try {
        core.sign(
          tampered,
          family: evmFamily,
          coin: Coin.ethereum,
          requiredRoles: roles,
          keys: keys,
          usedKeys: usedKeys,
        );
      } on Object catch (error) {
        caught = error;
      }
      expect(
        caught,
        isA<InvalidInputError>().having(
          (e) => e.inputName,
          'inputName',
          'signingInput',
        ),
      );
      expectRedacted(caught!, [_hex(planted), input['private_key'] as String]);
      // No native sign call, and no native object created at all: the key
      // was never copied anywhere.
      expect(nativeSignCalls, 0);
      expect(tracker.report.disposed - disposedBefore, 0);
    });

    test('a coin outside the family is rejected before any native call', () {
      final keys = vectorKeys();
      final disposedBefore = tracker.report.disposed;
      expect(
        () => core.sign(
          evmFamily.encodeKeylessInput(vectorRequest(input)),
          family: evmFamily,
          coin: Coin.bitcoin,
          requiredRoles: roles,
          keys: keys,
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
      expect(nativeSignCalls, 0);
      expect(tracker.report.disposed - disposedBefore, 0);
    });

    test('an upstream failure is a typed SigningError, with every temporary '
        'released and the borrowed key still the caller\'s', () {
      // Well-formed and key-less, but upstream cannot sign it: the recipient
      // is not an address.
      final keyless = eth.SigningInput(
        chainId: <int>[1],
        nonce: <int>[0],
        gasLimit: <int>[0x52, 0x08],
        toAddress: 'not an address',
        txMode: eth.TransactionMode.Enveloped,
        maxInclusionFeePerGas: <int>[1],
        maxFeePerGas: <int>[2],
        transaction: eth.Transaction(
          transfer: eth.Transaction_Transfer(amount: <int>[1]),
        ),
      ).writeToBuffer();
      final key = vectorKey();
      final keys = {KeyRole.primary: handleOf(Uint8List.fromList(key))};
      final disposedBefore = tracker.report.disposed;
      Object? caught;
      try {
        core.sign(
          keyless,
          family: evmFamily,
          coin: Coin.ethereum,
          requiredRoles: roles,
          keys: keys,
          usedKeys: usedKeys,
        );
      } on Object catch (error) {
        caught = error;
      }
      expect(caught, isA<SigningError>());
      final error = caught! as SigningError;
      expect(error.upstreamCode, isPositive);
      expect(error.upstreamCode, isNot(SigningError.malformedOutputCode));
      expectRedacted(error, [_hex(key)]);
      expect(nativeSignCalls, 1);
      // The key's TWData, the keyed input and the output.
      expect(tracker.report.disposed - disposedBefore, 3);
      expect(keys[KeyRole.primary]!.isDisposed, isFalse);
    });

    group('a role defect is a StateError, before any key is read', () {
      Uint8List keyless() => evmFamily.encodeKeylessInput(vectorRequest(input));

      void expectDefect(
        Map<KeyRole, PrivateKeyHandle> keys, {
        List<KeyRole> requiredRoles = roles,
      }) {
        final disposedBefore = tracker.report.disposed;
        expect(
          () => core.sign(
            keyless(),
            family: evmFamily,
            coin: Coin.ethereum,
            requiredRoles: requiredRoles,
            keys: keys,
            usedKeys: usedKeys,
          ),
          throwsStateError,
        );
        expect(nativeSignCalls, 0);
        expect(tracker.report.disposed - disposedBefore, 0);
      }

      test('a required role with no key', () {
        final other = handleOf(vectorKey());
        expectDefect({KeyRole.feePayer: other});
      });

      test('a key for a role the family does not require', () {
        expectDefect({
          KeyRole.primary: handleOf(vectorKey()),
          KeyRole.feePayer: handleOf(vectorKey()),
        });
      });

      test('a listed role the family has no slot for', () {
        expectDefect(
          {
            KeyRole.primary: handleOf(vectorKey()),
            KeyRole.feePayer: handleOf(vectorKey()),
          },
          requiredRoles: [KeyRole.primary, KeyRole.feePayer],
        );
      });

      test('no roles at all, and a repeated role', () {
        expectDefect(const {}, requiredRoles: const []);
        expectDefect(
          vectorKeys(),
          requiredRoles: [KeyRole.primary, KeyRole.primary],
        );
      });
    });
  });
}
