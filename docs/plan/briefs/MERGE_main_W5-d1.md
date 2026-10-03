<task>
MERGE W5 → main, resumed. The dirty tree was the orchestrator's own plan-doc edits; they are to be committed first, then the original steps run unchanged.

0. Repository root /Users/yossefebrahim/Work/wallet-core-package, branch `main`. `git status --short` must list only paths under `docs/plan/` (` M docs/plan/PROGRESS.md` and untracked `docs/plan/briefs/*.md`) — anything else: STOP. Then `git add docs/plan` and commit:
   "chore(plan): push, CI results, merge/dispatch briefs"
   with the trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` after a blank line. `git status --short` must now be empty.
1–4. Exactly as in the previous brief (MERGE_main_W5.md): fetch; check `main` is not behind `origin/main` (it is ahead by 2 now, fine); `git merge --no-ff integration/W5 -m "Merge integration/W5: waves 3–5 (SDK core, Approach A signing, loader, memory layer, lint, probe, docs)" -m "integration/W5 at 24dca0c: T1.6, T1.7, T1.19 (W3), T1.11, T1.12, T1.14, T1.15, T1.18, T1.2-d1, review fixes. Gate-green locally and in CI (run 37148298949); reviewed in docs/plan/reviews/W5-landing-*.md." -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"` (abort and STOP on conflict); `git push origin main` (plain); then
   gh workflow run build-native.yml --ref main -f upstream_tag=4.8.0 -f upstream_commit=d692ac27749d0c615e17c751b70ab4f0aa75c59b -f artifact_set_id=as_4.8.0_001 -f publish_release=false
   (if `gh` says the workflow is not found yet, wait 30 seconds and retry once — GitHub indexes new workflow files shortly after the push); wait 20 s; paste `gh run list --workflow=build-native.yml --limit 3` and the run URL; paste `git log --oneline --graph -6 main` and `gh run list --limit 6`.
Same action_safety as before: no rebase/reset/checkout/stash/amend/tag/force, no `publish_release=true`, no second dispatch beyond the one retry, no file edits, no other agent.
</task>
<structured_output_contract>Report: step-0 hash; MERGE_HASH; push output; dispatch output + run URL; pastes; anything failed/skipped.</structured_output_contract>
