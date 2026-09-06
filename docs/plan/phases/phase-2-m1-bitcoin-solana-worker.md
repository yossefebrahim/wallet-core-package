# Phase 2 — M1: Bitcoin, Solana, message signing, signing worker, capability matrix

Back to [EXECUTION_PLAN.md](../EXECUTION_PLAN.md) · Status in [PROGRESS.md](../PROGRESS.md) · Plan 1.1: multi-key signer, sealed results, worker built to the §14.3 protocol, two-input Bitcoin proof, variant-aware matrix, hostile-input suite (T2.12).

## Goal (PRD §18, M1, v1.2)

Multi-key signer with `KeyLocator`s; sealed `SignResult` types; UTXO family request/plan/sign; Solana sign; Ethereum message signing (personal and EIP-712); the signing worker built to the §14.3 protocol, with latency measurements; variant-aware capability matrix and vector inventory generated in CI; hostile-input suite (S5).

## Exit criteria (verbatim from PRD §18, v1.2)

Vectors for BTC (P2WPKH single-input transfer with plan **and** a two-input spend from two derivation paths), SOL (transfer), ETH message signing pass on both platforms; worker state-machine, queue-bound, timeout, cancellation, close-during-in-flight, and crash-injection tests; DECISION-3 recorded; README shows generated/exposed/tested counts per variant.

## Architecture constraint (from DECISION-12 and DECISION-13, implemented by T2.0)

Every chain family lives in `lib/src/families/<family>/` and exposes two pure functions that never see key material, isolates, or native handles:

```dart
KeylessSigningInput encodeKeylessInput(TransactionRequest request);   // serialized upstream SigningInput, no key fields
SignResult parseSigningOutput(Uint8List output);                       // sealed: EvmSignResult, UtxoSignResult, SolanaSignResult, …
```

The signer owns key resolution and injection: `Signer.sign(request, Set<KeyLocator>)` resolves every locator (an HD path in a wallet ref, an imported key ref, later an external-signer key), checks the key-less bytes against the generated `key_fields.json` list, injects the keys upstream's schema expects (Bitcoin: `repeated private_key`, one per input; Solana: `private_key` and optionally `fee_payer_private_key`), and calls upstream. Both the same-isolate `LocalSigner.sync` (advanced) and the worker-backed `LocalSigner` call the same family functions, so T2.5, T2.6, and T2.7 depend only on T2.0, not on T2.1. The public `Wallet` is worker-backed with asynchronous `close()`; the same-isolate `HDWallet` lives behind `advanced.dart` (DECISION-12).

## Tasks

| ID | Task | Impl | Size | Depends on | Owns (only these paths) | Flags |
|---|---|---|---|---|---|---|
| T2.0 | Signing model in code: `Signer.sign(request, keys)`, sealed `KeyLocator`, sealed `SignResult`, `UtxoInput` with locator, `KeyResolutionError`; refactor the Phase 1 EVM path onto it; `docs/architecture/signing.md` updated | claude | M, design | Phase 1 closed | `lib/src/signing/signer.dart`, `lib/src/signing/key_locator.dart`, `lib/src/signing/sign_result.dart`, `lib/src/requests/base.dart`, `lib/src/families/evm/` (refactor only), `lib/src/families/README.md`, `docs/architecture/signing.md` | |
| T2.1 | Signing worker isolate to the §14.3 protocol; async `LocalSigner`; `WalletCore.shutdown` | claude | L, security | T2.0 | `lib/src/worker/`, `lib/src/signing/local_signer.dart`, `lib/src/session/` (executor swap), `test/worker/` | replaces the in-process executor of T1.11 |
| T2.2 | Bitcoin vectors: P2WPKH address, plan, single-input transfer (`p2wpkh`), two-input spend from two derivation paths (`multi_input`) | agy | S | T0.8 | `test_vectors/bitcoin/` | |
| T2.3 | Solana vectors: address, transfer (`legacy`) | agy | S | T0.8 | `test_vectors/solana/` | |
| T2.4 | Ethereum message vectors: `personal`, `eip712` | agy | S | T0.8 | `test_vectors/ethereum/messages.yaml` | |
| T2.5 | UTXO family: `UtxoTransactionRequest` with per-input `KeyLocator`s, `plan`, sign | claude | L | T2.0, T2.2 | `lib/src/requests/utxo/`, `lib/src/families/utxo/`, `test/families/utxo/` | |
| T2.6 | Solana: `SolanaTransactionRequest.transfer`, sign, `SolanaSignResult` | claude | M | T2.0, T2.3 | `lib/src/requests/solana/`, `lib/src/families/solana/`, `test/families/solana/` | |
| T2.7 | Ethereum message signing: `EvmMessageRequest.personal`, `.typedData`, `signMessage`, `EvmMessageSignResult` | claude | M | T2.0, T2.4 | `lib/src/requests/evm/message_request.dart`, `lib/src/families/evm/message_*.dart`, `test/families/evm/message_*` | |
| T2.8 | Capability matrix generator (coin × operation × variant × platform), coverage checks, exclusions list | claude | M | T1.3, T1.4, T0.8 | `tools/matrix/`, `test_vectors/exclusions.yaml`, `test_vectors/results/` (CI output), `docs/capability_matrix.{md,json}` (generated), `lib/src/capabilities.dart`, melos `gen:matrix`, `matrix:check` | |
| T2.9 | Probes: `TWTransactionCompiler` per coin, message-signing input list | agy | S | T1.11 | `tools/probes/compiler_probe.dart`, `tools/probes/message_signing_probe.dart`, `docs/decisions/evidence/compiler_and_message_coverage.md` | needs host library or simulator |
| T2.10 | Worker integration tests on devices + latency/memory measurements | claude | M | T2.1, T2.5, T2.6, T2.7 | `integration_test/worker_*`, `tools/bench/`, `docs/decisions/DECISION-3-data.md` | device-gated |
| T2.11 | README counts from the matrix (per variant) | agy | S | T2.8 | `tools/matrix/readme_counts.dart`, README between `<!-- matrix-counts -->` markers | |
| T2.12 | Hostile-input and worker-fault test suite (PRD S5 v1.2) | claude | L | T2.1, T2.5, T2.6, T1.7 | `test/hostile/`, `packages/*_native/lib/src/fault_injection.dart` (test-only seam), `packages/*_bindings/test/hostile/` | |
| D2 | Phase-2 debate | codex | — | all | none | read-only |

## Task notes

**T2.0 — Signing model.** `KeyLocator` is sealed: `hdPath(walletRef, coin, derivationPath)`, `imported(keyRef)`, with `external(...)` reserved. `Signer.sign(request, keys)` plus a convenience that derives the single locator from an `Account` descriptor for single-key chains. `SignResult` is sealed with a small common base (encoded bytes when upstream returns bytes) and per-family members carrying what upstream actually returns (Bitcoin transaction id, Solana base64 string, Ethereum v/r/s). `UtxoInput(outpoint, amount, script, keyLocator)`. Unsupported cases (multisig, partial signing, watch-only) throw `UnsupportedOperationError` or `KeyResolutionError` with the reason. Acceptance: the Phase 1 Ethereum vector still passes through the new interface; the interface sketch in `docs/architecture/signing.md` and the code agree.

**T2.1 — Signing worker.** One background isolate owns every native wallet handle for the session and implements the §14.3 protocol exactly: states `initializing/ready/closing/closed/failed`; request ids on every message; a bounded queue that rejects with a typed error when full; per-operation timeouts; cancellation before start; `close()` during an in-flight operation on the same handle waits then disposes; idempotent `close()`/`shutdown()`. Messages: `CreateWallet(strength)`, `ImportWallet(mnemonic | entropy)` (the one message that carries a secret, documented as such), `DeriveAddress(walletRef, coin, path)`, `Sign(request, keyLocators)`, `SignMessage(request, keyLocators)`, `Plan(request)`, `Dispose(ref)`, `Shutdown`. Private keys are derived inside the worker for one operation and disposed immediately after. The worker loads the native library, verifies identity, and answers a symbol-lookup health check before `initialize()` completes. An uncaught error in the worker invalidates every ref; pending and future calls throw `WorkerTerminatedError`. `WalletCore.shutdown()` stops accepting work, resolves or rejects queued operations, disposes all handles, detaches finalizers, and awaits isolate exit. Public proxies keep the Dart `Finalizer` fallback from T1.11. `LocalSigner` posts to the worker; `LocalSigner.sync` remains under `advanced.dart`.

**T2.2 – T2.4 — Vectors.** Every entry has upstream provenance at the pinned commit and a `variant`. Bitcoin includes, for both entries, the UTXO set (outpoint, amount, script, derivation path per input), fee rate, expected plan (inputs chosen, fee, change) and the signed transaction bytes; the `multi_input` entry spends from two different derivation paths (for example `m/84'/0'/0'/0/0` and `m/84'/0'/0'/1/0`). Solana includes the recent blockhash and expected signed bytes; Ethereum messages include the exact message or typed-data JSON and the expected signature.

**T2.5 — UTXO family.** `UtxoTransactionRequest` (recipient, amount, fee rate, `UtxoInput` list each with its `KeyLocator`, change strategy, coin); `Signer.plan` returning a typed `UtxoPlan`; signing with the plan resolves one key per selected input into upstream's `repeated private_key`. Address validation for P2WPKH via `TWAnyAddress`; other script types throw `UnsupportedOperationError` until a vector exists. The builder is pure. Byte-for-byte against both T2.2 entries.

**T2.6 — Solana.** `SolanaTransactionRequest.transfer(to, lamports, recentBlockhash)`; builder and parser; `SolanaSignResult` carries the base64 encoded transaction; a request needing a separate fee payer or additional signers throws typed errors until a vector exists. Vector match.

**T2.7 — Ethereum message signing.** `EvmMessageRequest.personal(bytes)` and `.typedData(json)`; `Signer.signMessage`; builder uses `Ethereum.MessageSigningInput`; `EvmMessageSignResult`; vector match for both variants.

**T2.8 — Capability matrix.** Inputs: the proto descriptors and registry (generated column: a coin is *generated* for `sign` when its proto defines a signing input and the registry lists it; for `sign_message` when a message-signing input exists; for `plan`/`compile` from T2.9's probes; the global `TWAnySignerSign` symbol is never used as evidence), `lib/src/capabilities.dart` (exposed column: a registry of (coin, operation, variant) → typed | generic that SDK code maintains), and `test_vectors/results/<platform>.json` produced by CI (tested column: a vector for that exact variant passed on Android and iOS). Outputs `docs/capability_matrix.md` and `.json` at (coin, operation, variant, platform, upstream tag) granularity. `matrix:check` enforces PRD §13.2 (a) every Tested claim has a passing vector for that variant, (b) the matrix is regenerated not edited, (c) removing a vector or downgrading a level fails unless `exclusions.yaml` gains an entry with a reason. Non-tested cells read "exposed, unverified".

**T2.10 — Worker measurements.** Init time, median and 95th percentile sign latency for ETH/BTC/SOL through the worker versus `LocalSigner.sync`, memory before/after 1,000 signatures, and the protocol edge cases on real devices: close during in-flight sign, shutdown with pending calls, queue full, timeout, cancellation, worker crash injection. Results and the complexity assessment go to `DECISION-3-data.md`.

**T2.12 — Hostile-input suite.** A test-only fault-injection seam in the native package lets tests substitute native functions that return null, short, oversized, or garbage buffers; tests assert typed errors and no crash. Property-based fuzzing of FFI lengths, protobuf payloads fed to every `parseSigningOutput`, addresses, derivation paths, and numeric boundaries (amounts wider than the chain's integer width); wrong-network addresses (Bitcoin testnet address on mainnet and the reverse); worker queue limits, timeouts, cancellation, shutdown with pending work, crash injection (a test-only message that throws inside the worker). Wired into `melos run test` and CI.

## Wave schedule

| Wave | Tasks in parallel | Notes |
|---|---|---|
| W1a | T2.0, T2.2, T2.3 | |
| W1b | T2.4, T2.8, T2.9 | |
| W2 | T2.1, T2.5, T2.6 → T2.7 when a slot frees | all depend only on T2.0 (and their vectors) |
| W3 | T2.10, T2.12, T2.11 | device lock on T2.10 |
| D2 | DECISION-3; DECISION-12 worker model; DECISION-13 proof; matrix honesty; M1 exit | then triage, rework, tag `phase-2-closed` |

## D2 — Debate brief outline

- **Agreed points:** BTC (both variants), SOL, and ETH-message vectors pass on both platforms (CI run URLs); worker tests cover every §14.3 clause; the hostile-input suite runs in CI; README counts are generated per variant.
- **Contested points:** DECISION-3: long-lived worker vs per-call isolates vs hybrid, using T2.10 data; whether sequential processing is an acceptable throughput bound; DECISION-13 in practice: does the `KeyLocator` model hold for Bitcoin's repeated keys and Solana's fee payer without leaking keys into requests.
- **Questions:** Does any ref leak survive `shutdown()`? Can a native pointer cross the isolate boundary anywhere (PRD §14.1)? Does any family function receive key bytes? Is the key-field check run before every injection, including the multi-key path? Is every Tested cell backed by a vector for that exact variant and a passing result on both platforms? Is "generated" ever derived from the global signer symbol? Are exclusions justified? Does the mnemonic cross isolates more than once per import?
