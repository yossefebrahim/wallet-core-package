<task>
LAND T0.12 — record the reviewed work of task T0.12 in git. This is git bookkeeping only: you change no file except the single PROGRESS.md substitution in step 3.
Repository root, branch main: /Users/yossefebrahim/Work/wallet-core-package
Task worktree, branch task/T0.12: /Users/yossefebrahim/Work/wallet-core-package.worktrees/T0.12
The orchestrator has already reviewed the worktree. Commit the worktree exactly as it is; do not "fix" anything you see in it. `.dart_tool/` directories are git-ignored and must not be force-added.

Run these steps in order and stop at the first failure (report it; do not improvise a recovery beyond what a step allows):
1. In the worktree: `git status --porcelain` must show exactly `?? docs/security/`. Then
     git add -A
     git commit -q -m "T0.12: threat model v0 for the glue layer" -m "docs/security/threat_model.md: scope and trust boundaries, assets, actors, 31 threats (every PRD §16 S6 item plus the audit-derived worker, key-material, SigningOutput, and termination threats) with component, mitigation, owning task, and residual risk; what we do not promise; open questions for T0.11 and D0; revision plan for T5.7. Implemented by claude-delegate on brief docs/plan/briefs/T0.12.md; reviewed by the orchestrator."
   Record `git rev-parse --short HEAD` as HASH1. Verify `git show --stat HEAD | tail -4` lists exactly 1 file, docs/security/threat_model.md.
2. In the repository root: `git rev-parse --abbrev-ref HEAD` must print `main`. main has moved since task/T0.12 was cut, so run
     git -C /Users/yossefebrahim/Work/wallet-core-package.worktrees/T0.12 rebase main
   (expected to apply cleanly: the task adds one new file). If the rebase stops on a conflict, run `git -C <worktree> rebase --abort` and report. Then
     git merge --ff-only task/T0.12
   and record the new `git rev-parse --short HEAD` as HASH1.
3. In the repository root, in docs/plan/PROGRESS.md, replace the exact text `landed pending-T0.12` with `landed HASH1`. Exactly one occurrence must exist; if zero or more than one, report and skip this step.
4. In the repository root:
     git add docs/plan
     git commit -q -m "chore(plan): land T0.12 — brief and progress" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
   If `git diff --cached --quiet` shows nothing staged, skip the commit and say so.
5. Paste the output of: `git log --oneline -6`, `git status --porcelain` (expected: empty, or only `?? .claude/scheduled_tasks.lock`), `git branch --list 'task/*' 'scratch/*'` (do not delete anything), `git worktree list`.
</task>

<action_safety>
Do not push. Do not add a remote. Do not delete branches or worktrees. Do not touch the smoke-* worktrees at all. Do not run git reset, checkout, switch, clean, stash, amend, or rebase -i. Do not edit any file other than the step-3 substitution. Do not create a tag. Do not start another agent or delegation.
</action_safety>

<structured_output_contract>
End with a report in exactly this shape:
  1. Each step: the command run and its outcome (one line per step)
  2. Commit hashes created (HASH1 and the bookkeeping commit, or "skipped")
  3. The pasted verification output from step 5
  4. Anything that failed, was skipped, or needs the orchestrator's decision
</structured_output_contract>
