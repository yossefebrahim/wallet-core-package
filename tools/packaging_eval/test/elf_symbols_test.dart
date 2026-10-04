// ELF exports are read from the dynamic symbol table (T1.8b-d1).
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.
//
// The defect this covers: on the stripped release `.so` of as_4.8.0_001 the
// harness reported `0/464 TW*, 0 defined external, wcf_build_info no`, because
// llvm-nm without `--dynamic` reads `.symtab`, which a stripped library does
// not have. Both fixtures are that llvm-nm (NDK r28.2, LLVM 19.0.1) on that
// library: the full `.symtab` output, and an excerpt of the `.dynsym` output
// (whole lines, selected by name).

import 'dart:io';

import 'package:test/test.dart';
import 'package:wcf_tool_packaging_eval/gates.dart';
import 'package:wcf_tool_packaging_eval/host.dart';
import 'package:wcf_tool_packaging_eval/measurements.dart';
import 'package:wcf_tool_packaging_eval/results.dart';

import 'fixtures.dart';

const _listed = [
  'TWAnyAddressCreateWithString',
  'TWAnyAddressIsValid',
  'TWStringCreateWithUTF8Bytes',
];

/// Upstream's JNI glue, allowed the same way build_android.sh allows it.
const _jniGlue = [
  'TWDataCreateWithJByteArray',
  'TWDataJByteArray',
  'TWStringCreateWithJString',
  'TWStringJString',
];

void main() {
  group('parseElfDynamicExports', () {
    final dynsym = toolOutput('llvm_nm_dynamic_android_arm64_excerpt.txt');

    test('reads .dynsym: every listed name, the identity symbol, the JNI '
        'glue as allowed extras', () {
      final arch = parseElfDynamicExports(
        dynsym,
        expected: _listed,
        allowExtra: _jniGlue,
      );
      expect(arch.arch, '.dynsym');
      expect(arch.definedExternal, 11);
      expect(arch.twExports, 7);
      expect(arch.expected, 3);
      expect(arch.missing, 0);
      expect(arch.unexpected, 0);
      expect(arch.allowedExtra, _jniGlue);
      expect(arch.identityExported, isTrue);
      expect(arch.reconciles, isTrue);
      expect(arch.toJson()['allowed_extra'], _jniGlue);
    });

    test('the JNI glue is unexpected unless allowed', () {
      final arch = parseElfDynamicExports(dynsym, expected: _listed);
      expect(arch.unexpected, 4);
      expect(arch.allowedExtra, isEmpty);
      expect(arch.reconciles, isFalse);
      expect(arch.toJson(), isNot(contains('allowed_extra')));
    });

    test('a listed name absent from .dynsym is missing', () {
      final arch = parseElfDynamicExports(
        dynsym,
        expected: [..._listed, 'TWHDWalletCreate'],
        allowExtra: _jniGlue,
      );
      expect(arch.missing, 1);
      expect(arch.reconciles, isFalse);
    });

    test('the .symtab read of a stripped .so (the defect) counts nothing', () {
      final symtab = toolOutput('llvm_nm_symtab_stripped_android_arm64.txt');
      expect(symtab, contains('no symbols'));
      final arch = parseElfDynamicExports(symtab, expected: _listed);
      expect(arch.definedExternal, 0);
      expect(arch.missing, _listed.length);
      expect(arch.identityExported, isFalse);
    });
  });

  group('measureElfSymbols', () {
    late Directory scratch;
    late String inventory;
    late String nm;
    const library = 'libTrustWalletCore.so';

    setUp(() {
      scratch = scratchDirectory('wcf-elf-symbols-test-');
      inventory = '${scratch.path}/inventory.json';
      File(inventory).writeAsStringSync(
        '{"symbols": {${_listed.map((n) => '"$n": {"kind": "function"}').join(', ')}}}',
      );
      File('${scratch.path}/$library').writeAsStringSync('stand-in');
      // A stand-in llvm-nm that answers like the real one did on the stripped
      // library: the .dynsym listing with --dynamic, "no symbols" without.
      final fixtures = '${fixturesDirectory().path}/tool_output';
      nm = '${scratch.path}/llvm-nm';
      File(nm).writeAsStringSync('''#!/bin/sh
case " \$* " in
  *" --dynamic "*) cat '$fixtures/llvm_nm_dynamic_android_arm64_excerpt.txt' ;;
  *) cat '$fixtures/llvm_nm_symtab_stripped_android_arm64.txt' ;;
esac
''');
      Process.runSync('chmod', ['+x', nm]);
    });

    tearDown(() => scratch.deleteSync(recursive: true));

    test('runs llvm-nm --dynamic and passes the stripped library', () {
      final rows = measureSymbols(
        artifact: '${scratch.path}/$library',
        format: 'elf',
        target: 'android/arm64-v8a',
        inventoryPath: inventory,
        nmPath: nm,
        allowExtra: _jniGlue,
      );
      final row = rows.single;
      expect(row.status, CheckStatus.pass, reason: row.notes);
      expect(row.command, contains('--dynamic --defined-only --extern-only'));
      expect(row.command, isNot(contains('check_exports.sh')));
      expect(
        row.summary,
        '.dynsym: 3/3 TW*, 11 defined external, wcf_build_info yes, '
        '4 allowed extra',
      );
      expect(row.notes, contains('.dynsym'));
    });

    test('without the allowed extras the JNI glue fails it', () {
      final row = measureSymbols(
        artifact: '${scratch.path}/$library',
        format: 'elf',
        target: 'android/arm64-v8a',
        inventoryPath: inventory,
        nmPath: nm,
      ).single;
      expect(row.status, CheckStatus.fail);
      expect(row.notes, contains('4 unexpected TW* exports'));
    });

    test('no llvm-nm is unmeasured, with the command', () {
      final row = measureElfSymbols(
        artifact: '${scratch.path}/$library',
        target: 'android/arm64-v8a',
        inventoryPath: inventory,
      ).single;
      expect(row.status, CheckStatus.unmeasured);
      expect(row.command, contains('llvm-nm --dynamic'));
    });
  });
}
