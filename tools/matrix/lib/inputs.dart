import 'dart:convert';
import 'dart:io';

import 'package:wcf_tool_vectors/inventory.dart';

import 'registry.dart';

/// Where the matrix reads its inputs and writes its outputs. Every path
/// defaults to the repository layout under [root]; the overrides exist so a
/// test, or a reviewer demonstrating a failing check, can point one input at a
/// copy without editing the real file.
class MatrixPaths {
  MatrixPaths({
    required this.root,
    String? vectorsDir,
    String? docsDir,
    String? exposedFile,
    String? evidenceFile,
    String? resultsDir,
    String? registryDir,
    String? protoDir,
    String? manifestFile,
  }) : vectorsDir = vectorsDir ?? '$root/test_vectors',
       docsDir = docsDir ?? '$root/docs',
       exposedFile = exposedFile ?? '$root/docs/capability_exposed.json',
       evidenceFile =
           evidenceFile ??
           '$root/docs/decisions/evidence/compiler_and_message_coverage.json',
       resultsDir = resultsDir ?? '$root/test_vectors/results',
       registryDir =
           registryDir ??
           '$root/packages/wallet_core_flutter_bindings/lib/src/generated/registry',
       protoDir =
           protoDir ??
           '$root/packages/wallet_core_flutter_bindings/lib/src/generated/proto',
       manifestFile = manifestFile ?? '$root/compat_manifest.json';

  final String root;
  final String vectorsDir;
  final String docsDir;
  final String exposedFile;
  final String evidenceFile;
  final String resultsDir;
  final String registryDir;
  final String protoDir;
  final String manifestFile;

  String get matrixJson => '$docsDir/capability_matrix.json';
  String get matrixMarkdown => '$docsDir/capability_matrix.md';
}

/// One row of the T2.9 coverage evidence
/// (`docs/decisions/evidence/compiler_and_message_coverage.json`).
class ProbeRow {
  const ProbeRow({
    required this.coinId,
    required this.blockchain,
    required this.staticVerdict,
    required this.runtime,
    required this.agreement,
    this.crashDetail,
    this.specificSigner,
  });

  factory ProbeRow.fromJson(Map<String, Object?> json) => ProbeRow(
    coinId: json['coin_id']! as int,
    blockchain: json['blockchain']! as String,
    staticVerdict: json['static']! as String,
    runtime: json['runtime']! as String,
    agreement: json['agreement']! as String,
    crashDetail: json['crash_detail'] as String?,
    specificSigner: json['specific_signer'] as String?,
  );

  final int coinId;
  final String blockchain;

  /// `supported` / `unsupported` / `unclassified`.
  final String staticVerdict;

  /// The probe's runtime class (`reached`, `empty`, `crash`, …).
  final String runtime;

  /// `agree` / `conflict` / `crash` / `unclassified`.
  final String agreement;
  final String? crashDetail;
  final String? specificSigner;
}

class CoverageEvidence {
  const CoverageEvidence({
    required this.tag,
    required this.commit,
    required this.compiler,
    required this.message,
  });

  final String tag;
  final String commit;

  /// By numeric coin id.
  final Map<int, ProbeRow> compiler;
  final Map<int, ProbeRow> message;
}

CoverageEvidence readCoverageEvidence(File file) {
  final json = _readJsonObject(file, 'coverage evidence');
  final upstream = json['upstream']! as Map<String, Object?>;
  Map<int, ProbeRow> rows(String key) => {
    for (final row in (json[key]! as List<Object?>))
      (row! as Map<String, Object?>)['coin_id']! as int: ProbeRow.fromJson(
        row as Map<String, Object?>,
      ),
  };
  return CoverageEvidence(
    tag: upstream['tag']! as String,
    commit: upstream['commit']! as String,
    compiler: rows('compiler'),
    message: rows('message'),
  );
}

/// One (operation, variant) the SDK exposes, for [coins] or for every coin of
/// the registry when `null`.
class ExposedGroup {
  const ExposedGroup({
    required this.operation,
    required this.variant,
    required this.exposure,
    required this.coins,
  });

  final String operation;
  final String variant;

  /// `typed` or `generic`.
  final String exposure;
  final List<String>? coins;
}

/// Reads `docs/capability_exposed.json`, the snapshot of the SDK's
/// `lib/src/capabilities.dart` that `test/capabilities_test.dart` keeps current.
List<ExposedGroup> readExposed(File file) {
  final json = _readJsonObject(file, 'exposed snapshot');
  return [
    for (final entry in (json['groups']! as List<Object?>))
      _exposedGroup(entry! as Map<String, Object?>),
  ];
}

ExposedGroup _exposedGroup(Map<String, Object?> group) => ExposedGroup(
  operation: group['operation']! as String,
  variant: group['variant']! as String,
  exposure: group['exposure']! as String,
  coins: switch (group['coins']) {
    'all' => null,
    final List<Object?> ids => ids.cast<String>(),
    _ => throw FormatException(
      'exposed snapshot group ${group['operation']}/${group['variant']} '
      'has no "coins" list or "all"',
    ),
  },
);

class Upstream {
  const Upstream(this.tag, this.commit);
  final String tag;
  final String commit;
}

Upstream readUpstream(File manifest) {
  final json = _readJsonObject(manifest, 'compat manifest');
  final upstream = json['upstream']! as Map<String, Object?>;
  return Upstream(upstream['tag']! as String, upstream['commit']! as String);
}

Map<String, Object?> _readJsonObject(File file, String what) {
  if (!file.existsSync()) {
    throw FormatException('$what not found: ${file.path}');
  }
  try {
    return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  } on Object catch (e) {
    throw FormatException('$what ${file.path} is not readable: $e');
  }
}

/// Everything the matrix is computed from.
class MatrixInputs {
  const MatrixInputs({
    required this.upstream,
    required this.coins,
    required this.protoMessages,
    required this.evidence,
    required this.exposed,
    required this.inventory,
  });

  final Upstream upstream;
  final List<RegistryCoin> coins;

  /// Proto file stem → the message classes the generated Dart defines for it.
  final Map<String, Set<String>> protoMessages;
  final CoverageEvidence evidence;
  final List<ExposedGroup> exposed;
  final Inventory inventory;
}
