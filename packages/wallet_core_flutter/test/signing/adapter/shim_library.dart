/// Finding the shim-enabled host library the `shim`-tagged tests load — the
/// macOS host library built with `tools/native_build/build_apple.sh
/// --with-shim` (T1.13, DECISION-1 evaluation).
///
/// The same convention as `../../support/host_library.dart`, with names of its
/// own so that the standard library's variables never select it:
///
/// 1. `WCF_NATIVE_SHIM_LIB`, if set and non-empty. Authoritative: a path that
///    does not exist is not replaced by anything else.
/// 2. [shimLibraryRepoPath] under the repository root.
///
/// When neither exists the tests **skip** — `melos run test` and
/// `melos run test:native` run against the standard library, which has no
/// adapter. `WCF_NATIVE_SHIM_REQUIRED=1` turns absence into a failure, for the
/// runs that exist to exercise the shim: `tools/native_build/
/// run_shim_tests.sh` sets it, so that run cannot pass by skipping.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:wallet_core_flutter_native/wallet_core_flutter_native.dart'
    show ManifestIdentity;

import '../../support/host_library.dart' show repositoryRoot;

/// The shim library's identity: `build_apple.sh --with-shim` at the pinned
/// commit, which names its artifact set `as_<tag>-shim_<nnn>` so that the
/// runtime identity check refuses it wherever the standard library
/// (`hostIdentity`, `as_4.8.0_000`) is expected. Tests that load the shim
/// library pass this explicitly.
const ManifestIdentity shimIdentity = ManifestIdentity(
  artifactSetId: 'as_4.8.0-shim_000',
  upstreamCommit: 'd692ac27749d0c615e17c751b70ab4f0aa75c59b',
);

/// Names the environment variable that overrides the shim library path.
const String shimLibraryPathVariable = 'WCF_NATIVE_SHIM_LIB';

/// Names the environment variable that turns a skip into a failure.
const String shimLibraryRequiredVariable = 'WCF_NATIVE_SHIM_REQUIRED';

/// Where a developer's copy lives, relative to the repository root — beside
/// the standard host library's `third_party/wcf-native/`, never in it.
const String shimLibraryRepoPath =
    'third_party/wcf-native-shim/macos/arm64_x86_64/libTrustWalletCore.dylib';

/// What to tell someone who has not built the shim library.
const String shimLibraryMissingMessage =
    'the shim host library is not present. Build it with '
    '`tools/native_build/build_apple.sh --with-shim --slices '
    'macos-arm64_x86_64 --out-dir <dir containing "shim"> ...` and copy it to '
    '$shimLibraryRepoPath, or set $shimLibraryPathVariable.';

/// The absolute path of the shim library, or `null` when it is not there.
String? findShimLibrary() {
  final override = Platform.environment[shimLibraryPathVariable];
  if (override != null && override.isNotEmpty) {
    final file = File(override);
    return file.existsSync() ? file.absolute.path : null;
  }
  final root = repositoryRoot();
  if (root == null) return null;
  final file = File(
    '${root.path}${Platform.pathSeparator}$shimLibraryRepoPath',
  );
  return file.existsSync() ? file.absolute.path : null;
}

/// `null` when the shim tests can run, or the reason to skip them.
///
/// Throws [StateError] when the library is absent and
/// `$shimLibraryRequiredVariable=1` demands it.
String? shimLibrarySkipReason() {
  if (findShimLibrary() != null) return null;
  if (Platform.environment[shimLibraryRequiredVariable] == '1') {
    throw StateError(
      '$shimLibraryRequiredVariable=1 but $shimLibraryMissingMessage',
    );
  }
  return shimLibraryMissingMessage;
}

/// Opens the shim library. Only called from a test [shimLibrarySkipReason]
/// cleared.
DynamicLibrary openShimLibrary() {
  final path = findShimLibrary();
  if (path == null) throw StateError(shimLibraryMissingMessage);
  return DynamicLibrary.open(path);
}
