// The verdicts eval/option1/run_eval.sh writes into the DECISION-2 Option 1
// results: which outcome counts as a wrong-digest failure, as a clean offline
// install, what gets scanned for duplicate symbols, what a committed row may
// contain, and how the decision document's table is re-embedded. Each group
// reproduces a finding of the T1.8a-d4 review against the code it fixed.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.
//
// Evaluation branch only, like hook/: eval/option1/tool/eval_tool.dart is a
// script outside any package, imported here so `melos run test` and
// `melos run analyze` cover it.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../../eval/option1/tool/eval_tool.dart' hide main;
import '../../hook/src/acquire.dart';
import '../../tool/src/asset_names.dart' as names;
import '../hook/fixtures.dart';

void main() {
  const sim = 'ios-simulator/arm64_x86_64/libTrustWalletCore.dylib';
  const mac = 'macos/arm64_x86_64/libTrustWalletCore.dylib';

  /// What an Xcode build keeps of a failed build phase: its `error:` lines,
  /// as Flutter prints them (DECISION-2-option1.md §3, measured).
  List<String> xcodeKeeps(String hookMessage) => [
    'Failed to build iOS app',
    for (final line in const LineSplitter().convert(hookMessage))
      if (line.trimLeft().startsWith('error: '))
        'Error (Xcode): ${line.trimLeft().substring('error: '.length)}',
    'Error (Xcode): $sim could not be verified; stopping. Pass --keep-going '
        'to report the rest first (the exit code stays non-zero).',
    'Encountered error while building for simulator.',
  ];

  group('classify-negative (finding 3)', () {
    late Directory dir;
    final artifact = fatMachO([
      thinMachO(cpuX86_64, length: 128),
      thinMachO(cpuArm64, length: 160),
    ]);
    final flipped = flipDigest(sha256Hex(artifact));

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('wcf-eval-negative');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    /// The real hook failure text for [sim] against a manifest whose digest
    /// is flipped, through the real fetch tool.
    Future<String> hookFailure({required bool vendoredExists}) async {
      if (vendoredExists) {
        writeVendored(Directory('${dir.path}/vendored'), {sim: artifact});
      }
      final manifest = '${dir.path}/flipped.json';
      File(manifest).writeAsStringSync(
        manifestFor({sim: artifact}, digestOverrides: {sim: flipped}),
      );
      try {
        await acquireArtifact(
          AcquireRequest(
            logicalName: sim,
            manifestPath: manifest,
            cacheDir: '${dir.path}/cache',
            toolDir: '${Directory.current.path}/tool',
            sha256: flipped,
            size: artifact.length,
            vendoredDir: '${dir.path}/vendored',
            offline: true,
          ),
          cachePathFor: names.cachePathFor,
        );
      } on AcquireError catch (e) {
        return e.message;
      }
      fail('the flipped-digest acquisition succeeded');
    }

    test('the reviewer\'s scenario: a vendored_dir that does not resolve '
        'fails offline, and that is not a wrong-digest pass', () async {
      final log = xcodeKeeps(await hookFailure(vendoredExists: false));
      // The generic headline the pre-fix classifier accepted is there…
      expect(log.join('\n'), contains('could not be verified'));
      // …and it is not evidence of the digest.
      final verdict = classifyNegative(
        log,
        logicalName: sim,
        expectedSha256: flipped,
      );
      expect(verdict, startsWith('other\t'));
    });

    test('a real flipped digest, as Xcode keeps it: digest-mismatch', () async {
      final log = xcodeKeeps(await hookFailure(vendoredExists: true));
      final verdict = classifyNegative(
        log,
        logicalName: sim,
        expectedSha256: flipped,
      );
      expect(verdict, startsWith('digest-mismatch\t'));
      expect(verdict, contains('expected $flipped'));
      expect(verdict, contains('found ${sha256Hex(artifact)}'));
    });

    test('the whole message (host flutter test): digest-mismatch', () async {
      final message = await hookFailure(vendoredExists: true);
      expect(
        classifyNegative(
          const LineSplitter().convert(message),
          logicalName: sim,
          expectedSha256: flipped,
        ),
        startsWith('digest-mismatch\t'),
      );
    });

    test('the fetch tool\'s expected/found lines alone are not enough', () {
      expect(
        classifyNegative(
          [
            'failed    $sim',
            '          expected sha256 $flipped size 10',
            '          found    sha256 ${'b' * 64} size 10',
          ],
          logicalName: sim,
          expectedSha256: flipped,
        ),
        startsWith('other\t'),
      );
    });

    test('a mismatch of another artifact or another digest is not this '
        'check', () {
      String line(String name, String expected) =>
          'Error (Xcode): wallet_core_flutter_native: $name: sha256 mismatch: '
          'expected $expected (10 bytes), found ${'b' * 64} (10 bytes) from '
          'vendored /v; nothing was bundled';
      expect(
        classifyNegative(
          [line(mac, flipped)],
          logicalName: sim,
          expectedSha256: flipped,
        ),
        startsWith('other\t'),
      );
      expect(
        classifyNegative(
          [line(sim, 'c' * 64)],
          logicalName: sim,
          expectedSha256: flipped,
        ),
        startsWith('other\t'),
      );
    });

    test('a cache file replaced after verification is still the digest', () {
      // acquire.dart's second check (finding 1) uses the same one-line form.
      expect(
        classifyNegative(
          [
            'error: wallet_core_flutter_native: $sim: sha256 mismatch: '
                'expected $flipped (10 bytes), found ${'b' * 64} (10 bytes) '
                'from cache file /c read after verification; nothing was '
                'bundled',
          ],
          logicalName: sim,
          expectedSha256: flipped,
        ),
        startsWith('digest-mismatch\t'),
      );
    });
  });

  group('offline-evidence (finding 11)', () {
    // The text hooks_runner keeps in .dart_tool/hooks_runner/
    // wallet_core_flutter_native/<config>/stdout.txt (shape copied from the
    // consumer's own, paths shortened).
    String hookLog({
      int cache = 0,
      int downloaded = 0,
      int vendored = 0,
      int failed = 0,
      String name = sim,
      bool offline = true,
    }) =>
        'Running `(cd /pkg/; … hook.dill --config=…/input.json )`.\n'
        'wallet_core_flutter_native: \n'
        'wallet_core_flutter_native: 1 requested: $cache already verified in '
        'the cache, $downloaded downloaded, $vendored from --vendored, '
        '$failed failed — cache /app/.dart_tool/hooks_runner/shared/'
        'wallet_core_flutter_native/build/artifacts/\n'
        '\n'
        'wallet_core_flutter_native: bundled $name for iOS iphonesimulator '
        'arm64 (19860520 of 41225256 bytes, sha256 ${'6' * 64} verified in '
        'memory against /eval_manifest.json, a manifest override'
        '${offline ? ', offline' : ''}).\n';

    test('the reviewer\'s scenario: a warm cache is not a clean offline '
        'install', () {
      // What the in-place consumer's hook logs said on the run the pre-fix
      // script recorded as "pass offline: built".
      expect(
        offlineEvidence([hookLog(cache: 1)], sim, cacheHasArtifact: true),
        startsWith('cache\t'),
      );
    });

    test('the vendored copy, offline, nothing else: vendored', () {
      final verdict = offlineEvidence(
        [hookLog(cache: 1, name: mac), hookLog(vendored: 1)],
        sim,
        cacheHasArtifact: true,
      );
      expect(verdict, startsWith('vendored\t'));
      expect(verdict, contains('1 from --vendored'));
    });

    test('a second architecture that found the first one\'s copy does not '
        'hide the vendored run', () {
      expect(
        offlineEvidence(
          [hookLog(cache: 1), hookLog(vendored: 1)],
          sim,
          cacheHasArtifact: true,
        ),
        startsWith('vendored\t'),
      );
    });

    test('vendored without offline, or downloaded, is not the clean offline '
        'path', () {
      expect(
        offlineEvidence(
          [hookLog(vendored: 1, offline: false)],
          sim,
          cacheHasArtifact: true,
        ),
        isNot(startsWith('vendored\t')),
      );
      expect(
        offlineEvidence([hookLog(downloaded: 1)], sim, cacheHasArtifact: true),
        startsWith('downloaded\t'),
      );
    });

    test('before the build: none only when nothing is cached or logged', () {
      expect(offlineEvidence(const [], sim, cacheHasArtifact: false), 'none\t');
      expect(
        offlineEvidence(const [], sim, cacheHasArtifact: true),
        startsWith('warm-cache\t'),
      );
      expect(
        offlineEvidence(
          [hookLog(vendored: 1, name: mac)],
          sim,
          cacheHasArtifact: false,
        ),
        'none\t',
      );
    });
  });

  group('embedded-binaries (finding 12)', () {
    late Directory app;
    setUp(() async {
      app = await Directory.systemTemp.createTemp('wcf-eval-app');
    });
    tearDown(() => app.deleteSync(recursive: true));

    test('every embedded framework, not TrustWalletCore and Flutter only', () {
      // The five frameworks a debug Option 1 app with integration_test
      // embeds.
      for (final name in [
        'App',
        'Flutter',
        'TrustWalletCore',
        'integration_test',
        'objective_c',
      ]) {
        File('${app.path}/Frameworks/$name.framework/$name')
          ..createSync(recursive: true)
          ..writeAsStringSync('x');
      }
      File('${app.path}/Frameworks/libextra.dylib').writeAsStringSync('x');
      Directory('${app.path}/Frameworks/Empty.framework').createSync();
      expect(
        embeddedBinaries(app.path).map((p) => p.substring(app.path.length + 1)),
        [
          'Frameworks/App.framework/App',
          'Frameworks/Flutter.framework/Flutter',
          'Frameworks/TrustWalletCore.framework/TrustWalletCore',
          'Frameworks/integration_test.framework/integration_test',
          'Frameworks/libextra.dylib',
          'Frameworks/objective_c.framework/objective_c',
        ],
      );
    });

    test('a macOS bundle: Contents/Frameworks', () {
      File(
          '${app.path}/Contents/Frameworks/FlutterMacOS.framework/FlutterMacOS',
        )
        ..createSync(recursive: true)
        ..writeAsStringSync('x');
      expect(embeddedBinaries(app.path), hasLength(1));
    });

    test('no app (not built): nothing to scan', () {
      expect(embeddedBinaries('${app.path}/missing.app'), isEmpty);
    });
  });

  group('relativize (finding 14)', () {
    const home = '/Users/someone';
    const repo = '$home/Work/wallet-core-package.worktrees/T1.8';
    const tmp = '/var/folders/xy/abc/T';
    final local = relativizer(repo: repo, tmp: tmp, home: home);

    test('a harness-written row loses every home path', () {
      // The shape tools/packaging_eval writes: absolute paths in command,
      // notes and values.
      final row = jsonEncode({
        'check': 'alignment',
        'target': 'ndk/arm64-v8a',
        'status': 'pass',
        'values': {
          'summary': '4 LOAD @ 0x4000',
          'binary':
              '$home/Library/Android/sdk/ndk/28.2.13676358/toolchains/'
              'llvm/prebuilt/darwin-x86_64/sysroot/usr/lib/'
              'aarch64-linux-android/libc++_shared.so',
          'count': 4,
        },
        'command':
            'dart run tools/packaging_eval/bin/size.dart --artifact '
            '$repo/third_party/wcf-native-all/artifacts/ios/arm64/'
            'libTrustWalletCore.dylib',
        'notes': 'flutter at $home/flutter; scratch /private$tmp/o1/app',
      });
      final [out] = relativizeRows([row, ''], local);
      expect(out, isNot(contains(home)));
      expect(out, isNot(contains('/Users/')));
      final decoded = jsonDecode(out) as Map<String, Object?>;
      expect(
        decoded['command'],
        'dart run tools/packaging_eval/bin/size.dart --artifact '
        'third_party/wcf-native-all/artifacts/ios/arm64/'
        'libTrustWalletCore.dylib',
      );
      expect(decoded['notes'], r'flutter at ~/flutter; scratch $TMPDIR/o1/app');
      expect(
        (decoded['values']! as Map)['binary'],
        startsWith('~/Library/Android/sdk/ndk/'),
      );
      expect((decoded['values']! as Map)['count'], 4);
    });

    test('a path that only shares a prefix is left alone', () {
      expect(local('$home-other/x'), '$home-other/x');
    });
  });

  group('embed-table (finding 5)', () {
    const doc =
        'intro\n<!-- counts:begin -->\nstale\n<!-- counts:end -->\n'
        'middle\n<!-- table:begin -->\n| old |\n<!-- table:end -->\nend\n';
    const table =
        '# title\n\nprose\n\n'
        '| step | a | b |\n'
        '|---|---|---|\n'
        '| 1. x (`c`, h) | pass ok (p | q) [1] | — |\n'
        '| 2. y | — | unmeasured [2] |\n'
        '\n## Commands\n\n[1] `cmd`\n';
    final results = [
      jsonEncode({'status': 'pass'}),
      jsonEncode({'status': 'unmeasured'}),
      jsonEncode({'status': 'pass'}),
      '',
    ];

    test('the table is the rendered one, in-cell pipes escaped', () {
      final out = embedTable(doc: doc, table: table, results: results);
      expect(
        out,
        'intro\n<!-- counts:begin -->\n'
        '3 rows: 2 pass, 0 fail, 0 skip, 1 unmeasured.\n'
        '<!-- counts:end -->\n'
        'middle\n<!-- table:begin -->\n'
        '| step | a | b |\n'
        '|---|---|---|\n'
        '| 1. x (`c`, h) | pass ok (p \\| q) [1] | — |\n'
        '| 2. y | — | unmeasured [2] |\n'
        '<!-- table:end -->\nend\n',
      );
    });

    test('a row that does not fit the header fails, not mangles', () {
      expect(
        () => embedTable(
          doc: doc,
          table: table.replaceFirst('| — | unmeasured [2] |', '| — |'),
          results: results,
        ),
        throwsFormatException,
      );
    });

    test('a document without the markers fails', () {
      expect(
        () => embedTable(doc: 'no markers', table: table, results: results),
        throwsFormatException,
      );
    });
  });
}
