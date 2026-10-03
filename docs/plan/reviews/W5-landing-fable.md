# Review of the 2026-10-03 landing — Fable 5.1, high effort (read-only, re-ran every gate)

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

Brief: `docs/plan/briefs/REVIEW-W5-landing.md`. Tree: `integration/W5` @ `b07f593`. Verbatim report follows.

---

All evidence is in hand; nothing further is needed. Here is the review report.

# Review of the 2026-10-03 orchestrator session — `integration/W5` @ `b07f593`

Read-only review. Nothing in any worktree was created, edited, or deleted; no git write ran. Gate logs live only in the session scratchpad. All paths below are relative to `/Users/yossefebrahim/Work/wallet-core-package.worktrees/W5-integration` unless marked `(root)`.

## A. Per-item verdicts

### 1. A2 — documentation brought to the code — **OK, with findings (should-fix: 2, nit: 3)**

Every claim in the brief reproduces against the code:

- **13 requests / 14 replies.** `lib/src/worker/protocol.dart` declares requests at lines 137 (`Init`), 187, 211, 245, 260, 298, 330, 348, 366, 389 (`Sign`), 514 (`DisposeRef`), 536 (`Cancel`), 557 (`Shutdown`) = 13; replies at 611 (`InitOk`), 627, 644, 656, 668, 680, 692, 707, 731 (`Signed`), 744, 757, 770, 782, 796 (`Failed`) = 14. `ImportKey`/`SignMessage`/`Plan` exist only as "planned" in the library comment (protocol.dart:5-7, 33). DECISION-12 §3.2 (`docs/decisions/DECISION-12.md:104-108`) and `docs/architecture/lifecycle.md:361, 387, 409` state exactly these names and counts.
- **Secret-bearing set = eight (six requests incl. planned `ImportKey`, two replies).** Doc-comment markers: `CreateWallet` protocol.dart:186, `ImportWallet` :207, `ValidateMnemonic` :328, `ValidateMnemonicWord` :347, `SuggestMnemonicWords` :365, `MnemonicExported` :640, `MnemonicWordsSuggested` :704-707; library comment :31-40 lists the eight. Code-level: the only ownable buffer is `ImportWallet.entropy`, zeroed by `overwriteOwnedSecrets` (:579-583) and copied by `executorCopy` (:594-598); all other secrets are `String`s, redacted in every `toString()`. Consistent in DECISION-12.md:112-123, :374-376, :400-402; lifecycle.md:363; `docs/security/threat_model.md:64` ("three of the eight" — `ImportWallet`, `ValidateMnemonic`, `MnemonicExported` carry a whole mnemonic, correct) and :101 (TM-04 "closed set of eight", names all eight); `docs/security/memory_contract.md:74` ("one of the two replies"); `lib/src/wallet/wallet.dart:89-93`.
- **`OperationDeadline`.** Defined protocol.dart:60-108: `monotonicMicros() => Timeline.now` (:63), `after()` saturating at `neverMicros` (:84-94), `hasPassed` (:103). Created at submission `lib/src/session/session.dart:370` (before the session's own timer, :380), including for `Init` (:200-209 via `_send`). Carried beside the request: `lib/src/worker/transport.dart:46, 98, 111`. Checked twice in `lib/src/worker/worker_loop.dart`: before running (:233-240) and after the handler returns (:257-262), where the result is **not posted** (`return` at :261 precedes `post(reply)` at :263), the named wallet is released via `_handler.discard` (`handler.dart:480-488` disposes a `WalletCreated`'s wallet), and `_expired` posts `Failed(OperationTimeoutError)` (:284-288). Control messages never get a deadline (only the `default` branch stores one, :159). Session backstop :430-447, `Cancel` on expiry :449-458, late `WalletCreated` disposed :466-470. §3.5 defaults match `lib/src/session/wallet_core.dart:105-110`; mnemonic helpers use `derivation` (5 s) (`lib/src/mnemonic/mnemonic_facade.dart:52,70,90`); `initialize()` still takes `OperationTimeouts` (wallet_core.dart:46), so §3.5's "overridable at `initialize()`" is correct.
- **§8 trigger 6 "Fired 2026-10-03"** DECISION-12.md:374-376; **Amendment** :396-411; header row :13; **T2.1 forward note** :165 and :407-408 — present and phrased as not-yet-built.
- **Stale-wording sweep** (`grep -rn` "four" / "only reply" over `docs/` and `packages/*/lib`): no leftover in the amended passages except one — DECISION-12.md:393 "Read before ratifying: section 3.2 (the four payloads)" is unqualified (lines 384 and 374 correctly say "amended to eight"). `threat_model.md:103` (TM-06) "the one reply type that may carry it" is accurate for a *whole* mnemonic but reads as "the only secret-bearing reply".
- **Still stale, missed by A2:** `threat_model.md:67` (assets row: derived keys "serialized into the signing input under Approach A") and `:98` (TM-01 residual: "the serialized `SigningInput` holds the key in a Dart `Uint8List`"). The code makes no Dart-heap copy: the key reaches the core as a view over upstream's `TWData` and is staged only in a `calloc` buffer (`lib/src/signing/signing_core.dart:130-131`, `lib/src/engine/secret_buffers.dart:106-139`; `docs/decisions/DECISION-1-approach-a.md` §2 "Copies of the key on the Dart heap: 0"). This is the same staleness A2 proposed fixing in PRD §11.4 but did not carry into the threat model.
- `memory_contract.md` names `CreateWallet`, `ImportWallet`, `MnemonicExported`, `MnemonicWordsSuggested` but never `ValidateMnemonic`, `ValidateMnemonicWord`, `SuggestMnemonicWords` (grep count 0 each), although DECISION-12.md:112 says the contract "is to cover all eight".
- Process note: brief `DEC-12-amend.md` owned two files; the delivered change also touched `threat_model.md`, `protocol.dart`, `wallet.dart`, lifecycle §2, and `memory_contract.md` in the `T1.18` tree (disclosed in PROGRESS). Rule 11 deviation, content correct.

### 2. A3 — `crypto: ^3.0.7` — **OK**

`tools/probes/pubspec.yaml:9` is `crypto: ^3.0.7` (born in `42fea90`); root `pubspec.lock` resolves `crypto` `3.0.7`. `git diff integration/W3 task/T1.14 -- pubspec.lock` and `git diff task/T1.12 integration/W5 -- pubspec.lock` are both empty; `dart pub get --offline --dry-run` on W5: "No dependencies would change." Commit `42fea90` touches 8 files, all inside T1.14's allowed set.

### 3. LAND_W5 — git landing — **OK, with findings (should-fix: 1 pre-existing, nit: 3)**

- **File sets vs `LAND_W5.md`:** `54d08b2` (2 files) ✓; `6f7b520` W3 (145 files; none under `third_party/`, `build/`, `.dart_tool/`; none >5 MB new) ✓; `59e2f3a` T1.11 (52 files: `packages/wallet_core_flutter/**`, bindings `ffigen.yaml`, `lib/registry.dart`, `lib/src/generated/ffi/wallet_core_bindings.dart`, root `pubspec.yaml`, `tools/native_build/run_native_tests.sh`) ✓ — the generated file is faithfully regenerated (`gen:check` green); `6d894ff` T1.12 (50 files: SDK package + `DECISION-1-approach-a.md`, `DECISION-12.md`, `lifecycle.md`, `threat_model.md`) ✓; `333eb51` eval/approach-b (25 files, all in the step-5 set) ✓; `42fea90` T1.14 ✓; `8eab40e` T1.15 (59 files, `tools/lint/**` + `pubspec.yaml`) ✓; `d04f621` T1.18 (3 files) ✓; `e7bea5d` eval/option1 ✓; `1877067` eval/option2 ✓; `f53bd6b` (DECISION-2-option1 only) ✓; `b07f593` (2 files) ✓. Every commit carries the `Co-Authored-By` trailer.
- **Must-not-track check:** `git ls-files -i -c --exclude-standard` on W5 is empty; `eval/`, `hook/`, `android/`, `ios/`, `src/shim/` are absent from W5 (eval branches only, per the layout); no `DEVELOPMENT_TEAM` in any `project.pbxproj` on `eval/option1`/`eval/option2` (only empty `PROVISIONING_PROFILE_SPECIFIER`, `macos/Runner.xcodeproj/project.pbxproj:496,628,648`); credential-pattern scan (GitHub/AWS/PEM/Slack/OpenAI shapes) over all 11 branches: 0 files. **`tools/gen/bin/registry_transform.exe`** — 6,077,312-byte `Mach-O 64-bit executable arm64`, tracked since `1d70c6c`, present on every branch, not ignored: still a problem (see B).
- **Root `pubspec.yaml` merge:** workspace list ends `tools/probes`, `tools/lint` (lines 20-21); `test:native` is `run: bash tools/native_build/run_native_tests.sh` (line 148); `probe:sign-json` (177) and `lint:public-api` (178) present; 0 conflict markers; `127664d` merged clean, `2622c40` carries the manual resolution (`git show --cc`). Cosmetic residue: two consecutive blank lines after `- tools/lint` (22-23) and a doubled newline at EOF.
- **`task/T1.12` vs `eval/approach-b`:** `git diff … -- protocol.dart wallet.dart` is **empty** ✓. The 25 other differing files are the intended Approach B seam: `SigningCoreFactory` gains a `DynamicLibrary` parameter (`handler.dart`), `withDerivedKey` hands a `PrivateKeyHandle` instead of a `Uint8List` view (`hd_wallet.dart`), `SyncSigningCore` reads key bytes itself (`signing_core.dart`), plus the adapter core, shim C (`src/shim/wcf_sign.{c,h}`), shim tests, `run_shim_tests.sh`, `build_apple.sh`/`check_exports.sh`/README additions, and the "This copy" row in `DECISION-1-approach-a.md`. Note: `eval/approach-b`'s `build_apple.sh` lacks the `-headerpad_max_install_names` flag (it predates T1.2-d1) — must be carried when that branch is merged.
- **Topology:** `integration/W2` (`54d08b2`) is **not an ancestor** of W3 or W5; W3's `6f7b520` re-adds the same two files on `1d70c6c` (content diff W2↔W3 on those files: empty; legacy `git merge-tree` W2→W3: 0 conflict hunks). `main`↔W5: merge-base `89b137c`, 12 commits ahead / 2 behind, no file changed on both sides → Phase C's merge into `main` will be clean. The eleven landed trees all have empty `git status` (verified per worktree).

### 4. Gates on `integration/W5` — **OK** (re-run by me at tip `b07f593`, 06:29-06:30 host time; table in C)

All exit 0; `git status --short` empty after every gate including `gen:check` (which really ran `gen:ffi` → ffigen, `gen:proto`, `gen:registry`, `gen:manifest`, then `git diff --exit-code`). SDK **270**, native **42 + 74**, lint **49 elements, 0 violations** — all as expected. `probe:sign-json` ×2: stdout identical and the tree clean after both runs, i.e. the regenerated `docs/decisions/evidence/sign_json_coverage.md` is byte-identical to the committed file.

### 5. T1.2-d1 — **OK**

`b07f593` changes only a 3-line comment and one line `-Wl,-headerpad_max_install_names` on the `-dynamiclib` link block (`tools/native_build/build_apple.sh:366-371`; the rest of the invocation is byte-identical) plus one README sentence; `f53bd6b` appends the note to `DECISION-2-option1.md:177` without altering the recorded measurement. Host library check: `${TMPDIR}/wcf-native/artifacts/macos/arm64_x86_64/libTrustWalletCore.dylib` exists (built 06:24, post-flag). `otool -l | grep -A3 LC_ID_DYLIB`: `@rpath/libTrustWalletCore.dylib` on both arches (unchanged). Header padding (`otool -h` sizeofcmds vs `__text` offset): post-flag **6168 B arm64 / 6216 B x86_64**; the pre-flag `third_party/wcf-native/...` copy has **56 / 104 B** — exactly the numbers DECISION-2-option1 recorded. `install_name_tool -id` with a 212-char id on a scratchpad copy: **accepted** (post-flag) vs the documented "larger updated load commands do not fit" error on the pre-flag copy. Export gate on the post-flag dylib: 464 expected / 0 missing / 0 unexpected on both arches, `_wcf_build_info` exported, PASSED. Detail UNPROVEN: PROGRESS says `test:native 42 + 74` was run "on the rebuilt host library", but `run_native_tests.sh:30-37` prefers the repo copy (pre-flag) unless `WCF_NATIVE_LIB` is set; my run used the repo copy. Harmless (the flag changes no symbols).

### 6. Orchestrator's own edits (`PROGRESS.md`, `NEXT_STEPS.md`, root) — **FINDINGS (should-fix: 1, nit: 2)**

Rule-8 grep: only permitted uses (task name "Reproducibility job", "not claiming … reproducibility", the manifest key `reproducible_build_verified`, the narrative of rewording "audited"). Claims checked against the tree: branch hashes, "all eleven trees clean", "task/T1.8/T1.9 still at 6f7b520", "only conflict on the T1.15 merge", "`gen:proto` deletes `generated/proto/**` first" (`tools/gen/proto.sh:142 rm -rf "$out_dir"`), all gate counts — all supported. Not supported: the **wall-clock timeline** — PROGRESS records "A2 done 06:30", "LAND_W5 dispatched 06:32 … done 07:05", "T1.2-d1 done 06:35-06:50", yet the commits carrying that work are stamped 06:13:20 (`6d894ff`, includes A2), 06:15-06:17 (merges), 06:27:28 (`b07f593`/`f53bd6b`, all +0300), and the host clock read 06:33 EEST while I was running gates. Also: PROGRESS's "Correction to NEXT_STEPS: the additions are four, not five" — NEXT_STEPS never says "five" (the `DEC-12-amend.md` brief does); NEXT_STEPS:36's parenthetical lists six of the eight payloads (omits `CreateWallet`, `ImportKey`) while saying "becomes eight".

## B. Findings, most severe first

No blocking finding.

1. **should-fix** — `docs/security/threat_model.md:67` and `:98`. Assets row and TM-01 residual still describe Approach A as holding the key in a Dart `Uint8List`/"serialized into the signing input"; the built code keeps it only in a `calloc` staging buffer and a view over upstream's `TWData` (`signing_core.dart:130-131`, `secret_buffers.dart:106-139`, `DECISION-1-approach-a.md` §2). Fix: reword both cells to match the PRD §11.4 proposal A2 already drafted (none on the Dart heap; one SDK-allocated native buffer, zeroed and freed; upstream's own copies, incl. the unwiped Rust `TWData`, are the residual).
2. **should-fix** — `docs/plan/PROGRESS.md` (root), "Phase A/B" block. Stated times (06:30, 06:32-07:05, 06:35-06:50) contradict the commit timestamps (06:13-06:27 +0300) and the host clock; the block is the audit trail. Fix: replace with the commit timestamps or drop the times.
3. **should-fix (pre-existing, re-pushed)** — `tools/gen/bin/registry_transform.exe` (5.9 MB Mach-O arm64, tracked since `1d70c6c`, on all 11 branches). A compiled binary in a security-sensitive repo with no build provenance. Fix: `git rm --cached`, add `tools/gen/bin/*.exe` (or `*.exe`) to `.gitignore` in a bookkeeping commit before or right after the push; it is unreferenced by any script (gates use `dart run tools/gen/bin/registry_transform.dart`).
4. **should-fix (low)** — `docs/security/memory_contract.md`. DECISION-12.md:112 says the contract "is to cover all eight" secret-bearing payloads; it never names `ValidateMnemonic`, `ValidateMnemonicWord`, `SuggestMnemonicWords` (it covers the suggest path only via `WalletEngine.suggestMnemonicWords`, :76). Fix: one short paragraph listing the three requests and that they are `String`s dropped after use.
5. **nit** — `docs/decisions/DECISION-12.md:393` "section 3.2 (the four payloads)" unqualified; add "(eight since 2026-10-03)".
6. **nit** — `threat_model.md:103` TM-06 "the one reply type that may carry it": say "the only reply that carries a whole mnemonic".
7. **nit** — root `pubspec.yaml:22-23` double blank line and doubled newline at EOF from the T1.15 merge resolution.
8. **nit** — `integration/W2` `54d08b2` is a dead-end duplicate of content already in `6f7b520` (not an ancestor of W3/W5). Either merge it into W3 (merge-tree shows 0 conflicts) or do not push W2's new commit.
9. **nit** — `eval/approach-b` `tools/native_build/build_apple.sh` lacks the headerpad flag; carry it at the D1a merge.
10. **nit** — A2 exceeded its brief's owned paths (rule 11; disclosed); PROGRESS misattributes the "five → four" correction to NEXT_STEPS; NEXT_STEPS:36 lists six of eight payloads.
11. **UNPROVEN detail** — PROGRESS "T1.2-d1 … `test:native` 42 + 74 on the rebuilt host library": the script defaults to the pre-flag repo copy. Functionally irrelevant.

## C. Gate results (`integration/W5` @ `b07f593`, host Flutter 3.47.5 / Dart 3.13.4, `PATH` incl. `~/.pub-cache/bin`)

| Gate | Exit | Key counts | Matches expectation |
|---|---|---|---|
| `melos run analyze` | 0 | 11 packages, "No issues found!" each | yes |
| `melos run format:check` | 0 | 447 files, 0 changed | yes |
| `melos run test` | 0 | SDK **270**; bindings 64; native pkg 190; gen 3; inventory 29; lint 48; manifest 67; packaging_eval 178; probes 4; upstream 109; vectors 20 — all passed | yes (270) |
| `melos run test:native` | 0 | bindings **+42**, SDK **+74**, lib = `third_party/wcf-native/.../libTrustWalletCore.dylib` | yes (42 + 74) |
| `melos run inventory:check` | 0 | functions 466/466 missing 0; enums 19/19; inventory.json and symbol_names.dart up to date | yes |
| `melos run gen:check` | 0 | gen:ffi, gen:proto, gen:registry, gen:manifest ran; `git diff --exit-code` clean; no untracked generated files; `git status` empty afterwards | yes |
| `melos run lint:public-api` | 0 | **49 exported elements, 0 violations** | yes |
| `melos run vectors:validate` | 0 | files 2, vectors 5, exclusions 0 | yes |
| `melos run manifest:validate` | 0 | "Manifest is valid." | yes |
| `melos run probe:sign-json` ×2 + `cmp` | 0 / 0 | stdout identical; `git status` empty after both (regenerated `sign_json_coverage.md` == committed) | yes |
| (extra) `check_exports.sh` on post-flag dylib | 0 | 464/0/0 both arches, `_wcf_build_info` exported | yes |

Final `git status --short` after the whole sequence: empty; HEAD unchanged.

## D. Outside today's changes, but visible on push

- `tools/gen/bin/registry_transform.exe` (B.3) — the single most embarrassing tracked file.
- `.github/workflows/ci.yml:31,77` pin Flutter 3.44.1 while the host and all evidence are on 3.47.5 (known; T1.17).
- `docs/archive/wallet_core_flutter_prd_v1.1.md`: 12 rule-8 word hits (archived PRD; owner's call, already flagged in PROGRESS).
- `docs/audit-resaults/` directory name is misspelled.
- `docs/plan/briefs/*.md` and the audit doc on W5 embed absolute `/Users/yossefebrahim/...` paths (ten files); not secrets, but personal paths in a public repo.
- `docs/plan/` on W5 is stale relative to `main` (today's PROGRESS/NEXT_STEPS live on `main` only); the merge is clean, so this resolves in Phase C step 1.
- Loose ends not being pushed: worktrees `T1.6` (13), `T1.7` (19), `T1.19` (2), `T1.10` (1) still carry uncommitted files.

## E. Ready to push?

**Yes.** Every gate is green at the actual tip `b07f593` with a clean tree before and after (including `gen:check`), every number the plan promised reproduced exactly (SDK 270, native 42 + 74, lint 49/0, probe byte-identical), each of the ten commits and three merges contains only its allowed files, no tracked file violates the layout or `.gitignore` beyond the pre-existing `.exe`, and the one real bug fixed today (header padding) is demonstrated on the rebuilt library (56 B → 6168 B, 212-char id accepted, export gate 464/0). The findings are documentation accuracy (threat-model Approach A wording, the PROGRESS timeline) and housekeeping (the `.exe`, blank lines, the dead-end W2 commit) — none changes bytes CI verifies, and all can land as a follow-up bookkeeping commit without holding the push.
