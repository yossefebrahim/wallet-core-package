/// [ResourceScope] and [runScope]: dispose everything a block created, in
/// reverse order, however the block ends (PRD §11.2 item 6).
library;

import 'dart:typed_data';

import 'disposable.dart';
import 'native_context.dart';
import 'tw_data.dart';
import 'tw_string.dart';

/// Collects the resources a block creates and disposes them on the way out.
///
/// A scope is the exception-safe form of the `try`/`finally` pair every handle
/// otherwise needs: register a resource with [use] and it is disposed when the
/// block ends, whether it returns or throws (PRD §11.2 item 6). It is created
/// by [runScope] — or by `context.scope(...)` — and is valid only for the
/// duration of that call.
///
/// A scope **does not own its [context]**: the context outlives it, and closing
/// a scope neither disposes nor invalidates it. Nor does a scope attach a
/// finalizer of its own; each resource keeps the one it was constructed with,
/// so a scope that is somehow never closed leaves its resources exactly as they
/// would have been without it.
///
/// Scopes are for the isolate that owns the handles. Do not hold one, do not
/// pass one to another isolate, and do not let one escape its block.
abstract interface class ResourceScope {
  /// The context the resources in this scope were created against.
  NativeContext get context;

  /// Registers [resource] for disposal at the end of the scope and returns it.
  ///
  /// The return value is the argument, so a creation can be wrapped in place:
  ///
  /// ```dart
  /// final data = scope.use(TWDataHandle.fromBytes(context, bytes));
  /// ```
  ///
  /// Registering the same resource twice is harmless — the second `dispose()`
  /// is a no-op — but it is not what the API is for.
  ///
  /// Throws [StateError] once the scope has closed: a resource registered then
  /// would never be disposed by anybody, and silently accepting it would turn a
  /// scope that escaped its block into a leak.
  T use<T extends Disposable>(T resource);

  /// Copies [bytes] into a new `TWData` registered with [use].
  ///
  /// Shorthand for `use(TWDataHandle.fromBytes(context, bytes))`; identical in
  /// every respect, including the [RangeError] on an oversized length and the
  /// [StateError] after the scope has closed — which is raised *before* any
  /// native object is created, so a rejected call allocates nothing.
  TWDataHandle data(Uint8List bytes);

  /// Copies [value] into a new `TWString` registered with [use].
  ///
  /// Shorthand for `use(TWStringHandle.fromString(context, value))`; see
  /// [data].
  TWStringHandle string(String value);
}

/// Runs [body] with a fresh [ResourceScope] over [context] and disposes
/// everything it registered.
///
/// Disposal happens in **reverse order of registration** — the last resource
/// created is the first released — and it happens whether [body] returns or
/// throws. Reverse order is the order a nested `try`/`finally` would have
/// produced, and it is the order that holds for a resource built out of an
/// earlier one: the derived object is released while the thing it was derived
/// from is still alive.
///
/// **Which error wins.** At most one error leaves this function:
///
/// * If [body] throws, that error is rethrown with its original stack trace.
///   Every registered resource is still disposed first, and an error thrown by
///   one of those `dispose()` calls is **discarded**. The body's failure is the
///   one the caller has to handle; a delete that failed while unwinding is
///   almost always a consequence of it, and letting the second error replace
///   the first would hide the cause of both.
/// * If [body] returns and one or more `dispose()` calls throw, the disposal of
///   the remaining resources still runs to completion and the **first** error —
///   the one from the resource disposed earliest, that is, registered latest —
///   is rethrown afterwards. Later ones are discarded for the same reason.
///
/// In both cases every resource gets its `dispose()` called exactly once: a
/// throwing delete never strands the resources behind it. A `NativeResource`
/// marks itself disposed before it calls upstream, so even a resource whose
/// delete threw is not deleted a second time.
///
/// A resource the caller disposed early is simply disposed again, which is a
/// no-op (PRD §11.2 item 3); there is nothing to unregister.
///
/// [body] must be **synchronous**. Disposal happens when it returns, so a
/// `Future` it returned would still be pending over resources that are already
/// released. Nothing here can detect that for you: use the scope inside the
/// asynchronous function rather than around it.
T runScope<T>(NativeContext context, T Function(ResourceScope scope) body) {
  final scope = _Scope(context);
  final T result;
  try {
    result = body(scope);
  } catch (error, stackTrace) {
    scope._closeAll();
    Error.throwWithStackTrace(error, stackTrace);
  }
  final failure = scope._closeAll();
  if (failure != null) {
    Error.throwWithStackTrace(failure.error, failure.stackTrace);
  }
  return result;
}

/// `context.scope(...)`, the same thing spelled from the context.
extension NativeContextScope on NativeContext {
  /// Runs [body] with a scope over this context; see [runScope], which this
  /// forwards to and which holds the only implementation.
  T scope<T>(T Function(ResourceScope scope) body) => runScope(this, body);
}

/// The first failure seen while closing a scope, with the stack trace it was
/// thrown with.
typedef _Failure = ({Object error, StackTrace stackTrace});

final class _Scope implements ResourceScope {
  _Scope(this.context);

  @override
  final NativeContext context;

  final List<Disposable> _resources = <Disposable>[];
  bool _closed = false;

  @override
  T use<T extends Disposable>(T resource) {
    _checkOpen();
    _resources.add(resource);
    return resource;
  }

  @override
  TWDataHandle data(Uint8List bytes) {
    // Checked *before* the handle exists. Creating one and then discovering
    // the scope was closed would leave a native object nobody owns — the exact
    // thing the [StateError] is warning about.
    _checkOpen();
    return use(TWDataHandle.fromBytes(context, bytes));
  }

  @override
  TWStringHandle string(String value) {
    _checkOpen();
    return use(TWStringHandle.fromString(context, value));
  }

  void _checkOpen() {
    if (_closed) {
      throw StateError(
        'ResourceScope.use() was called after the scope closed. A resource '
        'registered now would never be disposed; create it inside the scope '
        'body, or dispose it yourself.',
      );
    }
  }

  /// Disposes everything registered, last first, and returns the first failure.
  ///
  /// Closing first is deliberate: a `dispose()` that reaches back into this
  /// scope gets the [StateError] rather than adding a resource to a list that
  /// is already being drained.
  _Failure? _closeAll() {
    _closed = true;
    _Failure? failure;
    for (var i = _resources.length - 1; i >= 0; i--) {
      try {
        _resources[i].dispose();
      } catch (error, stackTrace) {
        failure ??= (error: error, stackTrace: stackTrace);
      }
    }
    // The scope holds the only reference some of these may have had; dropping
    // them keeps a scope object that outlived its block from keeping disposed
    // wrappers reachable.
    _resources.clear();
    return failure;
  }
}
