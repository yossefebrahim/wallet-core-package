<task>
You are an adversarial project auditor for wallet_core_flutter, an unofficial MIT-licensed Dart/Flutter SDK over the open-source Trust Wallet Core library (not affiliated with or endorsed by Trust Wallet). This is a READ-ONLY audit of the whole project at /Users/yossefebrahim/Work/wallet-core-package on branch `main` (HEAD = merge of integration/W6, 2026-10-04): do not create, edit, or delete any file. Your only deliverable is your final message. Read-only git commands are allowed (`git log --all`, `git show <branch>:<path>`, `git branch -a`, `git grep`).

Goal: judge the PROJECT — plan, process, decisions, documentation, CI, licensing, and the honesty of its status reporting — not line-level code (a sibling reviewer covers code). Assume nothing in docs/plan/PROGRESS.md is true until the tree or git history proves it.
</task>

<context>
Read in this order: AGENTS.md; docs/wallet_core_flutter_prd.md (whole; note the Status row); docs/plan/EXECUTION_PLAN.md; docs/plan/phases/phase-1-m0-spike.md; docs/plan/NEXT_STEPS.md; docs/plan/PROGRESS.md (status table and the dated log at the bottom, newest at the bottom of each section); docs/decisions/*.md and docs/decisions/evidence/**; docs/plan/reviews/*.md (previous reviews and debates — judge whether their blocking findings were actually fixed); docs/security/**; docs/architecture/**; README.md, LICENSE, THIRD_PARTY_NOTICES.md; .github/workflows/*.yml; .github/dependabot.yml; melos.yaml / root pubspec.yaml (gate scripts); compat_manifest.json; test_vectors/**.
State of the world you cannot see: GitHub Actions is currently blocked by account billing, so the first native artifact set (`as_4.8.0_001`) has not been published; `compat_manifest.json` still carries `TBD-T1.2` placeholders; no physical devices are available to the maintainers; an API-35 arm64 Android emulator and an iOS simulator exist locally. Branches `eval/option1`, `eval/option2`, `eval/approach-b` hold packaging/approach evaluations awaiting DECISION-2 and DECISION-1.
</context>

<questions>
1. Plan integrity: does PROGRESS.md's status table agree with git history (commit dates/hashes, branch tips on origin) and with the tree? List every disagreement. Are there tasks marked done whose deliverables are absent on `main` and only on a branch?
2. Previous reviews: for each blocking or should-fix finding in docs/plan/reviews/W5-*.md, W6-fable.md, and the two codex debates, state FIXED (commit/file) / OPEN / SILENTLY DROPPED.
3. Decisions: are DECISION-1/-2/-6/-14 (and any the phase plan says are due) actually decided, or are they evidence files masquerading as decisions? Is the evidence sufficient for the decision each one claims to support? Which decisions are being made implicitly by code already merged (e.g. example/ depending on a packaging path, CI pins, `-DFLUTTER=ON`, the JNI allow-list, `libc++_shared` handling) before the recorded decision exists?
4. PRD vs reality: list PRD sections that the implementation already contradicts (e.g. §10.1, §11.4 wording, §12.2 steps, §15.3 manifest fields, §18 exit criteria) and say whether the PRD or the code should move.
5. Rule 8 and licensing: grep for the forbidden words ("zeroization", "secret-free", "audited", "reproducible" about this SDK's artifacts) and for "trust" in package names; check the disclaimer sentence appears everywhere the project is described (README, package READMEs/pubspec descriptions, example/README, docs index); check LICENSE (MIT) vs THIRD_PARTY_NOTICES.md (upstream Apache-2.0 NOTICE preserved) vs any AGPL legal claim (forbidden). Report every hit with a judgement.
6. CI and release engineering: do ci.yml and build-native.yml enforce the canonical gate table of AGENTS.md (which gates run in CI, which only locally)? Is anything that PROGRESS.md calls "gate-green" actually enforced by a CI job on `main`? Is the artifact pipeline's draft-release/tag-reservation flow safe to re-run (idempotent) and does it match PRD §12 and DECISION-14 §4.3? Is `gen:check` byte-identical between macOS dev machines and the Linux runner (there is a note about protoc pins — find the evidence)?
7. Process risks: the implementers are delegated agents; AGENTS.md rule 10 forbids them from committing; PROGRESS.md records that an agy "LAND"/"PUSH" precedent commits and pushes under owner authorization. Is that precedent recorded clearly enough that a future session will not misread it? Is there any record of what the owner actually authorized (dates, scope), and does the log match it? Are there signs of agents mis-reporting gate results and how is that mitigated?
8. Phase 1 closure: given everything above, write the shortest credible list of items between `main` today and "Phase 1 closed" (tag `phase-1-closed`), each tagged OWNER / CI / AGENT / DEVICE, in dependency order.
9. Anything a new maintainer reading the repository for the first time would be misled by.
</questions>

<grounding_rules>
Ground every claim in file:line, a commit hash, or pasted command output. Label inferences. Say UNPROVEN rather than guess. Do not propose new product scope. Do not touch git write operations, do not dispatch workflows, do not start other agents.
</grounding_rules>

<structured_output_contract>
Report in exactly this shape:
  A. Findings, ordered by severity (blocking / should-fix / nit): id, severity, file:line or commit, description, suggested fix, confidence.
  B. Per question 1–9: verdict and evidence summary.
  C. Previous-review findings ledger (Q2) as a table: review → finding → FIXED/OPEN/DROPPED → evidence.
  D. Phase-1 closure list (Q8).
  E. One paragraph: is the project's self-reporting trustworthy? What single process change would most improve it?
</structured_output_contract>
