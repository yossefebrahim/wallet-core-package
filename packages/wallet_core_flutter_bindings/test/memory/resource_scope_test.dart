/// PRD §11.2 item 6 — scoped disposal, run against the real host library.
///
/// Every handle these tests create is a real `TWData` or `TWString` and every
/// disposal is a real `TWDataDelete` or `TWStringDelete`, counted through
/// `CountingBindings`. The tests skip when the library is absent (see
/// `test/support/host_library.dart`); they never pass by not exercising it.
@Tags(['native'])
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart';

import '../support/host_library.dart';
import '../support/observers.dart';

/// A [Disposable] that is not native-backed, for the failure paths.
///
/// Upstream's delete functions do not fail, so "a `dispose()` that throws" has
/// to be constructed. What is under test is the scope's unwinding, not the
/// resource, so a plain Dart object is the honest stand-in.
final class _ExplodingDisposable implements Disposable {
  _ExplodingDisposable(this.name, this.log);

  final String name;
  final List<String> log;

  @override
  bool isDisposed = false;

  @override
  void dispose() {
    if (isDisposed) return;
    isDisposed = true;
    log.add(name);
    throw StateError('dispose() of $name failed');
  }
}

/// A [Disposable] that only records that it was disposed.
final class _RecordingDisposable implements Disposable {
  _RecordingDisposable(this.name, this.log);

  final String name;
  final List<String> log;

  @override
  bool isDisposed = false;

  @override
  void dispose() {
    if (isDisposed) return;
    isDisposed = true;
    log.add(name);
  }
}

void main() {
  final skip = hostLibrarySkipReason();

  group('PRD §11.2 item 6 — ResourceScope', skip: skip, () {
    late CountingBindings bindings;
    late RecordingObserver observer;
    late NativeContext context;

    setUp(() {
      bindings = CountingBindings(DynamicLibrary.open(findHostLibrary()!));
      observer = RecordingObserver();
      context = NativeContext(bindings, observer: observer);
    });

    test('item 6 — a scope disposes everything registered in it, in reverse '
        'order of registration', () {
      late TWDataHandle first;
      late TWStringHandle second;
      late TWDataHandle third;

      final answer = runScope<int>(context, (scope) {
        first = scope.use(
          TWDataHandle.fromBytes(context, Uint8List.fromList([1])),
        );
        second = scope.use(TWStringHandle.fromString(context, 'two'));
        third = scope.data(Uint8List.fromList([3, 3, 3]));
        expect([first, second, third].every((r) => r.isDisposed), isFalse);
        return 7;
      });

      expect(answer, 7, reason: "the body's value is returned unchanged");
      expect(observer.created, [first, second, third]);
      expect(observer.disposed, [
        third,
        second,
        first,
      ], reason: 'last registered, first disposed');
      expect(bindings.dataDeletes, 2);
      expect(bindings.stringDeletes, 1);
    });

    test('item 6 — the scope disposes everything when the body throws, and '
        "rethrows the body's error", () {
      late TWDataHandle data;
      late TWStringHandle string;

      expect(
        () => runScope<void>(context, (scope) {
          data = scope.data(Uint8List.fromList([9, 9]));
          string = scope.string('nine');
          throw const FormatException('the body failed');
        }),
        throwsFormatException,
      );

      expect(data.isDisposed, isTrue);
      expect(string.isDisposed, isTrue);
      expect(observer.disposed, [string, data]);
      expect(bindings.dataDeletes, 1);
      expect(bindings.stringDeletes, 1);
    });

    test('item 6 — a throwing dispose() does not prevent the others, and the '
        'first error is the one rethrown', () {
      final log = <String>[];
      late TWDataHandle data;

      expect(
        () => runScope<void>(context, (scope) {
          scope.use(_RecordingDisposable('first', log));
          data = scope.data(Uint8List.fromList([4]));
          scope.use(_ExplodingDisposable('third', log));
          scope.use(_ExplodingDisposable('fourth', log));
        }),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('fourth'),
          ),
        ),
        reason: 'the first failure in reverse order — the last registered',
      );

      expect(log, [
        'fourth',
        'third',
        'first',
      ], reason: 'a throwing dispose() strands nothing behind it');
      expect(data.isDisposed, isTrue);
      expect(bindings.dataDeletes, 1);
    });

    test("item 6 — a dispose() that throws while unwinding does not replace "
        "the body's error", () {
      final log = <String>[];

      expect(
        () => runScope<void>(context, (scope) {
          scope.use(_ExplodingDisposable('bang', log));
          scope.data(Uint8List.fromList([5]));
          throw const FormatException('the body failed');
        }),
        throwsFormatException,
        reason:
            'the body is the cause; the delete that failed while unwinding '
            'is a consequence and must not hide it',
      );

      expect(log, ['bang'], reason: 'it was still disposed');
      expect(bindings.dataDeletes, 1);
    });

    test('item 6 — use() after the scope has closed throws StateError', () {
      late ResourceScope escaped;
      runScope<void>(context, (scope) {
        escaped = scope;
        scope.data(Uint8List.fromList([6]));
      });

      expect(
        () => escaped.use(_RecordingDisposable('late', <String>[])),
        throwsA(isA<StateError>()),
      );
      expect(
        () => escaped.string('late'),
        throwsA(isA<StateError>()),
        reason: 'the convenience methods register through use()',
      );
      // The handle the rejected call would have created is never made, so
      // nothing was allocated and left unowned.
      expect(bindings.stringDeletes, 0);
      expect(observer.created, hasLength(1));
    });

    test('item 6 — a resource the caller disposed early is simply skipped', () {
      late TWDataHandle early;
      runScope<void>(context, (scope) {
        early = scope.data(Uint8List.fromList([1, 2, 3]));
        early.dispose();
        expect(bindings.dataDeletes, 1);
        scope.string('still mine');
      });

      expect(early.isDisposed, isTrue);
      expect(bindings.dataDeletes, 1, reason: 'double dispose is a no-op');
      expect(bindings.stringDeletes, 1);
      expect(observer.disposed, hasLength(2));
    });

    test('item 6 — context.scope(...) is runScope(context, ...)', () {
      final round = context.scope<String>((scope) {
        expect(scope.context, same(context));
        final data = scope.data(Uint8List.fromList(utf8.encode('round trip')));
        final string = scope.string(utf8.decode(data.copyBytes()));
        return string.toDartString();
      });

      expect(round, 'round trip');
      expect(observer.created, hasLength(2));
      expect(observer.disposed, hasLength(2));
      expect(bindings.dataDeletes, 1);
      expect(bindings.stringDeletes, 1);
    });

    test('item 6 — use() returns its argument and registers it once', () {
      final log = <String>[];
      final resource = _RecordingDisposable('once', log);

      runScope<void>(context, (scope) {
        expect(scope.use(resource), same(resource));
        // Registering twice is harmless: the second dispose() is a no-op.
        expect(scope.use(resource), same(resource));
      });

      expect(log, ['once']);
    });

    test('item 6 — a scope does not own its context: handles created after it '
        'closed still work', () {
      runScope<void>(context, (scope) => scope.data(Uint8List.fromList([1])));

      final after = TWDataHandle.fromBytes(context, Uint8List.fromList([2]));
      expect(after.copyBytes(), Uint8List.fromList([2]));
      after.dispose();
      expect(bindings.dataDeletes, 2);
    });
  });
}
