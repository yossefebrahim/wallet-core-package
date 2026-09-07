# Upstream Security Audits

This document lists published third-party security audits and reviews of the upstream `trustwallet/wallet-core` repository. It defines what these audits do and do not cover, serving as evidence for [PRD §16 S1](../../wallet_core_flutter_prd.md) so that this project's docs can state precisely what upstream audits cover without over-claiming.

## Audits found

### Kudelski Security Audit
* **Performer:** Kudelski Security, Inc.
* **Date:** September 15, 2023 (Version 2.0)
* **Upstream version / commit range covered:** Commit `502878aadcac340b98c8619dd8e141dec94b1ad5` (specifically `Key_pairs.rs`). Also covers external Rust dependencies (`starknet-crypto`, `starknet.curve`, `starknet-ff`).
* **Components covered:** Rust layers related to key pairs and StarkNet cryptography.
* **Findings summary:** 9 findings reported (KS-TW-01 through KS-TW-09).
* **Public URL:** [2023-09-15_TrustWallet_SecureCodeReviewReport_Public_v2.00.pdf](https://github.com/trustwallet/wallet-core/blob/master/audit/2023-09-15_TrustWallet_SecureCodeReviewReport_Public_v2.00.pdf) (Accessed: 2026-09-07)
* **How found:** Located in the official `trustwallet/wallet-core` repository's `audit/` directory.

### Community-submitted security review filed as GitHub issue #4706
* **Performer:** Self-described audit by an individual contributor (mefai-dev), open and unlabeled, with 0 comments and no maintainer response captured as of 2026-09-07.
* **Date:** March 20, 2026
* **Upstream version / commit range covered:** `master` branch at the time of the report (prior to fix PRs).
* **Components covered:** C++ core cryptographic and utility implementations (e.g., `PrivateKey.cpp`, `HDWallet.cpp`, `interface/TWData.cpp`, `Keystore/AESParameters.cpp`).
* **Findings summary:** 12 findings reported (covering AES padding, C++ `std::fill` vs `memzero`, bounds validations, and curve order validation). The issue itself excludes findings already fixed in the merged PRs it lists.
* **Public URL:** [Issue #4706](https://github.com/trustwallet/wallet-core/issues/4706) (Accessed: 2026-09-07)
* **How found:** Discovered via GitHub API search for issues mentioning "audit" in the `trustwallet/wallet-core` repository; referenced by integrators in issue #4834.

## Not found / not verifiable

Claims of audits by CertiK, Halborn, Cure53, Quantstamp, Least Authority, and Sigma Prime appear in blogs, forums, and GitHub issue comments (e.g., issue #4834 mentions a CertiK report). However, no public reports linked directly to the `wallet-core` codebase were found in the repository or through public web searches. These claims remain unverifiable for the specific `wallet-core` scope.

## Security advisories

* **Identifier:** GHSA-7g72-jxww-q9vq
* **Publication date:** 2024-12-10T19:09:47Z
* **Severity:** Critical
* **Affected versions:** `ed25519-dalek` < 2.0.0
* **Fixed version:** 2.0.0
* **Summary:** Key exposure attack in secret.rs
* **URL:** [GHSA-7g72-jxww-q9vq](https://github.com/trustwallet/wallet-core/security/advisories/GHSA-7g72-jxww-q9vq) (Accessed: 2026-09-07)

## What none of the audits cover

The scope of upstream audits applies to Trust Wallet Core's C++ and Rust implementations. Factually, for this project's scope, none of the audits cover:
* Dart FFI glue
* Protobuf construction and serialization in Dart
* Artifact acquisition and loading mechanisms
* Our background signing worker model
