<task>
Two bookkeeping steps in /Users/yossefebrahim/Work/wallet-core-package (branch `main`, tip `de3fe4c`):
1. `git status --short` must list only paths under `docs/plan/` (` M docs/plan/PROGRESS.md`, untracked `docs/plan/briefs/*.md`, `docs/plan/reviews/*.md`) — anything else: STOP. `git add docs/plan`; commit "chore(plan): Phase C log, Codex Phase D debate, T1.16a/T1.17-pre briefs and progress" with the trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` after a blank line. Do NOT push.
2. Probe whether GitHub Actions is unblocked (the owner was fixing billing): run exactly
   gh workflow run build-native.yml --ref main -f upstream_tag=4.8.0 -f upstream_commit=d692ac27749d0c615e17c751b70ab4f0aa75c59b -f artifact_set_id=as_4.8.0_001 -f xcode_version=26.3.0 -f publish_release=false
   wait 60 seconds, then `gh run list --workflow=build-native.yml --limit 2 --json databaseId,status,conclusion,url` and, for the newest run, `gh run view <id> --json jobs -q '.jobs[] | "\(.name): \(.status) \(.conclusion // "-")"'`. If the plan job already shows `failure` within that minute, fetch its annotation: `gh api repos/yossefebrahim/wallet-core-package/check-runs/<plan job databaseId>/annotations -q '.[].message'` and paste it. Do not dispatch a second time either way.
No other git writes, no file edits, no other agent.
</task>
<structured_output_contract>Report: the commit hash; the dispatch output; the run list; the job states; the annotation text if the run failed immediately.</structured_output_contract>
