/// PRD §11.2 item 7 — the debug-only leak tracker, against the real host
/// library.
///
/// Two of the three things the tracker reports are exact and are asserted here:
/// creation and disposal, which `NativeResource` tells it about. The third —
/// collection without disposal — depends on when the garbage collector runs,
/// which Dart gives no way to force, so the test for it is **best effort**: it
/// allocates, drops every reference, and makes garbage until either the count
/// moves or a time budget expires, and it **skips** rather than fails when the
/// collector did not run in time. A test that cannot observe what it claims
/// says so; it never asserts on a coin flip.
///
/// The `maybeCreate` test at the bottom runs whether or not the library is
/// present: it is about the release-mode mechanism, not about native memory.
@Tags(['native'])
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart';

import '../support/host_library.dart';
import '../support/observers.dart';

/// Bytes with no other reason to appear in a diagnostic string.
final Uint8List _secretBytes = Uint8List.fromList(
  utf8.encode('unlikely-mnemonic-abandon-abandon-1234'),
);

/// The same bytes as lower-case hex, the other obvious way a buffer leaks into
/// a log.
String get _secretHex =>
    _secretBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Creates [count] handles over [_secretBytes] and drops every reference to
/// them.
///
/// Deliberately a separate function: a [NativeResource] is `Finalizable`, and a
/// local holding one is kept alive to the end of the scope that uses it. Only
/// once this returns can the handles it made become unreachable.
void _allocateUndisposed(NativeContext context, int count) {
  for (var i = 0; i < count; i++) {
    TWDataHandle.fromBytes(context, _secretBytes);
  }
}

/// Where the garbage below is parked for an instant.
///
/// A static field, so the allocations escape and the compiler cannot decide
/// they never happened.
Object? _garbageSink;

/// Allocates a couple of megabytes nobody keeps, to give the collector a reason
/// to run.
void _makeGarbage() {
  for (var i = 0; i < 32; i++) {
    _garbageSink = Uint8List(1 << 16)..[0] = i;
  }
  // Read, then dropped: a field only ever written to is one the compiler may
  // remove along with the allocations that fed it.
  if (_garbageSink != null) _garbageSink = null;
}

void main() {
  final skip = hostLibrarySkipReason();

  group('PRD §11.2 item 7 — LeakTracker', skip: skip, () {
    late CountingBindings bindings;
    late LeakTracker tracker;
    late NativeContext context;

    setUp(() {
      bindings = CountingBindings(DynamicLibrary.open(findHostLibrary()!));
      tracker = LeakTracker.maybeCreate()!;
      context = NativeContext(bindings, observer: tracker);
    });

    test('item 7 — live and disposed counts follow the handles through a '
        'scope', () {
      expect(tracker.report.live, 0);

      final kept = TWStringHandle.fromString(context, 'kept');
      runScope<void>(context, (scope) {
        scope.data(Uint8List.fromList([1, 2]));
        scope.string('inside');
        final report = tracker.report;
        expect(report.live, 3);
        expect(report.disposed, 0);
        expect(report.finalizedWithoutDispose, 0);
        expect(report.liveByType, {'TWStringHandle': 2, 'TWDataHandle': 1});
      });

      final afterScope = tracker.report;
      expect(afterScope.live, 1, reason: 'only the handle outside the scope');
      expect(afterScope.disposed, 2);
      expect(afterScope.liveByType, {'TWStringHandle': 1});

      kept.dispose();
      kept.dispose();
      final afterDispose = tracker.report;
      expect(afterDispose.live, 0);
      expect(
        afterDispose.disposed,
        3,
        reason: 'the second dispose() notifies nobody',
      );
      expect(afterDispose.leaks, isEmpty);
      expect(bindings.dataDeletes, 1);
      expect(bindings.stringDeletes, 2);
    });

    test('item 7 — a live handle is counted by type and is not a leak', () {
      final data = TWDataHandle.fromBytes(context, _secretBytes);

      final report = tracker.report;
      expect(report.live, 1);
      expect(report.liveByType, {'TWDataHandle': 1});
      expect(
        report.leaks,
        isEmpty,
        reason: 'a handle that is still reachable was not collected',
      );

      data.dispose();
      expect(tracker.report.leaks, isEmpty);
    });

    test('item 7 — the report renders counts, types and stack traces, and no '
        'buffer contents (TM-31)', () {
      final secret = utf8.decode(_secretBytes);
      final data = TWDataHandle.fromBytes(context, _secretBytes);
      final string = TWStringHandle.fromString(context, secret);

      final rendered = tracker.report.toString();

      expect(rendered, contains('TWDataHandle'));
      expect(rendered, contains('TWStringHandle'));
      expect(rendered, contains('live: 2'));
      expect(rendered, isNot(contains(secret)));
      expect(rendered, isNot(contains(_secretHex)));
      expect(rendered, isNot(contains(_secretBytes.toString())));
      // Nor the pointer: an address is not identity a diagnostic needs, and
      // printing one hands an attacker the heap layout.
      expect(rendered, isNot(contains(data.pointer.address.toString())));
      expect(rendered, isNot(contains(string.pointer.address.toString())));

      data.dispose();
      string.dispose();
    });

    test('item 7 — stop() freezes the report and stops all counting '
        '(DECISION-12 §5)', () {
      final before = TWDataHandle.fromBytes(context, Uint8List.fromList([1]));
      expect(tracker.report.live, 1);

      tracker.stop();
      final frozen = tracker.report;
      expect(tracker.isStopped, isTrue);
      expect(frozen.stopped, isTrue);
      expect(frozen.live, 1);

      // Everything after the stop is invisible: a handle created, one disposed,
      // and a second stop().
      before.dispose();
      final after = TWStringHandle.fromString(context, 'after');
      after.dispose();
      tracker.stop();

      final still = tracker.report;
      expect(still.live, 1, reason: 'the same snapshot, not a new count');
      expect(still.disposed, 0);
      expect(still.finalizedWithoutDispose, 0);
      expect(identical(still, frozen), isTrue);
      // The handles themselves are unaffected: stopping the observer does not
      // stop the disposal contract.
      expect(before.isDisposed, isTrue);
      expect(bindings.dataDeletes, 1);
      expect(bindings.stringDeletes, 1);
    });

    test(
      'item 7 — a handle collected without dispose() is reported as a leak '
      '(best effort: skips when the collector does not run in time)',
      () async {
        const budget = Duration(seconds: 5);
        const handles = 64;

        _allocateUndisposed(context, handles);
        expect(tracker.report.live, handles);

        final deadline = DateTime.now().add(budget);
        var report = tracker.report;
        while (report.finalizedWithoutDispose == 0 &&
            DateTime.now().isBefore(deadline)) {
          _makeGarbage();
          // A managed Finalizer's callback runs on the event loop, so the
          // count cannot move without yielding to it.
          await Future<void>.delayed(const Duration(milliseconds: 5));
          report = tracker.report;
        }

        if (report.finalizedWithoutDispose == 0) {
          // Never a failure: `NativeFinalizer` and `Finalizer` run "as early as
          // possible" after unreachability and are guaranteed only at
          // isolate-group shutdown (PRD §11.1 [VERIFIED]). Nothing in Dart can
          // force a collection, so not observing one proves nothing.
          markTestSkipped(
            'the collector did not run within ${budget.inSeconds}s, so the '
            'finalized-without-dispose path could not be observed. This is a '
            'timing limitation of the runtime, not a failure of the tracker.',
          );
          return;
        }

        expect(report.finalizedWithoutDispose, lessThanOrEqualTo(handles));
        expect(report.leaks, hasLength(report.finalizedWithoutDispose));
        expect(report.live, handles - report.finalizedWithoutDispose);
        expect(report.disposed, 0);

        final leak = report.leaks.first;
        expect(leak.resourceType, 'TWDataHandle');
        expect(leak.isFinalizedWithoutDispose, isTrue);
        expect(leak.isDisposed, isFalse);
        expect(leak.resource, isNull, reason: 'the record held it weakly');
        expect(
          leak.allocationStackTrace.toString(),
          contains('_allocateUndisposed'),
          reason: 'the record names the site that forgot to dispose (TM-11)',
        );

        // The leak report is the one place a stack trace is rendered; it still
        // carries no contents (TM-31).
        final rendered = report.toString();
        expect(rendered, contains('finalized without dispose'));
        expect(rendered, isNot(contains(utf8.decode(_secretBytes))));
        expect(rendered, isNot(contains(_secretHex)));
      },
    );
  });

  test('item 7 — maybeCreate() returns a tracker where assertions are on, '
      'which is what compiles it out of a release build (TM-30)', () {
    // `dart test` runs with assertions enabled, so the construction inside the
    // assert in `maybeCreate` happens and this is non-null. In a release build
    // the assert — and with it the only reachable call to the private
    // constructor — is removed, `maybeCreate` returns null, and the class is
    // tree-shaken. Proving *that* needs a compiled release-mode program and
    // belongs to T1.17, which owns the release-mode CI gate.
    var assertionsEnabled = false;
    assert(() {
      assertionsEnabled = true;
      return true;
    }());

    expect(
      assertionsEnabled,
      isTrue,
      reason: 'this test is only meaningful with assertions on',
    );
    expect(LeakTracker.maybeCreate(), isNotNull);
    expect(LeakTracker.maybeCreate(), isA<ResourceObserver>());
    expect(
      LeakTracker.maybeCreate(),
      isNot(same(LeakTracker.maybeCreate())),
      reason: 'each call makes its own tracker; there is no global',
    );
    expect(LeakTracker.maybeCreate()!.report.live, 0);
    expect(LeakTracker.maybeCreate()!.isStopped, isFalse);
  });
}
