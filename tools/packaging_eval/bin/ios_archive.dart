// PRD §12.2 step 10 — deployment target, visibility, duplicate symbols,
// install name, signing state, and the required-reason API scan.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.

import 'dart:io';

import 'package:wcf_tool_packaging_eval/cli.dart';
import 'package:wcf_tool_packaging_eval/measurements.dart';
import 'package:wcf_tool_packaging_eval/results.dart';
import 'package:wcf_tool_packaging_eval/xcframework.dart';

const _usage = r'''
Usage: dart run tools/packaging_eval/bin/ios_archive.dart --binary FILE \
           --target ID
       dart run tools/packaging_eval/bin/ios_archive.dart \
           --xcframework FILE.zip|DIR [--target-prefix ID]
       dart run tools/packaging_eval/bin/ios_archive.dart \
           --duplicate-scan LIB --duplicate-scan LIB --target ID

Measures, per architecture of a Mach-O:

  vtool -arch <arch> -show-build <binary>   minimum deployment target
                                            (LC_BUILD_VERSION / LC_VERSION_MIN_*)
  nm -gU  -arch <arch> <binary>             exported symbols: count, TW* count,
                                            wcf_build_info present
  nm -u   -arch <arch> <binary>             imported symbols, scanned against
                                            Apple's required-reason API
                                            categories (lib/required_reason_apis.json)
  otool -D -arch <arch> <binary>            install name
  otool -l -arch <arch> <binary>            LC_RPATH entries
  otool -L -arch <arch> <binary>            linked libraries
  codesign -dv <binary>                     signing state — recorded, never a
                                            failure: our relinked dylibs are
                                            expected unsigned and signing is
                                            the packaging option's to do

and, across a set of libraries that would both be linked into one app, the
symbols defined in more than one of them. That scan is streamed and hashed:
an upstream-style build exports on the order of 57 174 names per slice
(DECISION-9 §5), so it is O(n log n) and never a pairwise comparison.

A required-reason hit means the app that links this library needs a
`PrivacyInfo.xcprivacy` declaring a reason for that category.

Options:
  --binary FILE          A dylib or a framework binary. Repeatable.
  --xcframework PATH     A .xcframework directory or .zip; every slice is
                         measured, each as its own target.
  --target ID            The column the rows land in.
  --target-prefix ID     For --xcframework: targets are `<prefix>/<slice>`.
                         Default `upstream`.
  --duplicate-scan FILE  Add a library to the duplicate-symbol scan.
                         Repeatable; needs at least two.
  --out FILE             Append the JSON result rows to FILE.
  -h, --help             This text.

Archive-link (`xcodebuild archive` of a consumer app) is the evaluations' step,
not this harness's; `report` carries that row as `unmeasured` with its command.
''';

Future<void> main(List<String> arguments) async {
  final args = Args.parse(arguments);
  if (args.flag('help')) {
    stdout.write(_usage);
    return;
  }

  final binaries = args.options('binary');
  final xcframeworks = args.options('xcframework');
  final duplicates = args.options('duplicate-scan');
  if (binaries.isEmpty && xcframeworks.isEmpty && duplicates.isEmpty) {
    stdout.write(_usage);
    stderr.writeln('error: give --binary, --xcframework or --duplicate-scan');
    exit(2);
  }

  final targets = args.options('target');
  final rows = <ResultRow>[];

  for (var i = 0; i < binaries.length; i++) {
    final target = targets.length == binaries.length
        ? targets[i]
        : (targets.isEmpty ? binaries[i] : targets.first);
    rows.addAll(await measureIosArchive(binary: binaries[i], target: target));
  }

  for (final path in xcframeworks) {
    final opened = openXcframework(path);
    try {
      for (final slice in opened.slices) {
        rows.addAll(
          await measureIosArchive(
            binary: slice.binaryPath,
            target:
                '${args.option('target-prefix') ?? 'upstream'}/'
                '${slice.identifier}',
          ),
        );
      }
    } finally {
      opened.dispose();
    }
  }

  if (duplicates.isNotEmpty) {
    rows.addAll(
      await measureDuplicateSymbols(
        binaries: duplicates,
        target: targets.isEmpty ? duplicates.first : targets.first,
      ),
    );
  }

  emit(rows, args.option('out'));
}
