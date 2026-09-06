List<String> validateManifest(Map<String, Object?> raw, {bool strict = false}) {
  final errors = <String>[];

  void checkKeys(Map<String, Object?> map, String path, Set<String> expected) {
    final actual = map.keys.toSet();
    final missing = expected.difference(actual);
    if (missing.isNotEmpty) {
      errors.add('Missing keys at $path: ${missing.join(', ')}');
    }
    final unexpected = actual.difference(expected);
    if (unexpected.isNotEmpty) {
      errors.add('Unexpected keys at $path: ${unexpected.join(', ')}');
    }
  }

  bool checkType<T>(Object? value, String path) {
    if (value is! T) {
      errors.add('Wrong type at $path: expected $T, got ${value.runtimeType}');
      return false;
    }
    return true;
  }

  final topLevelKeys = {
    'upstream',
    'generators',
    'schemas',
    'artifacts',
    'packages',
    'toolchain',
    'release_set',
    'identity',
    'retention',
    'sbom',
    'reproducible_build_verified',
  };
  checkKeys(raw, 'root', topLevelKeys);

  final placeholderRegExp = RegExp(r'^TBD-T\d+\.\d+$');

  void validateValue(Object? value, String path) {
    if (value is String) {
      if (placeholderRegExp.hasMatch(value)) {
        if (strict) {
          errors.add('Placeholder found in strict mode at $path: $value');
        }
      }
    }
  }

  void validateSha(Object? value, String path) {
    if (value is String) {
      if (placeholderRegExp.hasMatch(value)) {
        if (strict) {
          errors.add('Placeholder found in strict mode at $path: $value');
        }
      } else {
        if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
          errors.add('Invalid sha256 at $path: $value');
        }
      }
    } else {
      checkType<String>(value, path);
    }
  }

  void validateSemver(Object? value, String path) {
    if (value is String) {
      if (placeholderRegExp.hasMatch(value)) {
        if (strict) {
          errors.add('Placeholder found in strict mode at $path: $value');
        }
      } else {
        if (!RegExp(
          r'^\d+\.\d+\.\d+(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
        ).hasMatch(value)) {
          errors.add('Invalid semver at $path: $value');
        }
      }
    } else {
      checkType<String>(value, path);
    }
  }

  if (raw['upstream'] is Map<String, Object?>) {
    final map = raw['upstream'] as Map<String, Object?>;
    checkKeys(map, 'upstream', {'repo', 'tag', 'commit'});
    if (checkType<String>(map['repo'], 'upstream.repo')) {
      validateValue(map['repo'], 'upstream.repo');
    }
    if (checkType<String>(map['tag'], 'upstream.tag')) {
      validateValue(map['tag'], 'upstream.tag');
    }
    if (checkType<String>(map['commit'], 'upstream.commit')) {
      validateValue(map['commit'], 'upstream.commit');
    }
  } else if (raw.containsKey('upstream')) {
    errors.add(
      'Wrong type at upstream: expected Map, got ${raw['upstream'].runtimeType}',
    );
  }

  if (raw['generators'] is Map<String, Object?>) {
    final map = raw['generators'] as Map<String, Object?>;
    checkKeys(map, 'generators', {
      'ffigen',
      'protoc',
      'protoc_gen_dart',
      'registry_transform',
    });
    for (final k in [
      'ffigen',
      'protoc',
      'protoc_gen_dart',
      'registry_transform',
    ]) {
      if (map.containsKey(k)) {
        if (checkType<String>(map[k], 'generators.$k')) {
          validateValue(map[k], 'generators.$k');
        }
      }
    }
  } else if (raw.containsKey('generators')) {
    errors.add(
      'Wrong type at generators: expected Map, got ${raw['generators'].runtimeType}',
    );
  }

  if (raw['schemas'] is Map<String, Object?>) {
    final map = raw['schemas'] as Map<String, Object?>;
    checkKeys(map, 'schemas', {
      'proto_dir_sha',
      'registry_json_sha',
      'headers_sha',
    });
    for (final k in ['proto_dir_sha', 'registry_json_sha', 'headers_sha']) {
      if (map.containsKey(k)) {
        if (checkType<String>(map[k], 'schemas.$k')) {
          validateValue(map[k], 'schemas.$k');
        }
      }
    }
  } else if (raw.containsKey('schemas')) {
    errors.add(
      'Wrong type at schemas: expected Map, got ${raw['schemas'].runtimeType}',
    );
  }

  if (raw['artifacts'] is Map<String, Object?>) {
    final map = raw['artifacts'] as Map<String, Object?>;
    checkKeys(map, 'artifacts', {
      'android/arm64-v8a/libTrustWalletCore.so',
      'android/armeabi-v7a/libTrustWalletCore.so',
      'android/x86_64/libTrustWalletCore.so',
      'ios/TrustWalletCore.xcframework.zip',
    });
    for (final k in map.keys) {
      final aMap = map[k];
      if (aMap is Map<String, Object?>) {
        checkKeys(aMap, 'artifacts["$k"]', {'sha256', 'size'});
        if (aMap.containsKey('sha256')) {
          validateSha(aMap['sha256'], 'artifacts["$k"].sha256');
        }
        if (aMap.containsKey('size')) {
          final size = aMap['size'];
          if (size is! int || size < 0) {
            errors.add(
              'Wrong type or value at artifacts["$k"].size: expected non-negative integer, got $size',
            );
          }
        }
      } else {
        errors.add(
          'Wrong type at artifacts["$k"]: expected Map, got ${aMap.runtimeType}',
        );
      }
    }
  } else if (raw.containsKey('artifacts')) {
    errors.add(
      'Wrong type at artifacts: expected Map, got ${raw['artifacts'].runtimeType}',
    );
  }

  if (raw['packages'] is Map<String, Object?>) {
    final map = raw['packages'] as Map<String, Object?>;
    checkKeys(map, 'packages', {
      'wallet_core_flutter',
      'wallet_core_flutter_bindings',
      'wallet_core_flutter_native',
    });
    for (final k in map.keys) {
      if (map.containsKey(k)) {
        validateSemver(map[k], 'packages.$k');
      }
    }
  } else if (raw.containsKey('packages')) {
    errors.add(
      'Wrong type at packages: expected Map, got ${raw['packages'].runtimeType}',
    );
  }

  if (raw['toolchain'] is Map<String, Object?>) {
    final map = raw['toolchain'] as Map<String, Object?>;
    checkKeys(map, 'toolchain', {'ndk', 'xcode', 'cmake', 'rust'});
    for (final k in map.keys) {
      if (map.containsKey(k)) {
        if (checkType<String>(map[k], 'toolchain.$k')) {
          validateValue(map[k], 'toolchain.$k');
        }
      }
    }
  } else if (raw.containsKey('toolchain')) {
    errors.add(
      'Wrong type at toolchain: expected Map, got ${raw['toolchain'].runtimeType}',
    );
  }

  if (raw.containsKey('release_set')) {
    if (checkType<String>(raw['release_set'], 'release_set')) {
      validateValue(raw['release_set'], 'release_set');
    }
  }

  if (raw['identity'] is Map<String, Object?>) {
    final map = raw['identity'] as Map<String, Object?>;
    checkKeys(map, 'identity', {
      'symbol',
      'artifact_set_id',
      'upstream_commit',
    });
    for (final k in map.keys) {
      if (map.containsKey(k)) {
        if (checkType<String>(map[k], 'identity.$k')) {
          validateValue(map[k], 'identity.$k');
        }
      }
    }
  } else if (raw.containsKey('identity')) {
    errors.add(
      'Wrong type at identity: expected Map, got ${raw['identity'].runtimeType}',
    );
  }

  if (raw['retention'] is Map<String, Object?>) {
    final map = raw['retention'] as Map<String, Object?>;
    checkKeys(map, 'retention', {'primary', 'mirror', 'policy'});
    if (map.containsKey('primary')) {
      if (checkType<String>(map['primary'], 'retention.primary')) {
        validateValue(map['primary'], 'retention.primary');
      }
    }
    if (map.containsKey('mirror')) {
      final mirror = map['mirror'];
      if (mirror != null) {
        if (checkType<String>(mirror, 'retention.mirror')) {
          validateValue(mirror, 'retention.mirror');
        }
      }
    }
    if (map.containsKey('policy')) {
      if (checkType<String>(map['policy'], 'retention.policy')) {
        validateValue(map['policy'], 'retention.policy');
      }
    }
  } else if (raw.containsKey('retention')) {
    errors.add(
      'Wrong type at retention: expected Map, got ${raw['retention'].runtimeType}',
    );
  }

  if (raw.containsKey('sbom')) {
    final sbom = raw['sbom'];
    if (sbom != null) {
      if (checkType<String>(sbom, 'sbom')) {
        validateValue(sbom, 'sbom');
      }
    }
  }

  if (raw.containsKey('reproducible_build_verified')) {
    checkType<bool>(
      raw['reproducible_build_verified'],
      'reproducible_build_verified',
    );
  }

  return errors;
}
