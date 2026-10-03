/// Approach B of DECISION-1 — **T1.13 prototype, evaluation only**: the
/// signing core whose key injection happens in a C adapter linked into the
/// native library (`packages/wallet_core_flutter_native/src/shim/wcf_sign.c`),
/// not in Dart. **Internal**: never exported, and never the default —
/// `EngineRequestHandler` signs through Approach A unless it is given
/// [AdapterSigningCore.new].
///
/// The standard artifact does not contain the adapter; only a host library
/// built with `tools/native_build/build_apple.sh --with-shim` does. Against
/// any other library [AdapterSigningCore] fails at construction with
/// [NativeLoadError], so `Init` fails and nothing is signed.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart'
    hide DisposedError;

import '../../coin/coin.dart';
import '../../engine/coin_bridge.dart';
import '../../engine/handles.dart';
import '../../engine/secret_buffers.dart';
import '../../errors/errors.dart';
import '../../families/family.dart';
import '../../requests/requests.dart';
import '../key_field_check.dart';
import '../key_locator.dart';
import '../sign_result.dart';
import '../signing_core.dart';

/// The adapter's one entry point, declared in `src/shim/wcf_sign.h`.
const String adapterSymbol = 'wcf_sign_ethereum';

/// The signing-input message the adapter injects into.
const String adapterSigningInputMessage = 'TW.Ethereum.Proto.SigningInput';

/// The field number the adapter appends the key as: the value of
/// `WCF_ETHEREUM_SIGNING_INPUT_PRIVATE_KEY_FIELD` in `wcf_sign.h`.
///
/// Dart cannot read a C `#define`, so this mirrors it, and
/// `test/signing/adapter/field_number_test.dart` holds three numbers equal:
/// this one, the header's, and `key_fields.json`'s. [AdapterSigningCore]
/// additionally refuses to sign unless the family's reviewed injection field
/// carries it — so the adapter cannot be called for a schema whose key field
/// it does not write.
const int adapterPrivateKeyField = 9;

/// The shape of `wcf_sign_ethereum`: a key-less signing input `TWData`, a
/// `TWPrivateKey`, and upstream's coin-type value in; a new `TWData` holding
/// the serialized output, or `nullptr`, back.
///
/// The key is typed `Pointer<TWPrivateKey>` — the generated opaque struct —
/// and not `Pointer<Void>`: `TWData` is `Void` in the generated bindings, so
/// with both untyped, swapping the two pointer arguments would compile and C
/// would read a `TWPrivateKey` as a `TWData`. Typed, it does not compile.
typedef AdapterSign =
    Pointer<TWData> Function(
      Pointer<TWData> keylessInput,
      Pointer<TWPrivateKey> privateKey,
      int coin,
    );

typedef _AdapterSignNative =
    Pointer<TWData> Function(
      Pointer<TWData> keylessInput,
      Pointer<TWPrivateKey> privateKey,
      Uint32 coin,
    );

/// Approach B of DECISION-1, in the isolate that owns [context].
///
/// **What Dart touches.** The key-less input bytes, which it copies into a
/// `TWData` (they hold no key — [checkKeylessInput] proves it first); the
/// `PrivateKeyHandle`'s **pointer** — the address of upstream's
/// `TWPrivateKey` object, which Dart passes to the adapter and never
/// dereferences; and the output bytes. No Dart code on this path calls
/// `TWPrivateKeyData`, `TWDataBytes` on a key, or anything else that reads a
/// key byte, and no buffer allocated by Dart ever holds one.
///
/// Synchronous and stateless between calls, like [SyncSigningCore].
final class AdapterSigningCore implements SigningCore {
  /// Creates a core over [context], binding the adapter from [library].
  ///
  /// [library] must be the library behind [context] — `EngineRequestHandler`
  /// passes the one its `Init` loaded and verified. Throws [NativeLoadError]
  /// when [library] does not export [adapterSymbol] (the standard artifact
  /// does not), and [StateError] when it is not the image [context]'s
  /// bindings were made over.
  ///
  /// [adapterSign] replaces the call to the adapter, for tests that must
  /// observe the call or make it return `nullptr`. The symbol is still
  /// required: the core never exists over a library without the adapter.
  AdapterSigningCore(
    NativeContext context,
    DynamicLibrary library, {
    AdapterSign? adapterSign,
  }) : this._(context, bindAdapter(context, library), adapterSign);

  AdapterSigningCore._(this.context, AdapterSign bound, AdapterSign? override)
    : _adapterSign = override ?? bound;

  /// The loaded library and its bindings.
  final NativeContext context;

  final AdapterSign _adapterSign;

  /// Looks up [adapterSymbol] in [library] — a hand-written binding, since
  /// the adapter is not an upstream header and `lib/src/generated/**` is
  /// never hand-edited — after checking it is there and that [library] is
  /// the image behind [context].
  ///
  /// **The same-image check is only as strong as [library].** On macOS (and
  /// in the host tests) [library] is the `DynamicLibrary.open` of one file,
  /// and the check compares `TWDataDelete` in that file with the bindings'.
  /// On iOS the loader tries `DynamicLibrary.process()` first
  /// (`library_location.dart`, `NativePlatform.ios`): both lookups then go
  /// through the process-wide namespace, the comparison cannot fail, and the
  /// adapter binds to whichever loaded image exports [adapterSymbol] first —
  /// not provably the one whose identity `Init` verified.
  static AdapterSign bindAdapter(
    NativeContext context,
    DynamicLibrary library,
  ) {
    if (!library.providesSymbol(adapterSymbol)) {
      throw NativeLoadError(
        'the loaded library does not export $adapterSymbol: it was built '
        'without the Approach B signing adapter (DECISION-1 evaluation; '
        'tools/native_build/build_apple.sh --with-shim)',
      );
    }
    final ours = library.lookup<Void>('TWDataDelete').address;
    final theirs = context.bindings.addresses.TWDataDelete.address;
    if (ours != theirs) {
      throw StateError(
        'the library given for $adapterSymbol is not the library behind '
        'this context',
      );
    }
    return library.lookupFunction<_AdapterSignNative, AdapterSign>(
      adapterSymbol,
    );
  }

  /// Signs, in this order:
  ///
  /// 1. [coin] is checked against [family]; the family must be the one the
  ///    adapter writes ([adapterSigningInputMessage]) and its reviewed
  ///    injection field must be [adapterPrivateKeyField] — anything else is
  ///    [UnsupportedOperationError] (`'signing-adapter'`) or a [StateError].
  /// 2. [keylessInput] passes [checkKeylessInput] — a key field present fails
  ///    here, before the adapter is called and before any native call.
  /// 3. The key-less bytes are copied into a `TWData` with `secretData`, as
  ///    Approach A copies its keyed input: a `nullptr` from
  ///    `TWDataCreateWithBytes` is a `NativeResultError`, which the handler
  ///    reports as this one operation's [SigningError] (DECISION-12 §3.10) —
  ///    not a fault that ends the session.
  /// 4. The adapter is called with that `TWData`, [privateKey]'s pointer and
  ///    the coin type. In C it reads the key with `TWPrivateKeyData`, writes
  ///    the keyed input straight into one upstream `TWData`, deletes the
  ///    key's `TWData`, calls `TWAnySignerSign`, deletes the keyed input —
  ///    `TWDataDelete` overwrites both — and returns the output.
  /// 5. `nullptr` is a [SigningError] with [SigningError.malformedOutputCode];
  ///    otherwise the output is copied out and parsed by [family] — parse
  ///    before releasing.
  /// 6. In the `finally`, on every path: the output and the key-less input
  ///    `TWData`s are disposed.
  ///
  /// [privateKey] is borrowed and never disposed here. Never logs, never
  /// retains anything, and never puts key bytes in an error — it never has
  /// any to put.
  @override
  S sign<S extends SignResult>(
    Uint8List keylessInput, {
    required TransactionFamily<TransactionRequest, S> family,
    required Coin coin,
    required PrivateKeyHandle privateKey,
    required Set<KeyLocator> usedKeys,
  }) {
    if (coin.family != family.chainFamily) {
      throw InvalidInputError(
        '${coin.id} is not in the ${family.chainFamily.id} family',
        inputName: 'coin',
      );
    }
    if (family.signingInputMessage != adapterSigningInputMessage) {
      throw UnsupportedOperationError(coin, 'signing-adapter');
    }
    final coinType = twCoinTypeOf(coin);
    checkKeylessInput(keylessInput, family);
    final field = family.injectionField(KeyRole.primary);
    if (field.messagePath != adapterSigningInputMessage ||
        field.fieldNumber != adapterPrivateKeyField) {
      throw StateError(
        'the injection field ${field.messagePath}.${field.fieldName} '
        '(${field.fieldNumber}) is not the field $adapterSymbol writes '
        '($adapterSigningInputMessage, $adapterPrivateKeyField)',
      );
    }

    TWDataHandle? input;
    TWDataHandle? output;
    try {
      input = secretData(context, keylessInput);
      final pointer = _adapterSign(
        input.pointer,
        privateKey.pointer,
        coinType.value,
      );
      if (pointer == nullptr) {
        throw const SigningError(
          SigningError.malformedOutputCode,
          'the signing adapter returned no output',
        );
      }
      output = TWDataHandle.adopt(context, pointer);
      final Uint8List bytes;
      try {
        bytes = output.copyBytes();
      } on RangeError {
        throw const SigningError(
          SigningError.malformedOutputCode,
          'the signing adapter reported an output length out of range',
        );
      } on StateError {
        throw const SigningError(
          SigningError.malformedOutputCode,
          'the signing adapter reported output bytes but returned no buffer',
        );
      }
      return family.parseSigningOutput(bytes, coin: coin, usedKeys: usedKeys);
    } finally {
      output?.dispose();
      input?.dispose();
    }
  }
}
