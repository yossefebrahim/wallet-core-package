<task>
LAND T0.1 — record the reviewed work of task T0.1 in git. This is git bookkeeping only: you change no file except the single PROGRESS.md substitution in step 3.
Repository root, branch main: /Users/yossefebrahim/Work/wallet-core-package
Task worktree, branch task/T0.1: /Users/yossefebrahim/Work/wallet-core-package.worktrees/T0.1
The orchestrator has already reviewed the worktree and re-run the gates. Commit the worktree exactly as it is; do not "fix" anything you see in it. Note: `.dart_tool/` directories in the worktree are git-ignored and must not be force-added.

Run these steps in order and stop at the first failure (report it; do not improvise a recovery beyond what a step allows):
1. In the worktree: `git status --porcelain` must be non-empty (expected: 11 untracked entries — .gitignore, AGENTS.md, CLAUDE.md, LICENSE, README.md, THIRD_PARTY_NOTICES.md, analysis_options.yaml, packages/, pubspec.lock, pubspec.yaml, tools/). Then
     git add -A
     git commit -q -m "T0.1: monorepo skeleton, canonical gates, AGENTS.md" -m "Three-package melos 8.6.0 pub workspace (wallet_core_flutter, wallet_core_flutter_bindings, wallet_core_flutter_native) at 0.0.1 with exact cross-package pins, strict analysis options, the analyze/format:check/test gate scripts, AGENTS.md with the twelve repository rules, CLAUDE.md, MIT LICENSE, third-party notices placeholder, README with disclaimer, .gitignore, tools/README.md. Implemented by claude-delegate on brief docs/plan/briefs/T0.1.md; reviewed by the orchestrator (gates green from a clean checkout)."
   Record `git rev-parse --short HEAD` as HASH1. Verify `git show --stat HEAD | tail -25` lists 20 files and no `.dart_tool` path.
2. In the repository root: `git rev-parse --abbrev-ref HEAD` must print `main`. Then
     git merge --ff-only task/T0.1
   If it fails because main has moved: run `git -C /Users/yossefebrahim/Work/wallet-core-package.worktrees/T0.1 rebase main`. If the rebase stops on a conflict, run `git -C <worktree> rebase --abort` and report; otherwise retry the ff merge and record the new `git rev-parse --short HEAD` as HASH1.
3. In the repository root, in docs/plan/PROGRESS.md, replace the exact text `landed pending-T0.1` with `landed HASH1` (HASH1 = the short hash from step 1 or 2). Exactly one occurrence must exist; if zero or more than one, report and skip this step.
4. In the repository root:
     git add docs/plan docs/decisions/evidence/prefetch-2026-09-07 .claude/settings.json
     git commit -q -m "chore(plan): land T0.1 — brief, progress, pre-fetched evidence, sandbox settings" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
   If `git diff --cached --quiet` shows nothing staged, skip the commit and say so.
5. Paste the output of: `git log --oneline -5`, `git status --porcelain` (expected empty), `git branch --list 'task/*'` (expected: task/T0.1 still present — do not delete it), `git worktree list`.
</task>

<action_safety>
Do not push. Do not add a remote. Do not delete branches or worktrees. Do not run git reset, checkout, switch, clean, stash, amend, or rebase -i. Do not edit any file other than the step-3 substitution. Do not create a tag. Do not start another agent or delegation.
</action_safety>

<structured_output_contract>
End with a report in exactly this shape:
  1. Each step: the command run and its outcome (one line per step)
  2. Commit hashes created (HASH1 and the bookkeeping commit, or "skipped")
  3. The pasted verification output from step 5
  4. Anything that failed, was skipped, or needs the orchestrator's decision
</structured_output_contract>
