<task>
MERGE W5 → main and dispatch the native build — owner-authorized 2026-10-03 ("Yes — push, merge, dispatch"). Preconditions the orchestrator has checked: CI is green on `origin/integration/W5` at 24dca0c (pasted below by the orchestrator), `git merge-tree` reports no conflict.

1. Repository root /Users/yossefebrahim/Work/wallet-core-package: `git rev-parse --abbrev-ref HEAD` must print `main`; `git status --short` must be empty; `git fetch origin`; `git log --oneline -1 origin/main` and `git log --oneline -1 main` — if `main` is behind `origin/main`, STOP and report (do not pull). Then:
     git merge --no-ff integration/W5 -m "Merge integration/W5: waves 3–5 (SDK core, Approach A signing, loader, memory layer, lint, probe, docs)" -m "integration/W5 at 24dca0c: T1.6, T1.7, T1.19 (W3), T1.11, T1.12, T1.14, T1.15, T1.18, T1.2-d1, review fixes. Gate-green locally and in CI; reviewed in docs/plan/reviews/W5-landing-*.md." -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
   If git reports a conflict: `git merge --abort`, STOP, report. Record MERGE_HASH. `git status --short` must be empty.
2. `git push origin main` — plain push, no force. Paste the output. If rejected, STOP (no force, no pull).
3. Dispatch the artifact build, from the root:
     gh workflow run build-native.yml --ref main -f upstream_tag=4.8.0 -f upstream_commit=d692ac27749d0c615e17c751b70ab4f0aa75c59b -f artifact_set_id=as_4.8.0_001 -f publish_release=false
   (every other input keeps its default: expected_tarball_sha256, android_abis arm64-v8a,x86_64, xcode_version, ndk, cmake, expected_symbol_count 464). Then wait 20 seconds and paste `gh run list --workflow=build-native.yml --limit 3` and the run URL (`gh run view <id> --json url -q .url`).
4. Paste `git log --oneline --graph -6 main` and `gh run list --limit 8`.
</task>
<action_safety>
No rebase, reset, checkout, stash, amend, tag, branch deletion, `--force*`, no `publish_release=true`, no second dispatch, no edits to any file, no other agent. Stop and report on anything unexpected.
</action_safety>
<structured_output_contract>
Report: step-1 pastes and MERGE_HASH; push output; the dispatch command's output and the run URL; the step-4 pastes; anything that failed or was skipped.
</structured_output_contract>

===== ORCHESTRATOR: CI EVIDENCE FOR integration/W5 =====
24dca0c = 24dca0c (integration/W5 tip, pushed). CI run 37148298949 on integration/W5: completed, conclusion success — jobs: "Gates (analyze, format, test)": success; "Generated code (gen:check, inventory:check)": success; "iOS simulator": skipped; "Android emulator": skipped. `git merge-tree --write-tree main integration/W5`: clean. Local `main` = c675063 (origin/main 1f0ad2f + today's plan-docs commit); pushing main carries both.
