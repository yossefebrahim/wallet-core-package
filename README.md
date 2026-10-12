# wallet_core_flutter

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

Status: pre-alpha, nothing published.

## Verified support

<!-- matrix-counts -->

**167 chains generated, 167 exposed, 3 tested.** Per-coin detail is in the [capability matrix](docs/capability_matrix.md), which names the exact variants verified.

3 of 167 chains have at least one variant tested on both Android and iOS. Testing is per variant; the table below lists which.

A chain counts at a level when at least one of its operations has a variant at that level. The levels, as the matrix defines them:

- **generated** — the coin's protobuf (or the T2.9 probe evidence) defines the operation and the registry lists the coin. Produced mechanically; says nothing about the SDK.
- **exposed** — the public SDK offers a typed or generic path, and no vector for this exact variant is confirmed on both Android and iOS.
- **tested** — a known-answer vector for this exact variant lists both `android` and `ios` in `platforms_verified`, and `matrix:check` confirms it against the CI results.

Per variant, in chains (upstream 4.8.0, commit `d692ac27749d0c615e17c751b70ab4f0aa75c59b`):

| operation | family | variant | generated | exposed | tested |
|---|---|---|---|---|---|
| address | evm | n/a | 60 | 60 | 0 |
| address | utxo | n/a | 14 | 14 | 1 |
| address | solana | n/a | 1 | 1 | 1 |
| address | other | n/a | 92 | 92 | 0 |
| sign | evm | legacy | 60 | 60 | 0 |
| sign | evm | eip1559 | 60 | 60 | 1 |
| sign | evm | contract_call | 60 | 60 | 0 |
| sign | utxo | p2pkh | 14 | 0 | 0 |
| sign | utxo | p2wpkh | 14 | 1 | 1 |
| sign | utxo | taproot | 14 | 0 | 0 |
| sign | utxo | multi_input | 14 | 1 | 1 |
| sign | solana | legacy | 1 | 1 | 1 |
| sign | solana | versioned | 1 | 0 | 0 |
| sign | other | any | 92 | 0 | 0 |
| sign_message | evm | personal | 60 | 60 | 1 |
| sign_message | evm | eip712 | 60 | 60 | 1 |
| sign_message | solana | personal | 1 | 0 | 0 |
| sign_message | other | any | 2 | 0 | 0 |
| plan | utxo | p2pkh | 14 | 0 | 0 |
| plan | utxo | p2wpkh | 14 | 1 | 1 |
| plan | utxo | taproot | 14 | 0 | 0 |
| plan | utxo | multi_input | 14 | 1 | 1 |
| plan | other | any | 14 | 0 | 0 |
| compile | evm | legacy | 60 | 0 | 0 |
| compile | evm | eip1559 | 60 | 0 | 0 |
| compile | evm | contract_call | 60 | 0 | 0 |
| compile | utxo | p2pkh | 14 | 0 | 0 |
| compile | utxo | p2wpkh | 14 | 0 | 0 |
| compile | utxo | taproot | 14 | 0 | 0 |
| compile | utxo | multi_input | 14 | 0 | 0 |
| compile | solana | legacy | 1 | 0 | 0 |
| compile | solana | versioned | 1 | 0 | 0 |
| compile | other | any | 83 | 0 | 0 |

<!-- /matrix-counts -->

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

Two pages describe how the SDK behaves as of `0d7e274` (the EVM signing path, with the Phase 1 changes up to T1.R2b):

- [Memory Contract](docs/security/memory_contract.md): where mnemonics, passphrases, entropy and private keys exist in memory, including during signing. It says which copies this SDK overwrites, which upstream overwrites, and which nobody overwrites as far as the sources show. The default API never returns private-key bytes.
- [Lifecycle](docs/security/lifecycle.md): proxies and internal handles, finalizers, session states, the errors `initialize()` can throw, scopes, deadlines, failures and shutdown.

Both pages describe behaviour and its limits. Neither promises a security property.
<!-- /memory-contract -->
