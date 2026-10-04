<task>
You are the D1a checkpoint auditor for Phase 1 of wallet_core_flutter, an unofficial MIT-licensed Dart/Flutter SDK over the open-source Trust Wallet Core library (not affiliated with or endorsed by Trust Wallet). READ-ONLY: do not create, edit or delete any file; your only deliverable is your final message. Read-only git is allowed and required: the two packaging evaluations live on branches — `git show eval/option1:<path>` and `git show eval/option2:<path>` (both pushed, tips 4623cb6 and c52b3a7); `main` is 313b4e5.
Your job is adversarial: for each contested decision, defend the position the data supports, attack the other with evidence from the tables, and say what data would change your mind. The owner decides; you recommend.
</task>

<context>
PRD: docs/wallet_core_flutter_prd.md §12 (packaging, 11 measurement steps in §12.2), §15.3–§15.4, §18. Plan: docs/plan/phases/phase-1-m0-spike.md (D1a row), docs/plan/NEXT_STEPS.md Phase D table. Status: docs/plan/PROGRESS.md (bottom of "Phase A/B of NEXT_STEPS.md" log: the 2026-10-04 bullets). Decisions: docs/decisions/DECISION-9.md, DECISION-14.md (§10 build-time facts a–h awaiting ratification), DECISION-12.md; evidence on branches: `eval/option1:docs/decisions/DECISION-2-option1.md` (+ `eval/option1:eval/option1/results/table.md`, `run_eval.sh`, `README.md`, hook under `eval/option1:packages/wallet_core_flutter_native/hook/`), `eval/option2:docs/decisions/DECISION-2-option2.md` (+ `eval/option2:eval/option2/results/table.md`, `run_eval.sh`, `README.md`, `eval/option2:packages/wallet_core_flutter_native/android/build.gradle`, `ios/wallet_core_flutter_native.podspec`). Earlier reviews of both options: docs/plan/reviews/W5-packaging.md, docs/plan/reviews/phase-D-codex-debate.md (your predecessor's Phase D debate), docs/plan/reviews/plan-applied-opus-B.md.
Facts established 2026-10-04 (verify in the files): artifact set `as_4.8.0_001` published as draft release `native-4.8.0-001` (run 37211800874): Android arm64-v8a + x86_64 built from source with `-DFLUTTER=ON`, Apple slices relinked; `compat_manifest.json` on `main` filled; draft assets 404 anonymously (publishing creates the tag). Both evaluations ran on an arm64-v8a emulator (AVD wcf_api35, API 35) and the booted iOS simulator; no physical device, no x86_64 emulator (Apple-Silicon host), only Flutter 3.47.5 installed. Option 1: 126 rows, 83 pass / 0 fail / 16 skip / 27 unmeasured. Option 2: 116 rows, 71 pass / 1 fail (a deliberate c++_shared counterfactual) / 11 skip / 33 unmeasured.
</context>

<agreed_points>
1. Both options build debug and release APKs carrying the pinned `.so` bytes for arm64-v8a and x86_64, pass 16 KB LOAD and APK alignment, resolve 467 symbols at runtime on the emulator, verify identity `as_4.8.0_001`, and fail a flipped digest at build time with both digests shown — evidence: the two `table.md` files, steps 1, 2, 4, 7, 8.
2. Our Android library is `c++_static` (`DT_NEEDED` = liblog, libm, libdl, libc); it needs no `libc++_shared.so` — both §5 sections.
3. iOS simulator debug builds and runs pass under both; iOS device rows are build-only (no device, no signing identity); Option 2's xcframework recommendation (§6.4) predates the per-slice dylib set and must be re-read against what the set actually ships.
4. `armeabi-v7a` is not shipped (PRD §12.2 step 8).
</agreed_points>

<contested_points>
DECISION-2 — packaging option for the native package.
  Position A (Option 1, build hooks): one `CodeAsset` per target, no consumer Gradle/Podfile edits, offline/vendored/cache rules enforced in Dart, unknown config keys fail the build; a default `flutter build apk` (which includes android-arm) is refused with a remedy message; `android_libcpp_shared` adds an unpinned 2.37 MiB `libc++_shared.so` per app and silently overrides another plugin's copy (dropping the dependency is supported by the data); hooks depend on Flutter's native-assets runner (hooks_runner 1.5.0 in 3.47.5), which sets the Flutter floor; app-size delta +45.41 MiB; the 87-char install-name issue is fixed by headerpad.
  Position B (Option 2, Gradle task + podspec): Gradle chain `wcfPrepare<Variant>JniLibs → mergeJniLibFolders → mergeNativeLibs`, no consumer edits either, no `libc++_shared.so` shipped at all, +43.02 MiB; a default `flutter build apk` is NOT refused — it silently ships an `armeabi-v7a` slice without our library (32-bit-only devices fail at load); `abiFilters` does nothing; a future c++_shared set would need consumer `pickFirsts`; works on older Flutter (no hooks dependency); CocoaPods-based iOS integration (SPM question §7).
  Position C: "A now, B later" or shipping both — judge whether maintaining two packaging paths is defensible for a 0.1 alpha.
DECISION-6 — minimum Flutter/Dart. Only 3.47.5 was tried; declared floor `flutter >=3.44.0`, `sdk ^3.12.0`; 3.44.1 could not build iOS on Xcode 27 (template issue). Position A: pin the floor to the version actually measured (3.47.5) until a second SDK is tested. Position B: keep 3.44.0 declared, measure later. State what the hooks path requires at minimum and what Option 2 requires.
DECISION-14 ratification of the build-time facts in §10 a–h: (a) ABIs arm64-v8a + x86_64 only — ratify, or require armeabi-v7a (PRD §12.2 step 8) given the default-build failures above; (b) `-DFLUTTER=ON` patch of upstream's Gradle module; (c) `.dynsym` export gate; (d) the four JNI helper exports allow-listed; (e) BOOST_ROOT / licences / Xcode default; (f) a failed publish burns the set id; (g) comparison 2 (manifest hash) not run on the default `initialize()` path — option (i) embed manifest bytes at `gen:manifest` and check by default vs (ii) amend the decision; (h) `TBD-T3.11` release_set and the draft-release 404 — should `native-4.8.0-001` be published (tag) now, or stay draft until D6?
</contested_points>

<questions>
0. Threat model (mandatory): which rows of docs/security/threat_model.md (v0.2) change owner, mitigation or residual risk depending on the DECISION-2 outcome (TM-13, TM-14, TM-16, TM-33…TM-36 at least)? Name them per option.
1. For each of PRD §12.2's eleven steps, compare the two tables cell by cell for Android and iOS: where do the options differ in result (not just in wording)? Produce the diff as a table.
2. The default-build behaviour (Option 1 refuses; Option 2 silently ships a broken 32-bit slice): which is correct for consumers, and is there a third behaviour (hook emits nothing for an unshipped ABI; Gradle task reads `-Ptarget-platform` and refuses) that D1a should order instead?
3. Consumer setup cost and failure UX: read §8 of both docs and the hook/Gradle error paths; which produces the clearer failure on wrong digest, placeholder manifest, offline miss, unsupported ABI?
4. Hooks maturity risk: what in Flutter 3.47.5's native-assets support is still experimental or flag-gated, and what does that mean for a public alpha? Cite the evaluation's own notes (hooks_runner versions, `includeParentEnvironment: false`, `lipo` slice handling) rather than general knowledge; label inferences.
5. What remains UNPROVEN for both options after today (physical devices, x86_64 emulator, AAB, second Flutter, cold Gradle cache, published release download path) and which of those must be closed before DECISION-2 is final versus before Phase 1 closes?
6. Anything in either evaluation that looks like a measurement error or an overclaim (e.g. app-size deltas measured against which baseline; "pass" rows whose command does not prove the claim).
</questions>

<grounding_rules>
Ground every claim in a file path (with branch for branch files) and line numbers, a table cell, or pasted command output. Label inferences. Say UNPROVEN rather than guess. Do not propose new product scope. No file writes, no git write operations, no workflow dispatch, no other agents.
</grounding_rules>

<structured_output_contract>
Report in exactly this shape:
  A. Recommendation per contested decision (DECISION-2, DECISION-6, DECISION-14 a–h): the position you defend, the three strongest data points for it, the strongest point against it, and what evidence would flip you.
  B. The step-by-step comparison table (question 1).
  C. Answers to questions 0, 2–6, each with evidence.
  D. Findings on the evaluations themselves, each with severity (blocking / should-fix / nit), file:line (branch), description, suggested fix.
  E. The exact list of items the owner must decide at D1a, in dependency order, each with your recommended answer in one line.
  F. One paragraph: is Phase 1 ready to proceed to T1.16b on the recommended option? Yes/No and the single most important reason.
</structured_output_contract>
