/// The Approach B signing core (T1.13, DECISION-1 evaluation) against the
/// shim host library: the vector `ethereum-sign-eip1559-1` byte for byte
/// through the adapter, equal to Approach A's output for the same key and
/// input; the tamper check before the adapter is called; a `nullptr` from the
/// adapter as a typed [SigningError]; the C adapter's own NULL returns for
/// NULL arguments and non-EVM coins; and zero undisposed resources after
/// every test.
///
/// Skips when the shim library is absent (see `shim_library.dart`);
/// `WCF_NATIVE_SHIM_REQUIRED=1` turns that into a failure.
@Tags(['native', 'shim'])
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;
import 'package:wallet_core_flutter/advanced.dart';
import 'package:wallet_core_flutter/src/coin/chain_family.dart';
import 'package:wallet_core_flutter/src/engine/coin_bridge.dart';
import 'package:wallet_core_flutter/src/errors/errors.dart';
import 'package:wallet_core_flutter/src/families/evm/evm_family.dart';
import 'package:wallet_core_flutter/src/families/family.dart';
import 'package:wallet_core_flutter/src/requests/requests.dart';
import 'package:wallet_core_flutter/src/signing/adapter/adapter_signing_core.dart';
import 'package:wallet_core_flutter/src/signing/key_locator.dart';
import 'package:wallet_core_flutter/src/signing/sign_result.dart';
import 'package:wallet_core_flutter/src/signing/signing_core.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart' show Coin;

import '../../support/fixtures.dart';
import '../../support/host_library.dart' show findHostLibrary;
import '../evm_vector.dart';
import '../signing_support.dart';
import 'shim_library.dart';

const String _vectorId = 'ethereum-sign-eip1559-1';

/// The EVM family with its signing-input message or injection field
/// replaced, for the adapter core's own guards. Everything else delegates.
final class _AlteredEvmFamily
    implements TransactionFamily<EvmTransactionRequest, EvmSignResult> {
  _AlteredEvmFamily({this.signingInput, this.injection});

  final String? signingInput;
  final KeyFieldEntry? injection;

  @override
  ChainFamily get chainFamily => evmFamily.chainFamily;

  @override
  String get signingInputMessage =>
      signingInput ?? evmFamily.signingInputMessage;

  @override
  KeyFieldEntry injectionField(KeyRole role) =>
      injection ?? evmFamily.injectionField(role);

  @override
  Uint8List encodeKeylessInput(EvmTransactionRequest request) =>
      evmFamily.encodeKeylessInput(request);

  @override
  GeneratedMessage decodeSigningInput(Uint8List bytes) =>
      evmFamily.decodeSigningInput(bytes);

  @override
  EvmSignResult parseSigningOutput(
    Uint8List bytes, {
    required Coin coin,
    required Set<KeyLocator> usedKeys,
  }) => evmFamily.parseSigningOutput(bytes, coin: coin, usedKeys: usedKeys);

  @override
  List<KeyRole> requiredRoles(EvmTransactionRequest request) =>
      evmFamily.requiredRoles(request);

  @override
  KeyFieldList get keyFields => evmFamily.keyFields;
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _unhex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

void main() {
  final skip = shimLibrarySkipReason();

  group('AdapterSigningCore against the shim library', skip: skip, () {
    late DynamicLibrary library;
    late WalletCoreBindings bindings;
    late Map<dynamic, dynamic> input;
    late Map<dynamic, dynamic> expected;

    late LeakTracker tracker;
    late NativeContext context;
    late AdapterSigningCore core;
    late int adapterCalls;

    setUpAll(() {
      library = openShimLibrary();
      bindings = WalletCoreBindings(library);
      final vector = vectorById(loadInventory(), _vectorId);
      input = vector.input as Map<dynamic, dynamic>;
      expected = vector.expected as Map<dynamic, dynamic>;
    });

    setUp(() {
      tracker = LeakTracker.maybeCreate()!;
      context = NativeContext(bindings, observer: tracker);
      final real = AdapterSigningCore.bindAdapter(context, library);
      adapterCalls = 0;
      core = AdapterSigningCore(
        context,
        library,
        adapterSign: (keyless, key, coin) {
          adapterCalls++;
          return real(keyless, key, coin);
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
      final result = withKeyHandle(
        context,
        vectorKey(),
        (key) => core.sign(
          keyless,
          family: evmFamily,
          coin: Coin.ethereum,
          privateKey: key,
          usedKeys: usedKeys,
        ),
      );
      expect(_hex(result.encoded), expected['encoded']);
      expect(_hex(result.v), expected['v']);
      expect(_hex(result.r), expected['r']);
      expect(_hex(result.s), expected['s']);
      expect(result.coin, Coin.ethereum);
      expect(result.usedKeys, usedKeys);
      expect(adapterCalls, 1);
      // The test's staging TWData and key, then the core's key-less input and
      // the output. The adapter's own two TWData objects are created and
      // deleted in C and never reach the tracker.
      expect(tracker.report.disposed, 4);
    });

    test("equals Approach A's output for the same key and input", () {
      final keyless = evmFamily.encodeKeylessInput(vectorRequest(input));
      final (a, b) = withKeyHandle(context, vectorKey(), (key) {
        final viaA = SyncSigningCore(context).sign(
          keyless,
          family: evmFamily,
          coin: Coin.ethereum,
          privateKey: key,
          usedKeys: usedKeys,
        );
        final viaB = core.sign(
          keyless,
          family: evmFamily,
          coin: Coin.ethereum,
          privateKey: key,
          usedKeys: usedKeys,
        );
        return (viaA, viaB);
      });
      expect(listEquals(a.encoded, b.encoded), isTrue);
      expect(listEquals(a.v, b.v), isTrue);
      expect(listEquals(a.r, b.r), isTrue);
      expect(listEquals(a.s, b.s), isTrue);
    });

    test('rejects key-less bytes carrying private_key before the adapter is '
        'called', () {
      final keyless = evmFamily.encodeKeylessInput(vectorRequest(input));
      final planted = Uint8List(32)..fillRange(0, 32, 0x11);
      final tampered = Uint8List.fromList([
        ...keyless,
        ...lengthDelimitedHeader(adapterPrivateKeyField, planted.length),
        ...planted,
      ]);
      Object? caught;
      withKeyHandle(context, vectorKey(), (key) {
        try {
          core.sign(
            tampered,
            family: evmFamily,
            coin: Coin.ethereum,
            privateKey: key,
            usedKeys: usedKeys,
          );
        } on Object catch (error) {
          caught = error;
        }
      });
      expect(
        caught,
        isA<InvalidInputError>().having(
          (e) => e.inputName,
          'inputName',
          'signingInput',
        ),
      );
      expectRedacted(caught!, [_hex(planted), input['private_key'] as String]);
      expect(adapterCalls, 0);
      // Only the test's own staging TWData and key: the core created nothing.
      expect(tracker.report.disposed, 2);
    });

    test('a coin outside the family is rejected before the adapter is '
        'called', () {
      withKeyHandle(context, vectorKey(), (key) {
        expect(
          () => core.sign(
            evmFamily.encodeKeylessInput(vectorRequest(input)),
            family: evmFamily,
            coin: Coin.bitcoin,
            privateKey: key,
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
      });
      expect(adapterCalls, 0);
    });

    test('a nullptr from the adapter is a typed SigningError, with every '
        'temporary released', () {
      final failing = AdapterSigningCore(
        context,
        library,
        adapterSign: (keyless, key, coin) {
          adapterCalls++;
          return nullptr;
        },
      );
      Object? caught;
      withKeyHandle(context, vectorKey(), (key) {
        try {
          failing.sign(
            evmFamily.encodeKeylessInput(vectorRequest(input)),
            family: evmFamily,
            coin: Coin.ethereum,
            privateKey: key,
            usedKeys: usedKeys,
          );
        } on Object catch (error) {
          caught = error;
        }
      });
      expect(
        caught,
        isA<SigningError>().having(
          (e) => e.upstreamCode,
          'upstreamCode',
          SigningError.malformedOutputCode,
        ),
      );
      expectRedacted(caught!, [input['private_key'] as String]);
      expect(adapterCalls, 1);
      // The test's two, and the core's key-less input.
      expect(tracker.report.disposed, 3);
    });

    test('a truncated key-less input never reaches the adapter', () {
      Object? caught;
      withKeyHandle(context, vectorKey(), (key) {
        try {
          core.sign(
            truncatedKeylessInput(input['to_address'] as String),
            family: evmFamily,
            coin: Coin.ethereum,
            privateKey: key,
            usedKeys: usedKeys,
          );
        } on Object catch (error) {
          caught = error;
        }
      });
      expect(
        caught,
        isA<InvalidInputError>().having(
          (e) => e.inputName,
          'inputName',
          'signingInput',
        ),
      );
      expect(adapterCalls, 0);
      // Only the test's own staging TWData and key: the core created nothing.
      expect(tracker.report.disposed, 2);
    });

    test('a family whose injection field is not the one the adapter writes '
        'is a StateError, before the adapter is called', () {
      final wrongField = _AlteredEvmFamily(
        injection: const KeyFieldEntry(
          messagePath: adapterSigningInputMessage,
          fieldName: 'private_key',
          fieldNumber: adapterPrivateKeyField + 1,
          repeated: false,
        ),
      );
      withKeyHandle(context, vectorKey(), (key) {
        expect(
          () => core.sign(
            evmFamily.encodeKeylessInput(vectorRequest(input)),
            family: wrongField,
            coin: Coin.ethereum,
            privateKey: key,
            usedKeys: usedKeys,
          ),
          throwsStateError,
        );
      });
      expect(adapterCalls, 0);
      expect(tracker.report.disposed, 2);
    });

    test("a family whose signing input is not the adapter's is "
        "UnsupportedOperationError('signing-adapter'), before any check or "
        'native call', () {
      final otherMessage = _AlteredEvmFamily(
        signingInput: 'TW.Solana.Proto.SigningInput',
      );
      withKeyHandle(context, vectorKey(), (key) {
        expect(
          () => core.sign(
            evmFamily.encodeKeylessInput(vectorRequest(input)),
            family: otherMessage,
            coin: Coin.ethereum,
            privateKey: key,
            usedKeys: usedKeys,
          ),
          throwsA(
            isA<UnsupportedOperationError>().having(
              (e) => e.capability,
              'capability',
              'signing-adapter',
            ),
          ),
        );
      });
      expect(adapterCalls, 0);
      expect(tracker.report.disposed, 2);
    });

    test('bindAdapter refuses a library that is not the image behind the '
        'context (macOS: two opened files)', () {
      final standard = findHostLibrary();
      if (standard == null) {
        markTestSkipped('the standard host library is absent');
        return;
      }
      final standardContext = NativeContext(
        WalletCoreBindings(DynamicLibrary.open(standard)),
      );
      expect(
        () => AdapterSigningCore.bindAdapter(standardContext, library),
        throwsStateError,
      );
      expect(
        () => AdapterSigningCore(standardContext, library),
        throwsStateError,
      );
    });

    group('the C adapter itself returns NULL, and does not crash,', () {
      late AdapterSign raw;
      setUp(() => raw = AdapterSigningCore.bindAdapter(context, library));

      final ethereum = twCoinTypeOf(Coin.ethereum).value;

      test('for a NULL key', () {
        final keyless = TWDataHandle.fromBytes(
          context,
          evmFamily.encodeKeylessInput(vectorRequest(input)),
        );
        try {
          expect(raw(keyless.pointer, nullptr, ethereum), nullptr);
        } finally {
          keyless.dispose();
        }
      });

      test('for a NULL input', () {
        withKeyHandle(context, vectorKey(), (key) {
          expect(raw(nullptr, key.pointer, ethereum), nullptr);
        });
      });

      for (final coin in [Coin.bitcoin, Coin.solana]) {
        test('for ${coin.id}, whose blockchain is not Ethereum', () {
          final keyless = TWDataHandle.fromBytes(
            context,
            evmFamily.encodeKeylessInput(vectorRequest(input)),
          );
          try {
            withKeyHandle(context, vectorKey(), (key) {
              expect(
                raw(keyless.pointer, key.pointer, twCoinTypeOf(coin).value),
                nullptr,
              );
            });
          } finally {
            keyless.dispose();
          }
        });
      }
    });

    test('an empty key-less input still reaches upstream, whose failure is '
        'a typed SigningError, not a NULL', () {
      // Empty bytes are a valid, all-default SigningInput: the adapter does
      // not judge it, upstream rejects it with its own error code.
      Object? caught;
      withKeyHandle(context, vectorKey(), (key) {
        try {
          core.sign(
            Uint8List(0),
            family: evmFamily,
            coin: Coin.ethereum,
            privateKey: key,
            usedKeys: usedKeys,
          );
        } on Object catch (error) {
          caught = error;
        }
      });
      expect(caught, isA<SigningError>());
      final error = caught! as SigningError;
      expect(error.upstreamCode, isNot(SigningError.malformedOutputCode));
      expectRedacted(error, [input['private_key'] as String]);
      expect(adapterCalls, 1);
    });
  });
}
