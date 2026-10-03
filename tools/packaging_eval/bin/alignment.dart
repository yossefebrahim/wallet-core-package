// PRD §12.2 step 8 — 16 KB page alignment, in the ELF and in the package.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.

import 'dart:io';

import 'package:wcf_tool_packaging_eval/cli.dart';
import 'package:wcf_tool_packaging_eval/measurements.dart';
import 'package:wcf_tool_packaging_eval/results.dart';

const _usage = r'''
Usage: dart run tools/packaging_eval/bin/alignment.dart --binary FILE.so \
           --target ID
       dart run tools/packaging_eval/bin/alignment.dart --apk FILE.apk \
           --target ID

Two halves of one requirement. A 16 KB-page Android device will not load a
library whose LOAD segments are 4 KB-aligned, and it will not load one that the
APK stored off a 16 KB boundary either — both have to hold.

  ELF segments, by calling the build's own gate:
      tools/native_build/check_alignment.sh --binary <so> --readelf <llvm-readelf>
    every LOAD program header's Align must read 0x4000.

  APK/AAB packaging:
      zipalign -c -P 16 -v 4 <apk>
    `-P 16` is the flag that checks uncompressed .so entries against 16 KB
    boundaries; `zipalign -c 4` alone passes an APK a 16 KB device refuses.

Options:
  --binary FILE          The .so to check.
  --apk FILE             The .apk/.aab to check.
  --target ID            The column the row lands in.
  --readelf PATH         llvm-readelf. Defaults to the NDK's copy; neither
                         readelf nor llvm-readelf is on PATH on macOS.
  --readelf-output FILE  Check a saved `llvm-readelf -l` output instead of
                         running the tool (how the parser is tested where no
                         Android build exists).
  --zipalign PATH        zipalign. Defaults to the highest installed
                         $ANDROID_HOME/build-tools/<version>/zipalign.
  --zipalign-output FILE Parse a saved `zipalign -c -P 16 -v 4` output.
  --out FILE             Append the JSON result rows to FILE.
  -h, --help             This text.

A 32-bit ELF is reported `skip`: the requirement is on 64-bit ABIs.
''';

void main(List<String> arguments) {
  final args = Args.parse(arguments);
  if (args.flag('help')) {
    stdout.write(_usage);
    return;
  }

  final binary = args.option('binary');
  final readelfOutput = args.option('readelf-output');
  final apk = args.option('apk');
  final zipalignOutput = args.option('zipalign-output');
  final target = args.option('target');

  if (binary == null &&
      readelfOutput == null &&
      apk == null &&
      zipalignOutput == null) {
    stdout.write(_usage);
    stderr.writeln(
      'error: give --binary, --readelf-output, --apk or --zipalign-output',
    );
    exit(2);
  }

  final rows = <ResultRow>[];
  if (binary != null || readelfOutput != null) {
    rows.addAll(
      measureElfAlignment(
        target: target ?? binary ?? readelfOutput!,
        binary: binary,
        readelfOutput: readelfOutput,
        readelfPath: args.option('readelf'),
      ),
    );
  }
  if (apk != null || zipalignOutput != null) {
    rows.addAll(
      measureApkAlignment(
        target: target ?? apk ?? zipalignOutput!,
        apk: apk,
        zipalignOutput: zipalignOutput,
        zipalignBinary: args.option('zipalign'),
      ),
    );
  }

  emit(rows, args.option('out'));
}
