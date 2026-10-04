# wallet_core_flutter_native

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

The native distribution layer of the `wallet_core_flutter` workspace. Applications depend on `wallet_core_flutter`, not on this package directly; it is documented here because it is the package that decides which binary a build links and proves which one it got.

## What it does

- **Puts the library into the app.** A build hook (`hook/build.dart`, DECISION-2) runs in every `flutter build`, `flutter run` and `flutter test` of an app that depends on the SDK. It verifies the library for the target against the shipped manifest and bundles it as a code asset; nothing else in the app's Gradle, CocoaPods or Xcode setup is involved. See [Build hook](#build-hook).
- **Loads the library.** `WalletCoreNative.load()` opens the library where the build hook's code asset lands — `libTrustWalletCore.so` on Android, `TrustWalletCore.framework/TrustWalletCore` on iOS — never from a caller-supplied path or an environment variable at run time.
- **Checks the build identity.** Every artifact this project publishes exports `wcf_build_info()`, a symbol we compile and link ourselves, returning the upstream commit and the artifact-set id it was built for. `verifyIdentity` compares those with the compatibility manifest before any other symbol is used. Upstream's C API exposes no version symbol, so this identity is ours; a library without it is not one of ours and is rejected.
- **Ships the manifest.** `assets/compat_manifest.json` is a byte copy of the repository's `compat_manifest.json`, written by `melos run gen:manifest` and diffed by `melos run gen:check`. It carries the sha256 and the size of every artifact in the set.
- **Fetches the artifacts at build time.** `tool/fetch_artifacts.dart` downloads what the manifest lists and verifies it. The build hook calls the same code; it can also be run by hand ([Fetching artifacts](#fetching-artifacts)).

Nothing in `lib/` opens a socket. The fetch is build-time code under `hook/` and `tool/`, outside the package's library API, and runs in the build, never in the app.

## Build hook

`hook/build.dart` is invoked by Flutter once per target OS, architecture and, on iOS, SDK. For each invocation it:

1. **Picks the artifact** for the target from the manifest: Android `android/<abi>/libTrustWalletCore.so`, iOS device `ios/arm64/libTrustWalletCore.dylib`, iOS simulator `ios-simulator/arm64_x86_64/libTrustWalletCore.dylib`, macOS `macos/arm64_x86_64/libTrustWalletCore.dylib`. Linux and Windows get no asset and no failure.
2. **Obtains it verified**, through the fetch tool's code: from the hook's cache, else from `vendored_dir`, else — unless `offline: true` — by downloading it from the manifest's content-addressed release URLs over HTTPS. The fetch tool checks the sha256 **and** the size; the hook then reads the file once and hashes those bytes again against the manifest, and bundles only bytes that passed. A mismatch fails the build naming the artifact and both digests; nothing accepts it.
3. **Takes the target's slice** out of a universal Mach-O (a byte range of the verified file, nothing relinked), or checks that an Android `.so` has the ABI's ELF machine.
4. **Emits one code asset**, id `package:wallet_core_flutter_native/wallet_core`, `DynamicLoadingBundled`, file `libTrustWalletCore.so` on Android and `libTrustWalletCore.dylib` on Apple targets. Flutter packages the Android file as `lib/<abi>/libTrustWalletCore.so` and wraps the Apple file in `TrustWalletCore.framework`, embedded in the app.

**Android ABIs.** The artifact set ships `arm64-v8a` and `x86_64` only (PRD §12.2 step 8 ships an ABI only if it is tested). A build that targets `armeabi-v7a`, x86 or RISC-V is **refused by the hook** with the shipped ABIs and the remedy. A default `flutter build apk` or `flutter build appbundle` targets `android-arm` too, so pass the target platforms explicitly (see [Consumer setup](#consumer-setup)); `abiFilters` in Gradle does not help, because Flutter decides which targets the hook runs for.

**No `libc++_shared.so`.** The shipped Android library links the C++ runtime statically (`c++_static`; its `DT_NEEDED` entries are `liblog.so`, `libm.so`, `libdl.so` and `libc.so`). The hook emits no `libc++_shared.so`, and this package depends on no package that does.

**Configuration** comes only from the app's `pubspec.yaml`, never from the environment (build hooks run with a filtered environment, so `WCF_ARTIFACT_DIR` does not reach them). Every key is optional, and an unknown key fails the build:

```yaml
hooks:
  user_defines:
    wallet_core_flutter_native:
      offline: true              # never download: cache or vendored_dir only
      vendored_dir: third_party/wcf-artifacts   # laid out by logical name
      cache_dir: /var/cache/wcf  # default: the hook's own per-app output directory
      manifest: tool/my_manifest.json           # replace the shipped manifest
```

Relative paths resolve against the directory of the `pubspec.yaml` that declares them; in a pub workspace the block belongs in the workspace root's `pubspec.yaml`. A `cache_dir` shared between apps is safe (the hook bundles only bytes it hashed itself) but should be shared only between apps on the same manifest.

**Where the loader finds the asset.** `defaultLocations()` is built from `codeAssetLocations()`: Android `libTrustWalletCore.so` on the loader search path; iOS `TrustWalletCore.framework/TrustWalletCore`; a macOS app the absolute path `<App>.app/Contents/Frameworks/TrustWalletCore.framework/TrustWalletCore` derived from the running executable, after an explicit `hostLibraryPath` and before the bare development-host name. No default tries the running process: the framework is embedded, not linked, so `DynamicLibrary.process()` would open an image without `wcf_build_info`.

**`flutter test` runs the hook too**, for the host. macOS is a development host, not a shipped platform: a manifest without a macOS library yields no asset rather than a failure, while a listed one is verified like any other. Host tests that need the library pass its path through the SDK's internal test seam, as before.

## Consumer setup

Adding `wallet_core_flutter` to an app is the whole setup for the library on Android and iOS, with two exceptions.

**Android release builds: name the target platforms.**

```
flutter build apk --target-platform android-arm64,android-x64
flutter build appbundle --target-platform android-arm64,android-x64
```

Without `--target-platform` the build stops at the hook's refusal of `armeabi-v7a`. `flutter run` on a device or emulator builds that device's ABI only and needs nothing.

**iOS: the app must declare the library's privacy-sensitive API use. This package does not ship a privacy manifest and cannot.** A build hook bundles a single file; the framework Flutter generates around it holds the binary, `Info.plist` and the code signature and nothing else, so there is no place for a `PrivacyInfo.xcprivacy` from this package. Every slice of the library calls APIs from two of Apple's required-reason categories:

| Category | APIs the library imports |
|---|---|
| `NSPrivacyAccessedAPICategoryFileTimestamp` | `stat`, `fstat`, `lstat`, `fstatat` |
| `NSPrivacyAccessedAPICategorySystemBootTime` | `mach_absolute_time` |

Declare both in the app's own privacy manifest, in the Runner target:

1. Open `ios/Runner.xcworkspace` in Xcode.
2. If the Runner target has no `PrivacyInfo.xcprivacy` yet: **File > New > File from Template…**, choose **App Privacy**, name it `PrivacyInfo`, save it in `ios/Runner/`, and tick **Runner** under *Targets*. If one exists, edit it.
3. Add both categories under `NSPrivacyAccessedAPITypes`, with the reasons that describe how *your app* uses the library. For example, as a source-code entry:

```xml
<key>NSPrivacyAccessedAPITypes</key>
<array>
  <dict>
    <key>NSPrivacyAccessedAPIType</key>
    <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
    <key>NSPrivacyAccessedAPITypeReasons</key>
    <array><string>C617.1</string></array>
  </dict>
  <dict>
    <key>NSPrivacyAccessedAPIType</key>
    <string>NSPrivacyAccessedAPICategorySystemBootTime</string>
    <key>NSPrivacyAccessedAPITypeReasons</key>
    <array><string>35F9.1</string></array>
  </dict>
</array>
```

4. Check that `PrivacyInfo.xcprivacy` is listed under the Runner target's **Build Phases > Copy Bundle Resources**.

The categories were measured on the artifacts (`nm -u` against Apple's list). The reason codes above were inferred from the imported symbols, not from every call site upstream makes, and have not yet been checked by App Store validation of a signed archive; choose the reasons that are true for your app.

## Fetching artifacts

```
dart run packages/wallet_core_flutter_native/tool/fetch_artifacts.dart --help
dart run packages/wallet_core_flutter_native/tool/fetch_artifacts.dart --dry-run
dart run packages/wallet_core_flutter_native/tool/fetch_artifacts.dart
```

`--dry-run` prints, per artifact, the primary URL, the mirror URL or `no mirror`, the cache path, and whether the cache entry is `verified`, `missing`, or `corrupt` — and opens no socket. It exits 0 when the manifest can be fetched from and 2 when it cannot, so it works as a CI preflight.

A manifest still in the placeholder shape — `TBD-` values in `retention.primary`, `identity.artifact_set_id` or an artifact digest — cannot be fetched from, and `--dry-run` names each blocked field and the task that fills it. The shipped manifest pins the published set `as_4.8.0_001` (release `native-4.8.0-001`).

### The cache directory

In order:

1. `--cache-dir <path>`, if given;
2. `$WCF_ARTIFACT_DIR`, if set — this is the configurable cache directory an air-gapped or containerised build points at;
3. otherwise `~/.cache/wallet_core_flutter/<upstream.tag>/`, tag-scoped because two upstream tags are two different artifact sets.

Inside it, an artifact lives at its logical name from the manifest, e.g. `android/arm64-v8a/libTrustWalletCore.so`.

A cached file is re-hashed before it is trusted. One that does not match the manifest is deleted rather than reused, and fetched again.

### Offline and vendored builds

`--vendored <dir>` takes a directory laid out by logical name, pre-populated by you. Each file is verified against the manifest exactly as a download is, **before** it is copied into the cache; a file that does not match is rejected and not copied. It is tried before the network, so a partially vendored directory still works.

`--offline` never opens a socket. It succeeds from a warm cache or a vendored directory and otherwise fails, naming the artifact and both places it looked. Combine the two for an air-gapped build:

```
dart run packages/wallet_core_flutter_native/tool/fetch_artifacts.dart \
  --vendored /mnt/artifacts --offline
```

Other flags: `--only <logical_name>` (repeatable) to fetch one artifact, `--keep-going` to report every failure rather than stopping at the first (the exit code stays non-zero), `--manifest <path>` to read a manifest other than the shipped one.

### Verification

**Every artifact is verified against the manifest's sha256 and its recorded size, from every source — the network, the cache, or a vendored directory — and there is no flag, environment variable, or code path that skips that check or accepts a mismatch.** Bytes land on a temporary name inside the cache directory and are renamed into place only after they verify, so a failed or interrupted run never leaves a wrong byte at the cache path. A mismatch is reported with the artifact's name, the URL, and both digests and both sizes, and stops the run.

Downloads are HTTPS only. Redirects are followed — GitHub Releases answers an asset URL with a redirect to its object store — up to five hops, each of which must also be HTTPS; the digest, not the host, is the control.

The artifacts are **checksum-pinned**: the manifest that pins them is checked into the repository, reviewed in the same change that publishes them, and shipped inside this package. An independent-rebuild comparison is a separate, later requirement and is not claimed here.

## Licence

MIT. See `LICENSE` at the repository root and `THIRD_PARTY_NOTICES.md` for upstream's Apache 2.0 notice.
