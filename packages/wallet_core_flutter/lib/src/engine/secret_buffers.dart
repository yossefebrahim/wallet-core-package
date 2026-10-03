/// Moving secrets into and out of native objects with the SDK's own staging
/// buffers overwritten before they are released. **Internal**: never exported.
///
/// The bindings' `TWStringHandle.fromString` and `TWDataHandle.fromBytes`
/// stage their input in a Dart list and a `calloc` buffer and free both as
/// they are; that is right for an address or a path, and not for a mnemonic, a
/// passphrase, or entropy. The helpers here do the same job for secrets and
/// zero-fill every buffer this SDK allocated for the copy before letting go of
/// it (DECISION-12 §3.9, "overwrite our own byte buffers").
///
/// What this does **not** do, and cannot: erase the caller's `String` or
/// `Uint8List`, a `String`'s internal copies, or anything the garbage
/// collector moved (PRD §11.3). The native object itself is zeroed by
/// upstream's delete when the returned handle is disposed (PRD §11.1).
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart'
    hide DisposedError;

import '../core/input_checks.dart';
import '../errors/boundary.dart';
import '../errors/errors.dart';

/// Copies [secret] into a new native `TWString` and returns its handle.
///
/// [secret] must reach upstream byte for byte, so a string containing U+0000
/// (which would end the C string early) or an unpaired surrogate (which
/// `utf8.encode` would replace with U+FFFD) is rejected with
/// [InvalidInputError] naming [inputName], before anything is allocated. The
/// callers check first, with the same rule; this is the guard no new caller
/// can forget.
///
/// The UTF-8 encoding and the NUL-terminated `calloc` buffer upstream copies
/// from are both zero-filled before they are released. The caller disposes the
/// returned handle, normally in a `finally`.
TWStringHandle secretString(
  NativeContext context,
  String secret, {
  required String inputName,
}) {
  checkNativeString(secret, inputName: inputName);
  final encoded = utf8.encode(secret);
  try {
    final size = checkNativeLength(
      encoded.length,
      resourceType: 'TWStringHandle',
      what: 'the UTF-8 length of a secret string',
    );
    final buffer = calloc<Uint8>(size + 1);
    try {
      buffer.asTypedList(size).setAll(0, encoded);
      final pointer = context.bindings.TWStringCreateWithUTF8Bytes(
        buffer.cast<Char>(),
      );
      if (pointer == nullptr) {
        throw const NativeResultError(
          'TWStringCreateWithUTF8Bytes returned nullptr',
        );
      }
      return TWStringHandle.adopt(context, pointer);
    } finally {
      buffer.asTypedList(size + 1).fillRange(0, size + 1, 0);
      calloc.free(buffer);
    }
  } finally {
    encoded.fillRange(0, encoded.length, 0);
  }
}

/// Copies [secret] into a new native `TWData` and returns its handle.
///
/// [secret] belongs to the caller and is read, never modified. The `calloc`
/// buffer upstream copies from is zero-filled before it is released.
TWDataHandle secretData(NativeContext context, Uint8List secret) {
  final size = checkNativeLength(
    secret.length,
    resourceType: 'TWDataHandle',
    what: 'the length of secret bytes',
  );
  final allocated = size == 0 ? 1 : size;
  final buffer = calloc<Uint8>(allocated);
  try {
    buffer.asTypedList(size).setAll(0, secret);
    final pointer = context.bindings.TWDataCreateWithBytes(buffer, size);
    if (pointer == nullptr) {
      throw const NativeResultError('TWDataCreateWithBytes returned nullptr');
    }
    return TWDataHandle.adopt(context, pointer);
  } finally {
    buffer.asTypedList(allocated).fillRange(0, allocated, 0);
    calloc.free(buffer);
  }
}

/// Copies the concatenation of [parts] into a new native `TWData` and returns
/// its handle.
///
/// For a secret assembled from pieces — the signing core's key field's tag
/// and length, the key, and the key-less input, in the order
/// `keyedInputParts` gives — without ever joining them in a Dart list: each
/// part is copied straight into one `calloc` buffer, which is zero-filled
/// before it is released, on the success path and when
/// `TWDataCreateWithBytes` fails alike. No Dart-heap copy of the concatenation
/// exists at any point.
///
/// [parts] belong to the caller and are read, never modified or retained; a
/// part may be a view over native memory, read only during this call.
TWDataHandle secretDataFromParts(NativeContext context, List<Uint8List> parts) {
  var total = 0;
  for (final part in parts) {
    total += part.length;
  }
  final size = checkNativeLength(
    total,
    resourceType: 'TWDataHandle',
    what: 'the length of secret bytes',
  );
  final allocated = size == 0 ? 1 : size;
  final buffer = calloc<Uint8>(allocated);
  try {
    final view = buffer.asTypedList(allocated);
    var offset = 0;
    for (final part in parts) {
      view.setAll(offset, part);
      offset += part.length;
    }
    final pointer = context.bindings.TWDataCreateWithBytes(buffer, size);
    if (pointer == nullptr) {
      throw const NativeResultError('TWDataCreateWithBytes returned nullptr');
    }
    return TWDataHandle.adopt(context, pointer);
  } finally {
    buffer.asTypedList(allocated).fillRange(0, allocated, 0);
    calloc.free(buffer);
  }
}

/// Decodes a secret `TWString` straight out of native memory.
///
/// Unlike `TWStringHandle.toDartString`, no intermediate Dart byte list is
/// made: the UTF-8 is decoded from a view over upstream's buffer, so the only
/// Dart copy is the returned `String`, which is the value the caller asked for.
/// The length is validated before anything is read (threat model TM-17).
///
/// Returns the empty string when upstream holds no bytes. Throws
/// [NativeResultError] if upstream reports a size out of range, reports bytes
/// but returns a null buffer, or returns bytes that are not UTF-8 (TM-17,
/// TM-19, TM-20) — a soft native failure, typed for the one operation
/// (DECISION-12 §3.10). The decoder's own message, which could quote the
/// bytes, is not kept.
String readSecretString(TWStringHandle handle) {
  final pointer = handle.pointer;
  final bindings = handle.context.bindings;
  final size = readNative(
    'TWStringSize',
    () => checkNativeLength(
      bindings.TWStringSize(pointer),
      resourceType: 'TWStringHandle',
      what: 'the size TWStringSize reported',
    ),
  );
  if (size == 0) return '';
  final bytes = bindings.TWStringUTF8Bytes(pointer);
  if (bytes == nullptr) {
    throw const NativeResultError('TWStringUTF8Bytes returned nullptr');
  }
  try {
    return utf8.decode(bytes.cast<Uint8>().asTypedList(size));
  } on FormatException {
    throw const NativeResultError('TWStringUTF8Bytes returned invalid UTF-8');
  }
}
