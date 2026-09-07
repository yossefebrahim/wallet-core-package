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

  // ---------------------------------------------------------------------
  // artifacts — DECISION-14 §5.1, D0 findings F6 and F14
  //
  // The Phase 0 validator required exactly four hard-coded keys, so adding an
  // ABI or dropping `armeabi-v7a` (which PRD §12.2 step 8 says we do unless it
  // is device-tested) meant editing the validator. The key set is now a path
  // grammar and the value is the fourteen-field record DECISION-14 §5.1
  // models.
  //
  // A record is checked in full once its `sha256` is a real digest. Before
  // that it is a placeholder written by an earlier task, and only `sha256` and
  // `size` are required — which is what keeps a `TBD-` manifest valid without
  // --strict while the artifact set does not exist yet. `--strict` still
  // rejects every placeholder, so a release cannot ship one.
  // ---------------------------------------------------------------------

  final identityMap = raw['identity'] is Map<String, Object?>
      ? raw['identity'] as Map<String, Object?>
      : const <String, Object?>{};
  final declaredSetId = identityMap['artifact_set_id'];
  final perArtifactToolchains = <String, Map<String, Object?>>{};

  if (raw['artifacts'] is Map<String, Object?>) {
    final map = raw['artifacts'] as Map<String, Object?>;
    for (final k in map.keys) {
      final path = 'artifacts["$k"]';
      final segments = k.split('/');
      if (!_logicalNameRegExp.hasMatch(k) ||
          k.contains('__') ||
          segments.any((s) => s == '.' || s == '..')) {
        errors.add(
          'Invalid artifact key at $path: expected "/"-separated path segments '
          'of [A-Za-z0-9._+-], no "." or ".." segment and no "__", got $k',
        );
      }
      final aMap = map[k];
      if (aMap is! Map<String, Object?>) {
        errors.add(
          'Wrong type at $path: expected Map, got ${aMap.runtimeType}',
        );
        continue;
      }

      final sha = aMap['sha256'];
      final populated = sha is String && _sha256RegExp.hasMatch(sha);

      if (!aMap.containsKey('sha256')) {
        errors.add('Missing keys at $path: sha256');
      } else {
        validateSha(sha, '$path.sha256');
      }

      final size = aMap['size'];
      if (!aMap.containsKey('size')) {
        errors.add('Missing keys at $path: size');
      } else if (size is! int || size < 0) {
        errors.add(
          'Wrong type or value at $path.size: expected non-negative integer, got $size',
        );
      } else if (populated && size == 0) {
        errors.add(
          'Wrong value at $path.size: a built artifact cannot be 0 bytes',
        );
      }

      if (!populated) {
        // Placeholder record. Anything beyond sha256/size that IS present is
        // still type-checked below via the same code paths, but nothing more
        // is required: the artifact does not exist yet.
        for (final extra in aMap.keys) {
          if (!_artifactRecordKeys.contains(extra)) {
            errors.add('Unexpected keys at $path: $extra');
          }
        }
        continue;
      }

      checkKeys(aMap, path, _artifactRecordKeys);

      for (final field in const [
        'source_commit',
        'build_workflow',
        'linkage',
        'target_os',
        'abi',
        'min_os',
        'provenance',
        'asset_name',
        'logical_name',
      ]) {
        if (aMap.containsKey(field)) {
          checkType<String>(aMap[field], '$path.$field');
        }
      }

      final sourceCommit = aMap['source_commit'];
      if (sourceCommit is String && !_commitRegExp.hasMatch(sourceCommit)) {
        errors.add(
          'Invalid source_commit at $path.source_commit: expected 40 lowercase hex, got $sourceCommit',
        );
      }

      final workflow = aMap['build_workflow'];
      if (workflow is String && !workflow.startsWith('https://')) {
        errors.add(
          'Invalid build_workflow at $path.build_workflow: expected an absolute https URL, got $workflow',
        );
      }

      final linkage = aMap['linkage'];
      if (linkage is String && !const ['static', 'dynamic'].contains(linkage)) {
        errors.add(
          'Invalid linkage at $path.linkage: expected static or dynamic, got $linkage',
        );
      }

      final targetOs = aMap['target_os'];
      if (targetOs is String &&
          !const [
            'android',
            'ios',
            'ios-simulator',
            'macos',
          ].contains(targetOs)) {
        errors.add(
          'Invalid target_os at $path.target_os: expected android, ios, ios-simulator or macos, got $targetOs',
        );
      }

      final provenance = aMap['provenance'];
      if (provenance is String &&
          !const [
            'built_from_source',
            'relinked_from_upstream_release_asset',
          ].contains(provenance)) {
        errors.add(
          'Invalid provenance at $path.provenance: expected built_from_source or '
          'relinked_from_upstream_release_asset, got $provenance',
        );
      }

      // `abi` and `min_os` are free strings on purpose: an Android API level
      // and an Apple deployment target are not the same kind of value and
      // coercing them into one would lose which is which (DECISION-14 §5.1
      // note 4). Empty, though, is never right.
      for (final field in const ['abi', 'min_os']) {
        final value = aMap[field];
        if (value is String && value.isEmpty) {
          errors.add('Empty value at $path.$field');
        }
      }

      // Nullable is not optional: the keys are present and explicitly null
      // before T4.5 lands, so "not yet attested" is a recorded fact rather
      // than a missing field.
      final signature = aMap['signature'];
      if (aMap.containsKey('signature') &&
          signature != null &&
          signature is! String) {
        errors.add(
          'Wrong type at $path.signature: expected String or null, got ${signature.runtimeType}',
        );
      }
      final attestation = aMap['attestation'];
      if (aMap.containsKey('attestation') &&
          attestation != null &&
          attestation is! Map<String, Object?>) {
        errors.add(
          'Wrong type at $path.attestation: expected Map or null, got ${attestation.runtimeType}',
        );
      }

      final toolchain = aMap['toolchain'];
      if (aMap.containsKey('toolchain')) {
        if (toolchain is Map<String, Object?>) {
          if (toolchain.isEmpty) {
            errors.add('Empty object at $path.toolchain');
          }
          toolchain.forEach((tk, tv) {
            if (tv is! String) {
              errors.add(
                'Wrong type at $path.toolchain.$tk: expected String, got ${tv.runtimeType}',
              );
            }
          });
          perArtifactToolchains[k] = toolchain;
        } else {
          errors.add(
            'Wrong type at $path.toolchain: expected Map, got ${toolchain.runtimeType}',
          );
        }
      }

      final logicalName = aMap['logical_name'];
      if (logicalName is String && logicalName != k) {
        errors.add(
          'Mismatch at $path.logical_name: the record says $logicalName but the map key is $k',
        );
      }

      // The primary asset name of DECISION-14 §3.1, checked character for
      // character. A prefix of the digest would not be content addressing, so
      // the embedded digest must equal the record's own, in full.
      final assetName = aMap['asset_name'];
      // `sha` is already known to be a String here: `populated` is a local
      // boolean holding that type test, which Dart promotes through.
      if (assetName is String) {
        if (assetName.length > 255) {
          errors.add(
            'Too long at $path.asset_name: ${assetName.length} characters, '
            'over the 255-character GitHub release asset limit',
          );
        }
        final parts = assetName.split('__');
        if (parts.length != 3) {
          errors.add(
            'Invalid asset_name at $path.asset_name: expected '
            '<artifact_set_id>__<sha256>__<flat_name>, got $assetName',
          );
        } else {
          if (!_artifactSetIdRegExp.hasMatch(parts[0])) {
            errors.add(
              'Invalid artifact set id in $path.asset_name: expected as_<tag>_<nnn>, got ${parts[0]}',
            );
          }
          if (declaredSetId is String &&
              !placeholderRegExp.hasMatch(declaredSetId) &&
              parts[0] != declaredSetId) {
            errors.add(
              'Mismatch in $path.asset_name: it carries set id ${parts[0]} but '
              'identity.artifact_set_id is $declaredSetId',
            );
          }
          if (parts[1] != sha) {
            errors.add(
              'Mismatch in $path.asset_name: it carries digest ${parts[1]} but '
              '$path.sha256 is $sha',
            );
          }
          final flat = k.replaceAll('/', '-');
          if (parts[2] != flat) {
            errors.add(
              'Mismatch in $path.asset_name: it carries flat name ${parts[2]} but '
              'the logical name flattens to $flat',
            );
          }
        }
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

  // ---------------------------------------------------------------------
  // toolchain — a SET-WIDE SUMMARY, not the authority (DECISION-14 §5.1 note 1)
  //
  // Under DECISION-9 Option C one artifact set contains artifacts built by two
  // different toolchains: a clang relink on Apple and a full NDK/CMake/Rust
  // build on Android. A single top-level block cannot describe both without
  // being either wrong or empty, so the per-artifact `toolchain` object is
  // authoritative and this block carries only what the set agrees on. The key
  // set is therefore no longer fixed, and what it does claim is checked
  // against the artifacts rather than assumed.
  // ---------------------------------------------------------------------
  if (raw['toolchain'] is Map<String, Object?>) {
    final map = raw['toolchain'] as Map<String, Object?>;
    for (final k in map.keys) {
      if (checkType<String>(map[k], 'toolchain.$k')) {
        validateValue(map[k], 'toolchain.$k');
        final claimed = map[k] as String;
        if (!placeholderRegExp.hasMatch(claimed)) {
          perArtifactToolchains.forEach((artifact, toolchain) {
            final actual = toolchain[k];
            if (actual is String && actual != claimed) {
              errors.add(
                'Disagreement at toolchain.$k: the set-wide summary says $claimed '
                'but artifacts["$artifact"].toolchain.$k says $actual',
              );
            }
          });
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
    // `build_workflow` is DECISION-14 §5's new field. It is optional while the
    // artifact set is a placeholder and required once one exists, because it
    // is one of the three values compiled into wcf_build_info() and a set that
    // cannot name the run that produced it is not identifiable.
    final missing = {
      'symbol',
      'artifact_set_id',
      'upstream_commit',
    }.difference(map.keys.toSet());
    if (missing.isNotEmpty) {
      errors.add('Missing keys at identity: ${missing.join(', ')}');
    }
    final unexpected = map.keys.toSet().difference({
      'symbol',
      'artifact_set_id',
      'upstream_commit',
      'build_workflow',
    });
    if (unexpected.isNotEmpty) {
      errors.add('Unexpected keys at identity: ${unexpected.join(', ')}');
    }
    for (final k in map.keys) {
      if (checkType<String>(map[k], 'identity.$k')) {
        validateValue(map[k], 'identity.$k');
      }
    }
    final symbol = map['symbol'];
    if (symbol is String && symbol != 'wcf_build_info') {
      errors.add(
        'Invalid identity.symbol: DECISION-14 §2.1 fixes it at wcf_build_info, got $symbol',
      );
    }
    final setId = map['artifact_set_id'];
    if (setId is String && !placeholderRegExp.hasMatch(setId)) {
      if (!_artifactSetIdRegExp.hasMatch(setId)) {
        errors.add(
          'Invalid identity.artifact_set_id: expected as_<tag>_<nnn>, got $setId',
        );
      }
      final workflow = map['build_workflow'];
      if (workflow is! String) {
        errors.add(
          'Missing keys at identity: build_workflow is required once '
          'artifact_set_id names a real artifact set',
        );
      } else if (!placeholderRegExp.hasMatch(workflow) &&
          !workflow.startsWith('https://')) {
        errors.add(
          'Invalid identity.build_workflow: expected an absolute https URL, got $workflow',
        );
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

// ---------------------------------------------------------------------------
// Shapes the artifact half of the manifest is held to (DECISION-14 §3.1, §5.1)
// ---------------------------------------------------------------------------

/// The manifest key of an artifact, which is also its path on the mirror and,
/// flattened, the tail of its primary asset name. Path segments only: the
/// grammar is what replaced the four hard-coded keys of the Phase 0 validator
/// (D0 finding F14), so shipping one more ABI or dropping an untested one is a
/// manifest edit and not a validator edit.
final RegExp _logicalNameRegExp = RegExp(
  r'^[A-Za-z0-9._+-]+(?:/[A-Za-z0-9._+-]+)*$',
);

final RegExp _sha256RegExp = RegExp(r'^[0-9a-f]{64}$');

final RegExp _commitRegExp = RegExp(r'^[0-9a-f]{40}$');

/// `as_<upstreamTag>_<3-digit sequence>` (DECISION-14 §2.1). The sequence is
/// exactly three digits and is never reused.
final RegExp _artifactSetIdRegExp = RegExp(r'^as_[0-9A-Za-z._-]+_[0-9]{3}$');

/// The fourteen fields of DECISION-14 §5.1. PRD §12.3's "Durability [REQ]"
/// names eleven of them — source commit, build workflow, linkage type, target
/// OS, ABI, minimum OS, toolchain, size, checksum, signature and attestation
/// identity — and DECISION-9 adds `provenance`, DECISION-14 §3.1 the two name
/// fields.
const Set<String> _artifactRecordKeys = {
  'sha256',
  'size',
  'source_commit',
  'build_workflow',
  'linkage',
  'target_os',
  'abi',
  'min_os',
  'toolchain',
  'signature',
  'attestation',
  'provenance',
  'asset_name',
  'logical_name',
};
