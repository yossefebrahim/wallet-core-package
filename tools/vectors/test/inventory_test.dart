import 'dart:io';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';
import 'package:wcf_tool_vectors/inventory.dart';
import 'package:wcf_tool_vectors/validator.dart';

void main() {
  group('Inventory Loader and Validator', () {
    test('Valid inventory fixtures', () {
      final dir = Directory('test/fixtures');
      final inventory = Inventory.load(dir);

      expect(inventory.vectors.length, 3);
      expect(inventory.exclusions.length, 1);

      final errors = validateInventory(inventory);
      expect(
        errors,
        isEmpty,
        reason: 'Expected no errors for valid fixture inventory',
      );
    });

    test('Empty inventory should be valid', () {
      final dir = Directory('test/does_not_exist');
      final inventory = Inventory.load(dir);

      expect(inventory.vectors, isEmpty);
      expect(inventory.exclusions, isEmpty);

      final errors = validateInventory(inventory);
      expect(errors, isEmpty);
    });

    test('Missing ID', () {
      final v = _createVector(id: '');
      final errors = validateInventory(
        Inventory(
          vectors: [v],
          exclusions: [],
          filesCount: 1,
          loadProblems: [],
        ),
      );
      expect(errors.any((e) => e.contains('missing an id')), isTrue);
    });

    test('Duplicate ID', () {
      final v1 = _createVector();
      final v2 = _createVector();
      final errors = validateInventory(
        Inventory(
          vectors: [v1, v2],
          exclusions: [],
          filesCount: 1,
          loadProblems: [],
        ),
      );
      expect(errors.any((e) => e.contains('Duplicate id')), isTrue);
    });

    test('ID does not match coin/operation/variant', () {
      final v = _createVector(id: 'wrong-id-format');
      final errors = validateInventory(
        Inventory(
          vectors: [v],
          exclusions: [],
          filesCount: 1,
          loadProblems: [],
        ),
      );
      expect(
        errors.any((e) => e.contains('does not match exact pattern')),
        isTrue,
      );
    });

    test('Unknown operation', () {
      final v = _createVector(
        operation: 'unknown_op',
        id: 'ethereum-unknown_op-n/a-1',
        variant: 'n/a',
      );
      final errors = validateInventory(
        Inventory(
          vectors: [v],
          exclusions: [],
          filesCount: 1,
          loadProblems: [],
        ),
      );
      expect(errors.any((e) => e.contains('Unknown operation')), isTrue);
    });

    test('Unknown variant', () {
      final v = _createVector(
        variant: 'unknown_variant',
        id: 'ethereum-sign-unknown_variant-1',
      );
      final errors = validateInventory(
        Inventory(
          vectors: [v],
          exclusions: [],
          filesCount: 1,
          loadProblems: [],
        ),
      );
      expect(errors.any((e) => e.contains('Unknown variant')), isTrue);
    });

    test('Address operation must have n/a variant', () {
      final v = _createVector(
        operation: 'address',
        variant: 'legacy',
        id: 'ethereum-address-legacy-1',
      );
      final errors = validateInventory(
        Inventory(
          vectors: [v],
          exclusions: [],
          filesCount: 1,
          loadProblems: [],
        ),
      );
      expect(errors.any((e) => e.contains('must be n/a')), isTrue);
    });

    test('Sign operation cannot have n/a variant', () {
      final v = _createVector(
        operation: 'sign',
        variant: 'n/a',
        id: 'ethereum-sign-n/a-1',
      );
      final errors = validateInventory(
        Inventory(
          vectors: [v],
          exclusions: [],
          filesCount: 1,
          loadProblems: [],
        ),
      );
      expect(
        errors.any((e) => e.contains('only for address and invalid_input')),
        isTrue,
      );
    });

    test('Missing source', () {
      final v = _createVector(hasSource: false);
      final errors = validateInventory(
        Inventory(
          vectors: [v],
          exclusions: [],
          filesCount: 1,
          loadProblems: [],
        ),
      );
      expect(errors.any((e) => e.contains('Missing source')), isTrue);
    });

    test('Upstream source requires path', () {
      final v = _createVector(
        source: VectorSource(
          kind: 'upstream_test',
          commit: '0123456789abcdef0123456789abcdef01234567',
        ),
      );
      final errors = validateInventory(
        Inventory(
          vectors: [v],
          exclusions: [],
          filesCount: 1,
          loadProblems: [],
        ),
      );
      expect(errors.any((e) => e.contains('requires path')), isTrue);
    });

    test('Upstream source requires valid commit', () {
      final v = _createVector(
        source: VectorSource(
          kind: 'upstream_test',
          path: 'path',
          commit: 'short',
        ),
      );
      final errors = validateInventory(
        Inventory(
          vectors: [v],
          exclusions: [],
          filesCount: 1,
          loadProblems: [],
        ),
      );
      expect(errors.any((e) => e.contains('requires a 40 hex commit')), isTrue);
    });

    test('Standard source requires reference', () {
      final v = _createVector(source: VectorSource(kind: 'standard'));
      final errors = validateInventory(
        Inventory(
          vectors: [v],
          exclusions: [],
          filesCount: 1,
          loadProblems: [],
        ),
      );
      expect(errors.any((e) => e.contains('requires reference')), isTrue);
    });

    test('Invalid platform', () {
      final v = _createVector(platformsVerified: ['windows']);
      final errors = validateInventory(
        Inventory(
          vectors: [v],
          exclusions: [],
          filesCount: 1,
          loadProblems: [],
        ),
      );
      expect(errors.any((e) => e.contains('outside allowed set')), isTrue);
    });

    test('Exclusion unknown operation', () {
      final ex = Exclusion(coin: 'eth', operation: 'unknown', reason: 'r');
      final v = _createVector();
      final errors = validateInventory(
        Inventory(
          vectors: [v],
          exclusions: [ex],
          filesCount: 1,
          loadProblems: [],
        ),
      );
      expect(
        errors.any((e) => e.contains('Exclusion names unknown operation')),
        isTrue,
      );
    });

    test('Exclusion unknown variant', () {
      final ex = Exclusion(
        coin: 'eth',
        operation: 'sign',
        variant: 'unknown',
        reason: 'r',
      );
      final v = _createVector();
      final errors = validateInventory(
        Inventory(
          vectors: [v],
          exclusions: [ex],
          filesCount: 1,
          loadProblems: [],
        ),
      );
      expect(
        errors.any((e) => e.contains('Exclusion names unknown variant')),
        isTrue,
      );
    });

    test('Structural problems are reported', () {
      final dir = Directory('test/invalid_load');
      final inventory = Inventory.load(dir);
      final errors = validateInventory(inventory);
      expect(errors, isNotEmpty);
      expect(errors.any((e) => e.contains('without vectors.yaml')), isTrue);
      expect(
        errors.any((e) => e.contains('is not a map or has no vectors: list')),
        isTrue,
      );
      expect(
        errors.any((e) => e.contains('is not a map') && e.contains('index 1')),
        isTrue,
      );
      expect(errors.any((e) => e.contains('YAML parse error')), isTrue);
      expect(errors.any((e) => e.contains('has no exclusions: list')), isTrue);
    });

    test('Closed key set and shapes', () {
      final v = _createVector(
        rawMapOverrides: {
          'extra_key': 123,
          'source': 'not a map',
          'input': 'not a map',
          'expected': 'not a map',
          'platforms_verified': <String, dynamic>{},
        },
      );
      final errors = validateInventory(
        Inventory(
          vectors: [v],
          exclusions: [],
          filesCount: 1,
          loadProblems: [],
        ),
      );
      expect(errors.any((e) => e.contains('Unknown key "extra_key"')), isTrue);
      expect(
        errors.any((e) => e.contains('Field "source" must be a map')),
        isTrue,
      );
      expect(
        errors.any((e) => e.contains('Field "input" must be a map')),
        isTrue,
      );
      expect(
        errors.any((e) => e.contains('Field "expected" must be a map')),
        isTrue,
      );
      expect(
        errors.any(
          (e) => e.contains('Field "platforms_verified" must be a list'),
        ),
        isTrue,
      );
    });

    test('Missing required keys', () {
      final v = _createVector(
        rawMapOverrides: <String, dynamic>{},
        omitRequiredKeys: true,
      );
      final errors = validateInventory(
        Inventory(
          vectors: [v],
          exclusions: [],
          filesCount: 1,
          loadProblems: [],
        ),
      );
      expect(
        errors.any((e) => e.contains('Missing required key "id"')),
        isTrue,
      );
      expect(
        errors.any((e) => e.contains('Missing required key "coin"')),
        isTrue,
      );
    });

    test('Exact ID pattern', () {
      final v1 = _createVector(
        id: 'ethereum-sign-eip1559-0',
      ); // 0 is not positive
      final v2 = _createVector(id: 'ethereum-sign-eip1559-abc');
      final v3 = _createVector(id: 'ethereum-sign-eip1559-1-extra');
      final errors = validateInventory(
        Inventory(
          vectors: [v1, v2, v3],
          exclusions: [],
          filesCount: 1,
          loadProblems: [],
        ),
      );
      expect(errors.where((e) => e.contains('exact pattern')).length, 3);
    });
  });
}

Vector _createVector({
  String id = 'ethereum-sign-eip1559-1',
  String coin = 'ethereum',
  String operation = 'sign',
  String variant = 'eip1559',
  bool hasSource = true,
  VectorSource? source,
  List<String>? platformsVerified,
  Map<String, dynamic>? rawMapOverrides,
  bool omitRequiredKeys = false,
}) {
  final map = <String, dynamic>{};
  if (!omitRequiredKeys) {
    map['id'] = id;
    map['coin'] = coin;
    map['operation'] = operation;
    map['variant'] = variant;
    map['source'] = hasSource ? <String, dynamic>{} : null;
    map['input'] = <String, dynamic>{};
    map['expected'] = <String, dynamic>{};
    map['platforms_verified'] = platformsVerified ?? [];
  }
  if (rawMapOverrides != null) {
    map.addAll(rawMapOverrides);
  }

  return Vector(
    id: id,
    coin: coin,
    operation: operation,
    variant: variant,
    source: hasSource
        ? (source ?? VectorSource(kind: 'standard', reference: 'ref'))
        : null,
    input: <String, dynamic>{},
    expected: <String, dynamic>{},
    platformsVerified: platformsVerified ?? [],
    rawMap: YamlMap.wrap(map),
    filePath: 'test.yaml',
    index: 0,
  );
}
