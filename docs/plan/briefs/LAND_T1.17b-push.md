<task>
Finish LAND_T1.17b (owner-authorized commit/push boundary). The previous run stopped correctly at step 3 because `example/ios` was polluted by melos's re-bootstrap; the orchestrator has restored `example/ios`. The merge `61c1c1a` is on local `main`, unpushed.
1. In /Users/yossefebrahim/Work/wallet-core-package: `git status --short` must show exactly ` M docs/plan/PROGRESS.md`, `?? docs/plan/briefs/LAND_T1.17b.md`, `?? docs/plan/briefs/LAND_T1.17b-push.md`, `?? docs/plan/briefs/T1.17b-d1.md` — anything else: STOP. `git log --oneline -1` must be `61c1c1a`. `git fetch origin`; `origin/main` must be `11261cf` (ancestor of local main).
2. `git add` those four paths by name; commit "docs: T1.17b review and landing; PROGRESS corrected on the example/ios CocoaPods cause" with trailer (blank line first) "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>". `git status --short` must be empty.
3. `git push origin main` (plain). Paste output and `git log --oneline -4 main`.
Do NOT run melos, flutter or dart commands.
</task>
<action_safety>No rebase/reset/checkout/restore/stash/amend/tag/force, no `git add -A`/`.`, no file edits, no other agent.</action_safety>
<structured_output_contract>Report: status output, docs commit hash, push output, log. Real output only.</structured_output_contract>
