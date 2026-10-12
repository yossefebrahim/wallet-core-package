import 'dart:convert';
import 'dart:io';

import 'package:wcf_tool_vectors/inventory.dart';

import 'inputs.dart';
import 'matrix.dart';
import 'render.dart';
import 'variants.dart';

/// Writes `capability_matrix.md` and `capability_matrix.json` into [dir].
void writeOutputs(Matrix matrix, Directory dir) {
  dir.createSync(recursive: true);
  File(
    '${dir.path}/capability_matrix.md',
  ).writeAsStringSync(renderMarkdown(matrix));
  File(
    '${dir.path}/capability_matrix.json',
  ).writeAsStringSync(renderJson(matrix));
}

// ---------------------------------------------------------------------------
// (b) the matrix is regenerated, never edited
// ---------------------------------------------------------------------------

/// PRD §13.2 (b): regenerates into a temporary directory and compares it, byte
/// for byte, with the committed outputs in `paths.docsDir`.
List<String> checkRegeneration(MatrixPaths paths, Matrix matrix) {
  final temp = Directory.systemTemp.createTempSync('wcf_matrix_');
  try {
    writeOutputs(matrix, temp);
    final violations = <String>[];
    for (final name in ['capability_matrix.md', 'capability_matrix.json']) {
      final committed = File('${paths.docsDir}/$name');
      final display = 'docs/$name';
      if (!committed.existsSync()) {
        violations.add('(b) $display is missing; run `melos run gen:matrix`');
        continue;
      }
      final difference = _firstDifference(
        committed.readAsStringSync(),
        File('${temp.path}/$name').readAsStringSync(),
      );
      if (difference != null) {
        violations.add(
          '(b) $display differs from the regenerated output ($difference); '
          'it is generated, never edited — run `melos run gen:matrix`',
        );
      }
    }
    return violations;
  } finally {
    temp.deleteSync(recursive: true);
  }
}

String? _firstDifference(String committed, String regenerated) {
  if (committed == regenerated) return null;
  final a = const LineSplitter().convert(committed);
  final b = const LineSplitter().convert(regenerated);
  for (var i = 0; i < a.length && i < b.length; i++) {
    if (a[i] != b[i]) return 'first at line ${i + 1}';
  }
  return 'committed has ${a.length} lines, regenerated ${b.length}';
}

// ---------------------------------------------------------------------------
// (c) no level goes down and no vector disappears without an exclusion
// ---------------------------------------------------------------------------

/// Whether an exclusions entry covers (coin, operation, variant).
bool isExcluded(
  List<Exclusion> exclusions,
  String coin,
  String operation,
  String variant,
) => exclusions.any(
  (e) =>
      e.coin == coin &&
      e.operation == operation &&
      (e.variant == null || e.variant == variant),
);

/// Entries of `exclusions.yaml` must name a coin, an operation and a reason
/// (D0 F16): an entry that excludes "everything" or gives no rationale is not
/// a documented exclusion.
List<String> checkExclusions(List<Exclusion> exclusions) {
  final violations = <String>[];
  for (var i = 0; i < exclusions.length; i++) {
    final e = exclusions[i];
    final where = 'exclusions.yaml entry ${i + 1}';
    if (e.coin.trim().isEmpty) violations.add('(c) $where has no coin');
    if (e.operation.trim().isEmpty) {
      violations.add('(c) $where has no operation');
    }
    if (e.reason.trim().isEmpty) violations.add('(c) $where has no reason');
  }
  return violations;
}

/// PRD §13.2 (c): compares [current] with the previous committed matrix
/// ([baseline], the decoded `capability_matrix.json`). A (coin, operation,
/// variant, platform) level that went down, a *Tested* flag that went false, a
/// cell that disappeared, or a vector that disappeared is a violation unless
/// [exclusions] has an entry for it.
List<String> checkAgainstBaseline(
  Matrix current,
  Map<String, Object?> baseline,
  List<Exclusion> exclusions,
) {
  final violations = <String>[];
  if (baseline['schema'] != schemaVersion) {
    return [
      '(c) the baseline matrix has schema ${baseline['schema']}, this tool '
          'reads $schemaVersion',
    ];
  }

  final now = {for (final row in current.coins) row.coin.id: row};
  final oldCoins = baseline['coins']! as Map<String, Object?>;
  for (final coinEntry in oldCoins.entries) {
    final coin = coinEntry.key;
    final oldOperations =
        (coinEntry.value! as Map<String, Object?>)['operations']!
            as Map<String, Object?>;
    for (final opEntry in oldOperations.entries) {
      final operation = opEntry.key;
      final oldVariants =
          (opEntry.value! as Map<String, Object?>)['variants']!
              as Map<String, Object?>;
      for (final variantEntry in oldVariants.entries) {
        final variant = variantEntry.key;
        if (isExcluded(exclusions, coin, operation, variant)) continue;
        final label = '$coin/$operation/$variant';
        final old = variantEntry.value! as Map<String, Object?>;
        final cell = now[coin]?.operations[operation]?.variants[variant];
        if (cell == null) {
          violations.add(
            '(c) $label is no longer generated (it was in the previous '
            'matrix); add an exclusions.yaml entry with a reason or restore it',
          );
          continue;
        }
        final oldLevels = old['levels']! as Map<String, Object?>;
        for (final platform in platforms) {
          final before = oldLevels[platform] as int? ?? 0;
          final after = cell.levelOn(platform);
          if (after < before) {
            violations.add(
              '(c) level of $label on $platform went down, $before -> $after; '
              'add an exclusions.yaml entry with a reason or restore it',
            );
          }
        }
        if (old['tested'] == true && !cell.tested) {
          violations.add(
            '(c) $label is no longer tested on both platforms; add an '
            'exclusions.yaml entry with a reason or restore it',
          );
        }
      }
    }
  }

  final nowIds = {for (final v in current.vectors) v.id};
  for (final old in (baseline['vectors']! as List<Object?>)) {
    final vector = old! as Map<String, Object?>;
    final id = vector['id']! as String;
    if (nowIds.contains(id)) continue;
    if (isExcluded(
      exclusions,
      vector['coin']! as String,
      vector['operation']! as String,
      vector['variant']! as String,
    )) {
      continue;
    }
    violations.add(
      '(c) vector $id was removed; add an exclusions.yaml entry with a reason '
      'for ${vector['coin']}/${vector['operation']}/${vector['variant']} or '
      'restore it',
    );
  }
  return violations;
}

/// The committed matrix at [ref] (`git show <ref>:docs/capability_matrix.json`),
/// or `null` when git, the ref or the file is not there — the first commit that
/// adds the matrix has nothing to compare with.
Map<String, Object?>? readBaselineFromGit(String root, String ref) {
  const path = 'docs/capability_matrix.json';
  try {
    final result = Process.runSync('git', ['-C', root, 'show', '$ref:$path']);
    if (result.exitCode != 0) return null;
    return jsonDecode(result.stdout as String) as Map<String, Object?>;
  } on Object {
    return null;
  }
}

// ---------------------------------------------------------------------------
// (a) every Tested claim has a passing vector
// ---------------------------------------------------------------------------

const _resultStatuses = {'pass', 'fail', 'skipped'};

class ResultsReport {
  ResultsReport(this.violations, this.unconfirmed);

  /// Claims contradicted by a results file, and malformed results files.
  final List<String> violations;

  /// Claims with no results file to check them against.
  final List<String> unconfirmed;
}

/// PRD §13.2 (a): every platform a vector claims in `platforms_verified`
/// (`android`, `ios`) must be `pass` in `<resultsDir>/<platform>.json`, which
/// CI writes (schema in `test_vectors/results/README.md`). When the file does
/// not exist the claim is reported as unconfirmed; the caller decides whether
/// that fails (`--strict`).
ResultsReport checkResults({
  required Inventory inventory,
  required String resultsDir,
  required Upstream upstream,
}) {
  final violations = <String>[];
  final unconfirmed = <String>[];
  for (final platform in platforms) {
    final claims = [
      for (final v in inventory.vectors)
        if (v.platformsVerified.contains(platform)) v.id,
    ]..sort();
    final file = File('$resultsDir/$platform.json');
    final display = 'test_vectors/results/$platform.json';
    if (!file.existsSync()) {
      for (final id in claims) {
        unconfirmed.add(
          'unconfirmed: vector $id claims $platform and $display does not exist',
        );
      }
      continue;
    }
    final Map<String, Object?> json;
    try {
      json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    } on Object catch (e) {
      violations.add('(a) $display is not readable JSON: $e');
      continue;
    }
    final problems = _resultsFileProblems(json, platform, upstream);
    if (problems.isNotEmpty) {
      violations.addAll(['(a) $display: ${problems.join('; ')}']);
      continue;
    }
    final status = <String, String>{};
    for (final entry in (json['results']! as List<Object?>)) {
      final result = entry! as Map<String, Object?>;
      status[result['id']! as String] = result['status']! as String;
    }
    for (final id in claims) {
      final recorded = status[id];
      if (recorded != 'pass') {
        violations.add(
          '(a) vector $id claims $platform in platforms_verified but $display '
          'records ${recorded ?? 'no entry'}',
        );
      }
    }
  }
  return ResultsReport(violations, unconfirmed);
}

List<String> _resultsFileProblems(
  Map<String, Object?> json,
  String platform,
  Upstream upstream,
) {
  final problems = <String>[];
  if (json['schema'] != 1) problems.add('schema must be 1');
  if (json['platform'] != platform) problems.add('platform must be $platform');
  final recorded = json['upstream'];
  if (recorded is! Map<String, Object?> ||
      recorded['tag'] != upstream.tag ||
      recorded['commit'] != upstream.commit) {
    problems.add(
      'upstream tag and commit must be the pinned ${upstream.tag} '
      '${upstream.commit} (stale results)',
    );
  }
  for (final key in ['repository_sha', 'run_id']) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      problems.add('$key must be a non-empty string');
    }
  }
  final results = json['results'];
  if (results is! List<Object?>) {
    problems.add('results must be a list');
  } else {
    for (final r in results) {
      if (r is! Map<String, Object?> ||
          r['id'] is! String ||
          !_resultStatuses.contains(r['status'])) {
        problems.add(
          'every result needs a string id and a status of pass, fail or skipped',
        );
        break;
      }
    }
  }
  return problems;
}
