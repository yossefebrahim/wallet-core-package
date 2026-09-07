<task>
LAND T0.R1 and T0.R3 — record two reviewed D0 rework tasks in git, one after the other. This is git bookkeeping only: you change no file except the two PROGRESS.md substitutions in step 5.
Repository root, branch main: /Users/yossefebrahim/Work/wallet-core-package
Worktree A, branch task/T0.R1: /Users/yossefebrahim/Work/wallet-core-package.worktrees/T0.R1
Worktree B, branch task/T0.R3: /Users/yossefebrahim/Work/wallet-core-package.worktrees/T0.R3
The orchestrator has already reviewed both worktrees. Commit each exactly as it is; do not "fix" anything. `.dart_tool/` directories are git-ignored and must not be force-added.

Run these steps in order and stop at the first failure (report it; do not improvise a recovery beyond what a step allows):
1. In worktree A: `git status --porcelain` must show exactly ` M AGENTS.md`. Then
     git add -A
     git commit -q -m "T0.R1: reconcile AGENTS.md rules 1, 2, 4, 8, 12 with the PRD (D0 findings 1, 2 and rule-by-rule)" -m "Rule 2 permits integrity hashing (SHA-256 of artifacts, manifests, generated inputs) as PRD §12.3 requires; rule 8 time-bounds 'reproducible' to the PRD §12.4 demonstration; rule 1 states CI enforcement begins with gen:check; rule 4 scopes 'only advanced.dart' to the SDK package; rule 12 covers advanced.dart's same-isolate objects. Implemented by agy-delegate on brief docs/plan/briefs/T0.R1.md; reviewed by the orchestrator."
   Record `git rev-parse --short HEAD` as HASH_A; the commit must list exactly 1 file.
2. In the repository root: `git rev-parse --abbrev-ref HEAD` must print `main`. Run `git merge --ff-only task/T0.R1`; if it fails because main moved, `git -C <worktree A> rebase main` (expected clean), abort and report on conflict, then retry. Record the new `git rev-parse --short HEAD` as HASH_A.
3. In worktree B: `git status --porcelain` must show exactly ` M docs/security/threat_model.md`. Then
     git add -A
     git commit -q -m "T0.R3: threat model v0.1 — native-crash wording, monitoring owners, per-phase review, naming (D0 findings 8, 12, 20)" -m "TM-25 no longer claims a native crash yields WorkerTerminatedError (DECISION-12 §3.10); TM-27 names T4.3's advisory feed and TM-28 names T1.17's pub Dependabot ecosystem as owners; §7 adds the mandatory threat-model question at every phase-close debate; wallet.mnemonic becomes exportMnemonic(). Implemented by agy-delegate on brief docs/plan/briefs/T0.R3.md; reviewed by the orchestrator."
   Record `git rev-parse --short HEAD` as HASH_B; the commit must list exactly 1 file.
4. In the repository root: `git -C <worktree B> rebase main` (expected clean: a different file), abort and report on conflict; then `git merge --ff-only task/T0.R3`; record the new `git rev-parse --short HEAD` as HASH_B.
5. In docs/plan/PROGRESS.md (repository root): replace the exact text `landed pending-T0.R1` with `landed HASH_A`, and `landed pending-T0.R3` with `landed HASH_B`. Each must occur exactly once; if not, report and skip that substitution.
6. In the repository root:
     git add docs/plan
     git commit -q -m "chore(plan): land T0.R1 and T0.R3 — D0 triage, rework briefs, plan and template corrections, phase follow-ups" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
   If `git diff --cached --quiet` shows nothing staged, skip the commit and say so.
7. Paste the output of: `git log --oneline -8`, `git status --porcelain` (expected empty, or only `?? .claude/scheduled_tasks.lock`), `git branch --list 'task/*'` (do not delete anything), `git worktree list`.
</task>

<action_safety>
Do not push. Do not add a remote. Do not delete branches or worktrees. Do not touch the T0.R2 worktree at all (another session is working in it). Do not run git reset, checkout, switch, clean, stash, amend, or rebase -i. Do not edit any file other than the two step-5 substitutions. Do not create a tag. Do not start another agent or delegation.
</action_safety>

<structured_output_contract>
End with a report in exactly this shape:
  1. Each step: the command run and its outcome (one line per step)
  2. HASH_A, HASH_B, and the bookkeeping commit hash (or "skipped")
  3. The pasted verification output from step 7
  4. Anything that failed, was skipped, or needs the orchestrator's decision
</structured_output_contract>
