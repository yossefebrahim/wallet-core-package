import 'dart:convert';
import 'dart:io';

/// Matches a resolved git commit sha as the manifest stores it.
final commitShaPattern = RegExp(r'^[0-9a-f]{40}$');

/// Matches the `TBD-T<phase>.<task>` placeholders Phase 0 left behind.
final placeholderPattern = RegExp(r'^TBD-T\d+\.\d+$');

/// Reads `compat_manifest.json` as an ordered map.
///
/// Dart's `jsonDecode` preserves key order, and `JsonEncoder.withIndent('  ')`
/// reproduces the checked-in formatting byte for byte, so a decode/mutate/
/// encode round trip only ever changes the values this tool sets. That is what
/// makes a second run of the fetch leave the file untouched.
Map<String, Object?> readManifest(File file) {
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    throw FormatException('${file.path}: root must be a JSON object');
  }
  return decoded;
}

/// Encodes a manifest with the repository's formatting: two-space indent, one
/// trailing newline.
String encodeManifest(Map<String, Object?> manifest) =>
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n';

/// Writes [manifest] to [file] only if the encoding differs from what is
/// already there. Returns true when bytes actually changed.
bool writeManifestIfChanged(File file, Map<String, Object?> manifest) {
  final encoded = encodeManifest(manifest);
  if (file.existsSync() && file.readAsStringSync() == encoded) return false;
  file.writeAsStringSync(encoded);
  return true;
}

/// Thrown when the commit passed on the command line contradicts the pin
/// already recorded in the manifest.
class CommitPinMismatch implements Exception {
  final String recorded;
  final String provided;
  CommitPinMismatch(this.recorded, this.provided);
  @override
  String toString() =>
      'upstream.commit is already pinned to $recorded but --commit '
      'gave $provided. The pin is changed deliberately, by editing '
      'compat_manifest.json, not as a side effect of a fetch.';
}

/// Decides what `upstream.commit` should be after this run.
///
/// The source archive does not carry the commit sha — GitHub's tarball is a
/// `git archive` of the tree, with no object metadata — so the sha can only
/// come from the caller. Two cases:
///
/// * The manifest still holds a placeholder: [provided] is required and is
///   adopted.
/// * The manifest already holds a 40-hex sha: [provided], if given, must
///   match it. A fetch verifies the pin; it never silently repins.
String resolveCommit({required String recorded, String? provided}) {
  final isResolved = commitShaPattern.hasMatch(recorded);
  if (provided != null && !commitShaPattern.hasMatch(provided)) {
    throw ArgumentError.value(
      provided,
      '--commit',
      'Expected 40 lowercase hex characters',
    );
  }
  if (isResolved) {
    if (provided != null && provided != recorded) {
      throw CommitPinMismatch(recorded, provided);
    }
    return recorded;
  }
  if (provided == null) {
    throw ArgumentError(
      'upstream.commit is "$recorded" and no --commit was given. The archive '
      'does not carry the commit sha; pass --commit <40-hex sha> for the '
      'pinned tag.',
    );
  }
  return provided;
}
