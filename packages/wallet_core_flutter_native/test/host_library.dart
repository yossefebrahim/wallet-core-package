/// Finding the real native library for the tests that need one.
///
/// Not a test file. Two lookups, in order:
///
///  1. `WCF_NATIVE_LIB`, which the **test** reads and passes to the loader —
///     never the library code, which must not resolve a path from the
///     environment (threat model TM-13).
///  2. `<repo root>/third_party/wcf-native/macos/arm64_x86_64/libTrustWalletCore.dylib`,
///     where `melos run native:host-lib` puts the relinked host library
///     (DECISION-9 Option C's Apple leg).
///
/// When neither is present the library-backed tests **skip** with a message
/// naming the script that produces one — unless `WCF_NATIVE_REQUIRED=1`, in
/// which case they run and fail, which is what CI sets so that a missing
/// library cannot quietly reduce the suite.
library;

import 'dart:io';

/// Path to the host library, or null when there is none.
final String? hostLibraryPath = _resolveHostLibrary();

/// The repository root — the directory holding `compat_manifest.json` and
/// `packages/`. Null when the package is consumed from pub rather than from a
/// checkout.
final Directory? repoRoot = _findRepoRoot();

/// Whether the suite must fail rather than skip when there is no library.
bool get hostLibraryRequired =>
    Platform.environment['WCF_NATIVE_REQUIRED'] == '1';

/// The `skip` argument for a test that needs the host library: null when it
/// can run, a reason when it cannot.
Object? get hostLibrarySkip {
  if (hostLibraryPath != null) return null;
  if (hostLibraryRequired) return null;
  return 'no host library. Build one with `melos run native:host-lib`, or '
      'point WCF_NATIVE_LIB at an existing artifact. Set '
      'WCF_NATIVE_REQUIRED=1 to fail instead of skipping.';
}

/// The host library's path, or a failure that says how to get one.
String requireHostLibrary() {
  final path = hostLibraryPath;
  if (path != null) return path;
  throw StateError(
    'WCF_NATIVE_REQUIRED=1 but no host library was found. Build one with '
    '`melos run native:host-lib`, or point WCF_NATIVE_LIB at an artifact.',
  );
}

/// The `skip` argument for a test that needs the repository checkout.
Object? get repoRootSkip => repoRoot != null
    ? null
    : 'needs the repository checkout; this package is being tested outside '
          'one, so the root compat_manifest.json is not reachable.';

const String _hostLibraryRelativePath =
    'third_party/wcf-native/macos/arm64_x86_64/libTrustWalletCore.dylib';

String? _resolveHostLibrary() {
  final fromEnv = Platform.environment['WCF_NATIVE_LIB'];
  if (fromEnv != null && fromEnv.isNotEmpty) {
    return File(fromEnv).existsSync() ? fromEnv : null;
  }
  final root = repoRoot;
  if (root == null) return null;
  final cached = File('${root.path}/$_hostLibraryRelativePath');
  return cached.existsSync() ? cached.path : null;
}

Directory? _findRepoRoot() {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 8; i++) {
    if (File('${dir.path}/compat_manifest.json').existsSync() &&
        Directory('${dir.path}/packages').existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}
