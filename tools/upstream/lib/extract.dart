import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'paths.dart';

/// What an extraction produced. Reported so a run can be inspected without
/// walking the extracted tree.
class ExtractionReport {
  /// The top-level directory that was stripped, e.g. `wallet-core-4.8.0`.
  final String strippedTopLevel;

  /// Regular files written.
  final int fileCount;

  /// Directories created (explicit archive entries plus implicit parents).
  final int directoryCount;

  /// Symbolic links recreated. Each one was checked to stay inside the
  /// destination.
  final int symlinkCount;

  ExtractionReport({
    required this.strippedTopLevel,
    required this.fileCount,
    required this.directoryCount,
    required this.symlinkCount,
  });
}

/// Decodes a gzip-compressed tar archive into an in-memory [Archive].
Archive decodeSourceArchive(List<int> gzipBytes) =>
    TarDecoder().decodeBytes(GZipDecoder().decodeBytes(gzipBytes));

/// Extracts a `.tar.gz` source archive into [destination], stripping the
/// archive's single top-level directory.
///
/// After a successful run, `<destination>/registry.json` and
/// `<destination>/include/TrustWalletCore/TWCoinType.h` exist.
///
/// [destination] is emptied first, so a second run over a different archive
/// cannot leave stale files behind: the tree is a function of the archive
/// alone, which is what makes the schema hashes meaningful.
///
/// Every entry name is validated by [safeRelativePath] and every symlink
/// target by [safeSymlinkTarget] before anything is written. Nothing in the
/// extracted tree is read as configuration or executed; this function only
/// writes bytes.
ExtractionReport extractSourceArchive({
  required File archiveFile,
  required Directory destination,
}) {
  final archive = decodeSourceArchive(archiveFile.readAsBytesSync());
  return extractArchiveTo(archive: archive, destination: destination);
}

/// The archive-to-disk half of [extractSourceArchive], split out so tests can
/// build hostile archives in memory.
ExtractionReport extractArchiveTo({
  required Archive archive,
  required Directory destination,
}) {
  final topLevel = singleTopLevelDirectory(archive.files.map((f) => f.name));

  if (destination.existsSync()) {
    destination.deleteSync(recursive: true);
  }
  destination.createSync(recursive: true);
  final destinationPath = destination.absolute.path;

  var fileCount = 0;
  var directoryCount = 0;
  var symlinkCount = 0;
  final createdDirectories = <String>{};

  void ensureDirectory(String relative) {
    if (relative.isEmpty || relative == '.') return;
    if (!createdDirectories.add(relative)) return;
    Directory(
      p.join(destinationPath, p.joinAll(p.posix.split(relative))),
    ).createSync(recursive: true);
    directoryCount++;
  }

  for (final entry in archive.files) {
    final normalised = safeRelativePath(entry.name);
    final stripped = stripTopLevel(normalised, topLevel);
    if (stripped == null) continue;

    final onDisk = p.join(destinationPath, p.joinAll(p.posix.split(stripped)));

    if (entry.isSymbolicLink) {
      final target = safeSymlinkTarget(stripped, entry.symbolicLink!);
      ensureDirectory(p.posix.dirname(stripped));
      Link(onDisk).createSync(target, recursive: true);
      symlinkCount++;
      continue;
    }

    if (entry.isDirectory) {
      ensureDirectory(stripped);
      continue;
    }

    ensureDirectory(p.posix.dirname(stripped));
    File(onDisk).writeAsBytesSync(entry.readBytes() ?? const <int>[]);
    fileCount++;
  }

  return ExtractionReport(
    strippedTopLevel: topLevel,
    fileCount: fileCount,
    directoryCount: directoryCount,
    symlinkCount: symlinkCount,
  );
}
