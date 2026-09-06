# Evidence — what upstream release 4.8.0 actually ships (T0.5, DECISION-9)

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

Upstream repository: `trustwallet/wallet-core`. Release `4.8.0`, published 2026-08-28T11:04:23Z. Tag object resolves to commit **`d692ac27749d0c615e17c751b70ab4f0aa75c59b`**
(source: `docs/decisions/evidence/prefetch-2026-09-07/tag-4.8.0.txt`, orchestrator, gh CLI, 2026-09-07).

**How to read this file.** Every row is labelled with how it was obtained:

| Label | Meaning |
|---|---|
| `[MEASURED]` | Produced on this machine on 2026-09-07 by running the quoted command against a locally extracted copy of the artifact. |
| `[METADATA]` | Read from an upstream-published file (`Package.swift`, the release asset list, the upstream README, an upstream workflow) without opening the artifact. |
| `[INFERENCE]` | A conclusion drawn from the rows above. Not itself an observation. |

The two large assets were extracted under a temporary directory outside the repository
(`unzip -q WalletCore.xcframework.zip -d $TMPDIR/t05work/xcf`, `tar -xJf TrustWalletCore-4.8.0.tar.xz -C $TMPDIR/t05work/tarball`).
Nothing was written under `third_party/` or `packages/`. The read-only cache at `~/.cache/wcf-upstream/4.8.0/` was not modified.

---

## 1. Asset table

Release 4.8.0 carries **8 assets**, not the 19 the PRD assumed (PRD §12.2, `[UNVERIFIED] the 19 release assets' contents`; plan task note T0.5 repeats the 19).
Source of names, byte sizes and URLs: `prefetch-2026-09-07/release-assets-4.8.0.tsv`.

| # | Asset | Size (bytes) | Purpose | sha256 | How the sha256 was obtained |
|---|---|---|---|---|---|
| 1 | `kdoc.zip` | 2 154 115 | Kotlin API documentation (Dokka). Not consumed by this project. | — | not published, not downloaded |
| 2 | `Package.swift` | 912 | Swift Package Manager manifest declaring two `binaryTarget`s and their checksums; pins `platforms: [.iOS(.v13)]`. | — | n/a (text file) |
| 3 | `TrustWalletCore-4.8.0.tar.xz` | 53 949 676 | **Not source.** Apple binary distribution: `License`, `Sources/` (Swift), `include/` (C headers), `WalletCoreCommon.xcframework` (static archives, four Apple slice families incl. macOS). See §4. | `30b0532d9f143b6409aa405f3ba124625fb01e70f13d8e52b3904334c617ff60` | **[MEASURED]** `shasum -a 256` on the local cache copy; upstream publishes no checksum for this asset |
| 4 | `WalletCore.doccarchive.zip` | 114 494 999 | Swift DocC documentation archive. Not consumed by this project. | — | not published, not downloaded |
| 5 | `WalletCore.xcframework.dSYM.zip` | 98 474 160 | Debug symbols for asset 6. Needed only to symbolicate crash reports against upstream's own build. | — | not published, not downloaded |
| 6 | `WalletCore.xcframework.zip` | 32 000 472 | iOS **dynamic** framework, two slices (device, simulator). See §2. | `0c79df1a901a3abfbccee5052229984b1e743696483176b3cfb68eaf90f400bc` | **[METADATA]** declared in `Package.swift`; **[MEASURED]** `shasum -a 256` on the local cache copy agrees byte-for-byte |
| 7 | `WalletCoreSwiftProtobuf.xcframework.dSYM.zip` | 6 722 623 | Debug symbols for asset 8. | — | not published, not downloaded |
| 8 | `WalletCoreSwiftProtobuf.xcframework.zip` | 3 318 045 | SwiftProtobuf runtime repackaged as an xcframework. Asset 6 has a hard `LC_LOAD_DYLIB` on it (§2.4), so an app consuming asset 6 must also embed this one. | `6098237d99dc609cc1ee5a8fe9c9cf0b90fb06ae739f42a51e3dbdbb1f18ec37` | **[METADATA]** declared in `Package.swift`; not downloaded |

Only assets 3 and 6 were downloaded (by the orchestrator, 2026-09-07) and inspected here. Assets 1, 4, 5, 7, 8 are described from metadata only.

**[INFERENCE]** Upstream publishes a checksum for exactly two of the eight assets, and only inside `Package.swift`. Any asset this project mirrors must be checksummed by us and pinned in `compat_manifest.json` (PRD §15.3 `artifacts`), because for six of eight assets there is no upstream checksum to compare against — the recorded value is first-seen, not attested.

---

## 2. `WalletCore.xcframework.zip` — inspected locally

Extracted to a temp directory; 150 MB on disk from a 32 MB zip.

### 2.1 Slices

Source: `WalletCore.xcframework/Info.plist` (**[MEASURED]** `cat`), corroborated by `prefetch-2026-09-07/xcframework-4.8.0-Info.plist`.

| LibraryIdentifier | Platform | Variant | Architectures | Binary path | Binary size (bytes) |
|---|---|---|---|---|---|
| `ios-arm64` | ios | device | arm64 | `WalletCore.framework/WalletCore` | 26 172 096 |
| `ios-arm64_x86_64-simulator` | ios | simulator | arm64, x86_64 | `WalletCore.framework/WalletCore` | 54 026 000 |

There is **no macOS slice, no Mac Catalyst slice, no tvOS/watchOS/visionOS slice, and no Android anything** in this asset.

### 2.2 Library type — dynamic, not static

The PRD records `[UNVERIFIED] whether a dynamic slice is available or must be built` and states "upstream's iOS distribution is a static xcframework" (§12.1, *Static vs dynamic* row). **That is not true of 4.8.0.**

**[MEASURED]**

```
$ file .../ios-arm64/WalletCore.framework/WalletCore
Mach-O 64-bit dynamically linked shared library arm64

$ file .../ios-arm64_x86_64-simulator/WalletCore.framework/WalletCore
Mach-O universal binary with 2 architectures:
  [x86_64:Mach-O 64-bit dynamically linked shared library x86_64] [arm64]

$ lipo -info .../ios-arm64_x86_64-simulator/WalletCore.framework/WalletCore
Architectures in the fat file: ... are: x86_64 arm64
$ lipo -info .../ios-arm64/WalletCore.framework/WalletCore
Non-fat file: ... is architecture: arm64

$ otool -hv .../ios-arm64/WalletCore.framework/WalletCore
MH_MAGIC_64  ARM64  ALL  0x00  DYLIB  40  5536
  NOUNDEFS DYLDLINK TWOLEVEL WEAK_DEFINES BINDS_TO_WEAK
  NO_REEXPORTED_DYLIBS MH_HAS_TLV_DESCRIPTORS NLIST_OUTOFSYNC_WITH_DYLDINFO

$ otool -l ... | grep -A5 LC_ID_DYLIB
  cmd LC_ID_DYLIB
  name @rpath/WalletCore.framework/WalletCore
  current version 1.0.0 / compatibility version 1.0.0
```

Mach-O `filetype` is `DYLIB` with install name `@rpath/WalletCore.framework/WalletCore`. **[INFERENCE]** `DynamicLoadingBundled()` in a Flutter build hook, and `DynamicLibrary.open` from Dart, can both address this framework as shipped — the PRD's stated blocker for Option 1 on iOS does not exist at 4.8.0. This is the fact T1.8 needs; §5 of DECISION-9 records the caveat.

### 2.3 Deployment target, SDK, signing, bitcode

**[MEASURED]**

- `LC_BUILD_VERSION`: `platform 2` (iOS), `minos 13.0`, `sdk 26.5`. Matches `Package.swift`'s `.iOS(.v13)` and the framework `Info.plist` key `MinimumOSVersion = 13.0`.
- Framework `Info.plist` (device slice): `CFBundleIdentifier = com.trustwallet.WalletCore`, `CFBundleShortVersionString = 1.0`, `CFBundleVersion = 1`, `DTPlatformName = iphoneos`, `DTPlatformVersion = 26.5`, `DTSDKName = iphoneos26.5`, `DTXcodeBuild = 17F113`, `BuildMachineOSBuild = 25F84`, `UIDeviceFamily = [1, 2]`.
- Signing: the **device** slice is `code object is not signed at all` (`codesign -dv`). The **simulator** slice carries a `_CodeSignature/` directory and is **ad-hoc** signed: `Signature=adhoc`, `TeamIdentifier=not set`, `CodeDirectory v=20400 flags=0x2(adhoc)`. Neither is a distribution signature. PRD §12.2 step 10 asks us to sign the xcframework `[REC]`; nothing upstream ships is signed in a way we could rely on.
- Bitcode: no `__LLVM` segment is present (`otool -l | grep segname` returns only `__TEXT`, `__DATA`, `__DATA_CONST`). **[INFERENCE]** bitcode is a non-issue; Apple removed bitcode support from Xcode 14 onward and this build has none.
- dSYM: shipped separately as asset 5 (98 MB). **[INFERENCE]** it matters only for symbolicating crashes inside upstream's own build. If we relink or rebuild (DECISION-9 options A′/B), asset 5 no longer corresponds to what runs, and our CI must emit its own dSYM if crash symbolication is wanted.
- No `PrivacyInfo.xcprivacy` exists anywhere in the xcframework (the framework directory holds exactly `Headers/`, `Info.plist`, `Modules/`, the binary, and — simulator only — `_CodeSignature/`). Required-reason-API auditing and the privacy manifest are T1.19's measurement; this row only records that upstream supplies none.

### 2.4 Dependencies of the shipped dynamic framework

**[MEASURED]** `otool -L .../ios-arm64/WalletCore.framework/WalletCore` lists, besides itself:

- `@rpath/WalletCoreSwiftProtobuf.framework/WalletCoreSwiftProtobuf` (asset 8)
- `/usr/lib/libc++.1.dylib`, `/usr/lib/libobjc.A.dylib`, `/usr/lib/libSystem.B.dylib`
- `/System/Library/Frameworks/Foundation.framework/Foundation`, `.../Security.framework/Security`
- `/usr/lib/swift/libswiftCore.dylib`, `libswiftFoundation.dylib` (both non-weak) and 13 further `libswift*.dylib` marked `weak`, including `libswiftUIKit`, `libswiftMetal`, `libswiftQuartzCore`, `libswiftCoreImage`, `libswiftSpatial`

**[INFERENCE]** The shipped iOS framework is a *Swift* framework that happens to export a C API. Consuming it costs a second embedded framework (asset 8) plus the Swift and UIKit runtime linkage, none of which a Dart FFI SDK uses. §4.3 shows the same C API can be obtained without any of it.

### 2.5 Headers and module map — present

**[MEASURED]**

- `Headers/`: **85** files per slice (`ls Headers | wc -l` = 85; the prefetched `unzip -l` listing has 172 `Headers/` lines across the two slices, i.e. 85 headers + 1 directory entry each). SUMMARY.md's figure of 143 headers per slice is the `include/` count from the `.tar.xz` (§4.2), not this one.
- Umbrella headers `WalletCore.h` and `WalletCore-Swift.h` are both present.
- `Modules/module.modulemap`:
  ```
  framework module WalletCore { umbrella header "WalletCore.h" export * module * { export * } }
  module WalletCore.Swift { header "WalletCore-Swift.h" }
  ```
- `Modules/WalletCore.swiftmodule/` holds `arm64-apple-ios.swiftinterface`, `.private.swiftinterface`, `.swiftdoc`, `.abi.json`.

### 2.6 Exported C symbols — complete and exactly matching the headers

**[MEASURED]** Device slice, `nm -gU`:

- 57 174 exported symbols in total (Swift, C++ and protobuf symbols included).
- **464** of them are `T _TW…` text symbols.
- Declared TW C functions in the slice's own `Headers/`: **464**, extracted with
  `grep -rhoE "^[A-Za-z_][A-Za-z0-9_ *]*\bTW[A-Za-z0-9_]+\(" Headers | grep -oE "TW[A-Za-z0-9_]+\($" | tr -d '(' | sort -u`.
- The two sets are **identical** (`diff` of the sorted lists is empty).
- Macro tally across those headers: 232 `TW_EXPORT_STATIC_METHOD`, 131 `TW_EXPORT_METHOD`, 75 `TW_EXPORT_PROPERTY`, 33 `TW_EXPORT_CLASS`, 29 `TW_EXPORT_STRUCT`, 20 `TW_EXPORT_ENUM`, 1 `TW_EXPORT_FUNC`, 1 `TW_EXPORT_STATIC_PROPERTY`.

**[INFERENCE]** On iOS, the visibility failure reported in upstream issue #4638 (§3.3) does not reproduce: the full declared C surface is dynamically exported. The 464-symbol figure is the number T1.4/T1.5 inventories should expect to reconcile against, and 57 174 total exports is the duplicate-symbol surface T1.19 must scan when two plugins each embed a wallet-core build.

### 2.7 No version symbol — corroboration of the [VERIFIED] fact

`[VERIFIED 2026-09-07 by the orchestrator]` the 4.8.0 headers expose no library-version symbol. Corroborated here **[MEASURED]**: the only version-shaped exported symbols are

- `S _WalletCoreVersionString` in the dynamic framework, whose string value is `@(#)PROGRAM:WalletCore  PROJECT:TrustWalletCore-1` (`strings -a | grep '^@(#)'`) — Xcode's `CURRENT_PROJECT_VERSION` stamp, literally `1`;
- `S _WalletCoreCommonVersionString` in the static archive, value `@(#)PROGRAM:WalletCoreCommon  PROJECT:WalletCoreCommon-1`;
- `__ZN6google8protobuf8internal13VersionStringEi` — the bundled protobuf runtime's version, not wallet-core's;
- `TWCoinTypeXprvVersion`, `TWCoinTypeXpubVersion`, `TWHDVersionIsPrivate`, `TWHDVersionIsPublic`, `TWSegwitAddressWitnessVersion` — all BIP-32/SegWit domain functions, unrelated.

**[INFERENCE]** Neither `4.8.0` nor commit `d692ac27…` is recoverable from any symbol in any shipped artifact. The build-identity symbol of PRD §12.3 must be ours in every option, and there is no upstream symbol we could fall back to if ours were absent.

---

## 3. Android — nothing is shipped, and the upstream binary is token-gated

### 3.1 GitHub Releases carry no Android artifact

**[METADATA]** The complete asset list for 4.8.0 is the 8 rows of §1. There is no `.aar`, no `.jar`, no `.zip` containing `.so` files, no per-ABI directory, and no `prefab` archive. `wallet-core` publishes no Android binary on GitHub Releases at this tag.

### 3.2 Upstream hosts Android on GitHub Packages behind a token

**[METADATA]** Upstream README at 4.8.0, **line 48** (`prefetch-2026-09-07/upstream-README-4.8.0.md`), verbatim:

> Android releases are hosted on [GitHub packages](https://github.com/trustwallet/wallet-core/packages/700258), you need to add GitHub access token to install it.

**[METADATA]** `android/gradle.properties` at the tag: `GROUP=com.trustwallet.walletcore`, `VERSION_NAME=0.12.1`, `POM_LICENCE_NAME=MIT`. `android/settings.gradle`: `include ':app', ':wallet-core', ':wallet-core-proto'`. `android/build.gradle`: AGP 8.8.0, Kotlin 2.1.0.

**[METADATA]** `android-ci.yml` at the tag builds and tests but does not publish; its final step `tools/samples-build android` is the only one that sets `GITHUB_USER` / `GITHUB_TOKEN`, i.e. the sample app *consumes* the token-gated GitHub Packages coordinate.

**[INFERENCE]** An unauthenticated consumer build, a Flutter build hook, or an unauthenticated CI job cannot resolve `com.trustwallet.walletcore` from upstream. Option A as briefed ("mirror upstream's binaries") is not available on Android: there is no unauthenticated binary to mirror, and mirroring a token-gated Maven artifact would mean redistributing a binary that no third party can fetch from a public URL to compare against ours.

### 3.3 What building from the git tree would produce, and the known risk

**[METADATA]** The Android build path in the git tree at `d692ac27…` is `tools/android-build`, preceded by `tools/install-sys-dependencies-mac`, `tools/install-rust-dependencies`, `tools/install-android-dependencies`, `tools/install-dependencies`, `tools/generate-files android` (step names taken from `android-ci.yml` at the tag). `android-ci.yml` pins JDK 17, Gradle 8.10.2, and — in the emulator step only — `ndk: 23.1.7779620`, `cmake: 3.18.1`.

**[INFERENCE]** The output is an `.aar` from the `:wallet-core` Gradle module containing `jni/<abi>/libTrustWalletCore.so` per configured ABI, plus the JNI Kotlin/Java classes we do not use. For this project only the `.so` files matter; the ABI set is whatever `tools/android-build` is configured for and must be pinned by us, since PRD §12.2 step 8 says an untested ABI is dropped rather than shipped.

**[METADATA]** Upstream issue **#4638** (open, filed 2026-01-29, `prefetch-2026-09-07/upstream-issue-4638.md`): a Flutter user cloned wallet-core v4.5.0, built the `.aar` with `./tools/android-build`, generated ffigen bindings, and at runtime got

> `Invalid argument(s): Failed to lookup symbol 'TWAnyAddressIsValid': undefined symbol: TWAnyAddressIsValid`

while confirming the `.so` was present inside the `.aar` and loadable. The issue has no maintainer answer; the only two comments are spam. Environment reported: Flutter 3.38.8, Dart 3.10.7, wallet-core v4.5.0.

**[INFERENCE]** The Android build path is tuned for JNI, where the `TW*` C symbols only need to be reachable from the JNI shim objects inside the same `.so`, not exported from it. Nothing in the report proves a specific cause (it could equally be `--gc-sections`, a version script, or `-fvisibility=hidden` without `visibility("default")` reaching those declarations). It is a concrete, unresolved report against the exact path Option B must use, at a different version, and this project must verify export visibility on every Android `.so` it produces before shipping it — the check is `llvm-nm --defined-only --extern-only libTrustWalletCore.so`, reconciled against the 464-name list of §2.6, and it belongs in T1.2's build job and T1.19's harness, not only in a device test.

---

## 4. `TrustWalletCore-4.8.0.tar.xz` — a binary Apple distribution, not source

### 4.1 Top level

**[MEASURED]** `tar -t` and the extracted tree agree with `prefetch-2026-09-07/source-tarball-4.8.0-toplevel.txt`. Exactly four entries:

| Entry | What it is | Extracted size |
|---|---|---|
| `License` | Apache License 2.0, full text (first line: `Apache License`, `Version 2.0, January 2004`) | 10 757 B |
| `Sources/` | **219** `.swift` files plus `SecRandom.m`; `Generated/`, `Extensions/`, `Types/`, `AnySigner.swift`, `KeyStore.swift`, `KeyStore.Error.swift`, `TWCardano.swift`, `TWData.swift`, `TWString.swift`, `Wallet.swift`, `Watch.swift` | 3.2 MB |
| `include/` | `include/TrustWalletCore/` — **143** C headers | 660 KB |
| `WalletCoreCommon.xcframework/` | four slice families of **static archives** — see §4.3 | 270 MB |

**[MEASURED]** the whole tarball contains **0** `.proto` files and **0** `registry.json`. It contains no `tools/`, no `android/`, no `rust/`, no `src/`, no CMake files. It is the CocoaPods-style payload for the Swift/ObjC integration, not a source distribution.

### 4.2 `include/` (143) versus the framework's `Headers/` (85)

**[MEASURED]** `diff` of the two sorted file lists: the 58 extra files in `include/TrustWalletCore/` are all `TW<Chain>Proto.h` (e.g. `TWEthereumProto.h`, `TWBitcoinV2Proto.h`, `TWSolanaProto.h`). The `TW_EXPORT_*` macro tallies are byte-identical between the two sets (232/131/75/33/29/20/1/1 — the same numbers as §2.6), i.e. the 58 extra headers declare no functions; they are protobuf type-alias headers. **[INFERENCE]** the framework's 85 headers carry the complete C function surface; the extra 58 matter only to a consumer that wants the `TW…Proto` typedefs, which our generated protobuf layer supplies instead.

### 4.3 `WalletCoreCommon.xcframework` — static archives including a **macOS** slice

**[MEASURED]** `Info.plist` declares four libraries:

| LibraryIdentifier | Platform | Variant | Architectures | Binary type (`file`) | Binary size (bytes) |
|---|---|---|---|---|---|
| `ios-arm64` | ios | device | arm64 | `current ar archive` | 39 318 328 |
| `ios-arm64_x86_64-simulator` | ios | simulator | arm64, x86_64 | universal, both slices `current ar archive` | 79 056 608 |
| `ios-arm64_x86_64-maccatalyst` | ios | maccatalyst | arm64, x86_64 | universal, both slices `current ar archive` | 83 294 352 |
| **`macos-arm64_x86_64`** | **macos** | — | arm64, x86_64 | universal, both slices `current ar archive` | 79 611 680 |

All four are **static** archives (`ar`), not dylibs, so none of them can be `DynamicLibrary.open`ed as they stand.

**[MEASURED]** `nm -gU` on the `macos-arm64_x86_64` archive, arm64 slice, yields **464** `T _TW…` symbols, and `diff` against the iOS dynamic framework's exported list (§2.6) is **empty** — the same 464 names. The `ios-arm64` static archive likewise yields 464.

**[MEASURED]** `ar -t` on the macOS arm64 slice lists **723** members, of which **192** are Rust codegen units (`*-cgu.N.rcgu.o`, e.g. `rustc_hex-…rcgu.o`, `rustc_std_workspace_core-…rcgu.o`) alongside `RustCoinEntry.o`. **[INFERENCE]** upstream's Rust-built components are already compiled into these archives; consuming them does not require a Rust toolchain on our side.

**[MEASURED]** `WalletCoreCommon` also contains at least one internally inconsistent object: linking with `-Wl,-all_load` fails with eight undefined Monero symbols (`_xmr_gen_range_sig_ex` in `range_proof.o` referencing `_ge25519_set_xmr_h`, `_xmr_add_keys2_vartime`, `_xmr_hash_to_scalar`, `_xmr_hasher_init/update/final`, `_xmr_random_scalar`). No `TW*` entry point reaches that object, so pulling members by demand rather than wholesale avoids it.

### 4.4 Relink experiment — a loadable library with our identity symbol, from release assets alone

**[MEASURED]** Performed on this machine, 2026-09-07, Apple clang from Xcode 17F113, entirely under the scratch directory. A four-line C file was compiled alongside the archive:

```c
/* the PRD 12.3 build-identity symbol, compiled by us */
const char* wcf_build_info(void) {
    return "{\"upstream_commit\":\"d692ac27749d0c615e17c751b70ab4f0aa75c59b\","
           "\"artifact_set_id\":\"t05-experiment\"}";
}
```

The 464 symbol names of §2.6 were turned into a linker response file (`sed 's/^/-Wl,-u,_/'`) so the linker pulls exactly the archive members those entry points reach.

**macOS host library:**

```
$ lipo -thin arm64 -output wcc-macos-arm64.a \
      WalletCoreCommon.xcframework/macos-arm64_x86_64/WalletCoreCommon.framework/Versions/A/WalletCoreCommon
$ clang -arch arm64 -dynamiclib -o libwalletcore_host.dylib \
      @uflags.rsp wcf_build_info.c wcc-macos-arm64.a \
      -lc++ -framework Foundation -framework Security -framework CoreFoundation
```

Result: `libwalletcore_host.dylib`, **19 876 872 bytes**, `Mach-O 64-bit dynamically linked shared library arm64`, exporting **464** `T _TW…` symbols plus `T _wcf_build_info`.

Loaded from Dart with `dart:ffi` and exercised:

```
$ dart run probe.dart
wcf_build_info() -> {"upstream_commit":"d692ac27749d0c615e17c751b70ab4f0aa75c59b","artifact_set_id":"t05-experiment"}
TWAnyAddressIsValid("0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed", ETH) -> true
TWAnyAddressIsValid("not-an-address", ETH) -> false
```

(`TWStringCreateWithUTF8Bytes` → `TWAnyAddressIsValid` → `TWStringDelete`, coin id 60. The address is the EIP-55 specification's own example in its all-lowercase form.)

**iOS device library:**

```
$ clang -arch arm64 -target arm64-apple-ios13.0 \
      -isysroot .../iPhoneOS.sdk -dynamiclib \
      -install_name @rpath/WalletCoreShim.framework/WalletCoreShim \
      -o libwalletcore_ios_arm64.dylib \
      @uflags.rsp wcf_build_info.c \
      WalletCoreCommon.xcframework/ios-arm64/WalletCoreCommon.framework/WalletCoreCommon \
      -lc++ -framework Foundation -framework Security -framework CoreFoundation
```

Result: **19 720 768 bytes** (vs 26 172 096 for upstream's device slice), 464 `T _TW…` symbols plus `_wcf_build_info`, and `otool -L` shows dependencies on `libc++.1`, `Foundation`, `Security`, `CoreFoundation`, `libSystem` **only** — no `libswift*`, no `WalletCoreSwiftProtobuf`.

**[INFERENCE]** Three things follow, and they are the load-bearing evidence for DECISION-9:

1. A host macOS library good enough for `melos run test:native` can be produced from release asset 3 with no upstream source build and no network beyond the release download.
2. The build-identity symbol can be linked *into the same library* on Apple platforms. A separate companion library — Option A as briefed — is not the only way to satisfy PRD §12.3 there, and a single library avoids the question of what happens when the companion and the real library get separated.
3. The result is smaller than upstream's own iOS slice and carries none of the Swift/UIKit/SwiftProtobuf linkage of §2.4, because it links only what the 464 C entry points reach.

Caveats, stated as such: this was one host, one architecture, one toolchain, debug-unstripped, not signed, not run on a device, and the produced libraries were not compared against upstream's for behaviour beyond the single call above. The archives' internal structure is undocumented and upstream publishes no checksum for asset 3 (§1), so this path can break at any future tag without notice.

---

## 5. Host library for `test:native`

**[METADATA]** None of the 8 release assets is a Linux artifact of any kind — no `.so`, no `.deb`, no `linux-x86_64` tarball. `wallet-core` ships no host library for Linux at 4.8.0.

**[MEASURED]** For macOS the answer is different from what the brief anticipated: a macOS binary *does* exist, inside asset 3, as the `macos-arm64_x86_64` static slice of `WalletCoreCommon.xcframework` (§4.3). It is not directly loadable — it is an `ar` archive — but §4.4 shows one `clang -dynamiclib` invocation turns it into a `.dylib` that Dart FFI opens and calls, carrying all 464 symbols and our identity symbol.

What building a host library from the tarball entails, concretely: download asset 3 (54 MB), extract, `lipo -thin` the host architecture out of the macOS slice, generate the `-u` list from the headers (which T1.4/T1.5 already produce), link against `libc++` + `Foundation` + `Security` + `CoreFoundation`. No Rust toolchain, no CMake, no protoc, no boost. On an Intel macOS runner the same works with `-arch x86_64`; the archive is universal.

**[INFERENCE]** For Linux CI there is no shortcut — a Linux host library requires a full from-source build at the pinned commit (`tools/install-dependencies`, `tools/generate-files`, CMake, Rust), which is what `linux-ci.yml` does upstream. Since the canonical gate table already names `test:native` as macOS-only ("unit tests that load the real native library on the host (macOS)"), the macOS path above is sufficient for the gate as written.

---

## 6. 16 KB page alignment

**[MEASURED]** Nothing can be checked today: **no `.so` file exists anywhere in the 8 release assets, in the `.tar.xz`, or in the xcframework zip.** 16 KB alignment is an ELF/Android property and there is no ELF object in anything upstream publishes on GitHub Releases at 4.8.0. This check is therefore blocked until T1.2 produces an Android `.so`.

The check, for the record, so T1.2 and T1.19 implement the same one. For every 64-bit ABI (`arm64-v8a`, `x86_64`):

```
$ $ANDROID_NDK/toolchains/llvm/prebuilt/<host>/bin/llvm-readelf -l libTrustWalletCore.so
```

Every `LOAD` program header's `Align` column must read `0x4000` (16384). `0x1000` (4 KB) means the library will not load on a 16 KB-page Android device. The fix is a link flag on every 64-bit target — `-Wl,-z,max-page-size=16384` — which NDK r27 and later apply by default and earlier NDKs do not; **[INFERENCE]** our CI must pin NDK r27 or newer, and upstream's `android-ci.yml` pinning `ndk: 23.1.7779620` (in its emulator step) is not a version we can inherit.

**[MEASURED]** `llvm-readelf` is present in the locally installed NDKs (`28.0.12674087/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-readelf`); NDK versions 21.4.7075529, 25.1.8937393, 26.3.11579264, 27.0.12077973, 28.0.12674087 are installed on this machine. Plain `readelf` and `llvm-readelf` are **not** on `PATH` on macOS, so the check must invoke the NDK-qualified path.

PRD §12.2 step 8 also requires the packaged APK/AAB to preserve the alignment (`zipalign -c -P 16 -v`), which is likewise blocked until an artifact exists.

---

## 7. Protos, headers, and `registry.json` — where they actually live

**[MEASURED]**

| Input T1.1/T1.3/T1.4/T1.5 need | In the 8 release assets? | In `TrustWalletCore-4.8.0.tar.xz`? | In `WalletCore.xcframework.zip`? |
|---|---|---|---|
| `src/proto/*.proto` | no | **no** — `find … -name '*.proto'` returns 0 | no — returns 0 |
| `registry.json` | no | **no** — `find … -name registry.json` returns 0 | no — returns 0 |
| `include/TrustWalletCore/*.h` | only inside assets 3 and 6 | yes, 143 files | yes, 85 files per slice (the function surface; §4.2) |
| `tools/`, `android/`, `rust/`, `src/`, CMake | no | no | no |

**[INFERENCE and REQUIREMENT for T1.1]** The protobuf schemas and the coin registry exist **only in the git tree**. `T1.1` must fetch the git tree at commit **`d692ac27749d0c615e17c751b70ab4f0aa75c59b`** — `git clone --depth 1 --branch 4.8.0` or the GitHub source archive for that commit — and must **not** try to satisfy PRD §15.2's "pin → fetch" stage from a release asset. Concretely, `src/proto/` and `registry.json` come from the git tree; `include/TrustWalletCore/` may come from either the git tree or asset 3 and the two should be compared, since `schemas.headers_sha` in `compat_manifest.json` (PRD §15.3) must name one of them unambiguously.

---

## 8. Consolidated findings

| # | Finding | Basis |
|---|---|---|
| F1 | Release 4.8.0 has 8 assets, not 19. | [METADATA] |
| F2 | The iOS xcframework is **dynamic** (`MH_DYLIB`, `@rpath` install name), device + simulator, iOS 13 minimum. The PRD's "static xcframework" assumption is wrong at this tag. | [MEASURED] |
| F3 | It exports exactly the 464 `TW*` C functions its headers declare — no visibility gap on iOS. | [MEASURED] |
| F4 | It hard-depends on `WalletCoreSwiftProtobuf.framework` and on the Swift runtime; a consumer must embed two frameworks. | [MEASURED] |
| F5 | Device slice unsigned, simulator slice ad-hoc signed, no bitcode, no privacy manifest. | [MEASURED] |
| F6 | No artifact carries a usable version/commit symbol; the only version strings say `…-1`. | [MEASURED], corroborating the orchestrator's [VERIFIED] fact |
| F7 | **No Android artifact exists on GitHub Releases**; upstream's Android binary is on GitHub Packages behind a token (README line 48), group `com.trustwallet.walletcore`. | [METADATA] |
| F8 | The only Android path open to us is building from the git tree with `tools/android-build`, against which issue #4638 reports missing FFI symbols at v4.5.0. | [METADATA] |
| F9 | `TrustWalletCore-4.8.0.tar.xz` is not source: License + 219 Swift files + 143 headers + static archives. 0 protos, 0 registry.json, no `tools/`. | [MEASURED] |
| F10 | That tarball contains a **macOS** static slice with all 464 symbols and the Rust components already compiled in. | [MEASURED] |
| F11 | One `clang -dynamiclib` turns that slice into a loadable `.dylib` **with our `wcf_build_info()` linked in**, opened and called successfully from Dart FFI. The same works for `ios-arm64`, producing a 19.7 MB Swift-free dylib. | [MEASURED] |
| F12 | 16 KB alignment cannot be checked at all today — there is no ELF object in anything upstream ships. | [MEASURED] |
| F13 | Protos and `registry.json` are git-tree-only; T1.1 must fetch commit `d692ac27…`. | [MEASURED] |

The recommendation these findings support is in [`DECISION-9.md`](../DECISION-9.md).
