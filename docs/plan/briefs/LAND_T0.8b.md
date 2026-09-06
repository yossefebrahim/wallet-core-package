<task>
LAND T0.8 (part b) — finish landing task T0.8. The task commit already exists: `4a90ea2` on branch task/T0.8 ("T0.8: test-vector inventory schema, loader, and validator", 17 files). A previous brief stopped before merging because its file-count check was written wrongly by the orchestrator; the commit itself is correct and reviewed. This is git bookkeeping only: you change no file except the single PROGRESS.md substitution in step 2.
Repository root, branch main: /Users/yossefebrahim/Work/wallet-core-package (the task worktree has already been removed; work in the root only).

Run these steps in order and stop at the first failure (report it; do not improvise a recovery beyond what a step allows):
1. In the repository root: `git rev-parse --abbrev-ref HEAD` must print `main`, and `git log --oneline main..task/T0.8` must print exactly one line starting with `4a90ea2`. Then
     git merge --ff-only task/T0.8
   Record `git rev-parse --short HEAD` as HASH1 (expected 4a90ea2). If the merge fails, report and stop; do not rebase.
2. In docs/plan/PROGRESS.md, replace the exact text `landed pending-T0.8` with `landed HASH1`. Exactly one occurrence must exist; if zero or more than one, report and skip this step.
3. Run
     git add docs/plan
     git commit -q -m "chore(plan): land T0.8 — briefs and progress" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
   If `git diff --cached --quiet` shows nothing staged, skip the commit and say so.
4. Paste the output of: `git log --oneline -6`, `git status --porcelain` (expected: empty, or only `?? .claude/scheduled_tasks.lock`), `git branch --list 'task/*' 'scratch/*'` (do not delete anything), `git worktree list`.
</task>

<action_safety>
Do not push. Do not add a remote. Do not delete branches or worktrees. Do not touch the T0.12 or smoke-* worktrees at all. Do not run git reset, checkout, switch, clean, stash, amend, rebase, or rebase -i. Do not edit any file other than the step-2 substitution. Do not create a tag. Do not start another agent or delegation.
</action_safety>

<structured_output_contract>
End with a report in exactly this shape:
  1. Each step: the command run and its outcome (one line per step)
  2. HASH1 and the bookkeeping commit hash (or "skipped")
  3. The pasted verification output from step 4
  4. Anything that failed, was skipped, or needs the orchestrator's decision
</structured_output_contract>
