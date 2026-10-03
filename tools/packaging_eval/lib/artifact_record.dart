// Reading the DECISION-14 §5.1 per-artifact record that sits next to a built
// artifact, so a size or symbol measurement can cross-check it.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.
//
// A `tools/native_build` output set is laid out as
//   <set>/artifacts/<logical_name>
//   <set>/records/<flat_name>.json      (flat_name = logical_name with / -> -)
// and the record's single key is the logical name. A disagreement between the
// bytes on disk and the record is a finding, not a detail: the record's sha256
// is what the manifest publishes and what a consumer build verifies
// (PRD §12.3).

import 'dart:convert';
import 'dart:io';

class ArtifactRecord {
  const ArtifactRecord({
    required this.logicalName,
    required this.recordPath,
    required this.fields,
  });

  final String logicalName;
  final String recordPath;
  final Map<String, Object?> fields;

  String? get sha256 => fields['sha256'] as String?;
  int? get size => (fields['size'] as num?)?.toInt();
  String? get minOs => fields['min_os'] as String?;
  String? get abi => fields['abi'] as String?;
  String? get targetOs => fields['target_os'] as String?;
  String? get provenance => fields['provenance'] as String?;
  String? get assetName => fields['asset_name'] as String?;

  /// Finds the record for [artifactPath] by walking up to the `artifacts/`
  /// directory of the set. Returns null when the artifact is not inside a
  /// `tools/native_build` output set.
  static ArtifactRecord? forArtifact(String artifactPath) {
    final file = File(artifactPath).absolute;
    final tail = <String>[];
    Directory? artifactsDirectory;
    for (var dir = file.parent; dir.path != dir.parent.path; dir = dir.parent) {
      if (_basename(dir.path) == 'artifacts') {
        artifactsDirectory = dir;
        break;
      }
      tail.insert(0, _basename(dir.path));
    }
    if (artifactsDirectory == null) return null;

    final logicalName = [...tail, _basename(file.path)].join('/');
    final flatName = logicalName.replaceAll('/', '-');
    final record = File(
      '${artifactsDirectory.parent.path}/records/$flatName.json',
    );
    if (!record.existsSync()) return null;
    final decoded = jsonDecode(record.readAsStringSync());
    if (decoded is! Map<String, Object?>) return null;
    final fields = decoded[logicalName];
    if (fields is! Map<String, Object?>) return null;
    return ArtifactRecord(
      logicalName: logicalName,
      recordPath: record.path,
      fields: fields,
    );
  }

  static String _basename(String path) =>
      path.split(Platform.pathSeparator).where((s) => s.isNotEmpty).last;
}
