# DECISION-2 — Packaging options

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

| | |
|---|---|
| **Question** | How should the native library be packaged and distributed to consumer applications? |
| **Status** | **Decided by the owner 2026-10-05 at D1a (provisional until T1.16b)** |
| **Evidence** | [`eval/option1` evidence](DECISION-2-option1.md) (from eval/option1 3ba7826), [`eval/option2` evidence](DECISION-2-option2.md) (from eval/option2 de63ff5), [`D1a Opus debate`](../plan/reviews/D1a-opus-debate.md), [`D1a Codex debate`](../plan/reviews/D1a-codex-debate.md) |

## 1. Positions and Data

The two paths debated were Option 1 (build hooks) and Option 2 (conventional platform packaging via Gradle and CocoaPods). 
- **Codex for Option 2**:
  - conventional Gradle/podspec path with no consumer Gradle edits (`docs/plan/reviews/D1a-codex-debate.md:13`)
  - ships no `libc++_shared.so` (`docs/plan/reviews/D1a-codex-debate.md:14`)
  - podspec ships the privacy bundle and script phases - condition: a Gradle refusal of `android-arm` via `-Ptarget-platform` (`docs/plan/reviews/D1a-codex-debate.md:15`, `docs/plan/reviews/D1a-codex-debate.md:9`).
- **Opus for Option 1**:
  - CocoaPods deprecation + SPM cannot run the fetch tool (`docs/plan/reviews/D1a-opus-debate.md:21-23`)
  - smaller integrity surface: checked-in user_defines, unknown keys refused, filtered hook environment (`docs/plan/reviews/D1a-opus-debate.md:24-26`)
  - fails loud on default builds (`docs/plan/reviews/D1a-opus-debate.md:30-31`)
- **Agreement**: Both debates agreed on the core metrics and that shipping both options simultaneously was not viable.

## 2. Decision and Conditions

**Option 1 — build hooks** is selected.

Conditions:
- Merge `eval/option1` (T1.R1).
- Drop the `android_libcpp_shared` dependency.
- Keep the build-time refusal of unshipped ABIs.
- Document the consumer iOS privacy-manifest step (must be verified on a signed archive before the alpha).
- Keep `eval/option2` unmerged as a fallback.
- The decision is provisional until T1.16b's networked, hosted fetch passes.
- Publish release tag `native-4.8.0-001` now.

## 3. Measured Facts that Drove It

- **Android / iOS Results**: Both options passed targeted builds. The Option 1 iOS release app was smaller (+16.51 MiB vs Option 2's +19.03 MiB) due to Flutter stripping the dylib.
- **Default-Build Behaviour**: Option 1 fails loudly at build time with a remedy on an unsupported default ABI (e.g., stops at the hook). Option 2 fails silently on default ABI (`armeabi-v7a` slice missing `.so`).
- **libc++_shared.so**: Option 1 shipped an unpinned 2.37 MiB shared C++ runtime not required by our library, which is resolved by dropping the dependency.
- **CocoaPods Deprecation**: Option 2 relies on CocoaPods, which has an announced EOL, and SPM cannot fulfill PRD §12.3 artifact fetch requirements without an `xcframework.zip` which isn't published.
- **Privacy-Manifest Gap**: Option 1's main risk/gap is shipping the `PrivacyInfo.xcprivacy`, which requires a documented consumer native edit (mitigated by verifying a signed archive before alpha).

## 4. Residual Risks and What Would Reopen It

The following would reopen the decision:
- **Hosted fetch failing**: An unresolved failure during T1.16b's hosted fetch.
- **App Store rejection**: A signed archive being rejected by App Store Connect due to the Option 1 framework missing its own privacy manifest.
- **Hooks protocol change**: A Flutter stable release altering the hooks protocol that Option 1 relies on.

## 5. What Changes if Overturned

If overturned in favor of the fallback (`eval/option2`), the merge path would require the `-Ptarget-platform` refusal inside Gradle, and dropping the hooks-based implementation.
