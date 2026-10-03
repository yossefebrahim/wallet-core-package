/// The per-library context every handle is created against, and the
/// observation hook the debug tooling plugs into.
library;

import 'dart:ffi';

import '../generated/ffi/wallet_core_bindings.dart';
import 'native_resource.dart';

/// Notified when a [NativeResource] is created and when it is disposed.
///
/// This is the single seam the debug-only tooling attaches to. It is
/// deliberately tiny and identity-only: an implementation is handed the
/// resource itself so it can record its type and hold a weak reference to it,
/// and it must record identity and provenance only — type, byte *length*,
/// allocation stack trace — never contents (threat model TM-31).
///
/// [onResourceCreated] is called from [NativeResource]'s constructor, after the
/// finalizer is attached and before the subclass's own constructor body runs.
/// An implementation may therefore read [NativeResource.isDisposed] and
/// `runtimeType`, and must not call anything a subclass defines.
/// [onResourceDisposed] is called once, at the end of the first `dispose()`.
/// Neither call is made again for the same resource.
///
/// Implementations must not throw: they run on the disposal path, where an
/// exception would mask the release it is observing.
abstract interface class ResourceObserver {
  /// A resource has been created and its finalizer attached.
  void onResourceCreated(NativeResource resource);

  /// A resource has been disposed. Called once, on the first `dispose()` only.
  void onResourceDisposed(NativeResource resource);
}

/// The default observer: records nothing.
///
/// It is `const`, so a release build in which no other observer is ever
/// constructed can tree-shake the whole observation path (PRD §16 S8,
/// threat model TM-30).
final class NoopResourceObserver implements ResourceObserver {
  /// The one instance anybody needs.
  const NoopResourceObserver();

  @override
  void onResourceCreated(NativeResource resource) {}

  @override
  void onResourceDisposed(NativeResource resource) {}
}

/// One loaded native library, the bindings over it, and the two
/// [NativeFinalizer]s its handles share.
///
/// Every handle takes its context explicitly: there is no global and no
/// singleton here. Locating and opening the library belongs to
/// `wallet_core_flutter_native` (T1.7), and wiring the two together belongs to
/// the SDK (T1.11); this class only holds what is already open.
///
/// A context is not thread- or isolate-safe in any way its handles are not: the
/// handles created against it belong to the isolate that created them, because
/// a native finalizer cannot free something owned by another isolate
/// (`docs/architecture/lifecycle.md` §5).
final class NativeContext {
  /// Wraps already-constructed [bindings].
  ///
  /// [observer] is the T1.6b seam; the default records nothing.
  NativeContext(this.bindings, {this.observer = const NoopResourceObserver()});

  /// The generated bindings over the loaded library.
  final WalletCoreBindings bindings;

  /// Notified as this context's resources are created and disposed.
  final ResourceObserver observer;

  /// The finalizer for `TWData` objects. Its callback is upstream's
  /// `TWDataDelete` itself, taken as a raw address from the generated
  /// bindings' `addresses` member, so no Dart code runs in it (PRD §11.2
  /// item 5).
  late final NativeFinalizer dataFinalizer = NativeFinalizer(
    bindings.addresses.TWDataDelete.cast<NativeFinalizerFunction>(),
  );

  /// The finalizer for `TWString` objects. Its callback is upstream's
  /// `TWStringDelete` itself; see [dataFinalizer].
  late final NativeFinalizer stringFinalizer = NativeFinalizer(
    bindings.addresses.TWStringDelete.cast<NativeFinalizerFunction>(),
  );
}
