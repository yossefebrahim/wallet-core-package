# Codex debate on the 2026-10-03 landing and the whole project — gpt-5.5, xhigh, read-only

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

Brief: `docs/plan/briefs/DEBATE-W5-landing.md` (the Fable review `reviews/W5-landing-fable.md` was appended verbatim). Tree: `integration/W5` — Codex read it while the W5-review-fixes edits were uncommitted (they landed as `0ac87c7` minutes later), which is what its "dirty worktree" remarks refer to. Thread `01a0ffda-abc8-7190-8864-0e2df60aab85`. Verbatim report follows; the orchestrator's triage is in PROGRESS.md.

---

A. **Debate Of The Fable Review**

1. **A2 docs/code alignment: SHARPENED.** Confirmed at committed tip `b07f593`: protocol counts and secret-bearing set match `packages/wallet_core_flutter/lib/src/worker/protocol.dart:31-40`, `:137`, `:187`, `:211`, `:389`, `:557`, `:611`, `:796`. Also confirmed that `OperationDeadline` is real and checked before/after execution at `protocol.dart:60-108` and `worker_loop.dart:232-263`. Sharpening: the current worktree is dirty and appears to already fix Fable’s stale doc findings in `DECISION-12.md`, `memory_contract.md`, and `threat_model.md`; those fixes are not in `b07f593` until committed.

2. **A3 `crypto: ^3.0.7`: CONFIRMED.** I found no contrary evidence; Fable’s dependency claim is consistent with `tools/probes/pubspec.yaml:9`. No dependencies were added by this review.

3. **LAND_W5 cleanliness: SHARPENED / partly stale.** Confirmed for committed `b07f593` as Fable reports, but not for the current worktree: `git status --short` now shows modified `docs/decisions/DECISION-12.md`, `docs/security/memory_contract.md`, and `docs/security/threat_model.md`. So “final tree clean” is no longer true of the checked-out tree.

4. **Gate results: UNPROVEN for current tree, accepted for `b07f593`.** I did not rerun write-capable gates in this read-only review, and the dirty docs mean Fable’s “clean after every gate” cannot be assumed for the current checkout. Fable’s pasted gate output is adequate evidence for committed `b07f593`.

5. **T1.2-d1 header padding: CONFIRMED with caveat.** Fable’s finding is consistent with `tools/native_build/build_apple.sh:366-371`. The caveat stands: `tools/native_build/run_native_tests.sh:30-37` prefers the repo dylib unless `WCF_NATIVE_LIB` is set, so “native tests ran on rebuilt host library” remains unproven.

6. **Orchestrator docs findings: SHARPENED.** I confirm the important part: Fable missed a larger doc contradiction in the live PRD. `docs/wallet_core_flutter_prd.md:206-210` still describes Approach A as Dart building a keyed protobuf/`Uint8List`, but the code stages key material in native memory via `secretDataFromParts` at `signing_core.dart:176-179` and `secret_buffers.dart:113-140`.

B. **Contested Points**

C1. **Ship A for M0; keep B as deliberate later work.** Approach A is coherent now because it has zero Dart-heap key copies and green tests, while B adds C key-path code, shim provenance, iOS loading ambiguity, and manifest/schema work. Evidence: `docs/decisions/DECISION-1-approach-a.md:17-25`, `signing_core.dart:123-149`. I’d change my mind after B has Android/iOS packaging proof, identity-covered shim symbols, fuzz/wire tests, and manifest provenance.

C2. **`Future<void> dispose()` should be exempt; private static `Pointer` fields should not report.** Rule 12 bans synchronous public disposal; lifecycle text says the lint rejects public `dispose` returning `void` at `docs/architecture/lifecycle.md:305`. Current lint flags any public `dispose` name regardless of return type at `tools/lint/lib/public_api_lint.dart:501-517`; that is broader than the rule. Private static pointers are not public surface or instance storage; current lint reasonably skips static fields at `:446-452`.

C3. **Option 1’s `libc++_shared.so` cannot ship unverified.** Acceptable only while eval remains eval. PRD §12.3 requires every artifact SHA pinned, `docs/wallet_core_flutter_prd.md:254-260`; Option 1 itself records the unpinned Android library risk at `eval/option1:docs/decisions/DECISION-2-option1.md:208`. Before release: add a verified manifest row, prove the dependency verifies it, or drop it.

C4. **Exporting `OperationCancelledError` is acceptable for M0 only as dormant API.** Public cancel is not present; only internal `WalletCoreSession.cancel` exists at `session.dart:540-553`. DECISION-12 explicitly defers public cancel-before-start to T2.1 at `docs/decisions/DECISION-12.md:165`. Do not claim cancellation support yet.

C5. **Must leave before public push/merge: the tracked binary; eval apps must not merge.** `tools/gen/bin/registry_transform.exe` is the serious one: a tracked Mach-O generator binary with no provenance. Eval `project.pbxproj`/consumer apps are absent from W5 and should stay out of main; pushing eval branches should be a deliberate evidence push after scrubbing, not part of W5.

C. **Answers Q0-Q6**

Q0. On committed `b07f593`, `docs/security/threat_model.md:67` and `:98` contradict the code by saying Approach A has a Dart `Uint8List` keyed signing input. Code evidence: `hd_wallet.dart:363-368`, `signing_core.dart:176-179`, `secret_buffers.dart:113-140`. Current dirty tree appears to fix those rows.

Q1. PRD §11.2 items 1-7: satisfied for internal native wrappers. Primary `dispose`, upstream delete, finalizer detach, double-dispose no-op, and `DisposedError` are in `native_resource.dart:83-121`. Temporaries are released in `TWDataHandle.withTWData` `tw_data_handle.dart:158-168`, `TWStringHandle.withTWString` `tw_string_handle.dart:163-173`, `ResourceScope.runScope` `resource_scope.dart:98-112`, and signing `finally` at `signing_core.dart:203-205`. Public proxies use async `close`, not sync dispose, at `wallet.dart:96-114`.

Q2. I found no path where `Sign`, `LocatorSpec`, or `SignResult` carries key bytes or a mnemonic across the seam. `Sign` is request plus locator specs at `protocol.dart:380-406`; locator specs are refs/device ids at `:423-506`; `SignResult` warns only that `usedKeys` may retain wallet refs, not bytes, at `sign_result.dart:23-34`. `ImportWallet.entropy` sender copy is overwritten by `InProcessTransport.send` at `transport.dart:98-112`; receiver cleanup is in `worker_loop.dart:241-253`. Real-isolate receiver-copy behavior remains T2.1 UNPROVEN.

Q3. Hostile-input tests are meaningful. Planted key fields fail in `evm_family_test.dart:245-289`; group/unknown wrapping fails at `:324-383`; truncated inputs fail without native signing at `signing_core_native_test.dart:229-248`; near-max timeout saturation is covered at `protocol_test.dart:195-208`. These would fail old behavior that appended keys, skipped opaque-field rejection, or allowed deadline overflow.

Q4. Wrong `wcf_build_info` cannot pass SDK init: `BuildIdentity.read` rejects missing/bad symbol at `build_identity.dart:79-101`, and `verifyIdentityValues` rejects mismatches/placeholders at `verify_identity.dart:106-127`, `:220-243`. But wrong manifest hash can be skipped on the default path: `WalletCore.initialize` passes no manifest bytes at `wallet_core.dart:44-47`, and `_init` only calls `verifyManifestHash` when `request.manifestBytes != null` at `handler.dart:273-278`.

Q5. I found no new active package-name violation; package names do not contain “trust”, and README has the required disclaimer at `README.md:3`. Fable’s archived PRD hits remain if archives are interpreted literally under rule 8. Generated/upstream Trust Wallet names are provenance, not package naming.

Q6. Not safe to merge to `main` as done. I would only push as a review branch after handling the dirty tree intentionally. The single thing to fix first is default native initialization/identity: make DECISION-14’s four comparisons actually happen on the default path, or amend the decision and tests.

D. **New Findings**

1. **blocking — `packages/wallet_core_flutter/lib/src/session/wallet_core.dart:44-47`, `packages/wallet_core_flutter/lib/src/worker/handler.dart:273-278`.** Default initialization does not provide manifest bytes, so manifest-hash comparison is skipped, contradicting DECISION-14’s four startup comparisons. Fix: load/pass manifest bytes on default init or formally change DECISION-14 and tests.

2. **blocking — `packages/wallet_core_flutter_native/lib/src/generated/manifest.dart:36`, `verify_identity.dart:220-243`.** Embedded `identityArtifactSetId = 'TBD-T1.2'` is rejected as a placeholder, so default public initialization cannot succeed against a real library today. Fix: populate real artifact identity before claiming M0 native init.

3. **should-fix — `docs/wallet_core_flutter_prd.md:206-210`.** PRD §11.4 still describes an older Approach A with Dart keyed protobuf/`Uint8List` copies. Fix it to match `signing_core.dart:123-149`.

4. **should-fix — `tools/gen/bin/registry_transform.exe`.** Tracked opaque executable generator with no provenance. Fix: remove from git and rely on the Dart source generator.

5. **should-fix — current worktree state.** `git status --short` is dirty in three docs. Fix: commit those intentional doc fixes or restore them, then rerun the relevant gates.

E. **Verdict**

`integration/W5` is close, but I would not call it ready for `main`: Fable’s code-surface review is mostly sound, yet it missed the default native initialization gap, where manifest hash verification is skipped and placeholder identity makes public init unusable. Fix that first; then remove the tracked binary and land the already-made doc corrections cleanly.
