**Verdict: fix before commit.** The T1.15 lint and the T1.18 docs both need changes. T1.14 is nearly ready; it needs small hardening.

## Findings (most severe first)

**1. High: the lint never looks inside types that aren't exported but appear in public signatures.** `T1.15/tools/lint/lib/public_api_lint.dart:441-449`, `:299-301`, `:145-150`
- **Defect:** an interface type is judged only by the library it is defined in. Its members, fields and `dispose` are never checked. An exported `typedef X = SomeClass` checks only the type itself, not the class behind it.
- **Scenario:** I put a copy of the default entry next to T1.12's bindings, re-exporting only `ResourceScope` and `NativeContextScope`. The lint reported "0 violations". Through `scope.context.bindings` a consumer gets the whole generated `WalletCoreBindings`, plus `TWDataHandle.pointer` (`Pointer<TWData>`) and a synchronous `dispose()`.
- The same gap lets through: private classes returned by public members, `Future<Inner>`, `Iterable<Inner>` supertypes, `T extends Inner` bounds, typedef-exported classes, and a non-exported subclass of a generated class.
- **Confirmed:** fixtures plus a consumer that imports only the entry. `dart analyze` was clean, and at run time the consumer obtained a `Pointer` and called `dispose()`. A patched walker that follows these types flags all of them.
- T1.12's current surface has no such type (49 elements, 0 violations even with the patched walker), so nothing leaks today.
- **Fix:** keep a worklist of every non-SDK interface type met in a public position (return, parameter, field, bound, type argument, typedef target). Run each through `_checkInterface` and attribute findings to the exported name.

**2. Medium: some public `dispose` forms are missed.** `public_api_lint.dart:286-298`, `:352-354`
- **Defect:** the `sync-dispose` check never runs on exported extensions, and it only matches methods (`MethodElement`).
- **Scenario:** each of these gives 0 violations, and the consumer can still call `x.dispose()`:
  - `extension SyncClose on Wallet { void dispose() {} }`
  - `void Function() get dispose`
  - `final void Function() dispose`
- **Confirmed** with fixtures.
- **Fix:** apply the check to extension members, and to getters and fields named `dispose` that have a function type.

**3. Medium: the `pointer-field` check misses Pointers wrapped in extension types.** `public_api_lint.dart:443-445`
- **Defect:** in field mode only types defined in `dart:ffi` are reported, and an extension type's representation is never looked at.
- **Scenario:** `final Handle _h;` where `extension type Handle(Pointer<Void> _)`. At run time the field stores a `Pointer`, and nothing is reported. A `package:ffi` `Arena` field is also not reported.
- **Confirmed.**
- **Fix:** for extension types, recurse into the representation type.

**4. Medium: the lint is not wired into CI.** `T1.15/.github/workflows/ci.yml` (no change from the W3 base)
- **Defect:** the plan for T1.15 says "Wired as `lint:public-api` and in CI". No CI step runs it, and no test runs it against `packages/wallet_core_flutter`.
- **Scenario:** a surface regression merges with CI green.
- **Confirmed.**
- **Fix:** add a `melos run lint:public-api` step, or assign it explicitly to T1.17.

**5. Low: only the default entry is checked.** `public_api_lint.dart:115`, `:183-184`
- **Defect:** AGENTS.md rule 4 allows only `advanced.dart` to export these types, but other files in `lib/` are never checked.
- **Scenario:** a new `lib/testing.dart` that re-exports the bindings passes.
- **Plausible** (from reading the code).
- **Fix:** lint every `lib/*.dart` except `advanced.dart`.

**6. Low: false positive for `implements`.** `public_api_lint.dart:328-336`
- **Defect:** fields are collected from all supertypes, including implemented interfaces, whose fields are not inherited.
- **Confirmed:** `class C implements Inner` is reported as `pointer-field C._p`, a field C doesn't have.
- **Fix:** walk only the superclass chain and mixins.

**7. Low: typedef chains are checked only at the outermost name.** `public_api_lint.dart:418-436`
- **Confirmed:** `typedef PublicId = GeneratedId` is not flagged. The impact is small because the underlying type is still checked.

**8. Medium: the memory contract leaves out private keys and wallet seeds.** `T1.18/docs/security/memory_contract.md:17-22`
- **Defect:** "What we overwrite" covers only `TWDataDelete`/`TWStringDelete` and the SDK's staging buffers.
- Already in T1.18's own code: `deriveAccount` creates a `TWPrivateKey` on every call (`hd_wallet.dart:201-212`). Upstream wipes it on delete (`~PrivateKey() { cleanup(); }`, `PrivateKey.h:93`, which zeroes the bytes). `TWHDWalletDelete` wipes the seed, mnemonic and passphrase (`HDWallet.cpp:102-106`). Neither is mentioned.
- T1.12 adds more that is not covered:
  - `withDerivedKey`: a view over the key's native buffer.
  - `secretDataFromParts`: a zeroed `calloc` staging buffer.
  - the keyed input `TWData`, and upstream's own copies while signing.
- PRD §11.3's statement on private-key exposure ("only through explicit `advanced` APIs") is also missing.
- **Confirmed** against the code and upstream sources.
- **Fix:** add a "Private keys and signing" section, and name `HDWallet` and `PrivateKeyHandle`/`PublicKeyHandle`/`AnyAddressHandle` in item 1.

**9. Medium: the claim that these are "the only Dart-heap copies the SDK makes" is false.** `memory_contract.md:37`
- **Defect:** `ImportWallet.entropy` (`protocol.dart:153-155`) makes a copy with `Uint8List.fromList(entropy)`. The worker loop overwrites it, but the doc mentions neither the copy nor the overwrite.
- **Worker-isolate scenario:** once T2.1 sends requests over a `SendPort`, the copy received by the worker is the one that gets overwritten (`worker_loop.dart` / `overwriteOwnedSecrets`). The session isolate's own copy is zeroed only when a request is rejected (`session.dart:336-344`), so it would stay in memory unzeroed. That makes `wallet.dart:43-45` ("overwritten … once the owning isolate has used it") false at that point.
- The "only copies" error is **confirmed**. The T2.1 consequence is **plausible**, since that code doesn't exist yet.
- **Fix:** correct the sentence, document the entropy copy, and have the sending side zero its copy after `send`.

**10. Low/medium: lifecycle.md overstates what scopes close.** `T1.18/docs/security/lifecycle.md:26`
- **Defect:** it says a scope "closes or disposes everything created inside it". `SessionScope` closes only wallets created through its own `createWallet`/`importMnemonic`/`importEntropy` (`scope.dart:45-72`). `ResourceScope` disposes only resources registered with `use`.
- **Scenario:** a wallet created with `core.wallets.create()` inside the scope body stays open in the executor, holding its mnemonic.
- **Confirmed** by reading the code.
- **Fix:** say "everything created through the scope".

**11. Low: the docs describe the M0 executor as if it were an isolate.** `memory_contract.md:50`, `lifecycle.md:7`
- **Defect:** "crosses the isolate boundary" / "asks the owner isolate". At this version the executor is `InProcessTransport` (`session.dart:60`, `transport.dart:49-62`), so no isolate boundary exists yet.
- **Confirmed.**

**12. Low: the leak-tracker release-build claim isn't backed.** `memory_contract.md:57`
- **Defect:** "the compiler drops it entirely" is stated as fact. The code itself defers the release-mode proof to T1.17 (`leak_tracker.dart:155-158`). Code outside the assert still contains `is LeakTracker` checks (`handler.dart:227`, `testing.dart:60`).
- **Plausible.**
- **Fix:** say it is never constructed in release builds and that T1.17 verifies tree-shaking.

**13. Low: the "Known gaps" section has small factual errors.** `memory_contract.md:28-35`
- It names a `toBytes` method that doesn't exist (the method is `copyBytes`).
- It says `fromBytes` stages input "in a Dart list"; only `fromString` makes one.
- Its line references (`engine.dart:109/115`, `hd_wallet.dart:200/252`) shift with T1.12 (to 111/117 and 203/255).
- T1.12 adds callers it doesn't list: `engine.dart:174/183`, `hd_wallet.dart:323`, `signing_core.dart:173`. None carries a secret, so the conclusion still holds.

**14. Low: lifecycle.md is incomplete on failures and finalizers.**
- `:32`: a failed `initialize()` can also throw `InvalidInputError`, `OperationTimeoutError`, or `WorkerTerminatedError(initializationFailed)`.
- `:40`: a late `WalletCreated` is released with a posted `DisposeRef`, not "simply discarded" (`session.dart:447-451`).
- `:44-46`: it applies `NativeFinalizer` guarantees to the managed `Finalizer` that `WalletProxy` uses; a managed `Finalizer` may never run.
- `:11`: `resolveWalletRef` has no caller in T1.18. It becomes true once T1.12's signer calls it.
- Forced shutdown isn't covered: `wallet_core.dart:121-124` says a forced stop does not wipe what the isolate owned, while M0's `kill()` does release everything (`worker_loop.dart:156-159`, `:259-266`). The doc is silent on both.

**15. Low/medium: the probe hard-codes its provenance instead of measuring it.** `T1.14/tools/probes/bin/sign_json_probe.dart:49-54`
- **Defect:** the doc header always says "Tag 4.8.0, Commit d692ac…, libTrustWalletCore.dylib", whatever `--lib` or `WCF_NATIVE_LIB` loaded.
- **Scenario:** running against another build writes a doc that falsely claims the pin.
- **Confirmed** by reading. Today's doc is correct: I read the build identity of the dylib it measured (`upstream_commit` d692ac…, `as_4.8.0_000`, `local`).
- **Fix:** read the build identity and the manifest, fail on a mismatch, and record the set id and SHA-256 in the header.

**16. Low: the probe test can't fail on a wrong evidence table.** `T1.14/tools/probes/test/sign_json_probe_test.dart:72-73`
- **Defect:** it asserts `rows.length == 167` (which is just `TWCoinType.values.length`) and that there were no exceptions.
- **Scenario:** a stale or edited evidence table still passes.
- **Fix:** a golden test against `sign_json_coverage.md`.

**17. Low: the probe's own advice doesn't work.** `sign_json_probe.dart:23-31`
- **Defect:** it says to run `melos run native:host-lib`, which writes to `${WCF_NATIVE_OUT:-$TMPDIR/wcf-native}/artifacts/…`. The probe's default path is `third_party/wcf-native/…`, so following the advice still fails.
- **Fix:** use the same lookup chain as `run_native_tests.sh`.

**18. Info: the probe iterates the FFI coin enum, not the registry's.** `T1.14/tools/probes/lib/sign_json_probe.dart:19`
- The plan says the registry's `CoinType.values`; the probe uses `TWCoinType.values`. I checked that both have the same 167 ids at this pin, so the table is unaffected. Add an equality check so a future pin can't drift silently.

## Claims checked and found true
- **Lint (T1.15):**
  - T1.12 SDK: 49 elements, 0 violations. T1.15's own SDK: 35, 0. `advanced.dart`: 4,973 violations, a useful positive control.
  - 30 unit tests pass; analyze and format are clean.
  - It correctly catches generic bounds, typedef targets, record and function types, `covariant` params, static members, top-level getters and setters, enums, mixins with `on`, extension types (including `implements`), `Finalizable` supertypes, `NativeFinalizer` fields, and inherited members with type arguments substituted.
- **T1.18 docs:**
  - `TWDataDelete`/`TWStringDelete` zero their buffer (`TWData.cpp:106-115`, `TWString.cpp:35-44`).
  - `NativeResource`: dispose order, idempotence and finalizer detach are as described; finalizer callbacks are the raw upstream delete functions.
  - `fromBytes`/`fromString` free their `calloc` buffer in `finally` without zeroing it; `secretString`/`secretData` do zero theirs.
  - `runScope` disposes in reverse order and the body's error wins.
  - The leak tracker records identity and stack only, behind an `assert`.
  - Session states and transitions match the enum doc and `checkReady`.
  - Operations and disposals share one FIFO queue.
  - Shutdown rejects queued operations with `SessionStateError`; control messages bypass the queue limit.
  - `close()` has no deadline, is idempotent, and leads to `ClosedError`.
  - The proxy finalizer posts only while the session is ready; an executor fault gives `uncaughtDartError`.
  - The cited line numbers are correct in T1.18. No forbidden words; the disclaimer is present; the README markers are present and their links resolve.
- **Probe (T1.14):**
  - Re-running it produces a byte-identical doc.
  - The measured dylib is the pinned commit.
  - 167 rows, 0 errors.
  - SignJSON actually produces output for Ethereum and Solana.
  - Analyze, format and tests are green.

## Not reviewed
- **Full workspace gates:** I didn't run `melos run analyze`/`test`/`test:native` across the workspace. The sandbox blocks Flutter's `dart` wrapper from writing to its cache, so I ran per-package analyze, format and tests with the raw SDK binary instead.
- **Conditional exports:** a custom `-D` condition never switched the export with the local toolchain, so I don't count it as an escape.
- **T1.12 signing code:** reviewed only as far as the doc-coverage finding needed.
- **T1.11/T1.13 SDK code in these trees:** reviewed only where a doc claim pointed to it.
- **CI YAML:** checked only for the lint step.