// Slice extraction and architecture checks for the build hook.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../hook/src/slices.dart';
import 'fixtures.dart';

void main() {
  final arm = thinMachO(cpuArm64, length: 96, fill: 0x11);
  final x86 = thinMachO(cpuX86_64, length: 80, fill: 0x22);

  group('Mach-O', () {
    test('a universal file yields exactly the requested slice', () {
      for (final wide in [false, true]) {
        final fat = fatMachO([x86, arm], wide: wide);
        expect(
          takeSlice(fat, const MachOSlice(MachOArch.arm64), source: 'f'),
          arm,
        );
        expect(
          takeSlice(fat, const MachOSlice(MachOArch.x86_64), source: 'f'),
          x86,
        );
      }
    });

    test('a thin file of the right architecture passes through unchanged', () {
      final out = takeSlice(
        arm,
        const MachOSlice(MachOArch.arm64),
        source: 't',
      );
      expect(identical(out, arm), isTrue);
    });

    test('a thin file of the wrong architecture is refused', () {
      expect(
        () => takeSlice(
          arm,
          const MachOSlice(MachOArch.x86_64),
          source: 'ios/arm64/libTrustWalletCore.dylib',
        ),
        throwsA(
          isA<SliceError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('ios/arm64/libTrustWalletCore.dylib'),
              contains('x86_64'),
            ),
          ),
        ),
      );
    });

    test('a universal file without the slice names what it has', () {
      expect(
        () => takeSlice(
          fatMachO([x86]),
          const MachOSlice(MachOArch.arm64),
          source: 'f',
        ),
        throwsA(
          isA<SliceError>().having(
            (e) => e.message,
            'message',
            contains('0x1000007'),
          ),
        ),
      );
    });

    test('a truncated or foreign file is refused', () {
      final fat = fatMachO([arm]);
      expect(
        () => takeSlice(
          Uint8List.sublistView(fat, 0, fat.length - 8),
          const MachOSlice(MachOArch.arm64),
          source: 'f',
        ),
        throwsA(isA<SliceError>()),
      );
      expect(
        () => takeSlice(
          Uint8List.fromList(List.filled(64, 0)),
          const MachOSlice(MachOArch.arm64),
          source: 'f',
        ),
        throwsA(isA<SliceError>()),
      );
      expect(
        () => takeSlice(
          elf(machine: 183),
          const MachOSlice(MachOArch.arm64),
          source: 'f',
        ),
        throwsA(isA<SliceError>()),
      );
    });
  });

  group('ELF', () {
    test('each ABI accepts its machine and refuses the others', () {
      final files = {
        ElfMachine.aarch64: elf(machine: 183),
        ElfMachine.arm: elf(machine: 40, bits: 32),
        ElfMachine.x86_64: elf(machine: 62),
      };
      for (final want in ElfMachine.values) {
        for (final entry in files.entries) {
          final spec = ElfSlice(want);
          if (entry.key == want) {
            expect(takeSlice(entry.value, spec, source: 'so'), entry.value);
          } else {
            expect(
              () => takeSlice(entry.value, spec, source: 'so'),
              throwsA(isA<SliceError>()),
            );
          }
        }
      }
    });

    test('the ABI table is the NDK one', () {
      expect(ElfMachine.forAndroidAbi('arm64-v8a'), ElfMachine.aarch64);
      expect(ElfMachine.forAndroidAbi('armeabi-v7a'), ElfMachine.arm);
      expect(ElfMachine.forAndroidAbi('x86_64'), ElfMachine.x86_64);
      expect(() => ElfMachine.forAndroidAbi('x86'), throwsArgumentError);
    });
  });

  // The real file, when this checkout has the locally built set: the slice
  // the hook takes must be byte-identical to what `lipo -thin` produces.
  final universal = File(
    '../../third_party/wcf-native-all/artifacts/macos/arm64_x86_64/'
    'libTrustWalletCore.dylib',
  );
  test(
    'on the real universal dylib, the slice equals lipo -thin',
    () async {
      final dir = await Directory.systemTemp.createTemp('wcf-slice');
      try {
        final bytes = universal.readAsBytesSync();
        // third_party/ is untrusted input: check it is the pinned file first.
        final manifest = File(
          '../../eval/option1/eval_manifest.json',
        ).readAsStringSync();
        expect(manifest, contains('"sha256": "${sha256Hex(bytes)}"'));
        for (final arch in MachOArch.values) {
          final out = '${dir.path}/${arch.name}';
          final lipo = await Process.run('lipo', [
            universal.path,
            '-thin',
            arch.name,
            '-output',
            out,
          ]);
          expect(lipo.exitCode, 0, reason: '${lipo.stderr}');
          expect(
            takeSlice(bytes, MachOSlice(arch), source: universal.path),
            File(out).readAsBytesSync(),
          );
        }
      } finally {
        dir.deleteSync(recursive: true);
      }
    },
    skip: !universal.existsSync() || !Platform.isMacOS
        ? 'needs macOS and third_party/wcf-native-all (git-ignored local set)'
        : false,
  );
}
