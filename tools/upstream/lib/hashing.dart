import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// SHA-256 of [bytes], lowercase hex.
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// SHA-256 of a file's bytes, lowercase hex.
String sha256OfFile(File file) => sha256Hex(file.readAsBytesSync());

/// Thrown when a directory being hashed contains something that is neither a
/// regular file nor a directory.
///
/// Silently skipping such an entry would make the digest under-cover the tree,
/// so the hash refuses to be computed instead.
class UnhashableEntry implements Exception {
  final String path;
  final String kind;
  UnhashableEntry(this.path, this.kind);
  @override
  String toString() =>
      'Cannot hash "$path": entry is a $kind, not a regular file or directory.';
}

/// The result of hashing a directory tree.
class DirectoryDigest {
  /// The tree digest, lowercase hex SHA-256.
  final String sha256;

  /// The number of regular files that went into the digest.
  final int fileCount;

  /// The exact bytes that were hashed, as text. Useful in tests and when
  /// diagnosing a digest change; never written to the manifest.
  final String hashInput;

  DirectoryDigest({
    required this.sha256,
    required this.fileCount,
    required this.hashInput,
  });
}

/// Builds the canonical hash input for a directory tree.
///
/// See [hashDirectory] for the definition this implements. [fileShas] maps a
/// POSIX path, relative to the hashed root, to the lowercase-hex SHA-256 of
/// that file's bytes.
String directoryHashInput(Map<String, String> fileShas) {
  final paths = fileShas.keys.toList()..sort();
  final buffer = StringBuffer();
  for (final path in paths) {
    buffer.write(path);
    buffer.write('\n');
    buffer.write(fileShas[path]);
    buffer.write('\n');
  }
  return buffer.toString();
}

/// Hashes a directory tree deterministically.
///
/// **Definition (normative; also stated in `tools/upstream/README.md`).** For
/// every regular file under [root], take its path relative to [root], written
/// with POSIX `/` separators and no leading `./`, and the lowercase-hex
/// SHA-256 of its bytes. Sort those pairs by relative path using ordinal
/// (UTF-16 code-unit) comparison. Concatenate `"<relative path>\n<sha256>\n"`
/// for each pair, in that order, and take the SHA-256 of the UTF-8 encoding of
/// the result. That digest is the directory hash.
///
/// The digest depends on file paths and file contents and on nothing else: not
/// on extraction order, not on mtimes, not on permissions, and not on the
/// absolute location of [root]. Directories contribute nothing of their own —
/// an empty directory is invisible to the digest. Symbolic links and other
/// non-regular entries are rejected ([UnhashableEntry]) rather than skipped.
DirectoryDigest hashDirectory(Directory root) {
  if (!root.existsSync()) {
    throw ArgumentError('Directory not found: ${root.path}');
  }
  final rootPath = root.absolute.path;
  final fileShas = <String, String>{};
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    final relative = p.posix.joinAll(
      p.split(p.relative(entity.absolute.path, from: rootPath)),
    );
    if (entity is Directory) continue;
    if (entity is Link) {
      throw UnhashableEntry(relative, 'symbolic link');
    }
    if (entity is! File) {
      throw UnhashableEntry(relative, entity.runtimeType.toString());
    }
    fileShas[relative] = sha256OfFile(entity);
  }
  final input = directoryHashInput(fileShas);
  return DirectoryDigest(
    sha256: sha256Hex(utf8.encode(input)),
    fileCount: fileShas.length,
    hashInput: input,
  );
}
