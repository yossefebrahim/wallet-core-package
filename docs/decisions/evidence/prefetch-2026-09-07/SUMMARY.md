# Pre-fetched upstream evidence (orchestrator, 2026-09-07, via gh CLI)

Source repo: trustwallet/wallet-core. Files in this directory hold the raw outputs; this summary is pasted into the T0.4 / T0.5 briefs so the implementers can work offline.

## Release 4.8.0 (published 2026-08-28T11:04:23Z)
Tag object: d692ac27749d0c615e17c751b70ab4f0aa75c59b
Assets (8, not 19 as the PRD assumed): see release-assets-4.8.0.tsv
- kdoc.zip (2.2 MB), Package.swift (912 B), TrustWalletCore-4.8.0.tar.xz (54 MB — NOT a source tarball: see below), WalletCore.doccarchive.zip (114 MB), WalletCore.xcframework.dSYM.zip (98 MB), WalletCore.xcframework.zip (32 MB), WalletCoreSwiftProtobuf.xcframework.dSYM.zip (6.7 MB), WalletCoreSwiftProtobuf.xcframework.zip (3.3 MB)
- NO Android artifact (no .aar, no per-ABI .so) on GitHub Releases.
- Package.swift declares SPM binary targets with sha256 checksums: WalletCore.xcframework.zip = 0c79df1a901a3abfbccee5052229984b1e743696483176b3cfb68eaf90f400bc; WalletCoreSwiftProtobuf.xcframework.zip = 6098237d99dc609cc1ee5a8fe9c9cf0b90fb06ae739f42a51e3dbdbb1f18ec37. Platform iOS 13+.

## Android distribution
README @4.8.0 line 48: "Android releases are hosted on GitHub packages (https://github.com/trustwallet/wallet-core/packages/700258), you need to add GitHub access token to install it." Gradle group com.trustwallet.walletcore (android/gradle.properties). Consequence: an unauthenticated consumer or build hook cannot fetch the Android library from upstream; our native package must mirror or build (PRD §12.3, DECISION-9).
Issue #4638 (open, 2026-01-29): a Flutter user building the .aar from source with tools/android-build hit missing FFI symbols (TWAnyAddressIsValid undefined) at v4.5.0 — symbol visibility in the Android build is a risk for Option B.

## Upstream flutter/ directory (DECISION-8)
- Single commit touching flutter/: 11bd2fba, 2025-06-09, gupnik, "Adds flutter bindings (#4412)" (PR #4412 merged 2025-06-04). No later commits.
- Contents @4.8.0: .gitignore, CHANGELOG.md, README.md, analysis_options.yaml, bin/, config.yaml (ffigen), include -> symlink, lib/, pubspec.lock, pubspec.yaml, test/.
- pubspec.yaml: name "flutter", description "A sample command-line application.", version 1.0.0, sdk ^3.8.1, deps ffi ^2.1.4, path ^1.9.1; dev ffigen ^19.0.0, lints ^5.0.0, test ^1.24.0. README: "Wallet Core Bindings for Flutter", install Dart SDK, dart pub get, dart run, dart test.
- flutter-ci.yml exists @4.8.0: builds native, generates files, sets up Dart 3.8.1, runs in flutter/ (see upstream-flutter-ci.yml).
- Main README @4.8.0 line 120 lists the community project "Flutter binding https://github.com/weishirongzhen/flutter_trust_wallet_core" under non-official bindings; open PR #4634 (Toby1009, 2026-01-23, docs only) proposes changing that reference — see upstream-pr-4634.diff.
- Related history: issue #1791 "Dart FFI support" (closed, 2021-11), issue #2086 "Functions are not exposed to dart.ffi" (closed, 2022-03), PR #2033 added visibility("default") to TWString.h (merged 2022-02).

## Workflows @4.8.0
android-ci.yml, claude-bc-risk-router.yml, codegen-v2.yml, docker.yml, flutter-ci.yml, ios-ci.yml, kotlin-ci.yml, kotlin-sample-ci.yml, linux-ci-sonarcloud.yml, linux-ci.yml, linux-sampleapp-ci.yml, rust.yml, wasm-ci.yml. Android/Kotlin publish details: see grep results recorded in the orchestrator's session log; the release-on-tag publishing path was not among these files' names.

## pub.dev name availability (pubdev-names.tsv, checked 2026-09-07 via https://pub.dev/api/packages/<name>)
All three planned names (wallet_core_flutter, wallet_core_flutter_bindings, wallet_core_flutter_native) are FREE. Taken: wallet_core (fuse.io), wallet_core_bindings (the PRD §3 competitor, version 4.8.0), flutter_trust_wallet_core, trust_wallet_core.

## How this directory is used
Raw inputs pre-fetched by the orchestrator (plan §2.2 step 3) so that T0.4, T0.5, T0.6, T0.9 can run without network. Files here are never edited by a task; tasks write their own evidence files beside this directory.

## Local downloads (orchestrator, 2026-09-07, user-approved; `gh release download`)
Location: ~/.cache/wcf-upstream/4.8.0/ (outside the repo; SHA256SUMS file beside them)
- WalletCore.xcframework.zip — 32000472 bytes — sha256 0c79df1a901a3abfbccee5052229984b1e743696483176b3cfb68eaf90f400bc — MATCHES Package.swift's SPM checksum
- TrustWalletCore-4.8.0.tar.xz — 53949676 bytes — sha256 30b0532d9f143b6409aa405f3ba124625fb01e70f13d8e52b3904334c617ff60 (no upstream checksum published for it; recorded here as first-seen)
Listings: xcframework-4.8.0-listing.txt (unzip -l), source-tarball-4.8.0-toplevel.txt (tar -t, top two levels).

## Correction: TrustWalletCore-4.8.0.tar.xz is a binary iOS distribution, not source
`tar -t` shows only ./License, ./Sources, ./include, ./WalletCoreCommon.xcframework (see source-tarball-4.8.0-toplevel.txt). It contains 0 .proto files, no registry.json, no tools/, no android/. It is the CocoaPods-style payload. Consequence: protos, registry.json, headers-as-source, and the Android build scripts must come from the git tree at tag 4.8.0 (commit d692ac27749d0c615e17c751b70ab4f0aa75c59b) — `git clone --depth 1 --branch 4.8.0` or the GitHub source archive — which is T1.1's job (PRD §15.2 pin → fetch). The xcframework zip carries 143 headers under each slice's Headers/ (xcframework-4.8.0-listing.txt); slices: ios-arm64 (device) and ios-arm64_x86_64-simulator; Info.plist saved as xcframework-4.8.0-Info.plist.
- WalletCore.xcframework Info.plist: two libraries, both `LibraryPath WalletCore.framework`, `BinaryPath WalletCore.framework/WalletCore`: ios-arm64 (device; binary 26.2 MB) and ios-arm64_x86_64-simulator (binary 54.0 MB). Static vs dynamic must be read from the Mach-O header (T0.5: `file`/`otool -hv` after extracting under a temp dir).
- Inside TrustWalletCore-4.8.0.tar.xz: `WalletCoreCommon.xcframework` with slices ios-arm64, ios-arm64_x86_64-maccatalyst, ios-arm64_x86_64-simulator, **macos-arm64_x86_64**; `Sources/` = 221 Swift files (206 under Generated/, plus TWData.swift, TWString.swift, AnySigner.swift, KeyStore*.swift, Wallet.swift, Watch.swift, TWCardano.swift, Extensions/, Types/); `include/TrustWalletCore/` = 143 C headers. T0.5 must determine whether WalletCoreCommon's macOS slice carries the TW* C symbols — if so it is a candidate host library for `melos run test:native` (T1.6) without building from source.

## upstream-src/ (fetched 2026-09-07 at commit d692ac27749d0c615e17c751b70ab4f0aa75c59b = tag 4.8.0)
`registry.json` (the coin registry), `proto/{Bitcoin,BitcoinV2,Solana,Ethereum,Common,Cosmos}.proto`, and headers `TWAnySigner.h`, `TWTransactionCompiler.h`, `TWHDWallet.h`, `TWCoinType.h`, `TWDerivation.h`, `TWData.h`, `TWString.h`, `TWPrivateKey.h`, `TWAnyAddress.h`. Read-only inputs for T0.11 (DECISION-11 facade over the registry; DECISION-13 key fields and output shapes) and for T1.x briefs. These are upstream Apache-2.0 files kept here as evidence; the pinned working copy for generation is T1.1's `third_party/` checkout, not this directory.
