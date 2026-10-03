// Every check that has a real input on this machine, then the table.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.
//
// This is what `melos run packaging:measure` runs. It knows the standard
// locations of the inputs and nothing about what a build hook or a podspec is:
// it discovers files, measures them, and leaves every check whose input is
// absent as `unmeasured` with the command that will produce it.
//
// Nothing is written inside the repository. The results and the table go under
// $WCF_PACKAGING_OUT, defaulting to $TMPDIR/wcf-packaging.

import 'dart:io';

import 'package:wcf_tool_packaging_eval/cli.dart';
import 'package:wcf_tool_packaging_eval/consumer_gen.dart';
import 'package:wcf_tool_packaging_eval/host.dart';
import 'package:wcf_tool_packaging_eval/measurements.dart';
import 'package:wcf_tool_packaging_eval/report.dart';
import 'package:wcf_tool_packaging_eval/required_reason.dart';
import 'package:wcf_tool_packaging_eval/results.dart';
import 'package:wcf_tool_packaging_eval/xcframework.dart';

const _usage = '''
Usage: dart run tools/packaging_eval/bin/measure_all.dart [--out-dir DIR]

Runs every measurement whose input exists on this machine and prints the
PRD §12.2 table. Inputs it looks for, in this order:

  \$WCF_NATIVE_ALL (default third_party/wcf-native-all)
      a tools/native_build output set: artifacts/<os>/<abi>/<library>, with the
      DECISION-14 §5.1 records next to them. Size, symbols, iOS archive.

  \$WCF_UPSTREAM_CACHE/<tag>/WalletCore.xcframework.zip
      (default ~/.cache/wcf-upstream) upstream's own framework — the library
      upstream users ship today, and a second real input for the iOS checks.

  \$ANDROID_NDK's libc++_shared.so for arm64-v8a and x86_64
      the only real 64-bit ELF on this machine, and the very file PRD §12.2
      step 9's duplicate check is about. Alignment only.

  the workspace pubspecs and `flutter --version`, and a generated hosted
  consumer app (PRD §12.2 step 11).

Options:
  --out-dir DIR        Where results and the table go. Default
                       \$WCF_PACKAGING_OUT, else \$TMPDIR/wcf-packaging.
  --upstream-tag TAG   Default 4.8.0.
  --skip-consumer-gen  Skip step 11 (it runs `flutter create` and
                       `flutter pub get`, which take about a minute).
  -h, --help           This text.
''';

Future<void> main(List<String> arguments) async {
  final args = Args.parse(arguments, switches: {'skip-consumer-gen'});
  if (args.flag('help')) {
    stdout.write(_usage);
    return;
  }

  final environment = Platform.environment;
  final tmp = environment['TMPDIR'] ?? '/tmp';
  final outDirectory = Directory(
    args.option('out-dir') ??
        environment['WCF_PACKAGING_OUT'] ??
        '${tmp.endsWith('/') ? tmp.substring(0, tmp.length - 1) : tmp}'
            '/wcf-packaging',
  )..createSync(recursive: true);

  final root = repoRoot().path;
  final rows = <ResultRow>[];
  final apis = await RequiredReasonApis.load();

  void log(String message) => stderr.writeln('== $message');

  // -- Our artifact set -----------------------------------------------------
  final setRoot = Directory(
    environment['WCF_NATIVE_ALL'] ?? '$root/third_party/wcf-native-all',
  );
  final ourLibraries = _discoverArtifacts(setRoot);
  if (ourLibraries.isEmpty) {
    log('no artifact set under ${setRoot.path}; library rows stay unmeasured');
  }
  for (final entry in ourLibraries) {
    log('artifact ${entry.target}');
    rows
      ..addAll(measureSize(artifact: entry.path, target: entry.target))
      ..addAll(
        measureSymbols(
          artifact: entry.path,
          format: 'macho',
          target: entry.target,
        ),
      )
      ..addAll(
        await measureIosArchive(
          binary: entry.path,
          target: entry.target,
          apis: apis,
        ),
      );
  }

  // -- Upstream's own framework --------------------------------------------
  final cache =
      environment['WCF_UPSTREAM_CACHE'] ??
      '${environment['HOME']}/.cache/wcf-upstream';
  final tag = args.option('upstream-tag') ?? '4.8.0';
  final xcframeworkZip = '$cache/$tag/WalletCore.xcframework.zip';
  final upstreamBinaries = <String>[];
  if (File(xcframeworkZip).existsSync()) {
    final opened = openXcframework(xcframeworkZip);
    try {
      for (final slice in opened.slices) {
        final target = 'upstream/${slice.identifier}';
        log('upstream slice $target');
        upstreamBinaries.add(slice.binaryPath);
        rows
          ..addAll(measureSize(artifact: slice.binaryPath, target: target))
          ..addAll(
            measureSymbols(
              artifact: slice.binaryPath,
              format: 'macho',
              target: target,
              // Upstream's framework carries no wcf_build_info; that is a
              // recorded fact about the library we did not relink, not a
              // failure of a packaging option (DECISION-9 §5).
              expectIdentity: false,
            ),
          )
          ..addAll(
            await measureIosArchive(
              binary: slice.binaryPath,
              target: target,
              apis: apis,
            ),
          );
      }

      // Duplicate symbols across two libraries that would both be linked into
      // one app: our relinked device dylib and upstream's device framework.
      final ourDevice = ourLibraries
          .where((e) => e.target == 'ios/arm64')
          .map((e) => e.path)
          .toList();
      final upstreamDevice = opened.slices
          .where((s) => s.identifier == 'ios-arm64')
          .map((s) => s.binaryPath)
          .toList();
      if (ourDevice.isNotEmpty && upstreamDevice.isNotEmpty) {
        log('duplicate-symbol scan: ours vs upstream, iOS device');
        rows.addAll(
          await measureDuplicateSymbols(
            binaries: [ourDevice.first, upstreamDevice.first],
            target: 'ios/arm64',
          ),
        );
      }
    } finally {
      opened.dispose();
    }
  } else {
    log('no upstream xcframework at $xcframeworkZip');
  }

  // -- 16 KB alignment on the only real ELF here ---------------------------
  for (final abi in const ['arm64-v8a', 'x86_64']) {
    final library = ndkLibcxxShared(abi);
    if (library == null) {
      log('no NDK libc++_shared.so for $abi');
      continue;
    }
    log('alignment ndk/$abi');
    rows.addAll(measureElfAlignment(target: 'ndk/$abi', binary: library));
  }

  // -- Step 6 evidence ------------------------------------------------------
  log('min-version');
  rows.addAll(measureMinVersion(target: 'host/toolchain'));

  // -- Step 11 --------------------------------------------------------------
  if (args.flag('skip-consumer-gen')) {
    log('consumer-gen skipped by request');
  } else {
    log('consumer-gen (flutter create + flutter pub get)');
    final outcome = await generateHostedConsumer(
      outDirectory: Directory('${outDirectory.path}/consumer-gen'),
    );
    rows.addAll(outcome.rows);
    if (outcome.lockExcerpt.isNotEmpty) {
      File(
        '${outDirectory.path}/consumer-pubspec.lock.excerpt',
      ).writeAsStringSync(outcome.lockExcerpt);
    }
  }

  final resultsFile = File('${outDirectory.path}/results.jsonl');
  ResultsFile.write(resultsFile, rows);
  final markdown = renderReport(rows);
  File('${outDirectory.path}/table.md').writeAsStringSync(markdown);

  stdout.write(markdown);
  stderr
    ..writeln()
    ..writeln('${rows.length} result rows -> ${resultsFile.path}')
    ..writeln('table -> ${outDirectory.path}/table.md');
}

class _Artifact {
  const _Artifact(this.target, this.path);

  final String target;
  final String path;
}

/// Every library under `<set>/artifacts/`, with its logical directory as the
/// target. Debug bundles (`.dSYM.zip`) are not manifest artifacts and are not
/// measured.
List<_Artifact> _discoverArtifacts(Directory setRoot) {
  final artifacts = Directory('${setRoot.path}/artifacts');
  if (!artifacts.existsSync()) return const [];
  final found = <_Artifact>[];
  for (final entity in artifacts.listSync(recursive: true)) {
    if (entity is! File) continue;
    final name = entity.path.split(Platform.pathSeparator).last;
    if (name.endsWith('.dSYM.zip') || name.startsWith('.')) continue;
    final relative = entity.path.substring(artifacts.path.length + 1);
    final parts = relative.split(Platform.pathSeparator);
    if (parts.length < 2) continue;
    found.add(
      _Artifact(parts.sublist(0, parts.length - 1).join('/'), entity.path),
    );
  }
  found.sort((a, b) => a.target.compareTo(b.target));
  return found;
}
