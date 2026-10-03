/// Hand-written ownership wrappers over upstream's `TWData` and `TWString`
/// objects (PRD §9, §11.2).
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// Everything here is the **internal** lifecycle of
/// `docs/architecture/lifecycle.md` §5: a synchronous `void dispose()`, a
/// `DisposedError` on use after it, and a native finalizer as the fallback for
/// a handle a caller forgot. Handles belong to the isolate that created them.
/// The default public SDK surface never exposes these types; they reach a
/// consumer only through `advanced.dart` or by depending on this package
/// directly, which means accepting the ownership responsibilities of PRD §11.
///
/// Every handle is created against a [NativeContext], which holds the loaded
/// library's bindings and the two finalizers. There is no global and no
/// singleton: locating and loading the library is the native package's job, and
/// wiring the two together is the SDK's.
///
/// A handle moves bytes and never interprets them. Nothing here renders a
/// buffer's contents in a message or a `toString()`.
library;

export 'disposable.dart' show Disposable, DisposedError;
export 'leak_tracker.dart' show LeakRecord, LeakReport, LeakTracker;
export 'limits.dart' show checkNativeLength, maxNativeBufferBytes;
export 'native_context.dart'
    show NativeContext, NoopResourceObserver, ResourceObserver;
export 'native_resource.dart' show NativeResource;
export 'resource_scope.dart' show NativeContextScope, ResourceScope, runScope;
export 'tw_data.dart' show TWDataHandle, withTWData;
export 'tw_string.dart' show TWStringHandle, withTWString;
