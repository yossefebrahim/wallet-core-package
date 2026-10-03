/// Obtaining manifest artifacts for a platform build, through the package's
/// own fetch tool and nothing else.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// DECISION-2 Option 2 (evaluation branch, T1.9). Shared by
/// `tool/option2/prepare_jni_libs.dart` (run by `android/build.gradle`) and
/// `tool/option2/prepare_xcframework.dart` (run by the podspec). Both callers
/// run from the package root, so the build-time Dart lives once, under
/// `tool/`, and outside `android/` and `ios/`, which `flutter pub get`
/// excludes from analysis in this package's `analysis_options.yaml`.
///
/// **No verification is implemented here.** Both passes are
/// `tool/fetch_artifacts.dart` itself, called in process through
/// `runFetchArtifacts`, so the sha256-and-size check, the cache re-hash, the
/// vendored-before-copy rule and the absence of any "accept a mismatch" flag
/// are exactly the tool's (PRD §12.3, threat model TM-14):
///
/// 1. **Acquire** into the shared cache — `--cache-dir`, else
///    `$WCF_ARTIFACT_DIR`, else `~/.cache/wallet_core_flutter/<tag>/` — from a
///    warm cache, a `--vendored` directory, or the network, as the caller's
///    flags allow.
/// 2. **Copy out** into a work directory that belongs to this run alone, with
///    the shared cache as the `--vendored` source and `--offline`: the tool
///    verifies each file before it copies it and again after, so the bytes the
///    build consumes were checked at the moment they arrived in that
///    directory, not at some earlier moment in a directory other processes
///    share.
///
/// The caller then *renames* the verified file into place (same file system,
/// no further copy). The work directory is only as private as the caller
/// makes it: on Android it is Gradle's per-task `temporaryDir`, inside the
/// app's build; on iOS the pod directory is shared by every app using the
/// package (for a hosted package, the pub-cache copy), so
/// `prepare_xcframework.dart` holds an exclusive lock for the whole
/// prepare-and-stamp step and passes a fresh `run-*` directory of its own
/// ([PrepareArgs.withWork]).
library;

import 'dart:io';

import '../../src/fetcher.dart' show resolveCacheDir, runFetchArtifacts;
import '../../src/manifest.dart' show FetchManifest;

/// Exit code for a command line the prepare step does not understand. The same
/// value the fetch tool uses.
const int prepareUsageExit = 64;

/// Exit code for a manifest the platform plan cannot use. The same value the
/// fetch tool uses for a manifest it cannot fetch from.
const int preparePlanExit = 2;

/// The command line shared by both prepare steps.
final class PrepareArgs {
  PrepareArgs._({
    required this.manifest,
    required this.out,
    required this.work,
    required this.vendored,
    required this.cacheDir,
    required this.offline,
    required this.extra,
  });

  /// `--manifest`: the compat manifest to plan from and verify against.
  final String manifest;

  /// `--out`: the directory the platform build consumes. Replaced wholesale.
  final String out;

  /// `--work`: a directory on the same file system as [out]. The copy-out
  /// pass writes into it directly, so it must not be shared with a concurrent
  /// run; a caller whose `--work` is shared narrows it with [withWork].
  final String work;

  /// `--vendored`: passed to the acquire pass.
  final String? vendored;

  /// `--cache-dir`: passed to the acquire pass; the shared cache.
  final String? cacheDir;

  /// `--offline`: passed to the acquire pass. The copy-out pass is always
  /// offline.
  final bool offline;

  /// Platform-specific single-valued options, by name without the dashes.
  final Map<String, String> extra;

  /// These arguments with [work] in place of `--work`.
  PrepareArgs withWork(String work) => PrepareArgs._(
    manifest: manifest,
    out: out,
    work: work,
    vendored: vendored,
    cacheDir: cacheDir,
    offline: offline,
    extra: extra,
  );

  /// Parses [args]. [extraOptions] names the platform's own value options.
  /// Throws [FormatException] for anything else.
  static PrepareArgs parse(
    List<String> args, {
    Set<String> extraOptions = const {},
  }) {
    final values = <String, String>{};
    var offline = false;
    const known = {'manifest', 'out', 'work', 'vendored', 'cache-dir'};
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--offline') {
        offline = true;
        continue;
      }
      if (!arg.startsWith('--')) {
        throw FormatException('unexpected argument "$arg"');
      }
      final name = arg.substring(2);
      if (!known.contains(name) && !extraOptions.contains(name)) {
        throw FormatException('unknown option "$arg"');
      }
      if (i + 1 >= args.length || args[i + 1].isEmpty) {
        throw FormatException('$arg needs a value');
      }
      if (values.containsKey(name)) {
        throw FormatException('$arg may be given once');
      }
      values[name] = args[++i];
    }
    for (final required in const ['manifest', 'out', 'work']) {
      if (!values.containsKey(required)) {
        throw FormatException('--$required is required');
      }
    }
    return PrepareArgs._(
      manifest: values['manifest']!,
      out: values['out']!,
      work: values['work']!,
      vendored: values['vendored'],
      cacheDir: values['cache-dir'],
      offline: offline,
      extra: {
        for (final name in extraOptions)
          if (values.containsKey(name)) name: values[name]!,
      },
    );
  }
}

/// Runs the two passes for [logicalNames] and returns the fetch tool's exit
/// code: 0 when every file is verified at `<work>/<logical name>`.
///
/// [packageDir] is the root of `wallet_core_flutter_native`; the fetch tool's
/// own directory is `<packageDir>/tool`.
Future<int> acquireVerified({
  required String packageDir,
  required PrepareArgs args,
  required List<String> logicalNames,
  Map<String, String>? environment,
  void Function(String line)? out,
  void Function(String line)? err,
}) async {
  final env = environment ?? Platform.environment;
  final scriptDir = '$packageDir${Platform.pathSeparator}tool';
  final only = [
    for (final name in logicalNames) ...['--only', name],
  ];

  final acquired = await runFetchArtifacts(
    [
      '--manifest',
      args.manifest,
      ...only,
      if (args.vendored != null) ...['--vendored', args.vendored!],
      if (args.cacheDir != null) ...['--cache-dir', args.cacheDir!],
      if (args.offline) '--offline',
    ],
    scriptDir: scriptDir,
    environment: env,
    out: out,
    err: err,
  );
  if (acquired != 0) return acquired;

  // The directory the acquire pass just used, resolved by the tool's own
  // function so the two cannot disagree about where the shared cache is.
  final shared = resolveCacheDir(
    manifest: FetchManifest.parse(
      File(args.manifest).readAsStringSync(),
      source: args.manifest,
    ),
    override: args.cacheDir,
    environment: env,
  );

  return runFetchArtifacts(
    [
      '--manifest',
      args.manifest,
      ...only,
      '--cache-dir',
      args.work,
      '--vendored',
      shared,
      '--offline',
    ],
    scriptDir: scriptDir,
    environment: env,
    out: out,
    err: err,
  );
}

/// The root of `wallet_core_flutter_native`, derived from the running script's
/// location: `<package>/tool/option2/<script>.dart` → `<package>`.
String packageDirOfScript() =>
    File.fromUri(Platform.script).parent.parent.parent.path;
