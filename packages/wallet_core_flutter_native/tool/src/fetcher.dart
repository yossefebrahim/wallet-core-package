/// The build-time artifact fetch of PRD §12.3: acquire, verify, cache.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// Build-time only. Nothing in this directory is part of the package's library
/// API and nothing under `lib/` imports it (AGENTS.md rule 3, PRD §16 S4).
///
/// The one invariant everything else serves: **a wrong byte never reaches the
/// cache path.** Bytes land on a temporary name inside the cache directory —
/// the same filesystem, so the final `rename` is atomic — and are moved into
/// place only after the sha256 and the size both match the manifest. A cached
/// file is re-hashed before it is trusted, and a cached file that does not
/// match is deleted rather than reused. There is no flag, and no environment
/// variable, that accepts a mismatch (threat model TM-14).
library;

import 'dart:io';

import 'package:crypto/crypto.dart';

import 'asset_names.dart';
import 'manifest.dart';
import 'options.dart';

/// Exit code: every requested artifact is verified in the cache.
const int exitOk = 0;

/// Exit code: a download, a verification, or a vendored copy failed.
const int exitFetchFailed = 1;

/// Exit code: the manifest cannot be fetched from.
const int exitManifestBlocked = 2;

/// Exit code: the command line was wrong.
const int exitUsage = 64;

/// How many redirects a download may follow. See the header comment of
/// `fetch_artifacts.dart` for why it follows any.
const int maxRedirects = 5;

/// What the cache holds for an artifact.
enum CacheState {
  /// The file is there and hashes to the manifest's digest at the manifest's
  /// size.
  verified,

  /// There is no file at the cache path.
  missing,

  /// There is a file and it is not the artifact. It is deleted on sight.
  corrupt,
}

/// The command's entry point, separated from `main` so tests can drive it with
/// their own script directory, environment, and output sink.
///
/// [scriptDir] is the directory holding `fetch_artifacts.dart`; the default
/// manifest is `../assets/compat_manifest.json` relative to it. Returns the
/// process exit code.
Future<int> runFetchArtifacts(
  List<String> args, {
  required String scriptDir,
  Map<String, String>? environment,
  void Function(String line)? out,
  void Function(String line)? err,
}) async {
  final write = out ?? (String line) => stdout.writeln(line);
  final writeError = err ?? (String line) => stderr.writeln(line);
  final env = environment ?? Platform.environment;

  final FetchOptions options;
  try {
    options = FetchOptions.parse(
      args,
      defaultManifestPath: defaultManifestPath(scriptDir),
    );
  } on UsageException catch (e) {
    writeError('error: ${e.message}');
    writeError('');
    writeError(helpText);
    return exitUsage;
  }

  if (options.help) {
    write(helpText);
    return exitOk;
  }

  final manifestFile = File(options.manifestPath);
  if (!manifestFile.existsSync()) {
    writeError('error: no manifest at ${options.manifestPath}');
    return exitManifestBlocked;
  }
  final FetchManifest manifest;
  try {
    manifest = FetchManifest.parse(
      manifestFile.readAsStringSync(),
      source: options.manifestPath,
    );
  } on FormatException catch (e) {
    writeError('error: ${e.message}');
    return exitManifestBlocked;
  }

  final selected = options.only.isEmpty
      ? manifest.artifacts.keys.toList()
      : options.only;
  if (options.only.isNotEmpty) {
    final unknown = options.only
        .where((o) => !manifest.artifacts.containsKey(o))
        .toList();
    if (unknown.isNotEmpty) {
      writeError('error: --only names artifacts the manifest does not have:');
      for (final name in unknown) {
        writeError('  $name');
      }
      writeError('the manifest lists:');
      for (final name in manifest.artifacts.keys) {
        writeError('  $name');
      }
      return exitUsage;
    }
  }

  final String cacheDir;
  try {
    cacheDir = resolveCacheDir(
      manifest: manifest,
      override: options.cacheDirOverride,
      environment: env,
    );
  } on StateError catch (e) {
    writeError('error: ${e.message}');
    return exitManifestBlocked;
  }

  final blockers = manifestBlockers(
    manifest,
    selected: selected,
    allowInsecureLoopback: options.allowInsecureLoopback,
  );

  if (options.dryRun) {
    return _dryRun(
      manifest: manifest,
      selected: selected,
      cacheDir: cacheDir,
      blockers: blockers,
      options: options,
      write: write,
    );
  }

  if (blockers.isNotEmpty) {
    writeError(
      'error: ${options.manifestPath} cannot be fetched from '
      '(${blockers.length} ${blockers.length == 1 ? "blocker" : "blockers"}):',
    );
    for (final blocker in blockers) {
      writeError('  $blocker');
    }
    writeError('');
    writeError(
      'Nothing was downloaded. Run with --dry-run to see the same report '
      'alongside the cache state.',
    );
    return exitManifestBlocked;
  }

  return _fetchAll(
    manifest: manifest,
    selected: selected,
    cacheDir: cacheDir,
    options: options,
    write: write,
    writeError: writeError,
  );
}

/// The package's own `assets/compat_manifest.json`, located relative to
/// [scriptDir] (the directory holding `fetch_artifacts.dart`).
String defaultManifestPath(String scriptDir) {
  final packageDir = Directory(scriptDir).parent.path;
  return '$packageDir${Platform.pathSeparator}assets'
      '${Platform.pathSeparator}compat_manifest.json';
}

/// Where verified artifacts are kept.
///
/// `--cache-dir`, else `WCF_ARTIFACT_DIR` (PRD §12.3's configurable cache
/// directory), else `~/.cache/wallet_core_flutter/<upstream.tag>/`. The tag is
/// in the path because two upstream tags are two different artifact sets and
/// sharing one directory between them buys nothing.
///
/// Reading the environment here is fine and is not threat model TM-13: that
/// row is about the *runtime* library location, and `lib/` never reads the
/// environment. This is a build-time tool whose output is verified against the
/// manifest whatever directory it lands in.
///
/// Throws [StateError] when it has to fall back to the default and the manifest
/// has no usable `upstream.tag`, or when there is no home directory.
String resolveCacheDir({
  required FetchManifest manifest,
  required String? override,
  required Map<String, String> environment,
}) {
  if (override != null) return override;
  final fromEnvironment = environment['WCF_ARTIFACT_DIR'];
  if (fromEnvironment != null && fromEnvironment.isNotEmpty) {
    return fromEnvironment;
  }
  final tag = manifest.upstreamTag;
  if (tag == null || tag.isEmpty || isPlaceholder(tag)) {
    throw StateError(
      'the default cache directory is '
      '~/.cache/wallet_core_flutter/<upstream.tag>/ and ${manifest.source} has '
      'no usable upstream.tag (${tag ?? "missing"}); pass --cache-dir or set '
      'WCF_ARTIFACT_DIR',
    );
  }
  final home = environment['HOME'] ?? environment['USERPROFILE'];
  if (home == null || home.isEmpty) {
    throw StateError(
      'no HOME (or USERPROFILE) in the environment, so the default cache '
      'directory cannot be resolved; pass --cache-dir or set WCF_ARTIFACT_DIR',
    );
  }
  final sep = Platform.pathSeparator;
  return '$home$sep.cache${sep}wallet_core_flutter$sep$tag';
}

// ---------------------------------------------------------------------------
// Dry run
// ---------------------------------------------------------------------------

int _dryRun({
  required FetchManifest manifest,
  required List<String> selected,
  required String cacheDir,
  required List<GateReason> blockers,
  required FetchOptions options,
  required void Function(String) write,
}) {
  write('manifest:  ${manifest.source}');
  write('cache dir: $cacheDir');
  write('');

  if (blockers.isEmpty) {
    write('manifest gate: passed');
  } else {
    write(
      'manifest gate: BLOCKED — ${blockers.length} '
      '${blockers.length == 1 ? "reason" : "reasons"}, nothing can be fetched:',
    );
    for (final blocker in blockers) {
      write('  $blocker');
    }
  }
  write('');

  final mirrorBase = manifest.retentionMirror;
  final primaryBase = manifest.retentionPrimary;
  final setId = manifest.artifactSetId;

  for (final name in selected) {
    final record = manifest.artifacts[name];
    write(name);
    if (record == null) {
      write('  not in the manifest');
      write('');
      continue;
    }
    final assetName = record.assetName;
    if (primaryBase == null || isPlaceholder(primaryBase)) {
      write('  primary: unavailable — retention.primary is not a base URL yet');
    } else if (assetName == null) {
      write('  primary: unavailable — the record has no asset_name');
    } else {
      write('  primary: ${primaryUrl(primaryBase, assetName)}');
    }

    final sha = record.sha256;
    if (mirrorBase == null) {
      write('  mirror:  no mirror');
    } else if (setId == null ||
        isPlaceholder(setId) ||
        sha == null ||
        !isSha256(sha)) {
      write(
        '  mirror:  unavailable — needs identity.artifact_set_id and a '
        '64-hex sha256',
      );
    } else {
      write('  mirror:  ${mirrorUrl(mirrorBase, setId, sha, name)}');
    }

    if (isLogicalName(name)) {
      final path = cachePathFor(
        cacheDir,
        name,
        separator: Platform.pathSeparator,
      );
      write('  cache:   $path');
      write('  state:   ${_describeState(_inspectSync(path, record))}');
    } else {
      write('  cache:   unavailable — the map key is not a logical name');
      write('  state:   ${_describeState(CacheState.missing)}');
    }
    write('');
  }

  final verb = options.offline ? 'offline dry run' : 'dry run';
  if (blockers.isEmpty) {
    write('$verb: no request was made; ${selected.length} artifact(s) listed.');
    return exitOk;
  }
  write(
    '$verb: no request was made. The manifest is blocked, so exit '
    '$exitManifestBlocked — a preflight that reported these blockers and still '
    'reported success would be worse than useless in CI.',
  );
  return exitManifestBlocked;
}

String _describeState(CacheState state) => switch (state) {
  CacheState.verified => 'verified',
  CacheState.missing => 'missing',
  CacheState.corrupt => 'corrupt',
};

/// The cache state without hashing, for the dry run: a file whose size is not
/// the manifest's size cannot be the artifact, and a manifest with no digest
/// yet cannot call anything verified.
CacheState _inspectSync(String path, ArtifactRecord record) {
  final file = File(path);
  if (!file.existsSync()) return CacheState.missing;
  final sha = record.sha256;
  final size = record.size;
  if (sha == null || !isSha256(sha) || size == null || size <= 0) {
    return CacheState.corrupt;
  }
  if (file.lengthSync() != size) return CacheState.corrupt;
  final digest = _hashFileSync(file);
  return digest == sha ? CacheState.verified : CacheState.corrupt;
}

// ---------------------------------------------------------------------------
// Fetch
// ---------------------------------------------------------------------------

/// What happened to one artifact.
enum _Outcome { verified, fetched, vendored, failed }

Future<int> _fetchAll({
  required FetchManifest manifest,
  required List<String> selected,
  required String cacheDir,
  required FetchOptions options,
  required void Function(String) write,
  required void Function(String) writeError,
}) async {
  Directory(cacheDir).createSync(recursive: true);

  final counts = <_Outcome, int>{
    _Outcome.verified: 0,
    _Outcome.fetched: 0,
    _Outcome.vendored: 0,
    _Outcome.failed: 0,
  };
  HttpClient? client;

  try {
    for (final name in selected) {
      final record = manifest.artifacts[name]!;
      try {
        final outcome = await _fetchOne(
          manifest: manifest,
          record: record,
          cacheDir: cacheDir,
          options: options,
          write: write,
          openClient: () => client ??= HttpClient(),
        );
        counts[outcome] = counts[outcome]! + 1;
      } on _ArtifactFailure catch (failure) {
        counts[_Outcome.failed] = counts[_Outcome.failed]! + 1;
        write('failed    $name');
        for (final line in failure.lines) {
          write('          $line');
        }
        if (!options.keepGoing) {
          writeError(
            'error: $name could not be verified; stopping. Pass --keep-going '
            'to report the rest first (the exit code stays non-zero).',
          );
          break;
        }
      }
    }
  } finally {
    client?.close(force: true);
  }

  final failed = counts[_Outcome.failed]!;
  final reported = counts.values.reduce((a, b) => a + b);
  write('');
  write(
    '${selected.length} requested: ${counts[_Outcome.verified]} already '
    'verified in the cache, ${counts[_Outcome.fetched]} downloaded, '
    '${counts[_Outcome.vendored]} from --vendored, $failed failed'
    '${reported < selected.length ? ", ${selected.length - reported} not attempted" : ""}'
    ' — cache $cacheDir',
  );
  return failed == 0 && reported == selected.length ? exitOk : exitFetchFailed;
}

Future<_Outcome> _fetchOne({
  required FetchManifest manifest,
  required ArtifactRecord record,
  required String cacheDir,
  required FetchOptions options,
  required void Function(String) write,
  required HttpClient Function() openClient,
}) async {
  final name = record.key;
  // The gate has already established these; a null here would be a bug in the
  // gate, not a manifest we should tolerate.
  final sha = record.sha256!;
  final size = record.size!;
  final assetName = record.assetName!;

  final cachePath = cachePathFor(
    cacheDir,
    name,
    separator: Platform.pathSeparator,
  );
  final cached = File(cachePath);

  if (cached.existsSync()) {
    final actual = await _hashFile(cached);
    if (actual.digest == sha && actual.size == size) {
      write('verified  $name  (cache)');
      return _Outcome.verified;
    }
    cached.deleteSync();
    write('corrupt   $name  cache entry deleted: $cachePath');
    write('          expected sha256 $sha size $size');
    write('          found    sha256 ${actual.digest} size ${actual.size}');
  }

  if (options.vendoredDir != null) {
    final vendored = File(
      cachePathFor(
        options.vendoredDir!,
        name,
        separator: Platform.pathSeparator,
      ),
    );
    if (vendored.existsSync()) {
      // Verified before it is copied, not after: a vendored directory is
      // consumer-supplied input and gets exactly the check a download gets.
      final actual = await _hashFile(vendored);
      if (actual.digest != sha || actual.size != size) {
        throw _ArtifactFailure([
          'vendored ${vendored.path}',
          'expected sha256 $sha size $size',
          'found    sha256 ${actual.digest} size ${actual.size}',
          'the vendored file is not this artifact; it was not copied',
        ]);
      }
      await _copyVerified(
        source: vendored,
        cachePath: cachePath,
        cacheDir: cacheDir,
        name: name,
        sha: sha,
        size: size,
      );
      write('vendored  $name  <- ${vendored.path}');
      return _Outcome.vendored;
    }
    if (options.offline) {
      throw _ArtifactFailure([
        'offline: not in the cache ($cachePath)',
        'and not in the vendored directory (${vendored.path})',
      ]);
    }
  }

  if (options.offline) {
    throw _ArtifactFailure([
      'offline: not in the cache ($cachePath)',
      'no request was made; supply it with --vendored or run without --offline',
    ]);
  }

  final locations = <_Location>[
    _Location('primary', primaryUrl(manifest.retentionPrimary!, assetName)),
    if (manifest.retentionMirror != null)
      _Location(
        'mirror',
        mirrorUrl(
          manifest.retentionMirror!,
          manifest.artifactSetId!,
          sha,
          name,
        ),
      ),
  ];

  final transportFailures = <String>[];
  for (final location in locations) {
    final temp = _temporaryFile(cacheDir, name);
    final _Downloaded downloaded;
    try {
      downloaded = await _download(
        client: openClient(),
        url: location.url,
        destination: temp,
        allowInsecureLoopback: options.allowInsecureLoopback,
      );
    } on _TransportFailure catch (failure) {
      if (temp.existsSync()) temp.deleteSync();
      transportFailures.add(
        '${location.kind} ${location.url}: ${failure.message}',
      );
      continue;
    }

    if (downloaded.digest != sha || downloaded.size != size) {
      temp.deleteSync();
      // A digest or size mismatch is not a reason to ask somewhere else: the
      // manifest is the integrity root, and a location that served the wrong
      // bytes has already answered the question. DECISION-14 §3.1 leaves no
      // "continue anyway" path.
      throw _ArtifactFailure([
        ...transportFailures,
        '${location.kind} ${location.url}',
        'expected sha256 $sha size $size',
        'found    sha256 ${downloaded.digest} size ${downloaded.size}',
        'the bytes served are not this artifact; the partial file was deleted '
            'and nothing was written to $cachePath',
      ]);
    }

    _ensureParent(cachePath);
    temp.renameSync(cachePath);
    write('fetched   $name  <- ${location.url}');
    return _Outcome.fetched;
  }

  throw _ArtifactFailure([
    ...transportFailures,
    if (manifest.retentionMirror == null)
      'retention.mirror is null, so there was no second location to try '
          '(DECISION-14 §3.1)',
    'nothing was written to $cachePath',
  ]);
}

final class _Location {
  const _Location(this.kind, this.url);
  final String kind;
  final String url;
}

/// A verification failure, or an exhausted set of locations, for one artifact.
final class _ArtifactFailure implements Exception {
  _ArtifactFailure(this.lines);
  final List<String> lines;
  @override
  String toString() => lines.join('\n');
}

/// A location could not be reached or did not answer with the bytes. Not a
/// verification failure — the next location may be tried.
final class _TransportFailure implements Exception {
  _TransportFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

final class _Downloaded {
  const _Downloaded(this.digest, this.size);
  final String digest;
  final int size;
}

Future<_Downloaded> _download({
  required HttpClient client,
  required String url,
  required File destination,
  required bool allowInsecureLoopback,
}) async {
  var current = Uri.parse(url);
  for (var hop = 0; hop <= maxRedirects; hop++) {
    final insecure = insecureUrlReason(
      current.toString(),
      allowInsecureLoopback: allowInsecureLoopback,
    );
    if (insecure != null) {
      throw _TransportFailure('refused $current: $insecure');
    }

    final HttpClientResponse response;
    try {
      final request = await client.openUrl('GET', current);
      // Redirects are followed by hand so that every hop is checked against
      // the same scheme rule and the hop count is ours.
      request.followRedirects = false;
      response = await request.close();
    } on Object catch (e) {
      throw _TransportFailure('$e');
    }

    if (response.isRedirect) {
      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain<void>();
      if (location == null) {
        throw _TransportFailure(
          'HTTP ${response.statusCode} with no Location header',
        );
      }
      if (hop == maxRedirects) {
        throw _TransportFailure('more than $maxRedirects redirects');
      }
      current = current.resolve(location);
      continue;
    }

    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw _TransportFailure(
        'HTTP ${response.statusCode} ${response.reasonPhrase}',
      );
    }

    _ensureParent(destination.path);
    final sink = destination.openWrite();
    final digestSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(digestSink);
    var size = 0;
    try {
      await for (final chunk in response) {
        hasher.add(chunk);
        sink.add(chunk);
        size += chunk.length;
      }
      await sink.flush();
    } on Object catch (e) {
      await sink.close();
      throw _TransportFailure('transfer failed after $size bytes: $e');
    }
    await sink.close();
    hasher.close();
    return _Downloaded(digestSink.value!.toString(), size);
  }
  throw _TransportFailure('more than $maxRedirects redirects');
}

Future<void> _copyVerified({
  required File source,
  required String cachePath,
  required String cacheDir,
  required String name,
  required String sha,
  required int size,
}) async {
  final temp = _temporaryFile(cacheDir, name);
  _ensureParent(temp.path);
  await source.copy(temp.path);
  // Re-hashed after the copy as well: the check that matters is the one over
  // the bytes that end up at the cache path.
  final actual = await _hashFile(temp);
  if (actual.digest != sha || actual.size != size) {
    temp.deleteSync();
    throw _ArtifactFailure([
      'copy of ${source.path} does not verify',
      'expected sha256 $sha size $size',
      'found    sha256 ${actual.digest} size ${actual.size}',
    ]);
  }
  _ensureParent(cachePath);
  temp.renameSync(cachePath);
}

File _temporaryFile(String cacheDir, String name) {
  // Inside the cache directory, so the rename that follows is on the same
  // filesystem and therefore atomic. The leading dot and the `.part` suffix
  // keep a half-written file recognisable if a run is killed.
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final sep = Platform.pathSeparator;
  return File('$cacheDir$sep.wcf-fetch-${flatName(name)}-$pid-$stamp.part');
}

void _ensureParent(String path) {
  final parent = File(path).parent;
  if (!parent.existsSync()) parent.createSync(recursive: true);
}

// ---------------------------------------------------------------------------
// Hashing (PRD §12.3 integrity verification; AGENTS.md rule 2 permits it)
// ---------------------------------------------------------------------------

final class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

/// The sha256 and the byte count of [file], read in chunks.
Future<({String digest, int size})> _hashFile(File file) async {
  final digestSink = _DigestSink();
  final hasher = sha256.startChunkedConversion(digestSink);
  var size = 0;
  await for (final chunk in file.openRead()) {
    hasher.add(chunk);
    size += chunk.length;
  }
  hasher.close();
  return (digest: digestSink.value!.toString(), size: size);
}

String _hashFileSync(File file) =>
    sha256.convert(file.readAsBytesSync()).toString();

/// The sha256 and size of the file at [path]. Exported for the tests, which
/// hash fixtures and a real upstream release asset with the same code the
/// fetcher verifies with.
Future<({String digest, int size})> sha256OfFile(File file) => _hashFile(file);
