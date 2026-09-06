<task>
LAND [TASK-ID] — record the reviewed work of task [TASK-ID] in git. This is git bookkeeping only: you change no file except the single PROGRESS.md substitution in step 3.
Repository root, branch main: /Users/yossefebrahim/Work/wallet-core-package
Task worktree, branch task/[TASK-ID]: /Users/yossefebrahim/Work/wallet-core-package.worktrees/[TASK-ID]
The orchestrator has already reviewed the worktree and re-run the gates. Commit the worktree exactly as it is; do not "fix" anything you see in it.

Run these steps in order and stop at the first failure (report it; do not improvise a recovery beyond what a step allows):
1. In the worktree: `git status --porcelain` must be non-empty. Then
     git add -A
     git commit -q -m "[TASK-ID]: [title]" -m "[one-sentence body from the orchestrator]. Implemented by [claude-delegate | agy-delegate] on brief docs/plan/briefs/[TASK-ID].md; reviewed by the orchestrator."
   Record `git rev-parse --short HEAD` as HASH1.
2. In the repository root: `git rev-parse --abbrev-ref HEAD` must print `main`. Then
     git merge --ff-only task/[TASK-ID]
   If it fails because main has moved: run `git -C <worktree> rebase main`. If the rebase stops on a conflict, run `git -C <worktree> rebase --abort` and report; otherwise retry the ff merge and record the new `git rev-parse --short HEAD` as HASH1.
3. In the repository root, in docs/plan/PROGRESS.md, replace the exact text `landed pending-[TASK-ID]` with `landed HASH1`. Exactly one occurrence must exist; if zero or more than one, report and skip this step.
4. In the repository root:
     git add docs/plan
     git commit -q -m "chore(plan): land [TASK-ID] — brief and progress" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
   If `git diff --cached --quiet` shows nothing staged, skip the commit and say so.
5. Paste the output of: `git log --oneline -5`, `git status --porcelain` (expected empty; the orchestrator lists any expected exception here: [none]), `git branch --list 'task/*'`.
</task>

<action_safety>
Do not push. Do not add a remote. Do not delete branches or worktrees. Do not run git reset, checkout, switch, clean, stash, amend, or rebase -i. Do not edit any file other than the step-3 substitution. Do not create a tag unless the brief says so. Do not start another agent or delegation.
</action_safety>

<structured_output_contract>
End with a report in exactly this shape:
  1. Each step: the command run and its outcome (one line per step)
  2. Commit hashes created (HASH1 and the bookkeeping commit, or "skipped")
  3. The pasted verification output from step 5
  4. Anything that failed, was skipped, or needs the orchestrator's decision
</structured_output_contract>
