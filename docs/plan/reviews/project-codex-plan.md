# Codex whole-project plan/process audit (gpt-5.5, xhigh, read-only) — main 672e09e, 2026-10-04

Brief: docs/plan/briefs/CODEX-REVIEW-project-plan.md. Thread 01a10601-852f-7ba0-bca1-1c371df5d32a. Report verbatim below; orchestrator triage in PROGRESS.md.

A. Findings
**Blocking**

| id | severity | evidence | description | suggested fix | confidence |
|---|---|---:|---|---|---|
| B1 | blocking | `git status --short --branch`; `docs/plan/PROGRESS.md:327-330`; commit `672e09e` | The project’s single status source is stale and locally dirty. `HEAD` has already merged/pushed W6 (`672e09e`), while committed `PROGRESS.md` still says W6 is “next merge into main”; the correcting entry is uncommitted, alongside untracked briefs. | Reconcile and commit `PROGRESS.md` as part of the W6 landing record, or stop treating it as authoritative until clean. | high |
| B2 | blocking | `compat_manifest.json:18-34`, `compat_manifest.json:48-59`; `packages/wallet_core_flutter_native/lib/src/generated/manifest.dart:36-57`; `docs/plan/PROGRESS.md:330` | Phase 1 cannot honestly close: native artifact identity is still `TBD-T1.2`, artifact hashes are placeholders, and the first artifact set has not published because Actions billing blocked the run. | Publish the artifact set, splice real artifact metadata, regenerate the manifest, and remove/build any ABI rows that are not actually shipped. | high |
| B3 | blocking | `docs/decisions/DECISION-14.md:79-88`; `packages/wallet_core_flutter_native/lib/src/loader/handler.dart:277-278` | DECISION-14 requires four runtime/build comparisons, including manifest hash. Default initialization only verifies manifest hash when optional `manifestBytes` are supplied, so the default path skips one claimed comparison. | Either wire embedded manifest bytes into default init or amend DECISION-14 and docs to state the comparison is not active yet. | high |
| B4 | blocking | `git ls-tree -r --name-only HEAD | rg 'DECISION-(1|2|6)'`; `docs/decisions/DECISION-1-approach-a.md:1-11`; `docs/plan/PROGRESS.md:470-475,483`; `docs/plan/phases/phase-1-m0-spike.md:95-105` | DECISION-1, DECISION-2, and DECISION-6 are not decided on `main`; DECISION-14 is recorded but still pending owner ratification. Evidence files are being treated too easily as decisions. | Run the D1a/D1 decision steps after real artifact/device evidence, then record explicit owner decisions. | high |
| B5 | blocking | `.github/workflows/ci.yml:21-55,67-142,144-160`; `AGENTS.md:22-37`; `docs/plan/PROGRESS.md:330` | CI does not enforce the canonical gate table, and current Actions are billing-blocked. `test:native`, `lint:public-api`, `lint:runtime-deps`, `vectors:validate`, device jobs, and consumer check are not enforced on `main`; emulator jobs are placeholders. | Separate “CI-enforced” from “local-only” gates in status, then add jobs or stop calling them CI gates. | high |
| B6 | blocking | `docs/wallet_core_flutter_prd.md:411-414`; `docs/plan/phases/phase-1-m0-spike.md:7-13`; provided world-state; `test_vectors/ethereum/vectors.yaml:13,26,39,55,93` | PRD M0 requires Android/iOS physical device evidence and simulator/emulator evidence. The maintainers have no physical devices, only local emulators/simulators, and vectors still have empty `platforms_verified`. | Produce the required evidence or amend the M0 exit criteria before tagging Phase 1 closed. | high |

**Should-Fix**

| id | severity | evidence | description | suggested fix | confidence |
|---|---|---:|---|---|---|
| S1 | should-fix | `AGENTS.md:16`; `docs/plan/EXECUTION_PLAN.md:171-200`; `docs/plan/NEXT_STEPS.md:7-12`; `docs/plan/PROGRESS.md:330,359-365` | Commit/push authority is contradictory. Rules forbid agents committing, plan says only owner commits, but W6 records an agy merge/push under owner authorization. The durable authorization record is not cleanly committed. | Add one current policy paragraph with dates/scope of the owner exception, and remove/supersede stale landing instructions. | high |
| S2 | should-fix | `.github/workflows/build-native.yml:156-162,520-532`; `docs/decisions/DECISION-14.md:101-112,204-222` | Artifact release flow is safe against overwrite but not idempotent after draft release creation: a failed partial publish consumes the artifact-set id because rerun refuses an existing release. | Document “retry means next artifact-set id” and ensure recovery playbook matches DECISION-14 immutability. | high |
| S3 | should-fix | `docs/wallet_core_flutter_prd.md:151,238-250,357-381,411-414`; `docs/decisions/DECISION-14.md:96-112` | PRD has drifted from current decisions and code: §10.1 still shows account-based signing; §15.3 still documents 12-hex digest asset names; §12.2/§18 require evidence not currently obtainable. | Update PRD where decisions superseded it; keep acceptance criteria only where the project still intends to meet them. | high |
| S4 | should-fix | `AGENTS.md:29`; `pubspec.yaml:108-115` | Canonical gate table says `gen:all` includes `gen:matrix`; actual `gen:all` runs `gen:manifest` and no `gen:matrix`. | Align AGENTS with the real Phase 1 gate, or add the promised matrix generator. | high |
| S5 | should-fix | `packages/wallet_core_flutter/pubspec.yaml:1-5`; `packages/wallet_core_flutter_bindings/pubspec.yaml:1-5`; `packages/wallet_core_flutter_native/pubspec.yaml:1-6`; `docs/audit-resaults/wallet_core_flutter_architecture_audit.md:1-8` | The exact disclaimer appears in main README/native README/example README and library doc comments, but not in package pubspec descriptions, and an older audit doc describes the project without it. | Put the exact disclaimer wherever package/project descriptions may be published, or narrow the rule explicitly. | medium |
| S6 | should-fix | `tools/native_build/build_android.sh:73-79,357-369,432-444`; `.github/workflows/build-native.yml:68-73`; `tools/native_build/check_exports.sh:136-139` | Several packaging decisions are already implicit in code before DECISION-2/D1a: shipped ABIs, `-DFLUTTER=ON`, Android JNI allow-list, ELF `.dynsym` export checking, and libc++ handling assumptions. | Ratify or reverse these in DECISION-2/DECISION-6/DECISION-14. | high |
| S7 | should-fix | `tools/consumer_check.sh:12-16,179-203,206-227` | `consumer_check` is still a scaffold around dependency/build/run flow; hosted dependency and device build checks wait for the packaging decision. | Do not count consumer checks as Phase 1 complete until T1.16b runs against the chosen packaging path. | high |
| S8 | should-fix | `.github/dependabot.yml:9-13`; `docs/plan/PROGRESS.md:330` | Dependabot pub workspace behavior is explicitly unverified, and the first opened PR targets `actions/download-artifact` v4→v8 while CI billing is blocked. | Treat Dependabot as unproven until its first useful PR runs real CI. | medium |
| S9 | should-fix | `tools/native_build/build_android.sh:35-38`; `tools/native_build/README.md:177-188`; `.github/workflows/build-native.yml:38-42` | Native build docs still say Android was “not yet run,” while PROGRESS records multiple build-native attempts. The artifact is still not published, but the wording is stale. | Update native build docs to distinguish attempted, billing-blocked, failed, and green artifact states. | high |

**Nit**

| id | severity | evidence | description | suggested fix | confidence |
|---|---|---:|---|---|---|
| N1 | nit | `docs/archive/wallet_core_flutter_prd_v1.1.md`; `docs/plan/PROGRESS.md:384` | Archived docs still contain Rule 8-sensitive words. This is likely historical, but a new maintainer will not know the exemption. | Add an archive exemption note or clean archived marketing language. | medium |
| N2 | nit | `find docs -maxdepth 2 \( -iname README.md -o -iname index.md \)` output: none | The requested “docs index” does not exist. | Add one or remove it from the checklist. | medium |
| N3 | nit | `README.md:11-14`; `test_vectors/ethereum/vectors.yaml:13,26,39,55,93` | README’s “Verified support” section is intentionally placeholder-like, while vectors have no verified platforms. Not false, but easy to overread. | Keep the section visibly provisional until platform evidence exists. | medium |

B. Per Question 1-9
**1. Plan Integrity**

Verdict: not trustworthy as-is.

Evidence summary:

- `HEAD`, `main`, and `origin/main` now point at `672e09e` (`Merge integration/W6...`), while committed `docs/plan/PROGRESS.md:329` still says “W6 is next merge into main.” The correcting W6 merge/push log entry is only in the dirty working tree at `docs/plan/PROGRESS.md:330`.
- `git status --short --branch` shows `M docs/plan/PROGRESS.md` plus untracked W6 brief files, so the status source is not clean.
- `docs/plan/PROGRESS.md:3` still says Plan 1.2 and “orchestrator never commits/merges/tags/pushes,” while `docs/plan/EXECUTION_PLAN.md:5-8` is Plan 1.3 and `PROGRESS.md:330` records an agy merge/push under owner authorization.
- Tasks marked as branch/evaluation work but absent from `main`: T1.8/T1.9 live on `eval/option1` and `eval/option2`; Approach B evidence lives on `eval/approach-b`; DECISION-2 and DECISION-6 are not present on `main`.
- W6 deliverables are now on `main`: `076d618` for example/consumer-check workspace changes, `1131dd5` for runtime-deps lint, `51d4c62` for proto atomicity, `ba83073` for shutdown ordering, merged by `672e09e`.

**2. Previous Reviews**

Verdict: many W5/W6 technical issues were fixed, but the most important project/process findings remain open: artifact placeholders, default manifest hash comparison, packaging decisions, device evidence, and status hygiene. Full ledger is in section C.

**3. Decisions**

Verdict: DECISION-1/-2/-6 are not decided; DECISION-14 is a recorded design pending owner ratification and live artifact proof.

Evidence summary:

- DECISION-1: `docs/decisions/DECISION-1-approach-a.md:9` says “Evidence only. DECISION-1 is owner's to decide at M0 exit.”
- DECISION-2: no `DECISION-2*.md` exists on `main`; `docs/plan/PROGRESS.md:471` says open.
- DECISION-6: no `DECISION-6*.md` exists on `main`; `docs/plan/PROGRESS.md:475` says open.
- DECISION-14: `docs/decisions/DECISION-14.md:11` says recorded by orchestrator, subject to owner ratification; `docs/plan/PROGRESS.md:483` agrees.
- Implicit decisions already merged: Flutter CI pin `3.47.5` in `.github/workflows/ci.yml:31,77`; build-native publish job still uses Flutter `3.44.1` in `.github/workflows/build-native.yml:436-440`; Android ABIs in `.github/workflows/build-native.yml:68-73`; `-DFLUTTER=ON` in `tools/native_build/build_android.sh:357-369`; JNI allow-list in `tools/native_build/build_android.sh:432-444`; `.dynsym` export gate in `tools/native_build/check_exports.sh:136-139`; Boost homebrew export in `tools/native_build/build_android.sh:309-314`.

**4. PRD vs Reality**

Verdict: the PRD is partly stale and partly still a valid bar the implementation has not reached.

- PRD should move: §10.1 still shows `wc.signer.sign(request, account)` at `docs/wallet_core_flutter_prd.md:151`, conflicting with DECISION-13’s key-locator signer model.
- PRD should move: §15.3 asset naming still says 12-hex prefix at `docs/wallet_core_flutter_prd.md:367`, while DECISION-14 requires the full 64-hex digest at `docs/decisions/DECISION-14.md:96-112`.
- Code/process should move: §12.2 packaging checks at `docs/wallet_core_flutter_prd.md:238-250` and §18 M0 exit at `docs/wallet_core_flutter_prd.md:411-414` require evidence not yet produced.
- Code should move or decision should be amended: DECISION-14’s manifest-hash comparison is not default-wired, per `handler.dart:277-278`.
- Fixed: the old PRD §11.4 key-boundary wording was corrected; current `docs/wallet_core_flutter_prd.md:206-209` matches Approach A.

**5. Rule 8 and Licensing**

Verdict: licensing is broadly correct; disclaimer coverage is incomplete in publishable metadata.

- MIT license present: `LICENSE:1-21`.
- Upstream Apache-2.0 notice/trademark separation present: `THIRD_PARTY_NOTICES.md:3-9`.
- No package names contain “trust”: `rg '^name: .*trust'` returned no hits.
- Exact disclaimer appears in `README.md:3`, `THIRD_PARTY_NOTICES.md:3`, `packages/wallet_core_flutter_native/README.md:3`, and package library doc comments.
- Pubspec package descriptions do not contain the exact disclaimer: `packages/wallet_core_flutter/pubspec.yaml:1-5`, `packages/wallet_core_flutter_bindings/pubspec.yaml:1-5`, `packages/wallet_core_flutter_native/pubspec.yaml:1-6`.
- Forbidden-word hits are mostly rule/meta/future/negative uses, not marketing claims. The noisy areas are archived docs and `docs/audit-resaults/wallet_core_flutter_architecture_audit.md:1-8`, which describes the project without the disclaimer.
- I found no AGPL legal claim; PRD references AGPL only as competitor/license context and explicitly forbids legal claims.

**6. CI and Release Engineering**

Verdict: CI enforces only part of the gate table; artifact publishing is overwrite-safe but not fully rerunnable under the same id.

Evidence summary:

- CI enforced today: bootstrap/analyze/format/test in `.github/workflows/ci.yml:21-55`; generated/fetch/gen:check/inventory/manifest in `.github/workflows/ci.yml:67-142`.
- CI placeholders only: Android/iOS simulator jobs at `.github/workflows/ci.yml:144-160`.
- Not enforced on `main`: `test:native`, `lint:public-api`, `lint:runtime-deps`, `vectors:validate`, real device jobs, and `tools/consumer_check.sh`.
- Actions billing currently blocks execution, so nothing is actually gate-green in GitHub for `672e09e`; this is recorded in dirty `PROGRESS.md:330`.
- Release flow refuses existing release tags at `.github/workflows/build-native.yml:156-162` and creates/uploads later at `.github/workflows/build-native.yml:520-532`. That protects immutability but means a failed draft release cannot be retried with the same artifact-set id.
- Protoc pinning evidence exists in `.github/workflows/ci.yml:98-122`; PROGRESS records Linux/mac generated success before billing blockage.

**7. Process Risks**

Verdict: the owner-authorization precedent is not recorded clearly enough for future implementers.

Evidence summary:

- Hard rule: `AGENTS.md:16` says do not run `git add`, `git commit`, or `git push`.
- Current plan: `docs/plan/EXECUTION_PLAN.md:171-200` says nobody but owner commits/tags/pushes.
- Local process note: `docs/plan/NEXT_STEPS.md:7-12` says “Commit locally, you push.”
- Actual W6 precedent: dirty `docs/plan/PROGRESS.md:330` records an agy merge/push under owner authorization.
- Misreported gates are not hypothetical: `docs/plan/PROGRESS.md:320-323` records agy reporting green gates while orchestrator reruns found analyze/format problems; `PROGRESS.md:330` records another gen:check hazard around missing `third_party/`. Mitigation is manual rerun by the orchestrator/reviewer, not CI.

**8. Phase 1 Closure**

Verdict: see section D.

**9. Misleading to a New Maintainer**

Verdict: yes. The main misleading areas are stale `PROGRESS.md`, contradictory commit authority, placeholder artifact identity that still validates structurally, partial CI described as gates, stale native build run wording, missing decided DECISION files, and incomplete disclaimer coverage in pubspec metadata.

C. Previous-Review Findings Ledger

| review | finding | status | evidence |
|---|---|---|---|
| W5-sdk | late reply can cross deadline | FIXED | W5 fixes log `docs/plan/reviews/W5-fixes-verification.md:16`; DECISION-12 deadline model `docs/decisions/DECISION-12.md:155` |
| W5-sdk | close during closing can force-kill session | FIXED | `docs/plan/reviews/W5-fixes-verification.md:17`; current shutdown ordering also touched by `ba83073` |
| W5-sdk | soft native failures end session | FIXED for Approach A / OPEN for Approach B eval | `docs/plan/reviews/W5-fixes-verification.md:18,38-42` |
| W5-sdk | secret-bearing message set too narrow | FIXED | `docs/decisions/DECISION-12.md:13,112-127,400-402` |
| W5-sdk | key field named/handled as key | FIXED | `docs/plan/reviews/W5-fixes-verification.md:20` |
| W5-sdk | public-surface lint weak | PARTIAL | tool exists, but CI lacks `lint:public-api`; `.github/workflows/ci.yml:21-160` |
| W5-sdk | entropy copies in Dart | FIXED for M0 / future isolate proof UNPROVEN | `docs/plan/reviews/W5-fixes-verification.md:22` |
| W5-sdk | `OperationCancelledError` unreachable | OPEN / deferred | `docs/plan/PROGRESS.md:339`; `docs/plan/NEXT_STEPS.md:12` |
| W5-sdk | tests cannot fail | FIXED | `docs/plan/reviews/W5-fixes-verification.md:23` |
| W5-sdk | doc slips | FIXED | `docs/plan/reviews/W5-fixes-verification.md:24`; commit `0ac87c7` |
| W5-sdk | `usedKeys` keeps wallet open | FIXED | `docs/plan/reviews/W5-fixes-verification.md:25` |
| W5-approach-b | append vs prepend | FIXED on eval branch | `docs/plan/reviews/W5-fixes-verification.md:26` |
| W5-approach-b | Approach A docs stale | FIXED | `docs/plan/reviews/W5-fixes-verification.md:27`; commit `0ac87c7` |
| W5-approach-b | copy counts unclear | FIXED | `docs/plan/reviews/W5-fixes-verification.md:28` |
| W5-approach-b | shim identity/out-dir guard | PARTIAL | `docs/plan/reviews/W5-fixes-verification.md:29,57-60` |
| W5-approach-b | iOS binding claim | FIXED | `docs/plan/reviews/W5-fixes-verification.md:30` |
| W5-approach-b | untyped key pointer | FIXED | `docs/plan/reviews/W5-fixes-verification.md:31` |
| W5-approach-b | missing tests | PARTIAL / OPEN | `docs/plan/reviews/W5-fixes-verification.md:32`; native/shim gates not CI-enforced |
| W5-packaging | Option 1 TOCTOU | OPEN | `docs/plan/reviews/W5-packaging.md:5-10`; DECISION-2 still open |
| W5-packaging | Option 2 shared iOS workdir | OPEN | `docs/plan/reviews/W5-packaging.md:12-18` |
| W5-packaging | classifier summary-only | OPEN | `docs/plan/reviews/W5-packaging.md:20-25` |
| W5-packaging | stale build outputs | OPEN | `docs/plan/reviews/W5-packaging.md:27-31` |
| W5-packaging | stale decision docs | OPEN | `docs/plan/reviews/W5-packaging.md:33-35` |
| W5-packaging | unpinned `android_libcpp_shared` | OPEN | `docs/plan/reviews/W5-packaging.md:37-41`; `docs/plan/NEXT_STEPS.md:96` |
| W5-packaging | Option 2 evidence hand-edited | OPEN | `docs/plan/reviews/W5-packaging.md:43-47` |
| W5-packaging | Flutter/Dart floor wrong | OPEN | `docs/plan/reviews/W5-packaging.md:49-52`; DECISION-6 open |
| W5-packaging | consumer app not pristine | OPEN | `docs/plan/reviews/W5-packaging.md:54-58` |
| W5-packaging | duplicate-symbol/offline/runtime gaps | OPEN | `docs/plan/reviews/W5-packaging.md:60-86` |
| W5-tools-docs | public API lint flaws | MOSTLY FIXED, CI OPEN | `tools/lint/lib/runtime_deps_check.dart:203-296`; `.github/workflows/ci.yml:21-160` |
| W5-tools-docs | memory/threat docs stale | FIXED | commit `0ac87c7`; current PRD `docs/wallet_core_flutter_prd.md:206-209` |
| W5-tools-docs | probe evidence provenance | FIXED / golden-test depth UNPROVEN | `docs/architecture/sign_json_coverage.md:5-8` |
| W5-landing-fable | threat model stale | FIXED | commit `0ac87c7` |
| W5-landing-fable | registry `.exe` tracked | FIXED | commit `24dca0c`; `git ls-files tools/gen/bin/registry_transform.exe` returned empty |
| W5-landing-fable | DECISION-12 four-payload language | FIXED | `docs/decisions/DECISION-12.md:112-127,400-402` |
| W5-landing-fable | eval/approach-b headerpad | OPEN | `eval/approach-b` only; DECISION-1 open |
| W5-landing-fable | ownership path/status misattribution | PARTIAL / OPEN | current `PROGRESS.md` dirty/stale |
| W5 codex debate | default init skips manifest hash | OPEN | `docs/plan/reviews/W5-landing-codex-debate.md:53-54`; `handler.dart:277-278` |
| W5 codex debate | placeholder artifact identity | OPEN | `compat_manifest.json:18-34,48-59` |
| W5 codex debate | PRD §11.4 stale | FIXED | commit `24dca0c`; `docs/wallet_core_flutter_prd.md:206-209` |
| W5 codex debate | tracked exe | FIXED | commit `24dca0c` |
| W5 codex debate | dirty worktree | FIXED then REOPENED | W5 committed; current `git status` dirty |
| W6-fable | `_states.close` unbounded | FIXED | commit `ba83073` |
| W6-fable | proto first rename masks EACCES | FIXED | commit `51d4c62`; `tools/gen/proto.sh:380-382` |
| W6-fable | proto staging same filesystem | FIXED | commit `51d4c62`; `tools/gen/proto.sh:132-137` |
| W6-fable | runtime deps hosted/overrides | FIXED | commit `1131dd5`; `tools/lint/lib/runtime_deps_check.dart:203-230` |
| W6-fable | allow-list branch untested | FIXED | `tools/lint/test/runtime_deps_test.dart:298-327` |
| W6-fable | symbol scan comments/strings | FIXED | `tools/lint/lib/runtime_deps_check.dart:250-296` |
| W6-fable | example failed-state trap | FIXED | commit `076d618` |
| W6-fable | PROGRESS glued/misattributed bullets | PARTIAL | local status still dirty/stale |
| W6-fable | consumer_check publish server lifecycle | OPEN / deferred T1.16b | `tools/consumer_check.sh:179-203` |
| phase-D codex debate | no artifact set / placeholders | OPEN | `compat_manifest.json:18-34` |
| phase-D codex debate | default manifest hash skipped | OPEN | `handler.dart:277-278` |
| phase-D codex debate | physical device evidence absent | OPEN | PRD `docs/wallet_core_flutter_prd.md:411-414`; world-state |
| phase-D codex debate | x86_64 runtime evidence absent | OPEN | `.github/workflows/build-native.yml:68-73`; world-state |
| phase-D codex debate | DECISION-2 rows unmeasured | OPEN | `docs/plan/PROGRESS.md:471` |
| phase-D codex debate | release-set comparison overclaim | OPEN | `docs/decisions/DECISION-14.md:79-88`; generated manifest placeholders |
| phase-D codex debate | Flutter/Dart minimum unproven | OPEN | `docs/plan/PROGRESS.md:475` |
| phase-D codex debate | stale native run comments | OPEN | `tools/native_build/README.md:177-188` |

D. Phase-1 Closure List
1. OWNER/CI: Fix GitHub Actions billing and rerun CI on `672e09e` so at least configured CI jobs actually execute.

2. CI: Run `build-native.yml` for `as_4.8.0_001`; produce draft release assets, SHA256SUMS, export checks, alignment checks, and Apple/Android archives.

3. AGENT: Replace `compat_manifest.json` placeholders with real artifact records, remove or build the unverified `armeabi-v7a` row, run manifest generation and validation.

4. AGENT: Make default native initialization perform the DECISION-14 manifest-hash comparison, or amend the decision/status to stop claiming it.

5. DEVICE/AGENT: Rerun DECISION-2 packaging evidence on real artifacts: Android arm64 emulator, Android x86_64 emulator if x86_64 ships, iOS simulator, 16KB packaging, libc++ conflict fixture, checksum/offline/hosted dependency cases.

6. OWNER/AGENT: Complete D1a and record DECISION-2, DECISION-6, and DECISION-14 ratification, including `-DFLUTTER=ON`, JNI allow-list, ABI set, and libc++ policy.

7. AGENT: Merge the chosen packaging path to `main` and finish T1.16b consumer checks against a hosted/path-independent dependency flow.

8. AGENT/CI/DEVICE: Enforce or explicitly classify remaining gates: `test:native`, `lint:public-api`, `lint:runtime-deps`, `vectors:validate`, Android emulator, iOS simulator, runtime no-network, and identity mismatch.

9. DEVICE/OWNER: Provide physical Android and iOS debug/release evidence, or explicitly amend M0 exit criteria.

10. OWNER: Run D1 for DECISION-1 and M0 closure, then tag `phase-1-closed` only after the status source is clean and all blocking review findings are closed or consciously deferred.

E. Trustworthiness
The project’s self-reporting is useful but not trustworthy without verification: it contains a lot of honest caveats, but the authoritative status file is stale, locally dirty, and contradicted by git history, while several “decision” and “gate” claims are ahead of the evidence. The single process change that would most improve it is this: require every merge/push/status change to land with a clean, committed `PROGRESS.md` update that names the exact commit, CI run, gates actually executed, and any owner-authorized exception before the work is considered reportable.