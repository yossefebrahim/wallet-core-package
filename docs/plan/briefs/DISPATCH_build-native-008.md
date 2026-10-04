<task>
Re-dispatch the native build (owner-authorized 2026-10-03 "push, merge, dispatch"; owner said 2026-10-04 "Go" after fixing GitHub Actions billing). Runs 37160894675 and 37165166476 did not start because the account's Actions billing was blocked ("recent account payments have failed or your spending limit needs to be increased"); run 7 (37158147404) proved the Android library builds and exports all 464 TW* symbols — its only gate failure (four JNI helper extras) is fixed on main (de3fe4c). Nothing is published or reserved (`gh release list` is empty), so the set id is reusable.

From /Users/yossefebrahim/Work/wallet-core-package run exactly:
  gh workflow run build-native.yml --ref main -f upstream_tag=4.8.0 -f upstream_commit=d692ac27749d0c615e17c751b70ab4f0aa75c59b -f artifact_set_id=as_4.8.0_001 -f xcode_version=26.3.0 -f publish_release=false
Wait 45 seconds, then paste `gh run list --workflow=build-native.yml --limit 3` and, for the newest run, `gh run view <id> --json url,status,conclusion,jobs -q '{url,status,conclusion,jobs:[.jobs[]|{name,status,conclusion}]}'`.
If the run already shows `conclusion: failure` within those 45 seconds, paste `gh run view <id> --log-failed | tail -40` — if the text mentions billing/payment/spending limit, say "BILLING STILL BLOCKED" verbatim in the report. Do not touch git, do not edit files, no second dispatch, no `publish_release=true`, no other agent.
</task>
<structured_output_contract>Report: the dispatch output, the run id and URL, the run list paste, the job list, and either "started normally" or "BILLING STILL BLOCKED" with the log excerpt.</structured_output_contract>
