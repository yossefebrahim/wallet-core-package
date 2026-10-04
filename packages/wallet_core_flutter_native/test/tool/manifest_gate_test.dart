/// The gate that runs before any socket is opened: what makes a manifest
/// unfetchable, and what a `--dry-run` says about the manifest this package
/// actually ships today.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/manifest.dart';
import 'fake_release.dart';

const String _setId = 'as_4.8.0_001';

FetchManifest _parse(String json) => FetchManifest.parse(json, source: 'fake');

List<GateReason> _blockers(
  String json, {
  List<String>? only,
  bool allowInsecureLoopback = false,
}) {
  final manifest = _parse(json);
  return manifestBlockers(
    manifest,
    selected: only ?? manifest.artifacts.keys,
    allowInsecureLoopback: allowInsecureLoopback,
  );
}

String _fields(List<GateReason> reasons) =>
    reasons.map((r) => r.field).join(', ');

void main() {
  final artifact = FakeArtifact.generated('android/arm64-v8a/lib.so');
  final other = FakeArtifact.generated('ios/Frame.zip', seed: 2);

  String good({
    String primary =
        'https://example.invalid/releases/download/native-4.8.0-001',
    String? mirror,
    bool includeMirrorKey = true,
    Map<String, Object?> Function(FakeArtifact)? overrideRecord,
  }) => fakeManifestJson(
    setId: _setId,
    upstreamTag: '4.8.0',
    primary: primary,
    mirror: mirror,
    includeMirrorKey: includeMirrorKey,
    artifacts: [artifact, other],
    overrideRecord: overrideRecord,
  );

  group('parse', () {
    test('reads the fields a fetch needs', () {
      final manifest = _parse(good(mirror: 'https://bucket.invalid/wcf'));
      expect(manifest.upstreamTag, '4.8.0');
      expect(manifest.artifactSetId, _setId);
      expect(
        manifest.retentionPrimary,
        'https://example.invalid/releases/download/native-4.8.0-001',
      );
      expect(manifest.retentionMirror, 'https://bucket.invalid/wcf');
      expect(manifest.mirrorKeyPresent, isTrue);
      expect(manifest.artifacts.keys, [
        artifact.logicalName,
        other.logicalName,
      ]);
      expect(
        manifest.artifacts[artifact.logicalName]!.sha256,
        artifact.sha256Hex,
      );
      expect(manifest.artifacts[artifact.logicalName]!.size, artifact.size);
    });

    test('records a null mirror as null, not as an absent key', () {
      final manifest = _parse(good());
      expect(manifest.retentionMirror, isNull);
      expect(manifest.mirrorKeyPresent, isTrue);
    });

    test('an ill-typed record becomes empty rather than an exception', () {
      final manifest = _parse(
        good(overrideRecord: (_) => <String, Object?>{'sha256': 42}),
      );
      expect(manifest.artifacts[artifact.logicalName]!.sha256, isNull);
    });

    test('refuses text that is not a manifest at all', () {
      expect(() => _parse('not json'), throwsA(isA<FormatException>()));
      expect(() => _parse('[]'), throwsA(isA<FormatException>()));
      expect(() => _parse('{}'), throwsA(isA<FormatException>()));
    });
  });

  group('a complete manifest', () {
    test('has no blockers', () {
      expect(_blockers(good()), isEmpty);
    });

    test('still has none with a mirror', () {
      expect(_blockers(good(mirror: 'https://bucket.invalid/wcf')), isEmpty);
    });
  });

  group('manifest-wide blockers', () {
    test('a placeholder primary names the field and the task', () {
      final reasons = _blockers(good(primary: 'TBD-T0.11'));
      expect(reasons, hasLength(1));
      expect(reasons.single.field, 'retention.primary');
      expect(reasons.single.fixedBy, 'T0.11');
      expect(reasons.single.toString(), contains('TBD-T0.11'));
    });

    test('a non-https primary is refused', () {
      final reasons = _blockers(good(primary: 'http://example.invalid/r'));
      expect(_fields(reasons), 'retention.primary');
      expect(reasons.single.reason, contains('https'));
    });

    test('an ftp primary is refused by scheme', () {
      final reasons = _blockers(good(primary: 'ftp://example.invalid/r'));
      expect(reasons.single.reason, contains('is not https'));
    });

    test('--allow-insecure-loopback permits http to 127.0.0.1 only', () {
      expect(
        _blockers(
          good(primary: 'http://127.0.0.1:8080/releases'),
          allowInsecureLoopback: true,
        ),
        isEmpty,
      );
      expect(
        _blockers(
          good(primary: 'http://localhost:8080/releases'),
          allowInsecureLoopback: true,
        ),
        isEmpty,
      );
      final routable = _blockers(
        good(primary: 'http://evil.invalid/releases'),
        allowInsecureLoopback: true,
      );
      expect(_fields(routable), 'retention.primary');
      expect(routable.single.reason, contains('not a loopback host'));
    });

    test('a missing mirror key is a blocker; an explicit null is not', () {
      expect(
        _fields(_blockers(good(includeMirrorKey: false))),
        'retention.mirror',
      );
      expect(_blockers(good()), isEmpty);
    });

    test('a non-https mirror is refused', () {
      final reasons = _blockers(good(mirror: 'http://bucket.invalid/wcf'));
      expect(_fields(reasons), 'retention.mirror');
    });

    test('a placeholder artifact set id names T1.2', () {
      final json = jsonDecode(good()) as Map<String, Object?>;
      (json['identity']! as Map<String, Object?>)['artifact_set_id'] =
          'TBD-T1.2';
      final reasons = _blockers(jsonEncode(json));
      // The set id itself, plus the two asset names that no longer agree with
      // it — three statements about the same inconsistency, each actionable.
      expect(reasons.first.field, 'identity.artifact_set_id');
      expect(reasons.first.fixedBy, 'T1.2');
    });
  });

  group('per-artifact blockers', () {
    Map<String, Object?> record(FakeArtifact a) => <String, Object?>{
      'sha256': a.sha256Hex,
      'size': a.size,
      'asset_name': a.assetName(_setId),
      'logical_name': a.logicalName,
    };

    List<GateReason> withRecord(
      Map<String, Object?> Function(FakeArtifact) build,
    ) => _blockers(good(overrideRecord: build), only: [artifact.logicalName]);

    test('a placeholder digest', () {
      final reasons = withRecord((a) => record(a)..['sha256'] = 'TBD-T1.2');
      expect(
        reasons.map((r) => r.field),
        contains('artifacts["${artifact.logicalName}"].sha256'),
      );
      expect(reasons.first.fixedBy, 'T1.2');
    });

    test('a digest that is not 64 lowercase hex', () {
      final reasons = withRecord((a) => record(a)..['sha256'] = 'abc');
      expect(reasons.first.reason, contains('not 64 lowercase hex characters'));
    });

    test('a zero size', () {
      final reasons = withRecord((a) => record(a)..['size'] = 0);
      expect(_fields(reasons), 'artifacts["${artifact.logicalName}"].size');
    });

    test('a missing asset_name', () {
      final reasons = withRecord((a) => record(a)..remove('asset_name'));
      expect(
        _fields(reasons),
        'artifacts["${artifact.logicalName}"].asset_name',
      );
      expect(reasons.single.fixedBy, 'T1.2');
    });

    test('a missing logical_name', () {
      final reasons = withRecord((a) => record(a)..remove('logical_name'));
      expect(
        _fields(reasons),
        'artifacts["${artifact.logicalName}"].logical_name',
      );
    });

    test('a logical_name that is not the map key', () {
      final reasons = withRecord(
        (a) => record(a)..['logical_name'] = 'android/other.so',
      );
      expect(reasons.single.reason, contains('but the map key is'));
    });

    test('an asset_name carrying another digest', () {
      final reasons = withRecord(
        (a) =>
            record(a)..['asset_name'] = '${_setId}__${'b' * 64}__${a.flatName}',
      );
      expect(reasons.single.reason, contains('carries digest ${'b' * 64}'));
    });

    test('an asset_name carrying another set id', () {
      final reasons = withRecord(
        (a) =>
            record(a)
              ..['asset_name'] = 'as_4.8.0_002__${a.sha256Hex}__${a.flatName}',
      );
      expect(reasons.single.reason, contains('carries set id as_4.8.0_002'));
    });

    test('an asset_name whose flat name is not the logical name flattened', () {
      final reasons = withRecord(
        (a) =>
            record(a)..['asset_name'] = '${_setId}__${a.sha256Hex}__wrong.so',
      );
      expect(reasons.single.reason, contains('carries flat name wrong.so'));
    });

    test('an asset_name with a 12-hex prefix instead of the digest', () {
      final reasons = withRecord(
        (a) => record(a)
          ..['asset_name'] =
              '${_setId}__${a.sha256Hex.substring(0, 12)}__${a.flatName}',
      );
      expect(reasons.single.reason, contains('64 lowercase hex characters'));
    });

    test('an asset_name over the 255-character GitHub limit', () {
      final reasons = withRecord(
        (a) =>
            record(a)
              ..['asset_name'] = '${_setId}__${a.sha256Hex}__${'x' * 250}',
      );
      expect(reasons.first.reason, contains('over the 255-character'));
    });

    test('--only scopes the artifact checks', () {
      final json = jsonDecode(good()) as Map<String, Object?>;
      (json['artifacts']! as Map<String, Object?>)[other.logicalName] =
          <String, Object?>{'sha256': 'TBD-T1.2', 'size': 0};
      expect(
        _blockers(jsonEncode(json), only: [artifact.logicalName]),
        isEmpty,
      );
      expect(
        _blockers(jsonEncode(json), only: [other.logicalName]),
        isNotEmpty,
      );
    });

    test('an artifact that is not in the manifest', () {
      final reasons = _blockers(good(), only: ['nope/at-all.so']);
      expect(reasons.single.reason, contains('not in the manifest'));
    });
  });

  group('insecureUrlReason', () {
    test('accepts https anywhere', () {
      expect(
        insecureUrlReason(
          'https://github.com/o/r/releases/download/t/a',
          allowInsecureLoopback: false,
        ),
        isNull,
      );
    });

    test('refuses a relative or schemeless string', () {
      expect(
        insecureUrlReason('/releases/download', allowInsecureLoopback: true),
        contains('absolute URL'),
      );
    });

    test('refuses file: even under the loopback override', () {
      expect(
        insecureUrlReason('file:///etc/passwd', allowInsecureLoopback: true),
        isNotNull,
      );
    });

    test('knows the three loopback hosts and nothing else', () {
      expect(isLoopbackHost('127.0.0.1'), isTrue);
      expect(isLoopbackHost('::1'), isTrue);
      expect(isLoopbackHost('localhost'), isTrue);
      expect(isLoopbackHost('127.0.0.2'), isFalse);
      expect(isLoopbackHost('localhost.evil.invalid'), isFalse);
    });
  });

  group('the placeholder manifest', () {
    late FetchManifest manifest;

    setUpAll(() {
      final file = File(
        '${Directory.current.path}/test/fixtures/compat_manifest.placeholder.json',
      );
      expect(
        file.existsSync(),
        isTrue,
        reason: 'run from the package directory, as `flutter test` does',
      );
      manifest = FetchManifest.parse(
        file.readAsStringSync(),
        source: file.path,
      );
    });

    test('is blocked, and says which task fills each field', () {
      final reasons = manifestBlockers(
        manifest,
        selected: manifest.artifacts.keys,
      );
      final fields = reasons.map((r) => r.field).toList();
      expect(fields, contains('retention.primary'));
      expect(fields, contains('identity.artifact_set_id'));
      for (final key in manifest.artifacts.keys) {
        expect(fields, contains('artifacts["$key"].sha256'));
        expect(fields, contains('artifacts["$key"].size'));
        expect(fields, contains('artifacts["$key"].asset_name'));
        expect(fields, contains('artifacts["$key"].logical_name'));
      }
      expect(
        reasons.map((r) => r.fixedBy).toSet(),
        containsAll(<String>['T0.11', 'T1.2']),
      );
    });

    test('records a null mirror rather than dropping the key', () {
      expect(manifest.retentionMirror, isNull);
      expect(manifest.mirrorKeyPresent, isTrue);
    });

    test('carries the pinned upstream tag the cache path is named for', () {
      expect(manifest.upstreamTag, '4.8.0');
    });

    test('does not hard-code which artifacts exist — D0 finding F14', () {
      expect(manifest.artifacts, isNotEmpty);
      for (final key in manifest.artifacts.keys) {
        expect(key, matches(RegExp(r'^[A-Za-z0-9._+/-]+$')));
      }
    });
  });
}
