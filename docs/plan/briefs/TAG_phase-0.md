<task>
TAG phase-0-closed — record the close of Phase 0 in git. This is git bookkeeping only: you change no file.
Repository root, branch main: /Users/yossefebrahim/Work/wallet-core-package
Preconditions the orchestrator has verified before dispatching this brief: every Phase 0 task is landed, D0's findings are triaged and conceded in docs/plan/PROGRESS.md, all rework has landed, the gates are green on main, and DECISION-5/8/9/11-14 are recorded in docs/decisions/ (recorded 2026-09-07 by the orchestrator under the owner's standing authorization to continue without blocking, and marked in each record and in PROGRESS.md as subject to the owner's ratification; the owner may overturn any of them, which re-opens the affected task rather than the tag).

Run these steps in order and stop at the first failure (report it; do not improvise):
1. `git rev-parse --abbrev-ref HEAD` must print `main`; `git status --porcelain` must be empty (or show only `?? .claude/scheduled_tasks.lock`); `git tag --list phase-0-closed` must print nothing. Record `git rev-parse --short HEAD` as HASH_T and paste `git log --oneline -1`. If any check differs, stop and report.
2. `git tag -a phase-0-closed -m "Phase 0 (foundation) closed: workspace, CI skeleton, manifest and vector tooling, threat model v0, DECISION-5/8/9 records, DECISION-11..14 records and architecture sketches, D0 debate triaged. See docs/plan/PROGRESS.md."`
3. Paste `git tag -n1 phase-0-closed`, `git log --oneline -3`, `git status --porcelain`.
</task>

<action_safety>
Do not push (tags included). Do not add a remote. Do not commit, amend, reset, checkout, clean, or delete anything. Do not edit any file. Do not start another agent or delegation.
</action_safety>

<structured_output_contract>
End with a report in exactly this shape:
  1. Each step: the command run and its outcome
  2. The tag name and the commit it points at
  3. The pasted verification output
  4. Anything that failed or needs the orchestrator's decision
</structured_output_contract>
