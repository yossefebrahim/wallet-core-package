import 'dart:io';

import 'package:wcf_tool_matrix/checks.dart';
import 'package:wcf_tool_matrix/cli.dart';
import 'package:wcf_tool_matrix/inputs.dart';
import 'package:wcf_tool_matrix/load.dart';
import 'package:wcf_tool_matrix/matrix.dart';

const usage =
    'Usage: gen:matrix\n$pathOptionsUsage\n'
    'Writes capability_matrix.md and capability_matrix.json into --docs-dir '
    '(default <root>/docs).';

/// `melos run gen:matrix`: computes the capability matrix (PRD §13) and writes
/// `docs/capability_matrix.{md,json}`. Exit 0; 1 when an input is missing or the
/// inputs are inconsistent (nothing is written); 64 on a usage error.
void main(List<String> args) {
  final options = parseArgs(args, forCheck: false);
  if (options == null) {
    stderr.writeln(usage);
    exit(64);
  }
  final MatrixInputs inputs;
  try {
    inputs = loadInputs(options.paths);
  } on FormatException catch (e) {
    stderr.writeln('gen:matrix: ${e.message}');
    exit(1);
  }
  final result = buildMatrix(inputs);
  if (result.problems.isNotEmpty) {
    for (final problem in result.problems) {
      stderr.writeln('gen:matrix: $problem');
    }
    stderr.writeln(
      'gen:matrix: ${result.problems.length} inconsistencies; nothing written',
    );
    exit(1);
  }
  writeOutputs(result.matrix, Directory(options.paths.docsDir));
  stdout.writeln(
    'gen:matrix: wrote ${options.paths.matrixMarkdown} and '
    '${options.paths.matrixJson} (${result.matrix.coins.length} coins, '
    '${result.matrix.conflicts.length} conflicts)',
  );
}
