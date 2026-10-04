# D1a debate — Opus 5.5 auditor (first of two), 2026-10-04, read-only

Brief: `docs/plan/briefs/DEBATE-D1a.md`. Inputs: `eval/option1` 4623cb6, `eval/option2` c52b3a7, `main` 313b4e5. Report verbatim below; the Codex pass follows in `D1a-codex-debate.md`; orchestrator triage in `PROGRESS.md`.

---

**D1a audit (first of two): DECISION-2, DECISION-6 and DECISION-14 §10 a–h**

## A. Recommendations

### DECISION-2: Position A, Option 1 (build hooks), with conditions

I reject Position C as "ship both". Keeping `eval/option2` unmerged as a fallback costs nothing and is fine.

Conditions:
- Drop `android_libcpp_shared`.
- Keep the build-time refusal of unshipped ABIs.
- The record stays provisional until one networked, hosted consumer build passes on Android and iOS against the published release (T1.16b).

Three strongest data points:
1. **Option 2's iOS half has an announced end of life, and its successor cannot do what PRD §12.3 requires.**
   - Flutter 3.44.1 and 3.47.5 both print, for this plugin: "This will become an error in a future version of Flutter" (`eval/option2:docs/decisions/DECISION-2-option2.md:170`, `:268`).
   - The SPM replacement cannot run the fetch tool, has no `--vendored`/`--offline` equivalent, and needs a published `xcframework.zip` (`:268`). The published set has no such zip: `compat_manifest.json` lists only the five per-slice `.dylib`/`.so` keys.
2. **Option 1 has the smaller integrity surface.**
   - It bundles only bytes it hashed in memory (`eval/option1:docs/decisions/DECISION-2-option1.md:21`).
   - Configuration comes only from the app's checked-in `pubspec.yaml`. Unknown keys are refused (`:37`, `hook/src/hook_options.dart:86-92`), and hooks run with a filtered environment (`:25`).
   - Option 2 instead:
     - writes into the shared pub-cache pod directory and leaves a replacement window it cannot see (`DECISION-2-option2.md:287`);
     - lets an ambient environment variable replace the integrity root (`ios/wallet_core_flutter_native.podspec:76-79`, `:199`; `android/build.gradle:198-202`).
3. **Option 1 fails loudly; Option 2 fails silently; every shared row is equal or better under Option 1.**
   - A default `flutter build apk` stops at the hook with the remedy (`eval/option1:eval/option1/results/table.md:230`). Under Option 2 it exits 0 and ships an `armeabi-v7a` slice without our library (`eval/option2:eval/option2/results/table.md:188`).
   - Every other shared row has the same result in both options (§B).
   - The iOS release app is 2.52 MiB smaller under Option 1: +16.51 vs +19.03 MiB, because Flutter strips the dylib (option1 `table.md:15`, option2 `DECISION-2-option2.md:96`).
   - Android differs only by the unneeded `libc++_shared.so`: 45.41 − 43.02 = 2.39 MiB, against 2.37 MiB for that file.

Strongest point against Option 1: it has no way to ship `PrivacyInfo.xcprivacy` (`DECISION-2-option1.md:185`; option1 `table.md:309`, "no PrivacyInfo.xcprivacy in the framework"). Every iOS consumer must add one to the Runner target by hand before submitting to the App Store. That is a manual native edit, and it leaves step 10's "add a PrivacyInfo.xcprivacy" undone by the package. Option 2 ships the file (`DECISION-2-option2.md:105`, "framework present, pod bundle present").

What would flip me:
- A signed archive validated by App Store Connect that rejects an Option 1 app even with an app-level privacy manifest.
- A networked build through the hook failing behind a proxy because the hooks runner filters the environment. Whether proxy variables reach the hook is **UNPROVEN**.
- A Flutter stable release that changes the framework naming, the per-architecture `lipo`, or the `user_defines` JSON shape this hook depends on (`DECISION-2-option1.md:192`, `:214`; `hook/build.dart:201-209`).
- Flutter publicly committing to keep CocoaPods support indefinitely.

**On Position C:** the PRD's reason for a fallback is "works on older Flutter". That reason is gone: both branches declare `flutter: ">=3.44.0"` and `sdk: ^3.12.0` (both pubspecs), so pub refuses either one on older Flutter. Shipping both doubles every M0 device row while neither option has a single physical-device row. *Inference:* one package version carrying both a hook and an `ffiPlugin` would bundle the library twice.

### DECISION-6: Position A, set the floor to the version actually measured

Data:
1. Only 3.47.5 was measured, in both tables (option1 `table.md:17`, option2 `DECISION-2-option2.md:98`).
2. PRD §12.2 step 6 says "set the SDK's environment constraints from that measurement, not from assumption".
3. 3.44.1 was measured to build **no** iOS app on Xcode 27.0 (option2 `:180`; option1 `:148`). CI already pins 3.47.5 (`.github/workflows/ci.yml:31`, `:77`), so `>=3.44.0` is tested nowhere.

Against: there is partial 3.44.1 evidence.
- The Option 1 hook ran end to end in a host `flutter test` on 3.44.1 (option1 `:181`, "the same on Flutter 3.44.1 and 3.47.5").
- Option 2 reached `pod install` on 3.44.1 (option2 `:197`).
- Android builds on 3.44.x are not blocked by Xcode at all.

What would flip me: a step-1 build and emulator run on 3.44.x. The Android half can be measured on this host without an older Xcode.

Minimums:
- **Hooks path:** its dependencies allow Dart 3.10 / Flutter 3.38 (`hooks` 2.0.2, `code_assets` 1.2.1, option1 `:145`). But the `flutter_tools` behaviour it relies on changed between 3.44.1 and 3.47.5: the native-asset framework's `MinimumOSVersion` went from 13 to 15 (`:150`, `:184`).
- **Option 2:** Flutter 3.0 for `ffiPlugin`, by documentation only. The first AGP version with the Variant API it uses and the first CocoaPods with `always_out_of_date` are `[UNVERIFIED]` (option2 `:193-194`).
- Both are capped today by the package's own `sdk: ^3.12.0` (Flutter 3.44, option2 `:195`).

### DECISION-14 §10 a–h

| Item | Recommendation | Key data | Strongest point against | What would flip it |
|---|---|---|---|---|
| a. ABIs | **Ratify** `arm64-v8a` + `x86_64`; do not require `armeabi-v7a`. Condition: `x86_64` gets a runtime run before Phase 1 closes, or is dropped | PRD step 8 allows dropping an ABI; no 32-bit test target exists; `x86_64` is shipped but never run (`unmeasured no x86_64 emulator here` in both tables), which PRD step 8's own rule ("run the flow on every shipped ABI or drop the ABI") forbids | 32-bit-only apps cannot adopt the SDK | A consumer needing 32-bit and a 32-bit device to test on |
| b. `-DFLUTTER=ON` | **Ratify the patch; correct the record.** §10b says "the patch is logged in the artifact record", but `tools/native_build/emit_artifact_record.sh` has no field for it (threat model TM-33 residual) | `build_android.sh:368-371`, the build fails if the patch does not apply; it is upstream's own switch | It exports every symbol upstream leaves visible (39,085 defined) | An upstream build that exports the C API without the patch |
| c. `.dynsym` gate | **Ratify** | Reading `.symtab` gave a false `0/464` on the stripped `.so` (option1 `:276`) | — | — |
| d. Four JNI exports | **Ratify** | The list is exact and none of the four is in the bindings (threat model TM-34) | They are callable by anything in the process | A fifth name appearing |
| e. BOOST_ROOT / licences / Xcode | **Ratify as operational facts**, after one check | The workflow default is Xcode `26.3.0` (`build-native.yml:81`), but the Apple record says SDK `iphoneos26.2`, build `17C529`. Confirm the record describes the Xcode actually selected (**UNPROVEN**) | — | — |
| f. Failed publish burns the set id | **Ratify**; fix the stale sentence "No run has yet reached the publish job" (run 37211800874 created the draft release) | Matches DECISION-14 §3.1 and §4.4 immutability | Sequence numbers get used up | — |
| g. Comparison 2 | **Option (ii):** amend §2.3 to make it opt-in until T3.11. Reject (i) as written | Under (i) one generator writes both the bytes and their hash, so the runtime compares a constant with a constant. The runtime cannot read the asset in the worker isolate (`generated/manifest.dart:16-19`). An attacker who can edit the pub cache can edit both | DECISION-12 `Init` already carries optional manifest bytes, so a UI-isolate asset read is possible | A threat in which the asset and the compiled constants drift apart without an attacker able to edit both |
| h. Release `native-4.8.0-001` | **Publish now** (the owner creates the tag) | The networked fetch, which is step 7's only allowed network use, has never run for either option; a fresh Option 1 consumer and this package's own macOS `flutter test` get HTTP 404 today (option1 `:285`); the retention promise attaches to *package* versions (§3.2), so publishing commits to nothing new | The tag is permanent | A defect in `as_4.8.0_001` found first (a new set id is cheap, item f) |

## B. Step-by-step comparison (PRD §12.2)

| Step | Android: Option 1 | Android: Option 2 | iOS: Option 1 | iOS: Option 2 | Results differ? |
|---|---|---|---|---|---|
| 1 build (`--target-platform`) | pass, debug and release | pass | sim debug, device debug, archive: pass | same three: pass; load command in `Runner.debug.dylib` / `Runner` | No |
| 1 default-ABI build | **build refused, with remedy** (cell reads "skip") | **exit 0, `armeabi-v7a` slice without our `.so`** (cell reads "skip") | — | — | **Yes**, and the identical "skip" cells hide it |
| 2 run | arm64 emulator debug and release pass; x86_64 and devices unmeasured | same | sim debug pass, via framework path | sim debug pass, via `ProcessLibrary` | No (mechanism differs) |
| 3 release launch and sign | pass (debug keystore) | pass | unmeasured | unmeasured | No |
| 4 symbols | 464/464, 39,085 / 39,081, 4 allowed extras; 467 resolved at run time | identical | 464/464, 29,434 / 30,002; 467 resolved | identical | No |
| 5 library size | 20.81 / 22.19 MiB | identical | device 18.81 MiB (input); **16.50 MiB packaged** (Flutter strips) | 18.95 MiB (assembled, +154,376 B signature) | **Yes**, iOS |
| 5 app delta | **+45.41** MiB | **+43.02** MiB | release **+16.51**, sim **+39.39** MiB | release **+19.03**, sim **+39.48** MiB | **Yes** (Android: `libc++` 2.37 MiB; iOS: strip 2.52 MiB) |
| 6 floor | "pass builds on 3.47.5 (only version tried)" | "unmeasured only Flutter 3.47.5 tried" | same as Android | same as Android | No; same data, different label |
| 7 offline | pass (empty cache, vendored); socket **not observed** | pass, plus **socket denied** for the prepare step | pass (sim and archive), socket not observed | pass, plus `pod install` with socket denied | **Yes** (strength of evidence) |
| 7 wrong digest | fails; first Gradle line shows both digests | fails in `wcfPrepareDebugJniLibs`, both digests | Xcode error line, both digests | `pod install` fails; the script phase catches a later manifest change | No |
| 7 placeholder manifest | **not measured in a build** (unit test only) | measured: exit 2, 14 blockers | not measured in a build | measured: exit 2, 6 blockers | **Yes** (evidence) |
| 8 16 KB | 3 LOAD @ 0x4000; APK 7/8 entries, 0 off | 3 LOAD; APK 5/6, 0 off | — | — | No (entry count = `libc++`) |
| 9 `libc++` | one copy, **ours (NDK 28.2) silently replaces the plugin's (NDK 28.0)** | one copy, **the plugin's**; we ship none; a `c++_shared` counterfactual fails without `pickFirsts` | — | — | **Yes** |
| 10 per-slice | min 13.0 / 14.0 / 13.0, 464, 2 categories | identical | — | — | No |
| 10 duplicate symbols | — | — | device only, 4 libraries, 0 duplicates; sim unmeasured | device + both sim slices, 5 libraries, 0 duplicates | Coverage only |
| 10 privacy manifest | — | — | **absent; consumer must add one** | **present** | **Yes** |
| 11 hosted | `pub get` only, no build | same | same | same | No |

## C. Answers

**Q0: Threat rows that depend on the DECISION-2 outcome**

| Row | Under Option 1 | Under Option 2 |
|---|---|---|
| TM-13 (library path hijacking) | iOS/macOS open the framework by path (`code_asset_locations.dart:72-96`). *Inference:* symbol lookup is limited to that image. If another package emits a same-named library, Flutter renames one `TrustWalletCore1.framework` (`:192`): detected by the identity check, not prevented. *Inference:* the app module's native-assets copy silently wins a same-named `.so` (by analogy with step 9) | iOS resolves through `ProcessLibrary` first (`:68`; `library_location.dart:205`). *Inference, unmeasured:* that is a lookup across the whole process, so `TW*` could resolve from another image while `wcf_build_info` resolves from ours and the identity check passes. A duplicate `.so` fails the build (`table.md:252`) |
| TM-14 (substitution in transit) | Download inside the hook; two checks, bytes kept in memory; per-app cache by default; a shared `cache_dir` lets apps evict each other (`:200`); proxy reach **UNPROVEN** | Download in `pod install` / Gradle. The iOS pod directory is in the pub cache, and the window between the script phase and linking is open (`:287`). iOS bytes are assembled on the consumer's machine (`:233`); Option 1's are also modified, by Flutter's strip and re-sign, so that part is parity |
| TM-16 (manifest tampering) | Override only through checked-in `user_defines`; logged as "a manifest override" (`build.dart:193`) | `WCF_MANIFEST` env var or Gradle property: an ambient, untracked override. Mitigation: the script phase re-checks the manifest's sha against the stamp on every build |
| TM-28 (dependency risk) | Third-party build-time code runs in every consumer build: `hooks`, `code_assets`, `android_libcpp_shared`, `native_toolchain_c`, `glob`. *Inference:* `lint:runtime-deps` would flag them, since its allow list does not include them (`tools/lint/lib/runtime_deps_check.dart:29-47`) | Our own Groovy and Ruby run in consumer builds; CocoaPods is required |
| TM-35 (undigested `libc++_shared.so`) | Open: an unpinned file, ours replacing other plugins'. Dropping the dependency closes the row | Does not apply. A future `c++_shared` set would need the consumer's `pickFirsts`, which picks by merge order |
| TM-36 (gates not enforced by CI) | The hook runs in every macOS `flutter test`, so packaging is exercised without devices, but those runs need the release published or a vendored set | Packaging runs only in device or simulator builds; CI's device jobs are still placeholders |
| TM-33, TM-34 | Unchanged by the option (artifact build) | Unchanged |

The threat model itself is stale: line 9 and TM-14 / TM-16 (`:142`, `:144`) still say no artifact set exists and that the identity is a placeholder. That stopped being true at f9f3d58.

**Q2: Default-build behaviour.**
- A loud build-time refusal is correct.
- Option 2's behaviour reports success while handing users on 32-bit-only devices an app whose `initialize()` fails. *Inference:* that surfaces as a typed `NativeLoadError` (`wallet_core.dart:32`), not a crash, but the developer never sees it on the 64-bit devices they test with.
- "Hook emits nothing for an unshipped ABI" is the same silent behaviour; reject it.
- If Option 2 were chosen, its Gradle task should read `-Ptarget-platform`, which Flutter does pass (`DECISION-2-option2.md:343-345`).
- D1a should order refuse-by-default. An explicit opt-in to "emit nothing" can wait until a consumer asks for it.

**Q3: Failure messages.**

| Case | Option 1 | Option 2 | Clearer |
|---|---|---|---|
| Wrong digest | One `error:` line, placed first, carrying the artifact and both digests and sizes; measured in Xcode and Gradle (`acquire.dart:299`; `DECISION-2-option1.md:123`) | Correct, but iOS wraps it as CocoaPods' "Invalid `….podspec` file" (`DECISION-2-option2.md:279`) | Option 1 |
| Placeholder manifest | An actionable text (`acquire.dart:316-325`), not measured in a build | Measured: exit 2 with the blockers named | Option 2 (evidence) |
| Offline cache miss | Remedy text exists (`acquire.dart:327-331`), but Xcode shows only the first `error:` line. *Inference:* the remedy is lost on iOS | Full tool report; not measured | Neither measured |
| Unsupported ABI | Measured refusal naming the remedy, followed by the hooks runner's stack trace (`:277`) | Silent | Option 1 |

**Q4: Hooks maturity (evaluation's own notes; inferences labelled).**
- `hooks_runner` moved from 1.1.1 (Flutter 3.44.1) to 1.5.0 (3.47.5) (`:25`).
- `code_assets` 2.0.0 changed the API, so `android_libcpp_shared` 0.3.x cannot resolve against ffigen 21 (`:146`).
- Hooks get `includeParentEnvironment: false` (`:25`): configuration only through `user_defines`. Whether proxy variables reach the hook is **UNPROVEN**.
- The hook reads the raw input JSON path `user_defines.workspace_pubspec.defines` (`build.dart:201-209`). *Inference:* that is an internal shape, not a public API.
- The per-architecture `lipo`, the framework naming and numbering, and the hard-coded `MinimumOSVersion` (13 → 15 between minor releases) are `flutter_tools` behaviour, not protocol (`:150`, `:192`, `:214`).
- `StaticLinking` is a TODO in `code_assets` (`:180`). There is no way to ship a privacy manifest (`:185`). An asset id is usable only through `@Native` (`:193`).
- Feature flag: neither `run_eval.sh` sets one with `flutter config`, and neither document records needing one. *Inference:* hooks are not flag-gated on 3.47.5, but `flutter config --list` was never recorded (**UNPROVEN**).
- For a public alpha: pin the floor to what was measured, and treat each new Flutter stable as a re-run trigger for the hook rows.

**Q5: What remains UNPROVEN.**
- **Before DECISION-2 is final:**
  - A networked fetch from the published release, through the chosen mechanism, from a hosted package. This is T1.16b, and it includes the proxy question.
  - A signed iOS archive validated by App Store Connect, which settles the weight of the privacy-manifest gap.
  - `flutter build appbundle`, to see the refusal and 16 KB alignment on an AAB.
- **Before Phase 1 closes:**
  - Physical arm64 Android and iPhone runs, debug and release.
  - An `x86_64` runtime run (CI on a Linux host).
  - A second Flutter version, for DECISION-6.
  - A cold Gradle cache. This matters most for Option 2: its module declares an AGP 9.0.1 buildscript, and only the prepare step ran with the network denied (`:164`).
  - Option 2's zip path, which has never run on a real zip (`:306`).

**Q6: Measurement errors and overclaims** are listed in D. The headline counts (83 vs 71 passes) are not comparable: the column sets differ and the same evidence gets different labels.

## D. Findings on the evaluations

| # | Severity | Where | Finding | Fix |
|---|---|---|---|---|
| 1 | should-fix | `eval/option2:eval/option2/run_eval.sh:713`; `eval/option1:eval/option1/run_eval.sh:470-473` | The default-ABI build is "skip" in both tables. Option 2 hard-codes `--status skip` whatever happens. The main Android difference is invisible in the tables and counts | Add a `default-abi-build` row: Option 1 pass (refused); Option 2 fail |
| 2 | should-fix | `eval/option1:eval/option1/run_eval.sh:883-884` | `min-version-floor` is "pass" with only one version tried; Option 2 records the same data as unmeasured. This adds 6 passes to Option 1's count | Change to `unmeasured` |
| 3 | should-fix | `eval/option1:docs/decisions/DECISION-2-option1.md:101` | Option 1's packaged Android `.so` is compared by size only; Option 2 has `packaged-digest` rows (`DECISION-2-option2.md:124-127`) | Add a digest row |
| 4 | should-fix | option1 `table.md:21` | Step 9 is "pass" for silently replacing another plugin's `libc++` with one from a different NDK. The two options' step 9 fixtures also use different NDKs | Record it as a conflict resolved by override, and re-run after dropping the dependency |
| 5 | should-fix | option1 `:107`; option2 `:317` | Step 11 "pass" is `pub get` only; no hosted app was built. This matters most for Option 2's writes into the pub cache | T1.16b closes it |
| 6 | should-fix | option1 consumer `pubspec.yaml` (`manifest: ../eval_manifest.json`); option2 `WCF_MANIFEST` | Every build used a manifest override (Option 1's is a byte-different JSON copy, sha `3e65dab…`), so the default shipped-manifest path never ran | Run one build with no override after publishing |
| 7 | should-fix | option1 `:103` | No socket-level offline evidence; no placeholder-manifest build | Reuse `eval/option2/tool/no_net_probe.sh` |
| 8 | should-fix | `docs/decisions/DECISION-14.md:350`, `:354`, `:356` | §10b claims the patch is in the artifact record (it is not); §10f and §10h are stale | Correct before ratifying |
| 9 | should-fix | `docs/security/threat_model.md:9`, `:142`, `:144` | Artifact status is stale (set published, manifest filled) | Revise alongside DECISION-2 |
| 10 | should-fix (if Option 2 is chosen) | podspec `:76-79`; `build.gradle:198-202`; `DECISION-2-option2.md:68` | Environment-variable manifest override; iOS loader tries the process image first | Require a checked-in setting; try the framework path first |
| 11 | nit | option1 `:277` (0 `abiFilters` hits in `results.jsonl`) | The `abiFilters` claim was measured on a scratch copy and is not reproducible by the script | Script it |
| 12 | nit | option1 `table.md:23` | Duplicate-symbol scan: device only | Scan the simulator slices too |
| 13 | nit | option1 `:101` vs `:68` | macOS size: 39.33 vs 39.35 MiB | Re-sync the prose |
| 14 | nit | both tables | Columns named `android-emulator-x86_64` show "pass" without an x86_64 emulator; Android delta is a two-ABI APK, which overstates the per-device cost | Relabel the columns; state the per-ABI cost |

## E. Owner decisions at D1a, in dependency order

1. **§10h:** publish `native-4.8.0-001` and create the tag. **Yes.**
2. **§10a:** ship `arm64-v8a` and `x86_64` only. **Ratify**, on condition that `x86_64` runs before Phase 1 closes or is dropped.
3. **Unshipped-ABI rule:** **refuse at build time with the remedy**, whichever option wins.
4. **DECISION-2:** **Option 1**, provisional until T1.16b's networked hosted build passes; keep `eval/option2` unmerged.
5. **TM-35:** **drop `android_libcpp_shared`**; record `c++_static` as a DECISION-14 fact.
6. **iOS privacy manifest under Option 1:** **accept a documented consumer edit for 0.1**, verified on a signed archive before the alpha.
7. **DECISION-6:** **`flutter: ">=3.47.5"`** with a matching Dart lower bound, and record that Xcode 27 rules out 3.44.x.
8. **§10b:** **ratify**, and fix the record or the text.
9. **§10c:** **ratify.**
10. **§10d:** **ratify.**
11. **§10e:** **ratify**, after checking the recorded Xcode against the selected one.
12. **§10f:** **ratify**, and fix the stale sentence.
13. **§10g:** **option (ii)**, opt-in until T3.11.
14. **Threat model:** update TM-13, 14, 16, 28, 35 and 36 for Option 1, plus the stale rows.

## F. Ready for T1.16b?

**Yes, on condition that the release is published and the Option 1 merge (T1.R1) lands first.** That merge must drop `android_libcpp_shared`, make the loader's default locations option-aware, and update the `lint:runtime-deps` allow list. The most important reason: across both tables, every shared row has the same result except where Option 1 is equal or better, apart from the iOS privacy manifest, which goes to Option 2. The gaps both options share (devices, `x86_64`, AAB, a second Flutter) do not tell them apart. The one unmeasured path that could tell them apart is a fresh hosted consumer fetching the published set inside the hook, and T1.16b is exactly that test. Today it would fail on the draft release's HTTP 404, not on the design.