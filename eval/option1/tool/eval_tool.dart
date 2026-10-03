// Small helpers run_eval.sh needs that the shared harness does not provide.
// Everything that *measures* is the harness's (tools/packaging_eval); this
// file only writes evaluation-owned result rows in the harness's schema,
// reads the eval manifest, and prepares scratch copies under $TMPDIR.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.
//
//   row --out F --check C --target T --status S --command CMD
//       [--summary TEXT] [--notes TEXT] [--value k=v]...
//       [--repo DIR] [--tmp DIR] [--home DIR]
//                                  (rewrite those paths as repo-relative,
//                                   $TMPDIR-relative and ~-relative)
//   relativize RESULTS --repo DIR --tmp DIR --home DIR
//                                  (the same rewrite over every row already in
//                                   RESULTS, the harness's included)
//   classify-macos-build LOG [PROJECT]
//   classify-negative LOG MANIFEST LOGICAL_NAME
//   offline-evidence APP_DIR LOGICAL_NAME
//   embed-table TABLE RESULTS DOC
//   embedded-binaries APP
//   value MANIFEST dotted.path
//   verify-set MANIFEST ARTIFACT_DIR
//   flip MANIFEST LOGICAL_NAME OUT
//   stage CONSUMER DEST [--manifest ABS]
//   pick-device DEVICES_JSON ios-simulator|ios-device|android-emulator|android-device
//
// Pure dart:io and dart:convert, so it runs with no package resolution. The
// verdict functions (classifyNegative, offlineEvidence, embedTable,
// relativizer) are public so that
// packages/wallet_core_flutter_native/test/eval_option1/eval_tool_test.dart
// can test them; that test is how `melos run test` covers this file.

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.isEmpty) _usage();
  final rest = args.sublist(1);
  switch (args.first) {
    case 'row':
      _row(rest);
    case 'relativize':
      _relativize(rest);
    case 'value':
      _value(rest);
    case 'verify-set':
      await _verifySet(rest);
    case 'flip':
      _flip(rest);
    case 'stage':
      _stage(rest);
    case 'pick-device':
      _pickDevice(rest);
    case 'classify-macos-build':
      _classifyMacosBuild(rest);
    case 'classify-negative':
      _classifyNegative(rest);
    case 'offline-evidence':
      _offlineEvidence(rest);
    case 'embed-table':
      _embedTable(rest);
    case 'embedded-binaries':
      _embeddedBinaries(rest);
    default:
      _usage();
  }
}

Never _usage() {
  stderr.writeln(
    'usage: eval_tool.dart row|relativize|value|verify-set|flip|stage|'
    'pick-device|classify-macos-build|classify-negative|offline-evidence|'
    'embed-table|embedded-binaries … (see the header of this file)',
  );
  exit(64);
}

Never _die(String message) {
  stderr.writeln('eval_tool: $message');
  exit(1);
}

/// Appends one result row in tools/packaging_eval's JSON Lines schema.
void _row(List<String> args) {
  final options = <String, String>{};
  final values = <String, Object?>{};
  for (var i = 0; i + 1 < args.length; i += 2) {
    final key = args[i];
    final value = args[i + 1];
    if (key == '--value') {
      final eq = value.indexOf('=');
      if (eq < 1) _die('--value needs k=v, got $value');
      values[value.substring(0, eq)] = value.substring(eq + 1);
    } else if (key.startsWith('--')) {
      options[key.substring(2)] = value;
    } else {
      _die('unexpected argument $key');
    }
  }
  for (final required in ['out', 'check', 'target', 'status', 'command']) {
    if (!options.containsKey(required)) _die('row needs --$required');
  }
  const statuses = {'pass', 'fail', 'skip', 'unmeasured'};
  if (!statuses.contains(options['status'])) {
    _die('status must be one of $statuses');
  }
  if (options['summary'] != null) values['summary'] = options['summary'];
  final local = relativizer(
    repo: options['repo'],
    tmp: options['tmp'],
    home: options['home'],
  );
  final row = {
    'check': options['check'],
    'target': options['target'],
    'status': options['status'],
    'values': {
      for (final e in values.entries)
        e.key: e.value is String ? local(e.value! as String) : e.value,
    },
    'command': local(options['command']!),
    'notes': local(options['notes'] ?? ''),
  };
  final out = File(options['out']!)..parent.createSync(recursive: true);
  out.writeAsStringSync('${jsonEncode(row)}\n', mode: FileMode.append);
  stdout.writeln(
    '${options['status']!.padRight(10)} ${options['check']} '
    '${options['target']}: ${options['summary'] ?? ''}',
  );
}

/// Rewrites machine-local absolute paths in a row's text: the repository
/// root becomes repo-relative, the temporary directory becomes `$TMPDIR` and
/// the home directory becomes `~`, each in its spelled and its
/// symlink-resolved form (`/tmp` is `/private/tmp`, `/var/folders/…` is
/// `/private/var/folders/…`), so a committed results file names no one's home
/// directory. The longest directory wins, so a repository under the home
/// directory still becomes repo-relative.
String Function(String) relativizer({String? repo, String? tmp, String? home}) {
  // (directory length, pattern, replacement)
  final rules = <(int, RegExp, String)>[];
  void add(String? dir, String replacement) {
    if (dir == null || dir.isEmpty) return;
    var path = dir;
    while (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    final forms = {path, '/private$path'};
    try {
      forms.add(Directory(path).resolveSymbolicLinksSync());
    } on FileSystemException {
      // A directory that does not exist has no other spelling.
    }
    for (final form in forms) {
      // Only a whole path: not preceded by a path character (so `/tmp/x`
      // inside `/private/tmp/x` is left to the longer rule), and the bare
      // directory only where the path ends (`/a/repo` must not rewrite
      // `/a/repo-other`).
      final start = r'(?<![\w./-])';
      final escaped = RegExp.escape(form);
      rules.add((
        form.length,
        RegExp('$start$escaped/'),
        replacement.isEmpty ? '' : '$replacement/',
      ));
      rules.add((
        form.length,
        RegExp('$start$escaped(?=\$|[\\s;:,)"\'])'),
        replacement.isEmpty ? '.' : replacement,
      ));
    }
  }

  add(tmp, r'$TMPDIR');
  add(repo, '');
  add(home, '~');
  rules.sort((a, b) => b.$1.compareTo(a.$1));
  return (text) {
    var out = text;
    for (final (_, from, to) in rules) {
      out = out.replaceAll(from, to);
    }
    return out;
  };
}

/// Applies [relativizer] to every string in every row of RESULTS, in place.
///
/// Rows written by `tools/packaging_eval` carry the absolute paths the
/// harness printed (its artifact, app and NDK paths); `row` rewrites only the
/// rows this evaluation writes. Run once, after the last row and before
/// rendering, it leaves no home directory in the committed results (review
/// finding 14, T1.8a-d4).
void _relativize(List<String> args) {
  if (args.isEmpty) _usage();
  final options = <String, String>{};
  for (var i = 1; i + 1 < args.length; i += 2) {
    if (!args[i].startsWith('--')) _die('unexpected argument ${args[i]}');
    options[args[i].substring(2)] = args[i + 1];
  }
  final file = File(args.first);
  if (!file.existsSync()) _die('no such file: ${args.first}');
  final local = relativizer(
    repo: options['repo'],
    tmp: options['tmp'],
    home: options['home'],
  );
  final out = relativizeRows(file.readAsLinesSync(), local);
  file.writeAsStringSync(out.isEmpty ? '' : '${out.join('\n')}\n');
}

/// [lines] of a JSON Lines results file with [local] applied to every string
/// value at any depth. Blank lines are dropped; key order is kept.
List<String> relativizeRows(List<String> lines, String Function(String) local) {
  Object? walk(Object? node) => switch (node) {
    String s => local(s),
    List<Object?> l => [for (final e in l) walk(e)],
    Map<String, Object?> m => {for (final e in m.entries) e.key: walk(e.value)},
    _ => node,
  };
  return [
    for (final line in lines)
      if (line.trim().isNotEmpty) jsonEncode(walk(jsonDecode(line))),
  ];
}

/// Classifies a failed `flutter build macos` log.
///
/// Prints `template-deployment-target<TAB>VALUE<TAB>MIN<TAB>MAX` when Xcode
/// refused the generated project's `MACOSX_DEPLOYMENT_TARGET` — a property of
/// the `flutter create` template and the installed Xcode, independent of any
/// package.
///
/// Prints `podfile-missing<TAB>PLUGINS<TAB>SPM` when Flutter stopped with
/// `Podfile missing` and PROJECT (the app directory, optional) shows why:
/// `.flutter-plugins-dependencies` lists native plugins for other platforms
/// (PLUGINS, e.g. `integration_test`) and none for macOS, so Flutter runs
/// CocoaPods for macOS (its "has plugins" test is project-wide) but never
/// generates `macos/Podfile`, and Swift Package Manager is off for macOS
/// (SPM = the recorded `swift_package_manager_enabled.macos`). A tooling gap,
/// independent of any package; writing the Podfile by hand is a native edit.
///
/// `other` for anything else. Always exits 0.
void _classifyMacosBuild(List<String> args) {
  if (args.isEmpty || args.length > 2) _usage();
  final file = File(args.first);
  final text = file.existsSync() ? file.readAsStringSync() : '';
  final match = RegExp(
    r"The macOS deployment target 'MACOSX_DEPLOYMENT_TARGET' is set to "
    r'([0-9][0-9.]*), but the range of supported deployment target versions '
    r'is ([0-9][0-9.]*) to ([0-9][0-9.x]*[0-9x])',
  ).firstMatch(text);
  if (match != null) {
    stdout.write(
      'template-deployment-target\t${match[1]}\t${match[2]}\t${match[3]}',
    );
    return;
  }
  if (RegExp(r'^\s*Podfile missing\s*$', multiLine: true).hasMatch(text) &&
      args.length == 2) {
    final project = args[1];
    final deps = File('$project/.flutter-plugins-dependencies');
    if (!File('$project/macos/Podfile').existsSync() && deps.existsSync()) {
      try {
        final json =
            jsonDecode(deps.readAsStringSync()) as Map<String, Object?>;
        final plugins = json['plugins']! as Map<String, Object?>;
        final macos = (plugins['macos'] as List?) ?? const [];
        final elsewhere = <String>{
          for (final entry in plugins.entries)
            if (entry.key != 'macos')
              for (final p in (entry.value as List?) ?? const [])
                if (p is Map && p['native_build'] == true) '${p['name']}',
        }.toList()..sort();
        final spm =
            (json['swift_package_manager_enabled'] as Map?)?['macos'] ??
            'unknown';
        if (macos.isEmpty && elsewhere.isNotEmpty) {
          stdout.write('podfile-missing\t${elsewhere.join(',')}\t$spm');
          return;
        }
      } on Object {
        // Not the shape we know; fall through to `other`.
      }
    }
  }
  stdout.write('other');
}

/// `classify-negative LOG MANIFEST LOGICAL_NAME`: prints [classifyNegative]
/// of LOG's lines, for LOGICAL_NAME's digest in the (flipped) MANIFEST the
/// build ran against. Always exits 0.
void _classifyNegative(List<String> args) {
  if (args.length != 3) _usage();
  final file = File(args[0]);
  final lines = file.existsSync() ? file.readAsLinesSync() : const <String>[];
  final artifacts = _readJson(args[1])['artifacts']! as Map<String, Object?>;
  final record = artifacts[args[2]] as Map<String, Object?>?;
  if (record == null) _die('${args[1]} has no artifact ${args[2]}');
  stdout.write(
    classifyNegative(
      lines,
      logicalName: args[2],
      expectedSha256: record['sha256']! as String,
    ),
  );
}

/// Classifies the log of a build that ran against a manifest in which
/// [logicalName]'s digest was flipped to [expectedSha256].
///
/// Returns `KIND<TAB>EVIDENCE`:
/// - `digest-mismatch`: the log has the hook's one-line verdict for **this**
///   artifact against **this** digest —
///   `<logicalName>: sha256 mismatch: expected <expectedSha256> (… bytes),
///   found <other digest> (… bytes)`. The hook prints that line first
///   whenever the fetch tool reports a digest or size mismatch, and Xcode
///   keeps it (it starts with `error:`), so this is the only outcome that
///   shows the build failed *on the flipped digest*;
/// - `other`: anything else. EVIDENCE is then the most telling line found
///   (an `error:` line, else a "could not be verified" line), or empty.
///
/// There is deliberately no third kind. Before T1.8a-d4 a log holding only
/// the generic "could not be verified" headline counted as a passing
/// wrong-digest check, but the hook prints that headline for *every* fetch
/// failure — a vendored file that is missing, an offline cache miss, a
/// transport error — so it proves nothing about the digest (review
/// finding 3).
String classifyNegative(
  List<String> lines, {
  required String logicalName,
  required String expectedSha256,
}) {
  final verdict = RegExp(
    '${RegExp.escape(logicalName)}: sha256 mismatch: expected '
    '${RegExp.escape(expectedSha256)} \\(\\d+ bytes\\), '
    'found ([0-9a-f]{64}) \\(\\d+ bytes\\)',
  );
  for (final line in lines) {
    final m = verdict.firstMatch(line);
    if (m != null && m[1] != expectedSha256) {
      return 'digest-mismatch\t${line.trim()}';
    }
  }
  String? find(bool Function(String) test) {
    for (final line in lines) {
      if (test(line)) return line.trim();
    }
    return null;
  }

  final evidence =
      find((l) => l.contains('error:') && l.contains(logicalName)) ??
      find((l) => l.contains('could not be verified')) ??
      find((l) => l.contains('error:')) ??
      '';
  return 'other\t$evidence';
}

/// `offline-evidence APP_DIR LOGICAL_NAME`: prints [offlineEvidence] for the
/// app at APP_DIR — the build hook's logs that `hooks_runner` keeps under
/// `.dart_tool/hooks_runner/wallet_core_flutter_native/<config>/stdout.txt`,
/// and whether the hook's default cache already holds LOGICAL_NAME. Always
/// exits 0.
void _offlineEvidence(List<String> args) {
  if (args.length != 2) _usage();
  final app = args[0];
  final logs = Directory(
    '$app/.dart_tool/hooks_runner/wallet_core_flutter_native',
  );
  final texts = <String>[
    if (logs.existsSync())
      for (final entity in logs.listSync())
        if (entity is Directory &&
            File('${entity.path}/stdout.txt').existsSync())
          File('${entity.path}/stdout.txt').readAsStringSync(),
  ];
  final shared = Directory(
    '$app/.dart_tool/hooks_runner/shared/wallet_core_flutter_native',
  );
  final cached =
      shared.existsSync() &&
      shared
          .listSync(recursive: true)
          .any((e) => e is File && e.path.endsWith('/${args[1]}'));
  stdout.write(offlineEvidence(texts, args[1], cacheHasArtifact: cached));
}

/// What a build hook's logs say about how [logicalName] was obtained.
///
/// [hookLogs] are the `stdout.txt` texts `hooks_runner` keeps, one per hook
/// configuration (one hook run = one artifact). The hook prints the fetch
/// tool's summary — `1 requested: C already verified in the cache, D
/// downloaded, V from --vendored, F failed — cache …` — and then
/// `bundled <logical name> for … (…, offline).` Returns `KIND<TAB>EVIDENCE`:
/// - `vendored`: a run bundled [logicalName] with `offline` set, after
///   copying it from the vendored directory (V ≥ 1) with nothing from the
///   cache, nothing downloaded and nothing failed — the clean offline path;
/// - `downloaded`: a run bundled it after a download;
/// - `cache`: every run that bundled it found it already in the cache — a
///   warm build, which says nothing about a clean offline install;
/// - `warm-cache`: no run bundled it, but the hook's cache already holds it;
/// - `none`: no run bundled it and the cache does not hold it — the state a
///   clean build must start from.
///
/// The offline row passes only on `none` before its build and `vendored`
/// after it (review finding 11, T1.8a-d4). That `offline: true` opened no
/// socket is the fetch tool's code path (no request is made); it is not
/// observed at the socket level.
String offlineEvidence(
  List<String> hookLogs,
  String logicalName, {
  required bool cacheHasArtifact,
}) {
  final summary = RegExp(
    r'(\d+) requested: (\d+) already verified in the cache, (\d+) downloaded, '
    r'(\d+) from --vendored, (\d+) failed',
  );
  final bundled = 'bundled $logicalName for ';
  String? fromCache;
  String? downloaded;
  for (final text in hookLogs) {
    final lines = const LineSplitter().convert(text);
    final bundle = lines.where((l) => l.contains(bundled)).firstOrNull;
    if (bundle == null) continue;
    final counts = lines.map(summary.firstMatch).nonNulls.lastOrNull;
    if (counts == null) continue;
    final evidence = '${counts[0]}; ${bundle.trim()}';
    final [cache, fetched, vendored, failed] = [
      for (final i in [2, 3, 4, 5]) int.parse(counts[i]!),
    ];
    if (vendored >= 1 &&
        cache == 0 &&
        fetched == 0 &&
        failed == 0 &&
        bundle.contains(', offline)')) {
      return 'vendored\t$evidence';
    }
    if (fetched >= 1) downloaded ??= evidence;
    if (cache >= 1) fromCache ??= evidence;
  }
  if (downloaded != null) return 'downloaded\t$downloaded';
  if (fromCache != null) return 'cache\t$fromCache';
  if (cacheHasArtifact) return 'warm-cache\t$logicalName is in the hook cache';
  return 'none\t';
}

/// `embedded-binaries APP`: prints [embeddedBinaries] of APP, one per line.
void _embeddedBinaries(List<String> args) {
  if (args.length != 1) _usage();
  embeddedBinaries(args.first).forEach(stdout.writeln);
}

/// The Mach-O binary of every framework and every loose dylib embedded in the
/// app bundle [app] (`Frameworks/` on iOS, `Contents/Frameworks/` on macOS),
/// sorted — the libraries an app loads besides its executable.
///
/// The duplicate-symbol scan runs over all of them, as Option 2's does
/// (review finding 12, T1.8a-d4: it used to scan `TrustWalletCore` and
/// `Flutter` only, so the two options' step-10 numbers were not comparable).
/// A framework's binary is `<Name>.framework/<Name>`; a framework without one
/// is skipped.
List<String> embeddedBinaries(String app) {
  final out = <String>[];
  for (final dir in ['$app/Frameworks', '$app/Contents/Frameworks']) {
    final frameworks = Directory(dir);
    if (!frameworks.existsSync()) continue;
    for (final entity in frameworks.listSync(followLinks: false)) {
      final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      if (entity is Directory && name.endsWith('.framework')) {
        final binary = File(
          '${entity.path}/${name.substring(0, name.length - 10)}',
        );
        if (binary.existsSync()) out.add(binary.path);
      } else if (entity is File && name.endsWith('.dylib')) {
        out.add(entity.path);
      }
    }
  }
  return out..sort();
}

/// `embed-table TABLE RESULTS DOC`: replaces DOC's generated blocks with
/// [embedTable]'s output.
void _embedTable(List<String> args) {
  if (args.length != 3) _usage();
  final doc = File(args[2]);
  final String out;
  try {
    out = embedTable(
      doc: doc.readAsStringSync(),
      table: File(args[0]).readAsStringSync(),
      results: File(args[1]).readAsLinesSync(),
    );
  } on FormatException catch (e) {
    _die(e.message);
  }
  doc.writeAsStringSync(out);
  stdout.writeln('embedded ${args[0]} into ${args[2]}');
}

/// [doc] with two generated blocks rewritten from the last run:
///
/// - between `<!-- table:begin -->` and `<!-- table:end -->`, the first
///   Markdown table of [table] (what `report.dart` rendered), with every `|`
///   that sits inside parentheses escaped as `\|` — the harness writes the
///   required-reason category list `(a | b)` raw, which splits a cell — and
///   each row checked to have the header's column count;
/// - between `<!-- counts:begin -->` and `<!-- counts:end -->`, the number of
///   rows in [results] and how many have each status.
///
/// Throws [FormatException] when a marker is missing or a row does not fit.
/// Nothing else in [doc] changes: prose that quotes results is written to be
/// re-checked by hand against the table after each run.
String embedTable({
  required String doc,
  required String table,
  required List<String> results,
}) {
  final rows = <String>[];
  for (final line in const LineSplitter().convert(table)) {
    if (line.startsWith('|')) {
      rows.add(line);
    } else if (rows.isNotEmpty) {
      break;
    }
  }
  if (rows.length < 3) throw const FormatException('TABLE has no table');
  String escape(String row) {
    final b = StringBuffer();
    var depth = 0;
    for (var i = 0; i < row.length; i++) {
      final c = row[i];
      if (c == '(') depth++;
      if (c == ')' && depth > 0) depth--;
      b.write(c == '|' && depth > 0 ? r'\|' : c);
    }
    return b.toString();
  }

  int cells(String row) => RegExp(r'(?<!\\)\|').allMatches(row).length - 1;
  final escaped = [for (final r in rows) escape(r)];
  final width = cells(escaped.first);
  for (final r in escaped) {
    if (cells(r) != width) {
      throw FormatException(
        'a row of TABLE has ${cells(r)} cells, the header $width: '
        '${r.length > 120 ? '${r.substring(0, 120)}…' : r}',
      );
    }
  }

  final statuses = <String, int>{
    'pass': 0,
    'fail': 0,
    'skip': 0,
    'unmeasured': 0,
  };
  var total = 0;
  for (final line in results) {
    if (line.trim().isEmpty) continue;
    final status = (jsonDecode(line) as Map<String, Object?>)['status'];
    statuses.update('$status', (n) => n + 1, ifAbsent: () => 1);
    total++;
  }
  final counts =
      '$total rows: ${statuses.entries.map((e) => '${e.value} ${e.key}').join(', ')}.';

  String replace(String text, String name, String body) {
    final begin = '<!-- $name:begin -->';
    final end = '<!-- $name:end -->';
    final from = text.indexOf(begin);
    final to = text.indexOf(end);
    if (from < 0 || to < from) {
      throw FormatException('DOC has no $begin … $end block');
    }
    return '${text.substring(0, from + begin.length)}\n$body\n'
        '${text.substring(to)}';
  }

  return replace(replace(doc, 'table', escaped.join('\n')), 'counts', counts);
}

Map<String, Object?> _readJson(String path) {
  final file = File(path);
  if (!file.existsSync()) _die('no such file: $path');
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

/// Prints the string at a dotted path, e.g. `identity.artifact_set_id`.
void _value(List<String> args) {
  if (args.length != 2) _usage();
  Object? node = _readJson(args[0]);
  for (final part in args[1].split('.')) {
    if (node is! Map<String, Object?> || !node.containsKey(part)) {
      _die('${args[0]} has no ${args[1]}');
    }
    node = node[part];
  }
  stdout.write(node is String ? node : jsonEncode(node));
}

/// Verifies every artifact the manifest pins (a real 64-hex digest) against
/// the file at ARTIFACT_DIR/<logical name>, by sha256 and size. Exit 1 on the
/// first mismatch or missing file. third_party/ is untrusted input: nothing
/// under it is measured before this passes.
Future<void> _verifySet(List<String> args) async {
  if (args.length != 2) _usage();
  final manifest = _readJson(args[0]);
  final artifacts = manifest['artifacts']! as Map<String, Object?>;
  final hex = RegExp(r'^[0-9a-f]{64}$');
  var checked = 0;
  for (final entry in artifacts.entries) {
    final record = entry.value! as Map<String, Object?>;
    final sha = record['sha256'];
    if (sha is! String || !hex.hasMatch(sha)) continue;
    final file = File('${args[1]}/${entry.key}');
    if (!file.existsSync()) _die('missing ${file.path}');
    final result = await Process.run('shasum', ['-a', '256', file.path]);
    if (result.exitCode != 0) _die('shasum failed: ${result.stderr}');
    final actual = (result.stdout as String).split(' ').first.trim();
    final size = file.lengthSync();
    if (actual != sha || size != record['size']) {
      _die(
        '${file.path}: expected sha256 $sha size ${record['size']}, '
        'found sha256 $actual size $size',
      );
    }
    stdout.writeln('verified  ${entry.key}  $sha');
    checked++;
  }
  if (checked == 0) _die('${args[0]} pins no artifact digest');
}

/// Writes MANIFEST with LOGICAL_NAME's digest changed in one hex character,
/// in `sha256` and in `asset_name` alike, so the manifest still agrees with
/// itself and the fetch tool's manifest gate passes: the mismatch must be
/// found where PRD §12.2 step 7 wants it, in the bytes.
void _flip(List<String> args) {
  if (args.length != 3) _usage();
  final manifest = _readJson(args[0]);
  final artifacts = manifest['artifacts']! as Map<String, Object?>;
  final record = artifacts[args[1]] as Map<String, Object?>?;
  if (record == null) _die('${args[0]} has no artifact ${args[1]}');
  final sha = record['sha256']! as String;
  final flipped = '${sha[0] == '0' ? '1' : '0'}${sha.substring(1)}';
  record['sha256'] = flipped;
  record['asset_name'] = (record['asset_name']! as String).replaceFirst(
    sha,
    flipped,
  );
  File(args[2])
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
    );
  stdout.writeln('${args[1]}: $sha -> $flipped');
}

/// Prints the id of the first device of KIND in the output of
/// `flutter devices --machine`, or nothing. Never starts a device: it reads
/// what is already running.
void _pickDevice(List<String> args) {
  if (args.length != 2) _usage();
  final file = File(args[0]);
  if (!file.existsSync()) return;
  final text = file.readAsStringSync();
  final start = text.indexOf('[');
  if (start < 0) return;
  final Object? decoded;
  try {
    decoded = jsonDecode(text.substring(start));
  } on FormatException {
    return;
  }
  if (decoded is! List) return;
  for (final device in decoded.whereType<Map<String, Object?>>()) {
    final platform = '${device['targetPlatform']}';
    final emulator = device['emulator'] == true;
    final match = switch (args[1]) {
      'ios-simulator' => platform.startsWith('ios') && emulator,
      'ios-device' => platform.startsWith('ios') && !emulator,
      'android-emulator' => platform.startsWith('android') && emulator,
      'android-device' => platform.startsWith('android') && !emulator,
      _ => _die('unknown device kind ${args[1]}'),
    };
    if (match) {
      stdout.write('${device['id']}');
      return;
    }
  }
}

/// Copies the consumer app to DEST (which must not exist) without build
/// output, and makes the copy's pubspec position-independent: every relative
/// path dependency and hook user-define becomes absolute, resolved against
/// the original. With --manifest the `manifest` user-define is replaced.
void _stage(List<String> args) {
  if (args.length != 2 && args.length != 4) _usage();
  final source = Directory(args[0]).absolute;
  final dest = Directory(args[1]);
  String? manifest;
  if (args.length == 4) {
    if (args[2] != '--manifest') _usage();
    manifest = File(args[3]).absolute.path;
  }
  if (dest.existsSync()) _die('${dest.path} exists');
  const skip = {'build', '.dart_tool', '.flutter-plugins-dependencies'};
  void copy(Directory from, Directory to) {
    to.createSync(recursive: true);
    for (final entity in from.listSync(followLinks: false)) {
      final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      if (from.path == source.path && skip.contains(name)) continue;
      if (name == 'Pods' || name == '.symlinks' || name == 'ephemeral') {
        continue;
      }
      if (entity is Directory) {
        copy(entity, Directory('${to.path}/$name'));
      } else if (entity is File) {
        entity.copySync('${to.path}/$name');
      }
    }
  }

  copy(source, dest);
  final pubspec = File('${dest.path}/pubspec.yaml');
  final lines = pubspec.readAsLinesSync();
  final pathLine = RegExp(
    r'^(\s+)(path|manifest|vendored_dir|cache_dir): (\.\.?/\S*)$',
  );
  final out = <String>[];
  for (final line in lines) {
    final m = pathLine.firstMatch(line);
    if (m == null) {
      out.add(line);
      continue;
    }
    final key = m.group(2)!;
    final value = key == 'manifest' && manifest != null
        ? manifest
        : File(
            '${source.path}/${m.group(3)}',
          ).absolute.uri.normalizePath().toFilePath();
    out.add('${m.group(1)}$key: $value');
  }
  pubspec.writeAsStringSync('${out.join('\n')}\n');
  stdout.writeln('staged ${dest.path}');
}
