/// Typed failures of the native loader and of the build-identity check.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// These two types are the vocabulary `docs/architecture/lifecycle.md` §3 fixes
/// for what `WalletCore.initialize()` surfaces when a session cannot start
/// (DECISION-12 §5: the check runs in the worker isolate during `Init`, and a
/// failure produces `initializing → failed` with no session handed out).
///
/// They extend `Error` rather than lifecycle.md's sketched
/// `WalletCoreException`, because that base belongs to the public SDK package
/// (T1.11) and this package sits below it: `wallet_core_flutter` depends on
/// `wallet_core_flutter_bindings`, which depends on this one, so a base class
/// declared up there cannot be extended down here. T1.11 wraps or re-exposes
/// these as it sees fit.
///
/// **What a message may contain.** Identity values — an artifact-set id, an
/// upstream commit, a symbol name, a library path — are not secrets and appear
/// verbatim, because a mismatch a developer cannot read is a mismatch they
/// cannot fix. The contents of a file never appear.
library;

/// The native library could not be located, loaded, or resolved.
///
/// Also the failure for an artifact whose build identity is absent or broken:
/// a missing `wcf_build_info` symbol, a null or non-JSON identity string, a
/// missing key, or an `upstream_commit` that is not 40 lowercase hex. That is
/// DECISION-14 §2.3's rule and it is deliberate — such an artifact is not one
/// of ours at all, which is a different fact from "ours, but the wrong one",
/// and only the latter is a [ManifestMismatchError].
final class NativeLoadError extends Error {
  NativeLoadError(
    this.message, {
    this.cause,
    List<LibraryLoadAttempt> attempts = const <LibraryLoadAttempt>[],
  }) : attempts = List<LibraryLoadAttempt>.unmodifiable(attempts);

  /// What went wrong, in one sentence.
  final String message;

  /// The underlying error, when there was one — typically the
  /// `ArgumentError` `dart:ffi` throws for a library it cannot open.
  final Object? cause;

  /// Every location the locator tried, in the order it tried them, each with
  /// the error it produced. Empty when the failure was not a load failure
  /// (a missing symbol, say).
  final List<LibraryLoadAttempt> attempts;

  @override
  String toString() {
    final buffer = StringBuffer('NativeLoadError: $message');
    for (final attempt in attempts) {
      buffer.write('\n  tried ${attempt.location}: ${attempt.error}');
    }
    if (cause != null && attempts.isEmpty) buffer.write('\n  cause: $cause');
    return buffer.toString();
  }
}

/// One location the locator tried and the error it got back.
final class LibraryLoadAttempt {
  const LibraryLoadAttempt({required this.location, required this.error});

  /// The location's own description — what was tried, in words a developer
  /// can act on.
  final String location;

  /// Why it did not work.
  final Object error;

  @override
  String toString() => '$location: $error';
}

/// Which of DECISION-14 §2.3's four comparisons failed.
///
/// The names are lifecycle.md §3's, unchanged, so that the enum a consumer
/// switches on is the one the architecture document describes.
enum ManifestCheck {
  /// Comparison 1 — the three packages' embedded `releaseSetId` constants do
  /// not all agree (or none has been allocated yet).
  releaseSetMismatch,

  /// Comparison 2 — the embedded manifest hash does not match the sha256 of
  /// the manifest copy shipped in this package.
  manifestHashMismatch,

  /// Comparison 3 — `wcf_build_info().artifact_set_id` does not match the
  /// manifest's `identity.artifact_set_id`.
  artifactSetMismatch,

  /// Comparison 4 — `wcf_build_info().upstream_commit` does not match the
  /// manifest's `identity.upstream_commit`.
  upstreamCommitMismatch,
}

/// The loaded library, the shipped manifest, and the packages' embedded
/// constants do not agree. [check] names which comparison failed.
///
/// A mismatch means the pieces are each intelligible but do not belong
/// together — a library from another artifact set, a manifest that was edited
/// after the constants were generated, a mixed package set. A piece that is
/// not intelligible at all is a [NativeLoadError].
final class ManifestMismatchError extends Error {
  ManifestMismatchError({
    required this.check,
    required this.expected,
    required this.actual,
    String? detail,
  }) : detail = detail ?? '';

  /// Which comparison failed.
  final ManifestCheck check;

  /// The value the manifest, or the embedded constant, said it should be.
  final String expected;

  /// The value actually found — in the loaded library, in the shipped asset,
  /// or in another package's constant.
  final String actual;

  /// Optional extra context, such as which package carried the odd value.
  final String detail;

  /// A one-line description naming the comparison and both values.
  String get message {
    final buffer = StringBuffer('${_describe(check)}: expected "$expected", ')
      ..write('found "$actual"');
    if (detail.isNotEmpty) buffer.write(' ($detail)');
    return buffer.toString();
  }

  @override
  String toString() => 'ManifestMismatchError(${check.name}): $message';

  static String _describe(ManifestCheck check) => switch (check) {
    ManifestCheck.releaseSetMismatch =>
      'release-set ids disagree across the three packages',
    ManifestCheck.manifestHashMismatch =>
      'the shipped manifest does not hash to the embedded digest',
    ManifestCheck.artifactSetMismatch =>
      'the loaded library belongs to another artifact set',
    ManifestCheck.upstreamCommitMismatch =>
      'the loaded library was built from another upstream commit',
  };
}
