# Review of integration/W6 @ 1077399 — Fable 5.1, high effort (read-only, re-ran every gate)

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

Brief: `docs/plan/briefs/REVIEW-W6.md`. Verbatim report follows; triage in PROGRESS.md.

---

# Review of `integration/W6` @ `1077399` — READ-ONLY

Nothing in the repository was created, edited, or deleted; no git command wrote. Worktree `git status --porcelain` is empty before and after everything below (including after `gen:check`), HEAD is still `1077399`, and the root checkout's status is unchanged from the start. All reproductions ran under the session scratchpad / `$TMPDIR` (`…/scratchpad/{gates,fresh,protoinj,oldsess,apk,cc,rdeps}`).

## A. Per delta

### 1. `08dced3` T1.16a — example app + `consumer_check.sh` skeleton: **OK** (nits + two example-level should-fixes)

- **Rule 4 / 12.** `grep` of `example/lib`: imports are only `package:flutter/{material,foundation}.dart`, `package:wallet_core_flutter/wallet_core_flutter.dart`, and the app's own files (`main.dart:12-16`, `m0_flow.dart:13-14`, `m0_page.dart:12-14`). No `CoinType`, `advanced.dart`, `dart:ffi`, `TW*`, protobuf token outside doc comments. Coin facade `Coin.ethereum` (`m0_flow.dart:426,460`); `wallet.close()` / `core.shutdown()` awaited (`:500`, `:515`). Every `src/` import of the SDK is confined to `example/test/support/test_seam.dart:21-30`, as the SDK's own tests do.
- **Rule 6.** `EvmTransactionRequest.transfer(...)` (`m0_flow.dart:459-471`) carries no key; the signer gets `KeyLocator.hdPath(wallet.ref, account.coin, account.derivationPath)` (`:429-433`).
- **Rule 8.** Forbidden words: 0 hits in `example/` (outside `android/ios`) and `tools/consumer_check*`; disclaimer present in `pubspec.yaml`, `README.md`, `main.dart`, `m0_flow.dart`, `m0_page.dart`, `consumer_check.sh`, `publish_locally.dart`; package name `wallet_core_flutter_example`.
- **No native-project edits — reproduced.** `HOME=$(mktemp -d) flutter create --platforms=android,ios --org dev.wcf.example --project-name wallet_core_flutter_example <scratch>` with the same Flutter 3.47.5 (`.metadata` revision `6a19cca564` identical). `diff -r` on `android/`: only git-ignored `gradle-wrapper.jar`, `gradlew`, `gradlew.bat`, `*.iml` differ. `ios/`: only git-ignored generated `Flutter/Generated.xcconfig`, `flutter_export_environment.sh`, `Flutter/ephemeral/` differ (absolute paths from the gate run). `.gitignore` and `.metadata` byte-identical; `grep -rn DEVELOPMENT_TEAM example/ios` → none. Claim holds.
- **Secrets.** `m0_flow_test.dart:114-133` really proves it: with `ensureSemantics()`, both mnemonics on screen (`findsNWidgets(2)`), `find.semantics.byLabel/byValue(RegExp('abandon|about'))` → `findsNothing`, and the "withheld" notice is in the tree (so the tree is live). `ExcludeSemantics` at `m0_page.dart:198-204`; obscured, no-suggestions field at `:225-238`. No `print`/`debugPrint`/`log` anywhere in `example/lib`. SDK side: `InvalidInputError.message` "must not quote the input" (`errors.dart:66,72`) and the SDK test 'errors raised for a secret input never render it' back the `StepError.sdk` lines.
- **`dependency_overrides`** (`example/pubspec.yaml:34-38`): justified in the comment and by the tree — `wallet_core_flutter` pins siblings exactly (PRD §15.4) and `example/` is not in the root `workspace:` (11 members, `pubspec.yaml:12-23`). `wallet_core_flutter_native` is both a dev_dependency and an override — redundant, harmless.
- **`publish_locally`** does what its header says (`publish_locally.dart:122-187`, `:191-228`): listing content type, exactly one version, served pubspec without `path:`/`resolution`/`publish_to`/`dev_dependencies`/`dependency_overrides`, siblings `hosted:` at the server URL at the exact staged version; archive sha256 == listed == staged; `pubspec.yaml` and `lib/` at the tar root. Reproduced end to end (`WCF_CONSUMER_CHECK_DIR=<scratch> tools/consumer_check.sh`): 3 packages 0.0.1 served on 127.0.0.1:55172 and fetched back (143360 / 505743 / 59565 bytes). It is, however, a self-consistency check of the loopback server against its own staging — no pub client resolves from it, and its artefacts cannot be reused by `add_dependency` (port baked into the staged pubspecs; server stopped) — which the script states honestly (`consumer_check.sh:179-184`).
- **Stage structure vs PRD §12.2 step 11.** Step 11 = `publish_locally` + `add_dependency` (waiting); step 1 = `create_consumer`; steps 2/3 = `build_*`/`run_m0_flow` (waiting). Exit codes verified: full run 2, `--stage add_dependency` 2, `report` 0, unknown stage 64, work dir inside the repo refused with 64. Missing for step 1: no stage asserts "no native edits" after `add_dependency` (should be a `diff -r` against a pristine template in T1.16b).
- **APK claim reproduced** in a scratch copy of the tree: `flutter build apk --debug` → `app-debug.apk` (151 MB), native libs `libflutter.so` ×3 ABIs (+ `libVkLayer_khronos_validation.so`), `libTrustWalletCore` count 0 — exactly README lines 79-82.
- Gaps found (details in B): stale comment `m0_flow.dart:200-202` contradicting T1.11-d1; `failed`-state UI trap (`m0_page.dart:107,133,336`); `tools/consumer_check/` analysed by no melos gate (I ran `dart analyze --fatal-infos tools/consumer_check`: clean).

### 2. `7286706` T1.17-pre — `lint:runtime-deps` + Dependabot pub: **FINDINGS**

- Closure is computed from `dependencies:` only (`runtime_deps_check.dart:140,175`), packages located through the root `.dart_tool/package_config.json` (`:70-93`), hosted pubspecs walked in the pub cache. **Transitive smuggle is caught** — fixture F2 (`ffi`'s own pubspec depends on `http`) → "http is on the deny list", exit 1. `flutter` (sdk) is handled: real closures contain `flutter, sky_engine, characters, …` (gate log). Real tree: 3× `Status: OK`, 6 "build-time, network allowed by rule 3" lines, all in `wallet_core_flutter_native/tool/`.
- **Escapes, all reproduced with hand-built fixtures (`scratchpad/rdeps/run_fixtures.sh`):**
  - F1 `ffi: {hosted: https://evil.example.com/pub, version: ^2.0.0}` in `wallet_core_flutter` → `Status: OK`, exit 0. The source check only looks for `git`/`path` keys (`:146,151`) and never consults `pubspec.lock` `source:`/`url:`; root `dependency_overrides` (today: `cli_util`, tooling only, `pubspec.yaml:36-37`) are likewise invisible.
  - F3 `lib/` using `io.SecureSocket.connect`, `RawSecureSocket`, `ServerSocket.bind`, `WebSocketTransformer`, `NetworkImage(...)`, `Process.run('curl', …)` → "Network Symbols: OK", exit 0 (symbol list `:199-207`, word-boundary regex `:233`). Aliased `io.Socket`/`show Socket` are caught (F3b); a doc comment "never uses HttpClient" is a false-positive violation (F3b). `dart:_http` is not importable by user code — not a gap.
  - F4 unknown non-denied package → "bad_pkg is not on the allow list", exit 1: the allow-list branch (`:188`) works, **but no test exercises it** — `bad_pkg` is created in `setUp` (`runtime_deps_test.dart:34`) and never used; the 8 fixture tests assert only deny-list, git-source, and symbol strings. A deny-list-only stub passes the whole suite, contrary to the brief ("the allow list is the policy", "each test fails on a stub").
  - F5 `--json` is documented (`README.md:34`, `bin:8`) but not parsed (`:66` handles `--root` only) — silently ignored, plain text printed.
- `path` is allow-listed (`:37`) but appears in no closure; README lists names without the per-entry justification the brief asked for. 'the real three packages' test depends on cwd (`Directory.current.parent.parent`, `test:300`) — fine under `melos exec`, wrong elsewhere. Missing `package_config.json` exits 1 like a violation (`:76`); the lint package's convention is 2 for "no verdict".
- **Dependabot pub at `directory: /` on a pub workspace: UNPROVEN** (`.github/dependabot.yml:9-16`); cannot be verified locally; if Dependabot's pub updater does not resolve workspaces it sees only the root pubspec (dev deps + `cli_util` override). Watch the first run.

### 3. `c7d32e9` T1.4-d1 — staged `gen:proto` with EXIT-trap restore: **FINDINGS**

`gen:check` at `1077399`: clean (proto.sh "60 .proto in -> 180 .dart out", `git diff --exit-code` empty, no untracked generated files). Injections ran in a scratch repo mirroring the layout (`compat_manifest.json`, symlinked `third_party/`, copied `generated/proto`, protoc 33.4 + pinned plugin); the unmodified script there is byte-identical to the committed output.

| scenario | exit | out_dir == committed | `.old` left |
|---|---|---|---|
| INJ1 `false` between the two `mv`s (`proto.sh:380-381`) — the PROGRESS claim | 1 | yes | no |
| INJ2 `dart format` fails (before any `mv`) | 1 | yes | no |
| INJ3 `$out_dir` absent | 0 | created, byte-identical | no |
| INJ4 stale `proto.old` + no `proto` (SIGKILL aftermath) then a failing run | 1 | restored from `.old` | no |
| INJ5 stale `.old` + no `proto` then a good run | 0 | yes | no |
| INJ7 SIGTERM inside the window | 143 | restored by the trap | no |
| INJ8 SIGKILL inside the window | 137 | **`proto` missing, `proto.old` left**; next run self-heals; `gen:check`'s untracked step would flag it; temp `wcf-gen-proto.*` left | transiently |
| **INJ6 parent `generated/` not writable** | **0** | **NO: 182 entries, a nested `proto/proto/` with 180 .dart files** | no |

INJ6 is a bug: `mv "$out_dir" "$out_dir.old" 2>/dev/null || true` (`proto.sh:380`) swallows EACCES (it was meant for ENOENT), then `mv "$staging" "$out_dir"` (`:381`) moves the staging dir *into* the still-existing output and the script reports success. Fix verified in scratch (`if [ -e "$out_dir" ]; then mv "$out_dir" "$out_dir.old"; fi`): exit 1 "Permission denied", output intact, normal run still byte-identical. CI is protected by `gen:check`'s untracked step; a developer's local `gen:proto` is not.

Same-filesystem assumption: here `$TMPDIR`, `/tmp` and the worktree are all `dev=16777230`, so both `mv`s are renames. Where they are not (tmpfs `/tmp`, `TMPDIR` on another volume) `mv` degrades to copy+delete: non-atomic, and a partial copy leaves `$out_dir` existing so `cleanup`'s `[ ! -e "$out_dir" ]` guard (`:138`) does not restore and `:141` deletes the only backup. Trap on failure before any `mv`: correct (nothing to restore, `rm -rf` of a stale `.old` is harmless).

### 4. `98fcef2` T1.11-d1 — `_finishClosed` async, awaited `_states.close()`: **FINDINGS**

Call paths (`session.dart`): `shutdown()` from `closed` → `Future.value()` (`:235-236`); `failed` → `_shutdown = _finishClosed()` whose synchronous prefix still transitions before the first `await` (`:240`, `:295-302`); `initializing` → error, unchanged (`:241-247`); `ready`/`closing` → `_runShutdown()` (`:250`); `closing` with `_shutdown == null` is unreachable (the `_transition(closing)` at `:255` runs in the synchronous prefix before `:250` assigns, and the async broadcast controller `:149-150` cannot re-enter). `_runShutdown`: acknowledged → `await _finishClosed()` (`:291`); forced → `kill()` sets `_closed` before `_fault`'s microtask (`transport.dart:116-119`, `:133-137`), so `_onTerminated` is suppressed and `states` show `closing → closed`; executor dies unforced → `_onTerminated` (closing → failed, `:306-312`) then `await _finishClosed()` + `rethrow` (`:285-286`), `finally grace.cancel()` (`:289`). `_onTerminated` after `closed` is a no-op. `_initialize`'s `await _states.close()` (`:220`) can have no listeners. Re-entrancy test (`session_test.dart:328-346`) passes; the futures are identical.

Broadcast `close()` semantics, probed (`scratchpad/broadcast_close_probe.dart`): completes only after every subscription has received pending data + `done` and been cancelled (order `[a:42, b:42, a:done, b:done, close-completed]`); it does **not** wait for async `onData` futures; a listener added after close gets `done` only. **But it never completes while a subscription is paused, and `await for` pauses while its body awaits.** Reproduced against the real W6 session (scratch copy, `review_paused_probe_test.dart`): `sub.pause()` → `shutdown()` "DID NOT COMPLETE within 2s (state=SessionState.closed)", completes after `resume()`; `await for` body awaiting on `closing` → `shutdown()` "still pending after 500ms", completes when the body releases. Before this delta `shutdown()` completed regardless. Handles are already released and `state == closed` synchronously, so nothing leaks — only the future is held hostage by a consumer. DECISION-12 §3.8 (`:214`) explicitly positions `shutdown()` as the operation "whose grace period *does* expire"; this wait sits outside the grace period.

Test count: the commit says "Five new tests"; the diff adds four (`session_test.dart:297,311,329,350`; 33 → 37 tests; SDK 270 → 274). The brief's first scenario (normal shutdown, no wallets, synchronous assertion) has no dedicated test; the pre-existing 'initialize → ready, shutdown → closing → closed' test awaits `toList()` and so cannot observe the ordering. Running the four new tests against `main`'s `session.dart`: three fail with `Expected: closed / Actual: closing` (open wallet, second subscriber, re-entrant); 'subscription made after closed' passes on the old code too (close() was already called, just unawaited).

Docs: the guarantee is stated in `wallet_core.dart:52-56,86-88`. DECISION-12 §3.8 steps 4-5 (`:221-222`), §3.1's broadcast sentence (`:83`) and `docs/security/lifecycle.md` "Shutdown" step 4 (`:149`) are silent, not contradictory. `example/lib/src/m0_flow.dart:200-202` still says "`closed` arrives after `shutdown()` has returned" — now false; W6 did not reconcile the two branches.

## B. Findings, most severe first

No **blocking** finding (no rule violation, no secret-handling defect, no gate failure, no merge artefact).

**Should-fix**

1. `packages/wallet_core_flutter/lib/src/session/session.dart:303` — `await _states.close()` lets a paused `states` subscription (or an `await for` body) hold `shutdown()` open indefinitely, outside `shutdownGrace`, contradicting DECISION-12 §3.8's rationale. Fix: `await _states.close().timeout(timeouts.shutdownGrace, onTimeout: () {})` (keeps the ordering guarantee for every live listener, restores boundedness), or document the coupling in `wallet_core.dart:52-56,86-88` and DECISION-12 §3.8 step 5; either way add a paused-subscription test to `session_test.dart` and the missing no-wallet ordering test.
2. `tools/gen/proto.sh:380` — `mv "$out_dir" "$out_dir.old" 2>/dev/null || true` masks every failure, producing a nested `proto/proto/` with exit 0 when the parent is not writable. Fix (verified): `if [ -e "$out_dir" ]; then mv "$out_dir" "$out_dir.old"; fi`.
3. `tools/gen/proto.sh:136,146` — staging under `$TMPDIR` assumes the same filesystem; across devices the swap is a copy and `cleanup` (`:138-141`) cannot restore a partial result. Fix: stage as a sibling (`$out_dir.staging.$$`, removed in the trap) or `die` unless `stat -f %d` / `stat -c %d` match.
4. `tools/lint/lib/runtime_deps_check.dart:141-155` — a custom `hosted:` URL (and any override) passes. Fix: for every closure entry read `pubspec.lock` and require `source: hosted` with `url: https://pub.dev`, `source: sdk`, or a workspace sibling.
5. `tools/lint/test/runtime_deps_test.dart` — no test covers the allow-list branch (`lib:188`); `bad_pkg` (`test:34`) is unused. Fix: add 'depends on an unlisted hosted package -> violation' asserting "is not on the allow list".
6. `tools/lint/lib/runtime_deps_check.dart:199-207` — symbol scan misses `SecureSocket`, `RawSecureSocket`, `ServerSocket`, `RawServerSocket`, `WebSocketTransformer`, `NetworkImage`/`Image.network`, `Process.run`; flags comments. Fix: extend the list (or match `^\s*import 'dart:io'` + `Socket|Http|WebSocket` identifiers), strip `//`/`///` lines, and say in the README that the scan is a guard, not a proof.
7. `example/lib/src/m0_page.dart:107,133,336` — after `ready → failed` neither "Shut down" (`_canOperate` needs `isReady`) nor "Start over" (`hasEnded` needs `closed`) is available, although DECISION-12 §3.1 says `failed` accepts `shutdown()`; `M0Flow.dispose()` (`m0_flow.dart:549`) also skips shutdown when not ready. Fix: enable shutdown for `failed` too; show "Start over" for `failed || closed`.
8. `docs/plan/PROGRESS.md` (root, uncommitted) `:324-325` — T1.4-d1 and T1.11-d1 share one bullet (" - **T1.11-d1 accepted" mid-line), and five sentences from Phase C entries (the `-DFLUTTER=ON` "this flag" finding, the T1.2 `/*` warning, the emulator/AVD, CI run 37148705952 on `99137b9` = the W5 merge, the T1.2/T1.17 symlink follow-up) are appended to the W6 entry, where "this flag" has no antecedent. They were already mis-attached to the T1.17-pre line in committed `62a6966:322`; the uncommitted edit moved them. Fix: split the bullet and move the five sentences back to their Phase C entry. Also "a test that failed on the old code plus four scenarios" (`:324`) and the commit's "Five new tests" → four.
9. `tools/consumer_check.sh:185-195` — `publish_locally`'s `ok` status does not carry to `add_dependency` (server gone, port baked in). Fix in T1.16b: serve + add + `pub get` + lock assertion in one stage/process, and add a "no native edits" `diff -r` against a pristine template (PRD §12.2 step 1).

**Nits**

10. `example/lib/src/m0_flow.dart:200-202` — stale comment; reword to the new guarantee.
11. `tools/lint/README.md:34`, `bin/runtime_deps_check.dart:8` — `--json` documented, not implemented; implement or drop. `README` should justify each allow-list entry (`path` is in no closure) as the brief required.
12. `tools/lint/lib/runtime_deps_check.dart:76` — missing package config exits 1; use the package's "no verdict" code 2.
13. `tools/lint/test/runtime_deps_test.dart:300` — resolve the repo root by walking up for `AGENTS.md`+`compat_manifest.json` (as `example/test/support/host_library.dart:65-77` does) instead of `Directory.current.parent.parent`.
14. `tools/consumer_check/` is analysed by no melos gate (clean today; `format:check` does cover it). Add `dart analyze --fatal-infos tools/consumer_check` to `analyze` or a `lint:tools` script.
15. DECISION-12 §3.8 step 5 (`:222`) and `lifecycle.md:149` should state the ordering guarantee (and its caveat) once; DECISION-12 is the normative doc.
16. `example/pubspec.yaml:28-29,37-38` — `wallet_core_flutter_native` as both dev_dependency and override; keep one.
17. `example/test/m0_flow_test.dart:14-28` will need flipping once P0 lands and a library is found by default (the comment says so) — expected.
18. `.github/dependabot.yml:9-16` — verify on the first run that Dependabot resolves the workspace members; otherwise list `directories: ["/", "/packages/*", "/tools/*"]`.

## C. Gate table at `1077399`

Run by me (`run_gates.sh`, logs under `scratchpad/gates/`), sequentially, `gen:check` last; `git status --porcelain` empty before and after.

| Gate | Exit | Counts |
|---|---|---|
| `melos bootstrap` | not re-run | pre-warmed per brief |
| `melos run analyze` | 0 | 11/11 packages "No issues found!" |
| `melos run format:check` | 0 | 459 files, 0 changed |
| `melos run test` | 0 | 995 tests: native 190 · SDK **274** · bindings 64 · gen 3 · vectors 20 · upstream 109 · probes 4 · manifest 67 · inventory 29 · packaging_eval 178 · lint **57** |
| `melos run test:native` | 0 | bindings **42** · SDK **74** |
| `melos run inventory:check` | 0 | 464 TW* exported, 19/19 enums, `inventory.json` + `symbol_names.dart` up to date |
| `melos run gen:check` | 0 | ffigen · inventory · proto (60 → 180 .dart; key_fields 49 msgs / 53 fields) · registry · manifest embed; `git diff --exit-code` clean; no untracked generated; tree clean after |
| `melos run lint:public-api` | 0 | 49 exported elements, 0 violations |
| `melos run lint:runtime-deps` | 0 | 3× OK; closures 15 / 14 / 10 entries as PROGRESS lists; 6 build-time lines (native `tool/`) |
| `melos run vectors:validate` | 0 | 2 files, 5 vectors, 0 exclusions |
| `melos run manifest:validate` | 0 | "Manifest is valid." |
| `example/` `flutter analyze` | 0 | No issues found |
| `example/` `flutter test` | 0 | 5 passed (incl. the native test; library present) |
| `example/` `WCF_NATIVE_LIB=… WCF_NATIVE_REQUIRED=1 flutter test --tags native` | 0 | 1 passed |
| extra: `dart analyze --fatal-infos tools/consumer_check` | 0 | No issues (not covered by any gate) |
| extra: `tools/consumer_check.sh` (full, scratch work dir) | 2 | `create_consumer` ok · `publish_locally` ok (3 pkgs) · 6 stages "waiting for DECISION-2 (T1.16b)" |
| extra: `flutter build apk --debug` (scratch copy) | 0 | `app-debug.apk` 151 MB; `libflutter.so` ×3 ABIs; no `libTrustWalletCore.so` |
| not run | — | `probe:sign-json` (not in the brief), device gates |

Merge sanity: `main..integration/W6` is exactly 4 task commits + 4 `--no-ff` merges; `git diff-tree --cc` of every merge is empty (41 bytes = header only); all four tips are ancestors; `git merge-tree --write-tree 48fbaf1 98fcef2` = `1951ba73…` = W6's tree.

## D. Verdict

`integration/W6` is ready to merge into `main` once CI is available: the tree is clean, every canonical gate and the example gates are green at `1077399` with the counts the orchestrator recorded, the four merges are trivial, and the four deltas do what they claim (the native-project diff, the semantics test, the loopback publication, the APK, the proto failure injection, and the three failing-then-passing ordering tests all reproduced). None of the findings is a rule violation or a safety regression, so none blocks the merge; but three deserve follow-up briefs opened with the merge rather than after it — T1.11-d2 (bound or document the new `states` wait, which lets a paused consumer hold `shutdown()` past its grace period; add the paused test and the missing no-wallet ordering test; fix the stale example comment), T1.4-d2 (guard the first rename so a non-ENOENT failure cannot nest the output under exit 0; stage on the same filesystem), and T1.17-d2 (check lock sources so a custom `hosted:` URL cannot slip through; test the allow-list branch; widen the symbol list; implement or drop `--json`). PROGRESS.md's uncommitted entries need the structural repair (glued bullets, five misattributed Phase C sentences, "five" → four tests) before they are committed, and Dependabot's pub run against the workspace root should be checked on its first execution.
