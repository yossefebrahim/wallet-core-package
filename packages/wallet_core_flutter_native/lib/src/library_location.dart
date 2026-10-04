/// One place the loader can look for the native library, and the ordered
/// per-platform defaults.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
library;

import 'dart:ffi';
import 'dart:io';

import 'code_asset_locations.dart';

/// A single attempt at obtaining a [DynamicLibrary].
///
/// The loader takes an ordered list of these and stops at the first that
/// succeeds, recording every failure. **This is the extension point:** the
/// packaging option DECISION-2 selects adds a location — a bundled code asset,
/// an `xcframework` inside the app bundle, a name the Gradle-packaged `.so`
/// resolves under — by defining a subclass and putting it in the list, with no
/// change to the loader or to this file. T1.8 and T1.9 measured which
/// locations their option needs using exactly this mechanism; the build-hook
/// option DECISION-2 chose is [codeAssetLocations], which [defaultLocations]
/// now uses.
///
/// `base` rather than `interface`: a location may be extended but not
/// implemented, so every location that exists really does end in one of
/// `dart:ffi`'s two entry points and cannot fake a library from Dart.
abstract base class LibraryLocation {
  const LibraryLocation();

  /// How this location reads in a failure report. One short phrase, no
  /// trailing punctuation.
  String get description;

  /// Opens the library, or throws. The loader catches whatever comes out.
  DynamicLibrary open();

  @override
  String toString() => description;
}

/// The already-loaded image: `DynamicLibrary.process()`.
///
/// The case for a consumer that links the library statically into the
/// application binary, or loads it into the process some other way, and
/// passes this location explicitly. **No default list contains it** since
/// DECISION-2 chose build hooks: `DynamicLibrary.process()` never fails, and
/// the hook's framework is embedded but not linked, so a process entry ahead
/// of it would "open" an image without `wcf_build_info` and the framework
/// would never be reached (`code_asset_locations.dart`).
final class ProcessLibrary extends LibraryLocation {
  const ProcessLibrary();

  @override
  String get description =>
      'the running process (statically linked or '
      'already-loaded image)';

  @override
  DynamicLibrary open() => DynamicLibrary.process();
}

/// `DynamicLibrary.open(name)` with a bare library name, resolved by the
/// platform's own dynamic loader search path.
///
/// This is how a library the packaging mechanism installed is found: the name
/// is a constant of this package, and *which file* it resolves to is the
/// packaging mechanism's decision, made at build time. Nothing here reads an
/// environment variable and nothing here accepts a name from a caller on a
/// device platform — TM-13 is precisely the case where a runtime-configurable
/// path decides which code runs.
final class NamedLibrary extends LibraryLocation {
  const NamedLibrary(this.name);

  /// The bare library name, e.g. `libTrustWalletCore.so`.
  final String name;

  @override
  String get description => 'loader search path for "$name"';

  @override
  DynamicLibrary open() => DynamicLibrary.open(name);
}

/// A library at a path on the file system.
///
/// **Development hosts only.** The per-platform defaults use this for the
/// explicit `hostLibraryPath` of a macOS or Linux developer machine, where the
/// library is a build output that has no packaging mechanism to find it, and
/// for the hook-bundled framework of a macOS app, whose absolute path is
/// derived from the running executable ([codeAssetLocations]). It is never
/// part of the Android or iOS defaults and the loader refuses a
/// `hostLibraryPath` on those platforms.
final class LibraryFile extends LibraryLocation {
  const LibraryFile(this.path);

  /// Absolute or relative path to the library file.
  final String path;

  @override
  String get description => 'host library file "$path"';

  @override
  DynamicLibrary open() {
    try {
      return DynamicLibrary.open(path);
    } on Object {
      // "No such file" is a different problem from "found it, could not load
      // it", and the loader's own message does not distinguish them. The
      // existence test happens *after* the open, never before: on macOS a
      // system library such as /usr/lib/libSystem.B.dylib opens from the dyld
      // shared cache while no file of that name exists on disk, so a
      // pre-check would reject paths that work.
      if (!File(path).existsSync()) {
        throw ArgumentError.value(path, 'path', 'no such file');
      }
      rethrow;
    }
  }
}

/// The platforms this package has a load strategy for.
///
/// A parameter rather than a direct read of `Platform`, so the default lists
/// are testable on any host: every test in this package can ask for Android's
/// or iOS's ordering without running there.
enum NativePlatform {
  android,
  ios,
  macos,
  linux,

  /// Anything else. No defaults; a caller must supply locations.
  other;

  /// The platform this code is running on.
  static NativePlatform get current {
    if (Platform.isAndroid) return NativePlatform.android;
    if (Platform.isIOS) return NativePlatform.ios;
    if (Platform.isMacOS) return NativePlatform.macos;
    if (Platform.isLinux) return NativePlatform.linux;
    return NativePlatform.other;
  }

  /// Whether a caller-supplied `hostLibraryPath` is honoured here.
  ///
  /// False on Android and iOS by design (TM-13): on a device platform the
  /// library is resolved by the packaging mechanism's own identity, never by a
  /// path a caller can choose at runtime.
  bool get allowsHostLibraryPath =>
      this == NativePlatform.macos ||
      this == NativePlatform.linux ||
      this == NativePlatform.other;
}

/// The bare library name each platform's dynamic loader is asked for.
const String androidLibraryName = 'libTrustWalletCore.so';

/// The framework-relative path an embedded Apple framework resolves under.
const String iosFrameworkLibraryPath =
    'TrustWalletCore.framework/TrustWalletCore';

/// The bare library name a macOS developer host is asked for.
const String macosLibraryName = 'libTrustWalletCore.dylib';

/// The bare library name a Linux developer host is asked for.
const String linuxLibraryName = 'libTrustWalletCore.so';

/// The ordered locations tried on [platform], most specific first.
///
/// DECISION-2 chose build hooks: `hook/build.dart` bundles the verified
/// library as a code asset, and the defaults open **that** asset where
/// Flutter puts it ([codeAssetLocations]).
///
/// | Platform | Order |
/// |---|---|
/// | Android | `libTrustWalletCore.so` on the loader search path — the hook's `lib/<abi>/libTrustWalletCore.so` |
/// | iOS | `TrustWalletCore.framework/TrustWalletCore` — the hook's embedded framework |
/// | macOS | `hostLibraryPath` if given, then the hook's framework inside the running `.app` (absolute, only when [executable] is in one), then `libTrustWalletCore.dylib` |
/// | Linux | `hostLibraryPath` if given, then `libTrustWalletCore.so` |
/// | other | `hostLibraryPath` if given, nothing otherwise |
///
/// No platform tries the running process (see [ProcessLibrary]). On Android
/// and iOS the hook is strict — a build for a shipped target either bundles
/// the asset or fails — so the asset's location is the only default. macOS is
/// a development host: the hook bundles a macOS library only when the
/// manifest lists one, and `flutter test` neither runs inside an `.app` nor
/// opens the asset by this list, so the host test seam — `hostLibraryPath`,
/// tried first — and the bare host name stay.
///
/// [executable] is the running executable, `Platform.resolvedExecutable` when
/// omitted; a parameter only so the macOS derivation is testable.
List<LibraryLocation> defaultLocations({
  required NativePlatform platform,
  String? hostLibraryPath,
  String? executable,
}) {
  if (hostLibraryPath != null && !platform.allowsHostLibraryPath) {
    throw ArgumentError.value(
      hostLibraryPath,
      'hostLibraryPath',
      'not accepted on ${platform.name}: on a device platform the native '
          'library is resolved by the packaging mechanism, never by a path '
          'chosen at runtime (threat model TM-13)',
    );
  }
  final host = hostLibraryPath == null
      ? const <LibraryLocation>[]
      : <LibraryLocation>[LibraryFile(hostLibraryPath)];

  return switch (platform) {
    NativePlatform.android ||
    NativePlatform.ios => codeAssetLocations(platform: platform),
    NativePlatform.macos => <LibraryLocation>[
      ...host,
      ...codeAssetLocations(platform: platform, executable: executable),
      const NamedLibrary(macosLibraryName),
    ],
    NativePlatform.linux => <LibraryLocation>[
      ...host,
      const NamedLibrary(linuxLibraryName),
    ],
    NativePlatform.other => host,
  };
}
