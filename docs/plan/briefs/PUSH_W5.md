<task>
PUSH W5 — commit the three approved pre-push edits on `integration/W5`, then push the Phase-B branch list to `origin` (github.com/yossefebrahim/wallet-core-package). The owner authorized the push on 2026-10-03 ("Yes — push, merge, dispatch"). No merge into `main` and no workflow dispatch in this brief — those come after CI is green.

1. Worktree /Users/yossefebrahim/Work/wallet-core-package.worktrees/W5-integration (branch `integration/W5`, tip `0ac87c7`). `git status --short` must list exactly ` M .github/workflows/ci.yml`, ` M .gitignore`, ` M docs/wallet_core_flutter_prd.md`, ` D tools/gen/bin/registry_transform.exe` — anything else: STOP. Then `git add -A` and commit:
   "chore: drop tracked registry_transform.exe, pin CI to Flutter 3.47.5, PRD §11.4 matches Approach A as built"
   body: "Owner-approved pre-push housekeeping (PROGRESS.md, 2026-10-03): the 6 MB compiled generator (tracked since 1d70c6c, unreferenced; *.exe now ignored); ci.yml pinned to the Flutter the host and every gate record use (3.47.5 / Dart 3.13.4, whose formatter re-laid-out files 3.44.1 would flag); PRD §11.4 Approach A cells reworded to the code (no Dart-heap key copy; one zeroed calloc staging buffer; upstream's native copies remain). Implemented by agy-delegate on brief docs/plan/briefs/W5-prepush.md; reviewed by the orchestrator."
   blank line, trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. Record HASH_W5.
2. From the repository root /Users/yossefebrahim/Work/wallet-core-package, push these branches, one `git push origin <branch>` per command, in this order, pasting each command's output: `integration/W2`, `integration/W3`, `task/T1.11`, `task/T1.12`, `task/T1.14`, `task/T1.15`, `task/T1.18`, `eval/approach-b`, `eval/option1`, `eval/option2`, `integration/W5`. Plain pushes only: no `--force`, no `--force-with-lease`, no `-u` needed, no tags, no `main`. If any push is rejected (non-fast-forward or otherwise), do not retry with force — STOP and report the message.
3. Paste `git ls-remote --heads origin | sort -k2` and `gh run list --limit 15` (from the root).
</task>
<action_safety>
No merge, rebase, reset, checkout, stash, amend, tag, branch deletion, `--force*`, no push of `main`, no workflow dispatch, no edits to any file, no other agent. Stop and report on anything unexpected.
</action_safety>
<structured_output_contract>
Report: step-1 status paste and HASH_W5; per-branch push output; the step-3 pastes; anything that failed or was skipped.
</structured_output_contract>
