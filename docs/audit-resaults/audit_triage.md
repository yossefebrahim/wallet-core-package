# Architecture audit — triage

| | |
|---|---|
| **Audit** | [wallet_core_flutter_architecture_audit.md](wallet_core_flutter_architecture_audit.md), September 7, 2026 |
| **Triaged** | September 7, 2026, by the orchestrating Claude session |
| **Applied to** | PRD v1.2 ([§25 changelog](../wallet_core_flutter_prd.md)), execution plan 1.1 ([plan §7](../plan/EXECUTION_PLAN.md)); v1.1 archived at `docs/archive/wallet_core_flutter_prd_v1.1.md` |

Buckets: **accept** (adopted as written), **reframe** (the problem is real, the fix was changed), **reject** (not adopted, reason given). Every upstream fact was checked against tag 4.8.0 on September 7, 2026.

## Evidence checked before triage

| Claim in the audit | What was checked | Result |
|---|---|---|
| Bitcoin signing needs several keys (A-03) | `src/proto/Bitcoin.proto` at 4.8.0 | `SigningInput` has `repeated bytes private_key = 6` |
| Appending one key field does not generalize (A-05) | `src/proto/Solana.proto` | three key fields: `private_key`, `fee_payer_private_key`, `nonce_account_private_key` |
| Outputs differ per chain (A-13) | `SigningOutput` in Bitcoin, Solana, Ethereum, Cosmos protos | Bitcoin `bytes encoded` + `string transaction_id`; Solana `string encoded`; Ethereum `bytes encoded`; Cosmos base64/json |
| `TWAnySignerSign` is one global symbol (A-06) | `include/TrustWalletCore/TWAnySigner.h` | one function taking `(TWData*, enum TWCoinType)`; no per-coin symbol |
| The registry conflates networks (A-04) | `registry.json` | 167 entries; 60 EVM networks are separate coins with `chainId`; Bitcoin testnet exists only as a derivation named `testnet`; no asset model |
| No usable version symbol (A-07, PRD §15.3 [UNVERIFIED]) | header list at 4.8.0 | only `TWHDVersion.h` and `TWStellarVersionByte.h`, both unrelated |
| `TWTransactionCompiler` exists (PRD §10.2 [UNVERIFIED]) | `include/TrustWalletCore/TWTransactionCompiler.h` | `PreImageHashes(coin, input)` and compile with signatures + public keys present |
| NativeFinalizer cannot post a message (A-02) | Dart semantics | true for `NativeFinalizer`; false for the managed `Finalizer`, which runs Dart code |

## Verdict per finding

| Finding | Severity claimed | Bucket | What changed | Where |
|---|---|---|---|---|
| A-01 Raw signing contradicts the keyless invariant | Blocking | **reframe** | `RawSigningInput` removed from the default SDK and placed under `advanced.dart`. The proposed "descriptor-aware validation instead of naming conventions" is not adopted: upstream protos carry no secret-marker option, so any validator ends up matching field names. A generated per-family list of key field names (`key_fields.json`, T1.4) is used and no generic guarantee is claimed. | PRD §10.2, §11.4 family boundary, §25; plan rule 6, T1.4, T1.12, T3.3 |
| A-02 Worker ownership vs synchronous disposal | Blocking | **accept**, with one correction | Two lifecycles: synchronous `dispose()` for internal handles (§11.2, now scoped), asynchronous idempotent `close()` for public proxies; §14.3 session state machine and protocol; accounts are descriptors; the worker is built after the protocol exists. Correction: a Dart `Finalizer` on the proxy can post `Dispose(ref)`, so the fallback path exists (new §11.2 item 8). | PRD §10.2, §11.2, §14.2, §14.3, DECISION-12; plan T0.11, T1.11, T2.1, rule 12 |
| A-03 Signer cannot represent multi-key transactions | Blocking (Bitcoin) | **accept** | `Signer.sign(request, Set<KeyLocator>)`; UTXO inputs carry locators; typed errors for multisig, partial, watch-only; M1 requires a two-input, two-path Bitcoin vector. | PRD §10.2, §13.3, DECISION-13; plan T2.0, T2.2, T2.5 |
| A-04 Domain model conflates chain, network, asset, account | Blocking (public API) | **reframe** | The generated `CoinType` leaves the public surface; a thin stable coin/network facade maps to the registry, with explicit network where upstream has only a derivation. The full five-type model (chain family, network, asset, account, address format) is not adopted for 1.0: EVM networks are already distinct registry coins, and assets are a PRD non-goal until helpers need them. | PRD §8, §9, §10.2, DECISION-11; plan T0.11, T1.5, T1.11, T1.15, rule 12 |
| A-05 Phase 2 hardcodes Approach A | Blocking | **accept** | Family contract is `encodeKeylessInput` / `parseSigningOutput`; only the signer injects keys after a key-field check; Approach B is a per-family adapter, never a universal append; repository rule on serialization clarified (signing-input encoding allowed, signed-transaction serialization not). | PRD §11.4; plan rule 2, T1.12, T1.13, Phase 2 architecture constraint |
| A-06 Capability model produces misleading evidence | Blocking (docs) | **accept**, vocabulary kept | Variant axis added (coin × operation × variant × platform × tag); "generated" derives from proto descriptors and the registry, never from the global signer symbol; docs name verified variants. The audit's four-level vocabulary is not adopted: the PRD's three levels are kept, and "integration verified" is what device CI already proves. | PRD §13.1, §13.2; plan T0.8, T2.8, T2.11 |
| A-07 Artifact durability and identity | High | **accept** | Build-identity symbol `wcf_build_info()` (verified: upstream has none); runtime library hashing dropped; content-addressed immutable URLs; retention promise and mirror before 1.0; extended manifest fields; SBOM [REC]. DECISION-9 must now allow the symbol (companion library for mirrored prebuilts, or build from source). | PRD §12.3, §15.3, DECISION-9, DECISION-14; plan T0.5, T1.2, T1.7, T3.13 |
| A-08 Coordinate the three package versions | High | **accept** | Exact cross-package pins, release-set id embedded in all three packages and checked at `initialize()`, hosted-graph CI job, publication order native → bindings → SDK, hosted-install smoke before announcing, recovery-release procedure. | PRD §8, §15.4, DECISION-14; plan T0.1, T3.11, T3.12 |
| A-09 Move security work earlier | High | **accept** | Threat model v0 at M0 start (T0.12), revised per milestone (T5.7); `SECURITY.md` before the public alpha (T3.13). External review stays before 1.0. | PRD §16 S6, §18; plan T0.12, T3.13, T5.7 |
| A-10 Current mobile binary requirements | High | **accept** | §12.2 steps 8–11: 16 KB alignment, per-ABI execution or drop, `libc++_shared` conflict fixture, iOS minimum target/archive/visibility/duplicate symbols/privacy manifest/signed xcframework [REC], packaged-dependency consumption. One shared measurement harness (T1.19). | PRD §12.2; plan T1.2, T1.8, T1.9, T1.16, T1.19 |
| A-11 Hostile-input and integration testing | High | **accept** | S5 gains the hostile-input list; S4 gains a runtime-dependency policy separate from build-time network; a dedicated suite with a fault-injection seam (T2.12); identity-mismatch negative test (T1.17). | PRD §16 S4, S5; plan T1.17, T2.12 |
| A-12 Exact v1 support instead of chain labels | High | **accept** | S9 v1 feature and exclusion table, extending DECISION-10; produced before the alpha (T3.13). | PRD §16 S9, DECISION-10; plan T3.13 |
| A-13 Model signed results per family | Medium | **accept** | Sealed `SignResult` family with per-chain members. | PRD §10.2; plan T2.0, T2.5–T2.7 |
| A-14 Upstream update policy | Medium | **reframe** | Candidate/stable channels with an expedited security path adopted as [REC], and upgrade reports must name the unverified surface upstream touched. The sub-7-day freshness target stays because it is a stated differentiator (PRD §4, §20); pre-release versions give both. Soak length is the human's policy. | PRD §15.2, §18 M3; plan T4.3 |
| A-15 Reduce execution-process overhead | Medium | **partly accept** | Adopted: one shared packaging harness and owner (T1.19); the orchestrator may make trivial integration fixes inline; ownership, lifecycle, and worker are designed together in one ADR batch (T0.11) and implemented separately. Not adopted: dropping per-phase debates (a stated requirement; they are cheap read-only runs); merging vector tasks into family implementations (the agy lane and provenance discipline depend on the split); merging the generation tasks (they are disjoint and already parallel). | plan §2.2 step 8, §7, T0.11, T1.19 |

## Decision mapping

| Audit proposal | Adopted as | Note |
|---|---|---|
| DECISION-11 public chain/network/asset/account model | PRD DECISION-11 | thin facade; assets deferred |
| DECISION-12 worker protocol and asynchronous lifecycle | PRD DECISION-12 | §14.3 written out; DECISION-3 keeps the worker-vs-per-call question |
| DECISION-13 multi-key and external-signer key resolution | PRD DECISION-13 | includes sealed results |
| DECISION-14 coordinated versioning and artifact retention | PRD DECISION-14 | includes identity symbol and SBOM |
| DECISION-15 exact v1 variants and exclusions | folded into DECISION-10 and S9 | one table, one owner |
| DECISION-16 capability evidence terminology | §13 amendment, no decision needed | vocabulary kept, granularity added |

## What the human still decides

- DECISION-5 (names), DECISION-4 (review funding), DECISION-7 (family packages), DECISION-10 (v1 table), and the outcomes of DECISION-11 to DECISION-14 after D0 and D1a.
- Retention promise and mirror cost (DECISION-14).
- Soak length for stable publication (A-14).
- Whether `armeabi-v7a` is tested or dropped (A-10).

## Not adopted, in one place

- A-01's descriptor-aware key validator as a generic guarantee.
- A-04's full five-type domain model for 1.0.
- A-06's renamed four-level vocabulary.
- A-15's removal of per-phase reviews, merging of vector tasks, and merging of generation tasks.
- The audit's "pause everything after repository init": Phase 0 and Phase 1 waves 1–3 are unaffected; the gate is at T1.11 (public surface), which now requires DECISION-11/12/13 recorded.
