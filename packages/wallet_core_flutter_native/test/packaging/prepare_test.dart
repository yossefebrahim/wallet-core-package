/// The two prepare steps end to end, without Gradle or CocoaPods: the Android
/// one against fake libraries, the iOS one against the real local artifact set
/// when it is present.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/option2/prepare_jni_libs.dart' show prepareJniLibs;
import '../../tool/option2/prepare_xcframework.dart'
    show
        binariesStampName,
        lockFileName,
        manifestStampName,
        prepareXcframework,
        runDirectoryPrefix;

const String _setId = 'as_4.8.0_001';

/// A manifest the fetch tool's gate accepts, for [files] by logical name.
/// [extra] adds fields to a row, by logical name.
String _manifest(
  Map<String, List<int>> files, {
  Map<String, Map<String, Object?>> extra = const {},
}) {
  final artifacts = <String, Object?>{};
  files.forEach((name, bytes) {
    final sha = sha256.convert(bytes).toString();
    artifacts[name] = {
      'sha256': sha,
      'size': bytes.length,
      'asset_name': '${_setId}__${sha}__${name.replaceAll('/', '-')}',
      'logical_name': name,
      ...?extra[name],
    };
  });
  return jsonEncode({
    'upstream': {'tag': '4.8.0'},
    'identity': {
      'artifact_set_id': _setId,
      'upstream_commit': 'd692ac27749d0c615e17c751b70ab4f0aa75c59b',
    },
    'retention': {'primary': 'https://example.invalid/r', 'mirror': null},
    'artifacts': artifacts,
  });
}

/// The Flutter SDK's `dart`, for a test that needs a second process.
String _dartExecutable() {
  final root = Platform.environment['FLUTTER_ROOT'];
  return root == null || root.isEmpty ? 'dart' : '$root/bin/dart';
}

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('wcf-prepare-'));
  tearDown(() => root.deleteSync(recursive: true));

  group('prepare_jni_libs', () {
    final files = {
      'android/arm64-v8a/libTrustWalletCore.so': utf8.encode('arm64 so'),
      'android/arm64-v8a/libc++_shared.so': utf8.encode('arm64 libc++'),
      'android/x86_64/libTrustWalletCore.so': utf8.encode('x86_64 so'),
    };

    void vendor(Map<String, List<int>> contents) {
      contents.forEach((name, bytes) {
        File('${root.path}/vendored/$name')
          ..createSync(recursive: true)
          ..writeAsBytesSync(bytes);
      });
    }

    List<String> args() => [
      '--manifest',
      '${root.path}/manifest.json',
      '--out',
      '${root.path}/jniLibs',
      '--work',
      '${root.path}/work',
      '--vendored',
      '${root.path}/vendored',
      '--cache-dir',
      '${root.path}/cache',
      '--offline',
    ];

    test('lays out every verified library as <abi>/<file>', () async {
      File('${root.path}/manifest.json').writeAsStringSync(_manifest(files));
      vendor(files);
      // A stale ABI from an earlier manifest must not survive.
      File('${root.path}/jniLibs/armeabi-v7a/libTrustWalletCore.so')
        ..createSync(recursive: true)
        ..writeAsStringSync('stale');

      final code = await prepareJniLibs(
        args(),
        packageDir: Directory.current.path,
        environment: const {},
      );
      expect(code, 0);
      final laidOut =
          Directory('${root.path}/jniLibs')
              .listSync(recursive: true)
              .whereType<File>()
              .map((f) => f.path.substring(root.path.length + 9))
              .toList()
            ..sort();
      expect(laidOut, [
        'arm64-v8a/libTrustWalletCore.so',
        'arm64-v8a/libc++_shared.so',
        'x86_64/libTrustWalletCore.so',
      ]);
      expect(
        File(
          '${root.path}/jniLibs/x86_64/libTrustWalletCore.so',
        ).readAsStringSync(),
        'x86_64 so',
      );
    });

    test('a wrong byte fails and packages nothing', () async {
      File('${root.path}/manifest.json').writeAsStringSync(_manifest(files));
      vendor({
        ...files,
        'android/x86_64/libTrustWalletCore.so': utf8.encode('x86_64 SO'),
      });

      final code = await prepareJniLibs(
        args(),
        packageDir: Directory.current.path,
        environment: const {},
      );
      expect(code, 1);
      expect(Directory('${root.path}/jniLibs').existsSync(), isFalse);
    });

    test('a placeholder manifest is blocked (exit 2), as the root one was '
        'before as_4.8.0_001', () async {
      File('${root.path}/manifest.json').writeAsStringSync(
        File(
          'test/fixtures/compat_manifest.placeholder.json',
        ).readAsStringSync(),
      );
      final code = await prepareJniLibs(
        args(),
        packageDir: Directory.current.path,
        environment: const {},
      );
      expect(code, 2);
      expect(Directory('${root.path}/jniLibs').existsSync(), isFalse);
    });
  });

  // The pod directory, and with it `--work` and `--out`, is shared by every
  // app that uses one copy of the package. Fake bytes: the fetch passes
  // verify them, and the run then stops at `lipo`, which is after the point
  // these tests are about.
  group('prepare_xcframework in a shared pod directory', () {
    const device = 'ios/arm64/libTrustWalletCore.dylib';
    const simulator = 'ios-simulator/arm64_x86_64/libTrustWalletCore.dylib';
    final files = {
      device: utf8.encode('A device dylib'),
      simulator: utf8.encode('A simulator dylib'),
    };
    final skip = Platform.isMacOS ? false : 'prepare_xcframework is macOS-only';

    late String work;

    setUp(() {
      work = '${root.path}/pod/.wcf_work';
      File('${root.path}/manifest.json').writeAsStringSync(
        _manifest(
          files,
          extra: {
            device: {'abi': 'arm64', 'min_os': '13.0'},
            simulator: {'abi': 'arm64_x86_64', 'min_os': '13.0'},
          },
        ),
      );
      files.forEach((name, bytes) {
        File('${root.path}/vendored/$name')
          ..createSync(recursive: true)
          ..writeAsBytesSync(bytes);
      });
    });

    List<String> args() => [
      '--manifest',
      '${root.path}/manifest.json',
      '--out',
      '${root.path}/pod/Frameworks',
      '--work',
      work,
      '--vendored',
      '${root.path}/vendored',
      '--cache-dir',
      '${root.path}/cache',
      '--offline',
      '--privacy-manifest',
      'ios/Resources/PrivacyInfo.xcprivacy',
      '--deployment-target',
      '15.0',
    ];

    test(
      'never touches a file another run verified in the shared --work',
      () async {
        // Another app's pod install, mid-flight, against another manifest: its
        // copy-out pass has just verified its own device dylib at the path a
        // run used to share. Deleting it as "corrupt" and putting this run's
        // bytes there is what let that run stamp and ship this run's set.
        final theirs = File('$work/$device')..createSync(recursive: true);
        theirs.writeAsStringSync('B device dylib, verified by B');
        // And a run directory a crashed run left behind.
        File(
          '$work/${runDirectoryPrefix}crashed/x',
        ).createSync(recursive: true);

        final code = await prepareXcframework(
          args(),
          packageDir: Directory.current.path,
          environment: const {},
        );
        expect(code, isNot(0), reason: 'fake bytes do not pass lipo');
        expect(theirs.readAsStringSync(), 'B device dylib, verified by B');
        final left =
            Directory(work)
                .listSync()
                .map((e) => e.uri.pathSegments.lastWhere((s) => s.isNotEmpty))
                .toList()
              ..sort();
        expect(left, [lockFileName, 'ios']);
      },
      skip: skip,
    );

    test(
      'a second prepare waits for the lock before it touches anything',
      () async {
        final packageConfig = File('../../.dart_tool/package_config.json');
        if (!packageConfig.existsSync()) {
          markTestSkipped('no workspace .dart_tool/package_config.json');
          return;
        }
        Directory(work).createSync(recursive: true);
        // This process plays the first `pod install`; the lock is a POSIX
        // record lock, so the second must be another process.
        final held = File('$work/$lockFileName').openSync(mode: FileMode.append)
          ..lockSync(FileLock.exclusive);
        final Process second;
        try {
          second = await Process.start(_dartExecutable(), [
            '--packages=${packageConfig.absolute.path}',
            'tool/option2/prepare_xcframework.dart',
            ...args(),
          ]);
        } on ProcessException catch (e) {
          held.closeSync();
          markTestSkipped('cannot start dart: $e');
          return;
        }
        final output = StringBuffer();
        final waiting = Completer<void>();
        second.stdout.transform(utf8.decoder).listen((chunk) {
          output.write(chunk);
          if (!waiting.isCompleted &&
              output.toString().contains('waiting for another prepare step')) {
            waiting.complete();
          }
        });
        second.stderr.transform(utf8.decoder).listen(output.write);
        var exited = false;
        final finished = second.exitCode.then((code) {
          exited = true;
          return code;
        });

        await Future.any([waiting.future, finished]);
        expect(waiting.isCompleted, isTrue, reason: '$output');
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(exited, isFalse, reason: 'ran while the lock was held: $output');
        expect(Directory('$work/ios').existsSync(), isFalse);
        expect(Directory('${root.path}/cache').existsSync(), isFalse);

        held.closeSync();
        expect(await finished, isNot(0), reason: 'fake bytes; $output');
        expect(output.toString(), contains('packaging for iOS'));
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  group('prepare_xcframework against the local artifact set', () {
    const manifest = '../../eval/option2/eval_manifest.json';
    const vendored = '../../third_party/wcf-native-all/artifacts';
    final available =
        Platform.isMacOS &&
        File(manifest).existsSync() &&
        File('$vendored/ios/arm64/libTrustWalletCore.dylib').existsSync();
    final skip = available
        ? false
        : 'needs macOS, eval/option2/eval_manifest.json and the git-ignored '
              'third_party/wcf-native-all/ set';

    List<String> args(String manifestPath) => [
      '--manifest',
      manifestPath,
      '--out',
      '${root.path}/Frameworks',
      '--work',
      '${root.path}/work',
      '--vendored',
      vendored,
      '--cache-dir',
      '${root.path}/cache',
      '--offline',
      '--privacy-manifest',
      'ios/Resources/PrivacyInfo.xcprivacy',
      '--deployment-target',
      '15.0',
    ];

    test(
      'assembles two signed framework slices and the stamps',
      () async {
        final code = await prepareXcframework(
          args(manifest),
          packageDir: Directory.current.path,
          environment: const {},
        );
        expect(code, 0);
        final xcf = '${root.path}/Frameworks/TrustWalletCore.xcframework';
        for (final slice in ['ios-arm64', 'ios-arm64_x86_64-simulator']) {
          final bundle = '$xcf/$slice/TrustWalletCore.framework';
          expect(File('$bundle/TrustWalletCore').existsSync(), isTrue);
          expect(File('$bundle/PrivacyInfo.xcprivacy').existsSync(), isTrue);
          final id = Process.runSync('otool', [
            '-D',
            '$bundle/TrustWalletCore',
          ]);
          expect(
            '${id.stdout}',
            contains('@rpath/TrustWalletCore.framework/TrustWalletCore'),
          );
          final verify = Process.runSync('codesign', ['--verify', bundle]);
          expect(verify.exitCode, 0, reason: '${verify.stderr}');
        }
        final check = Process.runSync('shasum', [
          '-a',
          '256',
          '-c',
          binariesStampName,
        ], workingDirectory: '${root.path}/Frameworks');
        expect(check.exitCode, 0, reason: '${check.stdout}${check.stderr}');
        expect(
          File(
            '${root.path}/Frameworks/$manifestStampName',
          ).readAsStringSync().trim(),
          sha256.convert(File(manifest).readAsBytesSync()).toString(),
        );
        // The run's own work directory is gone; only the lock file stays.
        expect(Directory('${root.path}/work').listSync().map((e) => e.path), [
          '${root.path}/work/$lockFileName',
        ]);
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'a flipped digest fails before anything is written',
      () async {
        final decoded =
            jsonDecode(File(manifest).readAsStringSync())
                as Map<String, Object?>;
        final record =
            (decoded['artifacts']!
                    as Map<
                      String,
                      Object?
                    >)['ios/arm64/libTrustWalletCore.dylib']!
                as Map<String, Object?>;
        final sha = record['sha256']! as String;
        final flipped =
            '${sha.substring(0, 63)}${sha.endsWith('0') ? '1' : '0'}';
        record['sha256'] = flipped;
        record['asset_name'] = (record['asset_name']! as String).replaceFirst(
          sha,
          flipped,
        );
        final path = '${root.path}/flipped.json';
        File(path).writeAsStringSync(jsonEncode(decoded));

        final code = await prepareXcframework(
          args(path),
          packageDir: Directory.current.path,
          environment: const {},
        );
        expect(code, 1);
        expect(Directory('${root.path}/Frameworks').existsSync(), isFalse);
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
