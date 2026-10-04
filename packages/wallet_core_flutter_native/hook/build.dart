/// Build hook: bundles the verified native library into the app as a
/// `CodeAsset` with `DynamicLoadingBundled()` (DECISION-2: build hooks).
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// Per invocation — one target OS, architecture and, on iOS, SDK:
///
/// 1. pick the manifest artifact for the target (`src/targets.dart`);
/// 2. obtain it verified — sha256 **and** size against the manifest — through
///    the build-time fetch tool's own code, then read it once and hash those
///    bytes again (`src/acquire.dart`); a mismatch at either check fails the
///    build naming the artifact and both digests, and nothing accepts it;
/// 3. take the target's slice out of a universal Mach-O, or confirm a thin
///    one's architecture or an `.so`'s ELF machine (`src/slices.dart`);
/// 4. emit one `CodeAsset`, id `package:wallet_core_flutter_native/wallet_core`
///    and file `libTrustWalletCore.dylib` / `libTrustWalletCore.so` — the same
///    for device, simulator and every architecture.
///
/// The network rule is stated in `src/acquire.dart`; the configuration keys
/// in `src/hook_options.dart`. Nothing here runs when the app runs.
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

import '../tool/src/asset_names.dart' as names;
import '../tool/src/manifest.dart';
import 'src/acquire.dart';
import 'src/hook_options.dart';
import 'src/slices.dart';
import 'src/targets.dart';

Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final code = input.config.code;

    final ArtifactSelection? selection;
    try {
      selection = selectArtifact(
        os: code.targetOS,
        architecture: code.targetArchitecture,
        iosSdk: code.targetOS == OS.iOS ? code.iOS.targetSdk : null,
      );
    } on UnsupportedTarget catch (e) {
      throw BuildError(message: 'wallet_core_flutter_native: ${e.message}');
    }
    if (selection == null) {
      stdout.writeln(
        'wallet_core_flutter_native: no library is shipped for '
        '${code.targetOS}; no asset emitted.',
      );
      return;
    }
    if (code.linkModePreference == LinkModePreference.static) {
      throw BuildError(
        message:
            'wallet_core_flutter_native: the build asks for static linking '
            'only, and the artifacts are dynamic libraries.',
      );
    }

    final HookOptions options;
    try {
      options = HookOptions.parse(
        read: (key) => input.userDefines[key],
        path: (key) => input.userDefines.path(key)?.toFilePath(),
        definedKeys: _definedUserDefineKeys(input.json),
        shippedManifestPath: input.packageRoot
            .resolve('assets/compat_manifest.json')
            .toFilePath(),
        defaultCacheDir: input.outputDirectoryShared
            .resolve('artifacts/')
            .toFilePath(),
      );
    } on FormatException catch (e) {
      throw BuildError(message: 'wallet_core_flutter_native: ${e.message}');
    }

    final manifestFile = File(options.manifestPath);
    output.dependencies.add(manifestFile.uri);
    if (!manifestFile.existsSync()) {
      throw BuildError(
        message:
            'wallet_core_flutter_native: no manifest at ${options.manifestPath}',
      );
    }
    final FetchManifest manifest;
    try {
      manifest = FetchManifest.parse(
        manifestFile.readAsStringSync(),
        source: options.manifestPath,
      );
    } on FormatException catch (e) {
      throw BuildError(message: 'wallet_core_flutter_native: ${e.message}');
    }

    final String logicalName;
    try {
      logicalName = chooseLogicalName(
        selection,
        manifest.artifacts.keys,
        manifestSource: options.manifestPath,
      );
    } on UnsupportedTarget catch (e) {
      if (selection.optional) {
        stdout.writeln(
          'wallet_core_flutter_native: ${options.manifestPath} lists no '
          'library for ${selection.target} (a development host, not a '
          'shipped platform); no asset emitted.',
        );
        return;
      }
      throw BuildError(message: 'wallet_core_flutter_native: ${e.message}');
    }

    final record = manifest.artifacts[logicalName]!;
    final request = AcquireRequest(
      logicalName: logicalName,
      manifestPath: options.manifestPath,
      cacheDir: options.cacheDir,
      toolDir: input.packageRoot.resolve('tool/').toFilePath(),
      // A record without both never gets past the fetch tool's manifest gate
      // (exit 2), whose message names what is missing; nothing can hash to
      // these stand-ins.
      sha256: record.sha256 ?? '',
      size: record.size ?? -1,
      vendoredDir: options.vendoredDir,
      offline: options.offline,
    );
    final Acquired acquired;
    try {
      acquired = await acquireArtifact(
        request,
        cachePathFor: (dir, name) =>
            names.cachePathFor(dir, name, separator: Platform.pathSeparator),
      );
    } on AcquireError catch (e) {
      throw BuildError(message: e.message);
    }
    for (final line in acquired.log) {
      stdout.writeln('wallet_core_flutter_native: $line');
    }

    output.dependencies.add(File(acquired.cachePath).uri);
    final vendored = options.vendoredDir == null
        ? null
        : File(
            names.cachePathFor(
              options.vendoredDir!,
              logicalName,
              separator: Platform.pathSeparator,
            ),
          );
    if (vendored != null && vendored.existsSync()) {
      output.dependencies.add(vendored.uri);
    }

    // The bytes acquireArtifact hashed, never a second read of the cache
    // path: another writer may have replaced the file since (finding 1).
    final bytes = acquired.bytes;
    final List<int> slice;
    try {
      slice = takeSlice(bytes, selection.slice, source: logicalName);
    } on SliceError catch (e) {
      throw BuildError(message: 'wallet_core_flutter_native: ${e.message}');
    }

    final target = File.fromUri(
      input.outputDirectory.resolve(selection.fileName),
    );
    final partial = File('${target.path}.part');
    partial.writeAsBytesSync(slice, flush: true);
    partial.renameSync(target.path);

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: codeAssetName,
        linkMode: DynamicLoadingBundled(),
        file: target.uri,
      ),
    );
    stdout.writeln(
      'wallet_core_flutter_native: bundled $logicalName for '
      '${selection.target} (${slice.length} of ${bytes.length} bytes, '
      'sha256 ${request.sha256} verified in memory against '
      '${options.manifestPath}'
      '${options.manifestOverridden ? ', a manifest override' : ''}'
      '${options.offline ? ', offline' : ''}).',
    );
  });
}

/// Every key under `hooks.user_defines.wallet_core_flutter_native`, read from
/// the raw hook input because the typed API offers lookup by key only.
List<String> _definedUserDefineKeys(Map<String, Object?> json) {
  final userDefines = json['user_defines'];
  if (userDefines is! Map) return const [];
  final pubspec = userDefines['workspace_pubspec'];
  if (pubspec is! Map) return const [];
  final defines = pubspec['defines'];
  if (defines is! Map) return const [];
  return [for (final key in defines.keys) '$key'];
}
