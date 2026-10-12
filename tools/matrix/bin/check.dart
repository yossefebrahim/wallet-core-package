import 'dart:convert';
import 'dart:io';

import 'package:wcf_tool_matrix/checks.dart';
import 'package:wcf_tool_matrix/cli.dart';
import 'package:wcf_tool_matrix/inputs.dart';
import 'package:wcf_tool_matrix/load.dart';
import 'package:wcf_tool_matrix/matrix.dart';

const usage =
    'Usage: matrix:check [--strict] [--baseline <capability_matrix.json>]\n'
    '  [--baseline-ref <git ref>]\n$pathOptionsUsage\n'
    'Exit 0 all checks pass; 1 one or more fail (one line each on stderr); '
    '64 usage.';

/// `melos run matrix:check`: PRD §13.2 (a)–(c), and (d), T2.11.
///
/// * (a) every `platforms_verified` claim is `pass` in the matching
///   `test_vectors/results/<platform>.json`; a claim with no results file is
///   reported `unconfirmed` and fails only under `--strict`.
/// * (b) `docs/capability_matrix.{md,json}` equal a fresh regeneration.
/// * (c) no level went down and no vector disappeared relative to the previous
///   committed matrix (`git show <ref>:docs/capability_matrix.json`, `HEAD`
///   unless `--baseline-ref`, or the file of `--baseline`), unless
///   `exclusions.yaml` has an entry with a reason.
/// * (d) the README region between the `matrix-counts` markers equals a fresh
///   regeneration.
void main(List<String> args) {
  final options = parseArgs(args, forCheck: true);
  if (options == null) {
    stderr.writeln(usage);
    exit(64);
  }
  final paths = options.paths;
  final MatrixInputs inputs;
  try {
    inputs = loadInputs(paths);
  } on FormatException catch (e) {
    stderr.writeln('matrix:check: ${e.message}');
    exit(1);
  }

  final violations = <String>[];
  final notes = <String>[];

  final result = buildMatrix(inputs);
  violations.addAll(result.problems);

  // (b)
  violations.addAll(checkRegeneration(paths, result.matrix));

  // (d)
  violations.addAll(checkReadme(paths, result.matrix));

  // (c)
  violations.addAll(checkExclusions(inputs.inventory.exclusions));
  Map<String, Object?>? baseline;
  if (options.baselinePath != null) {
    final file = File(options.baselinePath!);
    if (!file.existsSync()) {
      stderr.writeln('matrix:check: --baseline ${file.path} does not exist');
      exit(64);
    }
    try {
      baseline = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    } on Object catch (e) {
      stderr.writeln(
        'matrix:check: --baseline ${file.path} is not a matrix: $e',
      );
      exit(64);
    }
  } else {
    baseline = readBaselineFromGit(paths.root, options.baselineRef);
    if (baseline == null) {
      notes.add(
        '(c) skipped: no docs/capability_matrix.json at ${options.baselineRef} '
        'to compare with (the commit that adds the matrix has none)',
      );
    }
  }
  if (baseline != null) {
    violations.addAll(
      checkAgainstBaseline(
        result.matrix,
        baseline,
        inputs.inventory.exclusions,
      ),
    );
  }

  // (a)
  final report = checkResults(
    inventory: inputs.inventory,
    resultsDir: paths.resultsDir,
    upstream: inputs.upstream,
  );
  violations.addAll(report.violations);
  if (options.strict) {
    violations.addAll(report.unconfirmed.map((u) => '(a) $u (--strict)'));
  } else {
    notes.addAll(report.unconfirmed);
  }

  for (final note in notes) {
    stdout.writeln('matrix:check: $note');
  }
  if (violations.isNotEmpty) {
    for (final violation in violations) {
      stderr.writeln('matrix:check: $violation');
    }
    stderr.writeln('matrix:check: FAILED, ${violations.length} violations');
    exit(1);
  }
  stdout.writeln(
    'matrix:check: ok (${result.matrix.coins.length} coins, '
    '${result.matrix.vectors.length} vectors${options.strict ? ', strict' : ''})',
  );
}
