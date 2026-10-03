import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter_native/wallet_core_flutter_native.dart';

const String _commit = 'd692ac27749d0c615e17c751b70ab4f0aa75c59b';
const String _otherCommit = '0000000000000000000000000000000000000000';

const ManifestIdentity _expected = ManifestIdentity(
  artifactSetId: 'as_4.8.0_001',
  upstreamCommit: _commit,
);

BuildIdentity _identity({
  String artifactSetId = 'as_4.8.0_001',
  String upstreamCommit = _commit,
}) => BuildIdentity(
  artifactSetId: artifactSetId,
  upstreamCommit: upstreamCommit,
  buildWorkflow: 'local',
);

Matcher _mismatch(ManifestCheck check) =>
    isA<ManifestMismatchError>().having((e) => e.check, 'check', check);

void main() {
  group('comparison 3 — artifact set', () {
    test('passes when the ids agree', () {
      expect(
        () => verifyIdentityValues(_identity(), expected: _expected),
        returnsNormally,
      );
    });

    test('fails with artifactSetMismatch, naming both values', () {
      final error = _throwsMismatch(
        () => verifyIdentityValues(
          _identity(artifactSetId: 'as_4.8.0_002'),
          expected: _expected,
        ),
      );
      expect(error.check, ManifestCheck.artifactSetMismatch);
      expect(error.expected, 'as_4.8.0_001');
      expect(error.actual, 'as_4.8.0_002');
      expect(error.message, contains('as_4.8.0_001'));
      expect(error.message, contains('as_4.8.0_002'));
      expect(error.toString(), contains('artifactSetMismatch'));
    });

    test('is reported before comparison 4 when both differ', () {
      // The set id is the finer statement: two sets can share a commit.
      expect(
        () => verifyIdentityValues(
          _identity(
            artifactSetId: 'as_4.8.0_002',
            upstreamCommit: _otherCommit,
          ),
          expected: _expected,
        ),
        throwsA(_mismatch(ManifestCheck.artifactSetMismatch)),
      );
    });
  });

  group('comparison 4 — upstream commit', () {
    test('fails with upstreamCommitMismatch, naming both values', () {
      final error = _throwsMismatch(
        () => verifyIdentityValues(
          _identity(upstreamCommit: _otherCommit),
          expected: _expected,
        ),
      );
      expect(error.check, ManifestCheck.upstreamCommitMismatch);
      expect(error.expected, _commit);
      expect(error.actual, _otherCommit);
      expect(error.message, contains(_otherCommit));
    });
  });

  group('a TBD- placeholder is never a match', () {
    test('not even against an identical placeholder', () {
      // The window in which the manifest is incomplete is the window in which
      // a wrong artifact is most likely; a vacuous pass there is the worst
      // possible default.
      final error = _throwsMismatch(
        () => verifyIdentityValues(
          _identity(artifactSetId: 'TBD-T1.2'),
          expected: const ManifestIdentity(
            artifactSetId: 'TBD-T1.2',
            upstreamCommit: _commit,
          ),
        ),
      );
      expect(error.check, ManifestCheck.artifactSetMismatch);
      expect(error.detail, contains('unfilled manifest placeholder'));
    });

    test('for the artifact set', () {
      expect(
        () => verifyIdentityValues(
          _identity(),
          expected: const ManifestIdentity(
            artifactSetId: 'TBD-T1.2',
            upstreamCommit: _commit,
          ),
        ),
        throwsA(_mismatch(ManifestCheck.artifactSetMismatch)),
      );
    });

    test('for the upstream commit', () {
      expect(
        () => verifyIdentityValues(
          _identity(),
          expected: const ManifestIdentity(
            artifactSetId: 'as_4.8.0_001',
            upstreamCommit: 'TBD-T1.2',
          ),
        ),
        throwsA(_mismatch(ManifestCheck.upstreamCommitMismatch)),
      );
    });

    test('for the manifest digest', () {
      expect(
        () => verifyManifestHash(
          Uint8List.fromList(utf8.encode('{}')),
          expected: 'TBD-T3.11',
        ),
        throwsA(_mismatch(ManifestCheck.manifestHashMismatch)),
      );
    });

    test('and isPlaceholder says which values those are', () {
      expect(isPlaceholder('TBD-T1.2'), isTrue);
      expect(isPlaceholder('TBD-T3.11'), isTrue);
      expect(isPlaceholder('as_4.8.0_001'), isFalse);
      expect(isPlaceholder(placeholderPrefix), isTrue);
    });
  });

  group('comparison 2 — manifest hash', () {
    // sha256("abc"), the published NIST vector, so the digest this package
    // computes is checked against a value from outside this package.
    const String abcDigest =
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

    test('passes and returns the digest it computed', () {
      final bytes = Uint8List.fromList(utf8.encode('abc'));
      expect(verifyManifestHash(bytes, expected: abcDigest), abcDigest);
    });

    test('fails with manifestHashMismatch on one changed byte', () {
      final error = _throwsMismatch(
        () => verifyManifestHash(
          Uint8List.fromList(utf8.encode('abd')),
          expected: abcDigest,
        ),
      );
      expect(error.check, ManifestCheck.manifestHashMismatch);
      expect(error.expected, abcDigest);
      expect(error.actual, isNot(abcDigest));
      expect(error.actual, hasLength(64));
    });

    test('hashes bytes, so the string form agrees with the byte form', () {
      expect(verifyManifestHashOfString('abc', expected: abcDigest), abcDigest);
    });

    test('never puts the hashed content in the message', () {
      final error = _throwsMismatch(
        () => verifyManifestHashOfString(
          '{"secret_looking":"content"}',
          expected: abcDigest,
        ),
      );
      expect(error.message, isNot(contains('secret_looking')));
    });
  });

  group('comparison 1 — release set', () {
    test('passes when all three agree on an allocated id', () {
      expect(
        () => verifyReleaseSet(
          sdk: 'rs_4.8.0_001',
          bindings: 'rs_4.8.0_001',
          native: 'rs_4.8.0_001',
        ),
        returnsNormally,
      );
    });

    test('fails with releaseSetMismatch, naming the odd package', () {
      final error = _throwsMismatch(
        () => verifyReleaseSet(
          sdk: 'rs_4.8.0_002',
          bindings: 'rs_4.8.0_001',
          native: 'rs_4.8.0_001',
        ),
      );
      expect(error.check, ManifestCheck.releaseSetMismatch);
      expect(error.detail, contains('wallet_core_flutter'));
      expect(error.actual, 'rs_4.8.0_002');
      expect(error.expected, 'rs_4.8.0_001');
    });

    test('fails when the bindings package is the odd one', () {
      final error = _throwsMismatch(
        () => verifyReleaseSet(
          sdk: 'rs_4.8.0_001',
          bindings: 'rs_4.8.0_003',
          native: 'rs_4.8.0_001',
        ),
      );
      expect(error.detail, contains('wallet_core_flutter_bindings'));
    });

    test('fails while any package still carries the placeholder', () {
      // Today all three do: T3.11 allocates the id (DECISION-14 §4.1). The
      // three placeholders are equal, and equal placeholders are still not a
      // release set, so this is a mismatch rather than a pass.
      final error = _throwsMismatch(
        () => verifyReleaseSet(
          sdk: 'TBD-T3.11',
          bindings: 'TBD-T3.11',
          native: 'TBD-T3.11',
        ),
      );
      expect(error.check, ManifestCheck.releaseSetMismatch);
      expect(error.detail, contains('T3.11'));
    });

    test(
      'this package carries the placeholder until T3.11 runs',
      () {
        // A statement about the generated constant, not about the code: when it
        // stops being a placeholder, T3.11 has landed and the other two
        // packages must have gained theirs.
        expect(isPlaceholder(releaseSetId), isTrue);
        expect(releaseSetId, 'TBD-T3.11');
      },
      skip: isPlaceholder(releaseSetId)
          ? null
          : 'release_set has been allocated ($releaseSetId); T3.11 has landed '
                'and the other two packages must now carry the same constant.',
    );
  });

  test('the four ManifestCheck values each have a failing case', () {
    // Guards against a fifth comparison arriving without a test.
    expect(ManifestCheck.values, hasLength(4));
    final produced = <ManifestCheck>{};
    void record(void Function() body) {
      try {
        body();
      } on ManifestMismatchError catch (e) {
        produced.add(e.check);
      }
    }

    record(() => verifyReleaseSet(sdk: 'a', bindings: 'b', native: 'c'));
    record(() => verifyManifestHashOfString('x', expected: 'a' * 64));
    record(
      () => verifyIdentityValues(
        _identity(artifactSetId: 'other'),
        expected: _expected,
      ),
    );
    record(
      () => verifyIdentityValues(
        _identity(upstreamCommit: _otherCommit),
        expected: _expected,
      ),
    );
    expect(produced, ManifestCheck.values.toSet());
  });

  test('embedded expectations come from the generated manifest', () {
    expect(ManifestIdentity.embedded.artifactSetId, identityArtifactSetId);
    expect(ManifestIdentity.embedded.upstreamCommit, identityUpstreamCommit);
    expect(identitySymbol, 'wcf_build_info');
    expect(upstreamRepo, 'trustwallet/wallet-core');
    expect(upstreamTag, '4.8.0');
    expect(upstreamCommit, _commit);
    expect(manifestSha256, matches(RegExp(r'^[0-9a-f]{64}$')));
  });
}

ManifestMismatchError _throwsMismatch(void Function() body) {
  try {
    body();
  } on ManifestMismatchError catch (e) {
    return e;
  }
  fail('expected a ManifestMismatchError');
}
