/// The engine's handle types beyond `TWData` and `TWString`, and the native
/// finalizers they attach. **Internal**: never exported.
///
/// Each type owns one upstream object under the disposal contract of PRD §11.2
/// by extending the bindings' `NativeResource`: explicit `dispose()`, finalizer
/// detach, double-dispose no-op, `DisposedError` after disposal. The engine
/// only ever holds the key and address handles here for the length of one call,
/// registered with a scope that releases them in a `finally`.
library;

import 'dart:ffi';

import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart';

/// The native finalizers for the upstream object types the engine wraps, one
/// set per [NativeContext].
///
/// Each callback is upstream's delete function itself, taken as a raw address
/// from the generated bindings' `addresses` member, so no Dart code runs in it
/// (PRD §11.2 item 5). They are kept beside the context rather than in it so
/// that the bindings' memory layer stays unchanged; an [Expando] holds them
/// for exactly as long as the context lives.
final class EngineFinalizers {
  EngineFinalizers._(WalletCoreBindings bindings)
    : hdWallet = NativeFinalizer(
        bindings.addresses.TWHDWalletDelete.cast<NativeFinalizerFunction>(),
      ),
      privateKey = NativeFinalizer(
        bindings.addresses.TWPrivateKeyDelete.cast<NativeFinalizerFunction>(),
      ),
      publicKey = NativeFinalizer(
        bindings.addresses.TWPublicKeyDelete.cast<NativeFinalizerFunction>(),
      ),
      anyAddress = NativeFinalizer(
        bindings.addresses.TWAnyAddressDelete.cast<NativeFinalizerFunction>(),
      );

  static final Expando<EngineFinalizers> _byContext = Expando<EngineFinalizers>(
    'EngineFinalizers',
  );

  /// The finalizers for [context], created on first use.
  static EngineFinalizers of(NativeContext context) =>
      _byContext[context] ??= EngineFinalizers._(context.bindings);

  /// Callback `TWHDWalletDelete`.
  final NativeFinalizer hdWallet;

  /// Callback `TWPrivateKeyDelete`.
  final NativeFinalizer privateKey;

  /// Callback `TWPublicKeyDelete`.
  final NativeFinalizer publicKey;

  /// Callback `TWAnyAddressDelete`.
  final NativeFinalizer anyAddress;
}

/// Owns one upstream `TWPrivateKey` and frees it with `TWPrivateKeyDelete`.
///
/// **`dispose()` is the primary cleanup path.** The engine never lets one of
/// these outlive the call that derived it. [toString] is the base class's:
/// type and disposed state, never the key.
final class PrivateKeyHandle extends NativeResource {
  PrivateKeyHandle._(NativeContext context, Pointer<TWPrivateKey> pointer)
    : super(
        context: context,
        pointer: pointer.cast<Void>(),
        finalizer: EngineFinalizers.of(context).privateKey,
      );

  /// Takes ownership of a key upstream returned. [pointer] must not be
  /// `nullptr`; the call site reports a null return as a typed error first.
  factory PrivateKeyHandle.adopt(
    NativeContext context,
    Pointer<TWPrivateKey> pointer,
  ) => PrivateKeyHandle._(context, _nonNull(pointer, 'PrivateKeyHandle'));

  /// The native pointer. Throws the bindings' `DisposedError` after disposal.
  Pointer<TWPrivateKey> get pointer => rawPointer.cast<TWPrivateKey>();

  @override
  void releaseNative(Pointer<Void> pointer) =>
      context.bindings.TWPrivateKeyDelete(pointer.cast<TWPrivateKey>());
}

/// Owns one upstream `TWPublicKey` and frees it with `TWPublicKeyDelete`.
final class PublicKeyHandle extends NativeResource {
  PublicKeyHandle._(NativeContext context, Pointer<TWPublicKey> pointer)
    : super(
        context: context,
        pointer: pointer.cast<Void>(),
        finalizer: EngineFinalizers.of(context).publicKey,
      );

  /// Takes ownership of a public key upstream returned. [pointer] must not be
  /// `nullptr`.
  factory PublicKeyHandle.adopt(
    NativeContext context,
    Pointer<TWPublicKey> pointer,
  ) => PublicKeyHandle._(context, _nonNull(pointer, 'PublicKeyHandle'));

  /// The native pointer. Throws the bindings' `DisposedError` after disposal.
  Pointer<TWPublicKey> get pointer => rawPointer.cast<TWPublicKey>();

  @override
  void releaseNative(Pointer<Void> pointer) =>
      context.bindings.TWPublicKeyDelete(pointer.cast<TWPublicKey>());
}

/// Owns one upstream `TWAnyAddress` and frees it with `TWAnyAddressDelete`.
final class AnyAddressHandle extends NativeResource {
  AnyAddressHandle._(NativeContext context, Pointer<TWAnyAddress> pointer)
    : super(
        context: context,
        pointer: pointer.cast<Void>(),
        finalizer: EngineFinalizers.of(context).anyAddress,
      );

  /// Takes ownership of an address object upstream returned. [pointer] must
  /// not be `nullptr`.
  factory AnyAddressHandle.adopt(
    NativeContext context,
    Pointer<TWAnyAddress> pointer,
  ) => AnyAddressHandle._(context, _nonNull(pointer, 'AnyAddressHandle'));

  /// The native pointer. Throws the bindings' `DisposedError` after disposal.
  Pointer<TWAnyAddress> get pointer => rawPointer.cast<TWAnyAddress>();

  @override
  void releaseNative(Pointer<Void> pointer) =>
      context.bindings.TWAnyAddressDelete(pointer.cast<TWAnyAddress>());
}

Pointer<T> _nonNull<T extends NativeType>(Pointer<T> pointer, String type) {
  if (pointer == nullptr) {
    throw ArgumentError.value(
      null,
      'pointer',
      '$type.adopt: upstream returned nullptr, which is a failure signal and '
          'not a value to wrap',
    );
  }
  return pointer;
}
