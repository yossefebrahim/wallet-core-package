/// Release-mode inertness of the leak tracker (PRD §16 S8 [REQ], threat model
/// TM-30): in a program compiled ahead of time with assertions off,
/// `LeakTracker.maybeCreate()` builds nothing.
///
/// `dart test` runs with assertions on, so the tests in `leak_tracker_test.dart`
/// can only prove the debug side. This one compiles
/// `../support/leak_tracker_release_probe_main.dart` with `dart compile exe`
/// (AOT; assertions are off unless asked for) and runs the binary. A control
/// compiles the same program with `--enable-asserts` and must see the tracker
/// built, which shows the probe can tell the two apart.
///
/// The binaries are written to a temporary directory and removed afterwards;
/// nothing is written into the tree. No native library is needed.
@Tags(['aot'])
@TestOn('vm')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

/// Compiles the probe into [out] and returns the compiler's result.
Future<ProcessResult> _compile({
  required String config,
  required String out,
  bool enableAsserts = false,
}) {
  final script =
      '${Directory.current.path}/test/support/'
      'leak_tracker_release_probe_main.dart';
  return Process.run(Platform.resolvedExecutable, [
    'compile',
    'exe',
    '--packages=$config',
    if (enableAsserts) '--enable-asserts',
    '-o',
    out,
    script,
  ]);
}

void main() {
  late Directory temp;
  late String config;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('wcf_leak_tracker_aot_');
    final uri = await Isolate.packageConfig;
    expect(uri, isNotNull, reason: 'no package config for this test isolate');
    config = uri!.toFilePath();
  });

  tearDownAll(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  test('item 7 / TM-30 — in an AOT release build, maybeCreate() returns null '
      'and builds no tracker', () async {
    final out = '${temp.path}/release_probe';
    final compiled = await _compile(config: config, out: out);
    expect(
      compiled.exitCode,
      0,
      reason:
          'dart compile exe failed:\n${compiled.stdout}\n${compiled.stderr}',
    );

    final run = await Process.run(out, const []);

    expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
    expect((run.stdout as String).trim(), 'LeakTracker.maybeCreate() -> null');
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('control: the same program compiled with --enable-asserts does build '
      'a tracker', () async {
    final out = '${temp.path}/asserts_probe';
    final compiled = await _compile(
      config: config,
      out: out,
      enableAsserts: true,
    );
    expect(
      compiled.exitCode,
      0,
      reason:
          'dart compile exe failed:\n${compiled.stdout}\n${compiled.stderr}',
    );

    final run = await Process.run(out, const []);

    expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
    expect(
      (run.stdout as String).trim(),
      'LeakTracker.maybeCreate() -> ACTIVE',
      reason: 'without this the null above proves nothing',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
