/// The signing core: key-less bytes and one key in, a parsed result out
/// (`docs/architecture/signing.md` §6 steps 3–6). **Internal**: never
/// exported.
///
/// [SigningCore] is the seam DECISION-1 turns on. [SyncSigningCore] is
/// Approach A — Dart injects the key into the serialized protobuf and calls
/// `TWAnySignerSign` in the caller's isolate. Approach B (T1.13,
/// `adapter/adapter_signing_core.dart`) implements the same interface with the
/// injection moved into a C adapter; everything in front of the seam (locator
/// resolution, encoding) and behind it (the family's parser) stays as it is.
///
/// The seam hands a core the key as upstream's own object — a
/// [PrivateKeyHandle] — and not as bytes, because that is the one shape both
/// approaches can take: Approach A reads the bytes itself, Approach B passes
/// the handle's pointer on to native code and reads nothing.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart'
    hide DisposedError;

import '../coin/coin.dart';
import '../engine/coin_bridge.dart';
import '../engine/handles.dart';
import '../engine/secret_buffers.dart';
import '../errors/boundary.dart';
import '../errors/errors.dart';
import '../families/family.dart';
import '../requests/requests.dart';
import 'key_field_check.dart';
import 'key_locator.dart';
import 'sign_result.dart';

/// Signs serialized key-less input with one private key.
abstract interface class SigningCore {
  /// Checks [keylessInput] against [family]'s key-field list, injects the key
  /// [privateKey] holds for [KeyRole.primary], has upstream sign it for
  /// [coin], and parses the output with [family], reporting [usedKeys] in the
  /// result.
  ///
  /// **Precondition, enforced here and by every implementation:**
  /// [keylessInput] is a complete, well-formed serialized message of
  /// [TransactionFamily.signingInputMessage] with every key field absent.
  /// [checkKeylessInput]'s decode is what establishes well-formedness, and no
  /// implementation and no caller may skip it: the injection works on bytes,
  /// and bytes that are not one complete message give the injected key a
  /// meaning nobody chose. Every implementation **prepends** the key field
  /// ([keyedInputParts] here; `wcf_sign.c` for the C adapter), so that even
  /// bytes that slipped past the check cannot swallow the key into another
  /// field.
  ///
  /// [privateKey] is **borrowed**: used during this call only, never disposed
  /// and never retained. The caller owns it and disposes it — upstream's
  /// `TWPrivateKeyDelete` overwrites the key — after this returns or throws.
  ///
  /// Throws [InvalidInputError] when [coin] is not in [family]'s chain family
  /// (`inputName: 'coin'`) or when [keylessInput] fails the key-field check
  /// (`inputName: 'signingInput'`) — both before the key is used;
  /// [UnsupportedOperationError] for a coin upstream removed; and
  /// [SigningError] for upstream's failure or an output that cannot be
  /// accepted.
  S sign<S extends SignResult>(
    Uint8List keylessInput, {
    required TransactionFamily<TransactionRequest, S> family,
    required Coin coin,
    required PrivateKeyHandle privateKey,
    required Set<KeyLocator> usedKeys,
  });
}

/// The shape of `TWAnySignerSign`: a serialized signing input and a coin in,
/// a new `TWData` holding the serialized output back.
typedef AnySignerSign =
    Pointer<Void> Function(Pointer<Void> input, TWCoinType coin);

/// Approach A of DECISION-1, in the isolate that owns [context].
///
/// Synchronous and stateless between calls: it holds the context and the
/// native entry point, and nothing of any call it made.
final class SyncSigningCore implements SigningCore {
  /// Creates a core over [context].
  ///
  /// [anySignerSign] replaces the call to `TWAnySignerSign`, for tests that
  /// must observe whether, and with what, the native signer was called. It
  /// defaults to the bindings' own.
  SyncSigningCore(this.context, {AnySignerSign? anySignerSign})
    : _anySignerSign = anySignerSign ?? context.bindings.TWAnySignerSign;

  /// The loaded library and its bindings.
  final NativeContext context;

  final AnySignerSign _anySignerSign;

  /// Signs, in this order:
  ///
  /// 1. [coin] is checked against [family] and mapped to upstream's coin type.
  /// 2. [keylessInput] is decoded and checked for every field of
  ///    [TransactionFamily.keyFields] ([checkKeylessInput]). A key field
  ///    present, or bytes that are not one complete message, fail the call
  ///    here, before [privateKey] is used and before any native call.
  /// 3. `TWPrivateKeyData(privateKey)` copies the key's bytes into a new
  ///    upstream `TWData`, and a `Uint8List` *view* over that `TWData`'s
  ///    native buffer — no Dart-heap copy — goes to [signWithKeyBytes]'s
  ///    steps 3–6 below. In a `finally`, on every path, that `TWData` is
  ///    disposed; `TWDataDelete` overwrites it with zeros before freeing it.
  ///    A null result, an out-of-range or zero size, or a null buffer is a
  ///    `NativeResultError` — a soft native failure the handler reports as
  ///    this one operation's `SigningError` (DECISION-12 §3.10) — not a
  ///    `StateError` that would end the session.
  ///
  /// This is the code that used to sit in `withDerivedKey`; T1.13 moved it
  /// behind the seam so that a core which reads no key bytes can exist.
  @override
  S sign<S extends SignResult>(
    Uint8List keylessInput, {
    required TransactionFamily<TransactionRequest, S> family,
    required Coin coin,
    required PrivateKeyHandle privateKey,
    required Set<KeyLocator> usedKeys,
  }) {
    final (coinType, field) = _checkBeforeKey(keylessInput, family, coin);
    final bindings = context.bindings;
    final dataPointer = bindings.TWPrivateKeyData(privateKey.pointer);
    if (dataPointer == nullptr) {
      throw const NativeResultError('TWPrivateKeyData returned nullptr');
    }
    final keyData = TWDataHandle.adopt(context, dataPointer);
    try {
      final length = readNative('TWPrivateKeyData', () => keyData.length);
      if (length == 0) {
        throw const NativeResultError('TWPrivateKeyData returned no bytes');
      }
      final bytes = bindings.TWDataBytes(keyData.pointer);
      if (bytes == nullptr) {
        throw const NativeResultError('TWDataBytes returned nullptr');
      }
      return _injectAndSign(
        keylessInput,
        family: family,
        coin: coin,
        coinType: coinType,
        field: field,
        privateKey: bytes.asTypedList(length),
        usedKeys: usedKeys,
      );
    } finally {
      keyData.dispose();
    }
  }

  /// Approach A's injection with the key given as bytes — the body of
  /// [sign] after it has read the key out of its handle, and what [sign]
  /// was before T1.13 changed the seam. Kept callable so that the tests of
  /// byte-level behaviour (keys upstream rejects, a key that is a view over
  /// native memory, the caller's buffer left as it was) still run: a
  /// `TWPrivateKey` holding a malformed key cannot be constructed.
  ///
  /// In this order:
  ///
  /// 1. and 2. As [sign]: the coin, then the key-field check, both before
  ///    [privateKey] is read.
  /// 3. The key is injected by **prepending** one length-delimited field — the
  ///    tag of [TransactionFamily.injectionField], the key's length, the key —
  ///    to the key-less bytes ([keyedInputParts]). A serialized message is a
  ///    sequence of fields, so a complete field followed by a complete
  ///    message is that message with the field set; step 2 proved the field
  ///    absent from the rest, so no later occurrence overrides it.
  ///
  ///    **Why prepend and not append.** Appended, the key lands wherever the
  ///    key-less bytes leave the parser: after bytes that end inside a
  ///    length-delimited field it would be read as that field's payload — as
  ///    calldata, say — and the transaction would be signed and broadcastable
  ///    with the key inside it. Prepended, the key is always a complete field
  ///    of its own at the start of the message, whatever follows it. Step 2
  ///    remains required: it is what rejects truncated bytes, and a key field
  ///    already present *after* a prepended one would win (the last
  ///    occurrence of a singular field is the one parsed).
  ///
  ///    The three parts are copied straight into one native staging buffer,
  ///    which becomes a `TWData` ([secretDataFromParts]).
  /// 4. `TWAnySignerSign(input, coin)` is called.
  /// 5. Still inside the `try`: upstream's output is copied out and parsed by
  ///    [family] — parse before releasing.
  /// 6. In the `finally`, on every path: the output and the keyed input
  ///    `TWData`s are disposed — release before replying.
  ///
  /// **Every copy of the key while this runs**, and what becomes of it:
  ///
  /// * [privateKey], the caller's list. Read by step 3, **never overwritten
  ///   here** — it is borrowed, and the caller overwrites it after this
  ///   returns. It may be a view over native memory (for example over the
  ///   `TWData` upstream's `TWPrivateKeyData` returns), in which case no
  ///   Dart-heap copy of the key exists at all.
  /// * **No protobuf message ever holds the key.** Prepending the encoded field
  ///   instead of setting it on a `GeneratedMessage` and re-serializing means
  ///   there is no message field referencing the key and no
  ///   `CodedBufferWriter` chunk containing it — internal buffers this code
  ///   could not reach to overwrite. The message decoded in step 2 holds only
  ///   the key-less input.
  /// * **No Dart list of the keyed serialized input exists.** It is assembled
  ///   only in the `calloc` staging buffer, outside the Dart heap.
  /// * The `calloc` staging buffer. **Overwritten with zeros and freed** in a
  ///   `finally` inside [secretDataFromParts], whether or not the `TWData` was
  ///   created.
  /// * The keyed input `TWData`. Released in this method's `finally`;
  ///   upstream's `TWDataDelete` overwrites it with zeros before freeing it
  ///   (PRD §11.1).
  /// * Copies upstream makes while signing — its `Data` and protobuf parse of
  ///   the input, its private-key object, whatever its Rust signer allocates.
  ///   **Not reachable from this code** and not overwritten by it; whether
  ///   upstream wipes each of them is upstream's behaviour, not verified here.
  /// * The tag-and-length header holds the key's length, not its bytes.
  ///
  /// Best-effort, in the PRD §11.3 sense: a process killed between steps 3
  /// and 6 leaves the staging buffer or the `TWData` as they were, and
  /// nothing here can reach copies the caller or the garbage collector made of
  /// [privateKey] before this call.
  ///
  /// Never logs, never retains anything, and never puts key bytes in an
  /// error.
  S signWithKeyBytes<S extends SignResult>(
    Uint8List keylessInput, {
    required TransactionFamily<TransactionRequest, S> family,
    required Coin coin,
    required Uint8List privateKey,
    required Set<KeyLocator> usedKeys,
  }) {
    final (coinType, field) = _checkBeforeKey(keylessInput, family, coin);
    return _injectAndSign(
      keylessInput,
      family: family,
      coin: coin,
      coinType: coinType,
      field: field,
      privateKey: privateKey,
      usedKeys: usedKeys,
    );
  }

  /// Steps 1 and 2: everything that must fail before a key is touched.
  (TWCoinType, KeyFieldEntry) _checkBeforeKey(
    Uint8List keylessInput,
    TransactionFamily<TransactionRequest, SignResult> family,
    Coin coin,
  ) {
    if (coin.family != family.chainFamily) {
      throw InvalidInputError(
        '${coin.id} is not in the ${family.chainFamily.id} family',
        inputName: 'coin',
      );
    }
    final coinType = twCoinTypeOf(coin);
    checkKeylessInput(keylessInput, family);
    final field = family.injectionField(KeyRole.primary);
    if (field.messagePath != family.signingInputMessage) {
      throw StateError(
        'the injection field ${field.messagePath}.${field.fieldName} is not '
        'a field of ${family.signingInputMessage}',
      );
    }
    return (coinType, field);
  }

  /// Steps 3–6 of [signWithKeyBytes].
  S _injectAndSign<S extends SignResult>(
    Uint8List keylessInput, {
    required TransactionFamily<TransactionRequest, S> family,
    required Coin coin,
    required TWCoinType coinType,
    required KeyFieldEntry field,
    required Uint8List privateKey,
    required Set<KeyLocator> usedKeys,
  }) {
    TWDataHandle? input;
    TWDataHandle? output;
    try {
      input = secretDataFromParts(
        context,
        keyedInputParts(keylessInput, field, privateKey),
      );
      final pointer = _anySignerSign(input.pointer, coinType);
      if (pointer == nullptr) {
        throw const SigningError(
          SigningError.malformedOutputCode,
          'TWAnySignerSign returned no output',
        );
      }
      output = TWDataHandle.adopt(context, pointer);
      final Uint8List bytes;
      try {
        bytes = output.copyBytes();
      } on RangeError {
        throw const SigningError(
          SigningError.malformedOutputCode,
          'TWAnySignerSign reported an output length out of range',
        );
      } on StateError {
        throw const SigningError(
          SigningError.malformedOutputCode,
          'TWAnySignerSign reported output bytes but returned no buffer',
        );
      }
      return family.parseSigningOutput(bytes, coin: coin, usedKeys: usedKeys);
    } finally {
      output?.dispose();
      input?.dispose();
    }
  }
}

/// The parts of the keyed signing input, in order: [field]'s tag and the key's
/// length, [privateKey], then [keylessInput] — the key field **prepended**
/// (see [SyncSigningCore.signWithKeyBytes] step 3 for why). The one place in
/// Dart that decides the layout; the C adapter's one place is the body of
/// `wcf_sign_ethereum`, and `test/signing/keyed_layout_native_test.dart`
/// holds both to the same layout.
///
/// Only references are listed; nothing is copied. The caller copies the parts
/// into native memory ([secretDataFromParts]) and must already have run
/// [checkKeylessInput] on [keylessInput]: this function assumes, and cannot
/// check, that [keylessInput] is one complete message with no key field.
List<Uint8List> keyedInputParts(
  Uint8List keylessInput,
  KeyFieldEntry field,
  Uint8List privateKey,
) => <Uint8List>[
  lengthDelimitedHeader(field.fieldNumber, privateKey.length),
  privateKey,
  keylessInput,
];

/// The protobuf tag and length that precede a length-delimited field
/// numbered [fieldNumber] holding [length] bytes: `varint(fieldNumber << 3 |
/// 2)` then `varint(length)`. Holds no content.
Uint8List lengthDelimitedHeader(int fieldNumber, int length) {
  if (fieldNumber < 1 || fieldNumber > 0x1FFFFFFF) {
    throw RangeError.range(fieldNumber, 1, 0x1FFFFFFF, 'fieldNumber');
  }
  RangeError.checkNotNegative(length, 'length');
  final bytes = BytesBuilder(copy: false);
  _writeVarint(bytes, (fieldNumber << 3) | 2);
  _writeVarint(bytes, length);
  return bytes.takeBytes();
}

void _writeVarint(BytesBuilder out, int value) {
  var rest = value;
  while (rest >= 0x80) {
    out.addByte((rest & 0x7F) | 0x80);
    rest >>= 7;
  }
  out.addByte(rest);
}
