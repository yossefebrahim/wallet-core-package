# wallet_core_flutter

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

Status: pre-alpha, nothing published.

## Verified support

<!-- matrix-counts -->

## Documentation

- Product requirements: [docs/wallet_core_flutter_prd.md](docs/wallet_core_flutter_prd.md)
- Execution plan: [docs/plan/EXECUTION_PLAN.md](docs/plan/EXECUTION_PLAN.md)

## Packaging

The native library reaches an app through a Flutter build hook in `wallet_core_flutter_native` (DECISION-2): at build time the hook verifies the library for each target against the checksum-pinned manifest the package ships, downloading it from the project's release only when it is not already cached or vendored, and bundles it into the app. There is no Gradle, CocoaPods or Xcode step for the library itself. Two things are the app's to do:

- **Android:** build release APKs and app bundles with `--target-platform android-arm64,android-x64`. Only those two ABIs are shipped, and a default build is refused with that remedy.
- **iOS:** add the library's two required-reason API categories (file timestamp, system boot time) to the app's own `PrivacyInfo.xcprivacy` in the Runner target. The package does not ship a privacy manifest and, as a build-hook package, cannot.

Details, the step-by-step Runner-target edit and the offline/vendored build options: [packages/wallet_core_flutter_native/README.md](packages/wallet_core_flutter_native/README.md#consumer-setup).

<!-- memory-contract -->
### Memory and Lifecycle

Two pages describe how the SDK behaves as of task T1.12 (EVM signing):

- [Memory Contract](docs/security/memory_contract.md): where mnemonics, passphrases, entropy and private keys exist in memory, including during signing. It says which copies this SDK overwrites, which upstream overwrites, and which nobody overwrites as far as the sources show. The default API never returns private-key bytes.
- [Lifecycle](docs/security/lifecycle.md): proxies and internal handles, finalizers, session states, the errors `initialize()` can throw, scopes, deadlines, failures and shutdown.

Both pages describe behaviour and its limits. Neither promises a security property.
<!-- /memory-contract -->
