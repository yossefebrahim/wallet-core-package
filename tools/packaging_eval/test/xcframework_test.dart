// Opening an .xcframework: the synthetic directory shape, and upstream's real
// zipped framework when this machine has it cached.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.

import 'dart:io';

import 'package:test/test.dart';
import 'package:wcf_tool_packaging_eval/host.dart';
import 'package:wcf_tool_packaging_eval/xcframework.dart';

/// Upstream's own iOS framework, as the pinned 4.8.0 fetch leaves it.
String get upstreamZip {
  final home = Platform.environment['HOME'] ?? '';
  return '$home/.cache/wcf-upstream/4.8.0/WalletCore.xcframework.zip';
}

void main() {
  late Directory scratch;

  setUp(() => scratch = scratchDirectory('wcf-xcframework-test-'));
  tearDown(() {
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  group('openXcframework on a directory', () {
    test('lists one slice per <slice>/<name>.framework/<name> binary', () {
      for (final slice in const ['ios-arm64', 'ios-arm64_x86_64-simulator']) {
        final binary = File(
          '${scratch.path}/Fake.xcframework/$slice/Fake.framework/Fake',
        )..parent.createSync(recursive: true);
        binary.writeAsStringSync('not a Mach-O, and never executed');
      }

      final opened = openXcframework('${scratch.path}/Fake.xcframework');
      addTearDown(opened.dispose);

      expect(opened.temporary, isNull, reason: 'a directory is not unpacked');
      expect(opened.slices.map((s) => s.identifier), [
        'ios-arm64',
        'ios-arm64_x86_64-simulator',
      ]);
      expect(opened.slices.first.binaryPath, endsWith('Fake.framework/Fake'));
    });

    test('a slice directory with no framework binary contributes no slice', () {
      Directory(
        '${scratch.path}/Empty.xcframework/ios-arm64/Empty.framework',
      ).createSync(recursive: true);
      final opened = openXcframework('${scratch.path}/Empty.xcframework');
      addTearDown(opened.dispose);
      expect(opened.slices, isEmpty);
    });

    test('a path that does not exist raises', () {
      expect(
        () => openXcframework('${scratch.path}/Missing.xcframework'),
        throwsArgumentError,
      );
    });

    test('a .zip that does not exist raises', () {
      expect(
        () => openXcframework('${scratch.path}/Missing.xcframework.zip'),
        throwsArgumentError,
      );
    });
  });

  group("openXcframework on upstream's WalletCore.xcframework.zip", () {
    test('unpacks it, lists its two slices, and disposes the temp dir', () {
      if (!File(upstreamZip).existsSync()) {
        markTestSkipped('no cached upstream framework at $upstreamZip');
        return;
      }
      final opened = openXcframework(upstreamZip);

      final temporary = opened.temporary;
      expect(temporary, isNotNull, reason: 'a .zip is unpacked under TMPDIR');
      expect(temporary!.existsSync(), isTrue);
      expect(
        temporary.path,
        isNot(contains('wallet-core-package.worktrees')),
        reason: 'nothing is written inside the repository',
      );

      // Upstream ships a device slice and a simulator slice, and no macOS one
      // (T0.5 / DECISION-9 §5).
      expect(opened.slices, hasLength(2));
      expect(opened.slices.map((s) => s.identifier).toList(), [
        'ios-arm64',
        'ios-arm64_x86_64-simulator',
      ]);
      for (final slice in opened.slices) {
        expect(slice.binaryPath, endsWith('WalletCore.framework/WalletCore'));
        expect(File(slice.binaryPath).existsSync(), isTrue);
      }

      opened.dispose();
      expect(temporary.existsSync(), isFalse);
      opened.dispose(); // a second dispose is a no-op, not a crash
    });
  });
}
