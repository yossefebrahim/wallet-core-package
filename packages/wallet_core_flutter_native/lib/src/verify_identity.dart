/// DECISION-14 §2.3's four comparisons.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// | # | Compare | This library |
/// |---|---|---|
/// | 1 | the three packages' embedded `releaseSetId` constants | [verifyReleaseSet] |
/// | 2 | the embedded manifest hash against the shipped copy | [verifyManifestHash] |
/// | 3 | `wcf_build_info().artifact_set_id` against the manifest | [verifyIdentity] |
/// | 4 | `wcf_build_info().upstream_commit` against the manifest | [verifyIdentity] |
///
/// All four are synchronous and free of Flutter, because they run in the worker
/// isolate during `Init`, before `initialize()` returns (DECISION-12 §5).
///
/// **Comparisons 1 and 2 need constants this package cannot supply alone.**
/// The release-set id exists in `wallet_core_flutter` and
/// `wallet_core_flutter_bindings` only from T3.11 (DECISION-14 §4.1), and the
/// manifest bytes have to be read by whoever can reach the shipped asset. So
/// these two are pure functions over values a caller passes in; T1.11 calls
/// them with what it has, and passes three real ids once T3.11 has generated
/// them.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'build_identity.dart';
import 'errors.dart';
import 'generated/manifest.dart'
    show identityArtifactSetId, identityUpstreamCommit, manifestSha256;

/// The prefix a manifest field carries while the task that fills it has not
/// run yet — `TBD-T1.2`, `TBD-T3.11`.
///
/// A value with this prefix means **unknown**, and unknown never compares
/// equal to anything, including an identical placeholder. Accepting one would
/// make every check pass vacuously for exactly as long as the manifest is
/// incomplete, which is the window in which a wrong artifact is most likely.
const String placeholderPrefix = 'TBD-';

/// Whether [value] is an unfilled manifest placeholder.
bool isPlaceholder(String value) => value.startsWith(placeholderPrefix);

/// The manifest's `identity` block: the expected side of comparisons 3 and 4.
final class ManifestIdentity {
  const ManifestIdentity({
    required this.artifactSetId,
    required this.upstreamCommit,
  });

  /// Manifest `identity.artifact_set_id`.
  final String artifactSetId;

  /// Manifest `identity.upstream_commit`.
  final String upstreamCommit;

  /// The values generated from `compat_manifest.json` into this package
  /// (`melos run gen:manifest`). The default expectation of [verifyIdentity].
  static const ManifestIdentity embedded = ManifestIdentity(
    artifactSetId: identityArtifactSetId,
    upstreamCommit: identityUpstreamCommit,
  );

  @override
  String toString() =>
      'ManifestIdentity(artifactSetId: $artifactSetId, '
      'upstreamCommit: $upstreamCommit)';
}

/// Comparisons 3 and 4: reads the identity out of [library] and checks it
/// against [expected].
///
/// Returns the identity it read, so a caller that wants to log or report it
/// does not read the symbol twice.
///
/// Throws [NativeLoadError] when the identity symbol is absent or its value is
/// not the identity JSON (see [BuildIdentity.read]) — that is a library which
/// is not ours, not a library which is the wrong one. Throws
/// [ManifestMismatchError] with [ManifestCheck.artifactSetMismatch] or
/// [ManifestCheck.upstreamCommitMismatch] when it is ours but does not belong
/// to this package set.
///
/// [expected] defaults to [ManifestIdentity.embedded]; tests and the
/// packaging evaluations inject their own.
BuildIdentity verifyIdentity(
  DynamicLibrary library, {
  ManifestIdentity expected = ManifestIdentity.embedded,
  String? symbol,
}) {
  final identity = symbol == null
      ? BuildIdentity.read(library)
      : BuildIdentity.read(library, symbol: symbol);
  verifyIdentityValues(identity, expected: expected);
  return identity;
}

/// Comparisons 3 and 4 over an already-read identity.
///
/// The pure half of [verifyIdentity]: every comparison rule is testable
/// without a library, and the packaging evaluations can check an identity they
/// obtained some other way.
void verifyIdentityValues(
  BuildIdentity actual, {
  ManifestIdentity expected = ManifestIdentity.embedded,
}) {
  // Comparison 3 first, because the artifact-set id is the finer statement:
  // two sets can share an upstream commit, so a set-id mismatch is the more
  // informative failure when both differ.
  _compare(
    check: ManifestCheck.artifactSetMismatch,
    expected: expected.artifactSetId,
    actual: actual.artifactSetId,
    placeholderDetail:
        'the manifest has no artifact set yet, so no library can match it',
  );
  _compare(
    check: ManifestCheck.upstreamCommitMismatch,
    expected: expected.upstreamCommit,
    actual: actual.upstreamCommit,
    placeholderDetail:
        'the manifest records no upstream commit for the artifact set yet',
  );
}

/// Comparison 1: the three packages' embedded release-set ids must agree.
///
/// The three arguments are `wallet_core_flutter`'s, the bindings package's,
/// and this package's `releaseSetId` constants. Only this package's exists
/// today (`releaseSetId` in `lib/src/generated/manifest.dart`); T3.11
/// generates the other two, and until it does, all three are the placeholder
/// `TBD-T3.11`.
///
/// Throws [ManifestCheck.releaseSetMismatch] when they differ, **and also**
/// when any of them is still a placeholder: no release set has been published,
/// so there is nothing for the three packages to agree on and a pass would be
/// vacuous. T1.11 decides when in `Init` to call this; before T3.11 it has no
/// value to pass that this function will accept, which is the honest state of
/// affairs rather than a bug in either task.
void verifyReleaseSet({
  required String sdk,
  required String bindings,
  required String native,
}) {
  final values = <String, String>{
    'wallet_core_flutter': sdk,
    'wallet_core_flutter_bindings': bindings,
    'wallet_core_flutter_native': native,
  };
  for (final entry in values.entries) {
    if (isPlaceholder(entry.value)) {
      throw ManifestMismatchError(
        check: ManifestCheck.releaseSetMismatch,
        expected: 'an allocated release-set id (rs_<tag>_<nnn>)',
        actual: entry.value,
        detail:
            '${entry.key} still carries the placeholder; no release set has '
            'been published (DECISION-14 §4.1, T3.11)',
      );
    }
  }
  for (final entry in values.entries) {
    if (entry.value != native) {
      throw ManifestMismatchError(
        check: ManifestCheck.releaseSetMismatch,
        expected: native,
        actual: entry.value,
        detail:
            '${entry.key} disagrees with wallet_core_flutter_native; the '
            'resolved package set is mixed',
      );
    }
  }
}

/// Comparison 2: the shipped manifest must hash to the embedded digest.
///
/// [manifestBytes] are the bytes of the manifest copy shipped in this package
/// (`assets/compat_manifest.json`), read by whoever can reach it — the asset
/// bundle in an app, the package directory in a CLI. [expected] defaults to
/// this package's generated [manifestSha256].
///
/// The digest is over the **file's bytes**, not over a re-serialisation of its
/// JSON: the generator hashes the committed file and this hashes the copy of
/// it, so the comparison is a statement about the file rather than about two
/// encoders agreeing. T3.11's embedded copies in the other two packages use
/// the same definition.
///
/// Returns the digest it computed.
String verifyManifestHash(
  Uint8List manifestBytes, {
  String expected = manifestSha256,
}) {
  final actual = sha256.convert(manifestBytes).toString();
  _compare(
    check: ManifestCheck.manifestHashMismatch,
    expected: expected,
    actual: actual,
    placeholderDetail: 'no manifest digest has been embedded',
  );
  return actual;
}

/// Comparison 2 for a caller holding the manifest as text.
///
/// Encodes to UTF-8 and defers to [verifyManifestHash]. Convenience only —
/// the bytes are what is hashed either way, and a caller who has bytes should
/// pass bytes rather than decode and re-encode them.
String verifyManifestHashOfString(
  String manifestText, {
  String expected = manifestSha256,
}) => verifyManifestHash(
  Uint8List.fromList(utf8.encode(manifestText)),
  expected: expected,
);

void _compare({
  required ManifestCheck check,
  required String expected,
  required String actual,
  required String placeholderDetail,
}) {
  if (isPlaceholder(expected)) {
    throw ManifestMismatchError(
      check: check,
      expected: expected,
      actual: actual,
      detail:
          '"$expected" is an unfilled manifest placeholder: '
          '$placeholderDetail',
    );
  }
  if (expected != actual) {
    throw ManifestMismatchError(
      check: check,
      expected: expected,
      actual: actual,
    );
  }
}
