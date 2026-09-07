import 'package:path/path.dart' as p;

/// Thrown when an archive entry would write outside the extraction root.
///
/// `third_party/wallet-core/` is untrusted third-party data: the archive is
/// downloaded from a third party and its entry names are attacker-controlled
/// as far as this tool is concerned. Every entry name is run through
/// [safeRelativePath] before a single byte is written to disk.
class UnsafeArchiveEntry implements Exception {
  /// The entry name exactly as it appeared in the archive.
  final String entryName;

  /// Why the entry was rejected.
  final String reason;

  UnsafeArchiveEntry(this.entryName, this.reason);

  @override
  String toString() => 'Unsafe archive entry "$entryName": $reason';
}

final _windowsDrive = RegExp(r'^[A-Za-z]:');

/// Normalises a POSIX archive entry name and rejects anything that escapes the
/// extraction root.
///
/// Rejected: empty names, absolute paths (`/etc/passwd`), Windows drive and
/// UNC prefixes, and any name that normalises to `..` or below (`a/../../b`).
/// Returns the normalised relative POSIX path; `.`-only names normalise away
/// and are rejected as empty.
String safeRelativePath(String entryName) {
  if (entryName.isEmpty) {
    throw UnsafeArchiveEntry(entryName, 'empty entry name');
  }
  if (entryName.startsWith('/')) {
    throw UnsafeArchiveEntry(entryName, 'absolute path');
  }
  if (entryName.startsWith(r'\')) {
    throw UnsafeArchiveEntry(entryName, 'UNC or absolute Windows path');
  }
  if (_windowsDrive.hasMatch(entryName)) {
    throw UnsafeArchiveEntry(entryName, 'Windows drive-qualified path');
  }
  if (entryName.contains('\u0000')) {
    throw UnsafeArchiveEntry(entryName, 'NUL byte in entry name');
  }

  final normalised = p.posix.normalize(entryName);
  if (normalised == '.' || normalised.isEmpty) {
    throw UnsafeArchiveEntry(entryName, 'entry resolves to the root itself');
  }
  if (p.posix.isAbsolute(normalised)) {
    throw UnsafeArchiveEntry(entryName, 'absolute path after normalisation');
  }
  if (normalised == '..' || normalised.startsWith('../')) {
    throw UnsafeArchiveEntry(
      entryName,
      'path traversal: escapes the extraction root',
    );
  }
  return normalised;
}

/// Checks that a symbolic-link entry stays inside the extraction root.
///
/// [linkPath] is the already-normalised relative path of the link itself;
/// [target] is the link text. Returns the target unchanged when it is safe.
String safeSymlinkTarget(String linkPath, String target) {
  if (target.isEmpty) {
    throw UnsafeArchiveEntry(linkPath, 'empty symlink target');
  }
  if (p.posix.isAbsolute(target)) {
    throw UnsafeArchiveEntry(linkPath, 'absolute symlink target "$target"');
  }
  final resolved = p.posix.normalize(
    p.posix.join(p.posix.dirname(linkPath), target),
  );
  if (resolved == '..' || resolved.startsWith('../')) {
    throw UnsafeArchiveEntry(
      linkPath,
      'symlink target "$target" escapes the extraction root',
    );
  }
  return target;
}

/// The single top-level directory shared by every entry of a source archive.
///
/// GitHub's `codeload` tarballs and `git archive` both wrap the tree in one
/// directory (`wallet-core-4.8.0/`). Extraction strips it, so it has to be
/// unambiguous: zero or more than one top-level segment is an error.
String singleTopLevelDirectory(Iterable<String> entryNames) {
  final tops = <String>{};
  for (final name in entryNames) {
    final relative = safeRelativePath(name);
    tops.add(p.posix.split(relative).first);
  }
  if (tops.isEmpty) {
    throw ArgumentError('Archive is empty; expected one top-level directory.');
  }
  if (tops.length > 1) {
    final sorted = tops.toList()..sort();
    throw ArgumentError(
      'Archive has ${tops.length} top-level entries '
      '(${sorted.take(5).join(', ')}${sorted.length > 5 ? ', …' : ''}); '
      'expected exactly one directory to strip.',
    );
  }
  return tops.single;
}

/// Removes [topLevel] from the front of an already-normalised entry path.
///
/// Returns `null` for the top-level directory entry itself, which has nothing
/// left after stripping.
String? stripTopLevel(String normalisedPath, String topLevel) {
  final segments = p.posix.split(normalisedPath);
  if (segments.first != topLevel) {
    throw ArgumentError(
      'Entry "$normalisedPath" is not under top-level directory "$topLevel".',
    );
  }
  if (segments.length == 1) return null;
  return p.posix.joinAll(segments.sublist(1));
}
