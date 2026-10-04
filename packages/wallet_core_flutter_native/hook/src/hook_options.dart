/// The hook's configuration, read from the consuming app's `pubspec.yaml`.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// Build hooks run with a filtered environment, so `WCF_ARTIFACT_DIR` and every
/// other variable the fetch tool reads never reach them. Configuration comes
/// from `hooks.user_defines` instead — written by the app author, read at build
/// time only, and never visible at run time (threat model TM-13: the vendored
/// directory is accepted "only from build-time configuration"):
///
/// ```yaml
/// hooks:
///   user_defines:
///     wallet_core_flutter_native:
///       offline: true              # never download; cache or vendored only
///       vendored_dir: third_party/wcf-artifacts   # laid out by logical name
///       cache_dir: /var/cache/wcf  # optional; default is per app
///       manifest: tool/my_manifest.json           # replace the shipped one
/// ```
///
/// Relative paths resolve against the directory of the `pubspec.yaml` that
/// declares them. Every key is optional.
///
/// A `cache_dir` shared by apps that pin *different* manifests is safe but
/// not useful: the cache path carries no set id, so each app's fetch replaces
/// the other's entry, and an app whose entry is replaced between the fetch
/// tool's check and the hook's read fails its build rather than bundling the
/// other set (`acquire.dart` hashes the bytes it bundles). Share one only
/// between apps on the same manifest.
library;

/// The parsed `hooks.user_defines.wallet_core_flutter_native` block.
final class HookOptions {
  const HookOptions({
    required this.manifestPath,
    required this.manifestOverridden,
    required this.cacheDir,
    required this.vendoredDir,
    required this.offline,
  });

  /// The manifest the artifacts are verified against: the package's shipped
  /// `assets/compat_manifest.json` unless `manifest` overrides it.
  final String manifestPath;

  /// Whether `manifest` was given. Recorded in the hook's log line, because a
  /// build verified against a manifest other than the shipped one is a fact
  /// worth seeing.
  final bool manifestOverridden;

  /// Where verified artifacts are kept: `cache_dir`, else a directory inside
  /// the hook's own shared output directory.
  final String cacheDir;

  /// `vendored_dir`, or `null`.
  final String? vendoredDir;

  /// `offline`: no socket is opened.
  final bool offline;

  /// The user-define keys this hook reads. Any other key under
  /// `wallet_core_flutter_native` is a typo and fails the build.
  static const Set<String> keys = {
    'offline',
    'vendored_dir',
    'cache_dir',
    'manifest',
  };

  /// Parses the user-defines.
  ///
  /// [read] returns the raw value of a key; [path] resolves a string value
  /// against its pubspec's directory and returns an absolute file path.
  /// [definedKeys] is every key present, so an unknown one can be refused.
  /// [shippedManifestPath] and [defaultCacheDir] are the package's own.
  ///
  /// Throws [FormatException] for a value of the wrong type or an unknown key.
  static HookOptions parse({
    required Object? Function(String key) read,
    required String? Function(String key) path,
    required Iterable<String> definedKeys,
    required String shippedManifestPath,
    required String defaultCacheDir,
  }) {
    final unknown = definedKeys.where((k) => !keys.contains(k)).toList()
      ..sort();
    if (unknown.isNotEmpty) {
      throw FormatException(
        'hooks.user_defines.wallet_core_flutter_native has unknown '
        '${unknown.length == 1 ? 'key' : 'keys'} ${unknown.join(', ')}; '
        'the keys are ${(keys.toList()..sort()).join(', ')}',
      );
    }

    final offline = read('offline');
    if (offline != null && offline is! bool) {
      throw FormatException(
        'hooks.user_defines.wallet_core_flutter_native.offline must be true or '
        'false, got ${offline.runtimeType} "$offline"',
      );
    }

    String? pathOf(String key) {
      final raw = read(key);
      if (raw == null) return null;
      if (raw is! String || raw.isEmpty) {
        throw FormatException(
          'hooks.user_defines.wallet_core_flutter_native.$key must be a '
          'non-empty path string, got ${raw.runtimeType} "$raw"',
        );
      }
      return path(key);
    }

    final manifest = pathOf('manifest');
    return HookOptions(
      manifestPath: manifest ?? shippedManifestPath,
      manifestOverridden: manifest != null,
      cacheDir: pathOf('cache_dir') ?? defaultCacheDir,
      vendoredDir: pathOf('vendored_dir'),
      offline: offline == true,
    );
  }
}
