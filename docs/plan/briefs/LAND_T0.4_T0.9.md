<task>
LAND T0.4 and T0.9 — record the reviewed work of two documentation tasks in git, one after the other. This is git bookkeeping only: you change no file except the two PROGRESS.md substitutions in step 5.
Repository root, branch main: /Users/yossefebrahim/Work/wallet-core-package
Worktree A, branch task/T0.4: /Users/yossefebrahim/Work/wallet-core-package.worktrees/T0.4
Worktree B, branch task/T0.9: /Users/yossefebrahim/Work/wallet-core-package.worktrees/T0.9
The orchestrator has already reviewed both worktrees. Commit each exactly as it is; do not "fix" anything. `.dart_tool/` directories are git-ignored and must not be force-added.

Run these steps in order and stop at the first failure (report it; do not improvise a recovery beyond what a step allows):
1. In worktree A: `git status --porcelain` must show exactly `?? docs/decisions/DECISION-8.md` and `?? docs/decisions/evidence/upstream-flutter-dir.md`. Then
     git add -A
     git commit -q -m "T0.4: DECISION-8 evidence and recommendation on upstream's flutter/ directory" -m "docs/decisions/evidence/upstream-flutter-dir.md (facts only, from the pre-fetched upstream capture at 4.8.0) and docs/decisions/DECISION-8.md: three readings argued, verdict 'sample (dormant)', PRD corrections proposed, README wording, revisit triggers. Implemented by claude-delegate on brief docs/plan/briefs/T0.4.md plus T0.4_delta1.md; reviewed by the orchestrator."
   Record `git rev-parse --short HEAD` as HASH_A. Verify `git show --stat HEAD | tail -4` lists exactly 2 files.
2. In the repository root: `git rev-parse --abbrev-ref HEAD` must print `main`. Run `git -C <worktree A> rebase main` (expected clean: two new files); on conflict `git -C <worktree A> rebase --abort` and report. Then `git merge --ff-only task/T0.4`; record the new `git rev-parse --short HEAD` as HASH_A.
3. In worktree B: `git status --porcelain` must show exactly `?? docs/decisions/evidence/upstream-audits.md`. Then
     git add -A
     git commit -q -m "T0.9: evidence on published security audits of upstream wallet-core" -m "docs/decisions/evidence/upstream-audits.md: the Kudelski Security 2023 report in upstream's audit/ directory, a community-submitted review filed as issue #4706, published GitHub security advisories, unverifiable claims, and what none of them cover. Implemented by agy-delegate on brief docs/plan/briefs/T0.9.md plus T0.9_delta1.md; reviewed by the orchestrator."
   Record `git rev-parse --short HEAD` as HASH_B. Verify the commit lists exactly 1 file.
4. In the repository root: `git -C <worktree B> rebase main` (expected clean: one new file); on conflict abort and report. Then `git merge --ff-only task/T0.9`; record the new `git rev-parse --short HEAD` as HASH_B.
5. In docs/plan/PROGRESS.md (repository root): replace the exact text `landed pending-T0.4` with `landed HASH_A`, and the exact text `landed pending-T0.9` with `landed HASH_B`. Each must occur exactly once; if not, report and skip that substitution.
6. In the repository root:
     git add docs/plan docs/decisions/evidence/prefetch-2026-09-07
     git commit -q -m "chore(plan): land T0.4 and T0.9 — briefs, progress, pre-fetched PR and CI facts" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
   If `git diff --cached --quiet` shows nothing staged, skip the commit and say so.
7. Paste the output of: `git log --oneline -8`, `git status --porcelain` (expected: empty, or only `?? .claude/scheduled_tasks.lock`), `git branch --list 'task/*'` (do not delete anything), `git worktree list`.
</task>

<action_safety>
Do not push. Do not add a remote. Do not delete branches or worktrees. Do not touch the T0.5 worktree at all (another session is working in it). Do not run git reset, checkout, switch, clean, stash, amend, or rebase -i. Do not edit any file other than the two step-5 substitutions. Do not create a tag. Do not start another agent or delegation.
</action_safety>

<structured_output_contract>
End with a report in exactly this shape:
  1. Each step: the command run and its outcome (one line per step)
  2. HASH_A, HASH_B, and the bookkeeping commit hash (or "skipped")
  3. The pasted verification output from step 7
  4. Anything that failed, was skipped, or needs the orchestrator's decision
</structured_output_contract>
