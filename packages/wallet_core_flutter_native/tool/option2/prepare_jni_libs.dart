/// Lays out the verified Android libraries as a generated jniLibs directory.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// DECISION-2 Option 2 (evaluation branch, T1.9). Run by the Gradle task
/// `wcfPrepare<Variant>JniLibs` in `android/build.gradle`, never by hand in a
/// normal build:
///
/// ```
/// dart --packages=<app>/.dart_tool/package_config.json \
///     <package>/tool/option2/prepare_jni_libs.dart \
///     --manifest <compat_manifest.json> --out <generated jniLibs dir> \
///     --work <task temporary dir> [--vendored <dir>] [--offline] \
///     [--cache-dir <dir>]
/// ```
///
/// Every `android/<abi>/<file>.so` the manifest lists is obtained through
/// `tool/fetch_artifacts.dart` (see `src/verified_acquisition.dart`) and moved
/// to `<out>/<abi>/<file>.so`. A digest or size mismatch, a blocked manifest,
/// or a missing artifact exits non-zero with the tool's own report, and the
/// Gradle task turns that into a failed build.
///
/// Build time only: nothing here is part of the package's library API and
/// nothing under `lib/` imports it (AGENTS.md rule 3).
library;

import 'dart:convert';
import 'dart:io';

import 'src/jni_libs_plan.dart';
import 'src/verified_acquisition.dart';

Future<void> main(List<String> argv) async {
  exitCode = await prepareJniLibs(argv);
}

/// The command, separated from [main] for tests.
Future<int> prepareJniLibs(
  List<String> argv, {
  String? packageDir,
  Map<String, String>? environment,
}) async {
  final PrepareArgs args;
  try {
    args = PrepareArgs.parse(argv);
  } on FormatException catch (e) {
    stderr.writeln('prepare_jni_libs: ${e.message}');
    return prepareUsageExit;
  }

  final List<JniLibEntry> plan;
  try {
    final decoded = jsonDecode(File(args.manifest).readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      throw JniLibsPlanException('${args.manifest} is not a JSON object');
    }
    plan = jniLibsPlan(decoded);
  } on Object catch (e) {
    stderr.writeln('prepare_jni_libs: ${args.manifest}: $e');
    return preparePlanExit;
  }

  stdout.writeln('wallet_core_flutter_native: packaging for Android');
  for (final entry in plan) {
    stdout.writeln('  $entry');
  }
  for (final abi in abisWithoutLibcxx(plan)) {
    stdout.writeln(
      '  note: no android/$abi/$libcxxSharedName row; correct for a '
      'c++_static artifact, a load failure on $abi for a c++_shared one',
    );
  }

  final code = await acquireVerified(
    packageDir: packageDir ?? packageDirOfScript(),
    args: args,
    logicalNames: [for (final e in plan) e.logicalName],
    environment: environment,
  );
  if (code != 0) {
    stderr.writeln(
      'wallet_core_flutter_native: the native artifacts did not verify '
      'against ${args.manifest} (fetch tool exit $code). Nothing was packaged; '
      'the build stops here.',
    );
    return code;
  }

  final out = Directory(args.out);
  if (out.existsSync()) out.deleteSync(recursive: true);
  for (final entry in plan) {
    final verified = File(
      '${args.work}/${entry.logicalName}'.replaceAll(
        '/',
        Platform.pathSeparator,
      ),
    );
    final target = File(
      '${args.out}/${entry.jniLibsPath}'.replaceAll(
        '/',
        Platform.pathSeparator,
      ),
    );
    target.parent.createSync(recursive: true);
    // A rename, not a copy: the bytes at the target are the bytes the fetch
    // tool verified a moment ago in the same build directory.
    verified.renameSync(target.path);
  }
  stdout.writeln(
    'wallet_core_flutter_native: ${plan.length} verified '
    '${plan.length == 1 ? "library" : "libraries"} in ${args.out}',
  );
  return 0;
}
