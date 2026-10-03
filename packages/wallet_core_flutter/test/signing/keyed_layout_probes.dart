/// One layout test, two injectors: Approach A's `keyedInputParts` (the one
/// place in Dart that decides the keyed input's layout) and Approach B's
/// `wcf_sign_ethereum` (the one place in C), held to the same layout — the
/// key field **prepended** — by the same probes, with the key-less check
/// bypassed so that each injector's own behaviour is what is observed.
///
/// **How the C layout is observed.** By upstream's own parse of what the
/// adapter builds, on the production shim binary — not by a C test harness,
/// symbol interposition, or a test-only build: the adapter's calls to
/// upstream are direct branches inside the dylib (`llvm-objdump
/// --disassemble-symbols=_wcf_sign_ethereum` shows `bl _TWAnySignerSign`, no
/// symbol stub; only `memcpy` goes through one), so they cannot be
/// interposed; and a test hook
/// compiled only into a test build would test a different binary from the
/// one being evaluated. Upstream's parse is decisive because a singular field
/// that occurs twice takes its **last** value:
///
/// 1. key-less bytes followed by a planted `private_key = K2`: the output is
///    K2's signature, so the injected key precedes the end of the key-less
///    bytes — it was not appended;
/// 2. a planted K2 followed by the key-less bytes: still K2's signature, so
///    the injected key precedes every key-less byte — it is the first field;
/// 3. a well-formed input signs the published vector, so the injected field
///    is tag 9, the right length, and the key;
/// 4. REVIEW B finding 1's truncated input: the output contains no run of the
///    key and is not a signed transaction.
///
/// Approach A's byte-exact capture of the same layout is in
/// `signing_core_native_test.dart`. The probes run from
/// `keyed_layout_native_test.dart` (A, standard host library, tag `native`)
/// and `adapter/keyed_layout_shim_test.dart` (B, shim library, tags `native`
/// and `shim`). Not a test file itself.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/advanced.dart';
import 'package:wallet_core_flutter/src/engine/secret_buffers.dart'
    show secretData, secretDataFromParts;
import 'package:wallet_core_flutter/src/errors/errors.dart';
import 'package:wallet_core_flutter/src/families/evm/evm_family.dart';
import 'package:wallet_core_flutter/src/signing/adapter/adapter_signing_core.dart';
import 'package:wallet_core_flutter/src/signing/key_locator.dart';
import 'package:wallet_core_flutter/src/signing/signing_core.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart' show Coin;

import '../support/fixtures.dart';
import 'evm_vector.dart';
import 'signing_support.dart';

/// Injects [key] into [keyless] the way one approach does and has upstream
/// sign the result for Ethereum; returns upstream's serialized output.
typedef Injector =
    Uint8List Function(NativeContext context, Uint8List keyless, Uint8List key);

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _unhex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

/// Takes ownership of [pointer], copies its bytes out, and releases it.
Uint8List _take(NativeContext context, Pointer<Void> pointer) {
  expect(pointer, isNot(nullptr));
  final output = TWDataHandle.adopt(context, pointer);
  try {
    return output.copyBytes();
  } finally {
    output.dispose();
  }
}

/// Approach A's injector: `keyedInputParts` into `secretDataFromParts`, then
/// `TWAnySignerSign` — `SyncSigningCore`'s steps 3–4, without its checks.
Uint8List injectA(NativeContext context, Uint8List keyless, Uint8List key) {
  final field = evmFamily.injectionField(KeyRole.primary);
  final input = secretDataFromParts(
    context,
    keyedInputParts(keyless, field, key),
  );
  try {
    return _take(
      context,
      context.bindings.TWAnySignerSign(
        input.pointer,
        TWCoinType.TWCoinTypeEthereum,
      ),
    );
  } finally {
    input.dispose();
  }
}

/// Approach B's injector over [library]: the C adapter itself, given a
/// `TWPrivateKey` made from [key], without the Dart core's checks.
Injector injectB(DynamicLibrary library) => (context, keyless, key) {
  final adapter = AdapterSigningCore.bindAdapter(context, library);
  final input = secretData(context, keyless);
  try {
    return withKeyHandle(
      context,
      key,
      (handle) => _take(
        context,
        adapter(
          input.pointer,
          handle.pointer,
          TWCoinType.TWCoinTypeEthereum.value,
        ),
      ),
    );
  } finally {
    input.dispose();
  }
};

void layoutProbes(
  WalletCoreBindings Function() openBindings,
  Injector Function() injector,
) {
  late Map<dynamic, dynamic> input;
  late Map<dynamic, dynamic> expected;
  late WalletCoreBindings bindings;
  late LeakTracker tracker;
  late NativeContext context;
  late Injector inject;

  setUpAll(() {
    bindings = openBindings();
    final vector = vectorById(loadInventory(), 'ethereum-sign-eip1559-1');
    input = vector.input as Map<dynamic, dynamic>;
    expected = vector.expected as Map<dynamic, dynamic>;
  });

  setUp(() {
    tracker = LeakTracker.maybeCreate()!;
    context = NativeContext(bindings, observer: tracker);
    inject = injector();
  });

  tearDown(() {
    final report = tracker.report;
    expect(report.live, 0, reason: '$report');
    expect(report.finalizedWithoutDispose, 0, reason: '$report');
    tracker.stop();
  });

  Uint8List vectorKey() => _unhex(input['private_key'] as String);

  /// A second valid secp256k1 key, planted where the key-less bytes should
  /// have none.
  Uint8List plantedKey() => Uint8List(32)..fillRange(0, 32, 0x11);

  Uint8List keyless() => evmFamily.encodeKeylessInput(vectorRequest(input));

  Uint8List keyField(Uint8List key) =>
      Uint8List.fromList([...lengthDelimitedHeader(9, key.length), ...key]);

  test('a well-formed input signs the published vector', () {
    final output = inject(context, keyless(), vectorKey());
    final result = evmFamily.parseSigningOutput(
      output,
      coin: Coin.ethereum,
      usedKeys: const <KeyLocator>{},
    );
    expect(_hex(result.encoded), expected['encoded']);
  });

  test('a key field planted after the key-less bytes wins: the injected key '
      'is not appended', () {
    final planted = plantedKey();
    final reference = inject(context, keyless(), planted);
    final output = inject(
      context,
      Uint8List.fromList([...keyless(), ...keyField(planted)]),
      vectorKey(),
    );
    expect(listEquals(output, reference), isTrue);
  });

  test('a key field planted before the key-less bytes wins too: the injected '
      'key is the first field', () {
    final planted = plantedKey();
    final reference = inject(context, keyless(), planted);
    final output = inject(
      context,
      Uint8List.fromList([...keyField(planted), ...keyless()]),
      vectorKey(),
    );
    expect(listEquals(output, reference), isTrue);
  });

  test('REVIEW B finding 1: bytes truncated inside a length-delimited field '
      'never carry the key into the output', () {
    final key = vectorKey();
    final output = inject(
      context,
      truncatedKeylessInput(input['to_address'] as String),
      key,
    );
    expect(containsRun(output, key), isFalse);
    expect(
      () => evmFamily.parseSigningOutput(
        output,
        coin: Coin.ethereum,
        usedKeys: const <KeyLocator>{},
      ),
      throwsA(isA<SigningError>()),
      reason: 'not a signed transaction',
    );
  });
}
