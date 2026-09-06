# PROGRESS — wallet_core_flutter delegated execution

The only status source. Updated by the orchestrator when any task changes state, never in a batch. Plan: [EXECUTION_PLAN.md](EXECUTION_PLAN.md) (1.2). Commit boundary: the orchestrator never commits, merges, tags, or pushes; every such operation is an `agy-delegate` commit brief (plan §2.9).

Status values: `queued` · `dispatched` (worktree, artifact dir, session id recorded) · `in review` · `rework` · `landing` (commit brief at agy; the row carries `landed pending-<id>` until agy writes the hash) · `landed <hash>` · `eval-branch <branch>` · `blocked <reason>` · `skipped <reason>`.

## Environment findings (filled by T0.3)

| Relay | Status | Network in sandbox | `~/.pub-cache` writable | `git status` in worktree | Simulator / emulator callable | Wall-clock | Working dispatch command |
|---|---|---|---|---|---|---|---|
| claude-delegate | | | | | | | |
| agy-delegate | | | | | | | |
| codex-delegate | | | | | | | |

Pre-warm policy decided: _(pending T0.3)_. Pre-warmed on 2026-09-07 by the orchestrator: `melos 8.6.0` activated globally (`~/.pub-cache/bin`), and `lints`, `test`, `ffi`, `yaml`, `path` fetched into `~/.pub-cache`.

Relay dials verified so far: agy default model `gemini-3.1-pro` accepts `--effort low|high` only (`medium` fails at launch with no run).

agy headless (`--print`) mode auto-denies the `command` (shell) permission with no allow-rule configured (`scratchpad/relay/INIT-2/result.json`). Human decision 2026-09-07 in chat: agy commit briefs run with `--dangerously-skip-permissions`; implementer briefs never do (plan §2.9).

## Concurrency

Implementer cap: 3 · Device lock holder: _none_ · Open worktrees: _none_

## Task status

| ID | Task | Impl | Status | Worktree / branch | Session id | Artifact dir | Notes |
|---|---|---|---|---|---|---|---|
| INIT | Repository init + first commit (docs only) | agy (commit brief) | dispatched (attempt 3) | root checkout, `main` | | scratchpad/relay/INIT-3 | plan §2.9; brief `briefs/INIT_repo.md`. Attempt 1: `--effort medium` invalid for agy default model `gemini-3.1-pro` (low/high only), nothing ran. Attempt 2 (`--effort high`): agy headless mode auto-denied the `command` permission; nothing touched. Human chose `--dangerously-skip-permissions` for commit briefs; attempt 3 uses `--effort high --timeout 20m --dangerously-skip-permissions` |
| T0.1 | Monorepo skeleton, gates, AGENTS.md | claude | queued | | | | |
| T0.2 | CI skeleton | claude | queued | | | | |
| T0.3 | Delegate smoke test ×3 | orchestrator | queued | | | | |
| T0.4 | DECISION-8 research | claude | queued | | | | |
| T0.5 | DECISION-9 release assets | claude | queued | | | | |
| T0.6 | DECISION-5 pub.dev names | agy | queued | | | | |
| T0.7 | Compat manifest + validator | agy | queued | | | | |
| T0.8 | Vector inventory schema + validator | agy | queued | | | | |
| T0.9 | Upstream audits evidence | agy | queued | | | | |
| T0.10 | Apply DECISION-5 rename | agy | queued | | | | conditional |
| T0.11 | ADR batch: DECISION-11…14 drafts | claude | queued | | | | adjudicated at D0 |
| T0.12 | Threat model v0 | claude | queued | | | | |
| D0 | Phase-0 debate | codex | queued | | | | |
| T1.1 | Upstream pin + fetch | claude | queued | | | | |
| T1.2 | Native artifacts workflow | claude | queued | | | | |
| T1.3 | ffigen + inventory | claude | queued | | | | |
| T1.4 | Protobuf generation | claude | queued | | | | |
| T1.5 | Registry transform | agy | queued | | | | |
| T1.6 | Memory wrappers + disposal + leak tracker | claude | queued | | | | |
| T1.7 | Native loader + manifest verification | claude | queued | | | | |
| T1.8 | Packaging eval Option 1 | claude | queued | | | | eval branch |
| T1.9 | Packaging eval Option 2 | claude | queued | | | | eval branch |
| T1.10 | Ethereum vectors | agy | queued | | | | |
| T1.11 | SDK core | claude | queued | | | | |
| T1.12 | EVM request + Approach A | claude | queued | | | | |
| T1.13 | Approach B adapter | claude | queued | | | | eval branch |
| T1.14 | SignJSON probe | agy | queued | | | | |
| T1.15 | Public-API lint | agy | queued | | | | |
| T1.16 | Example app + consumer check | claude | queued | | | | device |
| T1.17 | CI device jobs + no-network test | claude | queued | | | | |
| T1.18 | Memory contract docs | agy | queued | | | | |
| T1.19 | Packaging measurement harness | claude | queued | | | | before T1.8 / T1.9 |
| D1a | Checkpoint debate DECISION-2/6 | codex | queued | | | | |
| D1 | Phase-1 debate | codex | queued | | | | |
| T2.0 | Signer interface + family architecture | claude | queued | | | | |
| T2.1 | Signing worker | claude | queued | | | | |
| T2.2 | Bitcoin vectors | agy | queued | | | | |
| T2.3 | Solana vectors | agy | queued | | | | |
| T2.4 | Ethereum message vectors | agy | queued | | | | |
| T2.5 | UTXO family | claude | queued | | | | |
| T2.6 | Solana | claude | queued | | | | |
| T2.7 | Ethereum message signing | claude | queued | | | | |
| T2.8 | Capability matrix generator | claude | queued | | | | |
| T2.9 | Compiler / message probes | agy | queued | | | | |
| T2.10 | Worker device tests + measurements | claude | queued | | | | device |
| T2.11 | README counts | agy | queued | | | | |
| T2.12 | Hostile-input and worker-fault suite | claude | queued | | | | |
| D2 | Phase-2 debate | codex | queued | | | | |
| T3.1 | API review audit | claude ro + agy | queued | | | | |
| T3.2 | Apply API freeze | claude | queued | | | | |
| T3.3 | advanced.dart + docs | agy | queued | | | | |
| T3.4 | StoredKey | claude | queued | | | | |
| T3.5 | PrivateKey / PublicKey | claude | queued | | | | |
| T3.6 | EVM helpers | claude | queued | | | | |
| T3.7 | UTXO helpers | claude | queued | | | | |
| T3.8 | Solana helpers | claude | queued | | | | |
| T3.9 | Cookbook part 1 | agy | queued | | | | |
| T3.10 | Cookbook part 2 | agy | queued | | | | |
| T3.11 | pub.dev readiness | claude | queued | | | | |
| T3.12 | Publish 0.x as a release set | human | queued | | | | |
| T3.13 | SECURITY.md, v1 feature table, retention policy | claude | queued | | | | |
| D3 | Phase-3 debate | codex | queued | | | | |
| T4.1 | API diff tool | claude | queued | | | | |
| T4.2 | Behavioral diff | claude | queued | | | | |
| T4.3 | Upstream watcher | claude | queued | | | | |
| T4.4 | Reproducibility job | claude | queued | | | | |
| T4.5 | Provenance attestations | agy | queued | | | | |
| T4.6 | Absorb next upstream tag | orchestrator | queued | | | | |
| D4 | Phase-4 debate | codex | queued | | | | |
| T5.1 | EVM chain matrix | agy | queued | | | | |
| T5.2a/b | LTC/DOGE/BCH | agy / claude | queued | | | | |
| T5.3a/b | TRON | agy / claude | queued | | | | |
| T5.4a/b | Cosmos | agy / claude | queued | | | | |
| T5.5a/b | TON | agy / claude | queued | | | | |
| T5.6a/b | XRP | agy / claude | queued | | | | |
| T5.7 | Threat model v1 revision + SECURITY.md update | claude | queued | | | | |
| T5.8 | External review scope pack | claude | queued | | | | |
| T5.9 | Migration guides | agy | queued | | | | |
| T5.10 | Review findings remediation | claude | queued | | | | |
| T5.11 | 1.0 release checklist | orchestrator + human | queued | | | | |
| D5 | Phase-5 debate | codex | queued | | | | |

## Per-task review notes

_(one entry per landed task: what landed, what was inspected, gate outcomes with counts, device results)_

## Decided facts (copy into later briefs)

_(names, paths, interfaces, conventions established by landed tasks; one line each, prefixed with the task id)_

- Commit boundary (user rule, 2026-09-07): the orchestrator never runs `git init/add/commit/merge/rebase/tag/push`; `agy-delegate` executes them on commit briefs (`briefs/INIT_repo.md`, `briefs/LAND_<id>.md`, `briefs/TAG_phase-<n>.md`). Implementers still never commit.
- T0.1: _pending_

## Needs your eyes

_(design decisions implementers made, defensible-but-unasked turns, non-blocking nits, questions for the human)_

## Debate triage

| Debate | Finding | Bucket (blocking / accepted risk / rejected) | Rework task or decision doc | Codex conceded? |
|---|---|---|---|---|

## Decisions log

| ID | Due | Status | Doc |
|---|---|---|---|
| DECISION-1 | D1 | open | docs/decisions/DECISION-1.md |
| DECISION-2 | D1a | open | docs/decisions/DECISION-2.md |
| DECISION-3 | D2 | open | docs/decisions/DECISION-3.md |
| DECISION-4 | before Phase 5 W4 (human) | open | docs/decisions/DECISION-4.md |
| DECISION-5 | Phase 0 (human) | open | docs/decisions/DECISION-5.md |
| DECISION-6 | D1a | open | docs/decisions/DECISION-6.md |
| DECISION-7 | after Phase 2 (human) | open | docs/decisions/DECISION-7.md |
| DECISION-8 | Phase 0 | open | docs/decisions/DECISION-8.md |
| DECISION-9 | Phase 0 | open | docs/decisions/DECISION-9.md |
| DECISION-10 | Phase 3 (human; v1 feature table) | open | docs/decisions/DECISION-10.md |
| DECISION-11 | D0 (public coin/network facade) | open | docs/decisions/DECISION-11.md |
| DECISION-12 | D0 protocol, D2 worker model | open | docs/decisions/DECISION-12.md |
| DECISION-13 | D0 interface, D2 proof | open | docs/decisions/DECISION-13.md |
| DECISION-14 | D1a (with DECISION-9 evidence) | open | docs/decisions/DECISION-14.md |
