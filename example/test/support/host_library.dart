/// Finding the real host native library the `native`-tagged test loads.
///
/// The SDK package's convention (`packages/wallet_core_flutter/test/support/
/// host_library.dart`), and the same resolution order, exactly:
///
/// 1. `WCF_NATIVE_LIB`, if set and non-empty. It is **authoritative**: when it
///    names a file that does not exist, nothing else is tried.
/// 2. [hostLibraryRepoPath] under the repository root, the git-ignored copy a
///    developer keeps in the checkout.
///
/// When neither exists the test **skips**, so `flutter test` stays green on a
/// machine that has never built the library. When `WCF_NATIVE_REQUIRED=1` is
/// set, absence is a **failure** instead.
library;

import 'dart:io';

/// Names the environment variable that overrides the library path.
const String hostLibraryPathVariable = 'WCF_NATIVE_LIB';

/// Names the environment variable that turns a skip into a failure.
const String hostLibraryRequiredVariable = 'WCF_NATIVE_REQUIRED';

/// Where a developer's copy lives, relative to the repository root.
const String hostLibraryRepoPath =
    'third_party/wcf-native/macos/arm64_x86_64/libTrustWalletCore.dylib';

/// What to tell someone who has not built the library yet.
const String hostLibraryMissingMessage =
    'the host native library is not present. Build it with '
    '`melos run native:host-lib`, or set $hostLibraryPathVariable to a '
    'libTrustWalletCore built from the pinned upstream commit.';

/// The absolute path of the host library, or `null` when it is not there.
String? findHostLibrary() {
  final override = Platform.environment[hostLibraryPathVariable];
  if (override != null && override.isNotEmpty) {
    final file = File(override);
    return file.existsSync() ? file.absolute.path : null;
  }
  final root = repositoryRoot();
  if (root == null) return null;
  final file = File(
    '${root.path}${Platform.pathSeparator}$hostLibraryRepoPath',
  );
  return file.existsSync() ? file.absolute.path : null;
}

/// `null` when the native test can run, or the reason to skip it.
///
/// Throws [StateError] when the library is absent and
/// `$hostLibraryRequiredVariable=1` demands it be present.
String? hostLibrarySkipReason() {
  if (findHostLibrary() != null) return null;
  if (Platform.environment[hostLibraryRequiredVariable] == '1') {
    throw StateError(
      '$hostLibraryRequiredVariable=1 but $hostLibraryMissingMessage',
    );
  }
  return hostLibraryMissingMessage;
}

/// Walks up from the current directory to the repository root, recognised by
/// the two files only the root has.
Directory? repositoryRoot() {
  var directory = Directory.current.absolute;
  while (true) {
    final marker = File('${directory.path}${Platform.pathSeparator}AGENTS.md');
    final manifest = File(
      '${directory.path}${Platform.pathSeparator}compat_manifest.json',
    );
    if (marker.existsSync() && manifest.existsSync()) return directory;
    final parent = directory.parent;
    if (parent.path == directory.path) return null;
    directory = parent;
  }
}
