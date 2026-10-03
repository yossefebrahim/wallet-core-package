import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'hashing.dart';
import 'paths.dart';

/// Where the release asset's public headers go, relative to the repository
/// root.
///
/// Deliberately a sibling of `third_party/wallet-core/`, not a directory
/// inside it: the two trees come from two different archives and only one of
/// them feeds `schemas.headers_sha`.
const defaultDistDestination = 'third_party/wallet-core-dist';

/// The single subtree taken out of the release asset. Everything else in the
/// asset (Swift sources, the xcframework, ~285 MB unpacked) is ignored.
const distHeadersSubdirectory = 'include/TrustWalletCore';

/// Provenance record written next to the extracted headers, so that the
/// inventory tool can say what produced the bindings without re-reading the
/// 54 MB archive.
const distProvenanceFile = 'dist_provenance.json';

/// The release asset's file name for [tag], e.g.
/// `TrustWalletCore-4.8.0.tar.xz`.
String distArchiveName({required String tag}) => 'TrustWalletCore-$tag.tar.xz';

final _repoPattern = RegExp(r'^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$');

/// The immutable release-asset URL for `<repo>` at `<tag>`.
///
/// `https://github.com/<repo>/releases/download/<tag>/TrustWalletCore-<tag>.tar.xz`
/// is the binary distribution upstream attaches to the tagged release. It
/// carries the 143 public headers, of which the git tree ships only 67 — the
/// other 76 are generated during upstream's own build. ffigen runs over the
/// 143.
///
/// Pure, like `sourceArchiveUrl`, so that what CI fetches is decided by
/// `upstream.repo` and `upstream.tag` and by nothing else. Contacted only from
/// build-time tooling, never from the three published packages (repo rule 3).
String releaseAssetUrl({required String repo, required String tag}) {
  if (!_repoPattern.hasMatch(repo)) {
    throw ArgumentError.value(repo, 'repo', 'Expected "<owner>/<name>"');
  }
  if (tag.isEmpty) {
    throw ArgumentError.value(tag, 'tag', 'Tag must not be empty');
  }
  if (tag.contains('/') || tag.contains('..') || tag.contains('%')) {
    throw ArgumentError.value(
      tag,
      'tag',
      'Tag must not contain "/", ".." or "%"',
    );
  }
  return 'https://github.com/$repo/releases/download/$tag/'
      '${distArchiveName(tag: tag)}';
}

/// Downloads the release asset for [repo] at [tag] to [destination].
///
/// Used by CI only; unreachable from the development sandbox, so the tested
/// path is `--from-dist <path>` and what is unit-tested here is
/// [releaseAssetUrl], the part that decides *which* bytes CI fetches.
Future<void> downloadReleaseAsset({
  required String repo,
  required String tag,
  required File destination,
}) async {
  final url = releaseAssetUrl(repo: repo, tag: tag);
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    request.followRedirects = true;
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException(
        'GET $url returned ${response.statusCode}',
        uri: Uri.parse(url),
      );
    }
    destination.parent.createSync(recursive: true);
    await response.pipe(destination.openWrite());
  } finally {
    client.close(force: true);
  }
}

/// Where the ffigen input came from: the provenance record of the header set.
///
/// Written to `<dist destination>/dist_provenance.json` and copied verbatim
/// into the `headers` block of the generated `inventory.json`, so that a
/// reviewer can answer "what produced these bindings?" from one generated
/// file.
class DistHeaders {
  /// The release asset's file name, e.g. `TrustWalletCore-4.8.0.tar.xz`.
  final String archiveName;

  /// SHA-256 of the whole asset, lowercase hex.
  final String archiveSha256;

  /// The pinned tag the asset belongs to.
  final String tag;

  /// The pinned commit the tag resolves to (`upstream.commit`).
  final String commit;

  /// Header files extracted.
  final int fileCount;

  /// Directory digest of the extracted header set, computed with T1.1's
  /// normative definition (`hashDirectory`).
  final String dirSha256;

  DistHeaders({
    required this.archiveName,
    required this.archiveSha256,
    required this.tag,
    required this.commit,
    required this.fileCount,
    required this.dirSha256,
  });

  /// The JSON shape of the record; the key order here is the key order in
  /// `inventory.json`, which is diffed by `melos run gen:check`.
  Map<String, Object?> toJson() => <String, Object?>{
    'source': 'release_asset',
    'archive': archiveName,
    'archive_sha256': archiveSha256,
    'tag': tag,
    'commit': commit,
    'file_count': fileCount,
    'dir_sha256': dirSha256,
  };

  static DistHeaders fromJson(Map<String, Object?> json) {
    T read<T>(String key) {
      final value = json[key];
      if (value is! T) {
        throw FormatException('$distProvenanceFile: "$key" must be a $T.');
      }
      return value;
    }

    return DistHeaders(
      archiveName: read<String>('archive'),
      archiveSha256: read<String>('archive_sha256'),
      tag: read<String>('tag'),
      commit: read<String>('commit'),
      fileCount: read<int>('file_count'),
      dirSha256: read<String>('dir_sha256'),
    );
  }
}

/// Extracts `include/TrustWalletCore/` out of the release asset.
///
/// [destination] is the dist root (`third_party/wallet-core-dist`); it is
/// emptied first, so the header set is a function of the archive alone and a
/// stale header from an earlier pin cannot survive into the digest.
///
/// The asset is a `.tar.xz` with no single wrapping directory: its entries are
/// `./include/…`, `./Sources/…`, `./WalletCoreCommon.xcframework/…`. Only the
/// header subtree is written; the ~285 MB of Swift sources and binaries are
/// decoded and dropped.
///
/// Entry names are validated by [safeRelativePath] and symlink targets by
/// [safeSymlinkTarget] before anything is written — the same validation the
/// source-tree extractor uses, on the same grounds: `third_party/` is
/// untrusted third-party data. Nothing in it is executed or read as
/// configuration.
DistHeaders extractDistHeaders({
  required File archiveFile,
  required Directory destination,
  required String tag,
  required String commit,
}) {
  final archiveSha = sha256OfFile(archiveFile);

  final scratch = Directory.systemTemp.createTempSync('wcf-dist-');
  final Archive archive;
  try {
    // The asset unpacks to ~285 MB; decode it through a file rather than
    // holding the whole tar in memory.
    final tarPath = p.join(scratch.path, 'dist.tar');
    final compressed = InputFileStream(archiveFile.path);
    final plain = OutputFileStream(tarPath);
    try {
      XZDecoder().decodeStream(compressed, plain);
    } finally {
      plain.closeSync();
      compressed.closeSync();
    }
    archive = TarDecoder().decodeStream(InputFileStream(tarPath));
    _extractSubtree(
      archive: archive,
      prefix: distHeadersSubdirectory,
      destination: destination,
    );
  } finally {
    scratch.deleteSync(recursive: true);
  }

  final headersDir = Directory(
    p.join(destination.path, p.joinAll(p.posix.split(distHeadersSubdirectory))),
  );
  if (!headersDir.existsSync()) {
    throw ArgumentError(
      'The archive ${archiveFile.path} contains no '
      '$distHeadersSubdirectory/ subtree; it is not the '
      '${distArchiveName(tag: tag)} release asset.',
    );
  }
  final digest = hashDirectory(headersDir);

  final headers = DistHeaders(
    archiveName: p.basename(archiveFile.path),
    archiveSha256: archiveSha,
    tag: tag,
    commit: commit,
    fileCount: digest.fileCount,
    dirSha256: digest.sha256,
  );

  File(p.join(destination.path, distProvenanceFile)).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(headers.toJson())}\n',
  );

  return headers;
}

/// Writes every archive entry under [prefix] into
/// `<destination>/<prefix>/…`, preserving the prefix itself.
void _extractSubtree({
  required Archive archive,
  required String prefix,
  required Directory destination,
}) {
  if (destination.existsSync()) {
    destination.deleteSync(recursive: true);
  }
  destination.createSync(recursive: true);
  final destinationPath = destination.absolute.path;
  final createdDirectories = <String>{};

  void ensureDirectory(String relative) {
    if (relative.isEmpty || relative == '.') return;
    if (!createdDirectories.add(relative)) return;
    Directory(
      p.join(destinationPath, p.joinAll(p.posix.split(relative))),
    ).createSync(recursive: true);
  }

  for (final entry in archive.files) {
    // The asset is a tar of a directory tree and carries that root as `./`.
    // It names nothing to write, and `safeRelativePath` rightly refuses to
    // name it, so drop it here rather than teach the validator an exception.
    if (p.posix.normalize(entry.name) == '.') continue;

    final normalised = safeRelativePath(entry.name);
    if (normalised != prefix && !normalised.startsWith('$prefix/')) continue;

    final onDisk = p.join(
      destinationPath,
      p.joinAll(p.posix.split(normalised)),
    );

    if (entry.isSymbolicLink) {
      final target = safeSymlinkTarget(normalised, entry.symbolicLink!);
      ensureDirectory(p.posix.dirname(normalised));
      Link(onDisk).createSync(target, recursive: true);
      continue;
    }
    if (entry.isDirectory) {
      ensureDirectory(normalised);
      continue;
    }
    ensureDirectory(p.posix.dirname(normalised));
    File(onDisk).writeAsBytesSync(entry.readBytes() ?? const <int>[]);
  }
}

/// Reads the provenance record written by [extractDistHeaders].
DistHeaders readDistProvenance(Directory distDestination) {
  final file = File(p.join(distDestination.path, distProvenanceFile));
  if (!file.existsSync()) {
    throw StateError(
      'No header provenance at ${file.path}. Run\n'
      '  melos run upstream:fetch -- --from <source.tar.gz> '
      '--from-dist <TrustWalletCore-<tag>.tar.xz>\n'
      'to place the release asset\'s headers first.',
    );
  }
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    throw FormatException('${file.path}: expected a JSON object.');
  }
  return DistHeaders.fromJson(decoded);
}
