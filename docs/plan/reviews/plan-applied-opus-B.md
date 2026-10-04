# Opus 5.5 audit B — Phase 1 (M0) status on `main` 672e09e (2026-10-04, read-only)

Brief: `docs/plan/briefs/REVIEW-plan-applied-B.md`. Report verbatim below; orchestrator triage in `PROGRESS.md`.

---

**Scope and method.** No edits and no git writes. Unmerged branches inspected with `git show` and `git diff main...<branch>`; the three eval branches were exported with `git archive` into a scratchpad (outside the repo) only to run their tests. Every test count comes from the reviewer's own `dart test -r json` / `flutter test -r json` runs, one package at a time; all passed with 0 failures, native-tagged tests ran because `third_party/wcf-native/macos/arm64_x86_64/libTrustWalletCore.dylib` is present.

## A. Task table T1.1–T1.19 (and deltas)

| Task | Verdict | Where | Deliverables present | Tests (measured) |
|---|---|---|---|---|
| T1.1 | ON MAIN | main (via integration/W1; `task/T1.1` 065ba34 is not an ancestor, but its content is on main) | `tools/upstream/`, `THIRD_PARTY_NOTICES.md`, manifest `upstream.commit` = `d692ac27…` | tools/upstream 109 |
| T1.2 | ON MAIN as authored; **BLOCKED** | main | `.github/workflows/build-native.yml`, `tools/native_build/*` (8 files), `src/identity/wcf_build_info.{c,h}`. **Not produced:** no release exists (`gh release list` empty). `compat_manifest.json` `artifacts[*].sha256`, `identity.artifact_set_id`, `toolchain.*` all `TBD-T1.2`; `validate.dart --strict` reports 12 placeholders. Apple job succeeded; last Android run (37158147404) failed the export gate; later dispatches never started (billing) | shell gates only |
| T1.3 | ON MAIN | main | `ffigen.yaml`, `generated/ffi/*`, `generated/inventory.json`, `tools/inventory/`. `inventory:check` re-run: 466 bound / 464 TW*, up to date. `gen:check` green in CI run 37158120282 at 44532eb | tools/inventory 29 |
| T1.4 (+d1, d2) | ON MAIN | main | `generated/proto/**`, `key_fields.json`, `tools/gen/proto.sh` (staging/swap from 51d4c62) | bindings key_fields 10, proto_round_trip 4 |
| T1.5 | ON MAIN | main | `tools/gen/lib/registry_transform.dart`, `generated/registry/{coin_type,coin_info}.dart` | tools/gen 3 |
| T1.6 | ON MAIN | main | `bindings/lib/src/memory/*` (9 files) | bindings 64, native-tagged 42. The release-mode inertness proof it defers to T1.17 is **NOT DONE** |
| T1.7 | ON MAIN | main | `native/lib/src/{loader,verify_identity,build_identity,library_location,errors}.dart`, `native/tool/fetch_artifacts.dart` + `tool/src/*` | native 190 |
| T1.8 (half a) | ON BRANCH ONLY: `eval/option1` f53bd6b | branch | `native/hook/**`, `eval/option1/**`, `DECISION-2-option1.md`. Every Android column `unmeasured`; iOS simulator debug `pass ran`; iOS device `unmeasured` | native on branch 280 (hook 55, eval_option1 35) |
| T1.8 (half b) | NOT DONE | — | needs Android artifacts and a device | — |
| T1.9 (half a) | ON BRANCH ONLY: `eval/option2` 1877067 | branch | `native/{android,ios}/**`, `native/tool/option2/**`, `eval/option2/**`, `DECISION-2-option2.md`. Same gaps | native on branch 235 (packaging 45) |
| T1.9 (half b) | NOT DONE | — | — | — |
| T1.10 | ON MAIN | main | `test_vectors/ethereum/vectors.yaml` (5 vectors), `exclusions.yaml` (empty); `vectors:validate` passes | tools/vectors 20 |
| T1.11 (+d1, d2) | ON MAIN | main | SDK `lib/src/{account,address,coin,core,engine,errors,lifecycle,mnemonic,session,wallet,worker}`, `wallet_core_flutter.dart`, `advanced.dart` | SDK 277 total, native-tagged 74 (session_test 41, session_native 18, engine_native 19, input_validation 19, coin_facade 20, protocol 17, worker_loop 12) |
| T1.12 (+d1) | ON MAIN | main | `requests/evm/`, `signing/*` (6 files), `families/evm/*`, `DECISION-1-approach-a.md` | evm_family 24, requests 19, sign_handler_native 15, signing_core_native 12, signer_session 11, signer_native 5, sign_protocol 5 |
| T1.13 | ON BRANCH ONLY: `eval/approach-b` 333eb51 (older T1.12 base) | branch | `native/src/shim/wcf_sign.{c,h}`, `signing/adapter/adapter_signing_core.dart`, `DECISION-1-approach-b.md` | SDK on branch 306 total, 283 run, 23 skipped (shim not present) |
| T1.14 | ON MAIN | main | `tools/probes/*`, `docs/decisions/evidence/sign_json_coverage.md` | tools/probes 4 |
| T1.15 (+d2, d3) | ON MAIN; **CI wiring NOT DONE** | main | `tools/lint/{bin,lib}/public_api_lint.dart`; re-run: 49 elements / 0 violations. Not in `ci.yml` | public_api_lint_test 48 |
| T1.16a (+d2) | PARTIAL ON MAIN | main | `example/lib/{main,src/m0_flow,src/m0_page}.dart`, `tools/consumer_check.sh`, `tools/consumer_check/`. Every packaging stage exits 2 "waiting for DECISION-2 (T1.16b)" (`consumer_check.sh:133-140`) | example 6; `tools/consumer_check` no tests |
| T1.16b | NOT DONE | — | packaged consumer build/run on emulator and simulator | — |
| T1.17-pre (+d2) | PARTIAL ON MAIN | main | `tools/lint/{bin,lib}/runtime_deps_check.dart`, `.github/dependabot.yml` (`pub`). `lint:runtime-deps` re-run: OK ×3 | runtime_deps_test 13 |
| T1.17 proper | NOT DONE | — | `ci.yml:146-160` device jobs are `echo placeholder`. No `integration_test/`. No no-network runtime test. CI runs none of `lint:public-api`, `vectors:validate`, `lint:runtime-deps`, `test:native`, example tests | — |
| T1.18 | ON MAIN | main | `docs/security/memory_contract.md` (220 lines), `lifecycle.md` (165), README memory-contract block lines 16–25 | docs |
| T1.19 | ON MAIN | main | `tools/packaging_eval/**` | 178 |
| D1a / D1 | NOT DONE | — | No debate record. No `phase-1-closed` tag (`git tag` shows only `phase-0-closed`) | — |

`task/T1.8` and `task/T1.9` both point at 6f7b520 (W3 base); the work lives on the eval branches.

## B. PRD §18 M0 exit criteria

| Criterion | Verdict | Evidence |
|---|---|---|
| Runs on Android (emulator + device) and iOS (simulator + device), debug **and** release | **UNPROVEN** | No file under `docs/decisions/evidence/` or `docs/plan/reviews/` records an M0-flow run on any target. Eval tables (branch only) show iOS simulator debug running only an identity/symbol probe; every Android cell `unmeasured`. No Android `.so`. No physical device (`reviews/phase-D-codex-debate.md:43`). No x86_64 emulator. |
| Create wallet | MET on macOS host only | `session_native_test.dart:172` |
| Import known mnemonic → expected Ethereum address | MET on host only | `session_native_test.dart:182`, vector `ethereum-address-n/a-1` (`m/44'/60'/0'/0/1`) |
| Sign EIP-1559, byte-for-byte | MET on host, **below the public API** | `signing_core_native_test.dart:101` via `SyncSigningCore` with the vector's raw key. Public surface cannot reproduce it: `KeyLocator.imported` needs a `KeyRef` nothing public issues. Every vector has `platforms_verified: []`. |
| Invalid mnemonic / address / path raise typed errors | MET on host | `session_native_test.dart:230`, `input_validation_test.dart` (19) |
| `dispose()`/`close()` exercised; leak tracker zero | MET on host, **debug only** | `session_native_test.dart:313-364`, `example/test/m0_flow_native_test.dart:96-103` (through the test seam; not public). Tracker compiled out in release (`leak_tracker.dart:150-158`). |
| Fresh consumer installs from packaged dependencies | **NOT MET** on main | `consumer_check.sh` packaging stages exit 2. Branches: iOS loopback-hosted builds pass; Android unmeasured. |
| Identity check passes; mismatched manifest fails | **NOT MET** | `generated/manifest.dart:36` `identityArtifactSetId = 'TBD-T1.2'`; public `initialize()` cannot succeed (`session_native_test.dart:58-67` asserts failure). Pass/mismatch shown only via `initializeForTesting` with override `as_4.8.0_000` (`:118-141`). Comparison 2 skipped on default path (`wallet_core.dart:44-47`, `handler.dart:277-278`). |
| DECISION-1 and DECISION-2 recorded with data | **NOT MET** | No `DECISION-1.md` / `DECISION-2.md`; evidence files only, option/approach-b evidence on branches. |
| DECISION-6 at D1a | **NOT MET** | No file. Only Flutter 3.47.5 tried. |
| DECISION-14 at D1a with T1.2 evidence | NOT MET | Recorded 2026-09-07 "subject to ratification"; T1.2 artifact evidence absent. |
| `gen:check` | MET as of CI 37158120282 (44532eb) | Not re-run in CI at 672e09e (billing). `gen:proto` changed afterwards (c7d32e9, 51d4c62). |
| `lint:public-api` passes; no generated `CoinType` public | MET (reviewer run), not CI-enforced | 49/0. `Coin` holds private `CoinType? _type` (`coin.dart:63`). |
| CI runs tests on Android emulator + iOS simulator | NOT MET | `ci.yml:146-160` |
| Signing duration measured before the worker is built | NOT MET | No measurement anywhere. |

## C. Rule compliance

| Rule | Hits | Judgement |
|---|---|---|
| 2 | `package:crypto` in native `verify_identity.dart:29` (sha256 of manifest bytes), `native/tool/src/fetcher.dart:20` (artifact sha256, build time), `tools/{gen,manifest,upstream,probes}`. Bit ops: `signing_core.dart:229-246` (protobuf tag/varint), `evm_family.dart:204-210` (BigInt→bytes). No pointycastle/HMAC/curve code. | **Compliant** — integrity hashing and signing-input encoding only. |
| 3 | lib: none. `dart:io` only in native `loader.dart`, `library_location.dart` (file access). Network only in `native/tool/src/fetcher.dart` (build time). runtime-deps OK ×3. | **Compliant.** S4 no-network runtime test does not exist. |
| 4 | `wallet_core_flutter.dart:29-74` exports typed facades + `ManifestCheck` enum. 0 violations. `advanced.dart` re-exports bindings and registry, not protobuf. | **Compliant.** |
| 6 | Requests carry chain id, nonce, to, value, gas, fees, data. `KeyRef` is an int id. `privateKey` only in `signing_core.dart` and `handler.dart:352`. | **Compliant.** |
| 8 | Only `"reproducible_build_verified": false` and `tools/native_build/README.md:143` ("**not** reproducible"). No AGPL claims, no "trust" in package names. Disclaimer in README, example, native README, security docs; **absent from the three package `description:` fields** (`packages/*/pubspec.yaml:2-5`). | **Compliant**, pre-publish gap on pubspec descriptions. |
| 12 | `Wallet.close`/`WalletCore.shutdown` return `Future<void>`; sync `close()` only on internal `WorkerTransport` (`transport.dart:54`). `Signer.sign(request, Set<KeyLocator>)` → sealed `SignResult`. | **Compliant.** |

## D. Decisions

| Decision | Due | State | Gap |
|---|---|---|---|
| DECISION-1 | D1 | evidence only (`-approach-a.md` main, `-approach-b.md` branch) | no record; D1 not held |
| DECISION-2 | D1a | evidence only, branches only | Android rows unmeasured |
| DECISION-6 | D1a | missing | floor `>=3.44.0` unproven; 3.44.1 cannot build iOS on Xcode 27 |
| DECISION-14 | D0 → D1a ratification | recorded, pending ratification | artifact fields TBD; retention "a proposal" (`:157`); `:23` still "pending D0" |
| DECISION-9 | Phase 0 | recorded, pending ratification | `-DFLUTTER=ON` patch and 4-JNI allowlist in `build_android.sh` recorded in neither DECISION-9 nor -14 |
| DECISION-5, 8, 11, 13 | Phase 0 | recorded (5, 11, 13 subject to ratification) | ratification owed at D6 |
| DECISION-12 | Phase 0 | recorded, amended 2026-10-03 | ratification |
| DECISION-3, 4, 7, 10 | later | missing (expected) | — |

## E. Findings

**Blocking (Phase 1 cannot close without them):**
1. **No artifact set exists.** Manifest identity/artifacts/toolchain TBD (`native/lib/src/generated/manifest.dart:36`); public `initialize()` always fails. Fix: billing → build-native → P0 → `gen:manifest`.
2. **Comparison 2 off on the default path.** `wallet_core.dart:44-47`, `handler.dart:277-278`. Fix: run the manifest hash check by default (e.g. constants `gen:manifest` already embeds).
3. **No packaging decision, no device evidence.** DECISION-1/-2/-6 unrecorded; D1a/D1 not run; T1.8b/T1.9b unmeasured.
4. **T1.17 not done.** `ci.yml:146-160` placeholders; no `integration_test/`, no no-network test, no CI wiring for lint:public-api, vectors, runtime-deps, test:native, example.
5. **T1.16b not done.** `consumer_check.sh:133-140` exits 2; example APK has no `.so`.
6. **Device criteria cannot be met on this host.** No physical devices, no x86_64 emulator. Satisfy them or have the owner amend M0 explicitly.
7. **Byte-for-byte signing not reachable through the public API.** Proven only at `signing_core_native_test.dart:101`. Fix: HD-derivable EIP-1559 vector, or D1 accepts the core-level proof explicitly.
8. **"Leak tracker reports zero" in release is structurally impossible as written.** Tracker compiled out (`leak_tracker.dart:150-158`); release proof unbuilt; report not public. Fix: amend the criterion, or add a release inertness test plus a public read-only report.

**Should-fix:**
- **Threat model stale** (`docs/security/threat_model.md`): line 9 "No product code exists yet"; §1.3 boundary 1 assumes a worker isolate but M0 runs `InProcessTransport`; TM-26 does not name `OperationDeadline` and no public cancel exists; TM-30 describes a "const guard" + release test, code is assert-based and the test does not exist; TM-16 claims a release-set cross-check (comparison 1 deferred to T3.11, comparison 2 off by default); TM-10 cites a no-network example test that does not exist; no rows for `-DFLUTTER=ON`, the JNI allowlist, undigested `libc++_shared` (Option 1), the example app's mnemonic display; §7 phase-close revision not done.
- **PROGRESS status table stale**: T1.16/T1.17 "queued" (lines 83–84) though partial work is on main; T1.1–T1.15, T1.18, T1.19 "ready for you"/"taken by you" though landed on main.
- **Implicit build decisions unrecorded** (`-DFLUTTER=ON`, JNI allowlist) in DECISION-9/-14.
- **HEAD 672e09e never ran in CI** (billing); last green main CI 37158120282.
- **Manifest artifact keys don't match the built set**: still lists `armeabi-v7a` and `ios/TrustWalletCore.xcframework.zip`; built Apple set is per-slice `.dylib`s. Reconcile at P0.
- **Package descriptions lack the disclaimer** (`packages/*/pubspec.yaml:2-5`).

**Nits:** `DECISION-14.md:23` "pending D0"; every vector `platforms_verified: []`; `example/` not a workspace member (root `pubspec.yaml:12-24`) so `melos run test` never runs its tests; plan T1.10 names path `/0/0`, vector uses `/0/1` (upstream-sourced, acceptable).

## F. Silent drops

- Signing-duration measurement (PRD §18 M0 scope, `phase-1-m0-spike.md:7`); DECISION-12:48 pushes it to T2.10.
- Release-mode inertness of debug aids (TM-30, S8): T1.6 defers to T1.17, T1.17's task text does not list it.
- Comparison 2 on the default path: in no task's acceptance; T1.16a excluded it on purpose.
- Public leak-tracker report and public byte-for-byte signing path.
- x86_64 emulator runtime and physical-device rows (owner).
- Threat-model revision at Phase 1 close: the D1 outline (`phase-1-m0-spike.md:101-105`) lacks the mandatory threat-row question (`threat_model.md:203`).

## G. Distance to "Phase 1 closed"

Main has all host-side plumbing, green on the macOS host library: generators, memory layer, loader; SDK session, EVM signing, public lint; vectors and docs; example skeleton and runtime-deps lint. Counts: SDK 277 (74 native), bindings 64 (42 native), native 190, tools 474, example 6. Rules 2, 3, 4, 6, 12 hold.

Main lacks every M0 criterion that needs a target: no artifact set; a public `initialize()` that cannot succeed; no packaging decision, so no packaged consumer; no device or CI-device evidence; DECISION-1/-2/-6 unrecorded. Packaging evidence is iOS-only and on eval branches. Phase 1 is "spike code complete on the host, target proof not started". The single most important gap is **the missing published artifact set** (billing-blocked T1.2 → P0); everything else waits on it.
