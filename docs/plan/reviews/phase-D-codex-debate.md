# Codex debate — Phase D plan and next steps (gpt-5.5, xhigh, read-only, 2026-10-04)

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

Brief: `docs/plan/briefs/DEBATE-phase-D.md` (state at dispatch appended there). Verbatim report follows; the orchestrator's triage is in PROGRESS.md.

---

A. Verdict On P0-P4

P0: KEEP, but it is currently blocked. `compat_manifest.json` still has `TBD-T1.2` artifact hashes and `identity.artifact_set_id` (`compat_manifest.json:19-34`, `:48-51`), and dispatch says no artifact set is published yet. After publication, also add `identity.build_workflow`; the validator requires it once the artifact set is no longer a placeholder (`tools/manifest/lib/validator.dart:558-563`). Drop `armeabi-v7a` if unbuilt; the workflow default explicitly excludes it (`.github/workflows/build-native.yml:68-73`) and PRD §12.2 says ship every ABI tested or drop it (`docs/wallet_core_flutter_prd.md:246`). ADD: D1a must ratify the Android source-tree patches and JNI-helper allowlist, because `build_android.sh` now patches upstream with `-DFLUTTER=ON` and allows four extra JNI symbols (`tools/native_build/build_android.sh:357-372`, `:426-444`).

P1 / D1: KEEP, but relabel the local emulator evidence. The row is `android-emulator-arm64-v8a`, not the PRD’s `android-emulator-x86_64` row (`docs/wallet_core_flutter_prd.md:241`, `docs/plan/NEXT_STEPS.md:79`). Arm64 emulator work is useful, but x86_64 runtime remains missing if x86_64 is shipped.

P2 / D1a: KEEP, but make the decision narrower. DECISION-2 can be taken after decisive packaging rows are filled; physical devices and store export can block Phase 1 close / alpha without blocking the packaging choice. DECISION-6 is still under-evidenced because Option 2 only proves Flutter 3.47.5 on Xcode 27 and warns that 3.44.1 is not safe on that host (`eval/option2:docs/decisions/DECISION-2-option2.md:144-166`).

P3 / D3-D4: REORDER / SPLIT. Start packaging-agnostic T1.16/T1.17 now: example skeleton, `consumer_check.sh` harness shape, CI gates, no-network dependency check, pub Dependabot, manifest-bytes plumbing. Delay packaged device builds, identity mismatch against real assets, and loader-location defaults until DECISION-2.

P4 / D5-D7: KEEP, but ADD a hard close checklist. Today’s CI has placeholder device jobs (`.github/workflows/ci.yml:144-160`), and M0 requires Android emulator+device and iOS simulator+device evidence (`docs/plan/phases/phase-1-m0-spike.md:11`). No tag until that is either produced or explicitly changed in the plan.

B. Answers Q1-Q7

Q1. The high-level order D1 -> D1a -> packaging-specific D3/D4 is right. T1.16 depends on D1a in the phase table (`docs/plan/phases/phase-1-m0-spike.md:34`), and T1.17 depends on T1.16 (`:35`). But packaging-agnostic work can start now: example app flow scaffolding, consumer-check command harness, CI additions for `lint:public-api` / `vectors:validate`, pub Dependabot, `runtime_deps_check.dart`, and manifest-byte comparison plumbing. The default public path currently passes `manifestBytes: null` (`packages/wallet_core_flutter/lib/src/session/session.dart:31-37`, `:64-68`), and the handler only checks the manifest hash when bytes are supplied (`packages/wallet_core_flutter/lib/src/worker/handler.dart:273-278`), so that fix is independent of Option 1 vs Option 2.

Q2. Decisive DECISION-2 rows: clean consumer with no native edits, Android emulator run, iOS simulator run, release build/link/sign behavior, full symbol/runtime lookup, min Flutter/Dart/Xcode floor, offline install and wrong-checksum failure, 16 KB ELF plus APK/AAB packaging, `libc++` conflict fixture, iOS archive/privacy/duplicate-symbol behavior, and hosted-package consumption (`docs/wallet_core_flutter_prd.md:238-250`). Noise: exact warm-cache timings, desktop/macOS rows except host-test support, simulator release rows Flutter does not meaningfully run, dSYM size, and size deltas unless extreme. Missing after an arm64 emulator run: Android x86_64 runtime, physical Android, physical iOS, signed archive/App Store export, and Play-style APK/AAB 16 KB packaging validation. [Inference] Physical devices and store export need not block DECISION-2 if the mechanism rows are decisive, but they block Phase 1 close because M0 names devices (`docs/plan/phases/phase-1-m0-spike.md:11`).

Q3. The arm64 emulator does not weaken per-artifact 16 KB ELF evidence if the workflow checks both shipped 64-bit ABIs; `check_alignment.sh` verifies 64-bit ELF `LOAD` alignment at `0x4000` (`tools/native_build/check_alignment.sh:3-19`, `:119-143`), and `build_android.sh` loops per ABI (`tools/native_build/build_android.sh:426-449`). It does weaken runtime ABI evidence: x86_64 load, symbol lookup, sign flow, APK size, packaged `libc++`, and APK/AAB alignment remain UNPROVEN. Measure those in T1.17 on a Linux/x86_64 Android emulator job; Apple Silicon local emulation is not enough.

Q4. M0 evidence today: generated gates exist in CI (`.github/workflows/ci.yml:127-142`), but device jobs are skipped placeholders (`:144-160`); no published artifact set exists, so manifest identity is still placeholder (`packages/wallet_core_flutter_native/lib/src/generated/manifest.dart:36`, `:57`); A vs B has evidence docs on main/eval branches (`docs/decisions/DECISION-1-approach-a.md:187-196`, `eval/approach-b:docs/decisions/DECISION-1-approach-b.md:158-166`); packaging evals have Apple/simulator evidence but Android rows remain unmeasured (`eval/option1:docs/decisions/DECISION-2-option1.md:53-58`, `eval/option2:docs/decisions/DECISION-2-option2.md:84-104`). D3-D7 would add example/consumer evidence, CI device jobs, identity mismatch, no-network runtime, and final decision review (`docs/plan/NEXT_STEPS.md:81-85`). Nothing in Phase D currently guarantees physical device evidence, App Store export, or x86_64 Android runtime unless explicitly added. Silent drops: physical devices, x86_64 emulator, public default manifest-hash comparison, and full release-set comparison.

Q5. After P0, `initialize()` can still fail if any placeholder remains in `identity.artifact_set_id`; placeholder comparisons are rejected (`packages/wallet_core_flutter_native/lib/src/verify_identity.dart:220-243`). `release_set = TBD-T3.11` will not block today’s default initialize because comparison 1 is intentionally not called yet (`packages/wallet_core_flutter/lib/src/worker/handler.dart:279-284`), but `verifyReleaseSet` would reject the placeholder if wired now (`packages/wallet_core_flutter_native/lib/src/verify_identity.dart:153-163`). `retention` is validator/fetch metadata, not runtime loader input (`packages/wallet_core_flutter_native/lib/src/loader.dart:19-33`). Leaving `armeabi-v7a` would create a false shipped-ABI row; it may pass non-strict validation, but it violates the “drop untested ABI” rule in PRD §12.2 (`docs/wallet_core_flutter_prd.md:246`).

Q6. Do not pull T2.5/T2.6/T2.7/T2.12 into Phase D; that expands Phase 1 past M0 (`docs/plan/phases/phase-2-m1-bitcoin-solana-worker.md:28-40`). Pull only a D6 audit note from T2.1: cancellation remains incomplete, and `OperationCancelledError` should not be claimed as reachable until T2.1’s deadline/cancel work lands (`docs/decisions/DECISION-12.md:153-187`). [Inference] If DECISION-1 chose Approach B now, all artifact/device evidence would need rerun because the native artifact contract changes (`eval/approach-b:docs/decisions/DECISION-1-approach-b.md:158-166`), so choose “A now, B later” unless the owner wants to reopen packaging.

Q7. The next 48 hours should be brutally simple: fix CI billing, produce one published `as_4.8.0_001`, fill/regenerate the manifest, verify assets against `SHA256SUMS`, then run D1 on that exact set. Without that, the project is debating shadows.

C. Risks Ranked

Blocking Phase 1 close: no published artifact set; manifest and generated identity still use placeholders (`compat_manifest.json:19-34`, `packages/wallet_core_flutter_native/lib/src/generated/manifest.dart:36`). Mitigation: publish, splice records, run `gen:manifest`, `manifest:validate`, and asset checksum verification.

Blocking Phase 1 close: public initialize skips DECISION-14 comparison 2 by default (`packages/wallet_core_flutter/lib/src/session/session.dart:31-37`, `packages/wallet_core_flutter/lib/src/worker/handler.dart:273-278`). Mitigation: T1.16 must supply embedded manifest bytes on the default path.

Blocking Phase 1 close: physical device evidence is absent despite M0 requiring Android/iOS devices (`docs/plan/phases/phase-1-m0-spike.md:11`). Mitigation: use real devices/device farm or amend M0 explicitly.

Blocking Phase 1 close: x86_64 Android runtime is silently replaced by arm64 emulator evidence (`docs/wallet_core_flutter_prd.md:241`, `docs/plan/NEXT_STEPS.md:79`). Mitigation: add x86_64 emulator CI row before close.

Blocking Phase 1 close: DECISION-2 Android rows are unmeasured for both options (`eval/option1:docs/decisions/DECISION-2-option1.md:223-230`, `eval/option2:docs/decisions/DECISION-2-option2.md:246-255`). Mitigation: rerun both options against the published artifact set.

Should-fix: release-set comparison is deferred; do not claim all four DECISION-14 comparisons (`docs/decisions/DECISION-14.md:77-88`, `packages/wallet_core_flutter/lib/src/worker/handler.dart:279-284`). Mitigation: document as T3.11, or wire only when package release-set ids exist.

Should-fix: Flutter/Dart minimum is UNPROVEN below the current host toolchain (`eval/option2:docs/decisions/DECISION-2-option2.md:144-166`). Mitigation: DECISION-6 should state measured floor and host constraints.

Nit: stale “not yet run” comments remain in native build docs/scripts despite dispatch history (`.github/workflows/build-native.yml:38-42`, `tools/native_build/build_android.sh:35-38`). Mitigation: clean after artifact set lands.

D. Revised Phase D Sequence

1. Owner/orchestrator: unblock GitHub Actions billing and publish `as_4.8.0_001`. Evidence: run URL, release URL, `SHA256SUMS`, export gate counts, 16 KB gate output, artifact records.

2. Opus implementer: P0 manifest fill. Evidence: `compat_manifest.json`, regenerated manifest, `manifest:validate`, downloaded assets verified against `SHA256SUMS`, no `armeabi-v7a` unless built/tested.

3. Opus implementer in parallel: packaging-agnostic T1.16/T1.17 prep. Evidence: example skeleton, `consumer_check.sh` skeleton, manifest-bytes default path, runtime deps/no-network check, pub Dependabot, CI gate additions.

4. Orchestrator on devices/simulators: D1 published-set evals for Option 1 and Option 2 on arm64 emulator and iOS simulator. Evidence: completed rows, APK/AAB 16 KB packaging output, `libc++` fixture, offline/wrong-checksum logs, size deltas.

5. Orchestrator/CI: Android x86_64 emulator row. Evidence: load/symbol/sign flow, APK packaging alignment, size, `libc++` fixture for x86_64.

6. Codex debate + owner decision: D1a. Evidence: DECISION-2, DECISION-6, DECISION-14 ratification, including Android `-DFLUTTER=ON`, JNI allowlist, and `libc++` policy.

7. Opus implementer: merge/rework selected packaging path and finish T1.16. Evidence: example app and `tools/consumer_check.sh` pass on selected option, no native edits, manifest hash comparison runs by default.

8. Opus/orchestrator: finish T1.17 CI. Evidence: live green CI with generated gates, `lint:public-api`, vectors, manifest, no-network runtime, runtime deps, identity mismatch, Android emulator, iOS simulator.

9. Owner/orchestrator: physical Android and iOS evidence or explicit M0 amendment. Evidence: debug/release M0 flow on devices, or a recorded plan change.

10. Codex/other reviewers: D5-D7. Evidence: review findings resolved, M0 checklist itemized, owner tags only after blockers are closed.

E. Closeability

I would call Phase 1 close-able when the published artifact set is real, the manifest is regenerated from it, the selected packaging path passes the decisive PRD §12.2 rows including x86_64 runtime and 16 KB APK/AAB evidence, the example/consumer check proves no native edits, CI runs the real device/simulator gates, default initialize performs the manifest-hash comparison, and M0’s physical-device requirement is either satisfied or explicitly amended. I would refuse to sign off today because the artifact set is not published, the manifest still contains placeholders, DECISION-2 lacks Android evidence, CI device jobs are placeholders, x86_64 runtime is unproven, and the default identity check still skips one of DECISION-14’s required comparisons.
