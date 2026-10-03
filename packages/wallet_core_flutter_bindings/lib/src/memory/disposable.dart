/// The internal disposal vocabulary: [Disposable] and [DisposedError].
///
/// These types are **bindings-internal**. They are the synchronous half of the
/// two lifecycles in `docs/architecture/lifecycle.md` §5: a handle that lives
/// in one isolate and is released by the code that owns it. The public SDK
/// surface never sees them — it closes asynchronously (PRD §14.3) — and only
/// `advanced.dart` may re-export them.
library;

/// Something that owns a native resource and must be released explicitly.
///
/// Disposal is the primary cleanup path. The finalizer is a fallback for
/// objects a caller forgot, not a strategy (PRD §11.2 item 1).
abstract interface class Disposable {
  /// Releases the resource. Calling it twice is a no-op (PRD §11.2 item 3).
  void dispose();

  /// Whether [dispose] has already run.
  bool get isDisposed;
}

/// An internal native-backed object was used after `dispose()`.
///
/// Raised at the wrapper boundary and never in native code (PRD §11.2 item 3).
/// It is an [Error] rather than an exception because using a disposed handle is
/// a defect in the calling code, not a condition to recover from.
///
/// This class deliberately has no superclass of its own yet. The public error
/// hierarchy (`WalletCoreException`) belongs to the SDK package and is T1.11's
/// to write; `docs/architecture/lifecycle.md` §3 sketches this error as a
/// member of it, and T1.11 reparents it if it needs to.
///
/// [toString] names the resource type and nothing else. It never carries the
/// resource's contents, because a handle may hold key material and a message is
/// exactly the thing that reaches a log (threat model TM-09, TM-31).
final class DisposedError extends Error {
  /// Creates an error naming [resourceType], e.g. `'TWDataHandle'`.
  DisposedError(this.resourceType, [this.message = 'used after dispose()']);

  /// The Dart type name of the resource that was used. Never its contents.
  final String resourceType;

  /// What was attempted. Never contains buffer contents.
  final String message;

  @override
  String toString() => 'DisposedError: $resourceType $message';
}
