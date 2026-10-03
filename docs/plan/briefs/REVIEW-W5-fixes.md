<task>
Verification review of review fixes. You are in the `eval/approach-b` worktree of `wallet_core_flutter` (read `AGENTS.md` first). Two earlier independent reviews (appended verbatim: REVIEW A — SDK; REVIEW B — Approach B) found defects in the SDK's signing path and session/worker protocol. Implementer sessions then fixed them: in the sibling tree `../T1.12` (readable; Approach A only) and here (the same fixes ported, plus the C adapter). The fix diff for the SDK, relative to the pre-fix state, is `/tmp/claude-501/port/T1.12-d1-sdk.patch` (paths relative to `packages/wallet_core_flutter`); this tree additionally changed `packages/wallet_core_flutter_native/src/shim/wcf_sign.{c,h}`, `lib/src/signing/**`, `lib/src/worker/handler.dart`, `lib/src/engine/hd_wallet.dart`, `tools/native_build/{build_apple.sh,check_exports.sh,run_shim_tests.sh}`, and both `docs/decisions/DECISION-1-approach-{a,b}.md`.

Your job, for this tree (and spot-check that `../T1.12` agrees where the code is shared):
  1. For every finding of REVIEW A (1–11, except 4 and 8 which were left for the owner) and REVIEW B (1–9): is it actually closed? Re-run or re-create the reviewer's scenario where one was given. A finding "closed" only by a test that cannot fail is not closed.
  2. Hunt for regressions the fixes introduced. In particular: the per-request `OperationDeadline` and the executor dropping late replies (queue accounting, exactly one reply per request, a wallet created by a late `CreateWallet` is released and never leaks, a late `DisposeRef`/`Shutdown` is never dropped, clock assumptions, what happens when the deadline expires while the request is queued behind a slow one, behaviour under a future isolate transport); `NativeResultError` mapping (can a real invariant break now be swallowed as a per-operation error? can an error message carry secret bytes?); sender/executor entropy overwrite (double use after overwrite, a retry path reading zeroed bytes); prepend in Dart and C (planted key field later in the bytes — the check must reject it; lengths, overflow, the header buffer; byte-identical output for all EVM coins; truncated input); the shim identity change (`as_<tag>-shim_<nnn>`) and the `--out-dir` guard.
  3. Check the two decision documents and the doc comments against the code as it now is: every count, line range, file map entry and claim about key copies.
Run the gates and your own experiments: `export PATH="$PATH:$HOME/.pub-cache/bin"`; `melos run analyze`; `melos run test`; `melos run test:native`; `bash tools/native_build/run_shim_tests.sh`. Host library: `third_party/wcf-native/macos/arm64_x86_64/libTrustWalletCore.dylib`; shim library: `third_party/wcf-native-shim/macos/arm64_x86_64/libTrustWalletCore.dylib`.
</task>

<action_safety>
Read-only: do not modify, create, or delete any file inside any worktree; scratch files go under $TMPDIR only. No git command that writes. No network.
</action_safety>

<structured_output_contract>
End with:
  1. Verdict in one line: ship as is / fix before commit / needs redesign.
  2. A table: each original finding → closed / not closed / partially (with how you checked).
  3. New findings, most severe first: severity, `file:line`, defect, concrete failure scenario, CONFIRMED (how) or PLAUSIBLE, smallest fix.
  4. What you did not review.
</structured_output_contract>

===== REVIEW A — SDK (verbatim) =====
**Verdict: fix before commit.** I found nothing critical or high. The EVM signing core is sound. The problems are in the session/worker protocol, where the code departs from DECISION-12, plus test gaps and small doc errors.

## Findings, most severe first

1. **Medium — a reply that arrives after its deadline still crosses the boundary, mnemonics included.** `worker/worker_loop.dart:228`, `session/session.dart:432-441`, `worker/protocol.dart:87-131`
   - **Defect:** the executor always posts its reply and the session throws late ones away. DECISION-12 §3.9 says such a result is "dropped without being posted, not posted and ignored". `Init` also leaves out the timeouts that §3.2 puts in it, so the executor can't know a deadline has passed.
   - **Scenario:** `exportMnemonic()` runs past `walletOperation`. The caller gets `OperationTimeoutError`, but `MnemonicExported` is still posted. Once T2.1 adds a real worker isolate, that mnemonic is copied into the UI isolate's heap for nobody, where it can't be erased.
   - **CONFIRMED** by reading the code. The test `session_test.dart:291` builds this behaviour in.
   - **Fix:** carry each operation's deadline (or `Init` timeouts plus a submit time) to the executor. After the handler's `finally`, the loop drops the reply if the deadline has passed. Keep the session-side discard as a backstop.

2. **Medium — `close()` called during `closing` reports success after a forced kill.** `session/session.dart:491-492`, with the swallow at `:281-291`
   - **Defect:** in `closing`, `close()` returns the `_shutdown` future. That future completes normally even when the grace period ran out and the executor was killed without acknowledging.
   - **Scenario:** I ran an experiment with a slow `DisposeRef` and a 50 ms grace period:
     - `w3.close()`, issued while ready → `WorkerTerminatedError`.
     - `w2.close()`, issued while closing → "completed normally", with `forcedTermination == true`.

     Neither handle was acknowledged. lifecycle.md §2 says close completes with `WorkerTerminatedError` if the isolate ends first. M0's kill does release the handles, but a killed T2.1 isolate does not, so this would be a false "released".
   - **CONFIRMED** by experiment.
   - **Fix:** `return _shutdown!.then((_) { if (_forcedTermination) throw const WorkerTerminatedError(WorkerTerminationKind.isolateExited); });`

3. **Medium — soft native failures end the whole session.** `worker/handler.dart:37-43, 107-117`, `engine/hd_wallet.dart:337-344`, `engine/secret_buffers.dart:59-61, 87-89, 129-131, 158-160`
   - **Defect:** a null return or out-of-range size from upstream throws `StateError` or `RangeError`. The handler rethrows it, the loop treats it as a fault, and the session moves to `failed`. DECISION-12 §3.10 says these are a typed error for that one operation and the session stays `ready` (TM-19/20).
   - **Scenario:** a corrupt `TWDataSize` during `account()`, or a null from `TWPrivateKeyData` during `sign`, kills every wallet in the session.
   - **CONFIRMED.** `session_test.dart:128-153` asserts exactly this ("corrupt size" → `failed`).
   - **Fix:** map these native-boundary checks to typed per-operation errors (as `SyncSigningCore` already does for its output). Alternatively, amend §3.10 if the stricter rule is wanted.

4. **Medium — the set of messages that carry secrets was widened without a decision.** `worker/protocol.dart:31-41, 274-327, 637-652`
   - **Defect:** `ValidateMnemonic`, `ValidateMnemonicWord`, `SuggestMnemonicWords` and `MnemonicWordsSuggested` carry mnemonic material. DECISION-12 §3.2 closes that set at four payloads, and §8 trigger 6 says adding one reopens the record. The code's own comment admits this. lifecycle.md §6's counts ("13 requests and 14 replies", "four of the 27") are now wrong.
   - **CONFIRMED** by reading.
   - **Fix:** owner decision before commit — reopen DECISION-12 §3.2 and update lifecycle.md §6 (and the memory contract), or take the helpers out.

5. **Low–medium — no test proves the signature comes from the key the caller named.** `test/signing/signer_native_test.dart:81-137`
   - **Defect:** the public-flow test compares against `withDerivedKey` plus `SyncSigningCore`, which is the same code path. The byte-for-byte vector uses a raw key.
   - **Scenario:** if `withDerivedKey` derived the wrong path or coin, both sides would agree and the test would pass.
   - **CONFIRMED** gap. The code itself is correct: a throwaway run of `withDerivedKey` at the `ethereum-address-n/a-1` path gave the vector's public key.
   - **Fix:** add that comparison as a native test.

6. **Low — the public-surface test is weaker than its name.** `test/public_surface_test.dart:118-130`
   - It reads only the directly exported files, so it skips the part file `requests/evm/evm_transaction_request.dart`.
   - It never looks for generated registry types (`CoinType`, `CoinInfo`), so a public member typed `CoinType` in `coin.dart` would pass.
   - **CONFIRMED.** Fix: cover part files and registry type names until T1.15 replaces this.

7. **Low — zeroing the entropy copy only works in M0.** `wallet/wallet.dart:41-47`, `worker/protocol.dart:157-160`, `worker/transport.dart:90-96`
   - Once T2.1 sends over a SendPort, only the worker's copy is zeroed; the UI isolate's `ImportWallet.entropy` copy is not.
   - In M0, a request dropped because the transport is closed also skips `overwriteOwnedSecrets`.
   - **PLAUSIBLE** for T2.1 (the transport doesn't exist yet); the closed-transport skip is confirmed by reading.
   - **Fix:** zero the sender's copy after `send`, and on the transport's closed path.

8. **Low — `OperationCancelledError` can never reach a caller.** `wallet_core_flutter.dart:52`, `session/session.dart:446-455`
   - There is no public cancel. The only `Cancel` comes from a deadline, and by then the caller already has `OperationTimeoutError`.
   - PRD §14.3 says operations "can be cancelled before they start", but nothing public does it; the design sketch has no cancel method either.
   - **CONFIRMED.**

9. **Low — two tests can't fail as written.**
   - `signer_session_test.dart:129-139` is named for "imported and external" locators but sends only an external one.
   - `protocol_test.dart:80-91` builds a `WorkerFault` from a type name, so it can't fail. The real coverage is in `worker_loop_test.dart:177`.

10. **Low — factual slips in `DECISION-1-approach-a.md`.**
    - Line 91 says "About 500 lines"; its own ranges add up to about 700.
    - Line 88 says `key_fields.dart` has 31 lines; it has 30.
    - The native-call list at line 73 leaves out `TWStringSize` and `TWStringUTF8Bytes`, which are used to read the EIP-55 rendering.
    - The table at lines 97-104 leaves out the `MessageSigningInput.private_key` entries for Ethereum and Solana.
    - Also, `advanced.dart:29-31` says the protobuf classes "join it with the signing path"; the signing path is here and they don't.

11. **Low, informational — a kept signing result keeps the wallet open.** `signing/sign_result.dart:84-101` with `local_signer.dart:47`
    - A retained `SignResult.usedKeys` (an audit log, say) holds the `WalletRef` and so the wallet proxy. The proxy's finalizer then never releases the wallet's native handle (the seed).
    - This is documented on `WalletRef` but not on `SignResult`.

## Checked and true

- **Gates:**
  - `dart analyze --fatal-infos` is clean.
  - Unit tests: 251 passed. Native tests (`WCF_NATIVE_REQUIRED=1`): 66 passed. I ran these once; the doc's three runs are not re-checked.
  - Format: 387 files, 0 changed. Bindings: 64 unit and 42 native passed. The inventory is up to date.
- **Upstream sources:**
  - `PrivateKey.h:93` and `PrivateKey.cpp:399-400` (the key is zeroed on delete).
  - `TWPrivateKeyData` is `TWDataCreateWithBytes(pk->impl.bytes…)`, and `TWDataDelete` zeroes the buffer.
  - `RustCoinEntry.h` sets `private_key` on the JSON-parsed input; Ethereum's `signJSON` returns only `hex(encoded)`.
  - `Ethereum::Address::isValid` ignores letter case, so the SDK's EIP-55 check is a real addition.
- **Measurements on the host library:**
  - SignJSON support is 106 of 167 coins: Ethereum and Solana yes, Bitcoin no.
  - All five rows of the Solana nested-key table in §5 reproduce exactly. Appending only the nested key signs a different transaction and still reports error 0.
  - A 31-byte key signs.
- **Doc structure:** the §4 line ranges, the §5 `key_fields.json` rows, and the §7 test counts (15/5/11/5) are correct.
- **Key handling:**
  - The key is never set on a protobuf message.
  - The staging buffer is zeroed in a `finally`.
  - The executor order is resolve → check → derive → parse → release → reply.
  - The checks that must come before derivation do.
- **Isolate readiness:** every protocol value crosses a real isolate intact. Equality, unmodifiable views and `KeyRole` identity all hold.
- **Mnemonics:** variants with stray whitespace or upper case are all rejected by upstream, so none silently imports a different wallet.
- **AGENTS.md rules:** no forbidden words, the disclaimer is present, there is no `dart:io` or network use in `lib/`, and the default barrel exports no FFI, generated or protobuf type.
- **New dependencies** (rule 9 requires listing them in the final report): `ffi ^2.1.0`, `protobuf 6.0.0`, and the dev dependency `wcf_tool_vectors` (path).

## Not reviewed

- The native package (loader, identity verification).
- The bindings memory layer beyond what the SDK uses.
- Generated code, tools, CI, and the DECISION-14 diff.
- Coin, address, error, derivation-path, input-validation and coin-bridge tests, plus the engine and session native tests: names only.
- Release-mode removal of `LeakTracker`.
- Device platforms.
===== REVIEW B — Approach B (verbatim) =====
**Verdict: fix before commit.** No defect in the shipped default path exposes a key. But the C adapter's stated precondition is the wrong one, and both decision documents contain claims the code does not back.

Gates (re-run): `melos run analyze` is clean. `flutter test` passes 269, `--tags native` passes 81, `--tags shim` passes 12. I did not re-run format:check, inventory:check or the bindings/native packages' tests.

## Findings

**1. Medium — `wcf_sign.h:65-70`, `wcf_sign.c:124-128` (same pattern in Approach A's `signing_core.dart:249-253`), and `DECISION-1-approach-b.md` §3 (L95-99).**
- **Defect:** the contract only requires "field 9 absent". The property that actually matters is that the key-less input is a *complete, well-formed* message.
- **Scenario:** take a key-less input that ends inside a length-delimited field (for example `transaction{transfer{data: len 34}}` with 0 bytes left), plus a planted `private_key`. The appended `4a 20 <key>` is swallowed as the transfer `data`. Upstream returns `error = 0` and a broadcastable transaction, signed by the planted key, whose calldata is the victim's private key.
- **The opposite case is harmless:** a planted field 9 on a well-formed input is simply overridden, because the last occurrence wins and the real key signs. So the native "absence" check that §3 costs out guards the wrong thing.
- **Why it is not exploitable today:** Dart's decode in `checkKeylessInput` rejects truncated input. That stays true only while every future caller (for example `RawSigningInput`) runs the decode.
- **CONFIRMED:** C probe against the shim library (output decoded: calldata = `4a20 46…46`). A Dart probe confirmed the decode rejects that input.
- **Fix:** *prepend* the key field instead of appending it, in both the C adapter and `secretDataFromParts`. I verified prepending produces byte-identical signatures for well-formed input and no key in the output for the truncated case. Also restate the precondition in `wcf_sign.h` and in §3.

**2. Medium — `DECISION-1-approach-a.md` is stale after the seam change, and approach-b §11 item 6 (L243) wrongly says "its copy table is still right".**
- L21: the handler no longer hands the core a view; `SyncSigningCore.sign` now calls `TWPrivateKeyData`.
- L34: the file-map entry for `withDerivedKey` is wrong.
- L52: #2's lifetime is no longer "same as #1, released just before it"; it is released in the core's `finally`, before the handler returns.
- L59: the order line ("return to the handler → release #2") is wrong.
- L81-83: line ranges are now handler 243–402, hd_wallet 283–333, signing_core 70–305.
- L139 and L172: they cite a handler test showing a 32-byte key. That assertion was removed.
- **CONFIRMED** by diffing against the T1.12 tree.
- **Fix:** update those lines, and correct §11 item 6.

**3. Low — approach-b L77.** The row "Native objects holding the key that this SDK causes to exist" reuses approach-a's label with different members.
- Approach-a's "3" is {#1, #2, #4}. Approach-b's A = 3 is {#2, #3, #4}, and its B = 2 leaves out #1, which B also creates.
- Counted consistently, it is A 4 (#1–#4) vs B 3 (#1, #2, #4).
- **CONFIRMED** by reading both tables. **Fix:** count all four.

**4. Low — `build_apple.sh:165-169, 186, 192`.**
- **Defect:** `--with-shim` embeds the standard identity `as_4.8.0_000`, so `verifyIdentity` accepts the shim library wherever the standard one is expected. The shim tests pass using `hostIdentity` against the shim library.
- **Defect:** the "out-dir contains shim" check runs on the raw argument, before the path is canonicalised at L192.
- **Scenario:** `--out-dir $TMPDIR/shim/../wcf-native` passes the check and writes to the exact fallback path `run_native_tests.sh` loads. Standard native tests then silently run against a library with our C on the key path.
- **CONFIRMED:** the identity part by the passing test; the guard bypass by code reading (I did not run a build).
- **Fix:** canonicalise the path before checking, and give shim builds a distinct artifact-set id.

**5. Low — `handler.dart:27-31` and approach-b L54/L56** claim the adapter "can only ever bind to the verified image" and that `DynamicLibrary.process()` was rejected.
- On iOS, the loader tries `ProcessLibrary` first (`library_location.dart:204-205`). The adapter lookup and the `TWDataDelete` same-image comparison then both go through the process-wide handle, so the comparison can never fail.
- **CONFIRMED** by code reading.
- **Fix:** qualify the claim and add it to §5.3.

**6. Low — `adapter_signing_core.dart:51-63, 188`.** The hand-written FFI signature types the key as `Pointer<Void>`, so swapping the two pointer arguments compiles. C would then read a `TWPrivateKey` as a `TWData`.
- PLAUSIBLE: no current caller swaps them.
- **Fix:** type the parameter as `Pointer<TWPrivateKey>`.

**7. Low — test gaps.**
- None of the adapter core's own guards is tested: the StateError for a wrong injection field, the `'signing-adapter'` UnsupportedOperationError, and the `bindAdapter` same-image StateError. Both libraries needed for the last one exist.
- Approach A's production `sign` (handle) path has no tamper or wrong-coin test proving rejection happens before `TWPrivateKeyData`. Those tests were moved to `signWithKeyBytes`.
- There is no test that a truncated key-less input never reaches the adapter (relevant given finding 1).
- The shim tests are never run in CI: they skip silently and `WCF_NATIVE_SHIM_REQUIRED` is not wired in.
- **CONFIRMED** by reading the tests.

**8. Low — approach-b §5.1 (L114).**
- The shim size 41,341,064 B (+368 B) comes from a different build than the hashed, tested library. That one (`c724bed2…`) is 41,341,096 B, so +400 B.
- The "standard" column (41,340,696 B) is not the `third_party/wcf-native` library the header names. That library is 41,242,056 B with a different `__TEXT` size.
- **CONFIRMED** by `stat`, `shasum` and `size`.

**9. Low — docs say upstream's signing-time copies are "not verified".**
- `RustCoinEntry.cpp:99` copies the whole keyed input into a Rust `TWData`. `tw_data.rs:75-78` frees it without wiping (there is no zeroize anywhere in `tw_memory`). This applies to both A and B.
- `TWPrivateKeyCreateWithData` also leaves an unwiped `Data bytes` copy, which affects §9's imported-key claim.
- **CONFIRMED** by reading the source. **Fix:** state these facts.

## Claims checked and found true
- The shim library's sha256 is `c724bed2…95360`.
- Defined external symbols are 29,436 / 30,004, with 464 `TW*`, and `__TEXT` sizes are as stated.
- The object's undefined references are the 7 listed `TW*` functions, `memcpy` and the stack protector.
- The source citations are correct: `TWDataDelete` overwrites with `memzero` (`TWData.cpp:106-115`), and the `PrivateKey.h:93` / `PrivateKey.cpp:399-400` lines on `~PrivateKey`/`cleanup` are right.
- The adapter returns NULL for NULL arguments, for 23 non-Ethereum-blockchain coins, and for out-of-enum values (0xFFFFFFFF, 0x80000000, 99999999).
- Across all 60 EVM-family coins, Approach B's output is byte-identical to A's.
- Neither the input nor the key is modified by the adapter. An empty input returns upstream's typed error rather than NULL.
- No Dart code on the B path calls `TWPrivateKeyData`. `NativeResource` is `Finalizable`, so the key handle stays alive across the FFI call.
- Approach B's lifetimes are as stated: #2 is deleted before `TWAnySignerSign`, #4 before Dart sees the output.
- The provenance enum values match the validator and record script.
- Test and line counts match: 3/10/2/2 tests plus 1; 674 test lines; 246 C lines; 218/128 Dart lines. The §7 line ranges are current.
- No forbidden words; the disclaimer is present. `wallet_core_flutter.dart` is unchanged from T1.12.

## Not reviewed
- The mobile packaging analysis in §5.2/§5.3, beyond the iOS loader point; I did not read `build_android.sh`.
- No shim rebuild, so wall time, the +368 B delta and the object sizes are unverified.
- No fuzzing of the C.
- T1.12 code outside the seam change (EVM encoder, session, protocol).
- The bindings memory layer beyond `TWDataHandle`.

All probes are in the scratchpad `rv/` directory; nothing in the worktree was modified.