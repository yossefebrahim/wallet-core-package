import 'dart:io';
import 'package:yaml/yaml.dart';

class VectorSource {
  final String kind;
  final String? path;
  final String? commit;
  final String? reference;
  final String? url;

  VectorSource({
    required this.kind,
    this.path,
    this.commit,
    this.reference,
    this.url,
  });

  factory VectorSource.fromYaml(YamlMap map) {
    return VectorSource(
      kind: map['kind'] as String? ?? '',
      path: map['path'] as String?,
      commit: map['commit'] as String?,
      reference: map['reference'] as String?,
      url: map['url'] as String?,
    );
  }
}

class Vector {
  final String id;
  final String coin;
  final String operation;
  final String variant;
  final VectorSource? source;
  final dynamic input;
  final dynamic expected;
  final List<String> platformsVerified;
  final YamlMap rawMap;
  final String filePath;
  final int index;

  Vector({
    required this.id,
    required this.coin,
    required this.operation,
    required this.variant,
    this.source,
    required this.input,
    required this.expected,
    required this.platformsVerified,
    required this.rawMap,
    required this.filePath,
    required this.index,
  });

  factory Vector.fromYaml(YamlMap map, String filePath, int index) {
    final rawSource = map['source'];
    final platformsList = map['platforms_verified'] as YamlList?;
    final platformsVerified =
        platformsList?.map((e) => e.toString()).toList() ?? [];

    return Vector(
      id: map['id'] as String? ?? '',
      coin: map['coin'] as String? ?? '',
      operation: map['operation'] as String? ?? '',
      variant: map['variant'] as String? ?? '',
      source: rawSource is YamlMap ? VectorSource.fromYaml(rawSource) : null,
      input: map['input'],
      expected: map['expected'],
      platformsVerified: platformsVerified,
      rawMap: map,
      filePath: filePath,
      index: index,
    );
  }
}

class Exclusion {
  final String coin;
  final String operation;
  final String? variant;
  final String reason;

  Exclusion({
    required this.coin,
    required this.operation,
    this.variant,
    required this.reason,
  });

  factory Exclusion.fromYaml(YamlMap map) {
    return Exclusion(
      coin: map['coin'] as String? ?? '',
      operation: map['operation'] as String? ?? '',
      variant: map['variant'] as String?,
      reason: map['reason'] as String? ?? '',
    );
  }
}

class Inventory {
  final List<Vector> vectors;
  final List<Exclusion> exclusions;
  final int filesCount;
  final List<String> loadProblems;

  Inventory({
    required this.vectors,
    required this.exclusions,
    required this.filesCount,
    required this.loadProblems,
  });

  static Inventory load(Directory testVectorsDir) {
    final vectors = <Vector>[];
    final exclusions = <Exclusion>[];
    final loadProblems = <String>[];
    int filesCount = 0;

    if (!testVectorsDir.existsSync()) {
      return Inventory(
        vectors: vectors,
        exclusions: exclusions,
        filesCount: filesCount,
        loadProblems: loadProblems,
      );
    }

    for (final entity in testVectorsDir.listSync(recursive: false)) {
      if (entity is Directory) {
        final vectorsFile = File('${entity.path}/vectors.yaml');
        if (!vectorsFile.existsSync()) {
          loadProblems.add(
            'Coin directory ${entity.path} without vectors.yaml',
          );
          continue;
        }
        filesCount++;
        final content = vectorsFile.readAsStringSync();
        dynamic yamlNode;
        try {
          yamlNode = loadYaml(content);
        } on YamlException catch (e) {
          loadProblems.add(
            'YAML parse error in ${vectorsFile.path}: ${e.message}',
          );
          continue;
        }

        if (yamlNode is! YamlMap ||
            !yamlNode.containsKey('vectors') ||
            yamlNode['vectors'] is! YamlList) {
          loadProblems.add(
            '${vectorsFile.path} top level is not a map or has no vectors: list',
          );
        } else {
          int index = 0;
          for (final v in yamlNode['vectors'] as YamlList) {
            if (v is! YamlMap) {
              loadProblems.add(
                'Vector entry at index $index in ${vectorsFile.path} is not a map',
              );
            } else {
              vectors.add(Vector.fromYaml(v, vectorsFile.path, index));
            }
            index++;
          }
        }
      }
    }

    final exclusionsFile = File('${testVectorsDir.path}/exclusions.yaml');
    if (exclusionsFile.existsSync()) {
      filesCount++;
      final content = exclusionsFile.readAsStringSync();
      dynamic yamlNode;
      try {
        yamlNode = loadYaml(content);
      } on YamlException catch (e) {
        loadProblems.add(
          'YAML parse error in ${exclusionsFile.path}: ${e.message}',
        );
      }

      if (yamlNode != null) {
        if (yamlNode is! YamlMap ||
            !yamlNode.containsKey('exclusions') ||
            yamlNode['exclusions'] is! YamlList) {
          loadProblems.add(
            '${exclusionsFile.path} top level is not a map or has no exclusions: list',
          );
        } else {
          int index = 0;
          for (final ex in yamlNode['exclusions'] as YamlList) {
            if (ex is! YamlMap) {
              loadProblems.add(
                'Exclusion entry at index $index in ${exclusionsFile.path} is not a map',
              );
            } else {
              exclusions.add(Exclusion.fromYaml(ex));
            }
            index++;
          }
        }
      }
    }

    return Inventory(
      vectors: vectors,
      exclusions: exclusions,
      filesCount: filesCount,
      loadProblems: loadProblems,
    );
  }
}
