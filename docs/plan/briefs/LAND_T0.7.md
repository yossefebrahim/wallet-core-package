<task>
LAND T0.7 — record the reviewed work of task T0.7 in git. This is git bookkeeping only: you change no file except the single PROGRESS.md substitution in step 3.
Repository root, branch main: /Users/yossefebrahim/Work/wallet-core-package
Task worktree, branch task/T0.7: /Users/yossefebrahim/Work/wallet-core-package.worktrees/T0.7
The orchestrator has already reviewed the worktree and re-run the gates. Commit the worktree exactly as it is; do not "fix" anything you see in it. `.dart_tool/` directories are git-ignored and must not be force-added.

Run these steps in order and stop at the first failure (report it; do not improvise a recovery beyond what a step allows):
1. In the worktree: `git status --porcelain` must show exactly ` M pubspec.yaml`, `?? compat_manifest.json`, `?? tools/manifest/`. Then
     git add -A
     git commit -q -m "T0.7: compatibility manifest skeleton and validator" -m "compat_manifest.json with the exact PRD §15.3 keys and TBD-T<n>.<m> placeholders; tools/manifest (wcf_tool_manifest) with a typed reader, a closed-key-set validator, a CLI with --strict, and tests; melos script manifest:validate. Implemented by agy-delegate on brief docs/plan/briefs/T0.7.md; reviewed by the orchestrator."
   Record `git rev-parse --short HEAD` as HASH1. Verify `git show --stat HEAD | tail -12` lists 8 files and no `.dart_tool` path.
2. In the repository root: `git rev-parse --abbrev-ref HEAD` must print `main`. Then
     git merge --ff-only task/T0.7
   If it fails because main has moved: run `git -C /Users/yossefebrahim/Work/wallet-core-package.worktrees/T0.7 rebase main`. If the rebase stops on a conflict, run `git -C <worktree> rebase --abort` and report; otherwise retry the ff merge and record the new `git rev-parse --short HEAD` as HASH1.
3. In the repository root, in docs/plan/PROGRESS.md, replace the exact text `landed pending-T0.7` with `landed HASH1`. Exactly one occurrence must exist; if zero or more than one, report and skip this step.
4. In the repository root:
     git add docs/plan .gitignore
     git commit -q -m "chore(plan): land T0.7 — briefs, progress, plan 1.2 dials, gitignore" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
   If `git diff --cached --quiet` shows nothing staged, skip the commit and say so.
5. Paste the output of: `git log --oneline -6`, `git status --porcelain` (expected: only `?? .claude/scheduled_tasks.lock` at most, or empty), `git branch --list 'task/*' 'scratch/*'` (do not delete anything), `git worktree list`.
</task>

<action_safety>
Do not push. Do not add a remote. Do not delete branches or worktrees. Do not touch the T0.2, T0.8, or smoke-* worktrees at all (other sessions are working in them). Do not run git reset, checkout, switch, clean, stash, amend, or rebase -i. Do not edit any file other than the step-3 substitution. Do not create a tag. Do not start another agent or delegation.
</action_safety>

<structured_output_contract>
End with a report in exactly this shape:
  1. Each step: the command run and its outcome (one line per step)
  2. Commit hashes created (HASH1 and the bookkeeping commit, or "skipped")
  3. The pasted verification output from step 5
  4. Anything that failed, was skipped, or needs the orchestrator's decision
</structured_output_contract>
