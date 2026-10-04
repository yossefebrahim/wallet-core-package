/// The Approach A signing core against the real host library: the T1.10
/// vector byte for byte, the tamper check before any key reaches native code,
/// upstream failures as typed errors, the caller's key left as it was, and
/// zero undisposed resources after every call.
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
import 'package:wallet_core_flutter/src/engine/secret_buffers.dart'
    show secretData;
import 'package:wallet_core_flutter/src/errors/errors.dart';
import 'package:wallet_core_flutter/src/families/evm/evm_family.dart';
import 'package:wallet_core_flutter/src/requests/requests.dart';
import 'package:wallet_core_flutter/src/signing/key_locator.dart';
import 'package:wallet_core_flutter/src/signing/signing_core.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart' show Coin;

import '../support/fixtures.dart';
import '../support/host_library.dart';
import 'evm_vector.dart';

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
      final report = tracker.report;
      expect(report.live, 0, reason: '$report');
      expect(report.finalizedWithoutDispose, 0, reason: '$report');
      tracker.stop();
    });

    /// The vector's published test key, in a fresh list per test.
    Uint8List vectorKey() => _unhex(input['private_key'] as String);

    final usedKeys = {KeyLocator.imported(issueKeyRef(1))};

    test("reproduces the vector's encoded, v, r and s byte for byte", () {
      final keyless = evmFamily.encodeKeylessInput(vectorRequest(input));
      final result = core.sign(
        keyless,
        family: evmFamily,
        coin: Coin.ethereum,
        privateKey: vectorKey(),
        usedKeys: usedKeys,
      );
      expect(_hex(result.encoded), expected['encoded']);
      expect(_hex(result.v), expected['v']);
      expect(_hex(result.r), expected['r']);
      expect(_hex(result.s), expected['s']);
      expect(result.coin, Coin.ethereum);
      expect(result.usedKeys, usedKeys);
      expect(nativeSignCalls, 1);
      // The keyed input and the output: both created, both disposed.
      expect(tracker.report.disposed, 2);
    });

    test("leaves the caller's key buffer exactly as it was", () {
      final key = vectorKey();
      final before = Uint8List.fromList(key);
      core.sign(
        evmFamily.encodeKeylessInput(vectorRequest(input)),
        family: evmFamily,
        coin: Coin.ethereum,
        privateKey: key,
        usedKeys: usedKeys,
      );
      // Compared without a matcher that would print the key on failure.
      expect(listEquals(key, before), isTrue);
    });

    test('accepts a key that is a view over native memory', () {
      // The shape T1.12b's resolution can hand in: no Dart-heap copy.
      final key = vectorKey();
      final staged = TWDataHandle.fromBytes(core.context, key);
      try {
        final view = bindings.TWDataBytes(staged.pointer)
            .asTypedList(staged.length);
        final result = core.sign(
          evmFamily.encodeKeylessInput(vectorRequest(input)),
          family: evmFamily,
          coin: Coin.ethereum,
          privateKey: view,
          usedKeys: usedKeys,
        );
        expect(_hex(result.encoded), expected['encoded']);
      } finally {
        staged.dispose();
      }
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
        privateKey: key,
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
        expect(
          () => core.sign(
            truncated,
            family: evmFamily,
            coin: Coin.ethereum,
            privateKey: vectorKey(),
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
        expect(tracker.report.disposed, 0, reason: 'no staging, no TWData');
      });

      test('even with the check bypassed, the keyed bytes put the key in its '
          'own field and never inside another', () {
        final key = vectorKey();
        final field = evmFamily.injectionField(KeyRole.primary);
        final keyed = Uint8List.fromList([
          for (final part in keyedInputParts(truncated, field, key)) ...part,
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
      Object? caught;
      try {
        core.sign(
          tampered,
          family: evmFamily,
          coin: Coin.ethereum,
          privateKey: vectorKey(),
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
      expect(tracker.report.disposed, 0);
    });

    test('a coin outside the family is rejected before any native call', () {
      expect(
        () => core.sign(
          evmFamily.encodeKeylessInput(vectorRequest(input)),
          family: evmFamily,
          coin: Coin.bitcoin,
          privateKey: vectorKey(),
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
      expect(tracker.report.disposed, 0);
    });

    // Keys upstream rejects at the pinned tag. (A 31-byte key is not among
    // them: upstream signs with it. The core does not judge key lengths; the
    // keys T1.12b hands it come from upstream's own derivation.)
    for (final (name, keyOf) in <(String, Uint8List Function(Uint8List))>[
      ('empty', (key) => Uint8List(0)),
      ('33-byte', (key) => Uint8List.fromList([...key, 1])),
      ('64-byte', (key) => Uint8List.fromList([...key, ...key])),
      ('all-zero', (key) => Uint8List(32)),
    ]) {
      test('an upstream failure on a $name key is a typed SigningError, with '
          'every temporary released', () {
        final key = keyOf(vectorKey());
        Object? caught;
        try {
          core.sign(
            evmFamily.encodeKeylessInput(vectorRequest(input)),
            family: evmFamily,
            coin: Coin.ethereum,
            privateKey: key,
            usedKeys: usedKeys,
          );
        } on Object catch (error) {
          caught = error;
        }
        expect(caught, isA<SigningError>());
        final error = caught! as SigningError;
        expect(error.upstreamCode, isPositive);
        expect(error.upstreamCode, isNot(SigningError.malformedOutputCode));
        if (key.any((b) => b != 0)) expectRedacted(error, [_hex(key)]);
        expect(nativeSignCalls, 1);
        expect(tracker.report.disposed, 2);
      });
    }
  });
}
