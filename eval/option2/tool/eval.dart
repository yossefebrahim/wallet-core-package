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
//                  DECISION-14 §5.1 records of a published artifact set
//                  (run once, by hand; the output is committed and reviewed,
//                  and is the integrity root of the evaluation — run_eval.sh
//                  never regenerates it from the untrusted records)
//   identity       print `<artifact_set_id> <upstream_commit>` of a manifest
//   flip           write a copy of a manifest with one artifact's digest
//                  changed consistently in `sha256` and `asset_name`, so the
//                  manifest stays self-consistent and only the bytes disagree
//   add-artifact   write a copy of a manifest with one more row, for a file
//                  the evaluation supplies (step 9's counterfactual
//                  libc++_shared.so rows), under $OUT only
//   row            append one evaluation-owned result row (the harness schema:
//                  check, target, status, values, command, notes)
//   json-get       print one string field of a JSON file (a dotted key walks
//                  nested objects), so the script reads toolchain facts
//                  (`flutter --version --machine`, the manifest's
//                  `toolchain.ndk`) at run time instead of hard-coding them
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
    case 'add-artifact':
      _addArtifact(options);
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
    'make-manifest|identity|flip|add-artifact|row|json-get|scrub|embed '
    '[--name value]...',
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
  // A dotted key walks nested objects: `toolchain.ndk`. A key may itself
  // contain dots (`artifacts.android/x86_64/libTrustWalletCore.so.sha256`),
  // so each step takes the longest run of parts that names a key.
  Object? value = _readJson(_one(options, 'file'));
  final parts = _one(options, 'key').split('.');
  var i = 0;
  while (i < parts.length && value is Map<String, Object?>) {
    final map = value;
    var j = parts.length;
    while (j > i && !map.containsKey(parts.sublist(i, j).join('.'))) {
      j--;
    }
    if (j == i) {
      value = null;
      break;
    }
    value = map[parts.sublist(i, j).join('.')];
    i = j;
  }
  if (i < parts.length) value = null;
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

  // The root manifest's rows, overlaid with the set's DECISION-14 §5.1
  // records as they are. Since the published set as_4.8.0_001 (main f9f3d58)
  // the records carry a real `build_workflow` and the root manifest carries
  // that set's identity, retention URL and per-slice rows, so nothing is
  // substituted any more: for that set the result holds the root's values.
  // (Until T1.9b the set was a local build, as_4.8.0_000, and this tool wrote
  // `.invalid` stand-ins for its `"local"` build_workflow and for
  // retention.primary, and dropped the root's xcframework-zip row.) A record
  // that is not a published one is refused rather than papered over.
  final artifacts = Map<String, Object?>.of(
    root['artifacts']! as Map<String, Object?>,
  );

  String? setId;
  String? commit;
  final xcodes = <Object?>{};
  final files =
      records
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final record = _readJson(file.path);
    for (final entry in record.entries) {
      final fields = entry.value! as Map<String, Object?>;
      final workflow = fields['build_workflow'];
      if (workflow is! String || !workflow.startsWith('https://')) {
        stderr.writeln(
          '${file.path}: build_workflow "$workflow" is not a published '
          'workflow run; the evaluation manifest takes published sets only',
        );
        exit(1);
      }
      final recordSet = (fields['asset_name']! as String).split('__').first;
      if (setId != null && setId != recordSet) {
        stderr.writeln('records span two sets, $setId and $recordSet');
        exit(1);
      }
      setId = recordSet;
      commit ??= fields['source_commit']! as String;
      final toolchain = fields['toolchain'] as Map<String, Object?>?;
      if (toolchain != null && toolchain.containsKey('xcode')) {
        xcodes.add(toolchain['xcode']);
      }
      artifacts[entry.key] = fields;
    }
  }
  if (setId == null) {
    stderr.writeln('no records under ${records.path}');
    exit(1);
  }

  final identity = root['identity']! as Map<String, Object?>;
  if (identity['artifact_set_id'] != setId ||
      identity['upstream_commit'] != commit) {
    stderr.writeln(
      "the records are set $setId @ $commit, the root manifest's identity "
      "${identity['artifact_set_id']} @ ${identity['upstream_commit']}; "
      'copy the root compat_manifest.json of that set first',
    );
    exit(1);
  }
  final toolchain = Map<String, Object?>.of(
    root['toolchain']! as Map<String, Object?>,
  );
  // Every Apple record agrees on this; the validator checks it.
  if (xcodes.length == 1) toolchain['xcode'] = xcodes.single;

  final manifest = Map<String, Object?>.of(root)
    ..['artifacts'] = artifacts
    ..['toolchain'] = toolchain;
  File(out).writeAsStringSync('${_pretty.convert(manifest)}\n');
  stdout.writeln('wrote $out (set $setId, ${files.length} records)');
}

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

/// A copy of a manifest with one more artifact row, for a file the
/// evaluation supplies itself: every field is copied from the `--like` row,
/// then `sha256`/`size` are the file's own (through `shasum -a 256`, the same
/// system command the harness's size check records) and `asset_name` /
/// `logical_name` follow the manifest's grammar. Step 9 uses it to ask what
/// Option 2 does with a `libc++_shared.so` row (a counterfactual `c++_shared`
/// set); the result is written under `$OUT` only, never committed.
void _addArtifact(Map<String, List<String>> options) {
  final manifest = _readJson(_one(options, 'manifest'));
  final artifacts = manifest['artifacts']! as Map<String, Object?>;
  final name = _one(options, 'name');
  final like = artifacts[_one(options, 'like')] as Map<String, Object?>?;
  if (like == null) {
    stderr.writeln('no artifact ${_one(options, 'like')}');
    exit(1);
  }
  final file = File(_one(options, 'file'));
  final shasum = Process.runSync('shasum', ['-a', '256', file.path]);
  if (shasum.exitCode != 0) {
    stderr.writeln('shasum failed on ${file.path}: ${shasum.stderr}');
    exit(1);
  }
  final sha = (shasum.stdout as String).split(' ').first.trim();
  final setId = (like['asset_name']! as String).split('__').first;
  artifacts[name] = {
    ...like,
    'sha256': sha,
    'size': file.lengthSync(),
    'asset_name': '${setId}__${sha}__${name.replaceAll('/', '-')}',
    'logical_name': name,
  };
  File(
    _one(options, 'out'),
  ).writeAsStringSync('${_pretty.convert(manifest)}\n');
  stdout.writeln('$name: $sha (${file.lengthSync()} B)');
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
