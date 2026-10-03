// Small helpers for eval/option2/run_eval.sh that are not measurements.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.
//
// DECISION-2 Option 2 evaluation (T1.9), evaluation branch only. Every
// measurement run_eval.sh records goes through tools/packaging_eval; this file
// only does what the harness has no command for:
//
//   make-manifest  build eval_manifest.json from the root manifest and the
//                  DECISION-14 §5.1 records of a local artifact set (run once,
//                  by hand; the output is committed and reviewed, and is the
//                  integrity root of the evaluation — run_eval.sh never
//                  regenerates it from the untrusted records)
//   identity       print `<artifact_set_id> <upstream_commit>` of a manifest
//   flip           write a copy of a manifest with one artifact's digest
//                  changed consistently in `sha256` and `asset_name`, so the
//                  manifest stays self-consistent and only the bytes disagree
//   row            append one evaluation-owned result row (the harness schema:
//                  check, target, status, values, command, notes)
//   json-get       print one top-level string field of a JSON file, so the
//                  script reads toolchain facts (`flutter --version --machine`)
//                  at run time instead of hard-coding them
//   scrub          rewrite every string in a results.jsonl, replacing
//                  machine-specific path prefixes (`--replace FROM=TO`,
//                  longest FROM first), so committed results name `$OUT`,
//                  `<repo>` and `~` instead of a home directory
//   embed          copy the rendered table, the uncatalogued rows and the
//                  row counts into the generated block of the decision
//                  document, between `<!-- BEGIN run_eval.sh results -->` and
//                  `<!-- END run_eval.sh results -->`, so the document cannot
//                  disagree with results/
//
// dart:io and dart:convert only, so it runs with no package resolution.

import 'dart:convert';
import 'dart:io';

void main(List<String> argv) {
  if (argv.isEmpty) _usage();
  final options = _parse(argv.skip(1).toList());
  switch (argv.first) {
    case 'make-manifest':
      _makeManifest(options);
    case 'identity':
      _identity(options);
    case 'flip':
      _flip(options);
    case 'row':
      _row(options);
    case 'json-get':
      _jsonGet(options);
    case 'scrub':
      _scrub(options);
    case 'embed':
      _embed(options);
    default:
      _usage();
  }
}

Never _usage() {
  stderr.writeln(
    'usage: dart eval/option2/tool/eval.dart '
    'make-manifest|identity|flip|row|json-get|scrub|embed [--name value]...',
  );
  exit(64);
}

void _scrub(Map<String, List<String>> options) {
  final replacements = <MapEntry<String, String>>[];
  for (final pair in options['replace'] ?? const <String>[]) {
    final eq = pair.indexOf('=');
    // A prefix shorter than two characters (an empty or `/` HOME) would
    // rewrite every path.
    if (eq < 2) continue;
    replacements.add(MapEntry(pair.substring(0, eq), pair.substring(eq + 1)));
  }
  replacements.sort((a, b) => b.key.length.compareTo(a.key.length));

  Object? walk(Object? value) => switch (value) {
    String s => replacements.fold<String>(
      s,
      (t, r) => t.replaceAll(r.key, r.value),
    ),
    List<Object?> l => [for (final e in l) walk(e)],
    Map<String, Object?> m => {for (final e in m.entries) e.key: walk(e.value)},
    _ => value,
  };

  final file = File(_one(options, 'file'));
  final lines = file
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty)
      .map((l) => jsonEncode(walk(jsonDecode(l))));
  file.writeAsStringSync(lines.map((l) => '$l\n').join());
}

/// report.dart writes a summary's own `|` unescaped, which splits the cell
/// (`ios-archive`: "(fstat,fstatat,lstat,stat | mach_absolute_time)"). Every
/// such `|` in this evaluation's summaries is inside parentheses; a column
/// separator never is.
String _escapeCellPipes(String line) {
  final out = StringBuffer();
  var depth = 0;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '(') depth++;
    if (c == ')' && depth > 0) depth--;
    final escaped = i > 0 && line[i - 1] == r'\';
    out.write(c == '|' && depth > 0 && !escaped ? r'\|' : c);
  }
  return out.toString();
}

const String _embedBegin = '<!-- BEGIN run_eval.sh results -->';
const String _embedEnd = '<!-- END run_eval.sh results -->';

void _embed(Map<String, List<String>> options) {
  final tableLines = File(_one(options, 'table')).readAsLinesSync();
  final start = tableLines.indexWhere((l) => l.startsWith('| PRD §12.2 step'));
  if (start < 0) {
    stderr.writeln('no results table in ${_one(options, 'table')}');
    exit(1);
  }
  final table = tableLines
      .skip(start)
      .takeWhile((l) => l.startsWith('|'))
      .map(_escapeCellPipes);
  final uncatalogued = tableLines
      .skipWhile((l) => l != '## Results with no catalogue row')
      .skip(1)
      .where((l) => l.startsWith('- '));

  final counts = <String, int>{
    for (final s in const ['pass', 'fail', 'skip', 'unmeasured']) s: 0,
  };
  var rows = 0;
  for (final line in File(_one(options, 'results')).readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    rows++;
    final status = (jsonDecode(line) as Map<String, Object?>)['status'];
    counts[status! as String] = (counts[status] ?? 0) + 1;
  }

  final block = StringBuffer()
    ..writeln(_embedBegin)
    ..writeln(
      '<!-- Written by eval/option2/run_eval.sh (tool/eval.dart embed) from '
      'eval/option2/results/; never edit by hand. -->',
    )
    ..writeln()
    ..writeln(
      '**$rows rows: ${counts['pass']} `pass`, ${counts['fail']} `fail`, '
      '${counts['skip']} `skip`, ${counts['unmeasured']} `unmeasured`.**',
    )
    ..writeln();
  table.forEach(block.writeln);
  if (uncatalogued.isNotEmpty) {
    block
      ..writeln()
      ..writeln('Results with no catalogue row:')
      ..writeln();
    uncatalogued.forEach(block.writeln);
  }
  block.write(_embedEnd);

  final doc = File(_one(options, 'doc'));
  final text = doc.readAsStringSync();
  final from = text.indexOf(_embedBegin);
  final to = text.indexOf(_embedEnd);
  if (from < 0 || to < from || text.indexOf(_embedBegin, from + 1) >= 0) {
    stderr.writeln(
      '${doc.path} needs exactly one $_embedBegin … $_embedEnd block',
    );
    exit(1);
  }
  doc.writeAsStringSync(
    '${text.substring(0, from)}$block'
    '${text.substring(to + _embedEnd.length)}',
  );
  stdout.writeln('embedded $rows rows into ${doc.path}');
}

void _jsonGet(Map<String, List<String>> options) {
  final value = _readJson(_one(options, 'file'))[_one(options, 'key')];
  if (value is! String) {
    stderr.writeln('no string field ${_one(options, 'key')}');
    exit(1);
  }
  stdout.writeln(value);
}

/// `--name value` pairs; `--value` and `--log-values` may repeat.
Map<String, List<String>> _parse(List<String> args) {
  final options = <String, List<String>>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--') || i + 1 >= args.length) _usage();
    options.putIfAbsent(arg.substring(2), () => []).add(args[++i]);
  }
  return options;
}

String _one(Map<String, List<String>> options, String name) {
  final values = options[name];
  if (values == null || values.length != 1) {
    stderr.writeln('--$name is required exactly once');
    exit(64);
  }
  return values.single;
}

String? _optional(Map<String, List<String>> options, String name) =>
    options[name]?.single;

Map<String, Object?> _readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

const JsonEncoder _pretty = JsonEncoder.withIndent('  ');

void _makeManifest(Map<String, List<String>> options) {
  final root = _readJson(_one(options, 'root'));
  final records = Directory(_one(options, 'records'));
  final out = _one(options, 'out');

  final artifacts = Map<String, Object?>.of(
    root['artifacts']! as Map<String, Object?>,
  );
  // The local set ships dylibs, not the CI xcframework zip the root manifest
  // names; the iOS plan prefers that row whenever it is present, so it is
  // dropped here. The Android rows stay `TBD-T1.2`: no Android artifact
  // exists, and the Gradle build must fail on them, not skip them.
  artifacts.remove('ios/TrustWalletCore.xcframework.zip');

  String? setId;
  String? commit;
  final files = records.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final record = _readJson(file.path);
    for (final entry in record.entries) {
      final fields = Map<String, Object?>.of(
        entry.value! as Map<String, Object?>,
      );
      // The records say `"build_workflow": "local"`. The validator requires an
      // absolute https URL once a digest is real, so the evaluation manifest
      // writes a host under `.invalid` (RFC 6761: never resolves), which says
      // the same thing — no workflow run produced this — in the validator's
      // grammar.
      if (fields['build_workflow'] == 'local') {
        fields['build_workflow'] = _localBuildWorkflow;
      }
      artifacts[entry.key] = fields;
      final assetName = fields['asset_name']! as String;
      setId ??= assetName.split('__').first;
      commit ??= fields['source_commit']! as String;
    }
  }

  final manifest = Map<String, Object?>.of(root)
    ..['artifacts'] = artifacts
    ..['toolchain'] = {
      ...(root['toolchain']! as Map<String, Object?>),
      // Every Apple record agrees on this; the validator checks it.
      'xcode': '17F113',
    }
    ..['identity'] = {
      ...(root['identity']! as Map<String, Object?>),
      'artifact_set_id': setId,
      'upstream_commit': commit,
      'build_workflow': _localBuildWorkflow,
    }
    ..['retention'] = {
      ...(root['retention']! as Map<String, Object?>),
      // Never contacted: run_eval.sh fetches with --offline from a vendored
      // directory. `.invalid` guarantees that a run without --offline fails
      // to resolve rather than reaching anything.
      'primary': 'https://eval-only.invalid/native-4.8.0-000',
    };
  File(out).writeAsStringSync('${_pretty.convert(manifest)}\n');
  stdout.writeln('wrote $out');
}

const String _localBuildWorkflow =
    'https://local-build.eval-only.invalid/as_4.8.0_000';

void _identity(Map<String, List<String>> options) {
  final identity =
      _readJson(_one(options, 'manifest'))['identity']! as Map<String, Object?>;
  stdout.writeln(
    '${identity['artifact_set_id']} ${identity['upstream_commit']}',
  );
}

void _flip(Map<String, List<String>> options) {
  final manifest = _readJson(_one(options, 'manifest'));
  final name = _one(options, 'artifact');
  final record =
      (manifest['artifacts']! as Map<String, Object?>)[name]
          as Map<String, Object?>?;
  if (record == null) {
    stderr.writeln('no artifact $name');
    exit(1);
  }
  final sha = record['sha256']! as String;
  final last = sha[sha.length - 1];
  final flipped =
      '${sha.substring(0, sha.length - 1)}${last == '0' ? '1' : '0'}';
  record['sha256'] = flipped;
  record['asset_name'] = (record['asset_name']! as String).replaceFirst(
    sha,
    flipped,
  );
  File(
    _one(options, 'out'),
  ).writeAsStringSync('${_pretty.convert(manifest)}\n');
  stdout.writeln('$name: $sha -> $flipped');
}

void _row(Map<String, List<String>> options) {
  final values = <String, Object?>{};
  for (final pair in options['value'] ?? const <String>[]) {
    final eq = pair.indexOf('=');
    if (eq < 1) {
      stderr.writeln('--value needs key=value, got "$pair"');
      exit(64);
    }
    values[pair.substring(0, eq)] = pair.substring(eq + 1);
  }
  // Lines a run printed as `WCF-EVAL key=value`, harvested verbatim.
  for (final log in options['log-values'] ?? const <String>[]) {
    final file = File(log);
    if (!file.existsSync()) continue;
    for (final line in file.readAsLinesSync()) {
      final at = line.indexOf('WCF-EVAL ');
      if (at < 0) continue;
      final pair = line.substring(at + 'WCF-EVAL '.length).trim();
      final eq = pair.indexOf('=');
      if (eq > 0) values[pair.substring(0, eq)] = pair.substring(eq + 1);
    }
  }
  final summary = _optional(options, 'summary');
  if (summary != null) values['summary'] = summary;

  final status = _one(options, 'status');
  if (!const ['pass', 'fail', 'skip', 'unmeasured'].contains(status)) {
    stderr.writeln('unknown status $status');
    exit(64);
  }
  final row = <String, Object?>{
    'check': _one(options, 'check'),
    'target': _one(options, 'target'),
    'status': status,
    'values': values,
    'command': _one(options, 'command'),
    'notes': _optional(options, 'notes') ?? '',
  };
  File(
    _one(options, 'out'),
  ).writeAsStringSync('${jsonEncode(row)}\n', mode: FileMode.append);
}
