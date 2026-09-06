# Phase 0 — Foundation (pre-M0)

Back to [EXECUTION_PLAN.md](../EXECUTION_PLAN.md) · Status in [PROGRESS.md](../PROGRESS.md) · Plan 1.1: adds T0.11 (ADR batch) and T0.12 (threat model v0) from the architecture audit.

## Goal

A repository in which three implementers can work concurrently: git, the monorepo skeleton with the canonical gates, a CI skeleton, the repository rules file, the decisions the PRD wants answered at "M0 start" (DECISION-5, DECISION-8, DECISION-9 and, since v1.2, DECISION-11 to DECISION-14), a first threat model, and proof that the delegation loop itself works on this machine.

## Exit criteria

1. `main` has the layout of plan §3. `melos bootstrap`, `melos run analyze`, `melos run format:check`, `melos run test` are green with one trivial test per package.
2. CI runs the same gates on push (validated statically until a remote exists).
3. PROGRESS.md → *Environment findings* records, per relay: network access, pub-cache writes, git inside a worktree, simulator/emulator control, and the exact working dispatch command.
4. `docs/decisions/DECISION-5.md`, `DECISION-8.md`, `DECISION-9.md` exist with evidence and a recommendation; the human has recorded DECISION-5. DECISION-9 states whether the chosen artifact source permits the build-identity symbol of PRD §12.3.
5. `docs/decisions/DECISION-11.md` to `DECISION-14.md` exist as decision records with options, evidence, and a recommendation; D0 has adjudicated them and the human has recorded the outcome. No public SDK code is written before this.
6. `docs/security/threat_model.md` v0 exists (PRD §16 S6 list).
7. `compat_manifest.json` and `test_vectors/` exist with validators wired to `manifest:validate` and `vectors:validate`; the vector schema carries a `variant` field.
8. D0 findings triaged; tag `phase-0-closed`.

## Repository init (delegated to `agy-delegate`, plan §2.9)

The orchestrator writes `briefs/INIT_repo.md` and dispatches it to `agy-delegate` before W0. agy runs, in the repository root:

```bash
git init -b main
git add docs
git commit -m "docs: PRD v1.2, delegated execution plan 1.2, audit and triage"
```

and reports `git log`, `git status`, and `git ls-files | wc -l`. No remote is added and nothing is pushed. Every later commit, fast-forward, and tag in this phase is likewise an agy commit brief (`briefs/LAND_<id>.md`, `briefs/TAG_phase-0.md`). Optional: run `delegate-setup` once with the human to define lanes `feature` → claude, `small` → agy, `debate` → codex read-only, so later dispatches can use `--lane`.

## Tasks

| ID | Task | Impl | Size | Depends on | Owns (only these paths) | Flags |
|---|---|---|---|---|---|---|
| T0.1 | Monorepo skeleton, canonical gates, AGENTS.md | claude | M, design | — | `.gitignore`, `melos.yaml`, `pubspec.yaml`, `analysis_options.yaml`, `AGENTS.md`, `CLAUDE.md`, `LICENSE`, `THIRD_PARTY_NOTICES.md`, `README.md`, `packages/*/` (pubspec, lib stub, one test), `tools/README.md` | solo wave |
| T0.2 | CI skeleton | claude | M | T0.1 | `.github/` | |
| T0.3 | Delegate smoke test through all three relays | orchestrator | S | T0.1 | scratch worktrees only | nothing lands |
| T0.4 | DECISION-8: intent of upstream `flutter/` directory | claude | S | T0.3 | `docs/decisions/DECISION-8.md`, `docs/decisions/evidence/upstream-flutter-dir.md` | network |
| T0.5 | DECISION-9: inspect the 19 release assets of 4.8.0; identity-symbol feasibility | claude | M | T0.3 | `docs/decisions/DECISION-9.md`, `docs/decisions/evidence/release-assets-4.8.0.md` | network, large downloads |
| T0.6 | DECISION-5: pub.dev name availability | agy | S | T0.3 | `docs/decisions/DECISION-5.md` | network; human decides |
| T0.7 | Compat manifest skeleton + validator | agy | S | T0.1 | `compat_manifest.json`, `tools/manifest/` | |
| T0.8 | Test-vector inventory schema (with `variant`) + loader + validator | agy | S | T0.1 | `test_vectors/`, `tools/vectors/` | |
| T0.9 | Evidence: which upstream security audits exist | agy | S | T0.3 | `docs/decisions/evidence/upstream-audits.md` | network |
| T0.10 | Apply DECISION-5 rename (only if names change) | agy | S | T0.6 + human | `packages/*` names, pubspecs, `README.md`, `AGENTS.md` | conditional |
| T0.11 | Architecture decision records: DECISION-11 (public coin/network/account facade), DECISION-12 (session lifecycle and worker protocol), DECISION-13 (signing model: `KeyLocator`s, multi-key, sealed results, external signers), DECISION-14 (distribution contract) | claude | L, design | T0.5, T0.8, T0.12 | `docs/decisions/DECISION-11.md` … `DECISION-14.md`, `docs/architecture/public_model.md`, `docs/architecture/lifecycle.md`, `docs/architecture/signing.md` | adjudicated at D0; human records |
| T0.12 | Threat model v0 for the glue layer | claude | M, security | T0.1 | `docs/security/threat_model.md` | |
| D0 | Phase-0 debate | codex | — | all above | none (read-only) | |

## Task notes

**T0.1 — Monorepo skeleton.**
Deliver the layout of plan §3 with three packages (`wallet_core_flutter`, `wallet_core_flutter_bindings`, `wallet_core_flutter_native`, placeholder names), each with `pubspec.yaml`, a `lib/<name>.dart` stub, and one trivial test. Add `melos` (pinned version recorded in the root `pubspec.yaml` dev dependencies or a documented `dart pub global activate melos <version>`) with scripts `analyze`, `format:check`, `test` exactly as named in plan §2.5; later tasks add their own scripts. `analysis_options.yaml` uses `package:lints` with `strict-casts`, `strict-inference`, `strict-raw-types` on. `AGENTS.md` contains the twelve rules of plan §2.4, the gate table, and the layout; `CLAUDE.md` contains exactly `@AGENTS.md`. `LICENSE` is MIT. `THIRD_PARTY_NOTICES.md` holds a placeholder that T1.1 fills with the upstream NOTICE. `README.md` carries the disclaimer, "pre-alpha, nothing published", and a `<!-- matrix-counts -->` placeholder. `.gitignore` covers `.dart_tool/`, `build/`, `third_party/`, `eval/**/build/`, IDE files. Dart SDK constraint `^3.12.0` as a placeholder that DECISION-6 revises. The SDK package's pubspec pins the other two packages at exact versions from the start (PRD §15.4).
Acceptance: the four gates are green from a clean clone; no package name contains "trust"; `CLAUDE.md` is exactly one line; no networking package appears in any package's runtime dependencies (PRD S4).

**T0.2 — CI skeleton.**
`.github/workflows/ci.yml`: on push and pull request, an `ubuntu-latest` job pinning Flutter 3.44.1, activating the same melos version, then `melos bootstrap`, `analyze`, `format:check`, `test`. Two `macos-latest` jobs `android-emulator` and `ios-simulator` exist as `workflow_dispatch`-only placeholders with a comment naming T1.17. Acceptance: YAML parses; the ubuntu job runs exactly the local gate commands; no secrets referenced.

**T0.3 — Delegate smoke test.**
The orchestrator writes one trivial brief ("add `tools/smoke/smoke.dart` printing the Dart version and a test for it; run `melos run test`") and dispatches it unchanged to `claude-delegate`, `agy-delegate`, and `codex-delegate` (write mode) in three scratch worktrees. For each relay record: terminal status; whether `dart pub get` reached the network; whether `~/.pub-cache` was writable; whether `git status` worked inside the worktree; whether `flutter devices` / `xcrun simctl list` / `adb devices` were callable; `finalMessage` shape; wall-clock time. From the answers the orchestrator sets the pre-warm policy (plan §2.2 step 3) and the exact dispatch command per relay in PROGRESS.md. Worktrees are deleted; nothing lands.

**T0.4 — DECISION-8.**
Evidence: last commits touching upstream `flutter/`, their authors and dates; open and closed issues or PRs mentioning Flutter; any maintainer statement; whether the main README's community-Flutter pointer targets the in-tree directory or an external project. Output: facts with dated sources, interpretation (sample / abandoned / planned SDK), and the consequence for PRD §4 positioning. If the relay has no network, the orchestrator pre-fetches `git log`, `gh issue list`, and README snapshots into the evidence file and the implementer analyzes offline.

**T0.5 — DECISION-9.**
List all 19 assets of release 4.8.0 with names and sizes. Download and inspect each relevant one: Android libraries per ABI (or AAR contents), iOS xcframework (static or dynamic, device and simulator slices, arm64 and x86_64 simulator), headers, protos, `registry.json`, any macOS or host library usable for `test:native`, Rust-built components, and 16 KB page alignment of the 64-bit Android libraries. Output: an evidence table and a recommendation among (A) mirror upstream assets and re-checksum plus a small companion identity library built by us, (B) build from source in CI with the identity symbol linked in, (C) both, with the consequences for T1.2, T1.6 host tests, T1.7's identity check, and T1.8's need for a dynamic iOS slice. **[VERIFIED 2026-09-07]** the 4.8.0 headers expose no version symbol, so the identity must be ours either way. Large downloads go to `~/.cache/wcf-upstream/4.8.0/` pre-fetched by the orchestrator when needed.

**T0.6 — DECISION-5.**
Check pub.dev for the three planned names and at least three alternative name families. Output a table (name, taken or free, by whom if taken) and a recommendation. The human records the decision; T0.10 applies it.

**T0.7 — Compat manifest.**
`compat_manifest.json` with exactly the keys of PRD §15.3 (including `release_set`, `identity`, `retention`, `sbom`) and placeholder values (`tag` = `4.8.0`, `commit` = `TBD-T1.1`). `tools/manifest/` provides a Dart reader (`Manifest.load`, typed fields) and a validator (required keys, sha256 hex length 64, semver format for packages, boolean `reproducible_build_verified`), a test, and the melos script `manifest:validate`.

**T0.8 — Test-vector inventory.**
Schema documented in `test_vectors/README.md`: `id`, `coin`, `operation` ∈ {address, sign, sign_message, plan, compile, invalid_input}, `variant` (free text from a documented list per family: EVM `legacy`, `eip1559`, `contract_call`; Bitcoin `p2pkh`, `p2wpkh`, `taproot`, `multi_input`; Solana `legacy`, `versioned`; messages `personal`, `eip712`; `n/a` for address and invalid-input entries), `source` {`kind` ∈ {upstream_test, standard, published_tx}, `path`, `commit` or `reference`, optional `url`}, `input` map, `expected` map, `platforms_verified` list. Storage: one YAML file per coin under `test_vectors/<coin>/`, merged by the loader (or a single `inventory.yaml`; the implementer picks and reports). `tools/vectors/` provides loader, validator (unique ids, provenance present, known operations and variants), a test, and the script `vectors:validate`.

**T0.9 — Upstream audits evidence.**
Which published security audit reports exist for wallet-core, who performed them, the versions and components covered, dates, URLs. Facts only; no conclusions for the README.

**T0.10 — Rename.**
Apply the DECISION-5 names everywhere (directories, pubspecs, imports, README, AGENTS.md). Gates green. Only dispatched if the human changes a name.

**T0.11 — Architecture decision records.**
Four records, each with context, options, evidence, recommendation, and consequences for tasks:
- DECISION-11, public model: a stable `Coin` (or `Network`) value type over the registry id with a stability policy, explicit mainnet/testnet where upstream has only a derivation (Bitcoin), assets deferred to family helpers; the generated `CoinType` stays behind `advanced.dart`. Evidence from the 4.8.0 registry: 167 entries, 60 EVM networks as separate coins with chain ids, Bitcoin testnet as a derivation named `testnet`.
- DECISION-12, lifecycle: the PRD §14.3 state machine and message protocol in full (states, request ids, bounded queue, timeouts, cancellation, close during in-flight, termination), the two lifecycles (synchronous internal `dispose()`, asynchronous public `close()`), and the Dart `Finalizer` fallback on proxies. Same-isolate `HDWallet` under `advanced.dart`.
- DECISION-13, signing: `Signer.sign(request, Set<KeyLocator>)`, `KeyLocator` shapes (HD path in a wallet ref, imported key ref, external-signer key), how UTXO inputs carry locators, the v1 policy for multisig, partial signing, and watch-only (typed errors), the sealed `SignResult` family, and the family boundary of PRD §11.4 (`encodeKeylessInput`, `parseSigningOutput`, per-family key-field lists). Evidence: Bitcoin `repeated bytes private_key`; Solana's three key fields; differing output shapes.
- DECISION-14, distribution: the build-identity symbol and how the T0.5 recommendation provides it, content-addressed immutable URLs, retention promise and mirror candidates with cost, exact cross-package pins and the release-set id, publication order, hosted-install smoke, recovery-release procedure, SBOM [REC].
`docs/architecture/*.md` hold the resulting interface sketches (Dart signatures, no implementation) that T1.11, T1.12, T2.0, and T2.1 must follow. Acceptance: every record cites the PRD sections it changes; the sketches contain no `dart:ffi`, generated, or protobuf types in public signatures.

**T0.12 — Threat model v0.**
Cover every item of PRD §16 S6: key residence time and lock/unlock, app backgrounding and auto-lock guidance, BIP-39 passphrases and keystore passwords, clipboard/keyboard/logs/analytics/crash dumps/screenshots, dynamic-library path hijacking and artifact substitution, malformed lengths/protobufs/native return values/null pointers, dependency and upstream vulnerability monitoring, emergency-update policy, debug-only tooling and secrets in diagnostics. For each: threat, affected component (wrappers, worker, loader, signer, adapter, docs), mitigation owner (task id or "app developer, documented"), and what remains out of scope. It is an input to T0.11 and is revised by T5.7.

## Wave schedule

| Wave | Tasks in parallel | Notes |
|---|---|---|
| W0 | T0.1 | solo; everything else depends on it |
| W1 | T0.2, T0.7, T0.8 (+ T0.3 run by the orchestrator) | 3 implementer slots |
| W2 | T0.5, T0.12, T0.4 → T0.9, T0.6 as slots free | network-dependent; pre-fetch evidence if T0.3 says so |
| W3 | T0.11 (+ T0.10 if DECISION-5 changes a name) | T0.11 needs T0.5, T0.8, T0.12 landed |
| D0 | Phase-0 debate | adjudicates DECISION-11…14, then triage, rework, human records, tag |

## D0 — Debate brief outline

- **Agreed points:** layout matches plan §3; the four gates run locally and in CI; `AGENTS.md` carries the twelve rules; manifest and vector schemas match PRD §15.3 and §13.2 including `variant`; the threat model covers every S6 item.
- **Contested points:** DECISION-9 recommendation (mirror plus companion identity library vs build from source vs both); DECISION-8 interpretation and its effect on §4 positioning; DECISION-5 naming recommendation; and the four architecture records: DECISION-11 thin facade vs full domain model vs public generated enum; DECISION-12 the §14.3 protocol as drafted; DECISION-13 key-locator shapes and the multisig/partial/watch-only policy; DECISION-14 retention and mirror cost vs promise, exact pins vs ranges.
- **Questions for Codex:** Can a hand-edit of a future generated directory slip past the gates as defined? Does the vector schema support checks (a)–(c) of §13.2 mechanically, per variant? Do the interface sketches in `docs/architecture/` let a Bitcoin spend from two derivation paths be expressed without key material in the request? Can a public proxy ever free a worker-owned pointer synchronously under the DECISION-12 draft? Is anything in `AGENTS.md` in tension with PRD v1.2? Are the audit-evidence facts stated without over-claiming?
