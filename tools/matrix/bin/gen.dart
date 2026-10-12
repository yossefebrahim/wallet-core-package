import 'dart:io';

import 'package:wcf_tool_matrix/checks.dart';
import 'package:wcf_tool_matrix/cli.dart';
import 'package:wcf_tool_matrix/inputs.dart';
import 'package:wcf_tool_matrix/load.dart';
import 'package:wcf_tool_matrix/matrix.dart';
import 'package:wcf_tool_matrix/readme_counts.dart';

const usage =
    'Usage: gen:matrix\n$pathOptionsUsage\n'
    'Writes capability_matrix.md and capability_matrix.json into --docs-dir '
    '(default <root>/docs) and regenerates the region of README.md between '
    '<!-- matrix-counts --> and <!-- /matrix-counts --> (--readme).';

/// `melos run gen:matrix`: computes the capability matrix (PRD §13) and writes
/// `docs/capability_matrix.{md,json}` and the README counts region (T2.11).
/// Exit 0; 1 when an input is missing, the inputs are inconsistent or the
/// README markers are wrong (nothing is written); 64 on a usage error.
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
  final String readme;
  try {
    readme = regeneratedReadme(options.paths, result.matrix);
  } on FormatException catch (e) {
    stderr.writeln('gen:matrix: ${e.message}; nothing written');
    exit(1);
  }
  writeOutputs(result.matrix, Directory(options.paths.docsDir));
  File(options.paths.readmeFile).writeAsStringSync(readme);
  stdout.writeln(
    'gen:matrix: wrote ${options.paths.matrixMarkdown}, '
    '${options.paths.matrixJson} and the counts in ${options.paths.readmeFile} (${result.matrix.coins.length} coins, '
    '${result.matrix.conflicts.length} conflicts)',
  );
}
