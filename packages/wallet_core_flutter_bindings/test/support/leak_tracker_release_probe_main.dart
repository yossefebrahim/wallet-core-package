/// The program `test/memory/leak_tracker_release_aot_test.dart` compiles with
/// `dart compile exe` and runs: it reports whether `LeakTracker.maybeCreate()`
/// builds a tracker. Not a test itself: the file name does not end in
/// `_test.dart`.
library;

import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart';

void main() {
  final tracker = LeakTracker.maybeCreate();
  // ignore: avoid_print
  print('LeakTracker.maybeCreate() -> ${tracker == null ? 'null' : 'ACTIVE'}');
}
