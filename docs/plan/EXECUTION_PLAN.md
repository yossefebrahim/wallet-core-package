# `wallet_core_flutter` — Delegated Execution Plan

| | |
|---|---|
| **Source** | [docs/wallet_core_flutter_prd.md](../wallet_core_flutter_prd.md) — PRD Draft v1.2, 2026-09-07 |
| **Plan version** | 1.3 — 2026-09-07 (1.1 absorbed the architecture audit, plan §7 and [audit_triage.md](../audit-resaults/audit_triage.md); 1.2 moved the commit boundary to `agy-delegate`; **1.3 removes it entirely — the repository owner is the only party that commits, tags, or pushes**, plan §2.9) |
| **Orchestrator** | A Claude Code session opened in this repository. It writes briefs, dispatches, monitors, reviews, re-runs gates, and keeps [PROGRESS.md](PROGRESS.md) current. It does not implement, and it never runs a git command that creates or moves a commit, tag, or branch head (`init`, `add`, `commit`, `merge`, `rebase`, `tag`, `push`). Since 2026-09-07 those are **not delegated either**: the repository owner performs every commit, tag, and push themselves (plan §2.9). |
| **Implementers** | `claude-delegate` (default, almost everything) · `agy-delegate` (small, bounded coding tasks). Neither commits: since 2026-09-07 the owner performs every commit, tag, and push (plan §2.9). |
| **Phase auditor** | `codex-delegate` in `--read-only` mode: an adversarial debate at the end of every phase, plus one checkpoint debate inside Phase 1 |
| **Human** | Approves phase closes, records decisions the PRD assigns to the owner, and performs every publication |

Section references such as §11.2 point at the PRD unless prefixed with "plan".

---

## 0. How to read and use this plan

- **Phases** map one-to-one onto PRD milestones: Phase 0 (foundation, pre-M0), Phase 1 = M0, Phase 2 = M1, Phase 3 = M2, Phase 4 = M3, Phase 5 = M4, Phase 6 = M5 backlog.
- **Tasks** are the unit of delegation: one task → one brief → one implementer session → one reviewed commit. Task IDs are `T<phase>.<n>`; debates are `D<phase>` (and `D1a` for the Phase 1 checkpoint).
- **Waves** group tasks that can run in parallel because none depends on another and their owned paths are disjoint. A wave starts only when every task it depends on has landed on `main`.
- **Owned paths** are the only paths a task may create or modify. Two tasks in the same wave never own the same path. This is what makes parallel implementers safe.
- **Implementer choice** follows one rule: `agy-delegate` for S-sized tasks that need no design decision (a script, a data file, a probe, a short doc, a lint check); `claude-delegate` for everything else, and always for anything touching secrets, FFI ownership, isolates, native builds, or CI. Anything marked **design** in a table goes to `claude-delegate` regardless of size.
- **Device-gated** tasks need an Android emulator, an iOS simulator, or physical devices. At most one device-gated task is at the implementer at a time, and the orchestrator runs the device gate itself during review (see plan §2.2).
- Everything the PRD marks **[REQ]** is traced to a task in plan Appendix C. Everything marked **[DECISION-n]** is adjudicated in a named debate and then written to `docs/decisions/DECISION-n.md`.

---

## 1. Verified environment (checked 2026-09-06 on this machine)

| Item | State | Consequence for the plan |
|---|---|---|
| Repository | `docs/wallet_core_flutter_prd.md` only; **no `.git` directory** | The orchestrator runs `git init` and commits the PRD and this plan before Phase 0 W0. Worktrees, and therefore parallel lanes, need this first. |
| `claude` CLI | 2.1.263, logged in (claude.ai) | `claude-delegate` relay usable |
| `agy` CLI | 1.1.27, authenticated; models listed include `gemini-3.8-flash-{high,medium,low}`, `gemini-3.7-flash-*`, `gemini-3.6-flash-*`, `gemini-3.1-pro-{high,low}`. **[VERIFIED 2026-09-07]** the configured default model is `gemini-3.1-pro`, which rejects `--effort medium`; pass `low` or `high` | `agy-delegate` relay usable |
| `codex` CLI | codex-cli 0.147.0, logged in (ChatGPT) | `codex-delegate` relay usable; supports `exec --json`, `--read-only`, `--session` |
| Relay scripts | `~/.agents/skills/{claude,agy,codex}-delegate/scripts/relay.mjs` (symlinked under `~/.claude/skills/`) | Dispatch commands in plan Appendix B use these paths |
| Node | v22.23.1 | relays need Node 18+ |
| Flutter / Dart | Flutter 3.44.1 stable, Dart 3.12.1 | Build hooks (`package_ffi` template, Flutter ≥ 3.38) are available locally, so PRD §12 Option 1 can be evaluated on this machine |
| `protoc` | `/opt/homebrew/bin/protoc` present | `protoc-gen-dart` (Dart `protoc_plugin`) is **not** installed; T1.4 installs and pins it |
| `melos` | not installed | T0.1 adds it as a dev dependency / pub global activation and records the version |
| Upstream | trustwallet/wallet-core, tag 4.8.0 (19 release assets, contents not inspected) | T0.5 inspects the assets before any native work |

Unknowns the plan resolves early (T0.3): whether each relay's sandbox allows `dart pub get` network access, writes to `~/.pub-cache`, git index writes inside a worktree, and simulator/emulator control.

---

## 2. Operating rules

### 2.1 Parallelism model: one worktree per task, waves per phase

```
main ──┬── task/T1.3 (worktree ../wallet-core-package.worktrees/T1.3)  claude-delegate
       ├── task/T1.4 (worktree ../wallet-core-package.worktrees/T1.4)  claude-delegate
       └── task/T1.5 (worktree ../wallet-core-package.worktrees/T1.5)  agy-delegate
```

- Worktrees live in a sibling directory `../wallet-core-package.worktrees/<task-id>` on branch `task/<task-id>` cut from `main`.
- Implementers never share a working tree. The delegate skills state that multiple implementers in one tree destroy attribution and the review boundary.
- **Concurrency cap: 3 implementer sessions at once** (raise only after T0.3 shows the machine and the CLIs' quotas tolerate it). Within a wave, tasks beyond the cap queue in table order.
- **Device lock:** one device-gated task at a time, because the emulator and simulator are single shared resources.
- Landing used to mean a fast-forward onto `main` executed by `agy-delegate` on a commit brief. **Since 2026-09-07 no session commits (plan §2.9):** a task that passes review is left in its worktree, its row in PROGRESS.md reads `ready for you`, and the worktree and branch stay until the owner has taken the work.
- A later wave's brief may rely on an earlier task's behavior only after that task has landed on `main` (fresh implementer sessions have no memory).
- **Evaluation branches:** Phase 1's two packaging evaluations (T1.8, T1.9) and the Approach B prototype (T1.13) touch `pubspec.yaml` and native build files in incompatible ways. They land on branches `eval/option1`, `eval/option2`, `eval/approach-b` and are tagged. Only the option that wins its decision is rebased onto `main`.

### 2.2 The per-task loop (what the orchestrator does for every task)

1. **Precondition.** All `Depends on` tasks are landed on `main` and the full gates are green there.
2. **Worktree.** `git worktree add ../wallet-core-package.worktrees/<id> -b task/<id> main`.
3. **Pre-warm.** Run `melos bootstrap` (or `dart pub get`) in the worktree so `.dart_tool/` and the pub cache exist. If T0.3 showed the relay sandbox blocks network, also pre-fetch any evidence or artifacts the task needs into the paths the brief names. Implementers then run gates with `--offline`.
4. **Brief.** Copy `briefs/_TEMPLATE_implement.md` to `briefs/<id>.md`; fill it from the task row and notes in this plan; append the *decided facts* from PROGRESS.md that the task depends on (names, paths, interfaces chosen by earlier tasks). One task per brief. Audit the premises: branch, owned paths, gates, constraints.
5. **Dispatch** in the background (plan Appendix B), with a timeout, and record the artifact directory and session id in PROGRESS.md as `dispatched`.
6. **Review** when `result.json` exists with a terminal status:
   - read `finalMessage`, `touchedFiles`, and the raw diff (`git status --short`, `git diff`, untracked files opened directly);
   - **tests first**: any edit to an existing test, any new skip, any weakened assertion is a finding until justified;
   - **re-run every gate yourself** in the worktree; never accept "gates passed";
   - hold the diff against the brief: scope creep, scope shortfall, quiet judgment calls, repo constraints;
   - implementer sweep: hardcoded success paths, broad catches, APIs that do not exist in installed versions, unused code, duplicate idioms, tests that mock our own behavior;
   - for device-gated tasks, run the device gate on the emulator/simulator (and devices when the task says so) and record the result;
   - run `clean-code-guard` on the diff when the task is code.
7. **Rework** with a delta brief in the same session: `--session <id>` for claude and codex, `--resume-last` for agy. Review the rework exactly like a first run.
8. **Land (through `agy-delegate`).** The orchestrator sets the task to `landing` in PROGRESS.md with the marker `landed pending-<id>`, writes `briefs/LAND_<id>.md` from `briefs/_TEMPLATE_commit.md`, and dispatches it to `agy-delegate`. agy commits on the task branch with a message naming the task ID and the implementer lane, fast-forwards `main` (rebasing the task branch first if `main` moved; a conflict aborts the rebase and is reported), replaces the marker in PROGRESS.md with the real hash, and commits the plan bookkeeping (`docs/plan/`). The orchestrator then re-runs the full gates on `main`, checks `git log` and `git status`, removes the worktree, and deletes the branch. Trivial integration fixes (a merge conflict in a hot file, an import path, a melos script entry, a formatting diff) may be made inline by the orchestrator in the worktree before the commit brief and noted in PROGRESS.md; anything larger goes back as a delta brief.
9. **Carry forward.** Add any name, path, interface, or convention the task established to PROGRESS.md → *Decided facts*. Later briefs copy from there.
10. **Surface, don't absorb.** Design decisions the implementer made, unasked-for turns, and non-blocking nits go into PROGRESS.md → *Needs your eyes*.

### 2.3 Phase close: the Codex debate

A phase is closed only by this procedure.

1. All phase tasks landed; full gates green on `main`; device gates green; PROGRESS.md up to date.
2. The orchestrator writes `briefs/D<phase>.md` from `briefs/_TEMPLATE_debate.md`:
   - **Agreed points**: each exit criterion of the phase (verbatim from PRD §18) with evidence pointers (file paths, test names, CI run URLs, decision docs);
   - **Contested points**: every `DECISION-n` due in this phase, with both positions and the measured data;
   - **Questions**: targeted checks against PRD sections (for example "does `Disposable` satisfy §11.2 items 1–7, item by item?");
   - grounding rules and the output contract.
3. Dispatch `codex-delegate` with `--read-only --effort high --timeout 1h`. On return, verify `touchedFiles` is `[]` and `readOnlyViolation` is `false`; otherwise inspect the diff before reading the report.
4. **Triage** every finding into exactly one bucket, recorded in PROGRESS.md:
   - **blocking** → a rework task (`T<phase>.R<n>`) dispatched to `claude-delegate` or `agy-delegate` by the same size rule, reviewed and landed as usual;
   - **accepted risk** → written into `docs/decisions/` with the reason;
   - **rejected** → the reason is recorded (Codex's claim was wrong, or it contradicts a PRD requirement).
5. When rework has landed, resume the same Codex thread with `--session <threadId>` and a delta brief listing the fixes; ask it to concede or hold each blocking point. Repeat until nothing blocking remains.
6. Record each `DECISION-n` outcome in `docs/decisions/DECISION-n.md`: options, data, debate verdict, final choice, who decided (the PRD's "Decided by" column names the human for DECISION-4, DECISION-5, DECISION-7).
7. The human approves the close and tags `phase-<n>-closed` themselves; no session tags (plan §2.9).

Codex never implements in this plan. Its only deliverable is its final message.

### 2.4 Repository constraints copied into every brief

`AGENTS.md` (created by T0.1) is the single source; `CLAUDE.md` contains only `@AGENTS.md` so Claude Code loads it, and Codex reads `AGENTS.md` natively. `agy` reads neither reliably. Every brief restates the rules below regardless, because that is the only guarantee.

1. Generated directories (`**/lib/src/generated/**`, `docs/capability_matrix.*`) are never hand-edited. Regenerate with the `melos run gen:*` scripts. CI fails on a clean-regeneration diff once `gen:check` exists (T1.3); until then this rule is enforced by review.
2. No cryptography, key derivation, or signed-transaction serialization is implemented in this repository. Every such operation calls upstream through the generated bindings. Encoding upstream's *signing-input* protobuf in Dart is allowed; producing the signed transaction bytes is not. Standard integrity hashing — SHA-256 of artifacts, manifests, and generated inputs, as PRD §12.3 requires — is allowed; it is verification, not wallet cryptography.
3. No network access at runtime in SDK, bindings, or native-loader code. Artifact download happens only in the native package's build-time tooling.
4. `package:wallet_core_flutter/wallet_core_flutter.dart` exports no `dart:ffi` type, no generated `TW*` class, and no protobuf class in any public signature. Within the SDK package, `advanced.dart` is the only file that may export them; a consumer who accepts the ownership responsibilities of PRD §11 may also import the bindings package directly.
5. Every native-backed object implements the disposal contract of PRD §11.2: explicit `dispose()`, finalizer detach, double-dispose no-op, `DisposedError` after disposal, `finally`-released temporaries.
6. Requests (`*TransactionRequest`, message requests) never contain key material. Family code encodes key-less inputs and parses results; only the signer injects keys (PRD §11.4 family boundary). Raw protobuf signing exists only under `advanced.dart`.
7. Every test vector entry cites its provenance: upstream file path and commit, a standard (BIP/SLIP) reference, or a published transaction hash.
8. Docs and README never use the words "zeroization", "secret-free", or "audited" about this SDK; never use "reproducible" about its artifacts until PRD §12.4's independent-rebuild demonstration is recorded (M3, T4.4); and never make a legal claim about AGPL. Package names never contain "trust". The disclaimer "Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet." appears wherever the project is described.
9. Do not add a dependency without listing it, with version, in the final report.
10. Do not run `git add`, `git commit`, or `git push`. Do not start another agent session. Leave all work uncommitted for the orchestrator.
11. Touch only the owned paths named in the brief. No unrelated cleanup, renames, or formatting sweeps.
12. The default public SDK surface never exposes the generated `CoinType`; use the stable coin/network facade (PRD §8, DECISION-11). Public resources of the default surface close asynchronously; synchronous `dispose()` exists only on internal wrappers and on the same-isolate objects of `advanced.dart`, which follow the internal ownership contract (PRD §11.2, §14.3). Signers take a set of `KeyLocator`s and return sealed `SignResult`s (PRD §10.2, DECISION-13).

### 2.5 Canonical gates (defined by T0.1, named verbatim in every brief)

| Script | What it runs | Device |
|---|---|---|
| `melos bootstrap` | pub get for all packages (orchestrator pre-warms) | no |
| `melos run analyze` | `dart analyze --fatal-infos` in every package | no |
| `melos run format:check` | `dart format --set-exit-if-changed .` | no |
| `melos run test` | unit tests in every package (no native library required unless the test says so) | no |
| `melos run test:native` | unit tests that load the real native library on the host (macOS) | no |
| `melos run gen:all` | `gen:ffi`, `gen:proto`, `gen:registry`, `gen:matrix` | no |
| `melos run gen:check` | `gen:all` then `git diff --exit-code` on generated paths | no |
| `melos run lint:public-api` | public-surface type check (T1.15) | no |
| `melos run vectors:validate` | inventory schema + provenance check (T0.8) | no |
| `melos run manifest:validate` | compat manifest schema + checksum presence (T0.7) | no |
| `melos run test:android` | `integration_test` on the running Android emulator | yes |
| `melos run test:ios` | `integration_test` on the running iOS simulator | yes |
| `tools/consumer_check.sh` | fresh `flutter create` consumer + add dependency + debug and release builds on both platforms | yes |

Until a script exists (Phase 0), briefs name the underlying `dart`/`flutter` commands instead.

### 2.6 Dials, timeouts, budgets

| Lane | Skill | Typical flags | Notes |
|---|---|---|---|
| Implementer, L / security-relevant | `claude-delegate` | `--effort high --timeout 2h --max-turns 120` | add `--max-budget-usd` if the human sets a cap; T0.1 exhausted 80 turns partly on sandbox workarounds, hence 120 |
| Implementer, M | `claude-delegate` | `--effort high --timeout 90m --max-turns 120` | the repo's `.claude/settings.json` sandbox allowlist (pub caches, pub.dev) applies to every claude-delegate run |
| Implementer, S | `agy-delegate` | `--effort high --timeout 45m --dangerously-skip-permissions` | default `agy` model (`gemini-3.1-pro`, efforts `low`/`high` only); pass `--model gemini-3.1-pro-high` when the S task still contains logic; flash labels are fine for pure data/doc files. The flag is required for any headless agy run that executes commands (INIT attempt 2 proved that without it nothing runs); recorded in PROGRESS.md → Needs your eyes on 2026-09-07 |
| Commit brief | `agy-delegate` | `--effort high --timeout 20m --dangerously-skip-permissions` | git mechanics only (plan §2.9); the flag is the human's standing decision for commit briefs; `--add-dir <worktree>` when landing a task |
| Read-only audit / research | `claude-delegate --read-only` | `--timeout 45m` | output is the final message; deliverable doc is then written by an S task or the orchestrator |
| Phase debate | `codex-delegate --read-only` | `--effort high --timeout 1h` | verify `readOnlyViolation == false` |

Permission escalations (`--dangerously-skip-permissions`, `danger-full-access`) are never used on implementer or debate dispatches without the human saying so in chat for that specific dispatch. Standing exception recorded 2026-09-07: agy **commit briefs** run with `--dangerously-skip-permissions` (plan §2.9).

### 2.7 PROGRESS.md and decided facts

[PROGRESS.md](PROGRESS.md) is the only status source. It holds the task status table (queued / dispatched / in review / rework / landed + hash), per-task review notes, *Decided facts* (carried into later briefs), *Needs your eyes*, and the debate triage tables. It is updated when each task changes state, never in a batch.

### 2.8 Stop-and-ask rules (the orchestrator pauses and reports)

- A task cannot be completed correctly inside its brief and owned paths.
- A review calls the plan itself into question (wrong split, wrong dependency, PRD contradiction).
- A gate reveals a defect in an already-landed task.
- A dispatch would need a permission or sandbox change the human did not approve.
- A lane's CLI is unavailable or out of quota: pause that lane; substituting another implementer is the human's call.
- Anything outward-facing: pushing to a remote, creating a GitHub release, publishing to pub.dev, opening issues on upstream.

### 2.9 Commit boundary (user rule, 2026-09-07; tightened by the user 2026-09-07 later the same day)

**Current rule, and the one that governs: nobody but the repository owner commits.** The owner said in chat, "stop
commiting ot pushing the code base please" and "I will do that with my self". From that moment:

- **No session commits, tags, or pushes** — not the orchestrator, not `agy-delegate`, not any implementer. Commit
  briefs are no longer written or dispatched, and `briefs/_TEMPLATE_commit.md`, `briefs/LAND_*.md` and
  `briefs/TAG_*.md` are dormant, kept only as a record of what was done before the rule changed.
- **Work accumulates uncommitted.** A finished task is reviewed by the orchestrator, its gates re-run, and it is then
  left in its worktree with a review note in PROGRESS.md saying it is ready for the owner. The owner decides what to
  stage, in what order, and with what message.
- **Landing still means "reviewed and gate-green"**, not "committed". PROGRESS.md task rows read `ready for you (worktree
  <path>, branch <branch>)` instead of `landed <hash>` for everything after this rule took effect.
- **A remote now exists** (`origin`, created by the owner). That changes nothing here: pushing was already
  outward-facing and is now entirely theirs.

What was committed before the rule changed, for the record: 29 commits ending at `89b137c`, plus the tag
`phase-0-closed`, every one of them made by `agy-delegate` on a commit brief and reviewed afterwards. The owner pushed
them; no session ever ran `git push`.

---

**Superseded (kept because it explains the history above): the 2026-09-07 morning rule.** The user's first instruction
was that the orchestrating session never commits or pushes, and that `agy-delegate` executes commits instead.
Consequences as they stood then:

- **Orchestrator may run:** `git worktree add/remove`, `git branch -d`, `git status`, `git diff`, `git log`, `git show`, `git rev-parse`, and any read-only inspection. It edits files in the main checkout only under `docs/plan/` (PROGRESS.md, briefs) and, as plan §2.2 step 8 allows, trivial integration fixes inside a task worktree before that task's commit brief.
- **Orchestrator never runs:** `git init`, `git add`, `git commit`, `git merge`, `git rebase`, `git tag`, `git push`, `git remote add`, or anything that amends, resets, or rewrites history.
- **`agy-delegate` executes every commit-creating operation** on a *commit brief* written from `briefs/_TEMPLATE_commit.md`: the repository init (`briefs/INIT_repo.md`), every task landing (`briefs/LAND_<id>.md`), every eval-branch landing, every phase-close tag, and every plan-bookkeeping commit. A commit brief is git mechanics only: it names the exact commands, the expected pre-state, and the verification to paste; it edits no file except the single `landed pending-<id>` → `landed <hash>` substitution in PROGRESS.md.
- **Implementers still never commit** (rule 10). `claude-delegate` and `codex-delegate` never receive a commit brief.
- **Pushing** stays outward-facing (plan §2.8): a push brief is dispatched only when the human asks in chat for that specific push.
- **Permission flag (human decision, 2026-09-07):** agy's headless (`--print`) mode auto-denies the shell `command` permission with no allow-rule configured, so the first two init attempts ran nothing. The human chose, in chat, that every agy **commit brief** runs with `--dangerously-skip-permissions` (agy auto-approves all of its tools for that run; the run is treated as full access). The flag is used on commit briefs only, never on an implementer brief; the brief's `<action_safety>` block (no push, no remote, no reset/checkout/clean/amend, no file edits beyond the PROGRESS.md substitution) is the boundary, and the orchestrator verifies every run afterwards with `git log`, `git status`, and `git show --stat`, comparing against the brief. Any commit or file change the brief did not name is a finding reported to the human.
- **Attribution:** task commits state the task ID, the implementer lane, and the brief path in the body. Bookkeeping commits of orchestrator-authored docs carry the trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

---

## 3. Target repository layout (fixed before any parallel work)

Set up by T0.1 so that owned paths can be assigned without collisions.

```
wallet-core-package/                      (repo root; rename is DECISION-5's business, not the plan's)
├── AGENTS.md                             single source of repo rules (plan §2.4)
├── CLAUDE.md                             "@AGENTS.md"
├── README.md                             disclaimer, counts placeholder, pointers
├── LICENSE                               MIT
├── THIRD_PARTY_NOTICES.md                upstream Apache 2.0 NOTICE preserved
├── melos.yaml / pubspec.yaml             workspace + canonical gate scripts (plan §2.5)
├── analysis_options.yaml                 strict lints, shared
├── compat_manifest.json                  PRD §15.3 (T0.7)
├── packages/
│   ├── wallet_core_flutter/              public SDK
│   │   ├── lib/wallet_core_flutter.dart  typed surface only
│   │   ├── lib/advanced.dart             bindings + protobuf re-export
│   │   ├── lib/src/{core,wallet,address,errors,lifecycle,requests,signing,worker,families,keys,keystore}/
│   │   ├── test/  integration_test/
│   ├── wallet_core_flutter_bindings/
│   │   ├── ffigen.yaml
│   │   ├── lib/src/generated/{ffi,proto,registry}/   never hand-edited
│   │   ├── lib/src/memory/               TWData/TWString wrappers, Disposable, leak tracker
│   └── wallet_core_flutter_native/
│       ├── lib/                          locate/load/verify
│       ├── tool/                         artifact fetch + verify (build time)
│       ├── hook/                         Option 1 (build hooks)        — eval branch until DECISION-2
│       ├── android/  ios/                Option 2 (Gradle / podspec)   — eval branch until DECISION-2
│       └── src/shim/                     Approach B adapter            — eval branch until DECISION-1
├── tools/
│   ├── upstream/    pin + fetch sources at the manifest commit
│   ├── gen/         registry transform, proto generation script
│   ├── inventory/   header vs generated symbol inventory
│   ├── matrix/      capability matrix generator
│   ├── manifest/    manifest validator
│   ├── vectors/     inventory loader + validator
│   ├── probes/      SignJSON / compiler / message-signing availability probes
│   ├── lint/        public API type check
│   ├── diff/        API diff, behavioral diff (Phase 4)
│   ├── native_build/  scripts used by the CI native build
│   └── consumer_check.sh
├── test_vectors/
│   ├── inventory.yaml                    or one file per coin under test_vectors/<coin>/, merged by the loader
│   └── exclusions.yaml
├── example/                              consumer app (Phase 1)
├── eval/                                 throwaway consumer apps for packaging evaluations (eval branches only)
├── third_party/                          git-ignored upstream checkout at the pinned commit
├── docs/
│   ├── wallet_core_flutter_prd.md
│   ├── plan/                             this plan, PROGRESS.md, briefs/
│   ├── decisions/                        DECISION-n.md + evidence/
│   ├── security/                         memory_contract.md, threat model
│   ├── cookbook/                         Phase 3
│   └── capability_matrix.md              generated
└── .github/workflows/                    ci.yml, build-native.yml, upstream-watch.yml, reproducibility.yml
```

Package names are placeholders until DECISION-5 (T0.6). Directory names under `packages/` change with that decision in one S task, before Phase 1 starts.

---

## 4. Phase index

Each phase file holds the goal, the verbatim PRD exit criteria, the task table (implementer, size, dependencies, owned paths), task notes detailed enough to write a brief from, the wave schedule, and the outline of its Codex debate.

| Phase | PRD milestone | File | Tasks | Debates | Max parallel |
|---|---|---|---|---|---|
| 0 | pre-M0 foundation | [phases/phase-0-foundation.md](phases/phase-0-foundation.md) | T0.1–T0.12 (T0.11 = ADR batch DECISION-11…14, T0.12 = threat model v0) | D0 | 3 |
| 1 | M0 spike on Ethereum | [phases/phase-1-m0-spike.md](phases/phase-1-m0-spike.md) | T1.1–T1.19 (T1.19 = shared packaging measurement harness) | D1a (checkpoint), D1 | 3 |
| 2 | M1 Bitcoin, Solana, worker, matrix | [phases/phase-2-m1-bitcoin-solana-worker.md](phases/phase-2-m1-bitcoin-solana-worker.md) | T2.0–T2.12 (T2.12 = hostile-input and worker-fault suite) | D2 | 3 |
| 3 | M2 public alpha on pub.dev | [phases/phase-3-m2-public-alpha.md](phases/phase-3-m2-public-alpha.md) | T3.1–T3.13 (T3.13 = SECURITY.md, v1 feature table, retention policy) | D3 | 3 |
| 4 | M3 release watching, reproducibility | [phases/phase-4-m3-release-watching.md](phases/phase-4-m3-release-watching.md) | T4.1–T4.6 | D4 | 3 |
| 5 | M4 1.0 stable | [phases/phase-5-m4-stable-and-phase-6-backlog.md](phases/phase-5-m4-stable-and-phase-6-backlog.md) | T5.1–T5.11 (families as a/b pairs) | D5 | 3 |
| 6 | M5 expansion | same file, backlog section | written when Phase 5 closes | — | — |

Implementer split across the whole plan: `claude-delegate` carries every L and design task and most M tasks; `agy-delegate` carries every S task (vectors, probes, validators, small docs, README automation, the public-API lint); `codex-delegate` runs the seven debates and nothing else; the human owns publication, DECISION-4/5/7/10, and phase-close approval.

---

## 5. Sequencing across phases

- Phases are strictly sequential: a phase starts only after the previous one is tagged `phase-<n>-closed`. The one allowed overlap: a later phase's **vector tasks** (agy, owning only `test_vectors/<coin>/`) may be dispatched during the previous phase's debate window, because they touch nothing the debate audits.
- Inside a phase, waves are the schedule and the dependency columns are the truth. If a wave's task list conflicts with a dependency column, the dependency column wins.
- Rework tasks from a debate (`T<phase>.R<n>`) always run before the phase closes, at the same concurrency cap.

| Phase | Waves | Critical path | Orchestration cycles (one cycle = dispatch → review → land) |
|---|---|---|---|
| 0 | 5 | T0.1 → T0.3 → T0.5 → T0.11 → D0 | ≈ 6 |
| 1 | 7 + 2 debates | T1.1 → T1.3 → T1.6 → T1.11 → T1.12 → T1.16 → T1.17 → D1 | ≈ 10 |
| 2 | 4 + 1 debate | T2.0 → T2.1 → T2.10 → T2.12 → D2 | ≈ 6 |
| 3 | 4 + 1 debate + publish | T3.1 → human → T3.2 → T3.4 → T3.10 → T3.13 → T3.11 → D3 → T3.12 | ≈ 8 |
| 4 | 3 + 1 debate | T4.1/T4.2 → T4.3 → T4.6 → D4 | ≈ 5 plus CI wall-clock |
| 5 | 6 + external review + 1 debate | vectors → families → T5.7 → T5.8 → external review → T5.10 → T5.11 → D5 | ≈ 8 plus the review's own duration |

The PRD's own estimate for M0 is 3–4 weeks of solo work; later milestones are explicitly "re-estimate after M0". This plan does not replace those estimates. After Phase 1 closes, the orchestrator records the measured cycle time per wave in PROGRESS.md and the human re-estimates Phases 2–5 from it.

---

## 6. Risks specific to delegated execution (and the rule that handles each)

| Risk | Handling |
|---|---|
| A relay's sandbox blocks network, so `pub get`, artifact downloads, or evidence fetches fail inside the implementer | T0.3 measures it per relay; plan §2.2 step 3 pre-warms dependencies and pre-fetches evidence/artifacts; briefs tell implementers to use `--offline` |
| Implementers cannot boot or drive the emulator/simulator | Device-gated tasks are reviewed by the orchestrator running the device gate; results pasted into the task's doc and PROGRESS.md |
| **Hot files** edited by several tasks in one wave (`melos.yaml`, root and package `pubspec.yaml`, `README.md`, `AGENTS.md`, `compat_manifest.json`, `.github/workflows/ci.yml`) | Same-wave edits to a hot file are limited to appending distinct entries (a melos script, a README marker block, a manifest key). The orchestrator resolves the trivial conflict at land time by rebasing. A non-trivial conflict is a plan defect and is surfaced, not patched silently. |
| Fabricated or mis-sourced test vectors | Provenance is mandatory (plan §2.4 rule 7); `vectors:validate` checks presence, not truth; the orchestrator spot-checks one vector per vector task against the upstream file at the pinned commit; every debate spot-checks two more |
| CI-only tasks (T0.2, T1.2, T1.17, T4.x) cannot be proven without a remote | The human creates the GitHub repository during Phase 0 (stop-and-ask item: pushing is outward-facing); until then acceptance is static validation and the task stays `landed (unverified in CI)` in PROGRESS.md |
| Fresh implementer sessions forget earlier decisions | *Decided facts* in PROGRESS.md are copied into every dependent brief (plan §2.2 step 9) |
| A CLI runs out of quota or fails authentication mid-wave | The lane pauses; nothing is re-routed without the human (plan §2.8); the relay's `result.json` status and `stderrTail` are recorded |
| `agy --print` exposes the brief in the process list | Briefs never contain secrets; test mnemonics are public standard vectors; artifacts and credentials are referenced by path or environment variable |
| Codex has no network during a debate | The orchestrator pastes CI logs, device results, and evidence excerpts into the debate brief's `<context>` block |
| An implementer weakens a test to make a gate pass | Plan §2.2 step 6 reviews test edits before gates; any weakened assertion, new skip, or deleted case is a finding until justified |
| Scope creep across owned paths | `touchedFiles` and `git status` are compared against the brief's owned paths at every review; out-of-scope edits are reverted or sent back as a delta brief |
| Two evaluation branches diverge from `main` for long | Eval branches are tagged and short-lived; D1a is scheduled right after W4 so the winner rebases before W5 |

---

## 7. Changelog — plan 1.0 → 1.1 (architecture audit)

Applied on 2026-09-07 from [audit_triage.md](../audit-resaults/audit_triage.md); the PRD moved to v1.2 (its §25) at the same time.

- **Phase 0:** T0.11 drafts DECISION-11…14 (public coin/network facade, session lifecycle and worker protocol, signing and multi-key model, distribution contract); T0.12 writes threat model v0; T0.5 must say whether the artifact source permits a build-identity symbol; T0.8's vector schema gains a `variant` field; D0 adjudicates the four decisions before any public SDK code exists.
- **Phase 1:** T1.2 embeds the build-identity symbol and checks 16 KB alignment; T1.7 verifies identity through that symbol, never by hashing the library; T1.19 is a shared measurement harness both packaging evaluations use (16 KB, `libc++_shared` conflicts, iOS archive and privacy checks, packaged-dependency consumer); T1.11 builds the session API with descriptors, async `close()`, and the coin facade; T1.12 encodes key-less inputs and lets the signer inject; T1.13 is a per-family adapter, not a generic field append.
- **Phase 2:** the family contract is `encodeKeylessInput` / `parseSigningOutput` → sealed `SignResult`; T2.0 adds `KeyLocator`s; T2.1 implements the DECISION-12 protocol; T2.2 and T2.5 prove a two-input, two-path Bitcoin spend; T2.8 derives "generated" from protos and the registry with a variant axis; T2.12 adds the hostile-input and worker-fault suite.
- **Phase 3:** T3.3 hosts raw protobuf signing under `advanced.dart` only; T3.13 publishes `SECURITY.md`, the v1 feature table, and the retention policy before the alpha; T3.11 and T3.12 publish the three packages as one release set with hosted-install smoke.
- **Phase 4:** T4.3 adds candidate/stable channels [REC] and names the unverified surface upstream touched.
- **Phase 5:** T5.7 becomes the threat-model revision; families follow the key-less, multi-key contract.
- **Rules:** repo rule 2 clarified (signing-input encoding allowed, signed-transaction serialization not); rule 6 and new rule 12 carry the family boundary, facade, lifecycle, and signer shape; the orchestrator may make trivial integration fixes inline (plan §2.2 step 8).
- **Not adopted from the audit:** removing per-phase debates; merging vector tasks into family implementations; merging the generation tasks (they are already parallel and disjoint). Reasons in the triage file.

---

## 8. Changelog — plan 1.1 → 1.2 (commit boundary)

Applied on 2026-09-07 on the user's instruction before execution started: the orchestrator does not commit or push; `agy-delegate` performs every git commit, fast-forward, and tag on a commit brief.

- New plan §2.9 (commit boundary), `briefs/_TEMPLATE_commit.md`, `briefs/INIT_repo.md`.
- Roles table, plan §2.1 landing bullet, §2.2 step 8, §2.3 step 7, Appendix A, Appendix B steps 6–7 updated accordingly.
- Phase 0: the "orchestrator prelude" became a delegated repository init; PROGRESS.md gained the `landing` status and the `INIT` row.
- Nothing else in the plan changed; implementers still never commit (rule 10).

---

## Appendix A — Files in `docs/plan/`

| File | Purpose |
|---|---|
| `EXECUTION_PLAN.md` | this document: roles, rules, layout, phase index, sequencing, risks, appendices |
| `PROGRESS.md` | the only status source: task table, environment findings, decided facts, needs-your-eyes, debate triage, decisions log |
| `phases/phase-0-foundation.md` … `phase-5-m4-stable-and-phase-6-backlog.md` | per-phase task tables, notes, waves, debate outlines |
| `briefs/_TEMPLATE_implement.md` | brief skeleton for `claude-delegate` and `agy-delegate` tasks |
| `briefs/_TEMPLATE_debate.md` | brief skeleton for `codex-delegate` phase debates |
| `briefs/EXAMPLE_T1.5_registry_transform.md` | a fully written brief showing the expected level of detail |
| `briefs/<task-id>.md` | written by the orchestrator at dispatch time, one per task; committed in the bookkeeping commit of that task's landing so the brief that produced each commit is in history |
| `briefs/_TEMPLATE_commit.md` | commit-brief skeleton for `agy-delegate` (plan §2.9): git mechanics only |
| `briefs/INIT_repo.md`, `briefs/LAND_<task-id>.md`, `briefs/TAG_phase-<n>.md` | the commit briefs actually dispatched, kept in history |
| `../audit-resaults/audit_triage.md` | accept / reframe / reject verdict per audit finding, with the evidence checked and the PRD or plan change made |

Decision records live outside the plan in `docs/decisions/DECISION-<n>.md` with raw evidence under `docs/decisions/evidence/`.

---

## Appendix B — Dispatch cheat sheet

All commands run from the repository root. In Claude Code every relay call runs with `run_in_background: true`; the orchestrator is notified on completion and then reads `result.json` from the artifact directory the relay prints.

```bash
# 1. worktree for a task
git worktree add ../wallet-core-package.worktrees/T1.5 -b task/T1.5 main
( cd ../wallet-core-package.worktrees/T1.5 && melos bootstrap )     # pre-warm (plan §2.2 step 3)

# 2a. claude-delegate — M or L task
node ~/.agents/skills/claude-delegate/scripts/relay.mjs \
  --brief docs/plan/briefs/T1.3.md --cd ../wallet-core-package.worktrees/T1.3 \
  --effort high --timeout 2h --max-turns 80

# 2b. agy-delegate — S task
node ~/.agents/skills/agy-delegate/scripts/relay.mjs \
  --brief docs/plan/briefs/T1.5.md --cd ../wallet-core-package.worktrees/T1.5 \
  --effort high --timeout 45m            # add --model gemini-3.1-pro-high when the S task has logic

# 2c. claude-delegate — read-only audit (T3.1, evidence analysis)
node ~/.agents/skills/claude-delegate/scripts/relay.mjs \
  --brief docs/plan/briefs/T3.1.md --cd . --read-only --timeout 45m

# 3. codex-delegate — phase debate, never writes
node ~/.agents/skills/codex-delegate/scripts/relay.mjs \
  --brief docs/plan/briefs/D1.md --cd . --read-only --effort high --timeout 1h
#    then confirm in result.json: "touchedFiles": [] and "readOnlyViolation": false

# 4. rework in the same session (delta brief only)
node ~/.agents/skills/claude-delegate/scripts/relay.mjs --brief delta.md --session <sessionId> --cd ../wallet-core-package.worktrees/T1.3
node ~/.agents/skills/agy-delegate/scripts/relay.mjs    --brief delta.md --resume-last          --cd ../wallet-core-package.worktrees/T1.5
node ~/.agents/skills/codex-delegate/scripts/relay.mjs  --brief delta.md --session <threadId> --cd . --read-only

# 5. review in the worktree (orchestrator; never trust finalMessage)
git -C ../wallet-core-package.worktrees/T1.5 status --short
git -C ../wallet-core-package.worktrees/T1.5 diff
( cd ../wallet-core-package.worktrees/T1.5 && melos run analyze && melos run format:check && melos run test )   # plus the task's own gates

# 6. land (plan §2.9: agy-delegate commits; the orchestrator and the implementers never do)
#    orchestrator: set "landed pending-T1.5" in PROGRESS.md, write briefs/LAND_T1.5.md from _TEMPLATE_commit.md
node ~/.agents/skills/agy-delegate/scripts/relay.mjs \
  --brief docs/plan/briefs/LAND_T1.5.md --cd . --add-dir ../wallet-core-package.worktrees/T1.5 \
  --effort high --timeout 20m --dangerously-skip-permissions   # low|high only for gemini-3.1-pro; the flag is the human's standing decision for commit briefs (plan §2.9)
#    agy: commit on task/T1.5 → git merge --ff-only task/T1.5 on main → hash into PROGRESS.md → chore(plan) commit
#    orchestrator afterwards:
git log --oneline -3 && git status --short
melos run analyze && melos run format:check && melos run test
git worktree remove ../wallet-core-package.worktrees/T1.5 && git branch -d task/T1.5

# 7. evaluation branches (T1.8, T1.9, T1.13): the commit brief lands on the eval branch and tags it; nothing merges
#    agy runs, on the orchestrator's brief:
#    git -C ../wallet-core-package.worktrees/T1.8 commit -m "T1.8: packaging evaluation, option 1 (build hooks)"
#    git branch -f eval/option1 task/T1.8 && git tag eval/option1-$(date +%Y%m%d) eval/option1
```

Relay `--help` prints every flag; `result.json` fields used in review are `status`, `finalMessage`, `touchedFiles`, `sessionId`/`threadId`, `readOnlyViolation`, `stderrTail`.

---

## Appendix C — PRD traceability (requirement → task)

| PRD section | Requirement (short) | Delivered by | Verified by |
|---|---|---|---|
| §8 | Package boundaries, dependency direction, import rules, own semver | T0.1, T1.15, T3.11 | `lint:public-api`, D3 |
| §9 | ffigen coverage, protobuf, registry transform, ownership wrappers, symbol inventory | T1.3, T1.4, T1.5, T1.6 | `gen:check`, `inventory:check`, D1 |
| §10.1–10.2 | Typed SDK surface, descriptors, key-less requests, multi-key signers, sealed results, errors, two lifecycles | T0.11, T1.11, T1.12, T2.0–T2.7, T3.2–T3.8 | D0, T3.1 audit, D3 |
| §11.2 | Disposal contract items 1–7 | T1.6 | named tests, D1 question 1 |
| §11.3 | "What we wipe / what we can't" docs and API consequences | T1.18, T3.10 | D1, D3 |
| §11.4 / DECISION-1 | Approach A vs B with spike data; family boundary (key-less encode, signer-owned injection) | T1.12, T1.13, T1.14, T2.0 | D1, D2 |
| §12.1–12.2 / DECISION-2, DECISION-6 | Packaging evaluation protocol on real artifacts | T1.8, T1.9 | D1a |
| §12.3 | Artifacts on GitHub Releases, sha256 in manifest, hard fail, vendored mode, attestations [REC], build-identity symbol, content-addressed retention, mirror, SBOM [REC] | T0.5, T0.11, T1.2, T1.7, T3.13, T4.5 | T1.17 negative test, D1a, D4 |
| §12.4 | Checksum verification (now) vs demonstrated reproducibility (M3) | T1.7, T4.4 | D4 |
| §13.1–13.2 | Generated / exposed / tested per (coin, operation); inventory; coverage checks; exclusions | T0.8, T2.8, T2.9 | `matrix:check`, D2 |
| §13.3 | Initial tested set per milestone | T1.10, T2.2–T2.4, T3.6–T3.8 vectors, T5.1–T5.6 | CI results files |
| §14 / DECISION-3, DECISION-12 | Worker model, §14.3 session state machine and protocol, no cross-isolate handles, request/signer separation | T0.11, T2.0, T2.1, T2.10, T2.12 | D0, D2 |
| §15.1 | Automation inside the spike | Phase 1 ordering (W1–W2 before SDK code) | D1 |
| §15.2 | Pin → build → generate → diff → test → human approval → watch | T1.1, T1.2, T1.3–T1.5, T4.1, T4.2, T1.17, T3.12 (human), T4.3 | T4.6, D4 |
| §15.3 | Compatibility manifest shape, runtime check | T0.7, T1.1, T1.7 | `manifest:validate` |
| §15.4 / DECISION-14 | Per-package semver, exact cross-package pins, release set, publication order, hosted-install smoke, recovery release | T0.11, T3.11, T3.12 | D3 |
| §16 S1 | Glue layer is ours to review | T5.7 threat model | D5 |
| §16 S2 | Disposal and secret contract | T1.6, T1.18 | D1 |
| §16 S3 | Artifact integrity | T1.7, T4.4, T4.5 | D4 |
| §16 S4 | No network at runtime, tested | T1.17 | CI |
| §16 S5 | Input validation before native calls; hostile-input and worker-fault tests | T1.11, T1.12, families, T2.12 | D1 question 2, D2 |
| §16 S6 | Threat model at M0 start, SECURITY.md before alpha, external review before 1.0 | T0.12, T3.13, T5.7, T5.8, T5.10 (DECISION-4 human) | D0, D3, D5 |
| §16 S7 | Keystore guidance in docs | T3.4, T3.10 | D3 |
| §16 S8 | Debug aids off in release | T1.6 (leak tracker compiled out) | D1 |
| §17 / DECISION-5 | MIT, naming without "trust", disclaimer everywhere | T0.1, T0.6, T0.10, T3.11 | D0, D3 |
| §18 | Milestone exit criteria | phase files | each phase's debate |
| §19 | Release acceptance criteria 1–8 | gates + T5.11 | D5 |
| §20 | pub.dev score ≥ 140, coverage ≥ 90 %, zero high findings | T3.11, T5.10 | D3, D5 |
| §21 | Risk register | plan §6 adds delegation-specific risks | — |
| §16 S9 | Exact v1 feature and exclusion table | T3.13 (DECISION-10, human) | D3, D5 |
| §22 | DECISION-1 … DECISION-14 | T0.11 drafts DECISION-11…14; decisions log in PROGRESS.md | D0 adjudicates 11–14; named debates; human where the PRD says so |
