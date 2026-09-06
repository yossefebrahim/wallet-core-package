<task>
INIT — turn the folder /Users/yossefebrahim/Work/wallet-core-package into a git repository and make its first commit. This is git bookkeeping only: create no files, edit no files, delete nothing.
Current state: the folder contains only a docs/ tree (PRD, execution plan, phase files, brief templates, audit, triage, an archived PRD). There is no .git directory in this folder or in any parent; `git status` currently fails with "not a git repository". Git identity is already configured globally (user.name and user.email); do not change any git config.

Run these steps in order and stop at the first failure (report it; do not improvise):
1. `cd /Users/yossefebrahim/Work/wallet-core-package && git rev-parse --git-dir` must FAIL (no repository yet). If it succeeds, stop and report: the premise is wrong.
2. `git init -b main` in that folder. Verify `git rev-parse --abbrev-ref HEAD` prints `main`.
3. `git add docs` — only the docs/ tree. `git status --porcelain` must show only `A  docs/...` lines (no other paths).
4. Commit with exactly this message (two -m arguments):
     git commit -q -m "docs: PRD v1.2, delegated execution plan 1.2, audit and triage" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
5. Paste the output of: `git log --oneline`, `git status --porcelain` (must be empty), `git ls-files | wc -l`, and `find docs -type f | wc -l` (the two counts must match).
</task>

<action_safety>
Do not create, edit, or delete any file (no .gitignore, no README, nothing). Do not add a remote. Do not push. Do not create tags or branches other than main. Do not change git config. Do not run git reset, checkout, clean, stash, or amend. Do not start another agent or delegation.
</action_safety>

<structured_output_contract>
End with a report in exactly this shape:
  1. Each step: the command run and its outcome (one line per step)
  2. The commit hash created
  3. The pasted verification output from step 5
  4. Anything that failed or that needs the orchestrator's decision
</structured_output_contract>
