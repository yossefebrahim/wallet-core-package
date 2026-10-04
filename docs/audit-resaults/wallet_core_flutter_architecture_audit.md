# Wallet Core Flutter Package - Architecture Audit

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

**Audit date:** September 7, 2026  
**Reviewed material:** PRD Draft v1.1, delegated execution plan, progress tracker, all phase plans, and task/debate brief templates in `/Users/yossefebrahim/Work/wallet-core-package/docs/`.

## Executive verdict

The product direction is sound: keep all cryptography inside Trust Wallet Core, generate the low-level Dart bindings, provide a typed public SDK, keep networking outside the package, verify native artifacts, and publish only after human review.

The plan is not ready to execute unchanged beyond the initial repository setup. Six architecture issues should be resolved before implementation begins:

1. The raw signing escape hatch contradicts the promise that requests never contain private keys.
2. The worker-isolate ownership model is incompatible with the synchronous disposal contract.
3. The signer and account model assumes one key and does not represent normal multi-input Bitcoin signing.
4. The public domain model conflates blockchain family, network, asset, account, and Wallet Core coin identifiers.
5. Phase 2 hardcodes Dart-side private-key handling before the relevant architecture decision has been resolved.
6. The capability matrix can make weak evidence look like complete chain support.

The plan also needs stronger artifact-retention, package-version compatibility, mobile-binary, security, release, and hostile-input testing requirements. All implementation tasks are currently queued, so this is the best time to make these changes.

## What is already strong

- Trust Wallet Core remains the only cryptographic and signed-transaction serialization engine.
- The default Dart API hides FFI pointers and generated protobuf classes.
- Native packaging is tested with real consumer applications before a mechanism is selected.
- The plan distinguishes exposed features from features verified by test vectors.
- Secret-memory limitations in Dart are described honestly.
- Native artifacts are pinned by checksum and releases require human approval.
- API and behavioral diffs are planned for upstream upgrades.
- Android and iOS debug and release configurations are included in the early vertical slice.

These choices should remain.

## Blocking architecture findings

### A-01 - Raw signing contradicts the keyless-request invariant

**Severity:** Blocking

The PRD allows `RawSigningInput(coin, protobufBytes)` while also requiring that every request be free of key material. Phase 5 proposes the same raw path for unverified coins. Arbitrary protobuf bytes may already contain one or more private-key fields, and the SDK cannot reliably prove otherwise across every upstream schema.

**Evidence:**

- `docs/wallet_core_flutter_prd.md`, section 10.2, transaction requests.
- `docs/plan/EXECUTION_PLAN.md`, repository constraint 6.
- `docs/plan/phases/phase-5-m4-stable-and-phase-6-backlog.md`, T5.2b-T5.6b notes.

**Required change:**

- Remove raw protobuf signing from the default SDK.
- Place it under `advanced.dart`, where callers explicitly accept protobuf and secret-handling responsibility.
- Keep the default SDK limited to typed request objects whose builders are generated or reviewed and proven to exclude keys.
- If a future default raw path is required, generate descriptor-aware validation that rejects all known key fields. Do not rely on naming conventions or byte scanning.

### A-02 - Worker ownership and synchronous disposal are incompatible

**Severity:** Blocking

The memory contract says every native-backed public object has synchronous `dispose()`. The proposed worker model later says that every native pointer lives inside a background isolate and public objects contain only opaque IDs. An ID-only object cannot synchronously destroy a worker-owned pointer. A native finalizer attached to the public object also cannot send an asynchronous Dart message to that worker.

There is a second leak risk: if the worker keeps native objects in a strong-reference map, forgetting a UI-side reference does not make the worker-owned object unreachable. It remains alive until explicit remote disposal or complete session shutdown.

**Evidence:**

- `docs/wallet_core_flutter_prd.md`, sections 11.2 and 14.
- `docs/plan/phases/phase-2-m1-bitcoin-solana-worker.md`, T2.1.

**Required change:**

Define two separate lifecycle models:

- Internal native handles, which live in the worker: synchronous native deletion, finalizer fallback, use-after-close guards, and exception-safe temporary cleanup.
- Public remote resources: `Future<void> close()` that sends a worker command and waits for acknowledgement.

Recommended ownership model:

- A `WalletCoreSession` owns the worker.
- The worker owns unlocked `HDWallet` or vault handles.
- Public accounts are plain descriptors containing wallet ID, network, and derivation information. They do not own native handles.
- Private keys are derived inside the worker for a signing operation and disposed immediately afterward.
- `close()` and `shutdown()` are idempotent and asynchronous.
- Session shutdown stops accepting work, resolves or rejects queued operations, disposes all native resources, and then terminates the worker.

Add an explicit protocol/state machine for initialization, ready, closing, closed, and failed states. Define request IDs, error replies, maximum queue size, timeouts, cancellation semantics, disposal during an in-flight operation, and behavior after worker termination.

### A-03 - The signer cannot represent multi-key transactions

**Severity:** Blocking for Bitcoin support

`Signer.sign(request, accountRef)` assumes that one account supplies one key. A normal Bitcoin transaction can spend UTXOs from several derived addresses and require multiple private keys. The proposed `UtxoTransactionRequest` does not associate each input with a derivation path or key reference. Solana and other chains can also have transactions requiring multiple signers.

**Evidence:**

- `docs/wallet_core_flutter_prd.md`, section 10.2, Signers.
- `docs/plan/phases/phase-2-m1-bitcoin-solana-worker.md`, T2.1 and T2.5.

**Required change:**

- Introduce a `SigningKeyRef` or `KeyLocator` that can identify an HD derivation path, imported key, hardware-wallet key, or remote key.
- Associate UTXO inputs with the key locator needed to spend them.
- Let the signer resolve a set of required keys instead of accepting one `AccountRef`.
- Keep account data such as address, network, public key, and derivation path separate from the component that owns the secret.
- Define the v1 policy for multiple HD paths, imported standalone keys, watch-only accounts, multisig, and partially signed transactions. Unsupported cases must fail explicitly with typed errors.

At minimum, the Bitcoin milestone must include a transaction spending two inputs from two different derivation paths. A one-input P2WPKH vector does not validate the signer architecture.

### A-04 - The domain model conflates chain, network, asset, and account

**Severity:** Blocking for a stable public API

The plan exposes a generated `CoinType` and models an account primarily as `(coin, derivationPath)`. This does not cleanly represent:

- EVM as a blockchain family.
- Ethereum, Polygon, Base, and BNB Chain as different networks.
- Mainnet, testnet, and devnet environments.
- Native currencies versus ERC-20 or SPL assets.
- Bitcoin address/script types.
- Wallet Core's internal numeric coin identifier.

Exposing a generated enum also couples the stable SDK directly to upstream registry churn. An upstream rename or removal can become an SDK breaking change.

**Evidence:**

- `docs/wallet_core_flutter_prd.md`, sections 9 and 10.2.
- `docs/plan/phases/phase-1-m0-spike.md`, T1.5 and T1.11.

**Required change:**

Define stable public value types such as:

- `ChainFamily`
- `NetworkId` or typed `Network`
- `AssetId`
- `AccountDescriptor`
- `DerivationPath`
- `AddressFormat` or UTXO script type where relevant

Keep the generated Wallet Core coin ID inside the adapter/bindings layer. The adapter maps the stable public network model to the pinned upstream registry.

### A-05 - Phase 2 assumes Approach A before DECISION-1 is applied

**Severity:** Blocking

Phase 2 fixes the family-builder contract as `buildSigningInput(request, keyBytes)`. That sends private-key bytes into Dart and therefore hardcodes Approach A even if DECISION-1 selects the native adapter. It also makes family builders responsible for a secret they should not own.

The proposed Approach B prototype appends a `private_key` protobuf field by number. That can prove an Ethereum experiment, but it cannot be assumed to generalize. Other schemas may use repeated keys, nested key structures, or different key fields.

**Evidence:**

- `docs/wallet_core_flutter_prd.md`, section 11.4.
- `docs/plan/phases/phase-1-m0-spike.md`, T1.12 and T1.13.
- `docs/plan/phases/phase-2-m1-bitcoin-solana-worker.md`, architecture constraint set by T2.0.

**Required change:**

Use this family boundary:

```dart
KeylessSigningInput encodeKeylessInput(TransactionRequest request);
SignResult parseSigningOutput(Uint8List output);
```

The signer implementation owns key injection. If a native adapter is selected, use generated descriptor information or explicitly implemented per-family adapters. Validate that key fields are absent before injection. Never assume that appending one field is a universal signing design.

Clarify the repository rule about serialization: Dart may encode Wallet Core's signing-input protobuf, but only Wallet Core may serialize the final signed blockchain transaction.

### A-06 - The capability model produces misleading evidence

**Severity:** Blocking before public documentation

`TWAnySignerSign` is a global entry point. Finding that symbol in a library does not establish transaction-signing capability for every registry coin. Likewise, one successful vector does not establish complete support for a chain. For example, EVM legacy, access-list, EIP-1559, contract-call, and newer transaction types are separate behaviors; Bitcoin script types are also separate behaviors.

**Evidence:**

- `docs/wallet_core_flutter_prd.md`, section 13.
- `docs/plan/phases/phase-2-m1-bitcoin-solana-worker.md`, T2.8.

**Required change:**

Generate the matrix at this granularity:

```text
network x operation x transaction/message variant x platform x upstream version
```

Recommended evidence states:

- **Upstream declared:** registry/protocol support is present in the pinned source.
- **SDK available:** generic or typed SDK path exists.
- **Vector verified:** named vectors pass for the exact variant and platforms shown.
- **Integration verified:** a clean consumer build and real platform invocation pass.

Do not use a general word such as "Tested" to imply that a whole chain is supported after one vector. Documentation should name exactly which transaction variants were verified.

## High-priority improvements

### A-07 - Strengthen artifact durability and identity

**Severity:** High

Downloading native artifacts from GitHub during a consumer build creates a permanent dependency on the availability and immutability of that release. An offline cache helps current CI but does not ensure that an application remains buildable years later.

Add the following to the artifact design:

- Content-addressed immutable URLs.
- A retention promise and secondary mirror.
- Artifact source, source commit, build workflow, linkage type, target OS, ABI, minimum OS, toolchain, size, checksum, signature, and attestation identity in the manifest.
- A software bill of materials and third-party license inventory.
- A native `wcf_build_info()` symbol generated during the build that returns the upstream commit and artifact-set ID.
- Compile-time and initialization checks comparing that identity with the Dart manifest.

Do not depend on hashing the loaded library file at runtime. That can be unavailable or meaningless when an iOS framework is statically linked into the application.

### A-08 - Coordinate the three package versions

**Severity:** High

Independent semantic versions with compatible ranges can let Pub resolve an SDK, generated bindings package, and native package that were never tested as one set.

Use a coordinated release train:

- The public SDK pins exact tested versions of bindings and native packages.
- Every package contains the same compatibility-manifest hash and release-set ID.
- CI tests the full resolved dependency graph without path overrides.
- Publication order is native, bindings, then SDK.
- A fresh application installs the hosted versions and signs before the release is announced.
- Define a recovery-release procedure because already published package versions and native artifacts cannot simply be overwritten safely.

The high-level SDK can retain independent semantic API versioning, but a released package set must be immutable and jointly verified.

### A-09 - Move security work to the beginning

**Severity:** High

The initial threat model is currently scheduled near the 1.0 release. That is too late because it may invalidate the worker, loader, signing, and public API designs.

Move a first threat-model task into Phase 0 or early Phase 1. Cover:

- Key residence time and explicit lock/unlock behavior.
- Application backgrounding and session auto-lock guidance.
- BIP-39 passphrases and keystore passwords.
- Clipboard, keyboard, logs, analytics, crash dumps, and screenshots.
- Dynamic-library path hijacking and artifact substitution.
- Malformed lengths, protobufs, native return values, and null pointers.
- Dependency and upstream vulnerability monitoring.
- Emergency security-update policy.
- Debug-only tooling and prevention of secrets in diagnostic output.

Publish `SECURITY.md` before the public alpha. Keep the independent external review before 1.0.

### A-10 - Add current mobile binary requirements

**Severity:** High

The plan should explicitly verify:

- Android 16 KB ELF segment and package alignment for every 64-bit native artifact.
- Release AAB contents and ABI splits.
- `libc++_shared.so` version and duplicate-library conflicts with other Flutter plugins.
- Runtime execution on every shipped ABI, or removal of untested ABIs such as `armeabi-v7a`.
- iOS device and simulator slices, minimum deployment target, release archive linking, symbol visibility, and duplicate symbols.
- A signed XCFramework and an appropriate `PrivacyInfo.xcprivacy` declaration after auditing required-reason API use.

### A-11 - Expand hostile-input and integration testing

**Severity:** High

Add tests for:

- Fuzzed or property-generated FFI lengths, protobuf payloads, addresses, derivation paths, and numeric boundaries.
- Amounts exceeding the chain's accepted integer width.
- Null and malformed native outputs.
- Worker queue limits, timeouts, cancellation, shutdown with pending work, and crash injection.
- Multi-input and multi-derivation-path Bitcoin signing.
- Mainnet/testnet separation and wrong-network addresses.
- Duplicate native libraries in an application using other C++ Flutter plugins.
- Clean builds using actual packaged or hosted dependency versions.
- API compatibility and deprecation checks between SDK releases.

The no-runtime-network requirement should be enforced through source/dependency policy as well as a runtime test. Build hooks are intentionally allowed to use the network, so build-time and runtime rules must be measured separately.

### A-12 - Define exact v1 support instead of broad chain labels

**Severity:** High

The 1.0 release needs an explicit feature table. At minimum, decide whether it includes:

- BIP-39 passphrases.
- Multiple accounts and custom derivation paths.
- Imported private keys.
- Watch-only accounts.
- EVM legacy and EIP-1559 transactions.
- Arbitrary EVM contract calldata.
- ERC-20 and common token operations.
- Bitcoin P2PKH, P2WPKH, nested SegWit, Taproot, and multiple-input transactions.
- Bitcoin mainnet and testnet.
- Solana legacy and versioned transactions, SPL tokens, and multiple signers.
- TRON native and token transfers.
- Message-signing formats and signature normalization.

Anything not selected should be listed as an explicit exclusion. Account discovery, balances, fees, nonce retrieval, UTXO discovery, recent blockhash retrieval, and broadcasting correctly remain outside the package because they require networking.

### A-13 - Model signed results per family

**Severity:** Medium

A universal `SignedTransaction { rawBytes, hash }` is too rigid. Wallet Core outputs vary by chain, and a transaction ID may not always be returned or may require chain-specific interpretation.

Use a sealed `SignResult` hierarchy or typed results such as `EvmSignResult`, `UtxoSignResult`, and `SolanaSignResult`. Keep common fields only where their meaning is genuinely common.

### A-14 - Change the upstream update policy

**Severity:** Medium

The target of publishing an upstream update in less than seven days rewards speed despite limited behavioral coverage. Use candidate and stable channels:

- A watcher opens an upgrade candidate.
- The candidate receives source/changelog review, API diff, schema diff, artifact verification, and all vector tests.
- A risk-based soak or quarantine period applies before stable publication.
- Critical security updates have a separate expedited path.
- The previous stable release remains buildable and its artifacts remain available.

Behavioral diffs cover only existing vectors. They do not protect unverified operations, so the upgrade report must state the untested surface affected by upstream changes.

### A-15 - Reduce execution-process overhead

**Severity:** Medium

The delegated execution plan uses dozens of very small tasks, strict path ownership, numerous worktrees, and repeated debates. This improves attribution but risks optimizing each component separately and increasing integration cost.

Combine work that shares one architectural contract:

- FFI, protobuf, registry generation, and inventories as one generation-pipeline task.
- Native ownership, public lifecycle, and worker protocol as one vertical architecture task.
- Both packaging options under one measurement harness and one owner.
- Request model, builder, parser, vectors, and integration tests as one vertical slice per chain family.

Add an integration owner after every wave. Keep independent architecture reviews at the meaningful boundaries: after the EVM/native spike, before public alpha, and before 1.0. The orchestrator should be allowed to make and test small integration fixes rather than delegating every correction through another worktree.

## Recommended target architecture

```text
Flutter application
  |
  +-- WalletCoreSession
        |
        +-- WalletVault / LocalSigner
        |     Owns unlocked native wallet handles inside one worker
        |
        +-- ExternalSigner
        |     Hardware wallet, MPC, or HSM in a later release
        |
        +-- AccountDescriptor
        |     Plain network, address, public key, and derivation metadata
        |
        +-- Typed keyless requests
              |
              +-- EVM adapter
              +-- UTXO adapter
              +-- Solana adapter
              +-- Other family adapters
                    |
                    +-- Generated protobuf and FFI layer
                          |
                          +-- Verified Wallet Core native artifact
```

### Boundary rules

1. The public SDK contains stable domain types and never exposes generated enums, protobufs, FFI types, native pointers, or raw signing bytes by default.
2. Accounts describe identities; signers own or resolve keys.
3. Requests contain transaction intent and required public chain data, never secrets.
4. Family adapters encode keyless Wallet Core inputs and parse typed results.
5. Only the selected signer path injects private keys.
6. The worker owns every native secret-bearing handle and performs deterministic internal cleanup.
7. Public remote resources close asynchronously.
8. Advanced APIs expose raw capabilities with a separate, weaker safety contract.
9. The native artifact, bindings, and SDK are released as one verified compatibility set.

## Recommended plan changes before implementation

### Phase 0

Add four architecture decisions before creating the public package skeleton:

1. **Domain model:** chain family, network, asset, account, key locator, and upstream coin mapping.
2. **Lifecycle protocol:** session state machine, worker ownership, asynchronous close, and failure behavior.
3. **Signing model:** single-key, multi-key, partial signing, and external-signer boundaries.
4. **Distribution contract:** artifact retention, identity, package release set, signing, SBOM, and rollback.

Move the initial threat model and `SECURITY.md` into this phase.

### M0 - Ethereum vertical slice

Keep the packaging comparison and EIP-1559 vector. Add:

- Stable public domain types instead of a generated public enum.
- Keyless request encoding.
- The native build-identity check.
- An actual packaged-dependency consumer test.
- Android 16 KB alignment and iOS release-archive checks.

Use synchronous signing internally during the spike if that keeps the comparison small. Measure signing duration before committing to a background worker.

### M1 - Architecture validation with Bitcoin and Solana

Use Bitcoin specifically to validate multi-key resolution with at least two derivation paths. Use Solana to validate a second transaction model and signer-result type. Implement the worker only after its ownership and asynchronous lifecycle contract are fixed.

### M2 - Public alpha

Publish only the typed EVM, Bitcoin, and Solana surfaces. Keep all raw protobuf signing under `advanced.dart`. Publish an exact feature/variant matrix, `SECURITY.md`, lifecycle guidance, and the artifact-retention policy.

### M3 and M4

Add the update candidate/stable process, reproducibility evidence, broader chain-family coverage, independent security review, and full release-set validation.

## Architecture decisions to add

Suggested new ADRs or PRD decisions:

- `DECISION-11`: Public chain/network/asset/account model.
- `DECISION-12`: Worker protocol and asynchronous lifecycle.
- `DECISION-13`: Multi-key and external-signer key-resolution model.
- `DECISION-14`: Coordinated package versioning and artifact retention.
- `DECISION-15`: Exact v1 transaction variants and exclusions.
- `DECISION-16`: Capability evidence terminology and matrix granularity.

## Final recommendation

Keep the product vision and the three-layer direction, but pause implementation after basic repository initialization until A-01 through A-06 are reflected in a PRD v1.2 and corresponding phase tasks. Those issues affect the public API, security guarantees, worker lifecycle, Bitcoin support, and the meaning of advertised chain coverage. Fixing them after the alpha would cause breaking API changes and potentially require replacing the signing architecture.

Once those decisions are recorded, the project has a credible path to becoming a safe, practical Flutter SDK over Trust Wallet Core.

## External technical references

- Dart build hooks and native assets: https://dart.dev/tools/hooks
- Flutter native-code integration: https://docs.flutter.dev/platform-integration/bind-native-code
- Android 16 KB page-size requirements: https://developer.android.com/guide/practices/page-sizes
- Apple privacy manifests for third-party SDKs: https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk
- Apple XCFramework origin verification: https://developer.apple.com/documentation/Xcode/verifying-the-origin-of-your-xcframeworks
- GitHub Actions secure-use guidance: https://docs.github.com/en/actions/reference/security/secure-use
- Trust Wallet Core repository: https://github.com/trustwallet/wallet-core
