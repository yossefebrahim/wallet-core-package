<task>
LAND T0.2 — record the reviewed work of task T0.2 in git. This is git bookkeeping only: you change no file except the single PROGRESS.md substitution in step 3.
Repository root, branch main: /Users/yossefebrahim/Work/wallet-core-package
Task worktree, branch task/T0.2: /Users/yossefebrahim/Work/wallet-core-package.worktrees/T0.2
The orchestrator has already reviewed the worktree and re-run the gates. Commit the worktree exactly as it is; do not "fix" anything you see in it. `.dart_tool/` directories are git-ignored and must not be force-added.

Run these steps in order and stop at the first failure (report it; do not improvise a recovery beyond what a step allows):
1. In the worktree: `git status --porcelain` must show exactly `?? .github/`. Then
     git add -A
     git commit -q -m "T0.2: CI skeleton" -m ".github/workflows/ci.yml runs the four canonical gates through melos on ubuntu-latest with Flutter 3.44.1 plus a pubspec.lock drift check; android-emulator and ios-simulator are workflow_dispatch-only placeholders for T1.17; .github/dependabot.yml watches GitHub Actions weekly. Implemented by claude-delegate on brief docs/plan/briefs/T0.2.md; reviewed by the orchestrator (actions/checkout pinned to v7 by the orchestrator). Unverified in CI until a remote exists."
   Record `git rev-parse --short HEAD` as HASH1. Verify `git show --stat HEAD | tail -5` lists exactly 2 files under .github/.
2. In the repository root: `git rev-parse --abbrev-ref HEAD` must print `main`. main has moved since task/T0.2 was cut, so run
     git -C /Users/yossefebrahim/Work/wallet-core-package.worktrees/T0.2 rebase main
   (expected to apply cleanly: the task touches only .github/). If the rebase stops on a conflict, run `git -C <worktree> rebase --abort` and report. Then
     git merge --ff-only task/T0.2
   and record the new `git rev-parse --short HEAD` as HASH1.
3. In the repository root, in docs/plan/PROGRESS.md, replace the exact text `landed pending-T0.2` with `landed HASH1`. Exactly one occurrence must exist; if zero or more than one, report and skip this step.
4. In the repository root:
     git add docs/plan .claude/settings.json
     git commit -q -m "chore(plan): land T0.2 — briefs, progress, sandbox settings (loopback, TLS trust)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
   If `git diff --cached --quiet` shows nothing staged, skip the commit and say so.
5. Paste the output of: `git log --oneline -6`, `git status --porcelain` (expected: empty, or only `?? .claude/scheduled_tasks.lock`), `git branch --list 'task/*' 'scratch/*'` (do not delete anything), `git worktree list`.
</task>

<action_safety>
Do not push. Do not add a remote. Do not delete branches or worktrees. Do not touch the T0.8, T0.12, or smoke-* worktrees at all (other sessions are working in them). Do not run git reset, checkout, switch, clean, stash, amend, or rebase -i. Do not edit any file other than the step-3 substitution. Do not create a tag. Do not start another agent or delegation.
</action_safety>

<structured_output_contract>
End with a report in exactly this shape:
  1. Each step: the command run and its outcome (one line per step)
  2. Commit hashes created (HASH1 and the bookkeeping commit, or "skipped")
  3. The pasted verification output from step 5
  4. Anything that failed, was skipped, or needs the orchestrator's decision
</structured_output_contract>
