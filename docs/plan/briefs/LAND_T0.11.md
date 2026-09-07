<task>
LAND T0.11 — record the reviewed work of task T0.11 in git. This is git bookkeeping only: you change no file except the single PROGRESS.md substitution in step 3.
Repository root, branch main: /Users/yossefebrahim/Work/wallet-core-package
Task worktree, branch task/T0.11: /Users/yossefebrahim/Work/wallet-core-package.worktrees/T0.11
The orchestrator has already reviewed the worktree. Commit the worktree exactly as it is; do not "fix" anything you see in it. `.dart_tool/` directories are git-ignored and must not be force-added.

Run these steps in order and stop at the first failure (report it; do not improvise a recovery beyond what a step allows):
1. In the worktree: `git status --porcelain` must show exactly these untracked entries and nothing else: `?? docs/architecture/` and `?? docs/decisions/DECISION-11.md`, `?? docs/decisions/DECISION-12.md`, `?? docs/decisions/DECISION-13.md`, `?? docs/decisions/DECISION-14.md`. Then
     git add -A
     git commit -q -m "T0.11: DECISION-11..14 architecture records and interface sketches" -m "docs/decisions/DECISION-11.md (public coin/network/account facade), DECISION-12.md (session lifecycle and worker protocol, PRD §14.3 in full), DECISION-13.md (signing model: KeyLocators, sealed SignResult, family boundary), DECISION-14.md (distribution contract on the DECISION-9 recommendation), and docs/architecture/{public_model,lifecycle,signing}.md with the Dart signatures later tasks must follow. Recommended by T0.11, adjudicated at D0, recorded by the human. Implemented by claude-delegate on brief docs/plan/briefs/T0.11.md; reviewed by the orchestrator."
   Record `git rev-parse --short HEAD` as HASH1. Verify `git show --stat HEAD | tail -9` lists exactly 7 files (4 under docs/decisions/, 3 under docs/architecture/).
2. In the repository root: `git rev-parse --abbrev-ref HEAD` must print `main`. If `git merge --ff-only task/T0.11` fails because main moved, run `git -C /Users/yossefebrahim/Work/wallet-core-package.worktrees/T0.11 rebase main` (expected clean: new files only); on conflict abort and report; then retry the ff merge. Record the new `git rev-parse --short HEAD` as HASH1.
3. In the repository root, in docs/plan/PROGRESS.md, replace the exact text `landed pending-T0.11` with `landed HASH1`. Exactly one occurrence must exist; if zero or more than one, report and skip this step.
4. In the repository root:
     git add docs/plan
     git commit -q -m "chore(plan): land T0.11 — brief and progress" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
   If `git diff --cached --quiet` shows nothing staged, skip the commit and say so.
5. Paste the output of: `git log --oneline -5`, `git status --porcelain` (expected: empty, or only `?? .claude/scheduled_tasks.lock`), `git branch --list 'task/*'` (do not delete anything), `git worktree list`.
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
