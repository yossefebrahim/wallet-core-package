<task>
Fix the Android job of `build-native.yml` and re-dispatch (owner-authorized 2026-10-03). Run 37148898353: Apple job succeeded (artifacts uploaded), Android job failed at "Build, gate, and record" with `tools/native_build/build_android.sh: Permission denied` — the script is tracked with mode 100644. `tools/native_build/lib/common.sh` is also 100644 (it is sourced, so harmless, but make it consistent). Nothing was published or reserved (assemble job skipped; `gh release list` empty), so `as_4.8.0_001` is reused.

From /Users/yossefebrahim/Work/wallet-core-package (branch `main`, tip `99137b9`; the tree has the orchestrator's uncommitted ` M docs/plan/PROGRESS.md` and untracked `docs/plan/briefs/*.md` — expected, leave them alone, do NOT `git add -A`):
1. `chmod +x tools/native_build/build_android.sh tools/native_build/lib/common.sh`; `git diff --stat` must show exactly those two files as mode changes (`old mode 100644 / new mode 100755`) and nothing else.
2. `git add tools/native_build/build_android.sh tools/native_build/lib/common.sh`; commit:
   "ci: mark build_android.sh and lib/common.sh executable"
   body: "build-native.yml run 37148898353: the Android job failed with 'Permission denied' because the script was tracked as 100644; build_apple.sh (100755) ran. Owner-authorized fix during Phase C."
   blank line, trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. `git show --stat --format= HEAD` must list only the two files.
3. `git push origin main` (plain; STOP on rejection, no force).
4. Wait 20 seconds, then:
   gh workflow run build-native.yml --ref main -f upstream_tag=4.8.0 -f upstream_commit=d692ac27749d0c615e17c751b70ab4f0aa75c59b -f artifact_set_id=as_4.8.0_001 -f xcode_version=26.3.0 -f publish_release=false
   Wait 30 seconds; paste `gh run list --workflow=build-native.yml --limit 3` and the new run URL.
No rebase/reset/checkout/stash/amend/tag/force, no `publish_release=true`, no second dispatch, no edits to file contents, no other agent.
</task>
<structured_output_contract>Report: the diff --stat paste, commit hash, push output, dispatch output + run id/URL, run list paste; anything failed/skipped.</structured_output_contract>
