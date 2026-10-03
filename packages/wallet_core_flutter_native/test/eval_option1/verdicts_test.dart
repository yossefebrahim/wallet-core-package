// The shell side of eval/option1/run_eval.sh's verdicts (tool/verdicts.sh),
// driven through /bin/sh with `row` and `harness` stubbed to print what they
// were asked to write or measure. Each group reproduces a finding of the
// T1.8a-d4 review against the script it fixed.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final String _verdicts = File(
  '${Directory.current.path}/../../eval/option1/tool/verdicts.sh',
).absolute.path;

/// Sources verdicts.sh, stubs its collaborators, runs [body]; returns stdout
/// lines. `row` prints `ROW <args>`, `harness` prints `HARNESS <args>`.
Future<List<String>> _sh(String body) async {
  final result = await Process.run('sh', [
    '-c',
    'set -eu; . "\$0"; '
        'row() { printf "ROW %s\\n" "\$*"; }; '
        'harness() { printf "HARNESS %s\\n" "\$*"; }; '
        'ORCH=orch-note; NOART=noart-note; $body',
    _verdicts,
  ]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return (result.stdout as String).trim().split('\n');
}

final String _eval = File(
  '${Directory.current.path}/../../eval/option1',
).absolute.path;

/// Runs `pristine_check DIR WHEN` in a subshell; returns (exit code, stderr).
Future<(int, String)> _pristine(String dir) async {
  final result = await Process.run('sh', [
    '-c',
    '. "\$0"; pristine_check "\$1" test',
    _verdicts,
    dir,
  ]);
  return (result.exitCode, result.stderr as String);
}

/// Copies directory [from] into [to], recursively.
void _copy(Directory from, Directory to) {
  to.createSync(recursive: true);
  for (final e in from.listSync(followLinks: false)) {
    final name = e.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (e is Directory) _copy(e, Directory('${to.path}/$name'));
    if (e is File) e.copySync('${to.path}/$name');
  }
}

void main() {
  test('verdicts.sh and run_eval.sh parse as POSIX sh', () async {
    for (final script in [_verdicts, '$_eval/run_eval.sh']) {
      final result = await Process.run('sh', ['-n', script]);
      expect(result.exitCode, 0, reason: '$script: ${result.stderr}');
    }
  });

  // T1.8a delta 5: the orchestrator's run ended with
  // "consumer/ios/Podfile exists … (after the run)". The in-place host
  // `flutter test` ran `flutter pub get` inside the checked-in consumer, whose
  // plugin injection copies Flutter's Podfile template into ios/ and adds
  // `#include? "Pods/…"` to the xcconfigs (reproduced with
  // `flutter pub get --offline` in a staged copy).
  group('the checked-in consumer is never run in (delta 5)', () {
    test('run_eval.sh only reads it: stage, deployment targets, guard', () {
      final script = File('$_eval/run_eval.sh').readAsLinesSync();
      final uses = [
        for (final (i, line) in script.indexed)
          if (RegExp(r'\$APP\b|\$\{APP\}').hasMatch(line) &&
              !line.trimLeft().startsWith('#'))
            (i + 1, line.trim()),
      ];
      final allowed = [
        RegExp(r'^tool stage "\$APP" '),
        RegExp(r'^pristine_check "\$APP" '),
        RegExp(r'^[A-Z_]+=\$\(template_target [A-Z_]+ "\$APP/'),
      ];
      expect(uses, isNotEmpty);
      for (final (line, text) in uses) {
        expect(
          allowed.any((p) => p.hasMatch(text)),
          isTrue,
          reason: 'run_eval.sh:$line uses the consumer directory: $text',
        );
      }
      // Both guards are there: before anything runs, and after the render.
      expect(
        script.where((l) => l.startsWith('pristine_check "\$APP" ')),
        hasLength(2),
      );
    });

    test('the consumer as committed passes the guard', () async {
      final (code, err) = await _pristine('$_eval/consumer');
      expect(code, 0, reason: err);
    });

    group('what flutter pub get leaves behind fails it', () {
      late Directory app;
      setUp(() async {
        app = await Directory.systemTemp.createTemp('wcf-eval-pristine');
        for (final d in ['ios', 'macos']) {
          _copy(Directory('$_eval/consumer/$d'), Directory('${app.path}/$d'));
        }
      });
      tearDown(() => app.deleteSync(recursive: true));

      test('a copy of the consumer passes', () async {
        expect((await _pristine(app.path)).$1, 0);
      });

      test('Podfile + xcconfig include (the delta-5 state)', () async {
        File('${app.path}/ios/Podfile').writeAsStringSync(
          "# Uncomment this line to define a global platform for your project\n"
          "# platform :ios, '13.0'\n",
        );
        final debug = File('${app.path}/ios/Flutter/Debug.xcconfig');
        debug.writeAsStringSync(
          '#include? "Pods/Target Support Files/Pods-Runner/'
          'Pods-Runner.debug.xcconfig"\n${debug.readAsStringSync()}',
        );
        final (code, err) = await _pristine(app.path);
        expect(code, 1);
        expect(err, contains('ios/Podfile exists'));
      });

      test('the xcconfig include alone', () async {
        final release = File('${app.path}/ios/Flutter/Release.xcconfig');
        release.writeAsStringSync(
          '#include? "Pods/Target Support Files/Pods-Runner/'
          'Pods-Runner.release.xcconfig"\n${release.readAsStringSync()}',
        );
        final (code, err) = await _pristine(app.path);
        expect(code, 1);
        expect(err, contains('Release.xcconfig references CocoaPods'));
      });

      test('the macOS plugin registrant pub get writes', () async {
        File(
          '${app.path}/macos/Flutter/GeneratedPluginRegistrant.swift',
        ).writeAsStringSync('//\n');
        expect((await _pristine(app.path)).$1, 1);
      });
    });
  });

  // Finding 4: when the archive build was refused or failed, the pre-fix
  // script measured whatever an earlier run had left at
  // consumer/build/ios/archive and recorded it as `pass`.
  group('packaged: only this run\'s build is measured (finding 4)', () {
    late Directory dir;
    late String stale;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('wcf-eval-stale');
      // An earlier run's framework, still on disk.
      stale =
          '${dir.path}/build/ios/archive/Runner.xcarchive/Products/'
          'Applications/Runner.app/Frameworks/TrustWalletCore.framework/'
          'TrustWalletCore';
      File(stale)
        ..createSync(recursive: true)
        ..writeAsStringSync('stale');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    for (final (rc, summary) in [
      (10, 'refused here'),
      (1, 'not built in this run'),
      (20, 'no artifact'),
    ]) {
      test('build exit $rc: the stale file is not measured', () async {
        final out = await _sh(
          'packaged $rc "$stale" ios-device-arm64/release macho',
        );
        expect(out.where((l) => l.startsWith('HARNESS')), isEmpty);
        expect(out, hasLength(2));
        for (final line in out) {
          expect(line, startsWith('ROW --check '));
          expect(line, contains('--target ios-device-arm64/release'));
          expect(line, contains('--status unmeasured'));
          expect(line, contains('--summary $summary'));
        }
        expect(out.first, contains('--check symbols'));
        expect(out.last, contains('--check size'));
      });
    }

    test('build exit 0: measured', () async {
      final out = await _sh(
        'packaged 0 "$stale" ios-device-arm64/release macho',
      );
      expect(out, [
        'HARNESS symbols --artifact $stale --format macho '
            '--target ios-device-arm64/release',
        'HARNESS size --artifact $stale --target ios-device-arm64/release',
      ]);
    });
  });

  // Finding 11: the pre-fix script wrote `pass offline: built` for any
  // successful build, though every build ran in the checkout with the
  // hook's cache already holding the artifact.
  group('offline_verdict: pass only for a clean offline install '
      '(finding 11)', () {
    Future<(String, String)> verdict(int rc, String pre, String post) async {
      final out = await _sh(
        'offline_verdict $rc "\$(printf "$pre")" "\$(printf "$post")"; '
        'printf "%s|%s\\n" "\$OFF_STATUS" "\$OFF_SUMMARY"',
      );
      final [status, summary] = out.single.split('|');
      return (status, summary);
    }

    const vendored =
        r'vendored\t1 requested: 0 already verified in the cache, 0 '
        r'downloaded, 1 from --vendored, 0 failed; bundled … offline).';
    const cache =
        r'cache\t1 requested: 1 already verified in the cache, 0 '
        r'downloaded, 0 from --vendored, 0 failed; bundled … offline).';

    test('the reviewer\'s scenario: built, from a warm cache', () async {
      final (status, summary) = await verdict(0, r'none\t', cache);
      expect(status, 'unmeasured');
      expect(summary, contains('cache'));
    });

    test('a cache that was not empty before the build', () async {
      final (status, _) = await verdict(
        0,
        r'warm-cache\tios/arm64/libTrustWalletCore.dylib is in the hook cache',
        vendored,
      );
      expect(status, 'unmeasured');
    });

    test('empty before, vendored copy after: pass', () async {
      final (status, summary) = await verdict(0, r'none\t', vendored);
      expect(status, 'pass');
      expect(summary, 'offline: built from vendored_dir, empty cache');
    });

    test('a download despite offline: fail', () async {
      final (status, _) = await verdict(
        0,
        r'none\t',
        r'downloaded\t1 requested: 0 already verified in the cache, 1 '
            r'downloaded, 0 from --vendored, 0 failed',
      );
      expect(status, 'fail');
    });

    test('refused or failed builds say so, never pass', () async {
      expect((await verdict(10, r'none\t', r'none\t')).$1, 'unmeasured');
      expect((await verdict(1, r'none\t', vendored)).$1, 'unmeasured');
    });
  });
}
