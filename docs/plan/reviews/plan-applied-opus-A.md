# Opus 5.5 audit A — was NEXT_STEPS.md applied, and does PROGRESS.md tell the truth? (`main` 672e09e, 2026-10-04, read-only)

Brief: `docs/plan/briefs/REVIEW-plan-applied-A.md`. Report verbatim below; orchestrator triage in `PROGRESS.md`.

---

**Short answer:** Phases A and B were applied as written. Phase C stopped partway, and the cause is external: GitHub billing. Phase D has only been partly pre-built. Every gate re-run on `main` (`672e09e`) passed, and all dispatch run IDs and log quotes spot-checked in PROGRESS are accurate. The status sections of PROGRESS.md and the NEXT_STEPS banner are stale, and the line the orchestrator added during the audit cites the wrong CI run id.

## A. Verdict table

| Step | Verdict | Evidence |
|---|---|---|
| A1 | DONE | PROGRESS.md:294-298 records the four decisions; :295 the new commit boundary |
| A2 | DONE | `6d894ff` (2026-10-03 06:13:20). DECISION-12.md:13, :112, §3.5 :153-165, trigger 6 :374-376, Amendment :396. lifecycle.md:361-363, :435. protocol.dart declares 13 requests and 14 replies. PRD §11.4 wording applied later in `24dca0c` (PRD:208-209) |
| A3 | DONE | tools/probes/pubspec.yaml `crypto: ^3.0.7`; folded into the T1.14 commit `42fea90` |
| B1 | DONE | `integration/W2` `54d08b2` on `1d70c6c`: exactly `ci.yml` and `registry_transform_test.dart` |
| B2 | DONE | `integration/W3` `6f7b520` (145 files); worktree clean |
| B3 | DONE | `task/T1.11` `59e2f3a` on `6f7b520`; no path outside the allowed set |
| B4 | DONE | `task/T1.12` `6d894ff` on `59e2f3a`; also contains `docs/security/threat_model.md` (LAND_W5.md:32 allows it because of A2) |
| B5 | DONE | `eval/approach-b` `333eb51` on `6d894ff` |
| B6 | DONE | `task/T1.14` `42fea90` on `6f7b520` |
| B7 | DONE | `task/T1.15` `8eab40e` on `59e2f3a` |
| B8 | DONE | `task/T1.18` `d04f621` on `59e2f3a`; 3 files |
| B9 | DONE | `eval/option1` `e7bea5d` on `6f7b520`, plus `f53bd6b` (T1.2-d1 note) |
| B10 | DONE | `eval/option2` `1877067` on `6f7b520` |
| B11 | DONE | `integration/W5` `5e96a36` = `6d894ff` + `127664d` (T1.14) + `2622c40` (T1.15) + `5e96a36` (T1.18). `test:native` survives at pubspec.yaml:139 |
| B12 | DONE (corroborated) | CI 37148298949 on `24dca0c` passed gates and generated-code jobs; reviews/W5-landing-fable.md:44, :100 reproduce SDK 270, native 42 + 74, lint 49/0 |
| B13 | DONE (inferred) | Every commit's path set inside its allowed set. The step-5 stop is UNPROVEN beyond the resume brief `LAND_W5-d1.md` |
| push list | DONE | `git ls-remote origin` shows all 11 at the listed hashes |
| C1 | DONE | `main` `99137b9` = `--no-ff` merge of `24dca0c`, pushed. CI 37148705952 passed. Flutter pin 3.47.5 at ci.yml:31, :77 (`24dca0c`) |
| C2 | BLOCKED (external), PARTIAL | 10 dispatches (37148717861 … 37188376458), 7 executed; Apple passed 6 times. Run 37158147404: Android "expected 464, missing 0, unexpected 4". Its fix `de3fe4c` has never run (37160894675, 37165166476, 37188376458 not started: billing) |
| C3 | NOT DONE (blocked by C2) | `gh release list` empty. compat_manifest.json:20-50 holds 11 `TBD-T1.2` placeholders; generated/manifest.dart:36 `identityArtifactSetId = 'TBD-T1.2'` |
| known fix | DONE | `b07f593`: build_apple.sh:370 `-Wl,-headerpad_max_install_names`; on `main`, every later Apple job ran on top of it |
| D1 | NOT DONE (blocked by C) | Setup only: AVD `~/.android/avd/wcf_api35.avd`, system image 3.8 GB |
| D2 | NOT DONE | No DECISION-2 / DECISION-6 record; neither eval branch merged |
| D3 | PARTIAL | see D3/D4 table |
| D4 | PARTIAL | see D3/D4 table |
| D5 | PARTIAL / pre-work only | reviews/W6-fable.md reviewed the pre-built halves |
| D6 | NOT DONE | No `docs/decisions/DECISION-1.md` |
| D7 | NOT DONE | No tags on origin |
| E | NOT DONE (correctly) | Gated on `phase-1-closed` |

**Phase C fixes on `main`:** `-DFLUTTER=ON` build_android.sh:367-369 · `--allow-extra` ×4 build_android.sh:441-444, check_exports.sh:84 · `--dynamic` for ELF check_exports.sh:139 · `BOOST_ROOT` build_android.sh:309-314 · `yes | sdkmanager --licenses` build-native.yml:313-319 · `xcode_version` default `'26.3.0'` build-native.yml:81 · headerpad build_apple.sh:370 · all `.sh` mode 100755.

**D3/D4 cells on `main`:**

| Cell | State | Evidence |
|---|---|---|
| D3 example app, M0 flow on the public surface | Delivered | example/lib/{main.dart, src/m0_flow.dart, src/m0_page.dart}; 6 tests |
| D3 leak-tracker report shown | Not delivered | m0_flow.dart:512: not on the public surface |
| D3 fresh `flutter create` | Delivered | consumer_check.sh:154 |
| D3 hosted dependencies via loopback repository | Partial | `publish_locally` passes (:185-194); `add_dependency` exits 2 (:197-204) |
| D3 debug and release builds, both platforms | Not delivered | :206-220 exit 2 "waiting for DECISION-2" |
| D3 M0 on emulator and simulator | Not delivered | `run_m0_flow` (:222-227) waits; no `integration_test/` |
| D4 CI device jobs | Not delivered | ci.yml:144-162 placeholders, `workflow_dispatch` only |
| D4 no-network runtime test | Not delivered | static scan only |
| D4 `runtime_deps_check.dart` | Delivered, not in CI | tools/lint/bin/runtime_deps_check.dart |
| D4 identity-mismatch negative test | Partial | session_native_test.dart:118-140 uses an `expectedIdentity` override, not a manifest; not in CI |
| D4 gates in CI | Partial | `gen:check` (ci.yml:135), `manifest:validate` (:141) run; `lint:public-api`, `vectors:validate`, `lint:runtime-deps`, `test:native` do not |
| D4 Dependabot `pub` | Delivered | dependabot.yml:9-19; pub-workspace handling UNPROVEN |
| D4 Flutter 3.47.5 | Delivered | via W5-prepush (`24dca0c`) |

## B. Gate results on `main` (`672e09e`)

Flutter 3.47.5, Dart 3.13.4, melos 8.6.0; `third_party/` present.

| Gate | Exit | Counts |
|---|---|---|
| bootstrap | 0 | 12 packages |
| analyze | 0 | 12/12 no issues |
| format:check | 0 | 459 files, 0 changed |
| test | 0 | SDK 277, native 190, bindings 64, lint 61, packaging_eval 178, upstream 109, manifest 67, inventory 29, vectors 20, probes 4, gen 3 — total 1002, none skipped |
| test:native | 0 | 42 + 74 |
| inventory:check | 0 | functions 466/466, enums 19/19, 464 TW* |
| gen:check | 0 | no diff, no untracked generated files |
| lint:public-api | 0 | 49 elements, 0 violations |
| lint:runtime-deps | 0 | 3/3 OK; 5 hits in native `tool/` allowed as build-time |
| vectors:validate | 0 | 2 files, 5 vectors, 0 exclusions |
| manifest:validate | 0 | valid (still accepts TBD placeholders) |
| example (outside melos) | 0 / 0 | analyze clean; 6 tests incl. 1 native |

**probe:sign-json:** twice via melos, exit 0, byte-identical; it rewrites the tracked `docs/decisions/evidence/sign_json_coverage.md` with identical bytes (blob `f02aff7`; 106 supported / 61 not / 167). With `--out` to a scratchpad: p1 = p2.

**git status before and after gates identical** (only the orchestrator's ` M docs/plan/PROGRESS.md` and the untracked briefs). All 16 worktrees checked are clean.

## C. PROGRESS.md claims checked

| Claim | Verdict | Evidence |
|---|---|---|
| A2 landed in `6d894ff` at 06:13 (:302) | TRUE | 06:13:20 +0300 |
| 13 requests and 14 replies | TRUE | protocol.dart |
| LAND_W5 hashes, "06:10–06:17" (:305) | TRUE | 06:12:33–06:17:36 |
| T1.2-d1 `b07f593` 06:27; eval/option1 `f53bd6b` (:307) | TRUE | git log |
| 11 branches pushed at listed hashes (:313) | TRUE | ls-remote |
| W5 CI 37148298949 green; 9 branches fail format:check only (:313-314) | TRUE | first failing step is `melos run format:check` |
| `main` `99137b9`; CI 37148705952 green (:316-317) | TRUE | gh run view |
| Dispatch chain causes and IDs (:316) | TRUE | logs match |
| Billing probe "at ~03:45 local", run 37165166476 (:324) | FALSE (time) | created 00:30:35Z = 03:30 +0300 |
| "62a6966 (not pushed)" (:324) | STALE | origin/main = `672e09e` contains it |
| W6 "Not pushed, not merged into main" (:327) | STALE | `672e09e` on origin |
| T1.11-d1: message says five tests, it is four; SDK 274 (:326) | TRUE | `98fcef2` |
| T1.16 `08dced3`, 76 files (:322) | TRUE | git show --stat |
| SDK 277, lint 61, native 42 + 74, 49/0, example 6, analyze 12/12 (:329) | TRUE | re-run |
| `.exe` removed and ignored; ci.yml 3.47.5 ×2 (:313) | TRUE | `24dca0c`; .gitignore:30-32 |
| AVD wcf_api35, 3.8 GB, Xcode 27.0, booted iPhone 16 Pro | TRUE | host check |
| Task table: T1.11/12/14/15/18 "uncommitted"; T1.16/T1.17 "queued" (:78-85) | STALE | all on `main` |
| Concurrency: "W3 uncommitted", "two W2 fixes uncommitted", "No session commits" (:25-44) | STALE | `6f7b520`, `54d08b2` |
| "Yours to decide" items 1 and 3 (:336, :338) | STALE | decided at :296, :298 |
| NEXT_STEPS.md:31 banner | STALE | W5 at `24dca0c`; agy executed Phase C |
| Uncommitted: "CI run 37188808655 on `672e09e`" | FALSE | 37188808655 is the Dependabot push run (`a224141`); the `main` run is 37188768594 |
| Uncommitted: dispatch 8′ = 37188376458 not started (billing) | TRUE | gh run view |
| Uncommitted: W6 merge authorized by "Go" 2026-10-04 | UNPROVEN | only in untracked briefs |
| DISPATCH-008: owner said "Go" after fixing billing | effect FALSE | 08:16Z and 08:23Z runs still billing-blocked |
| A2 "~630k tokens"; A3 "format 324/0" | UNPROVEN | no artifact |

## D. Findings

1. **should-fix**, PROGRESS.md:69-85: the task table is stale. Update T1.11/12/14/15/18 to landed on `main` `99137b9`; T1.16 half a (`08dced3`/`076d618`) and T1.17 pre (`7286706`/`1131dd5`) in `672e09e`; add T1.2-d1 (`b07f593`) and the six build fixes `326823d`…`de3fe4c` to T1.2.
2. **should-fix**, PROGRESS.md:25-44 (Concurrency) and :335-341 ("Yours to decide"): pre-2026-10-03 state; rewrite or mark superseded.
3. **should-fix**, NEXT_STEPS.md:31 banner stale.
4. **should-fix**, PROGRESS.md:324, :327 and the uncommitted line: run id 37188808655 → 37188768594 (`gh run rerun 37188768594`); "~03:45" → 03:30.
5. **should-fix (blocks Phase 1 close)**: comparison 2 skipped on the default path (wallet_core.dart:44-47, handler.dart:277-278); leak-tracker report not public (m0_flow.dart:512); EVM vector not reproducible byte-for-byte from the public surface. Each needs an owner decision or a task.
6. **should-fix**, ci.yml:44-51, :135-142: CI runs neither `lint:public-api`, `vectors:validate`, `lint:runtime-deps`, `test:native`, nor example analyze/test; `example/` not in the workspace list. T1.17 scope.
7. **should-fix**, build-native.yml:38 ("NOT YET RUN") and build_android.sh:35 ("UNRUN") are false after 7 executed runs; steps after the export gate have never executed.
8. **nit**, `672e09e` message credits consumer_check workspace membership to T1.17-pre; it was T1.16a-d2 (`076d618`); T1.17-d2 was the lock-source check (`1131dd5`).
9. **nit**, rule 9: W6 added `yaml: ^3.1.2` (tools/lint, `7286706`) and `flutter_lints: ^6.0.0` (example, `08dced3`), not recorded in PROGRESS.
10. **nit**, `third_party/wcf-native-all` holds a local `as_4.8.0_000` Apple-only set while PROGRESS reserves the name for the downloaded `as_4.8.0_001`.
11. **nit**, packaging metadata: pubspec descriptions lack the disclaimer; `wallet_core_flutter` and the bindings package have no README.
12. **nit**, AGENTS.md: rule 10 still bans add/commit/push for all sessions though the owner amended the boundary; gate table lacks `inventory:check` and `probe:sign-json`.
13. **nit**, `probe:sign-json` rewrites a tracked file by default; use `--out` as a read-only gate.
14. **info**: Dependabot PRs #1–#3 open (download-artifact v8, setup-java v6, upload-artifact v7), all editing build-native.yml; do not merge before a green artifact set.

## E. Rule-8 sweep and disclaimer presence

Every hit compliant: rule statements (AGENTS.md:14, EXECUTION_PLAN.md:117), the `reproducible_build_verified: false` schema key, PRD requirement text, archived PRD v1.1 (history), process notes in PROGRESS, T4.4 future-work references, tools/native_build/README.md:143 "**not** reproducible". Only 3 matching lines added since `1f0ad2f`, all in these categories.

| Location | Disclaimer |
|---|---|
| README.md | yes :3 |
| example/README.md, example/pubspec.yaml description, example/lib/main.dart | yes |
| packages/wallet_core_flutter: README / pubspec / library | no README / no / yes (wallet_core_flutter.dart:3-4, advanced.dart:5-6) |
| packages/wallet_core_flutter_bindings: README / pubspec / library | no README / no / yes |
| packages/wallet_core_flutter_native: README / pubspec / library | yes / no / yes |
| tools/consumer_check.sh, docs/security/{memory_contract,lifecycle}.md, NEXT_STEPS.md | yes |

## F. Readiness for D1

**Yes, conditionally.** Build fixes on `main`, both eval branches pushed, AVD exists, every gate passes. The single blocker is that no artifact set exists: every attempt since 02:10 local on 2026-10-04 has been refused by GitHub billing, including 37188376458 and 37188768594 after the reported "Go". When a run is allowed, the steps after the export gate (16 KB alignment, records, assemble, draft release) run for the first time, and P0 must land before `initialize()` can succeed.

Only the owner can unblock: (1) billing / spending limit (or make the repo public), then re-dispatch `as_4.8.0_001` and `gh run rerun 37188768594`; (2) Dependabot PRs #1–#3; (3) confirm the 2026-10-04 "Go" for the W6 merge in a committed record; (4) D1a: DECISION-2, -6, -14 incl. `-DFLUTTER=ON`, JNI allowlist, `libc++_shared`; (5) comparison-2 design on the default path; (6) physical-device evidence or an explicit M0 amendment; (7) reconcile AGENTS.md rule 10 with the amended boundary; (8) the `phase-1-closed` tag.
