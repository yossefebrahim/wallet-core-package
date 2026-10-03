// Target → artifact selection and asset naming for the build hook.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.

import 'package:code_assets/code_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter_native/wallet_core_flutter_native.dart';

import '../../hook/src/slices.dart';
import '../../hook/src/targets.dart';

void main() {
  group('Android ABI mapping', () {
    test('the three shipped ABIs', () {
      expect(androidAbi(Architecture.arm64), 'arm64-v8a');
      expect(androidAbi(Architecture.arm), 'armeabi-v7a');
      expect(androidAbi(Architecture.x64), 'x86_64');
    });

    test('x86 and RISC-V are not shipped', () {
      expect(androidAbi(Architecture.ia32), isNull);
      expect(androidAbi(Architecture.riscv64), isNull);
    });

    test('each ABI selects its own .so and checks its own ELF machine', () {
      const expected = {
        Architecture.arm64: ('arm64-v8a', ElfMachine.aarch64),
        Architecture.arm: ('armeabi-v7a', ElfMachine.arm),
        Architecture.x64: ('x86_64', ElfMachine.x86_64),
      };
      expected.forEach((arch, want) {
        final s = selectArtifact(os: OS.android, architecture: arch)!;
        expect(s.candidates, ['android/${want.$1}/libTrustWalletCore.so']);
        expect(s.fileName, 'libTrustWalletCore.so');
        expect((s.slice as ElfSlice).machine, want.$2);
      });
    });

    test('an unshipped ABI fails the build with the ABIs that are', () {
      expect(
        () => selectArtifact(os: OS.android, architecture: Architecture.ia32),
        throwsA(
          isA<UnsupportedTarget>().having(
            (e) => e.message,
            'message',
            allOf(contains('ia32'), contains('arm64-v8a'), contains('x86_64')),
          ),
        ),
      );
    });
  });

  group('Apple selection', () {
    test('iOS device arm64 takes the device library', () {
      final s = selectArtifact(
        os: OS.iOS,
        architecture: Architecture.arm64,
        iosSdk: IOSSdk.iPhoneOS,
      )!;
      expect(s.candidates, ['ios/arm64/libTrustWalletCore.dylib']);
      expect((s.slice as MachOSlice).arch, MachOArch.arm64);
    });

    test('iOS simulator prefers a thin slice, then the universal one', () {
      for (final (arch, mach) in [
        (Architecture.arm64, MachOArch.arm64),
        (Architecture.x64, MachOArch.x86_64),
      ]) {
        final s = selectArtifact(
          os: OS.iOS,
          architecture: arch,
          iosSdk: IOSSdk.iPhoneSimulator,
        )!;
        expect(s.candidates, [
          'ios-simulator/${mach.abiName}/libTrustWalletCore.dylib',
          'ios-simulator/arm64_x86_64/libTrustWalletCore.dylib',
        ]);
        expect((s.slice as MachOSlice).arch, mach);
      }
    });

    test('macOS takes its own library, per architecture', () {
      for (final arch in [Architecture.arm64, Architecture.x64]) {
        final s = selectArtifact(os: OS.macOS, architecture: arch)!;
        expect(
          s.candidates.last,
          'macos/arm64_x86_64/libTrustWalletCore.dylib',
        );
      }
    });

    test('a device x86_64 or a missing SDK is refused', () {
      expect(
        () => selectArtifact(
          os: OS.iOS,
          architecture: Architecture.x64,
          iosSdk: IOSSdk.iPhoneOS,
        ),
        throwsA(isA<UnsupportedTarget>()),
      );
      expect(
        () => selectArtifact(os: OS.iOS, architecture: Architecture.arm64),
        throwsA(isA<UnsupportedTarget>()),
      );
    });
  });

  group('asset naming (PRD §12.1, iOS row)', () {
    test('one file name across both iOS SDKs and every architecture', () {
      final names = <String>{
        for (final sdk in IOSSdk.values)
          for (final arch in [Architecture.arm64, Architecture.x64])
            if (!(sdk == IOSSdk.iPhoneOS && arch == Architecture.x64))
              selectArtifact(
                os: OS.iOS,
                architecture: arch,
                iosSdk: sdk,
              )!.fileName,
        for (final arch in [Architecture.arm64, Architecture.x64])
          selectArtifact(os: OS.macOS, architecture: arch)!.fileName,
      };
      expect(names, {'libTrustWalletCore.dylib'});
      expect(
        names.single,
        isNot(anyOf(contains('sim'), contains('arm64'), contains('x86'))),
      );
    });

    test('one file name across every Android ABI', () {
      final names = {
        for (final arch in [
          Architecture.arm64,
          Architecture.arm,
          Architecture.x64,
        ])
          selectArtifact(os: OS.android, architecture: arch)!.fileName,
      };
      expect(names, {'libTrustWalletCore.so'});
    });

    test('one asset id, and it carries no "trust"', () {
      expect(codeAssetName, 'wallet_core');
      expect(codeAssetName.toLowerCase(), isNot(contains('trust')));
    });

    test('the Apple file name becomes the framework the loader opens', () {
      // flutter_tools' frameworkUri: drop `.dylib`, drop a leading `lib`,
      // keep [A-Za-z0-9_-], then `<name>.framework/<name>`.
      var name = appleLibraryFileName;
      name = name.substring(0, name.length - '.dylib'.length);
      name = name.replaceFirst('lib', '');
      name = name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
      expect('$name.framework/$name', iosFrameworkLibraryPath);
    });

    test('the Android file name is the one the loader opens', () {
      expect(androidLibraryFileName, androidLibraryName);
    });
  });

  test('an OS with no library gets no asset and no failure', () {
    expect(
      selectArtifact(os: OS.linux, architecture: Architecture.x64),
      isNull,
    );
    expect(
      selectArtifact(os: OS.windows, architecture: Architecture.x64),
      isNull,
    );
  });

  group('chooseLogicalName', () {
    final sim = selectArtifact(
      os: OS.iOS,
      architecture: Architecture.arm64,
      iosSdk: IOSSdk.iPhoneSimulator,
    )!;

    test('takes the universal artifact when no thin one is listed', () {
      expect(
        chooseLogicalName(sim, const [
          'ios/arm64/libTrustWalletCore.dylib',
          'ios-simulator/arm64_x86_64/libTrustWalletCore.dylib',
        ], manifestSource: 'm.json'),
        'ios-simulator/arm64_x86_64/libTrustWalletCore.dylib',
      );
    });

    test('takes a thin artifact over the universal one', () {
      expect(
        chooseLogicalName(sim, const [
          'ios-simulator/arm64_x86_64/libTrustWalletCore.dylib',
          'ios-simulator/arm64/libTrustWalletCore.dylib',
        ], manifestSource: 'm.json'),
        'ios-simulator/arm64/libTrustWalletCore.dylib',
      );
    });

    test('an xcframework-only manifest fails, naming what it looked for', () {
      expect(
        () => chooseLogicalName(sim, const [
          'android/arm64-v8a/libTrustWalletCore.so',
          'ios/TrustWalletCore.xcframework.zip',
        ], manifestSource: 'compat_manifest.json'),
        throwsA(
          isA<UnsupportedTarget>().having(
            (e) => e.message,
            'message',
            allOf(
              contains(
                'compat_manifest.json has no artifact for iOS '
                'iphonesimulator arm64',
              ),
              contains('ios-simulator/arm64_x86_64/libTrustWalletCore.dylib'),
              contains('ios/TrustWalletCore.xcframework.zip'),
              contains('per-slice'),
            ),
          ),
        ),
      );
    });
  });

  test('the code-asset locations open what the hook emits', () {
    expect(
      codeAssetLocations(platform: NativePlatform.ios).single.description,
      contains(iosFrameworkLibraryPath),
    );
    expect(
      codeAssetLocations(
        platform: NativePlatform.macos,
        executable: '/Applications/Some App.app/Contents/MacOS/Some App',
      ).single.description,
      contains(
        '"/Applications/Some App.app/Contents/Frameworks/'
        '$iosFrameworkLibraryPath"',
      ),
    );
    expect(
      codeAssetLocations(platform: NativePlatform.android).single.description,
      contains(androidLibraryFileName),
    );
    expect(codeAssetLocations(platform: NativePlatform.linux), isEmpty);
    // Never the running process: DynamicLibrary.process() cannot fail, so it
    // would shadow the framework that holds the identity symbol.
    for (final platform in NativePlatform.values) {
      expect(
        codeAssetLocations(platform: platform).whereType<ProcessLibrary>(),
        isEmpty,
      );
    }
  });

  // Review finding 15 (T1.8a-d4): the macOS location was the relative
  // `TrustWalletCore.framework/TrustWalletCore`, which dlopen resolves against
  // the working directory — whatever directory the app was started from.
  group('macOS: never a working-directory-relative path', () {
    test('the location is the bundle\'s own framework, absolute', () {
      final location = codeAssetLocations(
        platform: NativePlatform.macos,
        executable: '/Users/x/Runner.app/Contents/MacOS/Runner',
      ).single;
      expect(location, isA<LibraryFile>());
      expect(
        (location as LibraryFile).path,
        '/Users/x/Runner.app/Contents/Frameworks/'
        'TrustWalletCore.framework/TrustWalletCore',
      );
    });

    test('outside an app bundle: no location, not a guess', () {
      for (final executable in [
        // flutter_tester, a dart CLI: not a bundle
        '/Users/x/flutter/bin/cache/artifacts/engine/darwin-x64/flutter_tester',
        // relative, or with dot segments: refused
        'Runner.app/Contents/MacOS/Runner',
        '/Users/x/Runner.app/Contents/MacOS/../MacOS/Runner',
        // the right names in the wrong places
        '/Users/x/Runner/Contents/MacOS/Runner',
        '/Users/x/Runner.app/MacOS/Runner',
        '/Users/x/Runner.app/Contents/MacOS/',
      ]) {
        expect(
          codeAssetLocations(
            platform: NativePlatform.macos,
            executable: executable,
          ),
          isEmpty,
          reason: executable,
        );
      }
    });

    test('no platform\'s list has a relative path with a slash, except '
        'iOS (working directory /, see code_asset_locations.dart)', () {
      for (final platform in NativePlatform.values) {
        if (platform == NativePlatform.ios) continue;
        for (final location in codeAssetLocations(
          platform: platform,
          executable: '/A.app/Contents/MacOS/A',
        )) {
          final path = switch (location) {
            NamedLibrary(:final name) => name,
            LibraryFile(:final path) => path,
            _ => fail('unexpected location $location'),
          };
          expect(
            path.startsWith('/') || !path.contains('/'),
            isTrue,
            reason: '${platform.name}: $path',
          );
        }
      }
    });
  });
}
