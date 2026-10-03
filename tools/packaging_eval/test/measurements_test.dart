// The measurement entry points: the pure ones against values, the real ones
// against the artifacts this machine has, skipping when it does not have them.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wcf_tool_packaging_eval/host.dart';
import 'package:wcf_tool_packaging_eval/measurements.dart';
import 'package:wcf_tool_packaging_eval/results.dart';

/// The relinked artifact set T1.2 built here; git-ignored, so absent on a
/// fresh clone.
String artifactPath(String logicalName) =>
    '${repoRoot().path}/third_party/wcf-native-all/artifacts/$logicalName';

void main() {
  group('humanBytes', () {
    test('bytes below a KiB stay bytes', () {
      expect(humanBytes(0), '0 B');
      expect(humanBytes(1023), '1023 B');
    });

    test('scales to KiB, MiB and GiB with two decimals', () {
      expect(humanBytes(1024), '1.00 KiB');
      expect(humanBytes(1536), '1.50 KiB');
      expect(humanBytes(19721208), '18.81 MiB');
      expect(humanBytes(1024 * 1024 * 1024), '1.00 GiB');
    });

    test('stops at GiB rather than inventing a larger unit', () {
      expect(humanBytes(4096 * 1024 * 1024), '4.00 GiB');
    });
  });

  group('bundleSize', () {
    late Directory scratch;
    setUp(() => scratch = scratchDirectory('wcf-bundle-test-'));
    tearDown(() {
      if (scratch.existsSync()) scratch.deleteSync(recursive: true);
    });

    test('sums a directory tree and measures a plain file', () {
      final bundle = Directory('${scratch.path}/Runner.app/Frameworks')
        ..createSync(recursive: true);
      File('${bundle.path}/a.dylib').writeAsBytesSync(List<int>.filled(100, 1));
      File(
        '${scratch.path}/Runner.app/Info.plist',
      ).writeAsBytesSync(List<int>.filled(23, 1));
      expect(bundleSize('${scratch.path}/Runner.app'), 123);

      final apk = File('${scratch.path}/app.apk')
        ..writeAsBytesSync(List<int>.filled(500, 1));
      expect(bundleSize(apk.path), 500);
    });

    test('a path that does not exist measures nothing', () {
      expect(bundleSize('${scratch.path}/absent'), isNull);
    });
  });

  group('measureAppSizeDelta', () {
    late Directory scratch;
    setUp(() => scratch = scratchDirectory('wcf-delta-test-'));
    tearDown(() {
      if (scratch.existsSync()) scratch.deleteSync(recursive: true);
    });

    test('differences two bundles', () {
      final baseline = File('${scratch.path}/base.apk')
        ..writeAsBytesSync(List<int>.filled(1024, 1));
      final withSdk = File('${scratch.path}/sdk.apk')
        ..writeAsBytesSync(List<int>.filled(3072, 1));
      final rows = measureAppSizeDelta(
        baselineApp: baseline.path,
        sdkApp: withSdk.path,
        target: 'android/arm64-v8a release',
      );
      expect(rows.single.status, CheckStatus.pass);
      expect(rows.single.values['delta_bytes'], 2048);
      expect(rows.single.values['summary'], startsWith('+2.00 KiB'));
    });

    test('an app that has not been built is unmeasured with its command', () {
      final rows = measureAppSizeDelta(
        baselineApp: '${scratch.path}/base.apk',
        sdkApp: '${scratch.path}/sdk.apk',
        target: 'android/arm64-v8a release',
      );
      expect(rows.single.status, CheckStatus.unmeasured);
      expect(rows.single.command, contains('du -sb'));
      expect(rows.single.notes, contains('no baseline app'));
    });
  });

  group('exportedTwFunctions', () {
    test('projects the 464 exported TW* names out of the real inventory', () {
      final path = inventoryJsonPath();
      expect(File(path).existsSync(), isTrue, reason: 'T1.3 generates this');

      final names = exportedTwFunctions(path);
      expect(names, hasLength(464));
      expect(names.every((n) => n.startsWith('TW')), isTrue);
      expect(names, contains('TWHDWalletCreate'));
      expect(names, contains('TWPrivateKeyDelete'));
      expect(names, isNot(contains('wcf_build_info')));

      // The list is a projection of the generated file, never hand-maintained:
      // it must agree with the count the generator itself recorded, and it must
      // be sorted and duplicate-free so a diff of two runs is stable.
      final counts =
          (jsonDecode(File(path).readAsStringSync())
              as Map<String, Object?>)['counts']!;
      expect(
        (counts as Map<String, Object?>)['exported_tw_functions'],
        names.length,
      );
      expect(names.toSet(), hasLength(names.length));
      expect([...names]..sort(), names);
    });

    test('a JSON file that is not an inventory raises', () {
      final directory = scratchDirectory('wcf-inventory-test-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final notAnObject = File('${directory.path}/list.json')
        ..writeAsStringSync('[]');
      expect(
        () => exportedTwFunctions(notAnObject.path),
        throwsA(isA<FormatException>()),
      );
      final noSymbols = File('${directory.path}/empty.json')
        ..writeAsStringSync('{"counts": {}}');
      expect(
        () => exportedTwFunctions(noSymbols.path),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('measureSize on the real relinked artifacts', () {
    test('the iOS device dylib: one architecture, size matching its record', () {
      final artifact = artifactPath('ios/arm64/libTrustWalletCore.dylib');
      if (!File(artifact).existsSync()) {
        markTestSkipped('no relinked artifact set at $artifact');
        return;
      }
      final rows = measureSize(artifact: artifact, target: 'ios/arm64');
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(
        row.status,
        CheckStatus.pass,
        reason: 'record disagreement: ${row.notes}',
      );
      expect(row.values['size_bytes'], File(artifact).lengthSync());
      expect(row.values['record_size'], row.values['size_bytes']);
      expect(row.values['sha256'], row.values['record_sha256']);
      expect(row.values['provenance'], 'relinked_from_upstream_release_asset');
      expect(row.command, contains('lipo'));
      // A thin Mach-O has no per-slice breakdown; the summary is the whole file.
      expect(row.values['summary'], humanBytes(File(artifact).lengthSync()));
    });

    test('the macOS fat dylib reports a size per thin slice', () {
      final artifact = artifactPath(
        'macos/arm64_x86_64/libTrustWalletCore.dylib',
      );
      if (!File(artifact).existsSync()) {
        markTestSkipped('no relinked artifact set at $artifact');
        return;
      }
      final row = measureSize(
        artifact: artifact,
        target: 'macos/arm64_x86_64',
      ).single;
      expect(row.status, CheckStatus.pass, reason: row.notes);
      final sliceSizes = row.values['slice_sizes'];
      expect(sliceSizes, isA<Map<String, Object?>>());
      expect((sliceSizes! as Map<String, Object?>).keys.toSet(), {
        'arm64',
        'x86_64',
      });
      for (final size in (sliceSizes as Map<String, Object?>).values) {
        expect(size, isA<int>());
        expect(size! as int, greaterThan(0));
      }
      expect(row.values['summary'], contains('arm64 '));
      expect(row.values['summary'], contains('x86_64 '));
    });
  });
}
