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
import 'dart:typed_data';

final List<Object> _retained = <Object>[];

/// Where the small garbage is parked for an instant, so the allocations escape
/// and the compiler cannot decide they never happened.
Object? _sink;

/// One round of pressure: 64 MiB held and then dropped, plus some small
/// objects.
void applyGcPressure() {
  for (var i = 0; i < 8; i++) {
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

/// Applies pressure and yields until [done] is true or [budget] runs out;
/// returns whether [done] became true.
Future<bool> pumpUntil(
  bool Function() done, {
  Duration budget = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(budget);
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) return false;
    applyGcPressure();
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  return true;
}
