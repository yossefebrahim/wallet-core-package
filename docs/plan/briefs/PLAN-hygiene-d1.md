<task>
Delta to PLAN-hygiene-2026-10-04 (same file docs/plan/PROGRESS.md in /Users/yossefebrahim/Work/wallet-core-package, no commit, touch nothing else). Two corrections:
1. The italic line "*Superseded 2026-10-03/04: everything below was committed and pushed (see the Phase A/B/C/D log); kept as history.*" was inserted nine times (before every paragraph of `## Concurrency` and of the 2026-09-08 blocks). Keep exactly ONE occurrence: the first line under the `## Concurrency` heading. Delete the other eight (and any blank line they left doubled).
2. In the "**Yours to decide (not fixed by the orchestrator):**" list, the marker you added is identical on items 1 and 3. Make item 1 read "(decided 2026-10-03: amend — DECISION-12 §3.2 now lists eight payloads)" and item 3 read "(decided 2026-10-03: defer — public cancel arrives with T2.1)".
Paste `grep -n "Superseded 2026-10-03/04" docs/plan/PROGRESS.md` (expect one line) and `git diff --stat docs/plan/PROGRESS.md`.
</task>
<structured_output_contract>Report: the grep output and the diff stat.</structured_output_contract>
