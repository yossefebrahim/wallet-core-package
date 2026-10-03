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