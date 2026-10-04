<task>
Build the local integration branch `integration/W6` — git bookkeeping only, no push. From the root /Users/yossefebrahim/Work/wallet-core-package (`main` must be at `62a6966`; `git status --short` may show only `docs/plan/**` edits — leave them):
1. `git worktree add -b integration/W6 /Users/yossefebrahim/Work/wallet-core-package.worktrees/W6-integration main`
2. In that worktree, one at a time, each followed by `git status --short` (must be empty) and `git log --oneline -1`:
   `git merge --no-ff task/T1.16 -m "merge task/T1.16 (T1.16a example app + consumer_check skeleton) into integration/W6"`
   `git merge --no-ff task/T1.17 -m "merge task/T1.17 (T1.17-pre runtime dependency policy, Dependabot pub) into integration/W6"`
   `git merge --no-ff task/T1.4-d1 -m "merge task/T1.4-d1 (atomic gen:proto) into integration/W6"`
   `git merge --no-ff task/T1.11-d1 -m "merge task/T1.11-d1 (shutdown ordering) into integration/W6"`
   `git merge-tree` showed all four clean against main; if any merge reports a conflict anyway: `git merge --abort`, STOP, report.
3. `cp -R /Users/yossefebrahim/Work/wallet-core-package.worktrees/W5-integration/third_party /Users/yossefebrahim/Work/wallet-core-package.worktrees/W6-integration/third_party` (git-ignored; needed for the gates the orchestrator runs next). `git status --short` must stay empty.
4. Paste `git log --oneline --graph -14` and `git branch -v --list 'integration/W6' 'task/T1.16' 'task/T1.17' 'task/T1.4-d1' 'task/T1.11-d1'`.
No push, no rebase/reset/checkout/stash/amend/tag/force, no file edits, no other agent.
</task>
<structured_output_contract>Report: per merge the status/log pastes; the graph; the branch list; anything failed/skipped.</structured_output_contract>
