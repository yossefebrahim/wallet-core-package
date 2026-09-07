// Tests for the per-artifact record of DECISION-14 §5.1 and the set-wide
// toolchain summary of §5.1 note 1 — the artifact/toolchain half of the
// validator, extended by T1.2.
//
// The fixture record is a real one: the digest, size, min_os and toolchain are
// what tools/native_build/build_apple.sh produced when it relinked upstream's
// macos-arm64_x86_64 slice on 2026-09-07. Using measured values rather than
// invented ones means the test would notice if the record shape and the
// producer ever drifted apart.

import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:wcf_tool_manifest/manifest.dart';
import 'package:wcf_tool_manifest/validator.dart';

const _sha = '0f5f6ddf21ec6a65b143432d90d10ed362ec4562073b001ced7713bc2e93dd09';
const _setId = 'as_4.8.0_001';
const _commit = 'd692ac27749d0c615e17c751b70ab4f0aa75c59b';
const _workflow =
    'https://github.com/yossefebrahim/wallet-core-package/actions/runs/1234567890';
const _logical = 'macos/arm64_x86_64/libTrustWalletCore.dylib';
const _assetName =
    '${_setId}__${_sha}__macos-arm64_x86_64-libTrustWalletCore.dylib';

Map<String, dynamic> _record({Map<String, dynamic> overrides = const {}}) => {
  'sha256': _sha,
  'size': 41242120,
  'source_commit': _commit,
  'build_workflow': _workflow,
  'linkage': 'dynamic',
  'target_os': 'macos',
  'abi': 'arm64_x86_64',
  'min_os': '26.0',
  'toolchain': {
    'xcode': '17F113',
    'clang': 'Apple clang version 21.0.0 (clang-2100.1.1.101)',
    'sdk': 'macosx26.5',
  },
  'signature': null,
  'attestation': null,
  'provenance': 'relinked_from_upstream_release_asset',
  'asset_name': _assetName,
  'logical_name': _logical,
  ...overrides,
};

/// The checked-in manifest with a populated artifact set spliced in, so the
/// tests exercise the shape a real release would carry.
Map<String, dynamic> _populatedManifest({
  Map<String, dynamic>? artifacts,
  Map<String, dynamic>? identity,
  Map<String, dynamic>? toolchain,
}) {
  final decoded =
      jsonDecode(File('../../compat_manifest.json').readAsStringSync())
          as Map<String, dynamic>;
  decoded['artifacts'] = artifacts ?? {_logical: _record()};
  decoded['identity'] =
      identity ??
      {
        'symbol': 'wcf_build_info',
        'artifact_set_id': _setId,
        'upstream_commit': _commit,
        'build_workflow': _workflow,
      };
  decoded['toolchain'] = toolchain ?? {'xcode': '17F113'};
  return decoded;
}

void main() {
  group('per-artifact record (DECISION-14 §5.1)', () {
    test('a fully populated record validates with zero problems', () {
      expect(validateManifest(_populatedManifest()), isEmpty);
    });

    test('the model reads every field back', () {
      final manifest = Manifest.parse(jsonEncode(_populatedManifest()));
      final artifact = manifest.artifacts[_logical]!;
      expect(artifact.isPopulated, isTrue);
      expect(artifact.sha256, _sha);
      expect(artifact.size, 41242120);
      expect(artifact.sourceCommit, _commit);
      expect(artifact.linkage, 'dynamic');
      expect(artifact.targetOs, 'macos');
      expect(artifact.abi, 'arm64_x86_64');
      expect(artifact.minOs, '26.0');
      expect(artifact.toolchain!['xcode'], '17F113');
      expect(artifact.signature, isNull);
      expect(artifact.attestation, isNull);
      expect(artifact.provenance, 'relinked_from_upstream_release_asset');
      expect(artifact.assetName, _assetName);
      expect(artifact.logicalName, _logical);
      expect(manifest.identity.buildWorkflow, _workflow);
      expect(manifest.toolchain['xcode'], '17F113');
    });

    test('a populated record must carry all fourteen fields', () {
      final partial = _record()..remove('provenance');
      final errors = validateManifest(
        _populatedManifest(artifacts: {_logical: partial}),
      );
      expect(
        errors,
        contains(
          contains('Missing keys at artifacts["$_logical"]: provenance'),
        ),
      );
    });

    test('a placeholder record needs only sha256 and size', () {
      final errors = validateManifest(
        _populatedManifest(
          artifacts: {
            'android/arm64-v8a/libTrustWalletCore.so': {
              'sha256': 'TBD-T1.2',
              'size': 0,
            },
          },
        ),
      );
      expect(errors, isEmpty);
    });

    test(
      'the checked-in placeholder manifest still validates without --strict',
      () {
        final decoded =
            jsonDecode(File('../../compat_manifest.json').readAsStringSync())
                as Map<String, dynamic>;
        expect(validateManifest(decoded), isEmpty);
        expect(
          validateManifest(
            decoded,
            strict: true,
          ).any((e) => e.contains('Placeholder found')),
          isTrue,
        );
      },
    );

    test('a built artifact cannot be zero bytes', () {
      final errors = validateManifest(
        _populatedManifest(
          artifacts: {
            _logical: _record(overrides: {'size': 0}),
          },
        ),
      );
      expect(errors, contains(contains('a built artifact cannot be 0 bytes')));
    });

    test('source_commit must be 40 lowercase hex', () {
      final errors = validateManifest(
        _populatedManifest(
          artifacts: {
            _logical: _record(overrides: {'source_commit': 'D692AC27'}),
          },
        ),
      );
      expect(errors, contains(contains('Invalid source_commit')));
    });

    test('build_workflow must be an absolute https URL', () {
      final errors = validateManifest(
        _populatedManifest(
          artifacts: {
            _logical: _record(overrides: {'build_workflow': 'local'}),
          },
        ),
      );
      expect(errors, contains(contains('Invalid build_workflow')));
    });

    test('linkage, target_os and provenance are closed domains', () {
      final errors = validateManifest(
        _populatedManifest(
          artifacts: {
            _logical: _record(
              overrides: {
                'linkage': 'shared',
                'target_os': 'linux',
                'provenance': 'downloaded',
              },
            ),
          },
        ),
      );
      expect(errors, contains(contains('Invalid linkage')));
      expect(errors, contains(contains('Invalid target_os')));
      expect(errors, contains(contains('Invalid provenance')));
    });

    test('signature and attestation are nullable but typed', () {
      expect(
        validateManifest(
          _populatedManifest(
            artifacts: {
              _logical: _record(
                overrides: {
                  'signature': 'as_4.8.0_001__sig.sig',
                  'attestation': {'subject_digest': 'sha256:$_sha'},
                },
              ),
            },
          ),
        ),
        isEmpty,
      );
      final errors = validateManifest(
        _populatedManifest(
          artifacts: {
            _logical: _record(overrides: {'attestation': 'yes'}),
          },
        ),
      );
      expect(
        errors,
        contains(contains('Wrong type at artifacts["$_logical"].attestation')),
      );
    });

    test('logical_name must repeat the map key', () {
      final errors = validateManifest(
        _populatedManifest(
          artifacts: {
            _logical: _record(overrides: {'logical_name': 'macos/other.dylib'}),
          },
        ),
      );
      expect(
        errors,
        contains(contains('Mismatch at artifacts["$_logical"].logical_name')),
      );
    });
  });

  group('asset name (DECISION-14 §3.1)', () {
    test(
      'a truncated digest is rejected — a prefix is not content addressing',
      () {
        final errors = validateManifest(
          _populatedManifest(
            artifacts: {
              _logical: _record(
                overrides: {
                  'asset_name':
                      '${_setId}__${_sha.substring(0, 12)}__macos-arm64_x86_64-libTrustWalletCore.dylib',
                },
              ),
            },
          ),
        );
        expect(errors, contains(contains('it carries digest')));
      },
    );

    test('the embedded set id must equal identity.artifact_set_id', () {
      final errors = validateManifest(
        _populatedManifest(
          artifacts: {
            _logical: _record(
              overrides: {
                'asset_name':
                    'as_4.8.0_002__${_sha}__macos-arm64_x86_64-libTrustWalletCore.dylib',
              },
            ),
          },
        ),
      );
      expect(errors, contains(contains('it carries set id as_4.8.0_002')));
    });

    test('the flat name must be the logical name with / replaced by -', () {
      final errors = validateManifest(
        _populatedManifest(
          artifacts: {
            _logical: _record(
              overrides: {
                'asset_name': '${_setId}__${_sha}__libTrustWalletCore.dylib',
              },
            ),
          },
        ),
      );
      expect(errors, contains(contains('it carries flat name')));
    });

    test('three fields separated by __, no more and no fewer', () {
      final errors = validateManifest(
        _populatedManifest(
          artifacts: {
            _logical: _record(
              overrides: {'asset_name': 'libTrustWalletCore.dylib'},
            ),
          },
        ),
      );
      expect(errors, contains(contains('Invalid asset_name')));
    });

    test('an asset name over 255 characters is rejected at build time', () {
      final longKey = 'macos/${'x' * 200}/libTrustWalletCore.dylib';
      final errors = validateManifest(
        _populatedManifest(
          artifacts: {
            longKey: _record(
              overrides: {
                'logical_name': longKey,
                'asset_name':
                    '${_setId}__${_sha}__${longKey.replaceAll('/', '-')}',
              },
            ),
          },
        ),
      );
      expect(
        errors,
        contains(contains('over the 255-character GitHub release asset limit')),
      );
    });
  });

  group('artifact keys are a path grammar, not a fixed set (D0 finding F14)', () {
    test('an ABI the Phase 0 validator never heard of is accepted', () {
      final errors = validateManifest(
        _populatedManifest(
          artifacts: {
            'android/riscv64/libTrustWalletCore.so': _record(
              overrides: {
                'logical_name': 'android/riscv64/libTrustWalletCore.so',
                'target_os': 'android',
                'abi': 'riscv64',
                'min_os': '21',
                'provenance': 'built_from_source',
                'toolchain': {'ndk': '28.0.12674087'},
                'asset_name':
                    '${_setId}__${_sha}__android-riscv64-libTrustWalletCore.so',
              },
            ),
          },
        ),
      );
      expect(errors, isEmpty);
    });

    test('dropping armeabi-v7a is a manifest edit, not a validator edit', () {
      // PRD §12.2 step 8: an ABI that is not device-tested is dropped rather
      // than shipped. The Phase 0 validator required the key to be present.
      final errors = validateManifest(
        _populatedManifest(artifacts: {_logical: _record()}),
      );
      expect(errors, isEmpty);
    });

    test('a key that is not a path is rejected', () {
      for (final bad in const [
        '/android/arm64-v8a/libTrustWalletCore.so',
        'android//libTrustWalletCore.so',
        'android/../secrets',
        'android/arm64-v8a__libTrustWalletCore.so',
      ]) {
        final errors = validateManifest(
          _populatedManifest(
            artifacts: {
              bad: _record(overrides: {'logical_name': bad}),
            },
          ),
        );
        expect(
          errors,
          contains(contains('Invalid artifact key')),
          reason: 'expected $bad to be rejected',
        );
      }
    });
  });

  group('toolchain is a set-wide summary (DECISION-14 §5.1 note 1)', () {
    test('a summary that matches every artifact validates', () {
      expect(
        validateManifest(_populatedManifest(toolchain: {'xcode': '17F113'})),
        isEmpty,
      );
    });

    test('a summary that contradicts an artifact is an error', () {
      final errors = validateManifest(
        _populatedManifest(toolchain: {'xcode': '16A242'}),
      );
      expect(errors, contains(contains('Disagreement at toolchain.xcode')));
    });

    test('a summary key no artifact carries is allowed', () {
      // One set holds artifacts from two toolchains, so the summary can name
      // an NDK version the Apple artifacts know nothing about.
      expect(
        validateManifest(
          _populatedManifest(toolchain: {'ndk': '28.0.12674087'}),
        ),
        isEmpty,
      );
    });

    test('the Phase 0 four-key toolchain block still validates', () {
      expect(
        validateManifest(
          _populatedManifest(
            toolchain: {
              'ndk': 'TBD-T1.2',
              'xcode': 'TBD-T1.2',
              'cmake': 'TBD-T1.2',
              'rust': 'TBD-T1.2',
            },
          ),
        ),
        isEmpty,
      );
    });
  });

  group('identity (DECISION-14 §5)', () {
    test('build_workflow is required once a real artifact set is named', () {
      final errors = validateManifest(
        _populatedManifest(
          identity: {
            'symbol': 'wcf_build_info',
            'artifact_set_id': _setId,
            'upstream_commit': _commit,
          },
        ),
      );
      expect(errors, contains(contains('build_workflow is required')));
    });

    test('build_workflow is not required while the set is a placeholder', () {
      final errors = validateManifest(
        _populatedManifest(
          artifacts: {
            'android/arm64-v8a/libTrustWalletCore.so': {
              'sha256': 'TBD-T1.2',
              'size': 0,
            },
          },
          identity: {
            'symbol': 'wcf_build_info',
            'artifact_set_id': 'TBD-T1.2',
            'upstream_commit': 'TBD-T1.1',
          },
        ),
      );
      expect(errors, isEmpty);
    });

    test('the artifact set id has a fixed shape', () {
      final errors = validateManifest(
        _populatedManifest(
          identity: {
            'symbol': 'wcf_build_info',
            'artifact_set_id': 'set-1',
            'upstream_commit': _commit,
            'build_workflow': _workflow,
          },
        ),
      );
      expect(errors, contains(contains('Invalid identity.artifact_set_id')));
    });

    test('the identity symbol is fixed at wcf_build_info', () {
      final errors = validateManifest(
        _populatedManifest(
          identity: {
            'symbol': 'wallet_core_build_info',
            'artifact_set_id': _setId,
            'upstream_commit': _commit,
            'build_workflow': _workflow,
          },
        ),
      );
      expect(errors, contains(contains('Invalid identity.symbol')));
    });
  });
}
