# Phase 3 — M2: Public SDK alpha on pub.dev

Back to [EXECUTION_PLAN.md](../EXECUTION_PLAN.md) · Status in [PROGRESS.md](../PROGRESS.md)

## Goal (PRD §18, M2)

API freeze candidate for §10; error hierarchy; cookbook (5 guides including secure storage and "what we wipe"); `advanced` import; family helpers for EVM, UTXO, and Solana only.

## Exit criteria (verbatim from PRD §18)

`0.x` published; API review checklist passed; capability matrix published; no `dart:ffi` or protobuf types in public signatures (lint-enforced).

## Tasks

| ID | Task | Impl | Size | Depends on | Owns (only these paths) | Flags |
|---|---|---|---|---|---|---|
| T3.1 | API review audit against PRD §10 → `docs/api_review.md` | claude `--read-only` then agy writes the doc from the report | M | Phase 2 closed | `docs/api_review.md` | human approves the change list |
| T3.2 | Apply the approved API freeze changes | claude | L, design | T3.1 + human | `packages/wallet_core_flutter/lib/**` (excluding families), `test/**` | breaking changes allowed; `0.x` |
| T3.3 | `advanced.dart` export: bindings, protobuf, same-isolate `HDWallet`, and `RawSigningInput` (raw protobuf signing lives only here) + memory-responsibility docs | agy | S | T3.2 | `lib/advanced.dart`, `lib/src/advanced/raw_signing.dart`, `docs/cookbook/advanced.md` | |
| T3.4 | `StoredKey`: encrypted keystore import/export via upstream | claude | M, security | T3.2 | `lib/src/keystore/`, `test/keystore/`, `test_vectors/keystore/` | |
| T3.5 | `PrivateKey` / `PublicKey` typed wrappers (advanced surface only) | claude | M, security | T3.2 | `lib/src/keys/`, `test/keys/` | |
| T3.6 | EVM family helpers (chain-id presets, ERC-20 transfer request, contract call data request) | claude | M | T3.2 | `lib/src/families/evm/helpers/`, `test/families/evm/helpers/`, `test_vectors/ethereum/helpers.yaml` | |
| T3.7 | UTXO family helpers (fee estimation from plan, address-type selection, change handling) | claude | M | T3.2 | `lib/src/families/utxo/helpers/`, tests, vectors | |
| T3.8 | Solana family helpers (SPL token transfer request, priority fee) | claude | M | T3.2 | `lib/src/families/solana/helpers/`, tests, vectors | |
| T3.9 | Cookbook part 1: hello wallet, error handling, background signing | agy | S | T3.2 | `docs/cookbook/{hello_wallet,errors,background_signing}.md` | |
| T3.10 | Cookbook part 2: secure storage with `StoredKey`, "what we wipe" guide (links `docs/security/memory_contract.md`) | agy | S | T3.4, T3.3 | `docs/cookbook/{secure_storage,what_we_wipe}.md` | |
| T3.11 | pub.dev readiness and release set: `pana` clean, `dart doc`, CHANGELOGs naming the upstream tag, metadata, LICENSE/NOTICE in each package, disclaimer text; exact cross-package pins, release-set id embedded in all three packages and checked at `initialize()`, a CI job resolving the hosted dependency graph without path overrides, recovery-release procedure | claude | M | T3.3–T3.10, T3.13 | `packages/*/CHANGELOG.md`, `packages/*/README.md`, `packages/*/pubspec.yaml`, `packages/*/LICENSE`, `docs/releases/process.md`, `.github/workflows/release-set.yml` | |
| T3.12 | Publish `0.x` as one release set | human | — | T3.11, D3 | — | orchestrator runs `melos publish --dry-run`; the human publishes native → bindings → SDK; a fresh app installs the hosted versions and signs a vector before the release is announced |
| T3.13 | `SECURITY.md`, v1 feature/exclusion table (PRD S9, DECISION-10), artifact-retention policy | claude | M, security | T3.2, T0.12 | `SECURITY.md`, `docs/features_v1.md`, `docs/artifact_retention.md` | human records DECISION-10 |
| D3 | Phase-3 debate | codex | — | all | none | read-only |

## Task notes

**T3.1 — API review.** The read-only session walks the public export against every bullet of PRD §10.2 and the hello-wallet sample of §10.1, and lists: missing surface, naming inconsistencies, lifecycle gaps, places where a request could carry key material, and error types that are not thrown where the PRD says. The report is turned into `docs/api_review.md` with a proposed change list. The human approves or trims the list; T3.2 implements only what was approved.

**T3.4 — StoredKey.** Import and export of upstream's encrypted keystore (`TWStoredKey`) with password handling documented under §11.3 rules; no persistence in the SDK. Vectors from upstream keystore tests.

**T3.6 – T3.8 — Helpers.** Each helper produces a request value or plan; none signs. Each ships with at least one vector so the matrix can mark it Tested. Helpers beyond these three families are out of scope until M2 exit (PRD §10.2).

**T3.11 — Readiness.** `pana` score target ≥ 140 (PRD §20); every package's description carries the disclaimer; no forbidden words; the compatibility manifest is included in the native package and mirrored in the other two packages' metadata (PRD §15.3). The three packages ship as a release set (PRD §15.4): exact pins, one release-set id, a hosted-graph CI job, and a documented publication order and recovery release.

**T3.13 — Security and scope docs.** `SECURITY.md` with the private channel and response expectations; the v1 feature table naming per family which transaction and message variants are Tested, exposed only, or excluded (BIP-39 passphrases, imported keys, watch-only, Taproot, versioned Solana transactions, multisig, and similar each listed); the artifact-retention policy (primary content-addressed location, mirror, promise). The feature table is the human's DECISION-10 record.

## Wave schedule

| Wave | Tasks in parallel | Notes |
|---|---|---|
| W1 | T3.1 | read-only audit → human approves the change list |
| W2 | T3.2 | solo; touches the whole public surface |
| W3 | T3.3, T3.4, T3.5 → T3.6, T3.7, T3.8 as slots free | disjoint directories |
| W4 | T3.9, T3.10, T3.13 → T3.11 when T3.13 lands | |
| — | T3.12 | human publishes after D3 |
| D3 | API critique, docs accuracy, readiness | then triage, rework, tag `phase-3-closed` |

## D3 — Debate brief outline

- **Agreed points:** every §10.2 bullet has a public type; `lint:public-api` is green; five cookbook guides exist; `pana` output attached; variant-aware matrix published; `SECURITY.md`, the v1 feature table, and the retention policy exist; the hosted-install smoke passed.
- **Contested points:** any API choice from T3.2 the human flagged; helper scope (what is in EVM/UTXO/Solana helpers and why nothing else); DECISION-7 stays "in SDK" (human).
- **Questions:** Is raw protobuf signing reachable from the default import by any path? Does the feature table match the matrix exactly? Does any cookbook example violate §11.3 (for example holding a mnemonic longer than needed)? Does any public doc comment over-claim on wiping, reproducibility, or audits? Is the `advanced.dart` warning sufficient? Would a P1 team reading the README understand what is Tested versus exposed?

## D0 follow-ups binding on Phase 3 (added 2026-09-07)

- **T3.7** provides the helper that builds `UtxoInput.script` bytes from an address or public key, which the DECISION-13 sketch leaves to the caller (D0, DECISION-13 note).
- **T3.13** publishes the retention policy only with the wording DECISION-14 §3.2 settles after D0 (no promise about third-party availability) and after mirror pricing, account ownership, and a restore drill are verified.
