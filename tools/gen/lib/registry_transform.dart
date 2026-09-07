import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

const _reservedWords = {
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'function',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'new',
  'null',
  'on',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'sealed',
  'set',
  'show',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'type',
  'typedef',
  'var',
  'void',
  'while',
  'with',
  'yield',
};

String normalizeId(String id) {
  final parts = id.split('_');
  return parts
      .asMap()
      .entries
      .map((e) {
        final i = e.key;
        final part = e.value;
        if (part.isEmpty) return '';
        if (i == 0) return part[0].toLowerCase() + part.substring(1);
        return part[0].toUpperCase() + part.substring(1);
      })
      .join('');
}

String escapeString(String? s) {
  if (s == null) return 'null';
  return jsonEncode(s);
}

Future<void> runRegistryTransform() async {
  final registryFile = File('third_party/wallet-core/registry.json');
  final registryData =
      jsonDecode(await registryFile.readAsString()) as List<dynamic>;

  final outDir = Directory(
    'packages/wallet_core_flutter_bindings/lib/src/generated/registry',
  );
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  // Sort by coinId for determinism
  registryData.sort(
    (a, b) => (a['coinId'] as int).compareTo(b['coinId'] as int),
  );

  final Set<String> usedIds = {};

  final coinTypeBuffer = StringBuffer();
  coinTypeBuffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
  coinTypeBuffer.writeln('enum CoinType {');

  final coinInfoBuffer = StringBuffer();
  coinInfoBuffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
  coinInfoBuffer.writeln("import 'coin_type.dart';");
  coinInfoBuffer.writeln();
  coinInfoBuffer.writeln('class Derivation {');
  coinInfoBuffer.writeln('  final String? name;');
  coinInfoBuffer.writeln('  final String path;');
  coinInfoBuffer.writeln('  final String? xpub;');
  coinInfoBuffer.writeln('  final String? xprv;');
  coinInfoBuffer.writeln(
    '  const Derivation({this.name, required this.path, this.xpub, this.xprv});',
  );
  coinInfoBuffer.writeln('}');
  coinInfoBuffer.writeln();
  coinInfoBuffer.writeln('class Explorer {');
  coinInfoBuffer.writeln('  final String url;');
  coinInfoBuffer.writeln('  final String txPath;');
  coinInfoBuffer.writeln('  final String accountPath;');
  coinInfoBuffer.writeln(
    '  const Explorer({required this.url, required this.txPath, required this.accountPath});',
  );
  coinInfoBuffer.writeln('}');
  coinInfoBuffer.writeln();
  coinInfoBuffer.writeln('class CoinInfo {');
  coinInfoBuffer.writeln('  final String name;');
  coinInfoBuffer.writeln('  final String symbol;');
  coinInfoBuffer.writeln('  final int decimals;');
  coinInfoBuffer.writeln('  final List<Derivation> derivation;');
  coinInfoBuffer.writeln('  final String curve;');
  coinInfoBuffer.writeln('  final String publicKeyType;');
  coinInfoBuffer.writeln('  final String blockchain;');
  coinInfoBuffer.writeln('  final Explorer explorer;');
  coinInfoBuffer.writeln('  final String? chainId;');
  coinInfoBuffer.writeln('  final bool deprecated;');
  coinInfoBuffer.writeln('  final String? hrp;');
  coinInfoBuffer.writeln();
  coinInfoBuffer.writeln('  const CoinInfo({');
  coinInfoBuffer.writeln('    required this.name,');
  coinInfoBuffer.writeln('    required this.symbol,');
  coinInfoBuffer.writeln('    required this.decimals,');
  coinInfoBuffer.writeln('    required this.derivation,');
  coinInfoBuffer.writeln('    required this.curve,');
  coinInfoBuffer.writeln('    required this.publicKeyType,');
  coinInfoBuffer.writeln('    required this.blockchain,');
  coinInfoBuffer.writeln('    required this.explorer,');
  coinInfoBuffer.writeln('    this.chainId,');
  coinInfoBuffer.writeln('    this.deprecated = false,');
  coinInfoBuffer.writeln('    this.hrp,');
  coinInfoBuffer.writeln('  });');
  coinInfoBuffer.writeln('}');
  coinInfoBuffer.writeln();
  coinInfoBuffer.writeln('const Map<CoinType, CoinInfo> coinInfo = {');

  for (var i = 0; i < registryData.length; i++) {
    final entry = registryData[i] as Map<String, dynamic>;
    final id = entry['id'] as String;
    final coinId = entry['coinId'] as int;
    final normalized = normalizeId(id);

    if (_reservedWords.contains(normalized)) {
      throw Exception(
        'Normalized ID $normalized for coin $id is a Dart reserved word',
      );
    }
    if (!usedIds.add(normalized)) {
      throw Exception('Normalized ID $normalized for coin $id is a duplicate');
    }

    final isLast = i == registryData.length - 1;
    coinTypeBuffer.writeln('  $normalized($coinId)${isLast ? ";" : ","}');

    coinInfoBuffer.writeln('  CoinType.$normalized: CoinInfo(');
    coinInfoBuffer.writeln(
      '    name: ${escapeString(entry["name"] as String?)},',
    );
    coinInfoBuffer.writeln(
      '    symbol: ${escapeString(entry["symbol"] as String?)},',
    );
    coinInfoBuffer.writeln('    decimals: ${entry["decimals"]},');
    coinInfoBuffer.writeln('    derivation: [');
    final derivations = entry['derivation'] as List<dynamic>? ?? [];
    for (final d in derivations) {
      final name = d['name'] as String?;
      final path = d['path'] as String;
      final xpub = d['xpub'] as String?;
      final xprv = d['xprv'] as String?;
      coinInfoBuffer.writeln(
        '      Derivation(name: ${escapeString(name)}, path: ${escapeString(path)}, xpub: ${escapeString(xpub)}, xprv: ${escapeString(xprv)}),',
      );
    }
    coinInfoBuffer.writeln('    ],');
    coinInfoBuffer.writeln(
      '    curve: ${escapeString(entry["curve"] as String?)},',
    );
    coinInfoBuffer.writeln(
      '    publicKeyType: ${escapeString(entry["publicKeyType"] as String?)},',
    );
    coinInfoBuffer.writeln(
      '    blockchain: ${escapeString(entry["blockchain"] as String?)},',
    );
    final explorer = entry['explorer'] as Map<String, dynamic>;
    coinInfoBuffer.writeln('    explorer: Explorer(');
    coinInfoBuffer.writeln(
      '      url: ${escapeString(explorer["url"] as String?)},',
    );
    coinInfoBuffer.writeln(
      '      txPath: ${escapeString(explorer["txPath"] as String?)},',
    );
    coinInfoBuffer.writeln(
      '      accountPath: ${escapeString(explorer["accountPath"] as String?)},',
    );
    coinInfoBuffer.writeln('    ),');
    if (entry.containsKey('chainId')) {
      final chainId = entry['chainId'] as String?;
      coinInfoBuffer.writeln('    chainId: ${escapeString(chainId)},');
    }
    if (entry.containsKey('deprecated')) {
      coinInfoBuffer.writeln('    deprecated: ${entry["deprecated"]},');
    }
    if (entry.containsKey('hrp')) {
      final hrp = entry['hrp'] as String?;
      coinInfoBuffer.writeln('    hrp: ${escapeString(hrp)},');
    }
    coinInfoBuffer.writeln('  ),');
  }

  coinTypeBuffer.writeln();
  coinTypeBuffer.writeln('  final int coinId;');
  coinTypeBuffer.writeln('  const CoinType(this.coinId);');
  coinTypeBuffer.writeln();
  coinTypeBuffer.writeln('  static CoinType? fromCoinId(int id) {');
  coinTypeBuffer.writeln('    for (final value in CoinType.values) {');
  coinTypeBuffer.writeln('      if (value.coinId == id) return value;');
  coinTypeBuffer.writeln('    }');
  coinTypeBuffer.writeln('    return null;');
  coinTypeBuffer.writeln('  }');
  coinTypeBuffer.writeln('}');

  coinInfoBuffer.writeln('};');

  await File(
    '${outDir.path}/coin_type.dart',
  ).writeAsString(coinTypeBuffer.toString());
  await File(
    '${outDir.path}/coin_info.dart',
  ).writeAsString(coinInfoBuffer.toString());

  // Recompute transform source hash
  final sourceFile = File('tools/gen/lib/registry_transform.dart');
  final sourceBytes = await sourceFile.readAsBytes();
  final sourceHash = sha256.convert(sourceBytes).toString();

  final manifestFile = File('compat_manifest.json');
  final manifestContent = await manifestFile.readAsString();
  final manifestJson = jsonDecode(manifestContent) as Map<String, dynamic>;
  (manifestJson['generators'] as Map<String, dynamic>)['registry_transform'] =
      sourceHash;
  await manifestFile.writeAsString(
    '${const JsonEncoder.withIndent("  ").convert(manifestJson)}\n',
  );

  // Format generated code
  final formatResult = await Process.run('dart', ['format', outDir.path]);
  if (formatResult.exitCode != 0) {
    throw Exception('dart format failed: ${formatResult.stderr}');
  }
}
