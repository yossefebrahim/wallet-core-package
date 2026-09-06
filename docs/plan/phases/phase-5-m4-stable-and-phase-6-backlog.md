# Phase 5 — M4: 1.0 stable · Phase 6 — M5 backlog

Back to [EXECUTION_PLAN.md](../EXECUTION_PLAN.md) · Status in [PROGRESS.md](../PROGRESS.md)

## Phase 5 goal (PRD §18, M4)

Remaining top-chain families with vectors; external review (S6); migration notes from `flutter_trust_wallet_core` and `wallet_core_bindings`.

## Exit criteria (verbatim from PRD §18)

1.0 published; review findings closed or documented; all *Tested* claims traceable to inventory.

Plus PRD §19 release acceptance criteria 1–8, run in full.

## Tasks

Each new family is a pair: `a` = vectors (agy, S), `b` = request types, builder, parser, helpers where cheap (claude, M or L). The `b` task depends on its `a` task and on T2.0's architecture; families are disjoint directories, so pairs run in parallel.

| ID | Task | Impl | Size | Depends on | Owns (only these paths) | Flags |
|---|---|---|---|---|---|---|
| T5.1 | EVM chain-ID matrix: vectors + parameterized tests for chains sharing Ethereum's signer | agy | M | Phase 4 closed | `test_vectors/evm_chains/`, `test/families/evm/chain_matrix_test.dart`, `lib/src/families/evm/chains.dart` | |
| T5.2a / T5.2b | Litecoin, Dogecoin, Bitcoin Cash via the UTXO family | agy / claude | S / M | T2.5 | `test_vectors/{litecoin,dogecoin,bitcoincash}/` / `lib/src/families/utxo/coins/`, tests | |
| T5.3a / T5.3b | TRON | agy / claude | S / M | T2.0 | `test_vectors/tron/` / `lib/src/requests/tron/`, `lib/src/families/tron/`, tests | |
| T5.4a / T5.4b | Cosmos family | agy / claude | S / L | T2.0 | `test_vectors/cosmos/` / `lib/src/requests/cosmos/`, `lib/src/families/cosmos/`, tests | |
| T5.5a / T5.5b | TON | agy / claude | S / M | T2.0 | `test_vectors/ton/` / `lib/src/requests/ton/`, `lib/src/families/ton/`, tests | |
| T5.6a / T5.6b | XRP | agy / claude | S / M | T2.0 | `test_vectors/xrp/` / `lib/src/requests/xrp/`, `lib/src/families/xrp/`, tests | |
| T5.7 | Threat model v1 revision (from T0.12's v0, covering the shipped worker, loader, signer, and adapter) and `SECURITY.md` update | claude | M, security | Phase 4 closed | `docs/security/threat_model.md`, `SECURITY.md` | |
| T5.8 | External review scope pack: components (wrappers, worker, loader, adapter if chosen), entry points, test harness instructions | claude | M, security | T5.7 | `docs/security/review_scope.md` | DECISION-4 (human: funding and scope) |
| T5.9 | Migration guides from `flutter_trust_wallet_core` and `wallet_core_bindings` | agy | M | T3.12 | `docs/migration/` | facts only; no license claims |
| T5.10 | Remediate external review findings | claude | varies | external review | as each finding dictates, one task per finding | rework-style tasks `T5.R<n>` |
| T5.11 | 1.0 release checklist: PRD §19 items 1–8 executed and recorded | orchestrator + human | — | all | `docs/releases/1.0.0-acceptance.md` | human publishes |
| D5 | Phase-5 debate | codex | — | all | none | read-only |

## Task notes

**T5.1 — EVM chain matrix.** One parameterized test over a table of chain IDs (Ethereum mainnet, Polygon, BNB Chain, Arbitrum, Optimism, Base, Avalanche C-Chain, and others upstream's registry marks as Ethereum-signer coins); each row needs a vector to be Tested, otherwise the matrix marks it exposed.

**T5.2b – T5.6b — Families.** Follow the T2.0 architecture exactly: key-less `encodeKeylessInput` and typed `parseSigningOutput` per family; `KeyLocator`s for every key the chain needs (Cosmos and TON multi-signer cases fail with typed errors unless a vector proves them); requests without key material; each (operation, variant) exposure declared in `lib/src/capabilities.dart`. Helpers only where a single vector-backed helper is obvious. Anything without a vector is reachable only through the advanced raw path and appears in the v1 feature table as exposed-unverified or excluded (DECISION-10, recorded by the human on the orchestrator's recommendation).

**T5.7 — Security docs.** Revise the Phase 0 threat model against the shipped code: the FFI glue, protobuf construction, artifact acquisition, the loader, the worker, and the adapter if chosen, and state what upstream audits do not cover (PRD §4, §16 S1). `SECURITY.md` (published in Phase 3 by T3.13) is updated with the 1.0 response expectations.

**T5.11 — Release checklist.** The 1.0 set is published in the §15.4 order and a fresh app installs the hosted versions before announcement. Each §19 item is run and its evidence linked: clean regeneration byte-identity, artifact verification with a corrupted-artifact negative test, full inventory on both platforms, both diffs linked from the changelog, public-surface lint, example release builds from a clean clone, changelog naming the upstream tag and any downgraded capability, maintainer approval.

## Wave schedule

| Wave | Tasks in parallel | Notes |
|---|---|---|
| W1 | T5.1, T5.2a, T5.3a | vectors first |
| W1b | T5.4a, T5.5a, T5.6a | |
| W2 | T5.2b, T5.3b, T5.4b | |
| W3 | T5.5b, T5.6b, T5.7 | |
| W4 | T5.8, T5.9 | human decides DECISION-4 and commissions the external review |
| — | external review runs | outside the plan's control |
| W5 | T5.10 rework tasks, one per finding | |
| W6 | T5.11 | human publishes 1.0 |
| D5 | debate | then triage, rework, tag `phase-5-closed` |

## D5 — Debate brief outline

- **Agreed points:** every §19 item with evidence; every Tested cell traceable to a vector and a CI result; review findings closed or documented.
- **Contested points:** any finding the team documented instead of fixing; DECISION-10 outcomes per coin.
- **Questions:** Is any README or pub.dev claim stronger than the evidence (Tested counts, reproducibility, audits, AGPL)? Are the migration guides free of legal claims? Does any family builder contain logic that belongs upstream (PRD §6 non-goals)?

---

## Phase 6 — M5 backlog (not planned in detail)

Listed so nothing in the PRD is lost; tasks are written when Phase 5 closes.

- macOS and Linux desktop through the same FFI path (native package gains host artifacts; T1.2's macOS host library is the seed).
- Web and Windows through a `_wasm` sibling of the native package (PRD §6 designed the boundary for this).
- `ExternalSigner` implementations (hardware wallet, MPC, remote HSM) behind the `Signer` interface; `compile` with `TWTransactionCompiler` pre-image hashes where T2.9 found availability.
- Per-family package split if size or cadence data argues for it (DECISION-7 revisit).
- Per-wallet worker pool if T2.10 throughput data argues for it.
