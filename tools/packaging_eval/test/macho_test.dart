// Parsers over saved Mach-O tool output.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.

import 'package:test/test.dart';
import 'package:wcf_tool_packaging_eval/macho.dart';

import 'fixtures.dart';

void main() {
  group('lipo', () {
    test('reads the slices of a real universal Mach-O', () {
      final slices = parseLipoDetailedInfo(
        toolOutput('lipo_detailed_info_fat.txt'),
      );
      expect(slices.map((s) => s.arch), ['x86_64', 'arm64']);
      expect(slices.first.size, 21351416);
      expect(slices.first.alignBytes, 4096);
      expect(slices.last.size, 19877320);
      // The arm64 slice of our relinked macOS library is 16 KB-aligned inside
      // the fat file and the x86_64 one is 4 KB-aligned. That is a property of
      // the fat header, not of the ELF LOAD alignment the Android gate checks.
      expect(slices.last.alignBytes, 16384);
    });

    test('reads a thin file and a fat file from -info', () {
      final lines = toolOutput('lipo_info_thin.txt').split('\n');
      expect(parseLipoInfo(lines[0]), ['arm64']);
      expect(parseLipoInfo(lines[1]), ['x86_64', 'arm64']);
    });

    test('a thin file has no detailed slice blocks', () {
      expect(
        parseLipoDetailedInfo('Non-fat file: x is architecture: arm64'),
        isEmpty,
      );
    });
  });

  group('vtool', () {
    test('reads the iOS deployment target', () {
      final build = parseVtoolShowBuild(
        toolOutput('vtool_show_build_ios_arm64.txt'),
      )!;
      expect(build.loadCommand, 'LC_BUILD_VERSION');
      expect(build.platform, 'IOS');
      expect(build.minOs, '13.0');
      expect(build.sdk, '26.5');
    });

    test('reads the macOS deployment target', () {
      final build = parseVtoolShowBuild(
        toolOutput('vtool_show_build_macos_x86_64.txt'),
      )!;
      expect(build.platform, 'MACOS');
      // Measured, and worth stating: the relink asked for 11.0 and the load
      // command says 26.0 on both slices. See the harness README.
      expect(build.minOs, '26.0');
    });

    test('understands the older LC_VERSION_MIN_* shape', () {
      final build = parseVtoolShowBuild('''
Load command 8
      cmd LC_VERSION_MIN_IPHONEOS
  cmdsize 16
  version 9.0
      sdk 12.1
''')!;
      expect(build.platform, 'IOS');
      expect(build.minOs, '9.0');
    });

    test('returns null when there is no build command', () {
      expect(parseVtoolShowBuild('nothing here'), isNull);
    });
  });

  group('otool', () {
    test('reads the install name and dependencies of our dylib', () {
      final linked = parseOtoolL(toolOutput('otool_L_relinked_ios_arm64.txt'));
      expect(linked.installName, '@rpath/libTrustWalletCore.dylib');
      expect(linked.dependencies, contains('/usr/lib/libc++.1.dylib'));
      expect(
        linked.dependencies.where((d) => d.contains('swift')),
        isEmpty,
        reason: 'our relink links no Swift runtime',
      );
    });

    test('reads upstream framework dependencies, Swift runtime and all', () {
      final linked = parseOtoolL(toolOutput('otool_L_upstream_ios_arm64.txt'));
      expect(linked.installName, '@rpath/WalletCore.framework/WalletCore');
      expect(
        linked.dependencies,
        contains(
          '@rpath/WalletCoreSwiftProtobuf.framework/WalletCoreSwiftProtobuf',
        ),
      );
      expect(
        linked.dependencies.where((d) => d.startsWith('/usr/lib/swift/')),
        isNotEmpty,
      );
    });

    test('reads the install name from -D', () {
      expect(
        parseOtoolD(toolOutput('otool_D_relinked_ios_arm64.txt')),
        '@rpath/libTrustWalletCore.dylib',
      );
    });

    test('finds no LC_RPATH in a library that has none', () {
      expect(
        parseOtoolRpaths(toolOutput('otool_l_head_relinked_ios_arm64.txt')),
        isEmpty,
      );
    });

    test('reads LC_RPATH entries', () {
      expect(parseOtoolRpaths(toolOutput('otool_l_rpaths_synthetic.txt')), [
        '@executable_path/Frameworks',
        '@loader_path',
      ]);
    });
  });

  group('nm', () {
    test('reads defined external symbols', () {
      final names = parseNmNames(
        toolOutput('nm_gU_relinked_ios_arm64_head.txt'),
      );
      expect(names, contains('_AptosDP'));
      expect(names.length, 20);
    });

    test('reads one-field undefined-symbol output', () {
      final names = parseNmNames(
        toolOutput('nm_u_relinked_ios_arm64_head.txt'),
      );
      expect(names, contains('_SecRandomCopyBytes'));
      expect(names, contains('__Unwind_Resume'));
      expect(names.length, 60);
    });

    test('drops the per-architecture banner', () {
      expect(
        parseNmNames(
          'libX.dylib (for architecture arm64):\n'
          '0000000000c026d8 D _AptosDP',
        ),
        ['_AptosDP'],
      );
    });
  });

  group('codesign', () {
    test('reads an unsigned library', () {
      final info = parseCodesignOutput(toolOutput('codesign_unsigned.txt'));
      expect(info.state, SigningState.unsigned);
    });

    test('reads an ad-hoc signature', () {
      final info = parseCodesignOutput('''
Executable=/tmp/x
Identifier=com.example.x
Format=Mach-O thin (arm64)
Signature=adhoc
''');
      expect(info.state, SigningState.adhoc);
      expect(info.identifier, 'com.example.x');
    });

    test('reads a real signature', () {
      final info = parseCodesignOutput('''
Executable=/tmp/x
Identifier=com.example.x
TeamIdentifier=ABCDE12345
Authority=Apple Development: Someone (XYZ)
''');
      expect(info.state, SigningState.signed);
      expect(info.teamIdentifier, 'ABCDE12345');
      expect(info.authority, 'Apple Development: Someone (XYZ)');
    });
  });
}
