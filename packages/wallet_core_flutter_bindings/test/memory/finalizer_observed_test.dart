/// PRD §11.2 items 2 and 5, **observed** rather than inferred from a flag the
/// wrapper sets itself.
///
/// The real `NativeResource` wiring is used unchanged — the same `attach` in
/// the constructor, the same `detach` in `dispose()`, the same `NativeFinalizer`
/// over `bindings.addresses.TWDataDelete` / `TWStringDelete` — but the bindings
/// are built over a lookup that resolves those two delete symbols to libc
/// `free`, and the "native object" is a `malloc` block. Two things then become
/// observable from Dart:
///
/// * a block is freed: `malloc_zone_from_ptr` returns null for it;
/// * a block is freed twice: libmalloc aborts the process.
///
/// So a forgotten handle must be *seen* freed by the finalizer, a disposed
/// handle must survive a collection that is *seen* to have run (its sibling
/// sentinel was finalized) without the process aborting, and a control that
/// leaves a finalizer attached after a manual free must abort. The control runs
/// in a subprocess (`../support/finalizer_control_main.dart`) because the abort
/// ends its process.
///
/// macOS only (`malloc_zone_from_ptr`); the library the project's native tests
/// target is the macOS host build. No upstream library is loaded: libc is
/// enough.
@TestOn('mac-os')
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';
import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart';

import '../support/gc_pressure.dart';

final DynamicLibrary _process = DynamicLibrary.process();

final Pointer<NativeFunction<Void Function(Pointer<Void>)>> _free = _process
    .lookup('free');

final int Function(Pointer<Void>) _zoneOf = _process
    .lookupFunction<
      IntPtr Function(Pointer<Void>),
      int Function(Pointer<Void>)
    >('malloc_zone_from_ptr');

/// Whether [block], once malloc'd, has been freed.
bool _isFreed(Pointer<Void> block) => _zoneOf(block) == 0;

/// A symbol lookup that resolves the two delete functions to `free` and
/// refuses everything else: nothing else may be reached by these tests.
Pointer<T> _lookup<T extends NativeType>(String name) {
  if (name == 'TWDataDelete' || name == 'TWStringDelete') {
    return _free.cast<T>();
  }
  throw StateError('unexpected native symbol $name in a libc-only test');
}

NativeContext _freshContext() =>
    NativeContext(WalletCoreBindings.fromLookup(_lookup));

Pointer<Void> _block() => malloc<Uint8>(64).cast<Void>();

/// Each of these is its own frame so that nothing in the caller keeps the
/// wrapper reachable (a `Finalizable` local lives to the end of its scope).
Pointer<Void> _forgottenData(NativeContext context) {
  final block = _block();
  TWDataHandle.adopt(context, block.cast<TWData>());
  return block;
}

Pointer<Void> _forgottenString(NativeContext context) {
  final block = _block();
  TWStringHandle.adopt(context, block.cast<TWString>());
  return block;
}

Pointer<Void> _disposedData(NativeContext context) {
  final block = _block();
  final handle = TWDataHandle.adopt(context, block.cast<TWData>());
  handle.dispose();
  return block;
}

Pointer<Void> _disposedString(NativeContext context) {
  final block = _block();
  final handle = TWStringHandle.adopt(context, block.cast<TWString>());
  handle.dispose();
  return block;
}

void main() {
  const count = 50;

  test('a forgotten TWData is freed by its NativeFinalizer', () async {
    final context = _freshContext();
    final blocks = [for (var i = 0; i < count; i++) _forgottenData(context)];
    for (final block in blocks) {
      expect(_isFreed(block), isFalse, reason: 'nothing freed it yet');
    }

    final all = await pumpUntil(() => blocks.every(_isFreed));

    expect(
      all,
      isTrue,
      reason:
          'the finalizer did not free '
          '${blocks.where((b) => !_isFreed(b)).length}/$count forgotten '
          'blocks within the budget',
    );
  });

  test('a forgotten TWString is freed by its NativeFinalizer', () async {
    final context = _freshContext();
    final blocks = [for (var i = 0; i < count; i++) _forgottenString(context)];

    final all = await pumpUntil(() => blocks.every(_isFreed));

    expect(
      all,
      isTrue,
      reason:
          'the finalizer did not free '
          '${blocks.where((b) => !_isFreed(b)).length}/$count forgotten '
          'blocks within the budget',
    );
  });

  test('a disposed handle is freed once by dispose() and never again by its '
      'finalizer', () async {
    final context = _freshContext();
    final disposed = [
      for (var i = 0; i < count; i++) ...[
        _disposedData(context),
        _disposedString(context),
      ],
    ];
    for (final block in disposed) {
      expect(_isFreed(block), isTrue, reason: 'dispose() freed it, once');
    }
    // A sentinel created after them: when its block is seen freed by its
    // finalizer, a collection that covers every handle above has run. A
    // finalizer still attached to any disposed handle would by now have freed
    // its block a second time, which aborts this process.
    final sentinels = [for (var i = 0; i < count; i++) _forgottenData(context)];

    final collected = await pumpUntil(() => sentinels.every(_isFreed));

    expect(
      collected,
      isTrue,
      reason: 'no collection was observed, so the check proved nothing',
    );
  });

  test('a handle that is disposed twice frees its block once', () {
    final context = _freshContext();
    final block = _block();
    final handle = TWDataHandle.adopt(context, block.cast<TWData>());

    handle.dispose();
    expect(_isFreed(block), isTrue);
    // A second `free` of this block would abort the process here.
    handle.dispose();
    handle.dispose();
    expect(handle.isDisposed, isTrue);
  });

  test('control: a finalizer left attached after a manual free aborts the '
      'process — the harness can fail', () async {
    final config = await Isolate.packageConfig;
    expect(config, isNotNull);
    final script = File(
      '${Directory.current.path}/test/support/finalizer_control_main.dart',
    );
    expect(script.existsSync(), isTrue, reason: script.path);

    final result = await Process.run(Platform.resolvedExecutable, [
      '--packages=${config!.toFilePath()}',
      script.path,
    ]);

    expect(
      result.stdout,
      isNot(contains('SURVIVED')),
      reason: 'the control ran to the end: the double free went unnoticed',
    );
    expect(
      result.exitCode,
      isNot(0),
      reason: 'the control must abort on the double free',
    );
  }, timeout: const Timeout(Duration(seconds: 90)));
}
