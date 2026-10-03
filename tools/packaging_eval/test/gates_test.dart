// Parsers over saved gate-script and zipalign output.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.

import 'package:test/test.dart';
import 'package:wcf_tool_packaging_eval/gates.dart';

import 'fixtures.dart';

void main() {
  group('check_exports.sh', () {
    test('reads a passing universal Mach-O, one row per architecture', () {
      final archs = parseCheckExportsLog(toolOutput('check_exports_pass.txt'));
      expect(archs.map((a) => a.arch), ['x86_64', 'arm64']);
      for (final arch in archs) {
        expect(arch.expected, 464);
        expect(arch.twExports, 464);
        expect(arch.missing, 0);
        expect(arch.unexpected, 0);
        expect(arch.identityExported, isTrue);
        expect(arch.reconciles, isTrue);
      }
      expect(archs.last.definedExternal, 29435);
    });

    test('reads upstream\'s framework: all 464, no identity symbol', () {
      // The fixture is upstream's `ios-arm64` device slice, which is thin:
      // one architecture, not the two of the simulator slice.
      final archs = parseCheckExportsLog(
        toolOutput('check_exports_no_identity.txt'),
      );
      expect(archs, hasLength(1));
      final arch = archs.single;
      expect(arch.arch, 'arm64');
      expect(arch.twExports, 464, reason: 'DECISION-9 F2, re-measured');
      expect(arch.missing, 0);
      expect(arch.unexpected, 0);
      expect(arch.reconciles, isTrue);
      expect(
        arch.identityExported,
        isFalse,
        reason: 'upstream does not build wcf_build_info.c',
      );
      // DECISION-9 §5 sizes the duplicate-symbol scan by this number.
      expect(arch.definedExternal, 57174);
    });

    test('reads a thin binary as a single architecture', () {
      final archs = parseCheckExportsLog('''
arch (single architecture): 100 defined external symbols, 4 of them TW*
arch (single architecture): expected 5, missing 1, unexpected 0
arch (single architecture): _wcf_build_info exported: no
''');
      expect(archs.single.arch, 'single');
      expect(archs.single.missing, 1);
      expect(archs.single.reconciles, isFalse);
      expect(archs.single.identityExported, isFalse);
    });
  });

  group('check_alignment.sh', () {
    test('reads a 16 KB-aligned ELF', () {
      final result = parseCheckAlignmentLog(
        toolOutput('check_alignment_pass.txt'),
      )!;
      expect(result.loadSegments, 4);
      expect(result.belowAlignment, 0);
      expect(result.requiredAlign, '0x4000');
      expect(result.passed, isTrue);
    });

    test('reads a 4 KB-aligned ELF as a failure', () {
      final result = parseCheckAlignmentLog(
        toolOutput('check_alignment_fail.txt'),
      )!;
      expect(result.loadSegments, 2);
      expect(result.belowAlignment, 2);
      expect(result.passed, isFalse);
    });

    test('reads the 32-bit skip', () {
      final result = parseCheckAlignmentLog(
        'check_alignment.sh: x.so is a 32-bit ELF; 16 KB alignment does not '
        'apply. Skipped.',
      )!;
      expect(result.skippedAs32Bit, isTrue);
      expect(result.passed, isFalse, reason: 'a skip is not a pass');
    });

    test('returns null when there is no summary line', () {
      expect(parseCheckAlignmentLog('nothing'), isNull);
    });
  });

  group('zipalign -c -P 16 -v 4', () {
    test('reads a passing archive', () {
      final report = parseZipalignCheck(toolOutput('zipalign_check_pass.txt'));
      expect(report.archive, 'aligned.apk');
      expect(report.verified, isTrue);
      expect(report.sharedObjects, hasLength(2));
      expect(report.badSharedObjects, isEmpty);
      expect(
        report.sharedObjects.first.offset % 16384,
        0,
        reason: 'a .so entry has to start on a 16 KB boundary',
      );
    });

    test('reads a failing archive and names the bad .so entries', () {
      final report = parseZipalignCheck(toolOutput('zipalign_check_fail.txt'));
      expect(report.verified, isFalse);
      expect(report.badSharedObjects.map((e) => e.name), [
        'lib/arm64-v8a/libc++_shared.so',
        'lib/x86_64/libc++_shared.so',
      ]);
      expect(report.badSharedObjects.first.verdict, 'BAD - 138');
    });

    test(
      'does not count directories or compressed entries as .so failures',
      () {
        final report = parseZipalignCheck('''
Verifying alignment of app.apk (4)...
      34 lib/ (OK - directory)
    4096 assets/flutter_assets/x (OK - compressed)
   16384 lib/arm64-v8a/libfoo.so (OK)
Verification successful
''');
        expect(report.verified, isTrue);
        expect(report.entries, hasLength(3));
        expect(report.sharedObjects, hasLength(1));
        expect(report.badEntries, isEmpty);
      },
    );
  });
}
