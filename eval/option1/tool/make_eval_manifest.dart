// Writes eval/option1/eval_manifest.json: the root compat_manifest.json with
// its Apple artifact rows and its identity filled from a locally built
// artifact set's DECISION-14 §5.1 records. EVALUATION ONLY.
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
// Three substitutions, each forced by the manifest validator and each
// recorded in eval/option1/README.md:
//   - `build_workflow` (identity and per artifact): the records say "local";
//     the validator requires an absolute https URL. Written as
//     https://wcf-eval-only.invalid/local-build/<set id> — `.invalid` is
//     reserved (RFC 2606, RFC 6761) and can never resolve.
//   - `retention.primary`: the root has TBD-T0.11, which the fetch tool's gate
//     refuses even for a vendored, offline fetch. Written as
//     https://wcf-eval-only.invalid/never-published/<set id>; a download
//     attempt against it fails closed at DNS.
//   - `ios/TrustWalletCore.xcframework.zip` is replaced by the per-slice
//     dylibs: a build hook bundles one library per SDK and architecture.
// The Android rows stay TBD-T1.2 placeholders: no Android artifact exists.

import 'dart:convert';
import 'dart:io';

const _invalidBase = 'https://wcf-eval-only.invalid';

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
      record['build_workflow'] = '$_invalidBase/local-build/$assetSet';
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
  identity['build_workflow'] = '$_invalidBase/local-build/$setId';
  final retention = Map<String, Object?>.of(
    root['retention']! as Map<String, Object?>,
  );
  retention['primary'] = '$_invalidBase/never-published/$setId';

  final manifest = <String, Object?>{
    for (final entry in root.entries)
      entry.key: switch (entry.key) {
        'artifacts' => artifacts,
        'toolchain' => toolchain,
        'identity' => identity,
        'retention' => retention,
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
