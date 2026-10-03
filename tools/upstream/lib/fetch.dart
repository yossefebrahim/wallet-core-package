import 'dart:io';

import 'package:path/path.dart' as p;

import 'dist.dart';
import 'download.dart';
import 'extract.dart';
import 'hashing.dart';
import 'manifest_edit.dart';
import 'notices.dart';

/// Where the pinned upstream tree lives, relative to the repository root.
const defaultDestination = 'third_party/wallet-core';

/// The three trees whose digests go into `schemas`.
const headersSubdirectory = 'include/TrustWalletCore';
const protoSubdirectory = 'src/proto';
const registryFile = 'registry.json';

/// Thrown for a usage error; the message is printed without a stack trace.
class UsageError implements Exception {
  final String message;
  UsageError(this.message);
  @override
  String toString() => message;
}

/// Parsed command line for `bin/fetch.dart`.
class FetchOptions {
  /// A pre-fetched `.tar.gz`, or null to download from `codeload.github.com`.
  final String? from;

  /// Path to `compat_manifest.json`.
  final String manifestPath;

  /// Where to extract the tree.
  final String destination;

  /// Path to `THIRD_PARTY_NOTICES.md`.
  final String noticesPath;

  /// The 40-hex commit the pinned tag points at, supplied by the caller
  /// because the archive does not carry it.
  final String? commit;

  /// Also place the release asset's public headers, the input ffigen runs
  /// over. Implied by [fromDist] and by [distOnly].
  final bool dist;

  /// Place only the release asset's headers: skip the source tree, the
  /// manifest digests, and `THIRD_PARTY_NOTICES.md`.
  ///
  /// The header set is a separate build input from the source tree
  /// (`docs/decisions/evidence/headers-4.8.0-source-vs-binary.md`), so
  /// refreshing the ffigen input should not require re-extracting 16 MB of
  /// sources or rewriting files this run has nothing new to say about.
  final bool distOnly;

  /// A pre-fetched `TrustWalletCore-<tag>.tar.xz`, or null to download the
  /// release asset when [dist] is set.
  final String? fromDist;

  /// Where the release asset's headers are extracted.
  final String distDestination;

  FetchOptions({
    required this.from,
    required this.manifestPath,
    required this.destination,
    required this.noticesPath,
    required this.commit,
    this.dist = false,
    this.distOnly = false,
    this.fromDist,
    this.distDestination = defaultDistDestination,
  });

  /// True when this run places the release asset's headers.
  bool get wantsDist => dist || distOnly || fromDist != null;

  static const usage =
      '''
Usage: dart run tools/upstream/bin/fetch.dart [options]

  --from <path>       Extract a pre-fetched source archive instead of
                      downloading. Required off-network.
  --commit <sha>      The 40-hex commit the pinned tag resolves to. Required
                      the first time; afterwards it is verified against the
                      manifest, never used to repin.
  --dist              Also place the release asset's public headers (the 143
                      headers ffigen runs over, T1.3) into
                      $defaultDistDestination. Downloads the asset unless
                      --from-dist is given.
  --from-dist <path>  A pre-fetched TrustWalletCore-<tag>.tar.xz. Implies
                      --dist. Required off-network.
  --dist-only         Place only those headers: no source tree, no manifest
                      digests, no THIRD_PARTY_NOTICES.md. Implies --dist.
  --manifest <path>   compat_manifest.json (default: compat_manifest.json)
  --dest <path>       Extraction root (default: $defaultDestination)
  --dist-dest <path>  Release-asset header root
                      (default: $defaultDistDestination)
  --notices <path>    THIRD_PARTY_NOTICES.md (default: THIRD_PARTY_NOTICES.md)
  -h, --help          Print this help.
''';

  /// Parses [args]. Kept free of I/O so it can be unit-tested.
  static FetchOptions parse(List<String> args) {
    String? from;
    String? commit;
    var dist = false;
    var distOnly = false;
    String? fromDist;
    var distDestination = defaultDistDestination;
    var manifestPath = 'compat_manifest.json';
    var destination = defaultDestination;
    var noticesPath = 'THIRD_PARTY_NOTICES.md';

    String valueFor(String flag, int index) {
      if (index + 1 >= args.length) {
        throw UsageError('$flag needs a value.');
      }
      return args[index + 1];
    }

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      switch (arg) {
        case '--from':
          from = valueFor(arg, i);
          i++;
        case '--commit':
          commit = valueFor(arg, i);
          i++;
        case '--dist':
          dist = true;
        case '--dist-only':
          distOnly = true;
        case '--from-dist':
          fromDist = valueFor(arg, i);
          i++;
        case '--dist-dest':
          distDestination = valueFor(arg, i);
          i++;
        case '--manifest':
          manifestPath = valueFor(arg, i);
          i++;
        case '--dest':
          destination = valueFor(arg, i);
          i++;
        case '--notices':
          noticesPath = valueFor(arg, i);
          i++;
        case '-h':
        case '--help':
          throw UsageError(usage);
        default:
          throw UsageError('Unknown argument "$arg".\n\n$usage');
      }
    }

    return FetchOptions(
      from: from,
      manifestPath: manifestPath,
      destination: destination,
      noticesPath: noticesPath,
      commit: commit,
      dist: dist,
      distOnly: distOnly,
      fromDist: fromDist,
      distDestination: distDestination,
    );
  }
}

/// What one fetch produced, for the run summary and for tests.
///
/// Every field below `commit` describes the source-tree stage and is null in a
/// `--dist-only` run, which touches neither the source tree nor the manifest.
class FetchResult {
  final String repo;
  final String tag;
  final String commit;
  final String? headersSha;
  final String? protoDirSha;
  final String? registryJsonSha;
  final int? headerCount;
  final int? protoFileCount;
  final ExtractionReport? extraction;
  final bool? manifestChanged;
  final bool? noticesChanged;

  /// The release asset's header set, when this run placed it; null otherwise.
  ///
  /// This is the ffigen input (T1.3). It is deliberately *not* written into
  /// `schemas.headers_sha`, which keeps its meaning: the digest of the git
  /// tree's `include/TrustWalletCore`.
  final DistHeaders? distHeaders;

  FetchResult({
    required this.repo,
    required this.tag,
    required this.commit,
    required this.headersSha,
    required this.protoDirSha,
    required this.registryJsonSha,
    required this.headerCount,
    required this.protoFileCount,
    required this.extraction,
    required this.manifestChanged,
    required this.noticesChanged,
    this.distHeaders,
  });

  /// The result of a `--dist-only` run: the pin, and the header set.
  FetchResult.distOnly({
    required this.repo,
    required this.tag,
    required this.commit,
    required DistHeaders this.distHeaders,
  }) : headersSha = null,
       protoDirSha = null,
       registryJsonSha = null,
       headerCount = null,
       protoFileCount = null,
       extraction = null,
       manifestChanged = null,
       noticesChanged = null;
}

/// Fetches (or unpacks) the pinned upstream tree, records its digests in the
/// manifest, and copies upstream's licence text into `THIRD_PARTY_NOTICES.md`.
///
/// Nothing in the extracted tree is executed or read as configuration. The
/// only files read back out of it are the two licence files and the bytes that
/// go into the three digests.
Future<FetchResult> runFetch(FetchOptions options, {StringSink? log}) async {
  final out = log ?? stdout;

  final manifestFile = File(options.manifestPath);
  if (!manifestFile.existsSync()) {
    throw UsageError('Manifest not found: ${options.manifestPath}');
  }
  final manifest = readManifest(manifestFile);

  final upstream = manifest['upstream'];
  if (upstream is! Map<String, Object?>) {
    throw UsageError('${options.manifestPath}: "upstream" must be an object.');
  }
  final repo = upstream['repo'];
  final tag = upstream['tag'];
  if (repo is! String || repo.isEmpty) {
    throw UsageError('upstream.repo must be a non-empty string.');
  }
  if (tag is! String || tag.isEmpty) {
    throw UsageError('upstream.tag must be a non-empty string.');
  }
  final recordedCommit = upstream['commit'];
  if (recordedCommit is! String) {
    throw UsageError('upstream.commit must be a string.');
  }
  final commit = resolveCommit(
    recorded: recordedCommit,
    provided: options.commit,
  );

  out.writeln('upstream: $repo @ $tag ($commit)');

  if (options.distOnly) {
    return FetchResult.distOnly(
      repo: repo,
      tag: tag,
      commit: commit,
      distHeaders: await _placeDistHeaders(
        options,
        repo: repo,
        tag: tag,
        commit: commit,
        out: out,
      ),
    );
  }

  File archiveFile;
  Directory? scratch;
  if (options.from != null) {
    archiveFile = File(options.from!);
    if (!archiveFile.existsSync()) {
      throw UsageError('Archive not found: ${options.from}');
    }
    out.writeln('archive:  ${archiveFile.path} (--from)');
  } else {
    scratch = Directory.systemTemp.createTempSync('wcf-upstream-');
    archiveFile = File(p.join(scratch.path, 'source.tar.gz'));
    final url = sourceArchiveUrl(repo: repo, tag: tag);
    out.writeln('archive:  $url (download)');
    await downloadSourceArchive(repo: repo, tag: tag, destination: archiveFile);
  }

  final String archiveSha;
  final int archiveSize;
  final ExtractionReport extraction;
  try {
    archiveSha = sha256OfFile(archiveFile);
    archiveSize = archiveFile.lengthSync();
    out.writeln('archive sha256: $archiveSha ($archiveSize bytes)');

    extraction = extractSourceArchive(
      archiveFile: archiveFile,
      destination: Directory(options.destination),
    );
  } finally {
    scratch?.deleteSync(recursive: true);
  }

  out.writeln(
    'extracted: ${extraction.fileCount} files, '
    '${extraction.directoryCount} directories, '
    '${extraction.symlinkCount} symlinks '
    '(stripped "${extraction.strippedTopLevel}/") '
    '-> ${options.destination}',
  );

  final headersDir = Directory(
    p.join(options.destination, p.joinAll(p.posix.split(headersSubdirectory))),
  );
  final protoDir = Directory(
    p.join(options.destination, p.joinAll(p.posix.split(protoSubdirectory))),
  );
  final registry = File(p.join(options.destination, registryFile));
  for (final required in <FileSystemEntity>[headersDir, protoDir, registry]) {
    if (!required.existsSync()) {
      throw UsageError(
        'Extracted tree is missing ${required.path}. The archive is not the '
        'upstream source tree for $repo @ $tag.',
      );
    }
  }

  final headers = hashDirectory(headersDir);
  final protos = hashDirectory(protoDir);
  final registrySha = sha256OfFile(registry);

  out
    ..writeln(
      'headers_sha       ${headers.sha256} '
      '(${headers.fileCount} files under $headersSubdirectory)',
    )
    ..writeln(
      'proto_dir_sha     ${protos.sha256} '
      '(${protos.fileCount} files under $protoSubdirectory)',
    )
    ..writeln('registry_json_sha $registrySha ($registryFile)');

  upstream['commit'] = commit;
  final schemas = manifest['schemas'];
  if (schemas is! Map<String, Object?>) {
    throw UsageError('${options.manifestPath}: "schemas" must be an object.');
  }
  schemas['headers_sha'] = headers.sha256;
  schemas['proto_dir_sha'] = protos.sha256;
  schemas['registry_json_sha'] = registrySha;

  // `identity.upstream_commit` carries a TBD-T1.1 placeholder and must equal
  // `upstream.commit` (PRD §15.3); resolving one without the other would leave
  // the manifest self-contradictory.
  final identity = manifest['identity'];
  if (identity is Map<String, Object?> &&
      identity['upstream_commit'] is String &&
      placeholderPattern.hasMatch(identity['upstream_commit'] as String)) {
    identity['upstream_commit'] = commit;
  }

  final manifestChanged = writeManifestIfChanged(manifestFile, manifest);

  final sections = <NoticeSection>[];
  for (final entry in upstreamNoticeFiles.entries) {
    final file = File(p.join(options.destination, entry.key));
    if (!file.existsSync()) {
      throw UsageError(
        'Upstream licence file ${entry.key} is missing from the extracted '
        'tree; refusing to write THIRD_PARTY_NOTICES.md without it.',
      );
    }
    sections.add(
      NoticeSection(
        upstreamPath: entry.key,
        title: entry.value,
        text: file.readAsStringSync(),
      ),
    );
  }
  final noticesFile = File(options.noticesPath);
  final notices = renderThirdPartyNotices(
    repo: repo,
    tag: tag,
    commit: commit,
    sections: sections,
  );
  final noticesChanged =
      !noticesFile.existsSync() || noticesFile.readAsStringSync() != notices;
  if (noticesChanged) noticesFile.writeAsStringSync(notices);

  out
    ..writeln(
      '${options.manifestPath}: '
      '${manifestChanged ? "updated" : "unchanged"}',
    )
    ..writeln(
      '${options.noticesPath}: '
      '${noticesChanged ? "updated" : "unchanged"} '
      '(${sections.map((s) => s.upstreamPath).join(", ")})',
    );

  final distHeaders = options.wantsDist
      ? await _placeDistHeaders(
          options,
          repo: repo,
          tag: tag,
          commit: commit,
          out: out,
        )
      : null;

  return FetchResult(
    repo: repo,
    tag: tag,
    commit: commit,
    headersSha: headers.sha256,
    protoDirSha: protos.sha256,
    registryJsonSha: registrySha,
    headerCount: headers.fileCount,
    protoFileCount: protos.fileCount,
    extraction: extraction,
    manifestChanged: manifestChanged,
    noticesChanged: noticesChanged,
    distHeaders: distHeaders,
  );
}

/// Places the release asset's public headers — the ffigen input of T1.3.
///
/// The git tree ships 67 headers; the release asset ships 143, the extra 76
/// being generated during upstream's own build. The 67 common to both are
/// byte-identical at 4.8.0, so the asset adds headers and drifts nothing; its
/// set declares the same 464 `TW*` functions the shipped framework exports.
/// Regenerating the missing 76 locally would need upstream's Ruby codegen, a
/// C++ protobuf build, and `codegen-v2` (Rust), so the asset is the source.
Future<DistHeaders> _placeDistHeaders(
  FetchOptions options, {
  required String repo,
  required String tag,
  required String commit,
  required StringSink out,
}) async {
  File assetFile;
  Directory? scratch;
  if (options.fromDist != null) {
    assetFile = File(options.fromDist!);
    if (!assetFile.existsSync()) {
      throw UsageError('Release asset not found: ${options.fromDist}');
    }
    out.writeln('asset:    ${assetFile.path} (--from-dist)');
  } else {
    scratch = Directory.systemTemp.createTempSync('wcf-dist-asset-');
    assetFile = File(p.join(scratch.path, distArchiveName(tag: tag)));
    out.writeln(
      'asset:    ${releaseAssetUrl(repo: repo, tag: tag)} (download)',
    );
    await downloadReleaseAsset(repo: repo, tag: tag, destination: assetFile);
  }

  final DistHeaders headers;
  try {
    headers = extractDistHeaders(
      archiveFile: assetFile,
      destination: Directory(options.distDestination),
      tag: tag,
      commit: commit,
    );
  } finally {
    scratch?.deleteSync(recursive: true);
  }

  out
    ..writeln(
      'asset sha256:   ${headers.archiveSha256} (${headers.archiveName})',
    )
    ..writeln(
      'dist headers    ${headers.dirSha256} '
      '(${headers.fileCount} files under $distHeadersSubdirectory) '
      '-> ${options.distDestination}',
    );

  return headers;
}
