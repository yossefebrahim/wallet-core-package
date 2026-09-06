import 'inventory.dart';

const validOperations = {
  'address',
  'sign',
  'sign_message',
  'plan',
  'compile',
  'invalid_input',
};

const validVariants = {
  'legacy',
  'eip1559',
  'contract_call',
  'p2pkh',
  'p2wpkh',
  'taproot',
  'multi_input',
  'versioned',
  'personal',
  'eip712',
  'n/a',
};

const validPlatforms = {'android', 'ios', 'host'};

const validVectorKeys = {
  'id',
  'coin',
  'operation',
  'variant',
  'source',
  'input',
  'expected',
  'platforms_verified',
};

List<String> validateInventory(Inventory inventory) {
  final errors = <String>[...inventory.loadProblems];
  final ids = <String>{};

  for (final vector in inventory.vectors) {
    final id = vector.id;
    final map = vector.rawMap;
    final displayId = id.isEmpty
        ? '${vector.filePath} index ${vector.index}'
        : id;

    for (final key in validVectorKeys) {
      if (!map.containsKey(key)) {
        errors.add('Missing required key "$key" in vector $displayId');
      }
    }

    for (final key in map.keys) {
      if (!validVectorKeys.contains(key)) {
        errors.add('Unknown key "$key" in vector $displayId');
      }
    }

    if (map.containsKey('source') &&
        map['source'] != null &&
        map['source'] is! Map) {
      errors.add('Field "source" must be a map in vector $displayId');
    }
    if (map.containsKey('input') &&
        map['input'] != null &&
        map['input'] is! Map) {
      errors.add('Field "input" must be a map in vector $displayId');
    }
    if (map.containsKey('expected') &&
        map['expected'] != null &&
        map['expected'] is! Map) {
      errors.add('Field "expected" must be a map in vector $displayId');
    }
    if (map.containsKey('platforms_verified') &&
        map['platforms_verified'] != null &&
        map['platforms_verified'] is! List) {
      errors.add(
        'Field "platforms_verified" must be a list in vector $displayId',
      );
    }

    if (id.isEmpty) {
      errors.add('Vector in ${vector.filePath} is missing an id.');
      continue;
    }

    if (ids.contains(id)) {
      errors.add('Duplicate id: $id');
    }
    ids.add(id);

    final expectedPattern =
        '^${RegExp.escape('${vector.coin}-${vector.operation}-${vector.variant}-')}[1-9]\\d*\$';
    if (!RegExp(expectedPattern).hasMatch(id)) {
      errors.add(
        'Id $id does not match exact pattern ^<coin>-<operation>-<variant>-<n>\$ with n as a positive integer.',
      );
    }

    if (!validOperations.contains(vector.operation)) {
      errors.add('Unknown operation: ${vector.operation} in vector $id');
    }

    if (!validVariants.contains(vector.variant)) {
      errors.add('Unknown variant: ${vector.variant} in vector $id');
    } else {
      if ((vector.operation == 'address' ||
              vector.operation == 'invalid_input') &&
          vector.variant != 'n/a') {
        errors.add(
          'Variant for operation ${vector.operation} must be n/a in vector $id',
        );
      } else if ((vector.operation != 'address' &&
              vector.operation != 'invalid_input') &&
          vector.variant == 'n/a') {
        errors.add(
          'Variant n/a is only for address and invalid_input in vector $id',
        );
      }
    }

    final source = vector.source;
    if (source == null) {
      errors.add('Missing source in vector $id');
    } else {
      final kind = source.kind;
      if (kind == 'upstream_test') {
        if (source.path == null || source.path!.isEmpty) {
          errors.add('Source kind upstream_test requires path in vector $id');
        }
        if (source.commit == null ||
            source.commit!.isEmpty ||
            source.commit!.length != 40 ||
            !RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(source.commit!)) {
          errors.add(
            'Source kind upstream_test requires a 40 hex commit in vector $id',
          );
        }
      } else if (kind == 'standard' || kind == 'published_tx') {
        if (source.reference == null || source.reference!.isEmpty) {
          errors.add('Source kind $kind requires reference in vector $id');
        }
      } else {
        errors.add('Unknown source kind: $kind in vector $id');
      }
    }

    for (final platform in vector.platformsVerified) {
      if (!validPlatforms.contains(platform)) {
        errors.add(
          'Platform $platform outside allowed set in platforms_verified for vector $id',
        );
      }
    }
  }

  for (final ex in inventory.exclusions) {
    if (!validOperations.contains(ex.operation)) {
      errors.add('Exclusion names unknown operation: ${ex.operation}');
    }
    if (ex.variant != null && !validVariants.contains(ex.variant)) {
      errors.add('Exclusion names unknown variant: ${ex.variant}');
    }
  }

  return errors;
}
