// Writes eval/option1/eval_manifest.json: the root compat_manifest.json with
// its artifact rows, set id and Xcode version taken from an artifact set's
// DECISION-14 §5.1 records. EVALUATION ONLY.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.
//
//   dart run eval/option1/tool/make_eval_manifest.dart \
//       [--set third_party/wcf-native-all] [--out eval/option1/eval_manifest.json]
//       [--check]
//
// The records under <set>/records/ are untrusted input (third_party/ is
// git-ignored). Each record is accepted only if the artifact file it describes
// is present and hashes to the record's sha256 at the record's size, so the
// digests written into the eval manifest are digests of bytes this run saw.
// The committed eval manifest is then the digest every later use of those
// files is verified against (the hook's vendored path, run_eval.sh).
//
// No substitution is left. Until T1.8b the set was a local build
// (as_4.8.0_000) and the root manifest a placeholder, so this tool wrote
// `.invalid` stand-ins for build_workflow and retention.primary and replaced
// the xcframework row with per-slice dylibs. The published set as_4.8.0_001
// (main f9f3d58) carries a real build_workflow in every record, the root
// manifest carries its identity, retention.primary and per-slice rows, and
// the records are written as they are: for that set the eval manifest holds
// the root's values (only the key order of `artifacts` differs).

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  var setDir = 'third_party/wcf-native-all';
  var out = 'eval/option1/eval_manifest.json';
  var check = false;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--set':
        setDir = args[++i];
      case '--out':
        out = args[++i];
      case '--check':
        check = true;
      default:
        stderr.writeln('unknown argument ${args[i]}');
        exit(64);
    }
  }

  final root =
      jsonDecode(File('compat_manifest.json').readAsStringSync())
          as Map<String, Object?>;
  final records = <String, Map<String, Object?>>{};
  final recordFiles =
      Directory('$setDir/records')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  String? setId;
  for (final file in recordFiles) {
    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    for (final entry in decoded.entries) {
      final record = Map<String, Object?>.of(
        entry.value! as Map<String, Object?>,
      );
      final artifact = File('$setDir/artifacts/${entry.key}');
      final actual = await _sha256(artifact);
      if (actual.digest != record['sha256'] || actual.size != record['size']) {
        stderr.writeln(
          'error: ${artifact.path} is sha256 ${actual.digest} size '
          '${actual.size}, but ${file.path} records ${record['sha256']} size '
          '${record['size']}; refusing to write a digest for it',
        );
        exit(1);
      }
      final assetSet = (record['asset_name']! as String).split('__').first;
      if (setId != null && setId != assetSet) {
        stderr.writeln('error: records span two sets, $setId and $assetSet');
        exit(1);
      }
      setId = assetSet;
      records[entry.key] = record;
    }
  }
  if (setId == null) {
    stderr.writeln('error: no records under $setDir/records');
    exit(1);
  }

  final artifacts = <String, Object?>{
    for (final entry in (root['artifacts']! as Map<String, Object?>).entries)
      if (entry.key.startsWith('android/')) entry.key: entry.value,
    ...records,
  };
  final toolchain = Map<String, Object?>.of(
    root['toolchain']! as Map<String, Object?>,
  );
  final xcodes = {
    for (final r in records.values)
      (r['toolchain']! as Map<String, Object?>)['xcode'],
  };
  if (xcodes.length == 1) toolchain['xcode'] = xcodes.single;

  final identity = Map<String, Object?>.of(
    root['identity']! as Map<String, Object?>,
  );
  identity['artifact_set_id'] = setId;
  final manifest = <String, Object?>{
    for (final entry in root.entries)
      entry.key: switch (entry.key) {
        'artifacts' => artifacts,
        'toolchain' => toolchain,
        'identity' => identity,
        _ => entry.value,
      },
  };
  final text = '${const JsonEncoder.withIndent('  ').convert(manifest)}\n';

  if (check) {
    final existing = File(out).existsSync() ? File(out).readAsStringSync() : '';
    if (existing != text) {
      stderr.writeln(
        'error: $out is not what $setDir/records and compat_manifest.json '
        'produce; rerun without --check',
      );
      exit(1);
    }
    stdout.writeln('$out is current (set $setId, ${records.length} artifacts)');
    return;
  }
  File(out).writeAsStringSync(text);
  stdout.writeln('wrote $out (set $setId, ${records.length} artifacts)');
}

/// sha256 and size through `shasum -a 256`, the same system command the
/// harness's size check records, so this script needs no package.
Future<({String digest, int size})> _sha256(File file) async {
  if (!file.existsSync()) {
    stderr.writeln('error: ${file.path} is missing');
    exit(1);
  }
  final result = await Process.run('shasum', ['-a', '256', file.path]);
  if (result.exitCode != 0) {
    stderr.writeln('error: shasum failed on ${file.path}: ${result.stderr}');
    exit(1);
  }
  final digest = (result.stdout as String).split(' ').first.trim();
  return (digest: digest, size: file.lengthSync());
}
