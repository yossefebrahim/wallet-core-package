# Phase 4 — M3: Release watching and reproducibility

Back to [EXECUTION_PLAN.md](../EXECUTION_PLAN.md) · Status in [PROGRESS.md](../PROGRESS.md)

## Goal (PRD §18, M3)

Upstream watcher; API and behavioral diff reports; one upstream release absorbed end to end; independent rebuild comparison.

## Exit criteria (verbatim from PRD §18)

New upstream tag absorbed with zero hand-edits; both diff reports attached to the PR; reproducibility result recorded (`reproducible_build_verified` true, or documented diffs).

## Tasks

| ID | Task | Impl | Size | Depends on | Owns (only these paths) | Flags |
|---|---|---|---|---|---|---|
| T4.1 | API diff tool: symbols, protobuf fields, registry entries between two pins | claude | M | Phase 3 closed | `tools/diff/api_diff.dart`, `tools/diff/test/`, melos `diff:api` | |
| T4.2 | Behavioral diff: re-run the whole vector inventory on new artifacts, flag changed outputs | claude | M | T2.8 | `tools/diff/behavioral_diff.dart`, melos `diff:behavior` | |
| T4.3 | Upstream watcher: scheduled workflow opens the pin PR, triggers build → generate → diff → test; opens an issue on failure; candidate (pre-release) then stable publication with an expedited security path [REC]; the upgrade report names the exposed-unverified operations upstream touched | claude | M | T4.1, T4.2, T1.2 | `.github/workflows/upstream-watch.yml`, `.github/workflows/pin-pr.yml`, `tools/upstream/watch.dart`, `docs/releases/channels.md` | needs repo write permissions in CI; human configures |
| T4.4 | Reproducibility: independent rebuild job with pinned toolchain, checksum comparison, `docs/reproducibility.md` | claude | L | T1.2 | `.github/workflows/reproducibility.yml`, `tools/native_build/compare.dart`, `docs/reproducibility.md`, manifest `reproducible_build_verified` | CI-run; long |
| T4.5 | Provenance attestations on native artifacts (SLSA / GitHub attestations) | agy | S | T1.2 | `.github/workflows/build-native.yml` (attestation step only) | [REC] |
| T4.6 | Absorb the next upstream tag end to end | orchestrator + claude rework tasks | L | T4.1–T4.4 | manifest, generated dirs, vectors (fixes as rework tasks `T4.R<n>`) | one real pin PR |
| D4 | Phase-4 debate | codex | — | all | none | read-only |

## Task notes

**T4.1 — API diff.** Given two manifests (or two `third_party` checkouts), report added/removed/changed functions and enums from the inventories, added/removed/renumbered protobuf fields, and registry entries added/removed/changed. Markdown output suitable for a PR comment.

**T4.2 — Behavioral diff.** Runs every vector against the new artifacts and reports any changed output for an existing vector, even when the API is unchanged. Reads `test_vectors/results/` from the CI run for the candidate pin and compares with the current pin's results.

**T4.3 — Watcher.** A scheduled job polls upstream tags; on a new tag it opens a PR that only changes `upstream.tag`/`commit` in the manifest. The pin PR workflow runs build (T1.2), `upstream:fetch`, `gen:all`, `gen:check`, `diff:api`, `diff:behavior`, the full test matrix, and `gen:matrix`, and comments both diff reports on the PR. Nothing publishes automatically. Failure opens an issue with the diffs and leaves the previous pin published and its artifacts available. The absorbed tag publishes first as a pre-release candidate; stable follows a soak period the human sets per risk; upstream security fixes take the expedited path. The report lists which exposed-unverified operations upstream changed, since the behavioral diff covers only vectors.

**T4.4 — Reproducibility.** A second, independent build of the pinned commit with the manifest's toolchain; byte comparison per artifact; where bytes differ, a documented diff (what differs and why, for example embedded timestamps). Sets `reproducible_build_verified` only on byte-identical results. README language changes from "checksum-pinned" to "reproducible" only when true.

**T4.6 — Absorb one release.** The orchestrator lets the watcher (or a manual trigger) open the pin PR for the first upstream tag after 4.8.0, reviews both diff reports, dispatches rework tasks for anything the new tag breaks (generated code must not be hand-edited; fixes go to generators, wrappers, or vectors), and records the outcome. The human approves the PR merge.

## Wave schedule

| Wave | Tasks in parallel | Notes |
|---|---|---|
| W1 | T4.1, T4.2, T4.5 | |
| W2 | T4.3, T4.4 | both CI-heavy; human sets up permissions |
| W3 | T4.6 | orchestrator-driven with rework tasks |
| D4 | debate | then triage, rework, tag `phase-4-closed` |

## D4 — Debate brief outline

- **Agreed points:** the pin PR for the absorbed tag shows zero hand-edits (clean regeneration diff), both diff reports attached, tests green, the reproducibility result recorded.
- **Contested points:** whether the documented build diffs (if any) are acceptable or must be eliminated before README says "reproducible"; whether the behavioral diff's sensitivity is right (false positives vs missed changes).
- **Questions:** Does the upgrade report name the unverified surface upstream touched? Could an upstream serialization change slip through both diffs? Does the watcher ever publish or push without a human? Are provenance attestations verifiable by a consumer? Does the breakage path keep the previous pin published?

## D0 follow-ups binding on Phase 4 (added 2026-09-07)

- **T4.3** polls the repository security-advisories feed (`/repos/trustwallet/wallet-core/security-advisories`) in addition to tags and opens an expedited pin PR on a new published advisory (D0 F8, TM-27 owner); it also watches the layout of `TrustWalletCore-<tag>.tar.xz` (DECISION-9 trigger 2) and DECISION-8's revisit triggers 1–4 and 6.
