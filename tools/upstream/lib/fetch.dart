import 'dart:io';

import 'package:path/path.dart' as p;

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

  FetchOptions({
    required this.from,
    required this.manifestPath,
    required this.destination,
    required this.noticesPath,
    required this.commit,
  });

  static const usage =
      '''
Usage: dart run tools/upstream/bin/fetch.dart [options]

  --from <path>       Extract a pre-fetched source archive instead of
                      downloading. Required off-network.
  --commit <sha>      The 40-hex commit the pinned tag resolves to. Required
                      the first time; afterwards it is verified against the
                      manifest, never used to repin.
  --manifest <path>   compat_manifest.json (default: compat_manifest.json)
  --dest <path>       Extraction root (default: $defaultDestination)
  --notices <path>    THIRD_PARTY_NOTICES.md (default: THIRD_PARTY_NOTICES.md)
  -h, --help          Print this help.
''';

  /// Parses [args]. Kept free of I/O so it can be unit-tested.
  static FetchOptions parse(List<String> args) {
    String? from;
    String? commit;
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
    );
  }
}

/// What one fetch produced, for the run summary and for tests.
class FetchResult {
  final String repo;
  final String tag;
  final String commit;
  final String headersSha;
  final String protoDirSha;
  final String registryJsonSha;
  final int headerCount;
  final int protoFileCount;
  final ExtractionReport extraction;
  final bool manifestChanged;
  final bool noticesChanged;

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
  });
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
  );
}
