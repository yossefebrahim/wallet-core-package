<task>
LAND T0.R2 — record the reviewed D0 rework of the architecture records in git. This is git bookkeeping only: you change no file except the single PROGRESS.md substitution in step 3.
Repository root, branch main: /Users/yossefebrahim/Work/wallet-core-package
Task worktree, branch task/T0.R2: /Users/yossefebrahim/Work/wallet-core-package.worktrees/T0.R2
The orchestrator has already reviewed the worktree. Commit it exactly as it is; do not "fix" anything. `.dart_tool/` directories are git-ignored and must not be force-added.

Run these steps in order and stop at the first failure (report it; do not improvise a recovery beyond what a step allows):
1. In the worktree: `git status --porcelain` must show only ` M ` entries among these eight paths and nothing else: docs/decisions/DECISION-9.md, DECISION-11.md, DECISION-12.md, DECISION-13.md, DECISION-14.md, docs/architecture/public_model.md, lifecycle.md, signing.md. Then
     git add -A
     git commit -q -m "T0.R2: D0 fixes to DECISION-9/11/12/13/14 and the architecture sketches" -m "Adds the mnemonic-export worker message and an accurate secret-bearing enumeration; resolves the Dispose timeout vs close() conflict; removes signWithAccount (Account stays a descriptor); models every PRD §12.3 per-artifact manifest field; replaces the nested GitHub Release URL with a flat asset name plus hierarchical mirror layout; visibility annotation for wcf_build_info; bounded control messages; finalizer wording; parse-before-release normative; DECISION-9 unproven claim removed; status lines say pending human recording; DECISION-11 and DECISION-14 conditions from D0. Implemented by claude-delegate on brief docs/plan/briefs/T0.R2.md; reviewed by the orchestrator."
   Record `git rev-parse --short HEAD` as HASH1; the commit must list at most 8 files, all within the two directories above.
2. In the repository root: `git rev-parse --abbrev-ref HEAD` must print `main`. Run `git merge --ff-only task/T0.R2`; if it fails because main moved, `git -C /Users/yossefebrahim/Work/wallet-core-package.worktrees/T0.R2 rebase main` (expected clean: disjoint files), abort and report on conflict, then retry. Record the new `git rev-parse --short HEAD` as HASH1.
3. In docs/plan/PROGRESS.md (repository root): replace the exact text `landed pending-T0.R2` with `landed HASH1`. Exactly one occurrence must exist; if not, report and skip.
4. In the repository root:
     git add docs/plan docs/wallet_core_flutter_prd.md
     git commit -q -m "chore(plan): land T0.R2 — progress; PRD v1.2.1 (Phase 0 evidence corrections, §26)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
   If `git diff --cached --quiet` shows nothing staged, skip the commit and say so.
5. Paste the output of: `git log --oneline -6`, `git status --porcelain` (expected empty, or only `?? .claude/scheduled_tasks.lock`), `git branch --list 'task/*'` (do not delete anything), `git worktree list`.
</task>

<action_safety>
Do not push. Do not add a remote. Do not delete branches or worktrees. Do not run git reset, checkout, switch, clean, stash, amend, or rebase -i. Do not edit any file other than the step-3 substitution. Do not create a tag. Do not start another agent or delegation.
</action_safety>

<structured_output_contract>
End with a report in exactly this shape:
  1. Each step: the command run and its outcome (one line per step)
  2. HASH1 and the bookkeeping commit hash (or "skipped")
  3. The pasted verification output from step 5
  4. Anything that failed, was skipped, or needs the orchestrator's decision
</structured_output_contract>
