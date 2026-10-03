// Locating the committed fixtures from a test.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.

import 'dart:io';

/// `tools/packaging_eval/fixtures/`, found by walking up from the test file.
Directory fixturesDirectory() {
  for (
    var dir = Directory.current.absolute;
    dir.path != dir.parent.path;
    dir = dir.parent
  ) {
    final candidate = Directory('${dir.path}/tools/packaging_eval/fixtures');
    if (candidate.existsSync()) return candidate;
    final local = Directory('${dir.path}/fixtures');
    if (local.existsSync() &&
        File('${dir.path}/pubspec.yaml').existsSync() &&
        File(
          '${dir.path}/pubspec.yaml',
        ).readAsStringSync().contains('wcf_tool_packaging_eval')) {
      return local;
    }
  }
  throw StateError('could not locate tools/packaging_eval/fixtures');
}

String toolOutput(String name) =>
    File('${fixturesDirectory().path}/tool_output/$name').readAsStringSync();
