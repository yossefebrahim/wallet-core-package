/// The signing core: key-less bytes and a borrowed native key handle per
/// [KeyRole] in, a parsed result out (`docs/architecture/signing.md` §6 steps
/// 3–6). **Internal**: never exported.
///
/// [SigningCore] is the seam DECISION-1 turns on. [SyncSigningCore] is
/// Approach A — Dart injects the keys into the serialized protobuf and calls
/// `TWAnySignerSign` in the caller's isolate. Approach B (T1.13) implements the
/// same interface with the injection moved into a C adapter that takes the
/// same `PrivateKeyHandle`s; everything in front of the seam (locator
/// resolution, key derivation, encoding) and behind it (the family's parser)
/// stays as it is. That is why the seam takes handles and not key bytes: an
/// adapter needs the native `TWPrivateKey`, and a Dart core needs bytes only
/// for the length of one assembly, which it can read from the handle itself.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' show calloc;
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

/// Signs serialized key-less input with the private keys of several roles.
abstract interface class SigningCore {
  /// Checks [keylessInput] against [family]'s key-field list, injects the key
  /// of every role in [keys] into the field [TransactionFamily.injectionField]
  /// names for it, has upstream sign the result for [coin], and parses the
  /// output with [family], reporting [usedKeys] in the result.
  ///
  /// **Precondition, enforced here and by every implementation:**
  /// [keylessInput] is a complete, well-formed serialized message of
  /// [TransactionFamily.signingInputMessage] with every key field absent.
  /// [checkKeylessInput]'s decode is what establishes well-formedness, and no
  /// implementation and no caller may skip it: the injection works on bytes,
  /// and bytes that are not one complete message give an injected key a
  /// meaning nobody chose.
  ///
  /// **[keys] is borrowed.** Each [PrivateKeyHandle] is read during this call
  /// only, never disposed, never retained; the caller owns every handle and
  /// disposes it after this returns. No key bytes cross this interface: an
  /// implementation reads the bytes it needs from the handle (Approach A) or
  /// hands the handle to native code (Approach B).
  ///
  /// **[requiredRoles] is [TransactionFamily.requiredRoles] for the request
  /// being signed, and its order is the injection order.** Keys are injected
  /// in that order, and the order is the only thing that fixes where a key
  /// lands among several in one repeated field (UTXO: the keys of `input(0)`,
  /// `input(1)`, … in input order). It does not depend on how [keys] iterates.
  /// Several roles may share one repeated field; a singular field takes one.
  ///
  /// Throws [InvalidInputError] when [coin] is not in [family]'s chain family
  /// (`inputName: 'coin'`) or when [keylessInput] fails the key-field check
  /// (`inputName: 'signingInput'`) — both before any key is read — or when
  /// the keyed input (key fields and key-less bytes together) is longer than
  /// one native buffer may be (`inputName: 'signingInput'`);
  /// [UnsupportedOperationError] for a coin upstream removed; and
  /// [SigningError] for upstream's failure or an output that cannot be
  /// accepted. A soft native failure while reading a key — upstream returning
  /// no bytes — is a `NativeResultError`, which the handler reports as a
  /// [SigningError].
  ///
  /// Throws [StateError] — a defect of the caller inside this SDK, never of a
  /// user's input — when [requiredRoles] is empty or repeats a role, when
  /// [keys] has a role [requiredRoles] does not list or lacks one it lists,
  /// when [family] has no injection field for a listed role or one that is not
  /// a field of its signing input, or when two roles share a singular field.
  S sign<S extends SignResult>(
    Uint8List keylessInput, {
    required TransactionFamily<TransactionRequest, S> family,
    required Coin coin,
    required List<KeyRole> requiredRoles,
    required Map<KeyRole, PrivateKeyHandle> keys,
    required Set<KeyLocator> usedKeys,
  });
}

/// The shape of `TWAnySignerSign`: a serialized signing input and a coin in,
/// a new `TWData` holding the serialized output back.
typedef AnySignerSign = Pointer<Void> Function(
  Pointer<Void> input,
  TWCoinType coin,
);

/// Approach A of DECISION-1, in the isolate that owns [context].
///
/// Synchronous and stateless between calls: it holds the context and the
/// native entry point, and nothing of any call it made.
final class SyncSigningCore implements SigningCore {
  /// Creates a core over [context].
  ///
  /// [anySignerSign] replaces the call to `TWAnySignerSign`, for tests that
  /// must observe whether, and with what, the native signer was called. It
  /// defaults to the bindings' own. [stagingAllocator] replaces the allocator
  /// of the one staging buffer the keyed input is assembled in, for tests that
  /// must observe what it holds when it is released. It defaults to `calloc`.
  SyncSigningCore(
    this.context, {
    AnySignerSign? anySignerSign,
    this._stagingAllocator = calloc,
  }) : _anySignerSign = anySignerSign ?? context.bindings.TWAnySignerSign;

  /// The loaded library and its bindings.
  final NativeContext context;

  final AnySignerSign _anySignerSign;
  final Allocator _stagingAllocator;

  /// Signs, in this order:
  ///
  /// 1. [coin] is checked against [family] and mapped to upstream's coin type.
  /// 2. [keylessInput] is decoded and checked for every field of
  ///    [TransactionFamily.keyFields] ([checkKeylessInput]). Bytes that do not
  ///    decode as one complete message, or that carry a key field, fail the
  ///    call here, **before any key is read** and before any native call.
  /// 3. The roles are checked ([StateError] on a defect, see
  ///    [SigningCore.sign]): [requiredRoles] against [keys], and each role's
  ///    injection field against the family's signing input. No key is read.
  /// 4. The keys are injected by **prepending**, for each role in
  ///    [requiredRoles] order, one length-delimited field — the tag of the
  ///    role's injection field, the key's length, the key — ahead of the
  ///    key-less bytes ([keyedInputParts]). A serialized message is a sequence
  ///    of fields, so complete fields followed by a complete message are that
  ///    message with those fields set, and several fields with one number are
  ///    one repeated field in order of appearance. Step 2 proved every key
  ///    field absent from the rest, so no later occurrence overrides a
  ///    prepended one.
  ///
  ///    **Why prepend and not append.** Appended, a key lands wherever the
  ///    key-less bytes leave the parser: after bytes that end inside a
  ///    length-delimited field it would be read as that field's payload — as
  ///    calldata, say — and the transaction would be signed and broadcastable
  ///    with the key inside it. Prepended, each key is always a complete field
  ///    of its own at the start of the message, whatever follows. Step 2
  ///    remains required: it is what rejects truncated bytes, and a key field
  ///    already present *after* a prepended one would win (the last
  ///    occurrence of a singular field is the one parsed).
  ///
  ///    For each role, `TWPrivateKeyData` gives a `TWData` copy of the key
  ///    ([_stage]); the headers, the keys' bytes (as views over those
  ///    `TWData`s) and the key-less bytes are copied straight into **one**
  ///    native staging buffer, which becomes a `TWData`
  ///    ([secretDataFromParts]). The key `TWData`s are released right after
  ///    the assembly, before upstream is called.
  /// 5. `TWAnySignerSign(input, coin)` is called.
  /// 6. Still inside the `try`: upstream's output is copied out and parsed by
  ///    [family] — parse before releasing.
  /// 7. In the `finally`, on every path: the output and the keyed input
  ///    `TWData`s are disposed — release before replying.
  ///
  /// **Every copy of a key while this runs**, and what becomes of it:
  ///
  /// * The caller's `PrivateKeyHandle` (a `TWPrivateKey`). **Borrowed**: read
  ///   through `TWPrivateKeyData`, never disposed here. The caller disposes
  ///   it, and upstream's `~PrivateKey` overwrites its bytes.
  /// * One `TWData` per key, from `TWPrivateKeyData`. Disposed in [_stage]'s
  ///   `finally` as soon as the assembly is done — success or failure — and
  ///   upstream's `TWDataDelete` overwrites it with zeros. The `Uint8List`s
  ///   read from it are views over its native buffer, not copies, and are
  ///   dropped with it.
  /// * **No Dart-heap copy of any key.** No `Uint8List.fromList`, no
  ///   `List<int>` of key bytes, no protobuf message with a key field:
  ///   prepending the encoded field instead of setting it on a
  ///   `GeneratedMessage` and re-serializing means no message field references
  ///   a key and no `CodedBufferWriter` chunk contains one. The message
  ///   decoded in step 2 holds only the key-less input.
  /// * **No Dart list of the keyed serialized input exists.** It is assembled
  ///   only in the `calloc` staging buffer, outside the Dart heap.
  /// * The `calloc` staging buffer: every key, each after its field header,
  ///   then the key-less input. **Overwritten with zeros and freed** in a
  ///   `finally` inside [secretDataFromParts], whether or not the `TWData` was
  ///   created.
  /// * The keyed input `TWData`. Released in this method's `finally`;
  ///   upstream's `TWDataDelete` overwrites it with zeros before freeing it
  ///   (PRD §11.1).
  /// * Copies upstream makes while signing — its `Data` and protobuf parse of
  ///   the input, its private-key objects, whatever its Rust signer allocates.
  ///   **Not reachable from this code** and not overwritten by it; whether
  ///   upstream wipes each of them is upstream's behaviour, not verified here.
  /// * Each field header holds a key's length, not its bytes.
  ///
  /// Best-effort, in the PRD §11.3 sense: a process killed between steps 4
  /// and 7 leaves the staging buffer or the `TWData` as they were.
  ///
  /// Never logs, never retains anything, and never puts key bytes in an
  /// error.
  @override
  S sign<S extends SignResult>(
    Uint8List keylessInput, {
    required TransactionFamily<TransactionRequest, S> family,
    required Coin coin,
    required List<KeyRole> requiredRoles,
    required Map<KeyRole, PrivateKeyHandle> keys,
    required Set<KeyLocator> usedKeys,
  }) {
    if (coin.family != family.chainFamily) {
      throw InvalidInputError(
        '${coin.id} is not in the ${family.chainFamily.id} family',
        inputName: 'coin',
      );
    }
    final coinType = twCoinTypeOf(coin);
    checkKeylessInput(keylessInput, family);
    final slots = _injectionSlots(family, requiredRoles, keys);
    TWDataHandle? input;
    TWDataHandle? output;
    try {
      input = _stage(keylessInput, slots);
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

  /// Assembles the keyed input for [slots], in order, and returns it as a
  /// `TWData`. Reads each key through `TWPrivateKeyData` and releases those
  /// copies before returning or throwing.
  TWDataHandle _stage(
    Uint8List keylessInput,
    List<(KeyFieldEntry, PrivateKeyHandle)> slots,
  ) {
    final bindings = context.bindings;
    final keyData = <TWDataHandle>[];
    try {
      final views = <(KeyFieldEntry, Uint8List)>[];
      for (final (field, handle) in slots) {
        final pointer = bindings.TWPrivateKeyData(handle.pointer);
        if (pointer == nullptr) {
          throw const NativeResultError('TWPrivateKeyData returned nullptr');
        }
        final data = TWDataHandle.adopt(context, pointer);
        keyData.add(data);
        final length = readNative('TWPrivateKeyData', () => data.length);
        if (length == 0) {
          throw const NativeResultError('TWPrivateKeyData returned no bytes');
        }
        final bytes = bindings.TWDataBytes(data.pointer);
        if (bytes == nullptr) {
          throw const NativeResultError('TWDataBytes returned nullptr');
        }
        views.add((field, bytes.asTypedList(length)));
      }
      try {
        return secretDataFromParts(
          context,
          keyedInputParts(keylessInput, views),
          allocator: _stagingAllocator,
        );
      } on RangeError {
        // The keyed input is longer than one native buffer may be: the
        // input's size, never a defect of this SDK, so it is reported as the
        // input's fault and cannot end the session. No length, no content.
        throw const InvalidInputError(
          'the keyed signing input is longer than one native buffer allows',
          inputName: 'signingInput',
        );
      }
    } finally {
      for (final data in keyData.reversed) {
        data.dispose();
      }
    }
  }
}

/// The injection field and handle of every role of [requiredRoles], in that
/// order, after the role checks of [SigningCore.sign]. Reads no key.
List<(KeyFieldEntry, PrivateKeyHandle)> _injectionSlots(
  TransactionFamily<TransactionRequest, SignResult> family,
  List<KeyRole> requiredRoles,
  Map<KeyRole, PrivateKeyHandle> keys,
) {
  if (requiredRoles.isEmpty) {
    throw StateError('a signing operation needs at least one key role');
  }
  if (requiredRoles.toSet().length != requiredRoles.length) {
    throw StateError('the required roles repeat a role');
  }
  for (final role in keys.keys) {
    if (!requiredRoles.contains(role)) {
      throw StateError('a key was given for ${role.id}, which is not required');
    }
  }
  final slots = <(KeyFieldEntry, PrivateKeyHandle)>[];
  final singular = <int>{};
  for (final role in requiredRoles) {
    final handle = keys[role];
    if (handle == null) {
      throw StateError('no key was given for the required role ${role.id}');
    }
    final KeyFieldEntry field;
    try {
      field = family.injectionField(role);
    } on ArgumentError {
      throw StateError('the family has no key slot for ${role.id}');
    }
    if (field.messagePath != family.signingInputMessage) {
      throw StateError(
        'the injection field ${field.messagePath}.${field.fieldName} is not '
        'a field of ${family.signingInputMessage}',
      );
    }
    if (!field.repeated && !singular.add(field.fieldNumber)) {
      throw StateError(
        'more than one role is injected into the singular field '
        '${field.fieldName}',
      );
    }
    slots.add((field, handle));
  }
  return slots;
}

/// The parts of the keyed signing input, in order: for each of [keys], its
/// field's tag and the key's length, then the key; then [keylessInput] — the
/// key fields **prepended** (see [SyncSigningCore.sign] step 4 for why).
///
/// Only references are listed; nothing is copied except the headers, which
/// hold lengths. The caller copies the parts into native memory
/// ([secretDataFromParts]) and must already have run [checkKeylessInput] on
/// [keylessInput]: this function assumes, and cannot check, that
/// [keylessInput] is one complete message with no key field.
List<Uint8List> keyedInputParts(
  Uint8List keylessInput,
  List<(KeyFieldEntry, Uint8List)> keys,
) => <Uint8List>[
  for (final (field, key) in keys) ...[
    lengthDelimitedHeader(field.fieldNumber, key.length),
    key,
  ],
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
