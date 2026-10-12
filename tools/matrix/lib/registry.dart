import 'dart:io';

/// One coin of the generated registry
/// (`packages/wallet_core_flutter_bindings/lib/src/generated/registry/`).
class RegistryCoin {
  const RegistryCoin({
    required this.id,
    required this.enumName,
    required this.coinId,
    required this.name,
    required this.blockchain,
    required this.deprecated,
    required this.derivationCount,
  });

  /// Upstream's registry id (`bitcoin`, `doge`, `classic`), the id vectors and
  /// the SDK's `Coin.id` use.
  final String id;

  /// The generated `CoinType` member name.
  final String enumName;

  /// Upstream's numeric coin id (SLIP-44), the key of the T2.9 evidence rows.
  final int coinId;

  final String name;

  /// The registry's `blockchain` string, e.g. `Ethereum`, `Bitcoin`.
  final String blockchain;

  final bool deprecated;

  /// Number of `derivation` entries the registry lists; address derivation is
  /// generated for a coin exactly when this is non-zero.
  final int derivationCount;
}

/// Registry ids the generator's identifier normalisation does not invert: the
/// same table the SDK's `registryIdOf` carries (`lib/src/coin/coin.dart`), which
/// a test of the SDK checks against the pinned `registry.json`.
const Map<String, String> registryIdExceptions = {'nebl': 'Nebl'};

/// The registry id of a generated `CoinType` member: `gen:registry` lower-cases
/// the first letter of the id and camel-cases at underscores, so snake-casing
/// the member name undoes it.
String registryIdOfEnumName(String enumName) =>
    registryIdExceptions[enumName] ??
    enumName.replaceAllMapped(
      RegExp('[A-Z]'),
      (match) => '_${match[0]!.toLowerCase()}',
    );

final RegExp _enumMember = RegExp(
  r'^  (\w+)\((\d+)\)[,;]\s*$',
  multiLine: true,
);
final RegExp _infoStart = RegExp(
  r'^  CoinType\.(\w+): CoinInfo\($',
  multiLine: true,
);
final RegExp _nameField = RegExp(
  r'^    name: "((?:[^"\\]|\\.)*)",$',
  multiLine: true,
);
final RegExp _blockchainField = RegExp(
  r'^    blockchain: "(\w+)",$',
  multiLine: true,
);
final RegExp _deprecatedField = RegExp(
  r'^    deprecated: true,$',
  multiLine: true,
);

/// Reads `coin_type.dart` and `coin_info.dart` under [registryDir] as text. The
/// tool never imports the bindings package: it is a Flutter package, and the
/// generated files are data here.
///
/// Throws [FormatException] when a coin lacks a field the matrix needs, so a
/// generator change shows up as a failure and not as a silently thinner matrix.
List<RegistryCoin> readRegistry(Directory registryDir) {
  final typeFile = File('${registryDir.path}/coin_type.dart');
  final infoFile = File('${registryDir.path}/coin_info.dart');
  for (final file in [typeFile, infoFile]) {
    if (!file.existsSync()) {
      throw FormatException(
        'generated registry file missing: ${file.path}; run `melos run gen:registry`',
      );
    }
  }
  final numbers = <String, int>{
    for (final m in _enumMember.allMatches(typeFile.readAsStringSync()))
      m.group(1)!: int.parse(m.group(2)!),
  };
  final info = infoFile.readAsStringSync();
  final starts = _infoStart.allMatches(info).toList();
  final coins = <RegistryCoin>[];
  for (var i = 0; i < starts.length; i++) {
    final enumName = starts[i].group(1)!;
    final end = i + 1 < starts.length ? starts[i + 1].start : info.length;
    final chunk = info.substring(starts[i].end, end);
    final name = _nameField.firstMatch(chunk)?.group(1);
    final blockchain = _blockchainField.firstMatch(chunk)?.group(1);
    final coinId = numbers[enumName];
    if (name == null || blockchain == null || coinId == null) {
      throw FormatException(
        'registry entry $enumName lacks a name, a blockchain or a coin id',
      );
    }
    coins.add(
      RegistryCoin(
        id: registryIdOfEnumName(enumName),
        enumName: enumName,
        coinId: coinId,
        name: name,
        blockchain: blockchain,
        deprecated: _deprecatedField.hasMatch(chunk),
        derivationCount: 'Derivation('.allMatches(chunk).length,
      ),
    );
  }
  if (coins.isEmpty) {
    throw FormatException('no coins found in ${infoFile.path}');
  }
  coins.sort((a, b) => a.id.compareTo(b.id));
  return coins;
}
