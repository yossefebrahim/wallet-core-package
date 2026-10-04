/// Obtaining one verified artifact for the hook, through the build-time fetch
/// tool's own code.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// **Two checks, one digest.** The hook calls `runFetchArtifacts` from
/// `tool/src/fetcher.dart` (T1.7b) with `--only <logical name>`; that returns
/// 0 only when the file at the cache path hashed to the manifest's sha256 at
/// the manifest's size. Every source goes through that check: a warm cache is
/// re-hashed, a vendored file is verified before it is copied, a download is
/// verified before it is renamed into place, and there is no option,
/// user-define or environment variable that accepts a mismatch (PRD §12.3,
/// threat model TM-14).
///
/// The fetch tool's verdict is about the file *as it was* when it hashed it.
/// The cache path carries no set id, so a `cache_dir` shared between apps
/// pinning different manifests — or any other local writer — can replace the
/// file between that verdict and the hook's read (review finding 1, T1.8a-d4).
/// [acquireArtifact] therefore reads the file once, hashes **those bytes**
/// against the sha256 and size the hook itself parsed from the manifest, and
/// returns them; the hook bundles only bytes that passed this second check and
/// never opens the cache path again.
///
/// **Network rule.** The hook may download, and only like this: when neither
/// the verified cache nor the vendored directory holds the artifact, from the
/// manifest's own DECISION-14 §3.1 content-addressed URLs (`retention.primary`,
/// then `retention.mirror` when non-null), over HTTPS only, verified before
/// use. PRD §12.3 puts the fetch at consumer build time and §16 S4 allows
/// build-time network in the native package's hook. `offline: true` in the
/// app's user-defines removes the network from that list entirely; the build
/// then succeeds only from the cache or the vendored directory. Nothing here
/// runs at app run time.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../tool/src/fetcher.dart' as fetcher;

/// The fetch tool's entry point, as a type, so tests can substitute a fake.
typedef FetchRunner = Future<int> Function(
  List<String> args, {
  required String scriptDir,
  Map<String, String>? environment,
  void Function(String line)? out,
  void Function(String line)? err,
});

/// What the hook asks the fetch tool for.
final class AcquireRequest {
  const AcquireRequest({
    required this.logicalName,
    required this.manifestPath,
    required this.cacheDir,
    required this.toolDir,
    required this.sha256,
    required this.size,
    this.vendoredDir,
    this.offline = false,
  });

  /// The manifest key of the artifact.
  final String logicalName;
  final String manifestPath;

  /// The artifact's sha256 and size as the hook parsed them from
  /// [manifestPath]: what the bytes it bundles must hash to.
  final String sha256;
  final int size;
  final String cacheDir;

  /// The package's `tool/` directory; the fetch tool's `scriptDir`.
  final String toolDir;
  final String? vendoredDir;
  final bool offline;

  /// The fetch tool command line this request is.
  ///
  /// `--manifest` and `--cache-dir` are always explicit, so neither the fetch
  /// tool's default manifest nor `WCF_ARTIFACT_DIR`/`HOME` decides anything
  /// inside a hook.
  List<String> get arguments => [
    '--manifest',
    manifestPath,
    '--cache-dir',
    cacheDir,
    '--only',
    logicalName,
    if (vendoredDir != null) ...['--vendored', vendoredDir!],
    if (offline) '--offline',
  ];

  /// The same command, runnable by hand from the package directory.
  String get commandLine =>
      'dart run tool/fetch_artifacts.dart ${arguments.map(_quote).join(' ')}';
}

String _quote(String s) =>
    RegExp(r'^[A-Za-z0-9_./:=+@-]+$').hasMatch(s) ? s : "'$s'";

/// The artifact could not be verified into the cache. [message] is the whole
/// build-failure text.
final class AcquireError implements Exception {
  const AcquireError(this.message, {required this.exitCode});

  final String message;

  /// The fetch tool's exit code: 1 fetch or verification failed, 2 manifest
  /// blocked, 64 usage.
  final int exitCode;

  @override
  String toString() => message;
}

/// The result of a successful acquisition.
final class Acquired {
  const Acquired({
    required this.cachePath,
    required this.bytes,
    required this.log,
  });

  /// Where the fetch tool verified the file. A dependency of the build, not a
  /// source of bytes: the file may have changed since [bytes] were read.
  final String cachePath;

  /// The artifact, read once from [cachePath] and verified in memory against
  /// the request's sha256 and size. The only bytes the hook may bundle.
  final Uint8List bytes;

  /// The fetch tool's output, for the hook's own log.
  final List<String> log;
}

/// Runs the fetch tool for [request], then reads the cache file once and
/// returns its bytes after hashing them against [AcquireRequest.sha256] and
/// [AcquireRequest.size].
///
/// Throws [AcquireError] with an actionable message otherwise — including when
/// the fetch tool succeeded but the bytes read afterwards are not the
/// artifact. The fetch tool runs with an **empty** environment: the hook has
/// already resolved every path it needs, and nothing inherited may change
/// which file is trusted.
Future<Acquired> acquireArtifact(
  AcquireRequest request, {
  FetchRunner run = fetcher.runFetchArtifacts,
  required String Function(String cacheDir, String logicalName) cachePathFor,
}) async {
  final out = <String>[];
  final err = <String>[];
  final code = await run(
    request.arguments,
    scriptDir: request.toolDir,
    environment: const <String, String>{},
    out: out.add,
    err: err.add,
  );
  if (code != fetcher.exitOk) {
    throw AcquireError(
      failureMessage(request, code, out: out, err: err),
      exitCode: code,
    );
  }
  final cachePath = cachePathFor(request.cacheDir, request.logicalName);
  final Uint8List bytes;
  try {
    bytes = File(cachePath).readAsBytesSync();
  } on FileSystemException catch (e) {
    throw AcquireError(
      _changedAfterVerification(request, cachePath, 'it could not be read: $e'),
      exitCode: fetcher.exitFetchFailed,
    );
  }
  final digest = sha256.convert(bytes).toString();
  if (digest != request.sha256 || bytes.length != request.size) {
    throw AcquireError(
      _changedAfterVerification(
        request,
        cachePath,
        'the bytes read from it hash to sha256 $digest size ${bytes.length}',
        found: (digest: digest, size: bytes.length),
      ),
      exitCode: fetcher.exitFetchFailed,
    );
  }
  return Acquired(cachePath: cachePath, bytes: bytes, log: out);
}

/// The failure text for a cache file that the fetch tool verified and that
/// was no longer the artifact when the hook read it.
String _changedAfterVerification(
  AcquireRequest request,
  String cachePath,
  String what, {
  ({String digest, int size})? found,
}) {
  final b = StringBuffer();
  if (found != null) {
    b.writeln(
      'error: wallet_core_flutter_native: ${request.logicalName}: sha256 '
      'mismatch: expected ${request.sha256} (${request.size} bytes), found '
      '${found.digest} (${found.size} bytes) from cache file $cachePath read '
      'after verification; nothing was bundled',
    );
  } else {
    b.writeln(
      'error: wallet_core_flutter_native: ${request.logicalName}: the '
      'verified cache file $cachePath could not be read; nothing was bundled',
    );
  }
  b.writeln(
    'wallet_core_flutter_native: ${request.logicalName} was verified at '
    '$cachePath against ${request.manifestPath}, but $what — not sha256 '
    '${request.sha256} size ${request.size}. Something replaced the file '
    'between the check and the read: another build sharing this cache_dir '
    '(possibly pinning a different manifest), or another writer. Nothing was '
    'bundled.',
  );
  b.writeln();
  b.writeln(
    'Give this app a cache_dir no other build or user writes to (the default, '
    'the hook\'s own output directory, is per app), and rebuild.',
  );
  b.writeln();
  b.writeln('Reproduce outside the build, from the package directory:');
  b.write('  ${request.commandLine}');
  return b.toString();
}

/// The text a failed acquisition fails the build with.
///
/// Leads with what failed and for which artifact, then the fetch tool's own
/// lines verbatim — which, for a digest or size mismatch, carry the source,
/// the expected and the found sha256 and size — then what to do about it.
/// The single `error:` line for a digest or size mismatch, built from the
/// fetch tool's `expected sha256 … size …` / `found    sha256 … size …` lines
/// (the last pair, which is the source that was tried last), or `null` when
/// [detail] holds no such pair.
String? xcodeErrorLine(String logicalName, List<String> detail) {
  final expected = RegExp(r'expected sha256 (\S+) size (\d+)');
  final found = RegExp(r'found +sha256 (\S+) size (\d+)');
  RegExpMatch? want;
  RegExpMatch? got;
  String? source;
  for (final line in detail) {
    final trimmed = line.trim();
    final e = expected.firstMatch(trimmed);
    final f = found.firstMatch(trimmed);
    if (e != null) {
      want = e;
    } else if (f != null) {
      got = f;
    } else if (trimmed.startsWith('vendored ') ||
        trimmed.startsWith('primary ') ||
        trimmed.startsWith('mirror ') ||
        trimmed.startsWith('copy of ')) {
      source = trimmed;
    }
  }
  if (want == null || got == null) return null;
  return 'error: wallet_core_flutter_native: $logicalName: sha256 mismatch: '
      'expected ${want[1]} (${want[2]} bytes), found ${got[1]} '
      '(${got[2]} bytes)${source == null ? '' : ' from $source'}; '
      'nothing was bundled';
}

String failureMessage(
  AcquireRequest request,
  int code, {
  required List<String> out,
  required List<String> err,
}) {
  final b = StringBuffer();
  final headline = switch (code) {
    fetcher.exitFetchFailed =>
      'wallet_core_flutter_native: ${request.logicalName} could not be '
          'verified against ${request.manifestPath}; nothing was bundled.',
    fetcher.exitManifestBlocked =>
      'wallet_core_flutter_native: ${request.manifestPath} cannot supply '
          '${request.logicalName}; nothing was bundled.',
    _ =>
      'wallet_core_flutter_native: the artifact fetch failed with exit code '
          '$code for ${request.logicalName}; nothing was bundled.',
  };
  final detail = [
    ...out.where((l) => l.trim().isNotEmpty),
    ...err.where((l) => l.trim().isNotEmpty),
  ];
  // The first line is the one an iOS or macOS build keeps. Xcode surfaces
  // only lines that carry `error:` from a failed build phase, so without this
  // line a consumer sees the fetch tool's "could not be verified; stopping"
  // summary and neither digest (measured, T1.8a delta 3). On a mismatch this
  // one line carries the artifact, both digests and both sizes.
  b.writeln(xcodeErrorLine(request.logicalName, detail) ?? 'error: $headline');
  b.writeln(headline);
  if (detail.isNotEmpty) {
    b.writeln();
    for (final line in detail) {
      b.writeln('  $line');
    }
  }
  b.writeln();

  final mismatch = detail.any((l) => l.contains('expected sha256'));
  if (code == fetcher.exitFetchFailed && mismatch) {
    b.writeln(
      'The file is not the artifact the manifest pins. This is never '
      'overridable: replace the file with the published one, or fix the '
      'manifest if it is the manifest that is wrong.',
    );
  } else if (code == fetcher.exitManifestBlocked) {
    b.writeln(
      'No artifact set has been published for this manifest yet, so there is '
      'nothing to download and no digest to verify a local file against. To '
      'build with a locally built, digest-pinned set instead, point the hook '
      'at a manifest that pins it and at the files, in the app\'s '
      'pubspec.yaml:',
    );
    b.writeln();
    b.writeln(_snippet);
  } else if (code == fetcher.exitFetchFailed) {
    b.writeln(
      request.offline
          ? 'offline is set, so only the cache and vendored_dir were tried. '
                'Pre-populate vendored_dir (laid out by logical name), or '
                'remove offline to allow the download.'
          : 'Nothing verifiable could be obtained. Check network access to the '
                'URLs above, or build offline from a vendored directory:',
    );
    if (!request.offline) {
      b.writeln();
      b.writeln(_snippet);
    }
  }
  b.writeln();
  b.writeln('Reproduce outside the build, from the package directory:');
  b.write('  ${request.commandLine}');
  return b.toString();
}

const String _snippet = '''
  hooks:
    user_defines:
      wallet_core_flutter_native:
        manifest: <a compat_manifest.json whose artifacts carry sha256 + size>
        vendored_dir: <directory laid out by logical name>
        offline: true''';
