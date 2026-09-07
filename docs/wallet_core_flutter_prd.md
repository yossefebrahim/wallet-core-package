# PRD — `wallet_core_flutter`: A Permissively-Licensed, Unofficial Dart/Flutter SDK over Trust Wallet Core

| | |
|---|---|
| **Status** | Draft v1.2.1 (supersedes Draft v1.2; Phase 0 evidence corrections, see §26) |
| **Author** | Yossef Ebrahim |
| **Date** | September 7, 2026 (v1.1: September 6, 2026) |
| **License** | MIT (package code); upstream Trust Wallet Core is Apache 2.0 |
| **Target platforms (v1.0 release)** | Android, iOS |
| **Upstream** | [trustwallet/wallet-core](https://github.com/trustwallet/wallet-core) — latest tag 4.8.0 at time of writing |
| **Relationship to Trust Wallet** | Unofficial community project. Not affiliated with or endorsed by Trust Wallet. |

---

## 0. How to read this document

Every substantive statement carries one of these labels so that proposals are never mistaken for guarantees:

| Label | Meaning |
|---|---|
| **[REQ]** | A requirement. The release is not done until it is met and tested. |
| **[REC]** | A recommendation or preferred approach. May be replaced if the spike shows a better option. |
| **[VERIFIED]** | A fact checked against a primary source on the date in §24. Still re-verify before publishing. |
| **[UNVERIFIED]** | A claim we believe but have not confirmed against a primary source. Do not repeat it in README/marketing until verified. |
| **[DECISION-n]** | An unresolved decision. Owner, deadline, and options are listed in §22. |

Changes from v1.0 are summarized in §23; changes from v1.1 (architecture audit) in §25.

## 1. Summary

`wallet_core_flutter` is an open-source, MIT-licensed, **unofficial** Dart/Flutter SDK over Trust Wallet Core. It provides mnemonic generation, HD key derivation, address derivation, and transaction/message signing for the blockchains wallet-core supports, on Android and iOS first, through generated bindings **plus** a typed, high-level Dart API.

Five things stay fixed from v1.0:

1. **All cryptography is upstream.** The SDK never implements key generation, hashing, or signing. It delegates every sensitive operation to wallet-core's C interface.
2. **Offline by design.** The SDK makes no network calls at runtime.
3. **Generated bindings.** The C API, protobuf models, and coin registry are generated from the pinned upstream tag, never hand-written.
4. **High-level Dart API.** Typed wallets, accounts, transaction requests, signers, errors, and lifecycle management sit on top of the bindings and are the product.
5. **Automated upstream synchronization.** A new upstream release is absorbed by regenerating, rebuilding, and re-testing, with a human approving publication.

What changes in v1.1 is precision: package boundaries are defined, the memory-safety and secret-handling story is stated with its real limitations, native packaging is evaluated before it is chosen, "exposed" is separated from "verified" per chain and per operation, background signing has an ownership model, and the first milestone is tightened so that the whole pipeline is proven before convenience APIs grow.

## 2. Background & Problem

**[VERIFIED]** Trust Wallet Core is an open-source (Apache 2.0) C++ library with strict C interfaces, supporting 130+ blockchains, with official idiomatic bindings for Swift (iOS) and Java/Kotlin (Android), plus JavaScript/WebAssembly, Go (beta), and Kotlin Multiplatform (beta). Upstream ships releases frequently (multiple releases per month in the observed history).

**[VERIFIED]** The upstream repository contains a `flutter/` directory titled "Wallet Core Bindings for Flutter" with a runnable app and tests. Its README gives setup and run instructions only; it contains no support statement, no platform matrix, and no description of how the bindings are generated or released. It is not published to pub.dev. The main README lists official bindings (Swift, Kotlin, JS/WASM, Go beta, KMP beta) and separately points to community-maintained projects, including a Flutter binding, with an explicit "not an endorsement" note; **[VERIFIED 2026-09-07]** that pointer refers to an external project (`weishirongzhen/flutter_trust_wallet_core`; open PR #4634 would repoint it to `xuelongqy/wallet_core_bindings`), not to the in-tree directory (DECISION-8, E7–E8).

**Interpretation:** upstream has a Flutter/Dart *sample or in-tree binding*, but it is not a supported, published, production-ready Flutter SDK. **[UNVERIFIED]** whether upstream intends to develop it further — checked 2026-09-07 (DECISION-8): one commit (2025-06-09, PR #4412), no README entry, no publication, no maintainer statement found, CI regenerates it as a build smoke check; the dated negative is recorded and the question stays open with revisit triggers in the upstream watcher, because if upstream ships an official Flutter SDK the value of this project shrinks to "permissive license + DX".

**The gap:** a Flutter team building a **closed-source commercial wallet** today must choose between an AGPL-licensed community binding (with commercial licensing on request), the unsupported upstream sample, abandoned packages, hand-written bindings, or platform-channel code over the Swift/Kotlin SDKs. None is a maintained, permissively-licensed, documented Dart SDK.

## 3. Landscape (verified against primary sources; see §24 for dates)

| Package | Latest | Status | License | Platforms | Notes |
|---|---|---|---|---|---|
| `flutter_trust_wallet_core` | 0.0.1 (Dec 2020) | Abandoned; flagged Dart 3 incompatible on pub.dev | **[UNVERIFIED]** (not read) | Android, iOS | **[VERIFIED]** version/date/Dart-3 flag |
| `trust_wallet_core_lib` | 0.0.7+3.0.4 (Feb 2021) | Inactive | MIT **[VERIFIED]** | Android (minSdk 23), iOS 13+ | Wraps the API list of a 2021 wallet-core |
| `wallet_core_bindings` (+ `_native`, `_libs`, `_wasm`, `_wasm_assets`) | 4.8.0 (Aug 30, 2026) | Actively maintained | **AGPL-3.0 [VERIFIED]**; README mentions commercial licensing on request | Android, iOS, macOS, Linux, Web, Windows (native FFI on the first four; WASM for all) | **[VERIFIED]** README claims: "TrustWalletCore include files and Protobuf file bindings", "APIs are repackaged for easier use", "Combined with Dart GC, there is no need to control memory". Unverified uploader; 140 pub points. |
| Upstream `flutter/` directory | one commit (2025-06-09, PR #4412), unchanged at 4.8.0; CI regenerates the bindings from current headers on every run | In-tree Dart console sample, unpublished, no support statement | Apache 2.0 (upstream repo) | **[VERIFIED 2026-09-07]** (DECISION-8) | See §2 |

**Correction from v1.0:** `wallet_core_bindings` is **not** merely raw C bindings. It ships generated protobuf classes and a repackaged Dart API, and it relies on Dart GC for memory management. Our differentiation must therefore rest on license, an explicitly designed and documented public API with a stated memory/secret contract, and verified per-chain capability — not on "they only have raw bindings".

## 4. Opportunity & Positioning

> **An MIT-licensed, unofficial Dart SDK for Trust Wallet Core, with verified capability and automated upstream tracking.**

Differentiators:

1. **License.** MIT package code over Apache 2.0 upstream. Whether AGPL obligations apply to a given closed-source app is a legal question that depends on how the app is distributed and linked; **this document makes no legal claim about AGPL**, and README/marketing must not either. The verifiable statement is: *our* license is MIT, and the competitor's is AGPL-3.0 with commercial terms on request. Teams decide with their own counsel.
2. **Designed public surface.** A stable, typed public API with explicit lifecycle and error types, raw pointers kept out of the default import, and a documented secret-handling contract (§11) rather than "GC handles it".
3. **Verified capability, not just exposure.** A published capability matrix (§13) states, per chain and per operation, whether support is generated, exposed, or tested against known vectors.
4. **Transparent supply chain.** Pinned upstream commit, generator versions, artifact checksums, and (as a separate, later requirement) demonstrated reproducibility (§12, §15).

**Qualification on audits:** **[VERIFIED 2026-09-07]** the only published third-party report is Kudelski Security's 2023 secure code review of Rust StarkNet key-pair code (upstream `audit/`), and upstream has published one repository security advisory (GHSA-7g72-jxww-q9vq, `ed25519-dalek`); claims of other audits are unverified (`docs/decisions/evidence/upstream-audits.md`). An upstream audit does **not** cover this binding: the FFI glue, protobuf construction in Dart, artifact acquisition, and the signing worker are ours and need their own review (§16).

Secondary opportunity: upstream's documentation references community-maintained projects, so a well-maintained, correctly-disclaimed binding is a plausible candidate for that listing.

## 5. Goals

- **G1 — Complete exposure, honest verification.** [REQ] Generate the complete C API surface and all protobuf models of the pinned upstream tag. [REQ] Publish a capability matrix that distinguishes *generated*, *exposed*, and *tested* support per chain and per operation (§13). Exposure alone is never described as "support".
- **G2 — Typed, safe public API.** [REQ] Wallet creation/import, account and address derivation, transaction requests, signing, validation, disposal, and typed errors without touching pointers or protobuf. [REQ] Advanced access to bindings is available only through an explicit import.
- **G3 — Automated upstream synchronization.** [REQ] A new upstream tag can be absorbed by running the pipeline (regenerate → rebuild → test → diff report) with no hand-edits to generated files, followed by human-approved publication. Target lag: **[REC]** under 7 days median, re-estimated after M2.
- **G4 — Precise security posture.** [REQ] A written secret-handling contract with stated guarantees *and* stated limitations (§11), explicit disposal, checksum-verified native artifacts, no network, and a security review of the glue layer before 1.0 (§16).
- **G5 — Adoption.** Become a credible default for new Flutter wallet projects that need a permissive license (§20).

## 6. Non-Goals (v1.0 release)

- Desktop (macOS/Linux/Windows) and Web (WASM). Deferred; architecture must not preclude them (the `native` package boundary is designed so a `wasm` sibling can be added).
- Networking of any kind: RPC, balances, broadcasting, fee estimation, prices. The SDK signs; it does not talk to chains.
- UI, QR, secure-storage implementations. We *document* secure-storage patterns; we do not ship them.
- Our own cryptography, key derivation, or serialization of signed transactions.
- Forking wallet-core. We consume tagged upstream source/artifacts; patches go upstream.
- Guaranteeing that every copy of a secret in process memory is erased (see §11 — this is explicitly *not* something Dart can promise).

## 7. Target Users

- **P1 — Commercial wallet teams** (fintech, exchange, startup): license clarity, security contract, verified chain coverage, upstream freshness.
- **P2 — Web3 app developers** embedding signing/derivation: fast integration, typed API, cookbook docs.
- **P3 — Open-source and hobbyist developers**: examples, no-fee permissive license, readable code.

## 8. Package Architecture

Three packages in one melos-managed monorepo. Boundaries are a **[REQ]**; the names are **[REC]** pending pub.dev availability (§17).

| Package | Owns | Must not contain |
|---|---|---|
| **`wallet_core_flutter`** — Public SDK | Stable, typed wallet/account/address APIs; transaction request types; signer interfaces and implementations; input validation; lifecycle (`dispose`, scopes, signing worker); typed error hierarchy; chain-family helpers (§10) | Raw `Pointer`s or generated symbols in its default export; artifact downloading; platform build logic |
| **`wallet_core_flutter_bindings`** — Bindings | `ffigen` output over `include/TrustWalletCore/*.h`; Dart protobuf classes from `src/proto/*.proto`; coin registry metadata from `registry.json`; thin ownership wrappers for `TWData`/`TWString` (create, borrow, delete) | Hand-written business logic; chain helpers; anything that requires a design decision rather than generation |
| **`wallet_core_flutter_native`** — Native distribution | Artifact acquisition from the release store; SHA-256 verification against the compatibility manifest; build integration (build hook *or* platform packaging, §12); library loading and symbol lookup; `libc++_shared` handling on Android | Dart API; protobuf; anything a consumer imports directly |

Dependency direction: `wallet_core_flutter → bindings → native`. Consumers depend on the SDK only.

**Public import rules [REQ]:**

- `package:wallet_core_flutter/wallet_core_flutter.dart` exports the typed SDK only. No `dart:ffi` types, no generated `TW*` classes, no protobuf classes appear in its signatures. The generated `CoinType` enum and registry metadata are likewise not public: the SDK exposes a stable coin/network facade that maps to the pinned registry inside the bindings layer (**[DECISION-11]**), so an upstream rename or removal is absorbed by the mapping instead of becoming an SDK breaking change.
- `package:wallet_core_flutter/advanced.dart` (or the bindings package directly) exposes generated bindings and protobuf for users who accept ownership responsibility. Its docs state that the memory contract of §11 is the caller's responsibility there.
- Chain helpers live inside the SDK, organized by family (`evm/`, `utxo/`, `solana/`, `cosmos/`, …) **[REC]**. Splitting families into separate packages is deferred until binary-size or release-cadence data argues for it (**[DECISION-7]**).

**Versioning [REQ]:** each Dart package carries its own semver reflecting *its own* API compatibility. None of the three packages mirrors the upstream version number in its own version. The mapping between package versions and the exact upstream commit/tag lives in the compatibility manifest (§15), which is shipped inside the packages and published alongside every release. Packages are nevertheless **released as one verified set**: the SDK pins the exact tested versions of `_bindings` and `_native` (not ranges), every package embeds the same manifest hash and release-set id, and `WalletCore.initialize()` fails with `ManifestMismatchError` when the three do not match (§15.4, **[DECISION-14]**).

## 9. Bindings Layer (generated)

- [REQ] `ffigen` runs against the pinned tag's `include/TrustWalletCore` headers and produces bindings for every declared function and enum. Coverage is measured by comparing the generated symbol set against the header symbol set in CI; any missing symbol fails the build.
- [REQ] `protoc` + `protoc-gen-dart` generate Dart classes for every message in `src/proto`. Generator versions are recorded in the manifest.
- [REQ] `registry.json` is transformed into a `CoinType` enum plus metadata (derivation paths, curve, public-key type, symbol, decimals, explorer templates). The transformation is a script under version control; its output is regenerated, never edited. The generated enum lives in the bindings package and reaches consumers only through the advanced import (§8).
- [REQ] Ownership wrappers for `TWData` and `TWString` expose: create-from-bytes, borrow-bytes (copy out), and delete, with the `[REQ]` disposal contract of §11. **[VERIFIED]** upstream's `TWDataDelete` and `TWStringDelete` call `memzero` on the buffer contents before `delete`, and `TWDataReset` fills the buffer with zeros.
- [REQ] The bindings package ships with a generated symbol inventory (function name → present in headers / present in loaded library) so §13's "generated" column is produced mechanically.

## 10. Public SDK Layer (hand-written)

### 10.1 Design targets

The "hello wallet" should stay short, but the example now shows the lifecycle and the request/signer separation:

```dart
import 'package:wallet_core_flutter/wallet_core_flutter.dart';

final wc = await WalletCore.initialize();              // loads native lib once; verifies manifest

final wallet = await wc.wallets.create(strength: 128);        // proxy to a worker-owned HDWallet
try {
  final account = await wallet.account(Coin.ethereum);    // plain descriptor: coin, path, address, public key
  print(account.address);

  final request = EvmTransactionRequest.transfer(       // pure Dart value — no key material
    chainId: 1, nonce: 7, to: '0x…', valueWei: BigInt.from(10).pow(18),
    maxFeePerGas: …, maxPriorityFeePerGas: …, gasLimit: 21000,
  );

  final signed = await wc.signer.sign(request, account); // EvmSignResult (sealed SignResult family, §10.2)
} finally {
  await wallet.close();                                     // explicit and asynchronous; the worker frees the handle (§14.3)
}
```

### 10.2 Surface for the 1.0 release

- **Wallets & keys:** `HDWallet` (create / import mnemonic / import entropy), `Mnemonic` validation and word lists, `PrivateKey`, `PublicKey`, `StoredKey` (encrypted keystore import/export via upstream).
- **Accounts & addresses:** an `Account` is a plain descriptor (coin/network, derivation path, address, public key) that owns no native handle and no key; `Address.parse/validate` for every coin in the registry via `TWAnyAddress` — *exposed* for all coins; *tested* per §13. Network (mainnet/testnet) is explicit wherever upstream supports it; **[VERIFIED]** upstream's registry models EVM networks as separate coins with chain IDs but models Bitcoin testnet only as a derivation entry, so the facade carries that distinction (**[DECISION-11]**).
- **Transaction requests:** immutable Dart value types per family (`EvmTransactionRequest`, `UtxoTransactionRequest`, `SolanaTransactionRequest`, …). [REQ] Requests never contain key material. A request is "what to sign"; a signer decides "with what". UTXO inputs name the key each one needs through a `KeyLocator` (see Signers). The generic `RawSigningInput(coin, protobufBytes)` escape hatch is **not** in the default SDK: arbitrary protobuf bytes can already contain key fields and the SDK cannot prove otherwise, so it lives under `advanced.dart`, where the caller accepts secret-handling responsibility.
- **Signers:** `Signer` interface with `sign(request, keys)`, `signMessage`, and — where upstream supports it — `plan` (UTXO) and `compile` (external-signature compilation via `TWTransactionCompilerPreImageHashes` and `TWTransactionCompilerCompileWithSignatures`, **[VERIFIED]** present in the 4.8.0 headers; per-coin availability **[UNVERIFIED]**). `keys` is a set of `KeyLocator`s (an HD path in a wallet, an imported key, an external-signer key): a single-key chain takes one, a Bitcoin spend takes one per input. **[VERIFIED]** upstream's Bitcoin `SigningInput` declares `repeated bytes private_key`, and Solana's carries `private_key`, `fee_payer_private_key`, and `nonce_account_private_key`, so a one-account signer cannot represent ordinary transactions. Unsupported cases (multisig, partially signed transactions, watch-only accounts) fail with typed errors. Results form a sealed `SignResult` family (`EvmSignResult`, `UtxoSignResult`, `SolanaSignResult`, …) because upstream outputs differ per chain (Bitcoin: encoded bytes plus a transaction-id string; Solana: a string in the requested encoding, base58 by default per `SigningInput.tx_encoding`; Ethereum: raw bytes). The 1.0 implementation is `LocalSigner` (worker-owned keys). The interface is designed so a future `ExternalSigner` (hardware wallet, MPC, remote HSM) can implement it without changing request types (**[DECISION-13]**).
- **Errors:** typed hierarchy — `WalletCoreException` → `InvalidInputError`, `UnsupportedOperationError(coin, capability)`, `SigningError(upstreamCode, message)`, `KeyResolutionError`, `DisposedError` (internal handles) / `ClosedError` (public resources), `WorkerTerminatedError(kind)`, `NativeLoadError`, `ManifestMismatchError(check)`, and — from §14.3 and the facade — `SessionStateError`, `QueueFullError`, `OperationTimeoutError`, `OperationCancelledError`, `UnknownCoinError` (DECISION-11, DECISION-12, DECISION-14; ratified at D0). Upstream's `SigningOutput.error`/`error_message` map to `SigningError`.
- **Lifecycle:** two contracts (§11.2, §14.3). Internal native handles implement synchronous `Disposable`. Public resources owned by the session (`Wallet`, signers) expose an idempotent `Future<void> close()` that asks the worker to free the handle and awaits the acknowledgement; `WalletCore.shutdown()` closes everything and terminates the worker.

[REQ] Convenience helpers beyond Ethereum/EVM, Bitcoin family, and Solana are **not** in scope until M2 exit criteria are met (§18).

## 11. Memory-Safety and Secret-Handling Contract

This section replaces v1.0's blanket promises ("never held in Dart Strings", "zeroized after use"). Those were not achievable as stated. The contract below is what we can guarantee, what we cannot, and what is left to a spike.

### 11.1 Verified facts the contract rests on

- **[VERIFIED]** `TWDataDelete` and `TWStringDelete` `memzero` the *current* buffer of that object before freeing it. `TWDataReset` zero-fills in place.
- **[VERIFIED]** `NativeFinalizer` runs callbacks "as early as possible" after an object becomes unreachable and guarantees them at the latest at isolate-group shutdown, but it "can not be relied upon for running actions on the program's exit" (crash, kill). Timing between those bounds is not guaranteed.
- **[VERIFIED]** Ethereum `SigningInput` and `MessageSigningInput` contain a `private_key` field (`bytes`, 32 bytes). `TWAnySignerSign` takes the serialized `SigningInput` as a `TWData`. Therefore any design that builds the signing input protobuf in Dart puts the private key into Dart-managed memory (the protobuf message object, its serialized `Uint8List`, and any intermediate copies).
- **[VERIFIED]** `TWAnySignerSignJSON(json, key, coin)` accepts the private key as a separate `TWData` argument, keeping the key out of the JSON document; `TWAnySignerSupportsJSON(coin)` reports whether a coin supports that path. **[UNVERIFIED]** which coins return `true`.

### 11.2 Disposal contract [REQ]

This contract governs **internal native handles**: the wrappers in the bindings package and the objects the signing worker owns. Public objects held by the UI isolate are proxies to worker-owned handles and follow the asynchronous close contract of §14.3, because a proxy cannot synchronously free a pointer that lives in another isolate.

1. Every native-backed wrapper exposes `dispose()`. Disposal is the **primary** cleanup path; documentation says so on every such class.
2. On `dispose()`, the wrapper: calls the upstream delete function, **detaches** its `NativeFinalizer` (using the detach key registered at attach time), and marks itself disposed.
3. Double-dispose is a no-op. Any use after disposal throws `DisposedError` (checked at the wrapper boundary, not in native code).
4. Temporary native allocations made during a call (input `TWData`, argument strings, serialized protobuf buffers) are released in `finally` blocks so exceptions cannot leak them.
5. `NativeFinalizer` is attached to every native-backed object as a **fallback** for objects a caller forgot to dispose. Its attach token is the native pointer; the detach key is the Dart wrapper. The finalizer's native callback calls the upstream delete function directly (no Dart code runs in the finalizer callback).
6. Scoped helpers (`wc.scope((s) { … })`) dispose everything created within the scope, exception-safe. [REC] Prefer scopes in cookbook examples.
7. A debug-mode leak tracker reports objects finalized without explicit disposal (counts, creation stack traces).
8. Public proxies attach a Dart `Finalizer` (not `NativeFinalizer`) whose callback posts `Dispose(ref)` to the worker, so a forgotten proxy is still released; a strong-reference map inside the worker alone would keep the handle alive until shutdown.

### 11.3 What "wipe" does and does not mean

- **Guaranteed [REQ]:** when a wrapper is disposed, upstream wipes the buffer *that object currently owns* (§11.1).
- **Not guaranteed, and documented as such [REQ]:** erasure of every copy of a secret. Copies can exist in Dart heap objects (`Uint8List`, `String`, protobuf messages, serialized bytes), in previous native allocations that upstream reallocated internally (e.g. after `TWDataAppend*` growth), in Dart's GC copying/compaction history, in platform keyboard/clipboard buffers, in crash dumps, and in swap. Dart provides no API to pin or securely erase managed memory.
- **Consequences for the API [REQ]:**
  - Mnemonic **export** (`wallet.mnemonic`) returns a Dart `String` by necessity (it is meant to be displayed). Docs state that the string lives until GC and cannot be erased; the recommended pattern is to display it once and drop references.
  - Mnemonic **import** accepts a `String` (user input) and, as soon as the native wallet is created, the SDK drops its own references; it cannot erase the caller's copy or the platform text-input buffers.
  - Private key bytes are exposed to callers only through explicit `advanced` APIs; the default SDK never returns raw private key bytes.
  - SDK docs contain a "What we wipe / what we can't" page. README does not use the words "zeroization" or "secret-free" without linking to it.

### 11.4 Secret material in signing requests — two approaches (spike decision)

Because upstream's signing inputs carry the private key inside the protobuf, the SDK must choose where that protobuf is assembled.

| | **Approach A — Dart-side, minimized** | **Approach B — thin native adapter** |
|---|---|---|
| Mechanism | SDK builds the `SigningInput` in Dart, injects `private_key` bytes obtained from `TWPrivateKeyData`/`TWHDWalletGetKey`, serializes, passes to `TWAnySignerSign`, then overwrites its own `Uint8List` copies with zeros | A small C/C++ shim (ours, compiled with the native package) receives the *key-less* serialized request plus a native private-key handle, inserts the key and serializes inside native memory, calls `TWAnySignerSign`, wipes its own buffers, returns the output |
| Dart-managed secret copies | Yes: protobuf message field, serialized bytes, possibly builder intermediates. Overwriting `Uint8List` contents helps but cannot reach GC-internal copies | None for the private key. The request protobuf still crosses into Dart but contains no key |
| Cryptography location | Upstream | Upstream (shim only assembles bytes; never touches curves) |
| Complexity | Low; pure Dart; works for every coin the same way | Medium: a native build step, a protobuf dependency in the shim (or byte-level field append), and one more component in our security review scope |
| Upstream coupling | Follows generated protobuf; zero native code of ours | Must track every key field per coin proto across upstream versions: **[VERIFIED]** Bitcoin uses `repeated bytes private_key` and Solana has three differently named key fields, so the adapter is per family (generated from the descriptors or explicitly implemented), never a universal "append one field" |
| Alternative path | For coins where `TWAnySignerSupportsJSON` is true, `TWAnySignerSignJSON` already keeps the key native. **[UNVERIFIED]** coverage and whether the JSON path has feature parity with proto signing | Not needed |
| Testability | Standard Dart tests | Requires native test harness |

**[DECISION-1]** Choose A, B, or "A now, B later behind the same `Signer` interface", based on the M0 spike, which must measure: implementation effort of B for Ethereum; whether `SignJSON` coverage is broad enough to matter; and whether A's residual exposure is acceptable for P1 users when documented. The public API must not change whichever is chosen.

**Family boundary [REQ], independent of DECISION-1:** chain-family code encodes a *key-less* signing input from a request (`encodeKeylessInput(request)`) and parses upstream's output into a typed `SignResult` (`parseSigningOutput(bytes)`). Only the selected signer path injects private keys, and before injecting it verifies, against a reviewed per-family list of key field names, that the key-less input contains none. Family builders never receive key bytes. Encoding upstream's *signing-input* protobuf in Dart is allowed; serializing the *signed transaction* remains upstream's job (§6).

## 12. Native Distribution and Packaging (evaluate before choosing)

v1.0 assumed conventional platform packaging (AAR / xcframework via podspec). Flutter now offers a different route, and the choice affects consumer setup, minimum SDK versions, and iOS/Android quirks, so it is evaluated in M0 with the **actual upstream artifacts**, not a hello-world library.

### 12.1 Options

| | **Option 1 — Build hooks (`package_ffi` template, `hook/build.dart`)** | **Option 2 — Conventional platform packaging** |
|---|---|---|
| What it is | **[VERIFIED]** Flutter docs: "Since Flutter 3.38, the recommended way to bind to native code is to use the `flutter create --template=package_ffi` command… no longer requires OS-specific build files." Assets are declared as `CodeAsset`s; prebuilt libraries use `DynamicLoadingBundled()` | `flutter create --template=plugin(_ffi)` with `build.gradle`/AAR (or prefab) on Android and a `.podspec`/SPM package wrapping an xcframework on iOS |
| Consumer setup | No CocoaPods/Gradle edits by consumers | Standard; CocoaPods or SPM on iOS; Gradle on Android |
| Minimum versions | Requires a Flutter version with stable build hooks; **[UNVERIFIED]** exact minimum and stability status for prebuilt-binary (`DynamicLoadingBundled`) assets on iOS and Android — the docs page reflects Flutter 3.47.2 and does not state a minimum | Works on older Flutter |
| iOS specifics | **[VERIFIED]** hook is invoked per SDK (`iphoneos`, `iphonesimulator`) and per architecture and must emit identical framework/asset names for the same asset ID; the docs say not to use `_sim`/arch suffixes | xcframework already separates device/simulator slices |
| Android specifics | **[VERIFIED]** `libc++_shared.so` is not a system library; apps using the C++ standard library must bundle it (docs point to `package:android_libcpp_shared`) | Same requirement, handled via Gradle packaging |
| Static vs dynamic | Docs do not cover static linking; **[VERIFIED 2026-09-07]** upstream's iOS `WalletCore.xcframework` at 4.8.0 is a *dynamic* framework (device and simulator slices), and the `TrustWalletCore-<tag>.tar.xz` asset carries static archives including a macOS slice (DECISION-9, F2 and F10) — a dynamic slice exists as shipped and by relink | Dynamic framework consumption is routine; the static archives need a relink step |
| Risk | Newer mechanism; fewer worked examples with large third-party static/dynamic libs; unknown interaction with upstream's Rust-built components | Two build systems to maintain; consumer friction; well trodden |

### 12.2 Evaluation protocol [REQ] (M0)

Using upstream 4.8.0 artifacts (or a from-source build of that tag if release assets are insufficient — **[VERIFIED 2026-09-07]** the 8 release assets' contents, `docs/decisions/evidence/release-assets-4.8.0.md`), for **each** option:

1. Build a consumer app from a clean checkout (`flutter create` + add dependency; no manual native edits).
2. Run on: Android emulator (x86_64) and physical arm64 device; iOS simulator (arm64 and x64 hosts if available) and physical device.
3. Build **release** configurations on both platforms; confirm the app launches and signs (release builds strip and optimize differently from debug).
4. Confirm the required native symbols are present and resolvable in the packaged binary (`nm`/`objdump` on the shipped library, plus a runtime symbol-lookup test for the full generated symbol set).
5. Record binary size per ABI/slice and app-size delta.
6. Record the minimum Flutter/Dart version the option needs; set the SDK's `environment` constraints from that measurement, not from assumption.
7. Confirm a clean consumer install works with no network access *except* the artifact fetch, and that a wrong checksum fails the build loudly.
8. Verify every 64-bit Android artifact is 16 KB page-aligned (ELF segments and APK/AAB packaging) and record the check command; run the flow on every shipped ABI or drop the ABI (`armeabi-v7a` ships only if tested).
9. Build the consumer app together with another Flutter plugin that bundles `libc++_shared.so` and confirm there is no duplicate-library or version conflict; record how the packaging option resolves it.
10. On iOS record the minimum deployment target, confirm the release archive links, check symbol visibility and duplicate symbols, audit required-reason API use and add a `PrivacyInfo.xcprivacy` if any is found, and sign the xcframework **[REC]**.
11. Consume the packages the way a real app will (a locally hosted package repository, or the archives produced by `pub publish --dry-run`), not through path dependencies.

**[DECISION-2]** Option 1 vs Option 2 (or Option 1 with Option 2 fallback for older Flutter). Recorded with the evaluation data.

### 12.3 Artifact acquisition [REQ]

- Native binaries are hosted on GitHub Releases of this project (built by CI from the pinned upstream tag) and fetched at consumer build time by the native package. The pub.dev package stays small.
- Every artifact's SHA-256 is pinned in the compatibility manifest (§15) shipped inside the package; fetch fails hard on mismatch. An offline/vendored mode (pre-downloaded artifacts in a configurable cache directory) is supported for air-gapped CI.
- Artifacts carry provenance attestations **[REC]** (GitHub artifact attestations / SLSA).
- **Identity [REQ].** **[VERIFIED 2026-09-07]** the 4.8.0 headers expose no library-version symbol (`TWHDVersion` and `TWStellarVersionByte` are unrelated), and hashing the loaded library at runtime is meaningless for a statically linked iOS framework. Each artifact set therefore embeds a build-identity symbol (`wcf_build_info()`: upstream commit, artifact-set id) that `WalletCore.initialize()` compares with the Dart manifest. This is possible only when we build the artifacts or ship a small companion library next to upstream prebuilts; **[DECISION-9]** must account for it.
- **Durability [REQ].** Artifact URLs are content-addressed and immutable; the manifest records source commit, build workflow, linkage type, target OS, ABI, minimum OS, toolchain, size, checksum, signature, and attestation identity. A retention promise and a secondary mirror are published before 1.0; an SBOM and third-party license inventory ship with every artifact set **[REC]** (**[DECISION-14]**).

### 12.4 Two separate requirements

- **[REQ] Checksum verification** — every consumer build verifies the artifacts against the manifest. Required from M0.
- **[REQ] Demonstrated reproducibility** — an independent rebuild from the pinned upstream commit with the pinned toolchain produces byte-identical (or documented-diff) artifacts. This is a *distinct* requirement with its own milestone (M3) because it depends on upstream's build determinism, which we do not control. Until it is demonstrated, README says "checksum-pinned", not "reproducible".

## 13. Capability Matrix and Verified Support

Full generated coverage proves that a symbol exists, not that a chain supports an operation or that our SDK exercises it correctly.

### 13.1 Definitions [REQ]

For each coin in the registry and each operation:

| Operation | Upstream entry point |
|---|---|
| Address derivation & validation | `TWAnyAddress`, `TWHDWallet` |
| Transaction signing | `TWAnySignerSign` (proto) / `TWAnySignerSignJSON` |
| Message signing | coin-specific `MessageSigningInput` where defined **[UNVERIFIED]** list |
| Planning | `TWAnySignerPlan` — **[VERIFIED]** doc comment: "for UTXO chains only" |
| External-signature compilation | `TWTransactionCompiler` pre-image hashes + compile **[UNVERIFIED]** per-coin availability |

Support is recorded per (coin, operation, **variant**, platform, upstream tag). A variant is a concrete transaction or message shape (EVM: legacy, EIP-1559, contract call; Bitcoin: P2PKH, P2WPKH, Taproot, multi-input; Solana: legacy, versioned; messages: personal, EIP-712), because one passing vector proves one variant, not a chain. Three support levels:

- **Generated** — the coin's protobuf defines the operation's input (for example a `SigningInput` message) and the registry lists the coin at the pinned tag (produced mechanically from the proto descriptors and the registry). **[VERIFIED]** `TWAnySignerSign` is one global symbol, so symbol presence says nothing per coin and is not used as evidence.
- **Exposed** — the public SDK offers a typed or generic path to call it.
- **Tested** — at least one known-answer test vector for that (coin, operation) passes on Android and iOS in CI, and the vector's origin is recorded.

Anything not *Tested* is labeled "exposed, unverified" in docs. The README's chain count states "N chains generated, M exposed, K tested" and links the matrix, which names the exact variants verified; docs never call a chain "supported" when only one variant is Tested.

### 13.2 Test vector inventory [REQ]

- A machine-readable file (`test_vectors/inventory.yaml`) lists every vector: coin, operation, variant, source (upstream test file path and commit, or external standard such as a BIP/SLIP test, or a published transaction hash), input, expected output, and platforms verified.
- Coverage checks in CI: (a) every *Tested* claim in the capability matrix corresponds to a passing vector; (b) the matrix is generated from the inventory and the symbol inventory, never edited by hand; (c) a PR that removes a vector or downgrades a level fails unless it updates a documented exclusions list with a reason.
- Documented exclusions: coins/operations we intentionally do not test (e.g. deprecated chains) are listed with rationale.
- **Replaced from v1.0:** the phrase "all upstream vectors passing" is retired. Upstream's tests are C++/Rust and are not directly runnable in Dart; we *port* selected vectors and record which.

### 13.3 Initial tested set

| Milestone | Coins | Operations |
|---|---|---|
| M0 | Ethereum | address derivation, transaction signing (EIP-1559 transfer), invalid-input handling |
| M1 | Bitcoin, Solana (+ Ethereum message signing, EIP-712) | address, signing (BTC: P2WPKH single-input **and** a two-input spend from two derivation paths, to prove multi-key resolution), planning (BTC), message signing (ETH/SOL) |
| M2+ | EVM chains sharing Ethereum's signer (chain-ID matrix), Litecoin/Dogecoin/Bitcoin Cash via UTXO family, TRON, Cosmos family, TON, XRP | per family; each added only with vectors |

## 14. Background Signing and Ownership

Signing and derivation are CPU-bound native calls and must not block the UI isolate. v1.0 hand-waved "Isolate-friendly design". The constraints are stricter than that.

### 14.1 Constraints

- **[REQ] No assumption that native pointers are safe to share across isolates.** A `Pointer` is just an address and can be sent between isolates, but the *object* it points to has no cross-isolate ownership, no synchronization, and a finalizer attached in one isolate does not follow it. Upstream does not document thread-safety of `TWHDWallet` or other handles **[UNVERIFIED]**; we assume none.
- Dart `Isolate.run` copies or transfers message data; a design that re-creates the wallet from the mnemonic in every worker call would move the mnemonic across isolates on every sign — unacceptable.

### 14.2 Proposed model — long-lived signing worker [REC, evaluate in M0/M1]

- One background isolate (the **signing worker**) owns all native wallet handles for the lifetime of a `WalletCore` session. The UI isolate never holds a native wallet pointer; it holds an opaque `WalletRef`/`AccountRef` (an ID) and plain Dart values.
- Operations are messages: `Sign(request, keyLocators)`, `DeriveAddress(walletRef, coin, path)`, `ImportWallet(mnemonic)` (the one message that necessarily carries a secret; documented), `Dispose(ref)`, `Shutdown`. Private keys are derived inside the worker for one signing operation and disposed immediately afterwards.
- **Initialization:** `WalletCore.initialize()` spawns the worker, loads the native library there, verifies the manifest, and returns only after a health check (a symbol-lookup round trip).
- **Serialization of operations:** the worker processes messages sequentially (single-threaded native access), which sidesteps the unknown thread-safety of upstream handles. Throughput is bounded by one signature at a time; measured in M1, and if insufficient, a per-wallet worker pool is the escalation, not shared handles.
- **Disposal:** `Dispose(ref)` disposes in the worker and is acknowledged; the public proxy's `close()` awaits that acknowledgement. `Shutdown` stops accepting work, resolves or rejects queued operations, disposes all handles, detaches finalizers, and exits the isolate. `WalletCore.shutdown()` awaits it. If the worker dies (uncaught error), all refs become invalid and calls throw `WorkerTerminatedError`; the session must be re-initialized.
- **Request/signer separation:** requests (`*TransactionRequest`) are plain values that cross isolates freely; `Signer` implementations decide where signing happens. `LocalSigner` posts to the worker; a future `ExternalSigner` never touches the worker at all.
- Synchronous, same-isolate use (`LocalSigner.sync`) remains available for tests and CLIs with the same disposal contract.

### 14.3 Session lifecycle and worker protocol [REQ]

- A `WalletCore` session has explicit states: `initializing`, `ready`, `closing`, `closed`, `failed`. Operations are accepted only in `ready`.
- Every message carries a request id; every reply is a result or a typed error. The queue is bounded; a full queue rejects with a typed error instead of growing without limit. Operations have a timeout and can be cancelled before they start; an operation already running in native code completes.
- `close()` on a proxy during an in-flight operation on the same handle waits for that operation, then disposes. `close()` and `shutdown()` are idempotent.
- After termination every proxy reports `WorkerTerminatedError`; nothing is retried silently.
- Accounts are descriptors, never handles (§10.2). The public API never holds a native pointer; the same-isolate `HDWallet` of the advanced import keeps the synchronous contract of §11.2 for tests, CLIs, and callers who accept ownership.

This protocol is written down as **[DECISION-12]** before the public SDK surface is implemented; the worker is built after the protocol exists, not before.

**[DECISION-3]** Confirm the worker model (vs. per-call short-lived isolates with key handles re-derived from a `StoredKey`) using M1 measurements: median/95th sign latency, memory, and the complexity of ref lifetime management.

## 15. Automation, Versioning, and the Compatibility Manifest

### 15.1 Order of work (changed from v1.0)

Automation is part of the **initial spike**, not a later milestone. M0's end-to-end flow must already run on generated bindings, pinned checksum-verified artifacts, and automated tests in CI. Release watching is added only after that foundation is proven (M3).

### 15.2 Pipeline stages [REQ]

1. **Pin:** a PR updates the manifest's upstream commit/tag.
2. **Build:** CI builds native artifacts for that tag (Android ABIs; iOS device + simulator) in upstream's Docker image or a pinned toolchain; uploads to GitHub Releases with checksums.
3. **Generate:** `ffigen`, `protoc`, registry transform. Zero hand-edits allowed in generated directories (CI enforces via a clean-regeneration diff).
4. **Diff reports:** (a) **API diff** — added/removed/changed symbols, protobuf fields, registry entries; (b) **behavioral diff** — the full test-vector inventory re-run; any changed output for an existing vector is flagged even if the API is unchanged (upstream may change serialization or defaults).
5. **Test:** unit + integration on Android emulator and iOS simulator; capability matrix regenerated.
6. **Human approval:** a maintainer reviews both diffs before `pub publish`. Nothing publishes automatically.
7. **Watch (M3+):** a scheduled job opens the pin PR when upstream tags a release.

Breakage policy: if generation or tests fail on a new tag, CI opens an issue with the diffs; the previous pin stays published and its artifacts stay available.

Release channels **[REC]**: an absorbed tag is first published as a pre-release (candidate) version; stable publication follows a risk-based soak period, with a separate expedited path for upstream security fixes. The upgrade report states which *exposed, unverified* operations upstream changed, because the behavioral diff covers only existing vectors.

### 15.3 Compatibility manifest [REQ]

One file, `compat_manifest.json`, checked into the repo, shipped inside `wallet_core_flutter_native` (and mirrored in the other two packages' metadata), and attached to every release:

```json
{
  "upstream": { "repo": "trustwallet/wallet-core", "tag": "4.8.0", "commit": "<sha>" },
  "generators": { "ffigen": "x.y.z", "protoc": "x.y.z", "protoc_gen_dart": "x.y.z", "registry_transform": "<script sha>" },
  "schemas": { "proto_dir_sha": "<sha>", "registry_json_sha": "<sha>", "headers_sha": "<sha>" },
  "artifacts": {
    "android/arm64-v8a/libTrustWalletCore.so": { "sha256": "…", "size": 0, "source_commit": "<sha>", "build_workflow": "<workflow-run url>", "linkage": "dynamic", "target_os": "android", "abi": "arm64-v8a", "min_os": "21", "toolchain": { "ndk": "…", "cmake": "…", "rust": "…" }, "signature": null, "attestation": null, "provenance": "built_from_source", "asset_name": "<artifact_set_id>__<sha256[0:12]>__android-arm64-v8a-libTrustWalletCore.so", "logical_name": "android/arm64-v8a/libTrustWalletCore.so" },
    "android/armeabi-v7a/…": {}, "android/x86_64/…": {},
    "ios/TrustWalletCore.xcframework.zip": { "sha256": "…", "size": 0 }
  },
  "packages": { "wallet_core_flutter": "0.x.y", "wallet_core_flutter_bindings": "0.x.y", "wallet_core_flutter_native": "0.x.y" },
  "toolchain": { "ndk": "…", "xcode": "…", "cmake": "…", "rust": "…" },
  "release_set": "<id shared by the three package versions>",
  "identity": { "symbol": "wcf_build_info", "artifact_set_id": "as_<tag>_<nnn>", "upstream_commit": "<sha>", "build_workflow": "<workflow-run url>" },
  "retention": { "primary": "<immutable content-addressed base URL>", "mirror": "<url or null>", "policy": "<url>" },
  "sbom": "<path or null>",
  "reproducible_build_verified": false
}
```

At runtime, `WalletCore.initialize()` calls the build-identity symbol (§12.3; **[VERIFIED]** upstream exposes no version symbol, so the identity is ours) and throws `ManifestMismatchError` when it does not match the manifest, or when the three packages' embedded release-set ids differ.

### 15.4 Versioning [REQ]

- Each package: semver of its own API. Breaking changes in generated symbols → major bump of `_bindings`; SDK public API changes → SDK semver; artifact/loader changes → `_native` semver.
- The SDK pins the **exact** tested versions of `_bindings` and `_native`; the manifest pins the exact upstream commit and the release-set id. CI tests the fully resolved dependency graph without path overrides. Publication order is `_native`, then `_bindings`, then the SDK; a fresh application installs the hosted versions and signs a vector before a release is announced. Published versions are immutable, so a recovery release (new patch versions of the whole set) is the only rollback; the procedure is written before the first publish (**[DECISION-14]**).
- Changelogs state the upstream tag each release tracks.

## 16. Security Requirements

- **S1 — Thin glue, own responsibility [REQ].** All cryptography is upstream. The SDK, bindings wrappers, any native adapter (§11.4 B), the artifact loader, and the signing worker are *ours* and are in scope for our own review; upstream audits are not claimed to cover them.
- **S2 — Disposal and secret contract [REQ].** §11 in full. Documentation carries the "what we wipe / what we can't" page.
- **S3 — Artifact integrity [REQ].** Checksum verification on every build (§12.3); provenance attestations [REC]; reproducibility as a separate demonstrated requirement (§12.4).
- **S4 — No network, no telemetry at runtime [REQ].** Verified by a test that runs the full example with networking disabled, and by a dependency policy: no networking package may be a runtime dependency of any of the three packages. Build-time network use (artifact fetch in the native package's build tooling or hook) is allowed and measured separately from runtime.
- **S5 — Input validation before native calls [REQ].** Addresses, derivation paths, amounts, chain IDs, and lengths are validated in Dart; invalid input raises `InvalidInputError` without reaching native code where feasible, and native error codes are surfaced typed. Hostile-input testing is part of the gate: fuzzed or property-generated FFI lengths, protobuf payloads, addresses, derivation paths, numeric boundaries (amounts wider than the chain's integer width), null or malformed native outputs, wrong-network addresses, and worker queue limits, timeouts, cancellation, shutdown with pending work, and crash injection.
- **S6 — Disclosure & review [REQ].** A first threat model (key residence and lock/unlock, app-backgrounding guidance, BIP-39 passphrases and keystore passwords, clipboard/keyboard/logs/crash dumps/screenshots, dynamic-library path hijacking and artifact substitution, malformed native inputs and outputs, dependency and upstream vulnerability monitoring, emergency-update policy, debug tooling and secrets in diagnostics) is written at M0 start, before the worker, loader, and public API are designed, and revised at each milestone. `SECURITY.md` with a private channel is published before the public alpha. An external review of the glue layer (bindings wrappers, worker, loader, and native adapter if any) happens before the 1.0 tag. **[DECISION-4]** funding/scope of the review.
- **S7 — Keystore guidance [REQ, docs].** Cookbook steers to `StoredKey` plus platform secure storage; the SDK does not persist anything itself.
- **S8 — Debug aids off in release [REQ].** Leak tracker and verbose native logging are compiled out of release builds.
- **S9 — Exact v1 support table [REQ, docs].** The 1.0 README carries a feature table naming, per family, the transaction and message variants that are Tested, those that are exposed only, and explicit exclusions (BIP-39 passphrases, imported keys, watch-only accounts, Taproot, versioned Solana transactions, multisig, and similar are each listed as included or excluded). Account discovery, balances, fees, nonces, UTXO sets, blockhashes, and broadcasting stay outside the package (§6). Extends **[DECISION-10]**.

## 17. Licensing, Naming, and Trademark

- **License:** MIT for all package code; upstream Apache 2.0 with NOTICE preserved in distributed artifacts. Any native adapter we write is MIT. **This document is not legal advice** and makes no claim about how AGPL applies to third-party apps.
- **Naming [REC]:** `wallet_core_flutter`, `wallet_core_flutter_bindings`, `wallet_core_flutter_native` (renamed from `_libs` in v1.0 to reflect that it owns loading and build integration, not just files). **[UNVERIFIED]** availability on pub.dev. **[DECISION-5]** final names.
- **Trademark [REQ]:** "Trust Wallet" is a third-party trademark. Package names avoid "trust"; README, pub.dev description, and docs say "Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet." No Trust Wallet logos or brand assets.

## 18. Milestones

Estimates after M0 are placeholders **to be re-estimated from M0 findings** (packaging option, secret-handling approach, worker model).

| Milestone | Scope | Exit criteria (acceptance) | Est. |
|---|---|---|---|
| **M0 — Spike: prove the whole pipeline on Ethereum** | Threat model v0 (S6) and DECISION-11/12/13/14 recorded first; pinned upstream tag + manifest; generated `ffigen`/protobuf/registry; artifact fetch with checksum and the build-identity symbol; disposal contract; stable public coin facade; key-less request encoding; §12 packaging evaluation on both options (including 16 KB alignment, `libc++_shared` conflicts, iOS archive and privacy checks, packaged-dependency consumption); §11.4 A vs B prototype; CI running the tests on Android emulator + iOS simulator. Signing may run same-isolate during the spike; signing duration is measured before the worker is built | On Android (emulator + device) and iOS (simulator + device), in **debug and release**: create wallet; import a known mnemonic; derive the expected Ethereum address; sign an EIP-1559 transfer and match a known vector **byte-for-byte**; invalid mnemonic / invalid address / invalid path each raise typed errors; explicit `dispose()`/`close()` paths exercised and leak tracker reports zero undisposed objects; a fresh consumer app installs cleanly from packaged (not path) dependencies with no manual native edits; the identity check passes and a mismatched manifest fails; DECISION-1 and DECISION-2 recorded with data | 3–4 weeks |
| **M1 — Bitcoin & Solana, worker** | Multi-key signer with `KeyLocator`s; sealed `SignResult` types; UTXO family request/plan/sign; Solana sign; ETH message signing (personal + EIP-712); signing worker built to the §14.3 protocol, with latency measurements; variant-aware capability matrix + vector inventory generated in CI; hostile-input suite (S5) | Vectors for BTC (P2WPKH single-input transfer with plan **and** a two-input spend from two derivation paths), SOL (transfer), ETH message signing pass on both platforms; worker state-machine, queue-bound, timeout, cancellation, close-during-in-flight, and crash-injection tests; DECISION-3 recorded; README shows generated/exposed/tested counts per variant | re-estimate |
| **M2 — Public SDK alpha on pub.dev** | API freeze candidate for §10; error hierarchy; cookbook (5 guides incl. secure storage, "what we wipe", and session lifecycle); `advanced` import (raw protobuf signing lives only there); family helpers for EVM/UTXO/Solana only; `SECURITY.md`; v1 feature table (S9) and artifact-retention policy published; release-set process (§15.4) exercised | `0.x` published as one release set; a fresh app installs the hosted versions and signs; API review checklist passed; variant-aware capability matrix published; no `dart:ffi`, generated, or protobuf types in public signatures (lint-enforced) | re-estimate |
| **M3 — Release watching & reproducibility** | Upstream watcher; API + behavioral diff reports; candidate/stable channels **[REC]**; one upstream release absorbed end-to-end; independent rebuild comparison | New upstream tag absorbed with zero hand-edits; both diff reports attached to the PR and naming the unverified surface upstream touched; reproducibility result recorded (`reproducible_build_verified` true, or documented diffs) | re-estimate |
| **M4 — 1.0 stable** | Remaining top-chain families with vectors; external review (S6); migration notes from `flutter_trust_wallet_core` and `wallet_core_bindings` | 1.0 published; review findings closed or documented; all *Tested* claims traceable to inventory | re-estimate |
| **M5 — Expansion** | macOS/Linux (same FFI path); Web/Windows via a `_wasm` sibling of the native package; external signers | per-platform matrix green | ongoing |

## 19. Release Acceptance Criteria (apply to every published version)

1. Generated directories are byte-identical to a clean regeneration from the manifest's pinned commit.
2. Every artifact in the manifest downloads and verifies; a corrupted artifact fails the consumer build with a clear error.
3. Full test-vector inventory passes on Android and iOS CI; the capability matrix is regenerated and committed.
4. API diff and behavioral diff reviewed and linked from the changelog.
5. Public SDK exports contain no `dart:ffi`, generated `TW*`, or protobuf types (lint).
6. Example app builds in release on both platforms from a clean clone.
7. Changelog names the upstream tag and lists any downgraded capability with reason.
8. A maintainer approved publication.

## 20. Success Metrics (revised)

- **Freshness:** median upstream-tag-to-release lag (target < 7 days after M3; measured, not promised before).
- **Verification:** number of (coin, operation) pairs at *Tested* level; growth per release; zero *Tested* claims without a vector.
- **Quality:** pub.dev score ≥ 140/160; SDK-layer coverage ≥ 90%; zero open severity-high security findings at 1.0.
- **Adoption (6 months after 1.0):** 1,000+ downloads/month; ≥ 3 production apps known; ≥ 5 external contributors; listed among upstream's community projects.

## 21. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Upstream ships an official, supported Flutter SDK | Low–Medium | High | Verify status of upstream `flutter/` early (§2); remain differentiated on license/contract/verification; be prepared to rebase our SDK layer on it |
| Build hooks route immature for large prebuilt libs on iOS | Medium | Medium | §12 evaluation on real artifacts; Option 2 fallback |
| Secret copies in Dart heap unacceptable to P1 users | Medium | High | Approach B (§11.4) available behind the same interface; precise documentation either way |
| Upstream handles not thread-safe | Unknown | High | Single-threaded worker (§14); never share handles |
| Upstream serialization/behavior changes without API change | Medium | High | Behavioral diff over the vector inventory (§15.2) |
| Upstream build not deterministic → reproducibility unprovable | Medium | Medium | Kept as a separate requirement; checksum pinning still holds; document diffs |
| Binary size | High | Medium | Measured in M0; ABI splits; track upstream modularization |
| `SignJSON`/compiler coverage narrower than assumed | Medium | Medium | Marked unverified; capability matrix reports reality |
| Trademark complaint | Low | Medium | §17 naming and disclaimer |
| Solo maintainer / bus factor | Medium | High | Everything generated and scripted; CONTRIBUTING; org-owned publisher |
| Over-claiming in README (AGPL, audits, zeroization) | Medium | High | Labels in this doc; README review checklist against §4, §11, §12.4 |

## 22. Unresolved Decisions

| ID | Decision | Options | Decided by | When |
|---|---|---|---|---|
| **DECISION-1** | Where the signing protobuf (with private key) is assembled | A Dart-side minimized; B native adapter; A-then-B | Spike data (§11.4) | M0 exit |
| **DECISION-2** | Native packaging mechanism | Build hooks; conventional; hooks with conventional fallback | §12.2 evaluation | M0 exit |
| **DECISION-3** | Signing worker model | Long-lived worker; per-call isolates; hybrid | M1 latency/memory data | M1 exit |
| **DECISION-4** | External security review scope and funding | Self-funded; grant; community | Owner | before M4 |
| **DECISION-5** | Final package names | `wallet_core_flutter*`; alternatives if taken | pub.dev availability check | M0 |
| **DECISION-6** | Minimum Flutter/Dart versions | Derived from DECISION-2 measurements | §12.2 step 6 | M0 exit |
| **DECISION-7** | Chain-family helpers in-package vs per-family packages | In SDK (default); split later | Size/cadence data | post-M2 |
| **DECISION-8** | Status and intent of upstream `flutter/` directory | Sample; abandoned; planned SDK | Check upstream issues/commits/maintainers | M0 start |
| **DECISION-9** | Source of native artifacts (must allow the build-identity symbol of §12.3) | Upstream release assets plus a companion identity library; from-source build in CI; both | Inspected the 8 release assets (T0.5, 2026-09-07) | M0 start |
| **DECISION-10** | Which operations and variants are *Exposed* in 1.0 for coins without vectors, and the exact v1 feature/exclusion table (S9) | Advanced-only raw signing; typed helpers; explicit exclusions | Capability policy + owner | M2 |
| **DECISION-11** | Public coin/network/account model: stable facade over the generated registry; explicit network where upstream has none; assets deferred to helpers | Thin facade (default); full chain-family/network/asset model; generated enum public with a deprecation policy | Owner, on the ADR drafted at M0 start | M0 start |
| **DECISION-12** | Session lifecycle and worker protocol (§14.3): states, request ids, queue bound, timeouts, cancellation, close semantics, failure behavior; async public close vs synchronous internal dispose | As §14.3; per-call isolates (folds into DECISION-3) | ADR + M0/M1 data | M0 start (protocol), M1 exit (worker model) |
| **DECISION-13** | Signing model: `KeyLocator`s, multi-key resolution, partial-signing and multisig policy, sealed `SignResult`, external-signer boundary | Signer resolves a key set (default); one account per request (rejected: Bitcoin needs several keys) | ADR + Bitcoin two-input vector | M0 start (interface), M1 exit (proof) |
| **DECISION-14** | Distribution contract: build-identity symbol, content-addressed retention and mirror, release set with exact pins, publication order, recovery release, SBOM | Build from source with identity symbol; upstream prebuilt plus companion identity library | DECISION-9 evidence + owner | M0 exit |

## 23. Changelog — v1.0 → v1.1

- **Package boundaries:** defined per-package ownership and prohibitions; renamed `_libs` → `_native` (owns acquisition, verification, build integration, loading); default import excludes pointers/generated/protobuf types; `advanced` import added; family helpers kept inside the SDK.
- **Memory & secrets:** replaced "never in Dart Strings"/"zeroized after use" with a disposal contract (explicit dispose, finalizer detach, double-free and use-after-dispose protection, exception-safe temporaries, finalizer as fallback), a "what wipe means" section with documented limitations (mnemonic import/export/display), and an A-vs-B comparison for private-key handling in signing inputs (DECISION-1). Added verified facts on `TWDataDelete`/`TWStringDelete`, `NativeFinalizer`, `Ethereum.proto`, `TWAnySigner`.
- **Native packaging:** added a build-hooks vs conventional packaging evaluation with a concrete protocol on real artifacts (devices, simulators, release builds, symbol checks, clean install); minimum Flutter/Dart versions derived from measurement; checksum verification and demonstrated reproducibility separated into two requirements.
- **Capability matrix:** introduced generated/exposed/tested levels per (coin, operation) across derivation, signing, message signing, planning, and external-signature compilation; test-vector inventory with provenance; measurable coverage checks; documented exclusions; retired "all upstream vectors passing".
- **Background signing:** replaced "isolate-friendly" with a long-lived signing-worker model (ownership, init, sequential operations, dispose, shutdown), an explicit rule that native handles are not assumed cross-isolate-safe, and request/signer separation for future external signers (DECISION-3).
- **Automation:** moved generated bindings, pinned artifacts, and CI tests into M0; release watching moved to M3; added behavioral diff alongside API diff; human approval retained; introduced the compatibility manifest; packages now carry their own semver rather than mirroring upstream.
- **Milestones:** M0 tightened to wallet create/import, Ethereum derivation, deterministic signing vs. a known vector on Android and iOS, invalid inputs, explicit cleanup, release builds, clean consumer install; Bitcoin and Solana in M1 before convenience APIs; later estimates marked for re-estimation.
- **Background claims:** corrected the competitor description (protobuf bindings + repackaged API, not raw C only); acknowledged upstream's in-tree Flutter directory and distinguished it from a supported SDK; removed blanket AGPL conclusions and "upstream audits cover us" phrasing; added [VERIFIED]/[UNVERIFIED] labels and a source-check date.
- **Kept from v1.0:** vision, MIT license, Android+iOS first, non-goals, personas, three-package monorepo, artifact hosting on GitHub Releases with checksums, human-approved publication, trademark posture, risk register (extended), adoption metrics.

## 24. References (checked September 6, 2026)

- Upstream repo, README (license, bindings list, chain count): https://github.com/trustwallet/wallet-core
- Upstream `flutter/` README: https://github.com/trustwallet/wallet-core/blob/master/flutter/README.md
- `TWData.cpp` (`TWDataDelete` memzero): https://github.com/trustwallet/wallet-core/blob/master/src/interface/TWData.cpp
- `TWString.cpp` (`TWStringDelete` memzero): https://github.com/trustwallet/wallet-core/blob/master/src/interface/TWString.cpp
- `Ethereum.proto` (`private_key` in `SigningInput`/`MessageSigningInput`): https://github.com/trustwallet/wallet-core/blob/master/src/proto/Ethereum.proto
- `TWAnySigner.h` (`Sign`, `SignJSON`, `SupportsJSON`, `Plan`): https://github.com/trustwallet/wallet-core/blob/master/include/TrustWalletCore/TWAnySigner.h
- Upstream latest release (4.8.0, 19 assets — contents not inspected): https://github.com/trustwallet/wallet-core/releases/latest
- `NativeFinalizer`: https://api.dart.dev/dart-ffi/NativeFinalizer-class.html
- Flutter native binding guide (build hooks since 3.38; iOS naming rules; `libc++_shared`): https://docs.flutter.dev/platform-integration/bind-native-code
- `wallet_core_bindings` (4.8.0, AGPL-3.0, README claims): https://pub.dev/packages/wallet_core_bindings
- `flutter_trust_wallet_core` (0.0.1, 2020): https://pub.dev/packages/flutter_trust_wallet_core
- `trust_wallet_core_lib` (0.0.7+3.0.4, 2021): https://pub.dev/packages/trust_wallet_core_lib
- Developer guide: https://developer.trustwallet.com/developer/wallet-core
- Architecture audit absorbed by v1.2: `docs/audit-resaults/wallet_core_flutter_architecture_audit.md` and its triage `docs/audit-resaults/audit_triage.md`
- `Bitcoin.proto` (`repeated bytes private_key`), `Solana.proto` (three key fields), `TWTransactionCompiler.h`, and the header list without a version symbol, all at tag 4.8.0 (checked September 7, 2026): https://github.com/trustwallet/wallet-core/tree/4.8.0
- Android 16 KB page-size requirement: https://developer.android.com/guide/practices/page-sizes
- Apple privacy manifests for third-party SDKs: https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk
- Apple XCFramework signature verification: https://developer.apple.com/documentation/Xcode/verifying-the-origin-of-your-xcframeworks

## 25. Changelog — v1.1 → v1.2 (architecture audit, September 7, 2026)

- **Signing model (A-03, A-05, A-13):** `Signer.sign` takes a set of `KeyLocator`s; UTXO inputs name their keys; family code encodes key-less inputs and parses typed, sealed `SignResult`s; only the signer injects keys, after checking a reviewed per-family key-field list; M1 proves it with a two-input, two-path Bitcoin vector.
- **Lifecycle (A-02):** §11.2 now governs internal native handles; §14.3 adds the session state machine and worker protocol; public resources close asynchronously; accounts are descriptors; proxies use a Dart `Finalizer` as fallback. The worker is built after the protocol is recorded.
- **Public model (A-04, reframed):** the generated `CoinType` is no longer public; a stable coin/network facade maps to the registry (DECISION-11). EVM networks are already distinct registry coins; the facade adds what upstream lacks (testnets) and defers assets.
- **Raw signing (A-01, reframed):** `RawSigningInput` moves to `advanced.dart`; no generic key-detection guarantee is claimed because upstream protos carry no secret marker.
- **Capability evidence (A-06):** variant axis added; "generated" derives from protos and the registry, never from the global `TWAnySignerSign` symbol; docs name verified variants.
- **Distribution (A-07, A-08):** build-identity symbol (no upstream version symbol exists), content-addressed retention, mirror, SBOM [REC]; exact cross-package pins, release sets, publication order, hosted-install smoke, recovery release (DECISION-14); DECISION-9 constrained accordingly.
- **Security and testing (A-09, A-11, A-12):** threat model at M0 start; `SECURITY.md` before alpha; hostile-input and worker-fault tests in S5; runtime-network rule enforced by dependency policy separately from build-time; v1 feature table (S9) extends DECISION-10.
- **Mobile binaries (A-10):** §12.2 gains 16 KB alignment, `libc++_shared` conflict, per-ABI execution, iOS archive/visibility/privacy-manifest/signing checks, and packaged-dependency consumption.
- **Upstream updates (A-14, [REC]):** candidate/stable channels with an expedited security path; upgrade reports name the unverified surface touched.
- **Rejected or reframed:** A-01's descriptor-aware validator (circular without a secret marker); A-04's full five-type domain model (exceeds 1.0 scope); A-15's removal of per-phase reviews and merging of vector tasks (kept in the execution plan for provenance and lane reasons). Details in the triage file.
- **Kept from v1.1:** everything else.

## 26. Changelog — v1.2 → v1.2.1 (Phase 0 evidence, September 7, 2026)

Factual corrections from the Phase 0 evidence tasks; no requirement changed.

- **§2, §3 (DECISION-8, T0.4):** upstream's `flutter/` is a one-commit, unpublished Dart console sample regenerated by CI as a build smoke check; the README's Flutter pointer is an external project. "Tracks master" replaced; one [UNVERIFIED] resolved, one kept with its dated negative.
- **§4 (T0.9):** the audit qualification names the one published report (Kudelski 2023, Rust StarkNet key pairs) and the one published advisory (GHSA-7g72-jxww-q9vq); other audit claims stay unverified.
- **§12.1, §12.2, §22 (DECISION-9, T0.5):** upstream's iOS framework at 4.8.0 is dynamic, not static; the release carries 8 assets, not 19, none of them Android; the tarball asset holds static archives including a macOS slice.
- **§10.2 (DECISION-13, T0.11):** Solana's result is a string in the requested encoding, base58 by default.
- **§15.3 (DECISION-14 §5.1, D0 F6):** the per-artifact manifest record carries every §12.3 durability field plus `provenance`, `asset_name`, `logical_name`, with `toolchain` per artifact and the top-level block a set-wide summary; `identity` gains `build_workflow`; the code block shows the full shape for one artifact. T1.2 implements; `compat_manifest.json` and the validator change then.
- **§10.2 (DECISION-11/12/14, ratified at D0):** the error hierarchy gains `SessionStateError`, `QueueFullError`, `OperationTimeoutError`, `OperationCancelledError`, `UnknownCoinError`, and `ManifestMismatchError` carries a `check` discriminator.
