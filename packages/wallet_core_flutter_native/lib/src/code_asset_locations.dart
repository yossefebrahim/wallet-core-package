/// Where a library bundled by this package's build hook is found at run time
/// (DECISION-2 Option 1, evaluation branch).
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// Adds a location list; changes nothing in the loader or in
/// [defaultLocations].
library;

import 'dart:io';

import 'library_location.dart';

/// The locations a `DynamicLoadingBundled` code asset emitted by
/// `hook/build.dart` resolves under, on [platform].
///
/// | Platform | Where Flutter puts the hook's file | Location |
/// |---|---|---|
/// | Android | `lib/<abi>/libTrustWalletCore.so` in the APK | `libTrustWalletCore.so` on the loader search path |
/// | iOS | `TrustWalletCore.framework/TrustWalletCore` in the app's `Frameworks/`, install name `@rpath/…` | that framework-relative path |
/// | macOS | the same framework in the app's `Contents/Frameworks/` | the absolute path of that file, derived from [executable] |
/// | Linux, other | no artifact is shipped | none |
///
/// **macOS never names a relative path** (review finding 15, threat model
/// TM-13). A relative path containing a slash is, to `dlopen`, a path — and
/// dyld tries it against the current working directory, which on a Mac is
/// whatever directory the app or `open` was started from and is often
/// writable by the user. The hooks protocol offers nothing better: the asset
/// id resolves only for `@Native` declarations, and no API returns the path
/// Flutter recorded for it (§7 of `DECISION-2-option1.md`). So the location
/// is computed from the running executable, which a macOS app bundle keeps at
/// `<App>.app/Contents/MacOS/<name>`: the framework is
/// `<App>.app/Contents/Frameworks/TrustWalletCore.framework/TrustWalletCore`.
/// [executable] defaults to `Platform.resolvedExecutable` (symlinks resolved)
/// and is a parameter only so the derivation is testable; an executable that
/// is not absolute or not inside `Contents/MacOS/` of a bundle yields **no**
/// location rather than a guess — `flutter test` on the host does not use
/// this list at all (the file sits at an absolute path recorded in
/// `build/native_assets/macos/native_assets.json`).
///
/// **iOS keeps the framework-relative name.** An iOS app starts with the
/// working directory `/`, on the read-only system volume and outside the app's
/// sandbox, so the relative candidate names a file no app or user can place;
/// the framework then resolves through the app's own `@rpath`
/// (`@executable_path/Frameworks`). That reasoning is about where the process
/// starts, not a guarantee of dyld's search order, and is not measured here.
///
/// Flutter derives the framework name from the emitted file name by dropping
/// `lib` and `.dylib` (`flutter_tools`' `frameworkUri`), which is why the hook
/// emits `libTrustWalletCore.dylib` for every Apple target.
///
/// **Why not [defaultLocations] on iOS.** Its iOS list tries the running
/// process first, and `DynamicLibrary.process()` never fails: under this
/// option the framework is embedded but not linked into the executable, so the
/// process "opens" and then has no `wcf_build_info` — the framework entry
/// after it is never reached. This list therefore omits the process. On macOS
/// the default name `libTrustWalletCore.dylib` is not where a hook-bundled
/// library lives either.
///
/// **What this depends on.** The framework path is a `flutter_tools`
/// convention, not a contract of the hooks protocol, and `frameworkUri`
/// appends a number when two packages emit the same name. The asset id
/// (`package:wallet_core_flutter_native/wallet_core`) is the stable handle,
/// but `dart:ffi` resolves an asset id only for `@Native` declarations; there
/// is no API that turns one into a `DynamicLibrary`, which is what the
/// generated bindings take.
List<LibraryLocation> codeAssetLocations({
  required NativePlatform platform,
  String? executable,
}) => switch (platform) {
  NativePlatform.android => const [NamedLibrary(androidLibraryName)],
  NativePlatform.ios => const [NamedLibrary(iosFrameworkLibraryPath)],
  NativePlatform.macos => [
    ?_macosBundledFramework(executable ?? Platform.resolvedExecutable),
  ],
  NativePlatform.linux || NativePlatform.other => const [],
};

/// `<App>.app/Contents/Frameworks/TrustWalletCore.framework/TrustWalletCore`
/// for an [executable] at `<App>.app/Contents/MacOS/<name>`, else `null`.
LibraryFile? _macosBundledFramework(String executable) {
  final segments = executable.split('/');
  // ['', …, '<App>.app', 'Contents', 'MacOS', '<name>']
  if (!executable.startsWith('/') ||
      segments.length < 5 ||
      segments.contains('..') ||
      segments.contains('.') ||
      segments.last.isEmpty ||
      segments[segments.length - 2] != 'MacOS' ||
      segments[segments.length - 3] != 'Contents' ||
      !segments[segments.length - 4].endsWith('.app')) {
    return null;
  }
  final contents = segments.sublist(0, segments.length - 2).join('/');
  return LibraryFile('$contents/Frameworks/$iosFrameworkLibraryPath');
}
