/// Making the collector run, for the tests that observe a finalizer.
///
/// Dart gives no way to force a collection, and a finalizer runs "as early as
/// possible" after its object is unreachable (PRD §11.1 [VERIFIED]). Small
/// short-lived garbage can leave the collector idle for seconds; what reliably
/// moves it is **retained-then-dropped multi-megabyte buffers**, which grow the
/// heap's external size past its threshold and then leave a lot of it dead.
/// [applyGcPressure] does that, and [pumpUntil] repeats it, yielding to the
/// event loop between rounds because a managed `Finalizer`'s callback runs
/// there.
///
/// A test using this must **fail**, not skip, when the budget runs out: a
/// finalizer that never ran is the thing under test.
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

final List<Object> _retained = <Object>[];

/// Where the small garbage is parked for an instant, so the allocations escape
/// and the compiler cannot decide they never happened.
Object? _sink;

/// One round of pressure: [megabuffers] buffers of 8 MiB held and then
/// dropped, plus some small objects.
void applyGcPressure({int megabuffers = 8}) {
  for (var i = 0; i < megabuffers; i++) {
    _retained.add(Uint8List(8 << 20)..[0] = i);
  }
  _retained.clear();
  for (var i = 0; i < 64; i++) {
    _sink = <int>[for (var j = 0; j < 4096; j++) j];
  }
  // Read, then dropped: a field only ever written to is one the compiler may
  // remove along with the allocations that fed it.
  if (_sink != null) _sink = null;
}

/// How the last [pumpUntil] went, for a failure message: how many rounds of
/// pressure it applied and how long it took.
String lastPumpSummary = 'no pump yet';

/// The most time a test waits for a collection. A finalizer runs "as early as
/// possible", not at a bound; on a machine busy with other suites a collection
/// that takes a second alone can take far longer, so the budget is generous and
/// only an absent collection ever spends it. A test that waits on it declares a
/// `timeout:` above this.
const Duration gcBudget = Duration(minutes: 2);

/// Applies pressure and yields until [done] is true or [budget] runs out;
/// returns whether [done] became true.
///
/// The pressure escalates: every 20 rounds without success the buffers per
/// round grow by 4 (8 MiB each, up to 24), because a run that has not seen its
/// collection by then is on a loaded machine or has a large young generation,
/// and more dead external memory is what moves the collector. Between rounds
/// the event loop is yielded to twice: a managed `Finalizer`'s callback runs
/// there.
Future<bool> pumpUntil(
  bool Function() done, {
  Duration budget = gcBudget,
}) async {
  final watch = Stopwatch()..start();
  var rounds = 0;
  try {
    while (!done()) {
      if (watch.elapsed > budget) return false;
      applyGcPressure(megabuffers: 8 + 4 * min(rounds ~/ 20, 4));
      rounds++;
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return true;
  } finally {
    lastPumpSummary =
        '$rounds rounds of pressure, ${watch.elapsedMilliseconds} ms';
  }
}
