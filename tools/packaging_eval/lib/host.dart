// Finding the repository, the gate scripts, and the system tools each
// measurement shells out to.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.
//
// Nothing here executes anything found under third_party/ or under a cache
// directory: those paths are data that system tools are pointed *at*. The only
// executables this file resolves are Xcode's, the NDK's, the Android
// build-tools', Flutter's, and this repository's own gate scripts.

import 'dart:io';

import 'proc.dart';

/// The workspace root: the nearest ancestor holding the workspace pubspec.
///
/// Resolved from this library's own location, so a command works from any
/// working directory, with a fall back to the current directory for a run out
/// of a copied tree.
Directory repoRoot() {
  final candidates = <Directory>[?_libraryDirectory, Directory.current];
  for (final start in candidates) {
    for (
      var dir = start.absolute;
      dir.path != dir.parent.path;
      dir = dir.parent
    ) {
      final pubspec = File('${dir.path}/pubspec.yaml');
      if (pubspec.existsSync() &&
          pubspec.readAsStringSync().contains(
            'name: wallet_core_flutter_workspace',
          )) {
        return dir;
      }
    }
  }
  throw StateError(
    'could not locate the workspace root (no ancestor pubspec.yaml naming '
    'wallet_core_flutter_workspace)',
  );
}

Directory? get _libraryDirectory {
  // package:wcf_tool_packaging_eval/host.dart -> tools/packaging_eval/lib
  final uri = Platform.script;
  if (uri.scheme == 'file') return File.fromUri(uri).parent;
  return null;
}

/// `tools/native_build/check_exports.sh` and friends. Called, never copied:
/// the packaged library is checked by the same code that checked the built
/// artifact.
String nativeBuildScript(String name) =>
    '${repoRoot().path}/tools/native_build/$name';

/// The canonical symbol inventory (T1.3). Read, never written.
String inventoryJsonPath() =>
    '${repoRoot().path}/packages/wallet_core_flutter_bindings/lib/src/'
    'generated/inventory.json';

/// Locates an Xcode toolchain tool. Returns null when Xcode is absent.
String? xcrunFind(String tool) {
  final result = run('xcrun', ['--find', tool]);
  if (!result.ok) return null;
  final path = result.stdout.trim();
  return path.isEmpty ? null : path;
}

/// The NDK root, from `$ANDROID_NDK`, `$ANDROID_NDK_HOME`, `$ANDROID_NDK_ROOT`
/// or the highest-numbered directory under `$ANDROID_HOME/ndk`.
String? ndkRoot({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  for (final key in const [
    'ANDROID_NDK',
    'ANDROID_NDK_HOME',
    'ANDROID_NDK_ROOT',
  ]) {
    final value = env[key];
    if (value != null && value.isNotEmpty && Directory(value).existsSync()) {
      return value;
    }
  }
  final sdk = env['ANDROID_HOME'] ?? env['ANDROID_SDK_ROOT'];
  final home = env['HOME'];
  final roots = <String>[
    if (sdk != null && sdk.isNotEmpty) '$sdk/ndk',
    if (home != null && home.isNotEmpty) '$home/Library/Android/sdk/ndk',
    if (home != null && home.isNotEmpty) '$home/Android/Sdk/ndk',
  ];
  for (final root in roots) {
    final directory = Directory(root);
    if (!directory.existsSync()) continue;
    final versions = directory.listSync().whereType<Directory>().toList()
      ..sort((a, b) => compareVersionDirectories(a.path, b.path));
    if (versions.isNotEmpty) return versions.last.path;
  }
  return null;
}

/// Orders `21.4.7075529` before `28.2.13676358` numerically, not lexically.
int compareVersionDirectories(String a, String b) {
  List<int> parts(String path) => path
      .split(Platform.pathSeparator)
      .last
      .split('.')
      .map((p) => int.tryParse(p) ?? -1)
      .toList();
  final pa = parts(a);
  final pb = parts(b);
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final c = pa[i].compareTo(pb[i]);
    if (c != 0) return c;
  }
  return pa.length.compareTo(pb.length);
}

String _hostTag() => Platform.isMacOS ? 'darwin-x86_64' : 'linux-x86_64';

/// `llvm-nm`, `llvm-readelf`, `llvm-objdump` … out of the NDK toolchain.
String? ndkLlvmTool(String name, {String? root}) {
  final ndk = root ?? ndkRoot();
  if (ndk == null) return null;
  final path = '$ndk/toolchains/llvm/prebuilt/${_hostTag()}/bin/$name';
  return File(path).existsSync() ? path : null;
}

/// Android ABI name to the NDK's target triple.
const Map<String, String> abiTriples = {
  'arm64-v8a': 'aarch64-linux-android',
  'armeabi-v7a': 'arm-linux-androideabi',
  'x86_64': 'x86_64-linux-android',
  'x86': 'i686-linux-android',
};

/// The NDK's own `libc++_shared.so` for [abi] — the very file the duplicate
/// check is about.
///
/// Two layouts: NDK r27 and earlier keep it under
/// `sources/cxx-stl/llvm-libc++/libs/<abi>/`; r28 removed that tree and the
/// library lives in the sysroot under the target triple. Both are tried.
String? ndkLibcxxShared(String abi, {String? root}) {
  final ndk = root ?? ndkRoot();
  if (ndk == null) return null;
  final triple = abiTriples[abi];
  final candidates = <String>[
    '$ndk/sources/cxx-stl/llvm-libc++/libs/$abi/libc++_shared.so',
    if (triple != null)
      '$ndk/toolchains/llvm/prebuilt/${_hostTag()}/sysroot/usr/lib/$triple/'
          'libc++_shared.so',
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

/// `zipalign` from the highest-numbered installed build-tools.
String? zipalignPath({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final onPath = _which('zipalign');
  if (onPath != null) return onPath;
  final sdk = env['ANDROID_HOME'] ?? env['ANDROID_SDK_ROOT'];
  final home = env['HOME'];
  final roots = <String>[
    if (sdk != null && sdk.isNotEmpty) '$sdk/build-tools',
    if (home != null && home.isNotEmpty)
      '$home/Library/Android/sdk/build-tools',
    if (home != null && home.isNotEmpty) '$home/Android/Sdk/build-tools',
  ];
  for (final root in roots) {
    final directory = Directory(root);
    if (!directory.existsSync()) continue;
    final versions = directory.listSync().whereType<Directory>().toList()
      ..sort((a, b) => compareVersionDirectories(a.path, b.path));
    for (final version in versions.reversed) {
      final path = '${version.path}/zipalign';
      if (File(path).existsSync()) return path;
    }
  }
  return null;
}

String? _which(String tool) {
  final result = run('/usr/bin/which', [tool]);
  if (!result.ok) return null;
  final path = result.stdout.trim().split('\n').first.trim();
  return path.isEmpty ? null : path;
}

/// `flutter`, from PATH.
String? flutterPath() => _which('flutter');

/// SHA-256 of a file, computed by the same tools `lib/common.sh` uses. This is
/// artifact integrity verification (PRD §12.3), not wallet cryptography.
String? sha256OfFile(String path) {
  for (final attempt in const [
    ['shasum', '-a', '256'],
    ['sha256sum'],
  ]) {
    final result = run(attempt.first, [...attempt.skip(1), path]);
    if (result.ok) {
      final digest = result.stdout.trim().split(RegExp(r'\s+')).first;
      if (RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) return digest;
    }
  }
  return null;
}

/// A scratch directory under TMPDIR. Nothing this package writes ever lands
/// inside the repository.
Directory scratchDirectory(String prefix) {
  final base = Platform.environment['TMPDIR'] ?? '/tmp';
  return Directory(
    base.endsWith('/') ? base.substring(0, base.length - 1) : base,
  ).createTempSync(prefix);
}
