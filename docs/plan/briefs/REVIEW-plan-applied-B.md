<task>
You are an independent auditor for wallet_core_flutter (unofficial MIT Dart/Flutter SDK over Trust Wallet Core; repo /Users/yossefebrahim/Work/wallet-core-package, branch `main`, HEAD = the merge of integration/W6). READ-ONLY: do not create, edit, or delete any file under the repository; your deliverable is your final message. Read-only git commands and `dart`/`flutter`/`melos` analysis or test commands are allowed (they write only under .dart_tool/ and build/).

Question to answer: **measured against the Phase 1 plan of record (docs/plan/phases/phase-1-m0-spike.md: its task table and exit criteria) and the PRD's M0 exit criteria (docs/wallet_core_flutter_prd.md §18, plus the sections each criterion cites), what is actually delivered on `main` today, what is delivered only on unmerged branches (eval/option1, eval/option2, eval/approach-b, task/T1.16, task/T1.17 — see `git branch -a`), and what has not been started?** PROGRESS.md's status table is the claim under test, not evidence.
</task>

<scope>
1. Read docs/plan/phases/phase-1-m0-spike.md (task table T1.1–T1.19 and exit criteria), docs/plan/EXECUTION_PLAN.md §2.4–2.5 (rules + gates), PRD §18 and the sections it cites, docs/plan/PROGRESS.md (status table + today's log), docs/decisions/*.md.
2. For every task T1.1–T1.19 (and their deltas a/b/-d1/-d2 named in PROGRESS.md): verdict ON MAIN / ON BRANCH ONLY (name it) / NOT DONE / BLOCKED, with the deliverable files actually present (paths) and the tests that exercise them (test file + count; run `dart test` or `flutter test` in that package yourself for the count — do not take counts from PROGRESS.md).
3. For every M0 exit criterion in PRD §18: MET / NOT MET / UNPROVEN with evidence. Be strict about device evidence: anything that needs an emulator, simulator, or physical device is UNPROVEN unless a file under docs/decisions/evidence/ or docs/plan/reviews/ records a run with a date and output.
4. Cross-check the twelve AGENTS.md rules against the code on main with concrete greps, at minimum: rule 2 (no crypto in Dart: grep packages/ for `package:crypto`, `pointycastle`, `sha256`, `hmac`, `secp256k1`, `ed25519`, custom bit-mixing in lib/ — distinguish allowed integrity hashing of artifacts from forbidden wallet cryptography and say which each hit is); rule 3 (no runtime network: grep lib/ of the three packages for `dart:io` HttpClient, `package:http`, `Socket`, `Uri.http`); rule 4 (`packages/wallet_core_flutter/lib/wallet_core_flutter.dart` and everything it exports expose no dart:ffi/TW*/protobuf types — read the file and the public signatures; the lint tool under tools/lint exists, run `melos run lint:public-api` and report); rule 6 (request classes carry no key material: read packages/wallet_core_flutter/lib/src/requests/** and signing/**); rule 12 (no generated CoinType on the default surface; async close on public resources).
5. Decisions: which DECISION-n files exist, which decisions the Phase 1 plan says are due in Phase 1 (DECISION-1, -2, -6, -14 ratification, and any others the phase file names) and their current state (recorded / draft / evidence-only / missing). Identify any decision PROGRESS.md calls "recorded" that has no file or whose file still says draft/TBD.
6. Threat model: does docs/security/threat_model.md exist and do its rows reflect the W5/W6 code (worker isolate, OperationDeadline, eight secret-bearing payloads, native loader identity checks, example app)? Name rows that are stale or missing.
</scope>

<grounding_rules>
Ground every claim in a file path with line numbers, a commit hash, or pasted command output. Label inferences. Say UNPROVEN rather than guess. Do not propose new scope. Do not run `git add/commit/push/checkout/reset/stash/merge`, do not dispatch workflows, do not start other agents. Use `git show <branch>:<path>` to inspect unmerged branches instead of checking them out.
</grounding_rules>

<structured_output_contract>
Report in exactly this shape:
  A. Task table T1.1–T1.19 (+ deltas): verdict, where (main/branch), deliverable paths, test file + measured count.
  B. PRD §18 M0 exit criteria: MET / NOT MET / UNPROVEN + evidence.
  C. Rule compliance table (rules 2, 3, 4, 6, 8, 12): grep commands run, hits, judgement.
  D. Decisions table: DECISION-n → due when → state → file → gap.
  E. Findings, each with severity (blocking / should-fix / nit), file:line, description, suggested fix. Blocking means Phase 1 cannot close without it.
  F. Silent drops: anything the Phase 1 plan or PRD §18 requires that no task on any branch delivers.
  G. One paragraph: the honest distance between "what main has" and "Phase 1 closed", and the single most important gap.
</structured_output_contract>
