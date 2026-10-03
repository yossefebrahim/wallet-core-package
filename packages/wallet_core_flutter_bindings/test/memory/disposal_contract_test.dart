/// The disposal contract of PRD §11.2, items 1–5, one named test each, run
/// against the real host library.
///
/// Every test here calls the library that upstream's sources built: the delete
/// counts are counts of real `TWDataDelete` and `TWStringDelete` calls, and the
/// bytes asserted on came back out of native memory. The tests skip when that
/// library is absent (see `test/support/host_library.dart`); they never pass by
/// not exercising it.
@Tags(['native'])
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart';

import '../support/host_library.dart';
import '../support/observers.dart';

void main() {
  // Computed once, before any test is defined: with WCF_NATIVE_REQUIRED=1 this
  // throws instead of skipping, which is what `melos run test:native` wants.
  final skip = hostLibrarySkipReason();

  group('PRD §11.2 disposal contract', skip: skip, () {
    late CountingBindings bindings;
    late RecordingObserver observer;
    late NativeContext context;

    setUp(() {
      bindings = CountingBindings(DynamicLibrary.open(findHostLibrary()!));
      observer = RecordingObserver();
      context = NativeContext(bindings, observer: observer);
    });

    test('item 1 — every native-backed wrapper exposes dispose(), and disposal '
        'is the cleanup path that actually runs', () {
      final data = TWDataHandle.fromBytes(context, Uint8List.fromList([1, 2]));
      final string = TWStringHandle.fromString(context, 'ok');

      expect(data, isA<Disposable>());
      expect(string, isA<Disposable>());
      expect(data.isDisposed, isFalse);
      expect(string.isDisposed, isFalse);

      data.dispose();
      string.dispose();

      // The counts come from the wrapper's own calls into upstream. A finalizer
      // calls upstream's delete address directly and would not be counted here,
      // so these prove `dispose()` released both objects.
      expect(bindings.dataDeletes, 1);
      expect(bindings.stringDeletes, 1);
      expect(data.isDisposed, isTrue);
      expect(string.isDisposed, isTrue);
    });

    test('item 2 — dispose() calls the upstream delete, detaches the '
        'finalizer, and marks the wrapper disposed', () {
      final data = TWDataHandle.fromBytes(context, Uint8List.fromList([7]));
      expect(data.isFinalizerAttached, isTrue);
      expect(bindings.dataDeletes, 0);

      data.dispose();

      expect(bindings.dataDeletes, 1, reason: 'upstream delete was called');
      expect(data.isFinalizerAttached, isFalse, reason: 'finalizer detached');
      expect(data.isDisposed, isTrue, reason: 'marked disposed');
      expect(observer.disposed, [data]);
    });

    test('item 3 — double dispose is a no-op and any use after disposal '
        'throws DisposedError', () {
      final data = TWDataHandle.fromBytes(context, Uint8List.fromList([1, 2]));
      final string = TWStringHandle.fromString(context, 'abc');

      data.dispose();
      data.dispose();
      data.dispose();
      string.dispose();
      string.dispose();

      expect(bindings.dataDeletes, 1, reason: 'no second delete');
      expect(bindings.stringDeletes, 1, reason: 'no second delete');
      expect(observer.disposed.length, 2, reason: 'notified once each');

      expect(() => data.pointer, throwsA(isA<DisposedError>()));
      expect(() => data.length, throwsA(isA<DisposedError>()));
      expect(data.copyBytes, throwsA(isA<DisposedError>()));
      expect(() => string.pointer, throwsA(isA<DisposedError>()));
      expect(() => string.length, throwsA(isA<DisposedError>()));
      expect(string.toDartString, throwsA(isA<DisposedError>()));
    });

    test('item 4 — temporaries are released in finally, so a throwing body '
        'still leaves nothing undisposed', () {
      const iterations = 1000;
      final bytes = Uint8List.fromList(List<int>.filled(64, 0xAB));

      for (var i = 0; i < iterations; i++) {
        expect(
          () => withTWData<void>(context, bytes, (data) {
            expect(data.isDisposed, isFalse);
            throw const FormatException('the body failed');
          }),
          throwsFormatException,
        );
        expect(
          () => withTWString<void>(context, 'value $i', (string) {
            expect(string.isDisposed, isFalse);
            throw const FormatException('the body failed');
          }),
          throwsFormatException,
        );
      }

      expect(observer.created.length, iterations * 2);
      expect(observer.disposed.length, iterations * 2);
      expect(
        observer.created.every((resource) => resource.isDisposed),
        isTrue,
        reason: 'every handle created inside a failing scope was disposed',
      );
      expect(bindings.dataDeletes, iterations);
      expect(bindings.stringDeletes, iterations);
    });

    test('item 5 — a NativeFinalizer is attached at construction and detached '
        'on dispose', () {
      // What is asserted is the attach and the detach, which are this
      // wrapper's doing. **The finalizer's timing is not asserted**: when an
      // unreachable object's callback runs is the runtime's choice, guaranteed
      // only at the latest at isolate-group shutdown and not at all if the
      // process is killed, so no test can force it. T1.6b's leak tracker adds a
      // best-effort collection test on top of this.
      final data = TWDataHandle.fromBytes(context, Uint8List.fromList([1]));
      final string = TWStringHandle.fromString(context, 'x');

      expect(data.isFinalizerAttached, isTrue);
      expect(string.isFinalizerAttached, isTrue);
      expect(
        identical(context.dataFinalizer, context.stringFinalizer),
        isFalse,
        reason: 'each kind of object has its own delete function',
      );

      data.dispose();
      string.dispose();

      expect(data.isFinalizerAttached, isFalse);
      expect(string.isFinalizerAttached, isFalse);
    });

    test('the observer hook is told about creation and disposal, in order', () {
      final first = TWDataHandle.fromBytes(context, Uint8List.fromList([1]));
      final second = TWStringHandle.fromString(context, 'two');

      expect(observer.created, [first, second]);
      expect(observer.disposed, isEmpty);

      second.dispose();
      first.dispose();

      expect(observer.disposed, [second, first]);
    });

    test('no diagnostic string carries buffer contents (TM-09, TM-31)', () {
      const secret = 'unlikely-mnemonic-text-abandon-abandon';
      final data = TWDataHandle.fromBytes(
        context,
        Uint8List.fromList(utf8.encode(secret)),
      );
      final string = TWStringHandle.fromString(context, secret);

      expect(data.toString(), isNot(contains(secret)));
      expect(data.toString(), contains('TWDataHandle'));
      expect(data.toString(), contains('${data.length}'));
      expect(string.toString(), isNot(contains(secret)));
      expect(string.toString(), contains('TWStringHandle'));

      data.dispose();
      string.dispose();

      expect(data.toString(), 'TWDataHandle(disposed: true)');
      expect(string.toString(), 'TWStringHandle(disposed: true)');

      final error = DisposedError('$data');
      expect(error.toString(), isNot(contains(secret)));
    });
  });
}
