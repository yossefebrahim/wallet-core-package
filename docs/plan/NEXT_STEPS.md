# Next steps after the wave-5 review pass (written 2026-10-03)

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

This is a plan, not a status page; status stays in [`PROGRESS.md`](PROGRESS.md). It sequences everything between "all wave-5 work accepted, nothing committed" and "Phase 1 closed, Phase 2 open", with the four decisions you took on 2026-10-03 folded in:

| Decision | Your answer | Consequence in this plan |
|---|---|---|
| Commit boundary | **Commit locally, you push** | agy executes commit briefs (`LAND_*`); no session ever runs `git push`, `git tag`, or dispatches a workflow |
| DECISION-12 §3.2 (secret-bearing payloads 4 → 8) | **Amend** | step A2 |
| Option 1 `libc++_shared.so` without a pinned digest | **Wait for the Android build**, decide at D1a | stays an open item in `DECISION-2-option1.md` §5.1 |
| `OperationCancelledError` without a cancel API | **Defer to Phase 2** | T2.1 adds cancel-before-start; note added to the T2.1 brief when it is written |

Where the trees stand (verified by file diff, 2026-10-03):

| Worktree | Branch | Contents on top of `integration/W3` (`1d70c6c`) | Base to commit on |
|---|---|---|---|
| `W2-integration` | `integration/W2` | two CI inline fixes (`ci.yml`, `registry_transform_test.dart`), also present in W3 | `integration/W2` |
| `W3-integration` | `integration/W3` | wave 3 (T1.6, T1.7, T1.19), FMT-3.13 reformat, the two W2 fixes — 37 entries | `integration/W3` |
| `T1.11` | `task/T1.11` | W3 + T1.11a/b | committed `integration/W3` |
| `T1.12` | `task/T1.12` | T1.11 + T1.12a/b + review fixes (touch T1.11 files) | committed `task/T1.11` |
| `T1.13` | `eval/approach-b` | T1.12 + Approach B + seam change | committed `task/T1.12` |
| `T1.14` | `task/T1.14` | W3 + probe (root `pubspec.yaml` lacks T1.11b's `test:native` script) | committed `integration/W3` |
| `T1.15` | `task/T1.15` | T1.11 + lint | committed `task/T1.11` |
| `T1.18` | `task/T1.18` | T1.11 + docs | committed `task/T1.11` |
| `T1.8` | `task/T1.8` | W3 + Option 1 (eval) | committed `integration/W3` |
| `T1.9` | `task/T1.9` | W3 + Option 2 (eval) | committed `integration/W3` |

---

> **Executed 2026-10-03:** Phases A and B are done (plus T1.2-d1 pulled forward from Phase C); `integration/W5` is at `b07f593`, gate-green, reviewed (`reviews/W5-landing-fable.md`) — details and the push list in `PROGRESS.md`. Phase C onward is still yours.

## Phase A — record and amend (orchestrator + one small Opus task, ~1 hour, no device)

**A1. PROGRESS.md** — record the four decisions above with the date, and the commit-boundary change ("agy commits locally on LAND briefs; push, tag, workflow dispatch remain yours").

**A2. Amend DECISION-12 and lifecycle.md** (Opus 5.5, high, in the `T1.12` tree; brief `DEC-12-amend.md`):
- `docs/decisions/DECISION-12.md` §3.2: the secret-bearing payload set becomes eight — requests `CreateWallet`, `ImportWallet`, `ImportKey` (planned), `ValidateMnemonic`, `ValidateMnemonicWord`, `SuggestMnemonicWords`; replies `MnemonicExported`, `MnemonicWordsSuggested` (four additions to the original four) —, with the same handling rules; §3.2 also stops listing timeouts in `Init` and records the per-request `OperationDeadline` (what it is, monotonic clock, dropped-not-posted rule, what T2.1's envelope must carry); §8 trigger 6 records this reopening with the date.
- `docs/architecture/lifecycle.md` §6: message counts (now `Sign`/`Signed` too), the eight payloads, the deadline.
- Acceptance: every statement cites the code; forbidden-word grep empty; `melos run format:check`.
- Also fold in: `docs/wallet_core_flutter_prd.md` §11.4 describes Approach A's Dart-side copies as "protobuf message field, serialized bytes" — the code has neither. PRD edits are yours; the brief produces the proposed wording as a diff in the report, not an edit.

**A3. Small leftovers** (agy, one brief): `tools/probes/pubspec.yaml` pin `crypto` to the resolved version instead of `any`; nothing else.

## Phase B — commit locally (agy LAND brief, you push; ~2 hours including gate runs)

One brief, `LAND_W5.md`, executed by agy with `--dangerously-skip-permissions`, strictly in this order, with `git status --short` pasted before and after each step and **no push, no tag, no branch deletion, no `--force`**:

1. `W2-integration`: `git add` the two files, commit on `integration/W2` ("ci: install protoc 33.4 + protoc_plugin 25.0.0 in the generated job; registry test skips without upstream tree").
2. `W3-integration`: `git add -A` (the `.gitignore` already excludes `third_party/`, `build/`, `.dart_tool/`), commit on `integration/W3` ("integration/W3: T1.6 memory layer, T1.7 native loader, T1.19 packaging harness, 3.13 reformat"). Verify `git status --short` is empty afterwards.
3. `T1.11`: `git checkout -B task/T1.11 integration/W3` (the working tree already contains W3's content, so only T1.11's files remain modified); confirm `git status --short` lists only `packages/wallet_core_flutter/**`, `packages/wallet_core_flutter_bindings/{ffigen.yaml,lib/registry.dart,lib/src/generated/ffi/**}`, root `pubspec.yaml`, `pubspec.lock`, `tools/native_build/run_native_tests.sh`; commit ("T1.11: SDK core — session, engine, proxies, facades").
4. `T1.12`: `git checkout -B task/T1.12 task/T1.11`; status must list only `packages/wallet_core_flutter/**` and `docs/decisions/DECISION-1-approach-a.md` (+ `DECISION-12.md`, `lifecycle.md` after A2); commit ("T1.12: EVM request, key-less encoder, Approach A signing, wave-5 review fixes").
5. `T1.13`: `git checkout -B eval/approach-b task/T1.12`; status must list only `packages/wallet_core_flutter_native/src/shim/**`, `tools/native_build/**`, `packages/wallet_core_flutter/**`, `docs/decisions/DECISION-1-approach-{a,b}.md`; commit ("T1.13 (eval): Approach B adapter prototype, host scope").
6. `T1.14`: `git checkout -B task/T1.14 integration/W3`; status: `tools/probes/**`, `docs/decisions/evidence/sign_json_coverage.md`, root `pubspec.yaml`, `pubspec.lock`; commit.
7. `T1.15`: `git checkout -B task/T1.15 task/T1.11`; status: `tools/lint/**`, root `pubspec.yaml`, `pubspec.lock`; commit.
8. `T1.18`: `git checkout -B task/T1.18 task/T1.11`; status: `docs/security/{memory_contract,lifecycle}.md`, `README.md`; commit.
9. `T1.8`: `git checkout -B eval/option1 integration/W3` (the plan names the eval branch so; `task/T1.8` stays as is); status: `packages/wallet_core_flutter_native/{hook/**,lib/src/code_asset_locations.dart,lib/wallet_core_flutter_native.dart,pubspec.yaml,test/**}`, `eval/option1/**`, `docs/decisions/DECISION-2-option1.md`, `pubspec.lock`; commit.
10. `T1.9`: `git checkout -B eval/option2 integration/W3`; status: `packages/wallet_core_flutter_native/{android/**,ios/**,tool/**,analysis_options.yaml,pubspec.yaml,test/**}`, `eval/option2/**`, `docs/decisions/DECISION-2-option2.md`; commit.
11. **Integration branch:** in a new worktree `W5-integration`, `git checkout -b integration/W5 task/T1.12`, then `git merge --no-ff task/T1.14 task/T1.15 task/T1.18` one at a time. Expected conflicts: root `pubspec.yaml` only (`workspace:` list and `melos: scripts:` appends from T1.14 and T1.15; T1.14's copy lacks T1.11b's `test:native` — keep both). Resolve, commit the merges.
12. **Gates on `integration/W5`** (orchestrator-run, unsandboxed): `melos bootstrap`, `analyze`, `format:check`, `test`, `test:native`, `inventory:check`, `gen:check`, `lint:public-api`, `vectors:validate`, `manifest:validate`, `probe:sign-json` (byte-identical). Expected: all green; SDK 270 tests, native 42 + 74, lint 0 violations over 49 elements.
13. Any step whose `git status` shows a path outside the listed set **stops the brief** and reports; nothing is committed for that step.

**Then you push** — suggested: `integration/W2`, `integration/W3`, `task/T1.11`, `task/T1.12`, `task/T1.14`, `task/T1.15`, `task/T1.18`, `integration/W5`, `eval/approach-b`, `eval/option1`, `eval/option2`. CI runs on each; `integration/W5` is the one that matters (its `generated` job answers the Linux-vs-macOS byte-identity question that has been open since 2026-09-08).

## Phase C — get the native artifacts (you, ~15 minutes of your time; CI ~30–60 minutes)

`build-native.yml` exists only on the integration branches, so:

1. Merge `integration/W5` into `main` (fast-forward or merge commit, your call) and push `main`. Before that, decide whether the two CI inline fixes and the Flutter pin belong in the same push: `ci.yml` still pins Flutter 3.44.1 while the host is on 3.47.5 — T1.17 owns the CI file, so either leave it (3.44.1 still builds the packages; only the Xcode-27 template issue was 3.44-specific) or ask for a one-line bump brief first.
2. Dispatch `build-native.yml` with `upstream_tag=4.8.0`, `artifact_set_id=as_4.8.0_001`, draft release. It builds Android `arm64-v8a` and `x86_64` from the pinned commit (NDK r27+, cmake, Rust in CI — none of which this Mac has) and relays the Apple slices with the identity object.
3. When it is green: paste the run URL into `PROGRESS.md` (or tell the orchestrator); the orchestrator then runs `tools/manifest` to fill `compat_manifest.json`'s `artifacts`/`toolchain`/`identity` from the workflow output, runs `gen:manifest`, and the manifest's `TBD-T1.2` placeholders disappear — at which point `initialize()` succeeds against a published set for the first time.

**Known fix to fold into the same release:** link every Apple artifact with `-Wl,-headerpad_max_install_names` (T1.2, `tools/native_build/build_apple.sh`) — the only remaining `fail` row in the Option 1 evaluation is the 87-character install-name limit it causes. Do it before dispatching, or plan a second set `as_4.8.0_002`. Brief `T1.2-d1.md` (Opus, S) can land on `integration/W5` before the push.

## Phase D — finish Phase 1 (after the artifacts exist; orchestrator + agents; device-gated)

| Step | Who | Needs | Produces |
|---|---|---|---|
| **D1. Android rows** — T1.8b and T1.9b: run both eval scripts with an Android emulator booted (`x86_64`, API 34+) and the `as_4.8.0_001` set; 16 KB alignment, `libc++_shared` fixture, APK size deltas, offline install | orchestrator runs the scripts; Opus deltas fix what breaks | C | both decision tables complete; the `libc++_shared` question answered with data |
| **D2. D1a checkpoint debate** — DECISION-2 (packaging option), DECISION-6 (minimum Flutter/Dart), DECISION-14 ratification | codex (read-only debate), your decision | D1 | DECISION-2/-6 recorded; winner's branch (`eval/option1` or `eval/option2`) merged onto `integration/W5` — rework task `T1.R1` if the merge needs work |
| **D3. T1.16** — example app + `tools/consumer_check.sh` (fresh `flutter create`, hosted dependencies via the T1.19 loopback repository, debug + release on both platforms, M0 flow on emulator and simulator) | Opus 5.5 (M), orchestrator runs devices | D2, T1.12 | `example/`, `consumer_check.sh`; PRD §12.2 step 11 evidence |
| **D4. T1.17** — CI device jobs, no-network runtime test, `runtime_deps_check.dart`, identity-mismatch negative test, `lint:public-api` + `gen:check` + `vectors:validate` + `manifest:validate` in CI, dependabot `pub`, Flutter pin to 3.47.5 | Opus 5.5 (L, halves a/b) | D3, T1.15 | `.github/workflows/ci.yml`, `integration_test/`, `tools/lint/runtime_deps_check.dart` — first live run needs your push |
| **D5. Ultracode review** of D3 + D4 and the D1a merge | two Opus 5.5 reviewers | D4 | fix deltas, same loop as wave 5 |
| **D6. D1 phase debate** — DECISION-1 (Approach A vs B vs "A now, B later"), M0 exit criteria item by item, ratification of DECISION-5/8/9/11–14 | codex debate, your decision | D5 | `docs/decisions/DECISION-1.md`; triage list |
| **D7. Triage and rework**, then **you tag `phase-1-closed`** | Opus deltas; you | D6 | Phase 1 closed in `PROGRESS.md` |

Inputs already on file for D6: `DECISION-1-approach-a.md` (0 Dart-heap key copies, 4 native objects), `DECISION-1-approach-b.md` (3 native objects, +384 B, one C file, same residual upstream copies), `sign_json_coverage.md` (106/167; Ethereum yes, Bitcoin no, JSON path returns no v/r/s), the five review reports under `docs/plan/reviews/`.

## Phase E — Phase 2 opens (after the tag)

From `docs/plan/EXECUTION_PLAN.md`: T2.0 signing model in code (already largely built by T1.12 — the brief becomes a gap list), **T2.1 worker isolate transport** (carry `OperationDeadline` in the envelope; add public cancel-before-start and make `OperationCancelledError` reachable; confirm `Timeline.now` across isolates in AOT; the sender-side entropy overwrite after `send`), T2.5 UTXO (`Signer.plan`, repeated key field → one locator per input), T2.6 Solana (three key fields, the nested `nonce_account_private_key` needs the whole sub-message re-sent, measured), T2.7 EVM messages (`MessageRequest`, `signMessage`), T2.12 hostile-input suite (seed it with the review probes: truncated input, planted key field, group-wrapped field, near-max timeout).

## Open items carried, none blocking

- Lint rules: `Future<void> dispose()` is reported by `sync-dispose`; private static `Pointer` fields are not reported. Decide at D6 or leave.
- `DECISION-2-option1.md` §5.1: `libc++_shared` — decided to wait (above).
- Two shim builds from the same inputs differ byte-wise; the identity object is compiled with `-g` and carries paths. Matters for PRD §12.4 (T4.4), not now.
- Flutter 3.47.5 rewrites a plugin package's `analysis_options.yaml` on `flutter pub get` (adds `build/**`, `android/**`, `ios/**` excludes). Worth an upstream issue; nothing for us to do beyond keeping build-time Dart out of those directories.
- Upstream 4.8.0: `~HDWallet` leaves `entropy` unwiped; the Rust signing path frees the keyed input unwiped. Candidates for an upstream report after Phase 1; the memory contract already states both.
- Session scratchpad was wiped once mid-session; relay artifacts for waves 3–4 are gone. Reviews and reports from wave 5 are copied under `docs/plan/reviews/`, so nothing needed is only in the scratchpad any more.

## Suggested order for you right now

1. Read this plan; say "go" for Phase A + B. The orchestrator dispatches A2/A3, then the `LAND_W5` brief, then runs the gates on `integration/W5` and reports the branch list to push.
2. Push; wait for CI; merge `integration/W5` to `main`; push; dispatch `build-native.yml`.
3. Tell the orchestrator the run URL. Phase D starts with the Android rows.
