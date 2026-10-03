/// [TWDataHandle]: ownership of one upstream `TWData` object.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../generated/ffi/wallet_core_bindings.dart';
import 'limits.dart';
import 'native_context.dart';
import 'native_resource.dart';

/// Owns one upstream `TWData` — a resizable block of bytes — and frees it with
/// `TWDataDelete`.
///
/// **`dispose()` is the primary cleanup path**; the native finalizer is a
/// fallback for a handle a caller forgot (PRD §11.2 item 1). Upstream's
/// `TWDataDelete` calls `memzero` on the buffer this object currently owns
/// before freeing it (PRD §11.1 [VERIFIED]), which is the whole reason disposal
/// is the primary path: the buffer stops holding what it holds when this is
/// called, not when the collector gets round to it.
///
/// A handle carries bytes and never interprets them. They may be key material,
/// so nothing here renders them: [toString] reports type, length and disposed
/// state only (threat model TM-09, TM-31).
///
/// Belongs to the isolate that created it.
final class TWDataHandle extends NativeResource {
  TWDataHandle._(NativeContext context, Pointer<TWData> pointer, int? size)
    : super(
        context: context,
        pointer: pointer.cast<Void>(),
        finalizer: context.dataFinalizer,
        externalSize: size,
      );

  /// Copies [bytes] into a new native `TWData`.
  ///
  /// The temporary native buffer the copy goes through is allocated with
  /// `package:ffi`'s `calloc` and freed in a `finally`, so an exception cannot
  /// leak it (PRD §11.2 item 4). Upstream copies out of it, so it is gone
  /// before this returns either way.
  ///
  /// Throws [RangeError] if [bytes] is longer than [maxNativeBufferBytes].
  factory TWDataHandle.fromBytes(NativeContext context, Uint8List bytes) {
    final size = checkNativeLength(
      bytes.length,
      resourceType: 'TWDataHandle',
      what: 'the length of the bytes to copy in',
    );
    // `calloc<Uint8>(0)` has no useful meaning; upstream reads nothing when the
    // size is zero, so one byte is allocated purely to have an address to pass.
    final buffer = calloc<Uint8>(size == 0 ? 1 : size);
    try {
      if (size != 0) {
        buffer.asTypedList(size).setAll(0, bytes);
      }
      final pointer = context.bindings.TWDataCreateWithBytes(buffer, size);
      if (pointer == nullptr) {
        throw StateError(
          'TWDataCreateWithBytes returned nullptr for $size bytes',
        );
      }
      return TWDataHandle._(context, pointer, size);
    } finally {
      calloc.free(buffer);
    }
  }

  /// Takes ownership of a `TWData` upstream returned to us.
  ///
  /// The caller must not delete [pointer] afterwards and must not adopt the
  /// same pointer twice: from here on this handle frees it.
  ///
  /// Throws [ArgumentError] when [pointer] is `nullptr`. Upstream signals
  /// failure by returning a null pointer, so a null is a failure to be reported
  /// by the call site that made the call — never something to wrap (threat
  /// model TM-20).
  ///
  /// No `externalSize` is given to the finalizer here: reading the size would
  /// mean a native call inside a constructor that has already taken ownership,
  /// and a size that failed validation there would leak the very pointer it was
  /// rejecting. [length] reads and validates it on demand instead.
  factory TWDataHandle.adopt(NativeContext context, Pointer<TWData> pointer) {
    if (pointer == nullptr) {
      throw ArgumentError.value(
        null,
        'pointer',
        'TWDataHandle.adopt: upstream returned nullptr, which is a failure '
            'signal and not a value to wrap',
      );
    }
    return TWDataHandle._(context, pointer, null);
  }

  /// The native pointer.
  ///
  /// Throws `DisposedError` after [dispose]. The pointer is valid only until
  /// then; nothing may retain it.
  Pointer<TWData> get pointer => rawPointer.cast<TWData>();

  /// The number of bytes upstream reports this object holds.
  ///
  /// Validated against [maxNativeBufferBytes] before it is returned, because it
  /// is upstream's answer and everything returning from native code is
  /// untrusted here (threat model TM-17). Throws `DisposedError` after
  /// [dispose] and [RangeError] if the reported size is negative or too large.
  int get length => checkNativeLength(
    context.bindings.TWDataSize(pointer),
    resourceType: 'TWDataHandle',
    what: 'the size TWDataSize reported',
  );

  /// Copies the contents out into a Dart-owned list.
  ///
  /// Always a copy, never a view over native memory: a view would keep reading
  /// the buffer after this handle freed it. The length is validated before
  /// anything is allocated (threat model TM-17).
  ///
  /// Throws `DisposedError` after [dispose], [RangeError] on an out-of-range
  /// size, and [StateError] if upstream reports a non-empty object but hands
  /// back a null buffer pointer (threat model TM-19, TM-20).
  Uint8List copyBytes() {
    final pointer = this.pointer;
    final size = checkNativeLength(
      context.bindings.TWDataSize(pointer),
      resourceType: 'TWDataHandle',
      what: 'the size TWDataSize reported',
    );
    if (size == 0) return Uint8List(0);
    final bytes = context.bindings.TWDataBytes(pointer);
    if (bytes == nullptr) {
      throw StateError('TWDataBytes returned nullptr for $size bytes');
    }
    return Uint8List.fromList(bytes.asTypedList(size));
  }

  @override
  void releaseNative(Pointer<Void> pointer) {
    // The parameter, not the guarded getter: this wrapper is already marked
    // disposed by the time the base class calls this.
    context.bindings.TWDataDelete(pointer.cast<TWData>());
  }

  /// Type, length and disposed state. Never contents (threat model TM-09).
  @override
  String toString() {
    if (isDisposed) return 'TWDataHandle(disposed: true)';
    return 'TWDataHandle(length: $length, disposed: false)';
  }
}

/// Copies [bytes] into a `TWData`, runs [body] on it, and disposes it on the
/// way out — whether [body] returns or throws (PRD §11.2 item 4).
///
/// The handle is invalid once [body] returns; nothing may retain it.
T withTWData<T>(
  NativeContext context,
  Uint8List bytes,
  T Function(TWDataHandle data) body,
) {
  final handle = TWDataHandle.fromBytes(context, bytes);
  try {
    return body(handle);
  } finally {
    handle.dispose();
  }
}
