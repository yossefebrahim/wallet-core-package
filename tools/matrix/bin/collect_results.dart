import 'dart:convert';
import 'dart:io';

import 'package:wcf_tool_matrix/collect.dart';
import 'package:wcf_tool_matrix/inputs.dart';
import 'package:wcf_tool_matrix/variants.dart' show platforms;
import 'package:wcf_tool_vectors/inventory.dart';

const usage =
    'Usage: matrix:collect --platform <android|ios> --out <dir>\n'
    '  [--repository-sha <sha>] [--run-id <id>] [--root <dir>]\n'
    '  [--vectors <dir>] [--manifest <file>] <device-test log>...\n'
    'Reads the WCF_VECTOR_RESULT lines of the logs and writes\n'
    '<dir>/<platform>.json (schema: test_vectors/results/README.md).\n'
    '--repository-sha and --run-id default to GITHUB_SHA and GITHUB_RUN_ID.\n'
    'Exit 0 written; 1 a log line is malformed or an id is not in the\n'
    'inventory (nothing is written); 64 usage.';

const _valueOptions = {
  '--platform',
  '--out',
  '--repository-sha',
  '--run-id',
  '--root',
  '--vectors',
  '--manifest',
};

/// `melos run matrix:collect`: one device run's logs become
/// `test_vectors/results/<platform>.json` (T2.8b).
void main(List<String> args) {
  final values = <String, String>{};
  final logs = <String>[];
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (_valueOptions.contains(arg)) {
      if (i + 1 >= args.length) _usage();
      values[arg] = args[++i];
    } else if (arg.startsWith('--')) {
      _usage();
    } else {
      logs.add(arg);
    }
  }
  final platform = values['--platform'];
  final out = values['--out'];
  if (platform == null || !platforms.contains(platform)) _usage();
  if (out == null || logs.isEmpty) _usage();
  final env = Platform.environment;
  final sha = values['--repository-sha'] ?? env['GITHUB_SHA'] ?? '';
  final runId = values['--run-id'] ?? env['GITHUB_RUN_ID'] ?? '';
  if (sha.isEmpty || runId.isEmpty) {
    stderr
      ..writeln(
        'matrix:collect: a repository sha and a run id are required '
        '(--repository-sha / GITHUB_SHA, --run-id / GITHUB_RUN_ID)',
      )
      ..writeln(usage);
    exit(64);
  }

  final paths = MatrixPaths(
    root: values['--root'] ?? '.',
    vectorsDir: values['--vectors'],
    manifestFile: values['--manifest'],
  );
  try {
    final upstream = readUpstream(File(paths.manifestFile));
    final inventory = Inventory.load(Directory(paths.vectorsDir));
    if (inventory.loadProblems.isNotEmpty) {
      throw FormatException(inventory.loadProblems.join('; '));
    }
    final results = <({String id, String status})>[];
    for (final path in logs) {
      final log = File(path);
      if (!log.existsSync()) {
        throw FormatException('log not found: $path');
      }
      results.addAll(
        parseResultLines(
          // Device logs can hold bytes that are not UTF-8.
          utf8.decode(log.readAsBytesSync(), allowMalformed: true),
          source: path,
        ),
      );
    }
    final file = buildResultsFile(
      platform: platform,
      upstreamTag: upstream.tag,
      upstreamCommit: upstream.commit,
      repositorySha: sha,
      runId: runId,
      results: results,
      knownIds: {for (final v in inventory.vectors) v.id},
    );
    final target = File('$out/$platform.json');
    target.parent.createSync(recursive: true);
    target.writeAsStringSync(encodeResultsFile(file));
    final entries = (file['results']! as List<Object?>).length;
    stdout.writeln(
      'matrix:collect: wrote ${target.path} ($entries vectors from '
      '${results.length} result lines in ${logs.length} logs)',
    );
    if (entries == 0) {
      stdout.writeln(
        'matrix:collect: warning: no WCF_VECTOR_RESULT line in the logs; '
        'every claim for $platform will fail matrix:check',
      );
    }
  } on FormatException catch (e) {
    stderr.writeln('matrix:collect: ${e.message}');
    exit(1);
  }
}

Never _usage() {
  stderr.writeln(usage);
  exit(64);
}
