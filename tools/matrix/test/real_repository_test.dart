// The matrix over this repository's own inputs. Skips, with the reason, when
// the git-ignored upstream checkout or the generated trees are absent.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wcf_tool_matrix/checks.dart';
import 'package:wcf_tool_matrix/inputs.dart';
import 'package:wcf_tool_matrix/load.dart';
import 'package:wcf_tool_matrix/matrix.dart';
import 'package:wcf_tool_matrix/render.dart';
import 'package:wcf_tool_matrix/variants.dart';

Directory? repositoryRoot() {
  var directory = Directory.current.absolute;
  while (true) {
    if (File('${directory.path}/AGENTS.md').existsSync() &&
        File('${directory.path}/compat_manifest.json').existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) return null;
    directory = parent;
  }
}

/// A reason to skip, or `null`.
String? skipReason(Directory? root) {
  if (root == null) {
    return 'repository root not found from ${Directory.current}';
  }
  final paths = MatrixPaths(root: root.path);
  for (final path in [
    '${root.path}/third_party/wallet-core/src/proto',
    '${root.path}/third_party/wallet-core/registry.json',
    paths.registryDir,
    paths.protoDir,
    paths.evidenceFile,
    paths.exposedFile,
  ]) {
    if (!FileSystemEntity.isDirectorySync(path) && !File(path).existsSync()) {
      return 'missing $path; run `melos run upstream:fetch` and `melos run gen:all`';
    }
  }
  return null;
}

void main() {
  final root = repositoryRoot();
  final reason = skipReason(root);
  if (reason != null) {
    test('the matrix over the real inputs', () {}, skip: reason);
    return;
  }
  final paths = MatrixPaths(root: root!.path);
  final inputs = loadInputs(paths);
  final result = buildMatrix(inputs);

  test('the inputs are consistent: no problems, no conflicts', () {
    expect(result.problems, isEmpty);
    expect(result.matrix.conflicts, isEmpty);
    expect(result.matrix.coins, hasLength(167));
  });

  test('registry ids are the ids of upstream registry.json', () {
    final upstream =
        (jsonDecode(
                  File(
                    '${root.path}/third_party/wallet-core/registry.json',
                  ).readAsStringSync(),
                )
                as List<Object?>)
            .cast<Map<String, Object?>>();
    expect(inputs.coins.map((c) => c.id).toSet(), {
      for (final entry in upstream) entry['id']! as String,
    });
    expect(
      {for (final c in inputs.coins) c.id: c.blockchain},
      {
        for (final entry in upstream)
          entry['id']! as String: entry['blockchain']! as String,
      },
    );
  });

  test('the proto messages the matrix reads are the messages upstream\'s '
      '.proto files define', () {
    final protoDir = Directory(
      '${root.path}/third_party/wallet-core/src/proto',
    );
    final messageLine = RegExp(r'^message (\w+)', multiLine: true);
    for (final entry in inputs.protoMessages.entries) {
      final source = File('${protoDir.path}/${entry.key}.proto');
      if (!source.existsSync()) continue;
      final upstreamTop = {
        for (final m in messageLine.allMatches(source.readAsStringSync()))
          m.group(1)!,
      };
      for (final name in [
        'SigningInput',
        'MessageSigningInput',
        'TransactionPlan',
      ]) {
        expect(
          entry.value.contains(name),
          upstreamTop.contains(name),
          reason: '${entry.key}.proto $name',
        );
      }
    }
  });

  test('every registry blockchain resolves to a proto package that exists', () {
    for (final coin in inputs.coins) {
      final proto = protoOfBlockchain(coin.blockchain);
      expect(
        inputs.protoMessages.containsKey(proto),
        isTrue,
        reason: '${coin.id} (${coin.blockchain}) -> $proto',
      );
    }
  });

  test('family counts and the generated totals at the pinned tag', () {
    final byFamily = <String, int>{};
    for (final row in result.matrix.coins) {
      byFamily[row.family] = (byFamily[row.family] ?? 0) + 1;
    }
    expect(byFamily, {'evm': 60, 'utxo': 14, 'solana': 1, 'other': 92});
    Counts totals(String op) => result.matrix.operationTotals(op);
    expect(totals('address').generated, 167);
    expect(totals('sign_message').generated, 63);
    expect(totals('compile').generated, 158);
    // EOS and WAX are generated but abort on malformed input.
    final aborting = [
      for (final row in result.matrix.coins)
        if (row.operations['compile']!.note != null) row.coin.id,
    ];
    expect(aborting, ['eos', 'wax']);
  });

  test('every vector of the inventory binds to a cell', () {
    expect(result.problems.where((p) => p.startsWith('vector ')), isEmpty);
    expect(result.matrix.vectors, isNotEmpty);
  });

  test('the committed outputs are a regeneration of these inputs', () {
    expect(checkRegeneration(paths, result.matrix), isEmpty);
  });

  test('regenerating twice gives identical bytes', () {
    expect(renderJson(result.matrix), renderJson(buildMatrix(inputs).matrix));
    expect(
      renderMarkdown(result.matrix),
      renderMarkdown(buildMatrix(inputs).matrix),
    );
  });
}
