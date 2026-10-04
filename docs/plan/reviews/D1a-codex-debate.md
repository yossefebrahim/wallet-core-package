# D1a debate — Codex gpt-5.5 (xhigh, read-only), second of two, 2026-10-04

Brief: docs/plan/briefs/DEBATE-D1a.md (updated to tips eval/option1 3ba7826, eval/option2 de63ff5, main 2466ab3). Thread 01a10879-3dcd-76f2-9fb7-4ffce74351d5. Report verbatim; section G contrasts with D1a-opus-debate.md. Orchestrator triage in PROGRESS.md.

A. Recommendation Per Contested Decision

**DECISION-2: choose Option 2, but only after a blocking default-ABI refusal fix. Do not ship both paths for 0.1 alpha.**

I defend Option 2 with a required gate: Gradle must read `-Ptarget-platform` and fail when Flutter asks for `android-arm`, matching Option 1’s fail-loud UX.

Three strongest data points:

1. Option 2 is the conventional Flutter plugin path and needs no consumer Gradle edits: its Gradle chain is measured as `wcfPrepare<Variant>JniLibs -> mergeJniLibFolders -> mergeNativeLibs` with targeted Android builds passing (`eval/option2:docs/decisions/DECISION-2-option2.md:112-115`).
2. Option 2 ships no `libc++_shared.so`, while Option 1 currently adds an unpinned 2.37 MiB shared C++ runtime that is not needed by this artifact set (`eval/option1:docs/decisions/DECISION-2-option1.md:170-175`; `eval/option2:docs/decisions/DECISION-2-option2.md:207-221`).
3. Option 2 handles iOS packaging and privacy as CocoaPods artifacts/script phases, while Option 1 documents that hooks cannot ship `PrivacyInfo.xcprivacy` and require a consumer Runner edit (`eval/option2:packages/wallet_core_flutter_native/ios/wallet_core_flutter_native.podspec:172-209`; `eval/option1:docs/decisions/DECISION-2-option1.md:187-205`).

Strongest point against: current Option 2 silently builds a default APK with an `armeabi-v7a` slice missing `libTrustWalletCore.so` (`eval/option2:docs/decisions/DECISION-2-option2.md:115`, `:341-347`). That is blocking.

Evidence that would flip me: if the Option 2 Gradle refusal cannot be implemented without consumer edits, or if SPM deprecation becomes an immediate blocker before a zip/path solution exists, Option 1 becomes the safer alpha path after dropping `android_libcpp_shared`.

**DECISION-6: pin the floor to what was measured: Flutter 3.47.5.**

Three strongest data points:

1. PRD step 6 says the minimum supported Flutter/Dart version must come from measurement, not declaration (`docs/wallet_core_flutter_prd.md:245`).
2. Both evaluations only proved Flutter 3.47.5 (`eval/option1:docs/decisions/DECISION-2-option1.md:144-152`; `eval/option2:docs/decisions/DECISION-2-option2.md:182-191`).
3. Flutter 3.44.1 could not build iOS on the Xcode 27 host, so it is not a proved floor (`docs/plan/PROGRESS.md:353-357`).

Strongest point against: Option 2’s `ffiPlugin` mechanism likely supports older Flutter versions, but that is explicitly UNPROVEN (`eval/option2:docs/decisions/DECISION-2-option2.md:193-199`).

Evidence that would flip me: a clean Android+iOS measurement on Flutter 3.44.x with the selected packaging path.

**DECISION-14 a-h**

| Item | Recommendation | Evidence |
|---|---|---|
| a | Ratify `arm64-v8a` + `x86_64` only; do not add `armeabi-v7a`; fix default builds by refusal. | PRD asks to decide ABI support, not require 32-bit (`docs/wallet_core_flutter_prd.md:247`); manifest contains only Android arm64/x86_64 (`compat_manifest.json:79-124`). |
| b | Ratify `-DFLUTTER=ON`, but record it per artifact. | Awaiting ratification in `docs/decisions/DECISION-14.md:350`; threat row TM-33 tracks this as a supply-chain fact (`docs/security/threat_model.md:145`). |
| c | Ratify `.dynsym` export gate. | `docs/decisions/DECISION-14.md:351`; stripped `.so` made static symtab insufficient (`eval/option1:docs/decisions/DECISION-2-option1.md:278`). |
| d | Ratify the four JNI helper exports allow-listed exactly. | `docs/decisions/DECISION-14.md:352`; TM-34 tracks the risk (`docs/security/threat_model.md:146`). |
| e | Ratify BOOST/license/Xcode facts, with exact toolchain recorded. | `docs/decisions/DECISION-14.md:353`; manifest carries Xcode/toolchain metadata (`compat_manifest.json:28-31`, `:68-71`, `:131-135`). |
| f | Ratify that a failed publish burns the set id. | `docs/decisions/DECISION-14.md:354`. |
| g | Choose option i: embed manifest bytes at `gen:manifest` and check comparison 2 by default. | Current default `initialize()` does not run comparison 2 (`docs/decisions/DECISION-14.md:355`); TM-16 calls this out (`docs/security/threat_model.md:144`); PRD expects manifest/release mismatch to fail initialize (`docs/wallet_core_flutter_prd.md:381-386`). |
| h | Publish `native-4.8.0-001` now after owner ratifies facts. | Draft assets 404 anonymously and block hosted/network fetch proof (`docs/plan/PROGRESS.md:334`; `eval/option1:docs/decisions/DECISION-2-option1.md:287`; `eval/option2:docs/decisions/DECISION-2-option2.md:353`). |

B. Step-By-Step Comparison Table

| PRD §12.2 step | Android difference | iOS difference | Evidence |
|---|---|---|---|
| 1. Consumer integration | Both pass targeted builds without consumer edits. Option 1 refuses default ABI; Option 2 currently succeeds with broken `armeabi-v7a`. | Option 1 cannot ship privacy manifest; Option 2 ships via podspec. | O1 `eval/option1:docs/decisions/DECISION-2-option1.md:63`; O2 `eval/option2:docs/decisions/DECISION-2-option2.md:90`, `:115`; O1 privacy `:187-205`; O2 podspec `eval/option2:packages/wallet_core_flutter_native/ios/wallet_core_flutter_native.podspec:172-209`. |
| 2. Device/sim run | Both pass arm64-v8a emulator runtime and symbol probe. x86_64 emulator UNPROVEN. | Both pass booted simulator. Physical iPhone UNPROVEN. | O1 `:64`, `:66-67`; O2 `:91`, `:93-94`; unproven O1 `:233-242`, O2 `:301-312`. |
| 3. Release/profile builds | Both pass targeted release APK. AAB UNPROVEN. | Archives/build-only rows exist; signed device/App Store path UNPROVEN. | O1 `:65`, `:288`; O2 `:92`, `:310`; iOS O1 `:76-78`, O2 `:103-105`. |
| 4. Runtime identity/symbols | No material difference; both resolve 467 symbols and identity `as_4.8.0_001`. | No material difference on simulator. | O1 `:66-67`; O2 `:93-94`. |
| 5. Size | Option 2 is smaller: +43.02 MiB vs Option 1 +45.41 MiB. | No decisive measured difference. | O1 `:68-69`; O2 `:95-96`. |
| 6. Minimum Flutter/Dart | No option proves 3.44.x. Option 1 has hooks dependency risk; Option 2 has older-plugin possibility but UNPROVEN. | Same. | O1 `:70-71`, `:144-152`; O2 `:97-98`, `:182-199`. |
| 7. Offline/cache/checksum | Both fail wrong digest with both digests shown. Option 1 has clearer hook-level fetch UX; Option 2 routes through Gradle/pod tooling. | Option 2’s podspec path is measured; Option 1 hook iOS fetch is measured but privacy remains separate. | O1 `:72`, acquire errors `eval/option1:packages/wallet_core_flutter_native/hook/src/acquire.dart:244-343`; O2 `:99`, `:132-135`. |
| 8. ABI/alignment | Both pass 16 KB LOAD and APK alignment for shipped ABIs. Option 1 refuses default ABI; Option 2 currently silent-broken. | Not applicable. | O1 `:73-74`, targets `eval/option1:packages/wallet_core_flutter_native/hook/src/targets.dart:113-123`; O2 `:100-101`, `:341-347`. |
| 9. C++ runtime conflict | Option 2 wins for current artifacts: ships none. Option 1 ships unnecessary unpinned `libc++_shared.so` unless dependency is dropped. | Not material. | O1 `:75`, `:170-175`; O2 `:102`, `:207-221`. |
| 10. Privacy/signing/iOS packaging | Android no material difference. | Option 2 wins because podspec includes privacy bundle and script phases; Option 1 requires consumer privacy file edit. | PRD `docs/wallet_core_flutter_prd.md:249`; O1 `:187-205`; O2 `:169`, podspec `:172-209`. |
| 11. Hosted package | Both are incomplete: mostly `pub get`/loopback proof, not full hosted build. | Same. | O1 `:79`; O2 `:106`, `:317-319`. |

C. Answers To Questions 0, 2-6

**0. Threat model rows changed by DECISION-2**

TM-13 changes owner/mechanism: Option 1 relies on native-assets hook path conventions and loader naming (`docs/security/threat_model.md:141`; `eval/option1:docs/decisions/DECISION-2-option1.md:191-195`). Option 2 relies on Gradle JNI folders and CocoaPods framework/script phases (`eval/option2:packages/wallet_core_flutter_native/ios/wallet_core_flutter_native.podspec:8-35`).

TM-14 changes mitigation surface: Option 1 does double digest checks in the Dart hook with filtered environment (`eval/option1:packages/wallet_core_flutter_native/hook/src/acquire.dart:7-33`, `:156-190`). Option 2 does two-pass acquisition into Gradle/pod work dirs and locks iOS work (`eval/option2:packages/wallet_core_flutter_native/tool/option2/verified_acquisition.dart:14-38`). Both still carry draft-release 404 risk until publish (`docs/security/threat_model.md:142`; `docs/plan/PROGRESS.md:334`).

TM-16 does not become acceptable under either option until comparison 2 runs by default (`docs/security/threat_model.md:144`, `:259-266`; `docs/decisions/DECISION-14.md:355`).

TM-33 and TM-34 are independent of packaging choice but must be ratified because both options consume the same patched artifacts and JNI allow-list (`docs/security/threat_model.md:145-146`).

TM-35 is Option 1-specific if `android_libcpp_shared` remains (`docs/security/threat_model.md:147`, `:160`; `eval/option1:docs/decisions/DECISION-2-option1.md:170-175`). Option 2 closes that row for the current artifact set.

TM-36 changes by gate placement: Option 1 hooks run during ordinary Flutter builds/tests (`eval/option1:docs/decisions/DECISION-2-option1.md:184`); Option 2 packaging is exercised by Gradle/pod builds. The selected option must add CI gates for default ABI, hosted fetch, AAB, and runtime probes (`docs/security/threat_model.md:206`).

**2. Default-build behavior**

Correct behavior is fail loud at build time with a remedy. Option 1 already does that for unsupported Android ABI (`eval/option1:packages/wallet_core_flutter_native/hook/src/targets.dart:113-123`). Option 2 must be changed to inspect `-Ptarget-platform` and refuse `android-arm`; the evaluation confirms Flutter passes that property and `abiFilters` does not solve the issue (`eval/option2:docs/decisions/DECISION-2-option2.md:341-347`). “Emit nothing” is not acceptable because it recreates the same runtime load failure.

**3. Consumer setup cost and failure UX**

Wrong digest: both are acceptable, with Option 1 clearer in raw hook output because it prints a first-line Xcode `error:` and both digests (`eval/option1:packages/wallet_core_flutter_native/hook/src/acquire.dart:244-300`). Option 2 reports through Gradle/pod tooling but still measures wrong-digest failure (`eval/option2:docs/decisions/DECISION-2-option2.md:99`, `:132-135`).

Placeholder manifest/offline miss: Option 1 has direct remedy text in the hook (`eval/option1:packages/wallet_core_flutter_native/hook/src/acquire.dart:316-343`). Option 2 measures placeholder/wrong-cache blockers through Gradle and pod install (`eval/option2:docs/decisions/DECISION-2-option2.md:132-135`, `:166`).

Unsupported ABI: Option 1 is currently much clearer. Option 2 is currently unsafe because it succeeds (`eval/option2:docs/decisions/DECISION-2-option2.md:115`, `:341-347`). After the required Gradle refusal fix, the setup cost is better under Option 2 because it avoids hook-specific dependencies and avoids the iOS privacy manual edit.

**4. Hooks maturity risk**

The evaluation’s own facts show the hook path depends on Flutter native-assets runner behavior: hooks runner versions are recorded as part of the Option 1 run (`eval/option1:docs/decisions/DECISION-2-option1.md:144-152`), hook options avoid parent environment because the hook environment is filtered (`eval/option1:packages/wallet_core_flutter_native/hook/src/hook_options.dart:6-10`), and iOS bundling depends on Flutter path/name conventions rather than a stable protocol (`eval/option1:docs/decisions/DECISION-2-option1.md:191-195`). Inference: this is usable for an alpha only with a measured Flutter floor and repeated checks on each stable Flutter release. It is not enough to declare 3.44.0.

**5. UNPROVEN items**

Before DECISION-2 is final: selected path must prove default-ABI behavior, AAB behavior, hosted/published release fetch, and the selected iOS packaging path with the real manifest.

Before Phase 1 closes: physical Android, physical iPhone, x86_64 emulator runtime, second Flutter SDK, cold Gradle cache, signed iOS/archive validation, AAB alignment, and full hosted consumer build remain UNPROVEN (`eval/option1:docs/decisions/DECISION-2-option1.md:233-242`; `eval/option2:docs/decisions/DECISION-2-option2.md:301-312`).

**6. Measurement errors or overclaims**

Step 11 is overclaimed: both mostly prove hosted `pub get`, not a full hosted app build (`eval/option1:docs/decisions/DECISION-2-option1.md:79`; `eval/option2:docs/decisions/DECISION-2-option2.md:317-319`).

AAB is unmeasured despite PRD step 3 including APK/AAB release builds (`docs/wallet_core_flutter_prd.md:242`; `eval/option1:docs/decisions/DECISION-2-option1.md:288`; `eval/option2:docs/decisions/DECISION-2-option2.md:310`).

Option 2’s xcframework discussion is stale against the current manifest, which ships per-slice iOS dylibs and no xcframework zip (`compat_manifest.json:18-78`; `eval/option2:docs/decisions/DECISION-2-option2.md:241-270`).

D. Findings On The Evaluations

| Severity | Location | Finding | Suggested fix |
|---|---|---|---|
| blocking | `eval/option2:docs/decisions/DECISION-2-option2.md:115`, `:341-347` | Option 2 default `flutter build apk` exits 0 while shipping an `armeabi-v7a` slice without the library. | Add Gradle refusal using `-Ptarget-platform`, or build/test `armeabi-v7a`. |
| blocking if Option 1 chosen | `eval/option1:docs/decisions/DECISION-2-option1.md:187-205` | Option 1 requires a consumer iOS privacy manifest edit. | Do not choose Option 1 unless packaging can ship privacy metadata without consumer native edits. |
| should-fix | `eval/option1:packages/wallet_core_flutter_native/pubspec.yaml:22-42`; `eval/option1:docs/decisions/DECISION-2-option1.md:170-175` | Option 1 includes unnecessary unpinned `android_libcpp_shared`. | Drop the dependency for the current `c++_static` artifact set. |
| should-fix | `eval/option2:docs/decisions/DECISION-2-option2.md:317-319` | Hosted package proof does not build a hosted consumer app. | Keep the local hosted repo alive through build, or test from a real published package. |
| should-fix | `eval/option2:docs/decisions/DECISION-2-option2.md:241-270`; `compat_manifest.json:18-124` | Option 2’s xcframework recommendation assumes an artifact not present in the current manifest. | Rewrite as future work or add the actual zip artifact. |
| should-fix | `eval/option1:docs/decisions/DECISION-2-option1.md:288`; `eval/option2:docs/decisions/DECISION-2-option2.md:310` | AAB remains unmeasured. | Run `flutter build appbundle` and alignment checks for the selected path. |
| nit | `docs/security/threat_model.md:206`; `docs/plan/PROGRESS.md:334` | TM-36 is stale relative to later CI/native artifact progress. | Refresh threat model after D1a selection. |

E. Owner Decisions At D1a

1. Ratify DECISION-14 a-f: yes, with exact patch/toolchain metadata recorded.
2. DECISION-14 g: embed manifest bytes at generation time and verify by default.
3. DECISION-14 h: publish `native-4.8.0-001` after ratifying the artifact facts.
4. ABI policy: ship only `arm64-v8a` and `x86_64`; unsupported default `android-arm` must fail at build time.
5. DECISION-2: choose Option 2 after the default-ABI refusal fix; do not maintain two packaging paths for alpha.
6. DECISION-6: set minimum to Flutter 3.47.5 until another SDK is measured.
7. If any Option 1 code remains: drop `android_libcpp_shared`.
8. Phase-1 closure gates: require x86_64 runtime, AAB, physical devices, signed iOS validation, and full hosted fetch/build.

F. Phase 1 Readiness

No, not directly ready to proceed to T1.16b on my recommended option. The single most important reason is that Option 2 currently allows a default consumer APK build to succeed while silently omitting the native library from the 32-bit slice; T1.16b should validate a consumer-safe path, not memorialize that failure mode.

G. Agreement And Disagreement With Opus Audit

I agree with Opus that the Flutter floor should be pinned to measured 3.47.5, not declared 3.44.0 (`docs/plan/reviews/D1a-opus-debate.md:46-64`). I also agree on ratifying the two-ABI set, publishing the draft release after fact ratification, rejecting “emit nothing,” and treating hosted-consumer proof as incomplete (`docs/plan/reviews/D1a-opus-debate.md:67-76`, `:116-121`, `:164`).

I disagree on DECISION-2. Opus recommends Option 1 now (`docs/plan/reviews/D1a-opus-debate.md:11-19`); I recommend Option 2 after the default-ABI refusal fix. The reason is that Option 1’s biggest advantage, fail-loud unsupported ABI behavior, is transferable to Option 2 because the evaluation proves Gradle can see `-Ptarget-platform` (`eval/option2:docs/decisions/DECISION-2-option2.md:341-347`). Option 1’s iOS privacy-manifest gap is not similarly solved by documentation; it requires a consumer native edit (`eval/option1:docs/decisions/DECISION-2-option1.md:187-205`), while Option 2 already packages the privacy bundle (`eval/option2:packages/wallet_core_flutter_native/ios/wallet_core_flutter_native.podspec:172-178`).

I also disagree with Opus on DECISION-14 g. Opus prefers amending the decision until T3.11 (`docs/plan/reviews/D1a-opus-debate.md:75`, `:189`); I prefer embedding manifest bytes and checking by default because TM-16 explicitly names the default-path gap (`docs/security/threat_model.md:144`) and PRD §15.4 expects initialize-time mismatch failure (`docs/wallet_core_flutter_prd.md:381-386`).

One caution: Opus audited older branch tips (`docs/plan/reviews/D1a-opus-debate.md:3`). Some of its findings are now stale after the `-d2` hygiene commits, especially row classification and counts; the current Option 2 document records 116 rows with 71 pass, 2 fail, 10 skip, and 33 unmeasured (`eval/option2:docs/decisions/DECISION-2-option2.md:83-87`).