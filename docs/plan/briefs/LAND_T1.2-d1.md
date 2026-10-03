<task>
LAND T1.2-d1 — git bookkeeping only, two commits, no file content changes.

1. Worktree /Users/yossefebrahim/Work/wallet-core-package.worktrees/W5-integration (branch `integration/W5`, tip `5e96a36`). `git status --short` must list exactly ` M tools/native_build/README.md` and ` M tools/native_build/build_apple.sh` — anything else: STOP and report. Then `git add tools/native_build/README.md tools/native_build/build_apple.sh` and commit:
   "T1.2-d1: link Apple slices with -headerpad_max_install_names"
   body: "Fixes the 87-character install-name limit that failed host flutter test from deep checkout paths (DECISION-2-option1 header-padding row). Verified on the host build: install_name_tool -id with a 213-byte id accepted; test:native 42 + 74; export gate 464/0. Implemented by agy-delegate on brief docs/plan/briefs/T1.2-d1.md; reviewed by the orchestrator."
   then a blank line and the trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. Record HASH_A.
2. Worktree /Users/yossefebrahim/Work/wallet-core-package.worktrees/T1.8 (branch `eval/option1`, tip `e7bea5d`). `git status --short` must list exactly ` M docs/decisions/DECISION-2-option1.md` — anything else: STOP. `git add docs/decisions/DECISION-2-option1.md`; commit "DECISION-2-option1: note T1.2-d1 header-padding fix" with the same trailer. Record HASH_B.
3. Paste `git -C <each worktree> status --short | wc -l` (both 0) and `git log --oneline -1` for each.
</task>
<action_safety>
No push, tag, reset, checkout, merge, rebase, stash, amend, clean, branch deletion, `--force`, or edits to any file. No other agent. Stop and report on anything unexpected.
</action_safety>
<structured_output_contract>
Report: per step the status paste, the command, the hash (or STOPPED: reason); then the step-3 paste.
</structured_output_contract>
