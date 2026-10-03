/// Native distribution layer of the `wallet_core_flutter` workspace.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// This package locates and loads the native library, reads the build-identity
/// symbol out of it, and runs DECISION-14 §2.3's four comparisons against the
/// values generated from `compat_manifest.json`. Start at
/// [WalletCoreNative.load].
///
/// **No Flutter, no network, nothing asynchronous.** Nothing under `lib/`
/// imports `package:flutter`, so a pure-Dart command-line tool can use the
/// loader, and the checks are synchronous because they run inside the worker
/// isolate during `Init`, before `initialize()` returns (DECISION-12 §5).
/// Nothing under `lib/` opens a socket: artifacts are downloaded only by this
/// package's build-time tooling under `tool/` (PRD §16 S4).
///
/// **The loaded library is never hashed at run time** (PRD §12.3, threat model
/// TM-13); artifact checksums are verified at build time against the manifest,
/// and the run-time integrity signal is the build-identity symbol. See
/// [WalletCoreNative] for the reasoning.
library;

export 'src/build_identity.dart' show BuildIdentity;
export 'src/code_asset_locations.dart' show codeAssetLocations;
export 'src/errors.dart'
    show
        LibraryLoadAttempt,
        ManifestCheck,
        ManifestMismatchError,
        NativeLoadError;
export 'src/generated/manifest.dart';
export 'src/library_location.dart'
    show
        LibraryFile,
        LibraryLocation,
        NamedLibrary,
        NativePlatform,
        ProcessLibrary,
        androidLibraryName,
        defaultLocations,
        iosFrameworkLibraryPath,
        linuxLibraryName,
        macosLibraryName;
export 'src/loader.dart' show WalletCoreNative;
export 'src/verify_identity.dart'
    show
        ManifestIdentity,
        isPlaceholder,
        placeholderPrefix,
        verifyIdentity,
        verifyIdentityValues,
        verifyManifestHash,
        verifyManifestHashOfString,
        verifyReleaseSet;

/// The pub name of this package.
const String packageName = 'wallet_core_flutter_native';

/// Where the manifest copy this package ships lives, relative to the package
/// root.
///
/// A byte-for-byte copy of the repository's `compat_manifest.json`, written by
/// `melos run gen:manifest` and gated by `gen:check`. It is what PRD §15.3
/// means by shipping the manifest inside this package, and it is what
/// `verifyManifestHash` hashes. The build-time fetch tool under `tool/` reads
/// it from the package directory; an application reads it as a Flutter asset.
const String manifestAssetPath = 'assets/compat_manifest.json';
