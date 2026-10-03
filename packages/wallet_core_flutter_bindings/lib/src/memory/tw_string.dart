/// [TWStringHandle]: ownership of one upstream `TWString` object.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../generated/ffi/wallet_core_bindings.dart';
import 'limits.dart';
import 'native_context.dart';
import 'native_resource.dart';

/// Owns one upstream `TWString` and frees it with `TWStringDelete`.
///
/// **`dispose()` is the primary cleanup path**; the native finalizer is a
/// fallback for a handle a caller forgot (PRD §11.2 item 1). Upstream's
/// `TWStringDelete` calls `memzero` on the buffer this object currently owns
/// before freeing it (PRD §11.1 [VERIFIED]), which is the whole reason disposal
/// is the primary path: the buffer stops holding what it holds when this is
/// called, not when the collector gets round to it.
///
/// A `TWString` can hold a mnemonic or a keystore document, so nothing here
/// renders its text: [toString] reports type, byte length and disposed state
/// only (threat model TM-09, TM-31).
///
/// Belongs to the isolate that created it.
final class TWStringHandle extends NativeResource {
  TWStringHandle._(NativeContext context, Pointer<TWString> pointer, int? size)
    : super(
        context: context,
        pointer: pointer.cast<Void>(),
        finalizer: context.stringFinalizer,
        externalSize: size,
      );

  /// Copies [value] into a new native `TWString` as UTF-8.
  ///
  /// The NUL-terminated temporary upstream reads from is allocated with
  /// `package:ffi` and freed in a `finally`, so an exception cannot leak it
  /// (PRD §11.2 item 4).
  ///
  /// Throws [RangeError] if the UTF-8 encoding of [value] is longer than
  /// [maxNativeBufferBytes].
  factory TWStringHandle.fromString(NativeContext context, String value) {
    final encoded = utf8.encode(value);
    final size = checkNativeLength(
      encoded.length,
      resourceType: 'TWStringHandle',
      what: 'the UTF-8 length of the string to copy in',
    );
    // One byte more than the encoding, for the terminator `calloc` zeroes.
    final buffer = calloc<Uint8>(size + 1);
    try {
      if (size != 0) {
        buffer.asTypedList(size).setAll(0, encoded);
      }
      final pointer = context.bindings.TWStringCreateWithUTF8Bytes(
        buffer.cast<Char>(),
      );
      if (pointer == nullptr) {
        throw StateError(
          'TWStringCreateWithUTF8Bytes returned nullptr for $size bytes',
        );
      }
      return TWStringHandle._(context, pointer, size);
    } finally {
      calloc.free(buffer);
    }
  }

  /// Takes ownership of a `TWString` upstream returned to us.
  ///
  /// The caller must not delete [pointer] afterwards and must not adopt the
  /// same pointer twice.
  ///
  /// Throws [ArgumentError] when [pointer] is `nullptr`: upstream signals
  /// failure with a null pointer, and a failure is reported by the call site,
  /// never wrapped (threat model TM-20).
  ///
  /// No `externalSize` is given to the finalizer here, for the reason
  /// `TWDataHandle.adopt` gives.
  factory TWStringHandle.adopt(
    NativeContext context,
    Pointer<TWString> pointer,
  ) {
    if (pointer == nullptr) {
      throw ArgumentError.value(
        null,
        'pointer',
        'TWStringHandle.adopt: upstream returned nullptr, which is a failure '
            'signal and not a value to wrap',
      );
    }
    return TWStringHandle._(context, pointer, null);
  }

  /// The native pointer.
  ///
  /// Throws `DisposedError` after [dispose]. Valid only until then.
  Pointer<TWString> get pointer => rawPointer.cast<TWString>();

  /// The number of UTF-8 bytes upstream reports, validated against
  /// [maxNativeBufferBytes] (threat model TM-17).
  ///
  /// Throws `DisposedError` after [dispose] and [RangeError] on an out-of-range
  /// size.
  int get length => checkNativeLength(
    context.bindings.TWStringSize(pointer),
    resourceType: 'TWStringHandle',
    what: 'the size TWStringSize reported',
  );

  /// Decodes the contents into a Dart `String`.
  ///
  /// The length comes from `TWStringSize` and is validated before anything is
  /// copied; the terminator is not searched for, so an unterminated or
  /// embedded-NUL buffer cannot make this read past the end (threat model
  /// TM-17).
  ///
  /// Throws `DisposedError` after [dispose], [RangeError] on an out-of-range
  /// size, [StateError] if upstream reports a non-empty string but hands back a
  /// null buffer pointer (threat model TM-19, TM-20), and [FormatException] if
  /// the bytes are not valid UTF-8.
  String toDartString() {
    final pointer = this.pointer;
    final size = checkNativeLength(
      context.bindings.TWStringSize(pointer),
      resourceType: 'TWStringHandle',
      what: 'the size TWStringSize reported',
    );
    if (size == 0) return '';
    final bytes = context.bindings.TWStringUTF8Bytes(pointer);
    if (bytes == nullptr) {
      throw StateError('TWStringUTF8Bytes returned nullptr for $size bytes');
    }
    // Copied out before decoding: `asTypedList` is a view over native memory
    // and must not outlive this call.
    final copy = Uint8List.fromList(bytes.cast<Uint8>().asTypedList(size));
    return utf8.decode(copy);
  }

  @override
  void releaseNative(Pointer<Void> pointer) {
    // The parameter, not the guarded getter: this wrapper is already marked
    // disposed by the time the base class calls this.
    context.bindings.TWStringDelete(pointer.cast<TWString>());
  }

  /// Type, byte length and disposed state. Never the text (threat model TM-09).
  @override
  String toString() {
    if (isDisposed) return 'TWStringHandle(disposed: true)';
    return 'TWStringHandle(length: $length, disposed: false)';
  }
}

/// Copies [value] into a `TWString`, runs [body] on it, and disposes it on the
/// way out — whether [body] returns or throws (PRD §11.2 item 4).
///
/// The handle is invalid once [body] returns; nothing may retain it.
T withTWString<T>(
  NativeContext context,
  String value,
  T Function(TWStringHandle string) body,
) {
  final handle = TWStringHandle.fromString(context, value);
  try {
    return body(handle);
  } finally {
    handle.dispose();
  }
}
