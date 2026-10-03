// Locating the repository, the NDK, and the tools each measurement shells out
// to.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.

import 'dart:io';

import 'package:test/test.dart';
import 'package:wcf_tool_packaging_eval/host.dart';

void main() {
  group('compareVersionDirectories', () {
    test('orders NDK directories numerically, not lexically', () {
      final directories = [
        '/sdk/ndk/28.2.13676358',
        '/sdk/ndk/21.4.7075529',
        '/sdk/ndk/9.0.0',
        '/sdk/ndk/27.0.12077973',
      ]..sort(compareVersionDirectories);
      expect(directories, [
        '/sdk/ndk/9.0.0',
        '/sdk/ndk/21.4.7075529',
        '/sdk/ndk/27.0.12077973',
        '/sdk/ndk/28.2.13676358',
      ]);
    });

    test('a longer version sorts after its own prefix', () {
      expect(
        compareVersionDirectories('/x/28.2', '/x/28.2.13676358'),
        lessThan(0),
      );
    });

    test('equal directory names compare equal', () {
      expect(compareVersionDirectories('/a/28.2.1', '/b/28.2.1'), 0);
    });

    test('a non-numeric component sorts below every numbered one', () {
      final directories = ['/sdk/ndk/28.2.1', '/sdk/ndk/side-by-side']
        ..sort(compareVersionDirectories);
      expect(directories.first, '/sdk/ndk/side-by-side');
    });
  });

  group('ndkRoot', () {
    late Directory scratch;

    setUp(() => scratch = scratchDirectory('wcf-host-test-'));
    tearDown(() {
      if (scratch.existsSync()) scratch.deleteSync(recursive: true);
    });

    test(r'prefers $ANDROID_NDK over $ANDROID_HOME/ndk', () {
      final explicit = Directory('${scratch.path}/explicit-ndk')
        ..createSync(recursive: true);
      final sdk = Directory('${scratch.path}/sdk/ndk/28.2.13676358')
        ..createSync(recursive: true);

      expect(
        ndkRoot(
          environment: {
            'ANDROID_NDK': explicit.path,
            'ANDROID_HOME': '${scratch.path}/sdk',
          },
        ),
        explicit.path,
      );
      // …and falls back to the SDK's highest-numbered ndk directory.
      expect(
        ndkRoot(environment: {'ANDROID_HOME': '${scratch.path}/sdk'}),
        sdk.path,
      );
    });

    test(r'ignores an $ANDROID_NDK that does not exist', () {
      expect(
        ndkRoot(environment: {'ANDROID_NDK': '${scratch.path}/absent'}),
        isNull,
      );
    });

    test(r'honours $ANDROID_NDK_HOME and $ANDROID_NDK_ROOT in that order', () {
      final home = Directory('${scratch.path}/ndk-home')
        ..createSync(recursive: true);
      final root = Directory('${scratch.path}/ndk-root')
        ..createSync(recursive: true);
      expect(
        ndkRoot(
          environment: {
            'ANDROID_NDK_HOME': home.path,
            'ANDROID_NDK_ROOT': root.path,
          },
        ),
        home.path,
      );
      expect(ndkRoot(environment: {'ANDROID_NDK_ROOT': root.path}), root.path);
    });

    test(r'picks the highest-numbered ndk under $ANDROID_HOME', () {
      for (final version in const ['21.4.7075529', '28.2.13676358', '9.0.0']) {
        Directory(
          '${scratch.path}/sdk/ndk/$version',
        ).createSync(recursive: true);
      }
      expect(
        ndkRoot(environment: {'ANDROID_HOME': '${scratch.path}/sdk'}),
        endsWith('/ndk/28.2.13676358'),
      );
    });

    test('an empty environment finds nothing', () {
      expect(ndkRoot(environment: const {}), isNull);
    });
  });

  group('repoRoot and the paths derived from it', () {
    test('finds the workspace root and the files the harness reads', () {
      final root = repoRoot();
      expect(
        File('${root.path}/pubspec.yaml').readAsStringSync(),
        contains('name: wallet_core_flutter_workspace'),
      );
      expect(
        nativeBuildScript('check_exports.sh'),
        endsWith('/tools/native_build/check_exports.sh'),
      );
      expect(File(nativeBuildScript('check_exports.sh')).existsSync(), isTrue);
      expect(
        File(nativeBuildScript('check_alignment.sh')).existsSync(),
        isTrue,
      );
      expect(inventoryJsonPath(), endsWith('/generated/inventory.json'));
      expect(File(inventoryJsonPath()).existsSync(), isTrue);
    });
  });

  group('scratchDirectory', () {
    test('creates a directory outside the repository', () {
      final directory = scratchDirectory('wcf-scratch-test-');
      addTearDown(() {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });
      expect(directory.existsSync(), isTrue);
      expect(directory.path, isNot(startsWith(repoRoot().path)));
    });
  });

  group('the real host toolchain', () {
    test('ndkLibcxxShared finds a 64-bit ELF for both ABIs when the NDK is '
        'installed', () {
      final ndk = ndkRoot();
      if (ndk == null) {
        markTestSkipped('no Android NDK on this machine');
        return;
      }
      for (final abi in const ['arm64-v8a', 'x86_64']) {
        final path = ndkLibcxxShared(abi, root: ndk);
        expect(path, isNotNull, reason: 'no libc++_shared.so for $abi');
        expect(File(path!).lengthSync(), greaterThan(0));
      }
      expect(ndkLlvmTool('llvm-readelf', root: ndk), isNotNull);
      expect(ndkLlvmTool('llvm-nm', root: ndk), isNotNull);
      expect(ndkLlvmTool('not-a-real-tool', root: ndk), isNull);
    });

    test('sha256OfFile agrees with itself over a temp file', () {
      final directory = scratchDirectory('wcf-sha-test-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/bytes')
        ..writeAsBytesSync(List<int>.filled(4096, 42));
      final digest = sha256OfFile(file.path);
      if (digest == null) {
        markTestSkipped('neither shasum nor sha256sum is on PATH');
        return;
      }
      expect(digest, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(sha256OfFile(file.path), digest);
      expect(sha256OfFile('${directory.path}/absent'), isNull);
    });
  });
}
