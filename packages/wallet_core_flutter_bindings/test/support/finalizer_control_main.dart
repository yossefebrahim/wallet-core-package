/// The control run of `test/memory/finalizer_observed_native_test.dart`: the
/// same redirected-delete harness, but with a finalizer that is **not**
/// detached after the block is freed by hand — the shape of a `dispose()` that
/// forgot `NativeFinalizer.detach`. It must abort the process (libmalloc
/// detects the double free); if it survives, the harness has no power and the
/// real tests beside it prove nothing.
///
/// Spawned as a subprocess by that test, because the abort ends the process.
/// Not a test itself: the file name does not end in `_test.dart`.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'gc_pressure.dart';

/// Allocated in its own frame so nothing here keeps the object reachable.
void _makeAndFreeByHand(NativeFinalizer finalizer) {
  final block = malloc<Uint8>(64).cast<Void>();
  final owner = _Owner();
  finalizer.attach(owner, block); // never detached
  malloc.free(block);
}

final class _Owner implements Finalizable {}

Future<void> main() async {
  final free = DynamicLibrary.process()
      .lookup<NativeFunction<Void Function(Pointer<Void>)>>('free');
  final finalizer = NativeFinalizer(free.cast());
  for (var i = 0; i < 50; i++) {
    _makeAndFreeByHand(finalizer);
  }
  // Running the finalizers is what aborts: a second `free` of each block.
  // `pumpUntil(() => false)` applies escalating pressure for the whole budget;
  // an abort ends the process long before it returns.
  await pumpUntil(() => false);
  stdout.writeln('control: SURVIVED (the harness has no power)');
}
