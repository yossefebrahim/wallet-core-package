<task>
W5 verification fixes — small, precise fixes in two sibling worktrees of the `wallet_core_flutter` repository. Your working directory is their parent: `T1.12/` (branch `task/T1.12`, Approach A only) and `T1.13/` (branch `eval/approach-b`: T1.12 plus the C signing adapter). Read `T1.13/AGENTS.md` first. Both trees hold a lot of uncommitted accepted work — change only what is listed here. The SDK's shared library files (`packages/wallet_core_flutter/lib/src/{worker,session,errors,families}/**`, `engine/secret_buffers.dart`, `signing/key_field_check.dart`) are byte-identical in the two trees today and must be byte-identical when you finish; the seam files (`worker/handler.dart`, `engine/hd_wallet.dart`, `signing/signing_core.dart`) differ on purpose.

A verification review (appended verbatim) confirmed every earlier finding closed and found these new ones. Fix:
  - **N1** (T1.13 only): `adapter_signing_core.dart` — a null from `TWDataCreateWithBytes` during a sign on the adapter path must be a per-operation `SigningError`, session stays `ready`, like Approach A. Regression test through the `EngineRequestHandler(bindings:)` seam, `shim`-tagged.
  - **N2** (both trees, identical): `OperationDeadline` overflow — a near-max timeout must mean "effectively never", not "already passed". Saturate. Regression test: `Duration(microseconds: 0x7FFFFFFFFFFFFFFF)` as an operation timeout, an operation runs and succeeds.
  - **N3** (both trees, identical): `close()` on a wallet after the session went `failed` → `closed` must fail with the termination error instead of completing normally. Regression test.
  - **N5** (T1.13 only): `tools/native_build/build_apple.sh --with-shim` must refuse a bad `--out-dir` before creating it; add the probe as a test or a scripted check you run and paste; fix the sentence in `DECISION-1-approach-b.md` if it still overstates.
  - **N6** (both trees, identical): `checkKeylessInput` rejects a key-less input containing a group (wire types 3/4) or any unknown field, so nothing can hide a key field from the check; state it in the doc comment. Regression test (pure) with the reviewer's nested-in-group field 9.
  - **Nits**: the three line-count/range slips in the two `T1.13/docs/decisions/DECISION-1-approach-{a,b}.md` documents (re-derive every range you touch from the files; if T1.12's copy of approach-a has the same slip, fix it there too), and the 130-character doc line in `secret_buffers.dart` (both trees).
Do NOT fix N4 (DECISION-12 §3.2 / `docs/architecture/lifecycle.md` §6 no longer match the deadline design): those are recorded decision documents and belong to the repository owner — list it in your report.

Constraints: AGENTS.md rules; no secret in errors/logs/test messages; no cryptography in Dart; generated dirs never hand-edited; no git command that writes; no other agent session; one shell command per call (scripts under $TMPDIR).

Gates, in EACH tree (`cd` via a script file), paste the tails: `export PATH="$PATH:$HOME/.pub-cache/bin"`; `melos run analyze`; `melos run format:check`; `melos run test`; `melos run test:native`; in `T1.13` also `bash tools/native_build/run_shim_tests.sh` (rebuild the shim library first only if you changed C). Finally show `diff -r` of the shared directories between the two trees prints nothing.

Report: 1. per finding — fixed (where, test) or not; 2. files touched per tree; 3. gate tails per tree with counts and the diff result; 4. for the owner.
</task>

===== VERIFICATION REVIEW (verbatim) =====
**Verdict: fix before commit.** Every original finding I could test is closed, but the fixes introduced or left three small defects, plus some doc slips. Nothing needs redesign.

Gates, re-run here, all green:
- **analyze:** clean.
- **format:check:** 399 files, 0 changed.
- **test:** SDK 300, bindings 64, native package 190, tools all passing.
- **test:native:** bindings 42, SDK 106.
- **run_shim_tests.sh:** 22 passed, none skipped.

**T1.12 spot-check:** every shared library file (`worker/`, `session/`, `errors/`, `secret_buffers.dart`, `key_field_check.dart`, `families/`) is byte-identical between the two trees. The only differences are the seam (`handler.dart`, `hd_wallet.dart`, `signing_core.dart`). T1.12's Approach A doc ranges add up to its stated 785 lines.

## Original findings

| Finding | Status | How I checked |
|---|---|---|
| A-1 late reply crosses | **closed** | Ran the loop with no session, so no `Cancel` could rescue a request. An operation whose deadline passed while queued never ran, got exactly one `Failed(timeout)`, and its entropy was zeroed. A late reply was dropped, and a late `WalletCreated` was discarded. With the real engine, a slow create and import left LeakTracker at `live: 0` and `disposedAtShutdown 0`. `DisposeRef` and `Shutdown` ignore any deadline. A 15-round random workload gave unique reply ids and `outstanding 0`. Clocks: 0 of 500 timers fired before the deadline (JIT and AOT `dart compile exe`), and isolates share the clock. |
| A-2 `close()` in `closing` after a kill | **closed** | Re-ran the reviewer's 3-wallet scenario (slow `DisposeRef`, 50 ms grace): w1 ok, w3 (ready) and w2 (closing) both `WorkerTerminatedError`. See N3 for an uncovered sibling path. |
| A-3 soft native failures end the session | **closed on the A path, partial in this tree** | The 3 soft-failure tests can fail. I injected a null from `TWDataCreateWithBytes`: under A it gives `SigningError` and the session stays `ready`; under B the session goes to `failed` (N1). |
| A-4, A-8 | left to the owner | Not reviewed. |
| A-5 key named = key used | **closed** | `key_identity_native_test.dart`: `withDerivedKey`'s public key and address are checked against the vector; the signature is reproduced with a key from `TWHDWalletGetDerivedKey`; `TWPublicKeyRecover` returns the vector's public key. |
| A-6 public-surface test | **closed** | Mutation run on scratch copies: a `CoinType` getter in `coin.dart`, a `CoinType?` getter in the part file, and a `List<CoinInfo>` getter each fail the test; the unmutated copy passes. |
| A-7 entropy copies | **closed** | The sender's copy is zeroed on send, on the closed-transport path, and on a rejected submit. No retry or re-read path touches it. The executor works on its own copy. |
| A-9 tests that couldn't fail | **closed** | Both now go through the real path: the imported locator crosses, and the loop dies on a `FormatException` that quotes a mnemonic. |
| A-10 doc slips | **closed** | Ranges add up to 900; `key_fields.dart` is 30 lines; `TWStringSize`/`TWStringUTF8Bytes` and both `MessageSigningInput` rows are present; `advanced.dart` text fixed. |
| A-11 `usedKeys` keeps the wallet open | **closed** | Documented on `sign_result.dart`. |
| B-1 append → prepend | **closed** | Called the C adapter directly, skipping the Dart check. Truncated input: upstream error −1, key not in the output. A key planted after the input wins, as the precondition says, and the Dart check rejects it. A and B are byte-identical on all 60 EVM coins. The Dart header matches protobuf's own writer in 99 field/length cases. `wcf_sign.h` and §3 restate the precondition. |
| B-2 Approach A doc stale | **closed** | Approach A L24, 37, 56, 63, 85–96 and 151, and Approach B §11 item 6, checked against the code. |
| B-3 copy counts | **closed** | Approach B L81: A 4 (#1–#4), B 3 (#1, #2, #4). |
| B-4 shim identity, `--out-dir` guard | **closed** | The shim library embeds `as_4.8.0-shim_000`, and a session test asserts `artifactSetMismatch`. Guard probes in scratch: `..`, a symlink, an own name without "shim", and the standard set id are all refused. See N5. |
| B-5 iOS binding claim | **closed** | Qualified in `handler.dart:27-35`, `adapter_signing_core.dart:112-119`, Approach B §1.3 and §5.3. |
| B-6 untyped key pointer | **closed** | The key is now `Pointer<TWPrivateKey>` (`adapter_signing_core.dart:56-68`). |
| B-7 test gaps | **partial** | The guard tests, the A production-path rejections (`disposed == 2`, so they can fail) and the truncated-input test all exist. CI still runs neither native nor shim tests; the doc says that is the orchestrator's job. |
| B-8 §5.1 sizes | **closed** | Re-measured the size, `__TEXT` per arch, defined externals (29,436/30,004 and 29,435/30,003) and 464 `TW*` exports: all match. The sha256 matches for the shim library and the third_party standard copy; the comparison build is not on disk here. |
| B-9 upstream copies | **closed** | Source verified: `RustCoinEntry.cpp:98–103`, `tw_data.rs:14/24/75–78`, `TWData.cpp:106–115`, and the move semantics in `TWPrivateKey.cpp:32–42`. |

## New findings

1. **Low — N1: under B, one soft native failure still ends the session.** `adapter_signing_core.dart:199`
   - **Defect:** `TWDataHandle.fromBytes` throws `StateError` when `TWDataCreateWithBytes` returns null. The handler rethrows it as a fault.
   - **Scenario:** that null during `sign` on the B path moves the session to `failed` and kills every wallet. Approach A (`secretDataFromParts`) gives `SigningError` and stays `ready`.
   - **CONFIRMED** by injecting the null through `EngineRequestHandler(bindings:)` on both paths.
   - **Fix:** use `secretData(context, keylessInput)`, or wrap the call in `readNative`.

2. **Low — N2: a near-max timeout makes every operation fail at once (introduced by the fix).** `protocol.dart:80-81`, `session.dart:45-58`
   - **Defect:** `monotonicMicros() + timeout.inMicroseconds` overflows int64. `atMicros` goes negative, so `hasPassed` is always true. `startSession` only checks that timeouts are positive.
   - **Scenario:** a caller passes `Duration(microseconds: 0x7FFFFFFFFFFFFFFF)` as a "never time out" value. Every `create()` then fails with `OperationTimeoutError` and nothing runs. Before the fix this worked, because only Timer and Stopwatch were used.
   - **CONFIRMED:** `atMicros=-9223371959896314627`; `create()` failed with `OperationTimeoutError`; nothing but `initialize` was handled.
   - **Fix:** saturate `atMicros` at the int maximum, or cap timeouts in `startSession`.

3. **Low — N3: `close()` after failed → closed reports a release nobody confirmed (same class as A-2, not covered by its fix).** `session.dart:509-515`
   - **Scenario:** the executor faults, so the session is `failed`, and `w.close()` correctly throws `WorkerTerminatedError`. After `shutdown()` moves it to `closed`, `w.close()` completes normally. In M0 `releaseAll` did release the wallet. A dead T2.1 isolate would not, so this becomes a false "released".
   - **CONFIRMED** in M0 by experiment; the T2.1 impact is PLAUSIBLE.
   - **Fix:** in the `closed` case, also throw when `_termination != null`.

4. **Low (docs) — N4: the deadline design isn't recorded.** `DECISION-12.md:90` still lists "timeouts" in `Init`. The code's `Init` (`protocol.dart:124-168`) has none; deadlines travel beside each operation (`transport.dart:36-46`). That T2.1 must carry the deadline in its message envelope is stated only in a doc comment. Neither DECISION-12 §3.2 nor lifecycle.md §6 is updated. **CONFIRMED** by reading. **Fix:** amend both.

5. **Low (docs/script) — N5: refused out-dirs are still created.** `build_apple.sh:209-215` runs `mkdir -p "$out_dir"` before the own-name check.
   - Approach B L272 says each probe was "refused before anything was written". My probes left empty `…/shim/wcf-native` and `…/wcf-native` directories behind.
   - **CONFIRMED** by probe (in scratch).
   - **Fix:** check the resolved parent plus the basename before `mkdir`, or reword the doc.

6. **Info — N6: a group hides field 9 from the Dart check, harmlessly.** `checkKeylessInput` accepts a field 9 nested inside an unknown group (wire type 3). Upstream rejects groups (error −1), and the C adapter's output then holds no key, so nothing is exposed. **CONFIRMED** with the Dart check and the adapter. **Optional fix:** reject unknown groups in the check, as the native walk sketched in Approach B §3 would.

7. **Nits:**
   - Approach B L33: `wcf_sign.c` has 83 code lines, not 82.
   - Approach A L93: `handles.dart` should be 59–85 (T1.12's copy says that for the identical file); L90 `family.dart` reads 87–153 here but 94–146 in T1.12 for the same file.
   - `secret_buffers.dart:106` is a 130-character unwrapped doc line.

## What I did not review

- No shim rebuild: the wall time, the +384 B delta against the comparison build, and byte stability are unverified.
- No C fuzzing. The 2-byte key-length prefix (keys over 127 bytes) can't be reached with a real `TWPrivateKey`.
- §5.2/§5.3 mobile analysis, Android scripts, device platforms, and `Timeline.now` on Android/iOS (checked on macOS only).
- A-4 and A-8. The T1.12 gates were not run (I diffed instead). Generated code, the bindings memory layer, and CI beyond a grep.

All probes and logs are in the scratchpad. No worktree source files changed; the gates and test runs wrote only the usual tool caches.