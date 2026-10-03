/// The one place errors from the packages below the SDK become members of the
/// sealed [WalletCoreException] hierarchy. **Internal**: never exported.
///
/// The bindings package's `DisposedError` and the native package's
/// `NativeLoadError` and `ManifestMismatchError` are `final class … extends
/// Error` in libraries the SDK depends on, so they cannot join a hierarchy
/// sealed in this package. They are converted here, at the boundary, with every
/// field they carry preserved, so that nothing of theirs escapes the default
/// public surface (`docs/architecture/lifecycle.md` §3).
library;

import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart'
    as bindings
    show DisposedError;
import 'package:wallet_core_flutter_native/wallet_core_flutter_native.dart'
    as native
    show ManifestMismatchError, NativeLoadError;

import 'errors.dart';

/// Converts [error] into the SDK's public type, or returns `null` when it is
/// not one of the boundary errors this SDK knows.
///
/// * A [WalletCoreException] is returned unchanged.
/// * The bindings' `DisposedError` becomes [DisposedError], keeping
///   `resourceType`.
/// * The native package's `NativeLoadError` becomes [NativeLoadError], keeping
///   the message, every attempted location with its failure, and the cause.
/// * The native package's `ManifestMismatchError` becomes
///   [ManifestMismatchError], keeping `check`, `expected`, `actual`, and
///   `detail`.
///
/// Anything else — a `RangeError`, a `StateError` — is a defect or a corrupt
/// native result rather than a condition this hierarchy names, and the caller
/// decides what to do with it; `null` says so without guessing.
WalletCoreException? toWalletCoreException(Object error) => switch (error) {
  WalletCoreException() => error,
  bindings.DisposedError(:final resourceType) => DisposedError(resourceType),
  native.NativeLoadError() => NativeLoadError(
    error.message,
    attempts: [
      for (final attempt in error.attempts)
        NativeLoadAttempt(
          location: attempt.location,
          reason: attempt.error.toString(),
        ),
    ],
    cause: error.cause,
  ),
  native.ManifestMismatchError() => ManifestMismatchError(
    check: error.check,
    expected: error.expected,
    actual: error.actual,
    detail: error.detail,
  ),
  _ => null,
};
