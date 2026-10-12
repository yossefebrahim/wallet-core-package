/// A small synthetic repository for the matrix tests: a generated registry, a
/// generated proto tree, T2.9 evidence, an exposed snapshot, a vector inventory
/// and a compat manifest, written into a temporary directory in the shapes the
/// real generators emit.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wcf_tool_matrix/inputs.dart';
import 'package:wcf_tool_matrix/load.dart';
import 'package:wcf_tool_matrix/matrix.dart';

const pinnedTag = '9.9.9';
const pinnedCommit = 'abcdef0123456789abcdef0123456789abcdef01';

/// The fixture's README: text around an empty generated region. The trailing
/// line has no final newline on purpose, to check that outside bytes survive.
const fixtureReadme =
    '# fixture\n\nbefore  \n\n<!-- matrix-counts -->\n<!-- /matrix-counts -->\n'
    '\nafter\r\n  trailing';

/// One fixture registry coin.
class FixtureCoin {
  const FixtureCoin(
    this.enumName,
    this.coinId,
    this.blockchain, {
    this.derivations = 1,
    this.deprecated = false,
  });

  final String enumName;
  final int coinId;
  final String blockchain;
  final int derivations;
  final bool deprecated;
}

const defaultCoins = [
  FixtureCoin('bitcoin', 0, 'Bitcoin'),
  FixtureCoin('ethereum', 60, 'Ethereum'),
  FixtureCoin('classic', 61, 'Ethereum'),
  FixtureCoin('bitcoincash', 145, 'BitcoinCash'),
  FixtureCoin('eos', 194, 'EOS'),
  FixtureCoin('internetComputer', 223, 'InternetComputer'),
  FixtureCoin('ronin', 10001, 'Ronin'),
  FixtureCoin('solana', 501, 'Solana'),
  FixtureCoin('nebl', 146, 'Bitcoin'),
];

/// Proto file stem → message classes.
const defaultProtos = {
  'Bitcoin': ['SigningInput', 'TransactionPlan', 'PreSigningOutput'],
  'Ethereum': ['SigningInput', 'MessageSigningInput', 'Transaction'],
  'EOS': ['SigningInput'],
  'InternetComputer': ['SigningInput'],
  'Solana': ['SigningInput', 'MessageSigningInput'],
  'Common': ['Unrelated'],
};

/// A T2.9 evidence row.
Map<String, Object?> probeRow(
  FixtureCoin coin, {
  String static = 'unsupported',
  String runtime = 'unsupported',
  String agreement = 'agree',
  String? crashDetail,
  String? specificSigner,
  bool message = false,
}) => {
  'coin_id': coin.coinId,
  'coin_type': 'TWCoinType${coin.enumName}',
  'blockchain': coin.blockchain,
  'static': static,
  'runtime': runtime,
  'agreement': agreement,
  'crash_detail': ?crashDetail,
  if (message) 'specific_signer': specificSigner,
};

/// Evidence rows consistent with [defaultProtos]: Ethereum-family and Solana
/// coins have a generic message signer, every coin but the listed ones has a
/// compiler.
List<Map<String, Object?>> defaultCompilerRows(List<FixtureCoin> coins) => [
  for (final c in coins)
    switch (c.enumName) {
      'eos' => probeRow(
        c,
        static: 'supported',
        runtime: 'crash',
        agreement: 'crash',
        crashDetail: 'signal 6 in preimage_empty',
      ),
      'internetComputer' => probeRow(
        c,
        static: 'unsupported',
        runtime: 'not-supported',
      ),
      _ => probeRow(c, static: 'supported', runtime: 'reached'),
    },
];

List<Map<String, Object?>> defaultMessageRows(List<FixtureCoin> coins) => [
  for (final c in coins)
    if (const {'Ethereum', 'Ronin', 'Solana'}.contains(c.blockchain))
      probeRow(c, static: 'supported', runtime: 'supported', message: true)
    else
      probeRow(c, message: true),
];

class FixtureRepo {
  FixtureRepo._(this.root);

  /// A repository with [coins], [protos], and the default evidence unless
  /// [compilerRows] / [messageRows] replace it. Every test gets its own
  /// directory; call [dispose] afterwards.
  factory FixtureRepo.create({
    List<FixtureCoin> coins = defaultCoins,
    Map<String, List<String>> protos = defaultProtos,
    List<Map<String, Object?>>? compilerRows,
    List<Map<String, Object?>>? messageRows,
    List<Map<String, Object?>>? exposedGroups,
    String evidenceCommit = pinnedCommit,
  }) {
    final repo = FixtureRepo._(
      Directory.systemTemp.createTempSync('wcf_matrix_fixture_'),
    );
    addTearDown(repo.dispose);
    repo._writeRegistry(coins);
    repo._writeProtos(protos);
    repo.writeJson('compat_manifest.json', {
      'upstream': {'tag': pinnedTag, 'commit': pinnedCommit},
    });
    repo.writeJson(
      'docs/decisions/evidence/compiler_and_message_coverage.json',
      {
        'schema': 1,
        'upstream': {'tag': pinnedTag, 'commit': evidenceCommit},
        'compiler': compilerRows ?? defaultCompilerRows(coins),
        'message': messageRows ?? defaultMessageRows(coins),
      },
    );
    repo.writeJson('docs/capability_exposed.json', {
      'schema': 1,
      'groups':
          exposedGroups ??
          [
            {
              'operation': 'address',
              'variant': 'n/a',
              'exposure': 'typed',
              'coins': 'all',
            },
            {
              'operation': 'sign',
              'variant': 'eip1559',
              'exposure': 'typed',
              'coins': ['classic', 'ethereum'],
            },
          ],
    });
    Directory('${repo.root.path}/test_vectors').createSync();
    repo.writeText('README.md', fixtureReadme);
    return repo;
  }

  final Directory root;

  MatrixPaths get paths => MatrixPaths(root: root.path);

  void dispose() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  }

  void writeText(String relative, String text) {
    final file = File('${root.path}/$relative');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(text);
  }

  void writeJson(String relative, Object? json) => writeText(
    relative,
    '${const JsonEncoder.withIndent('  ').convert(json)}\n',
  );

  /// Writes `test_vectors/<coin>/vectors.yaml` from [entries].
  void writeVectors(String coin, List<VectorSpec> entries) => writeText(
    'test_vectors/$coin/vectors.yaml',
    entries.isEmpty
        ? 'vectors: []\n'
        : 'vectors:\n${entries.map((e) => e.yaml).join()}',
  );

  void writeExclusions(String yaml) =>
      writeText('test_vectors/exclusions.yaml', yaml);

  /// Loads the inputs and builds the matrix.
  BuildResult build() => buildMatrix(loadInputs(paths));

  void _writeRegistry(List<FixtureCoin> coins) {
    const dir =
        'packages/wallet_core_flutter_bindings/lib/src/generated/registry';
    writeText(
      '$dir/coin_type.dart',
      '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
          'enum CoinType {\n'
          '${coins.map((c) => '  ${c.enumName}(${c.coinId}),\n').join()}'
          '  ;\n'
          '  final int coinId;\n'
          '  const CoinType(this.coinId);\n'
          '}\n',
    );
    final info = StringBuffer(
      "// GENERATED CODE - DO NOT MODIFY BY HAND\nimport 'coin_type.dart';\n\n"
      'const Map<CoinType, CoinInfo> coinInfo = {\n',
    );
    for (final c in coins) {
      info
        ..writeln('  CoinType.${c.enumName}: CoinInfo(')
        ..writeln('    name: "Coin ${c.enumName}",')
        ..writeln('    symbol: "X",')
        ..writeln('    decimals: 8,')
        ..writeln('    derivation: [');
      for (var i = 0; i < c.derivations; i++) {
        info.writeln(
          '      Derivation(name: null, path: "m/44\'/${c.coinId}\'/0\'/0/0", xpub: null, xprv: null),',
        );
      }
      info
        ..writeln('    ],')
        ..writeln('    curve: "secp256k1",')
        ..writeln('    publicKeyType: "secp256k1",')
        ..writeln('    blockchain: "${c.blockchain}",');
      if (c.deprecated) info.writeln('    deprecated: true,');
      info.writeln('  ),');
    }
    info.writeln('};');
    writeText('$dir/coin_info.dart', info.toString());
  }

  void _writeProtos(Map<String, List<String>> protos) {
    const dir = 'packages/wallet_core_flutter_bindings/lib/src/generated/proto';
    for (final entry in protos.entries) {
      writeText(
        '$dir/${entry.key}.pb.dart',
        '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
            '${entry.value.map((m) => 'class $m extends \$pb.GeneratedMessage {\n}\n\n').join()}'
            'class ${entry.value.first}Enum {}\n',
      );
    }
  }
}

/// One vector of a fixture `vectors.yaml`.
class VectorSpec {
  VectorSpec(
    this.coin,
    this.operation,
    this.variant, {
    this.n = 1,
    this.platforms = const [],
  });

  final String coin;
  final String operation;
  final String variant;
  final int n;
  final List<String> platforms;

  String get id => '$coin-$operation-$variant-$n';

  String get yaml =>
      '  - id: $id\n'
      '    coin: $coin\n'
      '    operation: $operation\n'
      '    variant: $variant\n'
      '    source:\n'
      '      kind: standard\n'
      '      reference: fixture\n'
      '    input: {}\n'
      '    expected: {}\n'
      '    platforms_verified: [${platforms.join(', ')}]\n';
}

/// The cell of [matrix] for (coin, operation).
OperationCell opOf(Matrix matrix, String coin, String operation) =>
    matrix.coins.singleWhere((r) => r.coin.id == coin).operations[operation]!;
