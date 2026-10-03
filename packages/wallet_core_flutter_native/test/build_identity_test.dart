import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter_native/wallet_core_flutter_native.dart';

/// A well-formed identity string, shaped exactly like `wcf_build_info.h`'s
/// contract comment: three keys, a 40-hex commit, a workflow URL.
const String _valid =
    '{"upstream_commit":"d692ac27749d0c615e17c751b70ab4f0aa75c59b",'
    '"artifact_set_id":"as_4.8.0_001",'
    '"build_workflow":"https://github.com/o/r/actions/runs/1"}';

Matcher _loadErrorSaying(Pattern message) => isA<NativeLoadError>().having(
  (e) => e.message,
  'message',
  contains(message),
);

void main() {
  group('BuildIdentity.parse accepts', () {
    test('the three keys of DECISION-14 §2.1', () {
      final identity = BuildIdentity.parse(_valid);
      expect(
        identity.upstreamCommit,
        'd692ac27749d0c615e17c751b70ab4f0aa75c59b',
      );
      expect(identity.artifactSetId, 'as_4.8.0_001');
      expect(identity.buildWorkflow, 'https://github.com/o/r/actions/runs/1');
    });

    test('an unknown key, ignoring it', () {
      // DECISION-14 §2.1: the format may gain a field without breaking an
      // older loader.
      final identity = BuildIdentity.parse(
        '{"upstream_commit":"d692ac27749d0c615e17c751b70ab4f0aa75c59b",'
        '"artifact_set_id":"as_4.8.0_001","build_workflow":"local",'
        '"sbom":"sbom/as_4.8.0_001.cdx.json","future_field":42}',
      );
      expect(identity.artifactSetId, 'as_4.8.0_001');
      expect(identity.buildWorkflow, 'local');
    });

    test('an artifact-set id it does not recognise', () {
      // The loader does not enforce the id's shape: a naming change upstream
      // of it must not become a load failure on every device.
      expect(
        BuildIdentity.parse(
          '{"upstream_commit":"d692ac27749d0c615e17c751b70ab4f0aa75c59b",'
          '"artifact_set_id":"whatever-the-workflow-allocated",'
          '"build_workflow":"local"}',
        ).artifactSetId,
        'whatever-the-workflow-allocated',
      );
    });
  });

  group('BuildIdentity.parse rejects with NativeLoadError', () {
    test('malformed JSON', () {
      expect(
        () => BuildIdentity.parse('{"upstream_commit":'),
        throwsA(_loadErrorSaying('did not return JSON')),
      );
      expect(
        () => BuildIdentity.parse('not json at all'),
        throwsA(_loadErrorSaying('did not return JSON')),
      );
    });

    test('an empty string', () {
      expect(
        () => BuildIdentity.parse(''),
        throwsA(_loadErrorSaying('did not return JSON')),
      );
    });

    test('JSON that is not an object', () {
      expect(
        () => BuildIdentity.parse('["as_4.8.0_001"]'),
        throwsA(_loadErrorSaying('must return a JSON object')),
      );
      expect(
        () => BuildIdentity.parse('null'),
        throwsA(_loadErrorSaying('must return a JSON object')),
      );
    });

    test('a missing key, naming the key', () {
      for (final key in const [
        'upstream_commit',
        'artifact_set_id',
        'build_workflow',
      ]) {
        final without = <String, String>{
          'upstream_commit': 'd692ac27749d0c615e17c751b70ab4f0aa75c59b',
          'artifact_set_id': 'as_4.8.0_001',
          'build_workflow': 'local',
        }..remove(key);
        expect(
          () => BuildIdentity.parse(
            '{${without.entries.map((e) => '"${e.key}":"${e.value}"').join(',')}}',
          ),
          throwsA(_loadErrorSaying('returned no "$key" key')),
          reason: 'a missing $key must be a load failure',
        );
      }
    });

    test('a key that is not a non-empty string', () {
      expect(
        () => BuildIdentity.parse(
          '{"upstream_commit":"d692ac27749d0c615e17c751b70ab4f0aa75c59b",'
          '"artifact_set_id":"","build_workflow":"local"}',
        ),
        throwsA(_loadErrorSaying('not a non-empty string')),
      );
      expect(
        () => BuildIdentity.parse(
          '{"upstream_commit":"d692ac27749d0c615e17c751b70ab4f0aa75c59b",'
          '"artifact_set_id":7,"build_workflow":"local"}',
        ),
        throwsA(_loadErrorSaying('not a non-empty string')),
      );
    });

    test('a commit that is not 40 lowercase hex', () {
      for (final commit in const <String>[
        'D692AC27749D0C615E17C751B70AB4F0AA75C59B', // uppercase
        'd692ac27749d0c615e17c751b70ab4f0aa75c59', // 39 digits
        'd692ac27749d0c615e17c751b70ab4f0aa75c59bb', // 41 digits
        'main',
        'd692ac27749d0c615e17c751b70ab4f0aa75c59z', // non-hex digit
      ]) {
        expect(
          () => BuildIdentity.parse(
            '{"upstream_commit":"$commit","artifact_set_id":"as_4.8.0_001",'
            '"build_workflow":"local"}',
          ),
          throwsA(_loadErrorSaying('not 40 lowercase hex')),
          reason: '"$commit" must not be accepted as a commit',
        );
      }
    });
  });

  test('a broken identity is a load error, never a mismatch', () {
    // DECISION-14 §2.3: an artifact whose identity cannot be read is not one
    // of ours at all, which is a different fact from being the wrong one.
    expect(() => BuildIdentity.parse('{}'), throwsA(isA<NativeLoadError>()));
    expect(
      () => BuildIdentity.parse('{}'),
      throwsA(isNot(isA<ManifestMismatchError>())),
    );
  });

  test('toString names the set and the commit, not the file', () {
    final text = BuildIdentity.parse(_valid).toString();
    expect(text, contains('as_4.8.0_001'));
    expect(text, contains('d692ac27749d0c615e17c751b70ab4f0aa75c59b'));
  });
}
