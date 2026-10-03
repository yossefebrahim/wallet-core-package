<task>
LAND W5 — record the reviewed, uncommitted work of waves 3–5 in git, one branch at a time, then build the `integration/W5` branch. This is git bookkeeping only: you change no file content except merge-conflict resolution in step 11. The orchestrator has reviewed every tree and re-run the gates; commit each tree exactly as it is — do not "fix" anything you see.

Worktrees live under `/Users/yossefebrahim/Work/wallet-core-package.worktrees/<name>`; the repository root is `/Users/yossefebrahim/Work/wallet-core-package` (branch `main` — you never touch it). Every tree below sits on commit `1d70c6c` (`integration/W3` = `integration/W2` today) with its content uncommitted on top. Trees were built on top of each other, so after an earlier step commits a base, `git checkout -B <branch> <base>` in a later tree re-points its branch to that base and leaves only that tree's own delta showing as modified (the working tree is not touched by `checkout -B` when the files are identical). The plan: `docs/plan/NEXT_STEPS.md` Phase B.

Before and after EVERY step paste `git status --short | sort` (collapse `??` directories as git prints them). A step whose status lists any path OUTSIDE its allowed set STOPS the brief: do not commit that step, do not continue to later steps, report the unexpected paths. Empty directories, `.dart_tool/`, `build/`, `third_party/`, `*.iml`, `.DS_Store` are git-ignored and never appear; `.claude/.cc-writes/` directories are empty and never appear.

Commit author: whatever `git config user.name/email` already gives (do not set it). Every commit message ends with the trailer line `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` after a blank line.

Steps, strictly in order:

1. `W2-integration` (expect branch `integration/W2`, `git rev-parse --abbrev-ref HEAD` must print it).
   Allowed: `.github/workflows/ci.yml`, `tools/gen/test/registry_transform_test.dart`.
   `git add .github/workflows/ci.yml tools/gen/test/registry_transform_test.dart`; commit:
   "ci: install protoc 33.4 + protoc_plugin 25.0.0 in the generated job; registry test skips without upstream tree"
   Record HASH_W2. `git status --short` must then be empty.

2. `W3-integration` (branch `integration/W3`).
   Allowed: anything — this tree holds wave 3 in full. Just paste the status (expect ~37 entries, among them `.github/workflows/ci.yml`, `docs/decisions/DECISION-14.md`, `packages/wallet_core_flutter_bindings/**`, `packages/wallet_core_flutter_native/**`, `tools/{gen,inventory,manifest,packaging_eval}/**`, `pubspec.yaml`, `pubspec.lock`). STOP only if you see `third_party/`, `build/`, `.dart_tool/`, or any file over 5 MB (`git status --short | awk '{print $2}' | xargs -I{} find {} -type f -size +5M` must print nothing).
   `git add -A`; commit:
   "integration/W3: T1.6 memory layer, T1.7 native loader, T1.19 packaging harness, 3.13 reformat"
   body: "Wave 3 (T1.6, T1.7, T1.19) plus the FMT-3.13 reformat and the two W2 CI fixes, as reviewed and gate-green in this tree (PROGRESS.md, Wave 3)."
   Record HASH_W3. Status must be empty afterwards.

3. `T1.11`: `git checkout -B task/T1.11 integration/W3`.
   Allowed set (and nothing else): `packages/wallet_core_flutter/**`, `packages/wallet_core_flutter_bindings/ffigen.yaml`, `packages/wallet_core_flutter_bindings/lib/registry.dart`, `packages/wallet_core_flutter_bindings/lib/src/generated/**`, `pubspec.yaml`, `pubspec.lock`, `tools/native_build/run_native_tests.sh`.
   `git add -A`; commit: "T1.11: SDK core — session, engine, proxies, facades"
   body: "Implemented by claude-delegate (Opus 5.5) on briefs T1.11a/T1.11b; reviewed by the orchestrator; wave-5 review fixes included."
   Record HASH_T1_11.

4. `T1.12`: `git checkout -B task/T1.12 task/T1.11`.
   Allowed: `packages/wallet_core_flutter/**`, `docs/decisions/DECISION-1-approach-a.md`, `docs/decisions/DECISION-12.md`, `docs/architecture/lifecycle.md`, `docs/security/threat_model.md`.
   `git add -A`; commit: "T1.12: EVM request, key-less encoder, Approach A signing, wave-5 review fixes"
   body: "Implemented by claude-delegate (Opus 5.5) on briefs T1.12a/T1.12b, T1.12-d1, W5-verification-fixes; DECISION-12 §3.2/§3.5/§8 and lifecycle.md §6 amended per the 2026-10-03 decision (brief DEC-12-amend)."
   Record HASH_T1_12.

5. `T1.13`: `git checkout -B eval/approach-b task/T1.12`.
   Allowed: `packages/wallet_core_flutter_native/src/shim/**`, `packages/wallet_core_flutter_native/lib/**`, `tools/native_build/**`, `packages/wallet_core_flutter/**`, `docs/decisions/DECISION-1-approach-a.md`, `docs/decisions/DECISION-1-approach-b.md`.
   `git add -A`; commit: "T1.13 (eval): Approach B adapter prototype, host scope"
   body: "Eval branch. Implemented by claude-delegate (Opus 5.5) on briefs T1.13, T1.13-d1; reviewed by the orchestrator. DECISION-1-approach-a.md differs from task/T1.12's copy on purpose (describes the seam)."
   Record HASH_T1_13.

6. `T1.14`: `git checkout -B task/T1.14 integration/W3`.
   Allowed: `tools/probes/**`, `docs/decisions/evidence/sign_json_coverage.md`, `pubspec.yaml`, `pubspec.lock`.
   `git add -A`; commit: "T1.14: SignJSON availability probe — 106 of 167 coins"
   body: "Implemented by agy-delegate on briefs T1.14, T1.14-d1, A3-crypto-pin; reviewed by the orchestrator."
   Record HASH_T1_14.

7. `T1.15`: `git checkout -B task/T1.15 task/T1.11`.
   Allowed: `tools/lint/**`, `pubspec.yaml`, `pubspec.lock`.
   `git add -A`; commit: "T1.15: public-API lint (lint:public-api)"
   body: "Implemented by agy-delegate then claude-delegate (Opus 5.5) on briefs T1.15, T1.15-d1..d3; reviewed by the orchestrator. CI wiring is T1.17's."
   Record HASH_T1_15.

8. `T1.18`: `git checkout -B task/T1.18 task/T1.11`.
   Allowed: `docs/security/memory_contract.md`, `docs/security/lifecycle.md`, `README.md`.
   `git add -A`; commit: "T1.18: memory contract and lifecycle pages, README pointers"
   body: "Implemented by claude-delegate (Opus 5.5) on briefs T1.18, T1.18-d1, T1.18-d2; reviewed by the orchestrator."
   Record HASH_T1_18.

9. `T1.8`: `git checkout -B eval/option1 integration/W3` (the tree is currently on `task/T1.8`; that branch name is left pointing where it is).
   Allowed: `packages/wallet_core_flutter_native/hook/**`, `packages/wallet_core_flutter_native/lib/**`, `packages/wallet_core_flutter_native/pubspec.yaml`, `packages/wallet_core_flutter_native/test/**`, `eval/**`, `docs/decisions/DECISION-2-option1.md`, `pubspec.lock`.
   `git add -A`; commit: "T1.8 (eval): packaging Option 1 — build hooks"
   body: "Eval branch. Implemented by claude-delegate (Opus 5.5) on briefs T1.8a, T1.8a-d1..d6; reviewed by the orchestrator; Android rows pending the native artifacts (NEXT_STEPS Phase D1)."
   Record HASH_T1_8.

10. `T1.9`: `git checkout -B eval/option2 integration/W3`.
    Allowed: `packages/wallet_core_flutter_native/android/**`, `packages/wallet_core_flutter_native/ios/**`, `packages/wallet_core_flutter_native/tool/**`, `packages/wallet_core_flutter_native/analysis_options.yaml`, `packages/wallet_core_flutter_native/pubspec.yaml`, `packages/wallet_core_flutter_native/test/**`, `eval/**`, `docs/decisions/DECISION-2-option2.md`.
    `git add -A`; commit: "T1.9 (eval): packaging Option 2 — Gradle/podspec"
    body: "Eval branch. Implemented by claude-delegate (Opus 5.5) on briefs T1.9a, T1.9a-d1..d6; reviewed by the orchestrator; Android rows pending the native artifacts (NEXT_STEPS Phase D1)."
    Record HASH_T1_9.

11. Integration branch. From the repository root:
    `git worktree add -b integration/W5 /Users/yossefebrahim/Work/wallet-core-package.worktrees/W5-integration task/T1.12`
    Then in that worktree, one at a time, each followed by `git status --short` and `git log --oneline -1`:
    a. `git merge --no-ff task/T1.14 -m "merge task/T1.14 into integration/W5"` — expected conflict: `pubspec.yaml` only. Resolution rule: keep BOTH sides — in `workspace:` keep every `- tools/...` entry from both (ordering: as in task/T1.12, then the new one appended where the other side put it), and in `melos: scripts:` keep task/T1.12's `test:native` entry (the `bash tools/native_build/run_native_tests.sh` one) AND add `probe:sign-json: dart run tools/probes/bin/sign_json_probe.dart`. If `pubspec.lock` conflicts, take task/T1.12's version (`git checkout --ours pubspec.lock`) — the orchestrator re-bootstraps afterwards. After resolving: `git add pubspec.yaml pubspec.lock` and `git commit --no-edit`. If any OTHER file conflicts, `git merge --abort` and STOP.
    b. `git merge --no-ff task/T1.15 -m "merge task/T1.15 into integration/W5"` — same rule; the new script is `lint:public-api: dart run tools/lint/bin/public_api_lint.dart` and the workspace entry `- tools/lint`.
    c. `git merge --no-ff task/T1.18 -m "merge task/T1.18 into integration/W5"` — expected clean.
    Paste the final `pubspec.yaml` `workspace:` list and the full `scripts:` key list (`grep -nE '^    [a-z:-]+:' pubspec.yaml`), the result of `grep -c "<<<<<<<" pubspec.yaml` (must be 0), and `git log --oneline --graph -12`.

12. Final paste: for each of the ten trees, `git -C <tree> rev-parse --abbrev-ref HEAD` and `git -C <tree> status --short | wc -l` (all must be 0), plus `git -C /Users/yossefebrahim/Work/wallet-core-package branch --list 'integration/*' 'task/*' 'eval/*' -v`.
</task>

<action_safety>
No `git push`, no tag, no remote changes, no branch deletion, no `--force`, no `reset`, no `clean`, no `stash`, no `amend`, no `rebase`, no edits to `main` or to the repository-root worktree. The only file content you may change is the merge resolution in step 11. Do not start another agent or delegation. If anything surprises you, stop and report rather than improvise.
</action_safety>

<structured_output_contract>
End with a report in exactly this shape:
  1. Per step: branch, before/after status summary (counts and any unexpected path), commit hash created (or "STOPPED: <reason>").
  2. The eleven hashes (HASH_W2, HASH_W3, HASH_T1_11, HASH_T1_12, HASH_T1_13, HASH_T1_14, HASH_T1_15, HASH_T1_18, HASH_T1_8, HASH_T1_9, integration/W5 tip).
  3. The step-11 pastes (merge conflicts seen and how resolved; final workspace/scripts lists; graph).
  4. The step-12 paste.
  5. Anything that failed, was skipped, or needs the orchestrator's decision.
</structured_output_contract>
