/// Command-line surface of `tool/fetch_artifacts.dart`.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// Hand-rolled rather than `package:args`, so the build-time tool adds no
/// dependency to `wallet_core_flutter_native` beyond `crypto` — a package a
/// consumer resolves in order to build an application should not grow a
/// dependency for the sake of a flag parser.
library;

/// The user got the invocation wrong. Carries the message the tool prints
/// before the usage text.
final class UsageException implements Exception {
  UsageException(this.message);

  /// What was wrong with the command line.
  final String message;

  @override
  String toString() => message;
}

/// A parsed command line.
final class FetchOptions {
  const FetchOptions({
    required this.manifestPath,
    required this.cacheDirOverride,
    required this.only,
    required this.offline,
    required this.vendoredDir,
    required this.dryRun,
    required this.keepGoing,
    required this.allowInsecureLoopback,
    required this.help,
  });

  /// `--manifest`, or the package's own `assets/compat_manifest.json`.
  final String manifestPath;

  /// `--cache-dir`, or null to fall back to `WCF_ARTIFACT_DIR` and then to
  /// `~/.cache/wallet_core_flutter/<upstream.tag>/`.
  final String? cacheDirOverride;

  /// `--only`, repeatable. Empty means every artifact in the manifest.
  final List<String> only;

  /// `--offline`: never open a socket.
  final bool offline;

  /// `--vendored`: a directory laid out by logical name.
  final String? vendoredDir;

  /// `--dry-run` (or its alias `--print-urls`).
  final bool dryRun;

  /// `--keep-going`: report every artifact's failure instead of stopping at
  /// the first. The exit code is still non-zero.
  final bool keepGoing;

  /// `--allow-insecure-loopback`: test-only, see [helpText].
  final bool allowInsecureLoopback;

  /// `--help`.
  final bool help;

  /// Parses [args]. Throws [UsageException] for anything it does not
  /// understand, an option that needs a value and did not get one, or a
  /// repeated single-valued option.
  static FetchOptions parse(
    List<String> args, {
    required String defaultManifestPath,
  }) {
    String? manifest;
    String? cacheDir;
    String? vendored;
    final only = <String>[];
    var offline = false;
    var dryRun = false;
    var keepGoing = false;
    var allowInsecureLoopback = false;
    var help = false;

    // An explicit index rather than a `for` loop: `takeValue` consumes the
    // next argument, and a closure that advances the loop's own counter is a
    // thing a reader has to think about.
    var i = 0;
    while (i < args.length) {
      final arg = args[i];
      String? inlineValue;
      var name = arg;
      final eq = arg.indexOf('=');
      if (arg.startsWith('--') && eq > 2) {
        name = arg.substring(0, eq);
        inlineValue = arg.substring(eq + 1);
      }

      String takeValue() {
        if (inlineValue != null) return inlineValue;
        if (i + 1 >= args.length) {
          throw UsageException('$name needs a value');
        }
        return args[++i];
      }

      void refuseValue() {
        if (inlineValue != null) throw UsageException('$name takes no value');
      }

      switch (name) {
        case '--help':
        case '-h':
          refuseValue();
          help = true;
        case '--manifest':
          if (manifest != null) {
            throw UsageException('--manifest may be given once');
          }
          manifest = takeValue();
        case '--cache-dir':
          if (cacheDir != null) {
            throw UsageException('--cache-dir may be given once');
          }
          cacheDir = takeValue();
        case '--vendored':
          if (vendored != null) {
            throw UsageException('--vendored may be given once');
          }
          vendored = takeValue();
        case '--only':
          only.add(takeValue());
        case '--offline':
          refuseValue();
          offline = true;
        case '--dry-run':
        case '--print-urls':
          refuseValue();
          dryRun = true;
        case '--keep-going':
          refuseValue();
          keepGoing = true;
        case '--allow-insecure-loopback':
          refuseValue();
          allowInsecureLoopback = true;
        default:
          throw UsageException('unknown option: $arg');
      }
      i++;
    }

    if (manifest != null && manifest.isEmpty) {
      throw UsageException('--manifest needs a path');
    }
    if (cacheDir != null && cacheDir.isEmpty) {
      throw UsageException('--cache-dir needs a path');
    }
    if (vendored != null && vendored.isEmpty) {
      throw UsageException('--vendored needs a directory');
    }
    if (only.any((o) => o.isEmpty)) {
      throw UsageException('--only needs an artifact logical name');
    }

    return FetchOptions(
      manifestPath: manifest ?? defaultManifestPath,
      cacheDirOverride: cacheDir,
      only: List<String>.unmodifiable(only),
      offline: offline,
      vendoredDir: vendored,
      dryRun: dryRun,
      keepGoing: keepGoing,
      allowInsecureLoopback: allowInsecureLoopback,
      help: help,
    );
  }
}

/// The `--help` output.
const String helpText = '''
fetch_artifacts.dart — download and verify the native artifacts named by
compat_manifest.json (PRD §12.3, DECISION-14 §3.1).

Build-time tooling. Nothing here runs in an application; the SDK, the bindings,
and this package's lib/ never open a socket (AGENTS.md rule 3, PRD §16 S4).

Usage:
  dart run packages/wallet_core_flutter_native/tool/fetch_artifacts.dart [options]

Options:
  --manifest <path>     The compat_manifest.json to read.
                        Default: this package's assets/compat_manifest.json.
  --cache-dir <path>    Where verified artifacts are kept.
                        Default: \$WCF_ARTIFACT_DIR if set, otherwise
                        ~/.cache/wallet_core_flutter/<upstream.tag>/.
  --only <logical_name> Fetch just this artifact. Repeatable. Default: all.
  --offline             Never open a socket. Succeeds only from the cache (and
                        from --vendored), and names what is missing otherwise.
  --vendored <dir>      A directory laid out by logical name, pre-populated by
                        the consumer. Each file is verified against the
                        manifest exactly as a download is, before it is copied
                        into the cache. Tried before the network; combine with
                        --offline for an air-gapped build.
  --dry-run             Print, per artifact, the primary URL, the mirror URL or
                        "no mirror", the cache path and the cache state, and
                        exit without touching the network.
  --print-urls          Alias of --dry-run.
  --keep-going          Report every artifact instead of stopping at the first
                        failure. The exit code is still non-zero.
  --allow-insecure-loopback
                        TEST ONLY. Permits plain http, and only to 127.0.0.1,
                        ::1, or localhost, so the test suite can serve a fake
                        artifact set from a loopback HttpServer. Refused for
                        any other host. Never needed, and never correct, for a
                        real artifact set.
  -h, --help            This text.

Verification:
  Every artifact is verified against the manifest's 64-hex sha256 and its
  recorded size, whatever served the bytes and whether they came from the
  network, the cache, or --vendored. There is no flag that accepts a mismatch.
  A file that fails is deleted; a download in flight lands on a temporary name
  inside the cache directory and is renamed into place only after it verifies,
  so a failed or interrupted run never leaves a wrong byte at the cache path.

Exit codes:
  0   every requested artifact is verified in the cache
  1   a download, a verification, or a vendored copy failed
  2   the manifest cannot be fetched from (see the blockers it prints)
  64  the command line was wrong
''';
