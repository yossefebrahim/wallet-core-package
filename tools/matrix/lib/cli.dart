import 'inputs.dart';

/// Options of `gen:matrix` and `matrix:check`. The path options override one
/// input; each defaults to the repository layout under `--root` (default `.`,
/// where melos runs the scripts).
class CliOptions {
  CliOptions({
    required this.paths,
    required this.baselinePath,
    required this.baselineRef,
    required this.strict,
  });

  final MatrixPaths paths;

  /// A decoded-baseline file for check (c); when `null` the baseline is read
  /// from git at [baselineRef].
  final String? baselinePath;
  final String baselineRef;

  /// Unconfirmed *Tested* claims fail check (a).
  final bool strict;
}

const _pathOptions = {
  '--root',
  '--vectors',
  '--docs-dir',
  '--exposed',
  '--evidence',
  '--results-dir',
  '--registry-dir',
  '--proto-dir',
  '--manifest',
};

const _checkOnlyOptions = {'--baseline', '--baseline-ref'};

/// Parses [args]; returns `null` when they are not valid, and the caller exits
/// 64. [forCheck] additionally allows `--baseline`, `--baseline-ref` and
/// `--strict`.
CliOptions? parseArgs(List<String> args, {required bool forCheck}) {
  final values = <String, String>{};
  var strict = false;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--strict' && forCheck) {
      strict = true;
    } else if (_pathOptions.contains(arg) ||
        (forCheck && _checkOnlyOptions.contains(arg))) {
      if (i + 1 >= args.length) return null;
      values[arg] = args[++i];
    } else {
      return null;
    }
  }
  final root = values['--root'] ?? '.';
  return CliOptions(
    paths: MatrixPaths(
      root: root,
      vectorsDir: values['--vectors'],
      docsDir: values['--docs-dir'],
      exposedFile: values['--exposed'],
      evidenceFile: values['--evidence'],
      resultsDir: values['--results-dir'],
      registryDir: values['--registry-dir'],
      protoDir: values['--proto-dir'],
      manifestFile: values['--manifest'],
    ),
    baselinePath: values['--baseline'],
    baselineRef: values['--baseline-ref'] ?? 'HEAD',
    strict: strict,
  );
}

const pathOptionsUsage =
    '  [--root <dir>] [--vectors <dir>] [--docs-dir <dir>] [--exposed <file>]\n'
    '  [--evidence <file>] [--results-dir <dir>] [--registry-dir <dir>]\n'
    '  [--proto-dir <dir>] [--manifest <file>]';
