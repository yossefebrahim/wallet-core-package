/// Waiting for something that happens "in a later timer turn" without guessing
/// how long a turn takes.
///
/// A fixed `Future.delayed(10 ms)` before an assertion is a bet that the event
/// loop gets through every pending turn in 10 ms. It wins on an idle machine and
/// loses on one running other suites at the same time (T1.R2a-d1). [eventually]
/// polls instead: it returns as soon as the condition holds, and gives up — so
/// the assertion after it fails, with its own message — only after [timeout].
library;

import 'dart:async';

/// Polls [condition] every [interval] until it is true or [timeout] passes;
/// returns whether it became true.
Future<bool> eventually(
  bool Function() condition, {
  Duration interval = const Duration(milliseconds: 5),
  Duration timeout = const Duration(seconds: 10),
}) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > timeout) return false;
    await Future<void>.delayed(interval);
  }
  return true;
}
