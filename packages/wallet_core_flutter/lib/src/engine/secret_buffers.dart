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
        throw StateError('TWStringCreateWithUTF8Bytes returned nullptr');
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
      throw StateError('TWDataCreateWithBytes returned nullptr');
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
/// Returns the empty string when upstream holds no bytes. Throws [StateError]
/// if upstream reports bytes but returns a null buffer (TM-19, TM-20).
String readSecretString(TWStringHandle handle) {
  final pointer = handle.pointer;
  final bindings = handle.context.bindings;
  final size = checkNativeLength(
    bindings.TWStringSize(pointer),
    resourceType: 'TWStringHandle',
    what: 'the size TWStringSize reported',
  );
  if (size == 0) return '';
  final bytes = bindings.TWStringUTF8Bytes(pointer);
  if (bytes == nullptr) {
    throw StateError('TWStringUTF8Bytes returned nullptr');
  }
  return utf8.decode(bytes.cast<Uint8>().asTypedList(size));
}
