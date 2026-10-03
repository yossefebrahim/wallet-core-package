/// [NativeResource]: the base every handle in this library extends.
library;

import 'dart:ffi';

import 'disposable.dart';
import 'native_context.dart';

/// Base for a wrapper around one native-owned object.
///
/// **Disposal is the primary cleanup path on every subclass.** The finalizer is
/// a fallback for an object a caller forgot, not a strategy (PRD §11.2 item 1),
/// and there are two reasons it cannot be the plan. Upstream's `TWDataDelete`
/// and `TWStringDelete` `memzero` the buffer the object currently owns before
/// freeing it (PRD §11.1 [VERIFIED]), so the sooner one is called the sooner
/// that buffer stops holding what it holds; and a `NativeFinalizer` runs "as
/// early as possible" after an object becomes unreachable, but its timing
/// between that and isolate-group shutdown is not guaranteed and it does not
/// run at all if the process is killed.
///
/// On [dispose] the wrapper calls upstream's delete function for that object,
/// **detaches** its native finalizer using the detach key registered at attach
/// time, and marks itself disposed (PRD §11.2 item 2). Any use after that
/// throws [DisposedError], checked here at the wrapper boundary and never in
/// native code (item 3).
///
/// The [NativeFinalizer] is attached at construction with the native pointer as
/// its attach token and this wrapper as its detach key (item 5). Its callback
/// is upstream's delete function directly: no Dart code runs in it, which is
/// exactly why it cannot be used to release something owned by another isolate.
///
/// A resource belongs to the isolate that created it. Do not share one across
/// isolates.
abstract base class NativeResource implements Disposable, Finalizable {
  /// Adopts [pointer] and attaches [finalizer] to this wrapper.
  ///
  /// [pointer] must not be `nullptr`; a subclass checks that before calling,
  /// because a null return from upstream is a failure signal and never a thing
  /// to wrap (threat model TM-20).
  ///
  /// [externalSize] is passed to the finalizer where the size of the native
  /// allocation is known, so the garbage collector can account for memory it
  /// cannot see.
  NativeResource({
    required this.context,
    required Pointer<Void> pointer,
    required NativeFinalizer finalizer,
    int? externalSize,
  }) : _pointer = pointer,
       _finalizer = finalizer {
    if (pointer == nullptr) {
      throw ArgumentError.value(null, 'pointer', 'must not be nullptr');
    }
    finalizer.attach(this, pointer, detach: this, externalSize: externalSize);
    _finalizerAttached = true;
    context.observer.onResourceCreated(this);
  }

  /// The library, bindings, and finalizers this resource was created against.
  final NativeContext context;

  final NativeFinalizer _finalizer;
  final Pointer<Void> _pointer;
  bool _disposed = false;
  bool _finalizerAttached = false;

  @override
  bool get isDisposed => _disposed;

  /// Whether the native finalizer is currently attached to this wrapper.
  ///
  /// Diagnostic only, and the observable half of PRD §11.2 item 5: it is `true`
  /// from the moment the attach in the constructor returns and `false` from the
  /// moment the detach in [dispose] returns. It says nothing about *when* a
  /// still-attached finalizer would run — that timing is the runtime's and is
  /// not asserted anywhere.
  bool get isFinalizerAttached => _finalizerAttached;

  /// The native pointer, guarded.
  ///
  /// Throws [DisposedError] once [dispose] has run. Subclasses expose this
  /// under their own type.
  Pointer<Void> get rawPointer {
    checkNotDisposed();
    return _pointer;
  }

  /// Calls upstream's delete function for this kind of object.
  ///
  /// Implemented by each subclass and called by [dispose] exactly once, with
  /// the pointer this wrapper was constructed with. It is never called after
  /// disposal and never called on a `nullptr`.
  void releaseNative(Pointer<Void> pointer);

  /// Releases the native object, detaches the finalizer, and marks this
  /// wrapper disposed.
  ///
  /// Calling it a second time does nothing at all: no second delete, no second
  /// detach, no second observer notification (PRD §11.2 item 3).
  @override
  void dispose() {
    if (_disposed) return;
    // Marked before the delete rather than after, so that a delete which
    // somehow failed still cannot be repeated on the same pointer. The
    // `finally` keeps the detach on the same footing.
    _disposed = true;
    try {
      releaseNative(_pointer);
    } finally {
      _finalizer.detach(this);
      _finalizerAttached = false;
      context.observer.onResourceDisposed(this);
    }
  }

  /// Throws [DisposedError] if this wrapper has been disposed.
  ///
  /// Every member that reaches native memory calls this first.
  void checkNotDisposed() {
    if (_disposed) throw DisposedError('$runtimeType');
  }

  /// Type and disposed state only.
  ///
  /// No wrapper in this library ever renders its buffer: a handle may hold key
  /// material, and a `toString()` is exactly what reaches a log (threat model
  /// TM-09, TM-31).
  @override
  String toString() => '$runtimeType(disposed: $_disposed)';
}
