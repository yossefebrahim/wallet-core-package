# D1-B — contracts audit (debater B)

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

Checkout: `wallet-core-package.worktrees/D1-B`, detached at `main` 4e1ff93. Nothing tracked was touched (`git status --short` → only `?? scratch_D1B/`). Probes, shims and logs are under `scratch_D1B/`; their sources are in B12.

**How the evidence was gathered, and its limits.**

- `melos` cannot run in this sandbox: it shells out to `flutter pub get`, and the Flutter wrapper cannot write its engine stamp (`Operation not permitted`). `flutter test` also cannot start (it binds a loopback socket; EPERM). So the gates were run through their underlying `dart` commands, and the SDK's `flutter_test` suites were run under plain `package:test` with two three-line shims for `flutter`/`flutter_test` (`scratch_D1B/shims/`).
- SDK suite under the shims: **277 pass, 2 fail** (279). Both failures are shim artefacts, not product defects: `dart test` runs all files in one process, and macOS `dlopen("libTrustWalletCore.dylib")` by bare name binds to the image an earlier file already loaded, so two "library cannot be loaded" tests see a library. Run alone, `test/worker/handler_test.dart` and `test/session/session_native_test.dart` pass (22/22). Bindings suite: **64/64** pass. `dart analyze --fatal-infos` on the three packages: **No issues found**.
- The SDK suite used the locally built host library (`third_party/wcf-native`, identity `as_4.8.0_000`, as `test:native` does); my probes used the release artifact from the hook cache (`as_4.8.0_001`, sha256 `4e0fed0a…` = the manifest's macOS digest). I could not run the device jobs and did not try.
- Anything not run is marked UNPROVEN.

---

## A. Verdict table

| Q | Verdict | Decisive evidence |
|---|---|---|
| 1 §11.2 items 1–8 | **Satisfied (8/8)**, two of the proofs weaker than they look | Code: `native_resource.dart:34-125`, `wallet.dart:243-315`. My probe redirecting the delete to `free`: forgotten handles 50/50 freed by the NativeFinalizer; disposed handles survive GC with no double free; control (finalizer left attached) aborts, exit 134. Item 5's test asserts only a self-reported flag; item 8's native test silently skips when run alone (C3). |
| 2 sync free from a public object | **No** | Every public close path posts through `InProcessTransport` (microtask → `Timer.run`); the only synchronous native frees are `WorkerLoop._stop`→`releaseAll`, reached from the shutdown-grace timer or a fault, never from a caller's `close()`/`dispose()` frame (B2). |
| 3 close/shutdown semantics | **Satisfied for what Phase 1 claims; real in-flight overlap is untestable until T2.1** | Probes P1a–P1d: `close()` memoised, queued ops complete before the dispose, `close()`‖`shutdown()` completes, `shutdown()` rejects queued ops with `SessionStateError`, both idempotent. Deferrals are documented (DECISION-12 §1, §3.5 "Recorded for T2.1"; security/lifecycle.md). |
| 4 key-field check | **Satisfied; no smuggling found** | One injection path (`signing_core.dart:167,178-181`), checked twice (`handler.dart:346`, `signing_core.dart:167`) before any key exists. Probe: populated, empty, duplicated, wrong-wire-type, unknown-field and truncated key fields are all rejected; native receives `4a20‖key‖keyless`. |
| 5 S5 validation | **Partially** | Every public entry point validates (table in B5) **except** the EVM `contractCall` `data` length: a >64 MiB payload raises a `RangeError` that the handler treats as a defect and **kills the session and releases every wallet** (probe P2; C1). |
| 6 generated files | **Satisfied** | All four generators re-run (ffigen → inventory → format, `proto.sh`, `registry_transform`, `manifest embed`): `git diff --exit-code` on the generated paths → 0, no untracked outputs. `melos run gen:check` itself could not run here (sandbox). |
| 7 public surface | **Satisfied** | `lint:public-api` 49 elements, 0 violations; independent grep over every exported file: no `dart:ffi`, `Pointer`, `TW*`, `GeneratedMessage`, or `CoinType` in a public signature; `Coin._type` is private. |
| 8 vectors | **Satisfied; provenance of invalid_input entries thin** | Both spot-checked vectors match the cited upstream lines exactly (quoted in B8). `invalid_input` entries cite a standard by name only, and two of the three cite the wrong or an inapplicable standard. |
| 9 wording | **Satisfied** | No "zeroization", "secret-free", "audited", AGPL or legal claim, and no "reproducible" about artifacts in README, docs/, package READMEs, example README (only forward-looking "reproducibility [REQ]" in DECISION-9). Disclaimer present on every project description. |
| 10 secrets in diagnostics | **Satisfied** | Probe P5: sentinel mnemonic/passphrase through 11 rejection paths, 7 `toString()`s and the leak report → zero occurrences. No `print`/`debugPrint`/`developer.log`/env read in any `lib/`. |
| 11 threat-model rows | **Rows mostly honest, but 5 rows/lines are stale since T1.17** and TM-21 over-claims | TM-36, TM-10, TM-23, TM-28, §6 "Open for D1/D6" describe CI/no-network as pending; both exist now. TM-21's "lengths validated in Dart" is false for `data`. TM-30 release-mode test still absent (honestly marked pending). |

---

## B. Details

### B0. Gate results

| Gate | Result | How it was run |
|---|---|---|
| `lint:public-api` | `49 exported elements checked, 0 violations` | `dart run tools/lint/bin/public_api_lint.dart` |
| `vectors:validate` | `Files: 2 / Vectors: 5 / Exclusions: 0` | `dart run tools/vectors/bin/validate.dart test_vectors` |
| `inventory:check` | functions 466/466, enums 19/19, `inventory.json` and `symbol_names.dart` up to date | `dart run tools/inventory/bin/symbols.dart --check` |
| `manifest:validate` | `Manifest is valid.` | `dart run tools/manifest/bin/validate.dart compat_manifest.json` |
| `lint:runtime-deps` | `Network Symbols: OK`, `Build-time (hook) imports: OK` | `dart run tools/lint/bin/runtime_deps_check.dart` |
| `gen:check` (by hand, step for step) | diff exit 0; no untracked generated files | ffigen (`ffigen.dart --config ffigen.yaml`, workspace package_config), `symbols.dart`, `dart format …/generated/ffi` ("0 changed"), `tools/gen/proto.sh` ("60 .proto in → 180 .dart out", `key_fields.json` 49 messages / 53 fields), `registry_transform.dart`, `embed.dart` ("unchanged" ×2) |
| `analyze` | No issues found (3 packages, `--fatal-infos`) | `dart analyze --fatal-infos packages/...` |
| Tests | bindings 64/64; SDK 277/279 (2 shim artefacts, 22/22 when run alone) | `scratch_D1B/dtest.sh`, `scratch_D1B/sdktest.sh` |

### B1. PRD §11.2, item by item

| # | Verdict | Code | Test (name) / my probe |
|---|---|---|---|
| 1 `dispose()` on every wrapper, documented as primary | **Satisfied** (nit C6) | `NativeResource` `native_resource.dart:34`, `dispose()` `:101`; docs say "primary cleanup path" on `NativeResource`, `TWDataHandle`, `TWStringHandle`, `PrivateKeyHandle` (`handles.dart:61`), `HDWallet` (`hd_wallet.dart:24`); **not** on `PublicKeyHandle` (`handles.dart:87`) or `AnyAddressHandle` (`:111`), one-line docs | `disposal_contract_test`: "item 1 — every native-backed wrapper exposes dispose(), and disposal is the cleanup path that actually runs" (TWData/TWString only). SDK handles: `engine_native_test` "double dispose is a no-op" (HDWallet); no direct dispose test for Private/Public/AnyAddress handles, only leak-count assertions (`signing_core_native_test`: `tracker.report.disposed`). |
| 2 dispose = delete + **detach** + mark | **Satisfied** | `native_resource.dart:101-114`: `_disposed = true` first, `releaseNative`, then in `finally` `_finalizer.detach(this)`, observer notified. | "item 2 — dispose() calls the upstream delete, detaches the finalizer, and marks the wrapper disposed" — the detach is observed only through the wrapper's own `isFinalizerAttached` bool, which the wrapper sets itself. **Independent proof:** `probe_finalizer.dart disposed` (B1a). |
| 3 double-dispose no-op; `DisposedError` after | **Satisfied** | `:102` early return; `rawPointer` `:83-86` and `checkNotDisposed` `:119`; `HDWallet._wallet` throws the SDK's `DisposedError`. | "item 3 — double dispose is a no-op and any use after disposal throws DisposedError"; `engine_native_test` "use after dispose raises the SDK's DisposedError"; `probe_edge_test` "use after dispose / double dispose on rawPointer". |
| 4 temporaries in `finally` | **Satisfied** on every SDK path I traced | bindings `tw_data.dart:46-69`, `tw_string.dart:46-71`; SDK `secret_buffers.dart:41-71,75-98,113-141` (zeroed then freed); `HDWallet.create` frees the passphrase handle in `finally`; every other native temporary goes through `runScope`; `withDerivedKey` scope; `SyncSigningCore.sign` `finally` (`signing_core.dart:205-207`). | "item 4 — temporaries are released in finally, so a throwing body still leaves nothing undisposed"; `engine_native_test` "a throwing body still releases everything", "a failing derivation releases its temporaries". Known, documented gap: the bindings' own staging buffers are not zeroed (memory_contract.md "Known gaps"). |
| 5 NativeFinalizer fallback, token = pointer, detach key = wrapper, callback = upstream delete, no Dart code | **Satisfied** | `native_resource.dart:54` `finalizer.attach(this, pointer, detach: this, externalSize: …)`; callbacks are `bindings.addresses.TWDataDelete` / `TWStringDelete` (`native_context.dart`) and `EngineFinalizers` (`handles.dart:23-45`); the `_SymbolAddresses` getters are generated (regeneration byte-identical). | "item 5 — a NativeFinalizer is attached at construction and detached on dispose" asserts only the flag; the test says the timing is not asserted. **Independent proof:** `probe_finalizer.dart forgotten` (B1a). |
| 6 scoped helpers | **Satisfied** | `resource_scope.dart` `runScope` (reverse order, body error wins, first dispose error otherwise). Public `WalletCore.scope` → `scope.dart` closes wallets via `close()`. | `resource_scope_test` "item 6 —" ×9; SDK `session_test` "scope (PRD §11.2 item 6) closes everything it created in reverse order on return / on throw / a failed creation inside a scope has nothing to close". |
| 7 debug leak tracker | **Satisfied** (debug); release inertness proven by me, not by CI | `leak_tracker.dart:183-…` `maybeCreate()` constructs only inside `assert`; `handler.dart:287-290` falls back to `NoopResourceObserver`. | `leak_tracker_test` "item 7 —" ×6 (the GC-dependent one passed when run alone). **My AOT probe** (`dart compile exe`, asserts off): `LeakTracker.maybeCreate() -> null (inert)`; with `--enable-asserts` → `ACTIVE`. The class is **not** compiled out (`observer is LeakTracker` remains, memory_contract.md says so); no CI gate (C5). |
| 8 public proxy `Finalizer` posts `Dispose(ref)` | **Satisfied** (test weaker than the claim) | `wallet.dart:243-251` (`Finalizer<_FinalizerTicket>`; the ticket holds the session and the integer, never the proxy), callback `session.dart:531` posts only while `ready`; `close()` detaches (`wallet.dart:315`). | `session_test` "the proxy finalizer callback (§3.7) posts DisposeRef only while ready, and never throws" calls the callback directly. `session_native_test` "a dropped proxy is released by its finalizer while the session is ready (best effort: skips when the collector does not run in time)": **run on its own it printed SKIPPED**; within the whole file it observed the release. First version of my probe (64×64 KB garbage per 5 ms for 20 s) never collected the proxy; with large retained-then-dropped buffers `probe_proxy_finalizer_test` P4 → `liveRefCount after churn: 0`, deterministic. |

**B1a — the NativeFinalizer proof the repo lacks** (`scratch_D1B/probe_finalizer.dart`, full source in B12). The real `NativeResource` wiring is used; only the delete symbol is redirected to libc `free` through `WalletCoreBindings.fromLookup`, and the "native object" is a `malloc` block, so a free is observable (`malloc_zone_from_ptr`) and a double free aborts.

```
== forgotten exit=0
forgotten: 50/50 blocks freed by the NativeFinalizer after churn
== disposed exit=0
disposed: survived churn without a double free (50 handles)
== control exit=134          # same shape, finalizer left attached after a manual free → abort
```

**What happens when a finalizer runs on a still-referenced native pointer.** The NativeFinalizer fires when the *Dart wrapper* is unreachable, not when the *address* is. The `forgotten` run is exactly that situation: the 50 raw pointers stayed in a list while their wrappers were dropped, and all 50 blocks were freed underneath them. The SDK's protection is `NativeResource implements Finalizable` (Dart keeps a `Finalizable`-typed local, parameter or `this` alive to the end of its scope), and every SDK site that extracts `.pointer` holds the wrapper in a typed local (`withDerivedKey(HDWallet wallet, …)`, `SyncSigningCore.sign`'s `input`/`output`, `HDWallet` methods via `this`; scope-registered handles are also held by `_Scope._resources`). I found no SDK path where a pointer outlives its wrapper. Nothing enforces it for a caller of `advanced.dart`: `rawPointer`/`pointer` are public and return a bare address (documented as outside the contract, `advanced.dart` statement 3). No test in the repo exercises this hazard.

### B2. Can a public object free a native pointer synchronously?

No. Trace of every public release path:

- `Wallet.close()` (`wallet.dart:308-316`) → `WalletCoreSession.releaseWallet` (`session.dart:489`) → `_sendControl(DisposeRef)` → `InProcessTransport.send` (`transport.dart`) → `scheduleMicrotask` → `WorkerLoop.receive` queues it → `Timer.run(_drainOne)` → `EngineRequestHandler._dispose` → `HDWallet.dispose()` → `TWHDWalletDelete`. Two event-loop hops after the call returns.
- The proxy `Finalizer` → `postFinalizerDispose` (`session.dart:531`) → `_post` → the same path.
- `WalletCore.shutdown()` → `Shutdown` control message → `EngineRequestHandler._shutdown` → `_disposeAll()` inside `_drainOne`, again a later event.
- `WalletCore.scope` closes via `wallet.close()`.
- Value types (`Account`, `Address`, `SignResult`, `KeyLocator`, `WalletRef`) hold no handle; `WalletRef` holds an int and the proxy.
- The only **synchronous** native frees are `WorkerLoop._stop()` → `_handler.releaseAll()` (`worker_loop.dart:302-310`), reached from `kill()`/`_fault`. Callers: the shutdown-grace `Timer` callback (`session.dart:257-262`) and executor faults — never a caller's `close()` stack frame. `shutdown()` in `failed` runs `_finishClosed()` synchronously, but the loop is already `_finished` there, so `releaseAll` is not re-run.
- `dispose()` that is synchronous exists on `TWDataHandle`, `TWStringHandle`, `HDWallet`, `PrivateKeyHandle`, `PublicKeyHandle`, `AnyAddressHandle`; the first two and `HDWallet` are reachable only through `advanced.dart`; the other three are internal (`src/engine/handles.dart`, not exported).

### B3. §14.3 / DECISION-12: `close()`, `shutdown()`, deferrals

What the same-isolate executor does, and why an overlap cannot be constructed today: `WorkerLoop._drainOne` runs one request per `Timer.run` event, and the native call is synchronous inside it, so no operation is ever "in flight" across a caller's `close()`. `close()` therefore always meets operations that are *queued*, and `DisposeRef` shares the FIFO with operations (`worker_loop.dart:128-141`), so it runs after everything queued ahead of it.

Probes (full source in B12, `probe_session_test.dart`; all pass):

| Probe | Observation |
|---|---|
| P1a | `w.exportMnemonic()` and `w.account()` queued, then `close()` ×2 (same `Future` object — `identical` true), then a call on the closed proxy → `ClosedError` immediately; the two queued calls still **complete with their values**; both `close()` futures complete; `shutdown()` ×2 return the identical future; `shutdown()` and `w.close()` after `closed` are no-ops; state `closed`. |
| P1b | `close()` immediately followed by `shutdown()`: the close future completes without error. |
| P1c | Five `account()` calls queued, `shutdown()` in the same turn: all five fail with `SessionStateError` (printed list), none hang (10 s bound). |
| P1d | `close()` ×2 after `shutdown()` completed: no throw. |

Existing tests that cover the rest and pass under the shim run: `session_test` "close() is idempotent, marks the proxy closed at once, and waits for work already submitted on the wallet", "close() has no deadline: it waits behind a slow operation and completes normally", "an operation already running when shutdown arrives completes…", "closing rejects new operations with SessionStateError at once…", "shutdown is admitted with the queue full".

**Deferred to T2.1 and whether the docs say so.**

| §14.3 item | State on main | Documented honestly? |
|---|---|---|
| Worker isolate (real isolation; `initialize()` spawns it) | in-process executor on the caller's isolate | Yes — DECISION-12 §1, security/lifecycle.md "The executor in this version", memory_contract.md "Where the executor runs", TM-23/25. |
| Cancel before start, public | internal only (`session.dart:544`), no caller; `OperationCancelledError` is exported but unreachable | DECISION-12 §3.5 "Recorded for T2.1", TM-26. **Not** in the public class doc of `OperationCancelledError` nor in security/lifecycle.md (C7). |
| Deadline carried in the isolate envelope | session-side clock + executor check, same isolate | DECISION-12 §3.5, TM-26. |
| `isolateExited` termination kind | only the in-process fault kinds occur | TM-25. |
| Forced stop that does *not* wipe | in-process `kill()` still releases every wallet | security/lifecycle.md "Forced shutdown" table says so explicitly. |
| Operation already in native code completes | trivially true (synchronous) | Yes. |

### B4. Key-field check

**Injection paths on main (Approach A): exactly one.** `SyncSigningCore.sign` is the only caller of `TWAnySignerSign` in any `lib/` (grep over `packages/*/lib` excluding `generated/`): `signing_core.dart:182`; the keyed bytes are assembled only by `secretDataFromParts(…, keyedInputParts(…))` at `:178-181`.

| Step | Where | Check |
|---|---|---|
| Handler, before any key exists | `handler.dart:345-346` `family.encodeKeylessInput(request)` then `checkKeylessInput(keyless, family)` | decode as the family's `SigningInput`, reviewed key-field list at any depth, no unknown field, no group |
| Core, again, before the key is read | `signing_core.dart:167` `checkKeylessInput(keylessInput, family)` | same; also coin ∈ family (`:160-165`), injection field belongs to the message (`:169-175`) |
| Key derived | `handler.dart:348` `withDerivedKey(…)` — after the first check | — |
| Reviewed list = generated list | `evm_family_test.dart` (passes); list `key_fields.dart:16-26`: `SigningInput.private_key = 9`, `MessageSigningInput.private_key = 1` | matches `third_party/wallet-core/src/proto/Ethereum.proto:259` and `:328`; I also scanned every upstream `.proto` for secret-looking names other than `private_key` (`seed`, `secret`, `mnemonic`, `password`, …): none in Ethereum.proto, and the other hits are public keys, network passphrases, or auth keys. |
| Other paths | Approach B adapter exists only on `eval/approach-b`; `advanced.dart` re-exports the raw bindings (`TWAnySignerSign`, `TWPrivateKeyData`) — a caller there is outside the contract by design; `src/session/testing.dart` and `startSession`'s test seams are reachable by `import 'package:…/src/…'` (convention only, C11). |

**Smuggling probe** (`probe_keyfield_test.dart`, B12). Key-less baseline = chain_id, nonce, to_address; appended variants of field 9 (`private_key`, tag `0x4a`):

```
populated key 32B at end                   -> InvalidInputError: … already carries the key field …private_key
explicit EMPTY private_key (4a 00)         -> InvalidInputError: … already carries the key field …
populated then EMPTY (last wins)           -> InvalidInputError: … already carries the key field …
EMPTY then populated                       -> InvalidInputError: … already carries the key field …
field 9 as varint (wrong wire type)        -> InvalidInputError: … already carries the key field …
unknown field 100                          -> InvalidInputError: … carries an unknown field (…field 100) …
truncated length-delimited                 -> InvalidInputError: … does not decode as TW.Ethereum.Proto.SigningInput
empty input (zero bytes)                   -> ACCEPTED   (see C12)
native input (accepted baseline): 4a20 5555…55 (32 bytes) 0a0101 120100 422a 3078…   # key prepended, key-less bytes follow intact
```

Nothing got past. The only accepted odd input is the zero-byte message (an empty `SigningInput`), harmless because upstream rejects it and the family encoder never emits it. The EVM request type has no free-form bytes except `data`, which the encoder places inside `Transaction.contract_generic` as a length-delimited field, so a hostile `data` cannot reach the top level.

### B5. S5 — every public entry point that reaches native code

| Entry point | Validation before the native call | Native-bound input left unvalidated |
|---|---|---|
| `WalletCore.initialize(queueLimit, timeouts)` | `queueLimit ≥ 1`, every timeout `> 0` (`session.dart:39-60`); no upper bounds (deadline arithmetic saturates, `protocol.dart` `OperationDeadline.after`) | none (no user bytes reach native) |
| `wallets.create(strength, passphrase)` | strength ∈ {128…256 step 32}; passphrase ≤ 1024 units, no NUL/unpaired surrogate (`input_checks.dart`); **repeated in the executor** (`HDWallet.create`) | none |
| `wallets.importMnemonic` | 12/15/18/21/24 words, ≤ 512 chars, NUL/surrogate; passphrase as above; BIP-39 checksum by upstream (`nullptr` → `InvalidInputError`) | word content is upstream's to judge |
| `wallets.importEntropy` | length ∈ {16,20,24,28,32}; passphrase | — |
| `Wallet.account(coin, network, style, path)` | `resolveDerivation` (coin/network/style supported), `checkDerivationPath` (`m/`, ≤ 255 levels, ≤ 10 digits, no leading zeros, < 2³¹, ≤ 1024 chars); repeated in the executor | — |
| `Wallet.exportMnemonic`, `Wallet.close` | proxy state; ref ownership in the executor | — |
| `addresses.isValid/parse` | `checkNetwork`; ≤ 512 chars, non-empty, NUL/surrogate-free, testnet-HRP logic (`engine.dart` `isValidAddress`) | — |
| `mnemonics.isValid/isValidWord/suggest` | shape / ≤ 64 chars / `[a-z]` only; local answer when implausible | — |
| `signer.sign/signWithKey` | request validated at construction (`EvmTransactionRequest`: EVM coin, `chainId ≥ 1`, `to` = `0x`+40 hex, nonce/value/gas/fees ∈ uint256); executor: locator resolution, session token, path, `checkRecipient` (valid for coin + EIP-55 for mixed case), key-less input check, native output parsed untrusted (`parseSigningOutput`) | **`data` length** (`contractCall`) — C1 |
| `signer.signMessage` | throws `UnsupportedOperationError` without any native call | — |
| `advanced.dart`: `HDWallet.create/fromMnemonic/fromEntropy/deriveAccount` | same checks as above | — |
| `advanced.dart`: bindings wrappers (`TWStringHandle.fromString`, `TWDataHandle.fromBytes`, raw `WalletCoreBindings`) | length ≤ 64 MiB only | **NUL in a string silently truncates; lone surrogate becomes U+FFFD** (`probe_edge_test`: `"ab\0cd"` → `"ab"`, `a\uD800b` → code units `[97, 65533, 98]`) — C4 |

**Probe P2 — what a hostile `data` length does** (`probe_session_test.dart`, `EvmTransactionRequest.contractCall(data: Uint8List(65 MiB))`, valid wallet and locator):

```
P2 error: WorkerTerminatedError: WorkerTerminatedError: the session isolate ended with an uncaught error (WorkerFault) ; state=SessionState.failed
```

Mechanism: `EvmTransactionRequest` has no cap on `data`; the encoder writes it; `checkKeylessInput` decodes it; `SyncSigningCore.sign` → `secretDataFromParts` → `checkNativeLength` throws `RangeError` (`secret_buffers.dart:118`) — not a `NativeResultError`, not a `WalletCoreException`; `EngineRequestHandler.handle` (`handler.dart:168-178`) does `if (mapped == null) rethrow;` by design ("a `RangeError` from a broken invariant of this SDK's own code … is rethrown", `handler.dart:80-90`); `WorkerLoop._drainOne` treats it as the executor dying (`_fault` → `_stop` → `releaseAll`). One oversized request thereby ends the session, disposes **every** wallet in it, and fails all pending calls. No secret is leaked (the key handles are released by their scopes before the rethrow), and recovery is a re-`initialize()` plus re-import. Every other length-bearing path I traced is capped or mapped (`readNative` turns `RangeError`/`StateError` into `NativeResultError` on the address, path, mnemonic and derivation paths).

### B6. Generated-file integrity

- All four generators reproduce the committed files byte for byte (B0). The 8 lines `59e2f3a` added to `wallet_core_bindings.dart` (the `_SymbolAddresses` getters for `TWAnyAddressDelete`, `TWHDWalletDelete`, `TWPrivateKeyDelete`, `TWPublicKeyDelete`) are what ffigen produces from `ffigen.yaml:65` today, so they are generator output, not a hand edit.
- `git log -- ':(glob)packages/*/lib/src/generated/**'`: `1d70c6c`, `6f7b520`, `59e2f3a`, `f9f3d58`; each coincides with a commit that also touched the generator inputs (`ffigen.yaml`, `tools/gen`, `tools/manifest`).
- `docs/capability_matrix.*` does not exist yet (no `gen:matrix`), so there is nothing to check there.
- Not verified here: that CI's `gen:check` job is green on `08e3b17` (PROGRESS says it is; I did not run CI).

### B7. Public export surface

- Independent grep (`dart:ffi`, `Pointer`, `\bTW[A-Z]`, `GeneratedMessage`, `package:protobuf`, `CoinType`, `wallet_core_flutter_bindings`) over `wallet_core_flutter.dart` and every file it exports: the only hits are `coin.dart` (`import registry.dart`, the **private** field `Coin._type`, and file-private helpers `registryIdOf`/`registryCoinTypeOf`, none exported — `wallet_core_flutter.dart:41` exports `Coin, CoinStatus` only).
- Exceptions' fields: `NativeLoadError.cause` and `WorkerTerminatedError.cause` are `Object?` (runtime values may be `dart:ffi` errors; no FFI type appears in a signature); `ManifestMismatchError.check` is the native package's `ManifestCheck` enum, re-exported deliberately (`wallet_core_flutter.dart:28-30`).
- `toString()` of every public type: `WalletRef(#id)`, `Wallet(#id[, closed])`, `HdKeyLocator(wallet, coin.id, path)`, `EvmTransactionRequest.*` (data as byte count), `EvmSignResult` (signed output only), `Account`/`Address` (public data). No secret.
- `advanced.dart` re-exports the bindings barrel (generated `WalletCoreBindings`, memory wrappers) and `registry.dart`; it does **not** re-export protobuf classes (rule 4/6 hold; `advanced.dart:29-36` says so).

### B8. Vectors

`ethereum-address-n/a-1` (`source.path: swift/Tests/Blockchains/EthereumTests.swift`, commit `d692ac27…`). The file exists in `third_party/wallet-core`; the test is `testGetPublicKeyFromXpub`, lines 240-256:

```
241: let wallet = HDWallet(mnemonic: "broom ramp luggage this language sketch door allow elbow wife moon impulse", passphrase: "")!
242: let path = "m/44'/60'/0'/0/1"
252: XCTAssertEqual(pubkey2.data.hexString, "044516c4aa5352035e1bb5be132694e1389a4ac37d32e5e717d35ee4c4dfab513226a9d14ea37a55962ad3644a08e2ce551b4495beabb9b09e688c7b92eba18acc")
255: XCTAssertEqual(address, "0x996891c410FB76C19DBA72C6f6cEFF2d9DD069b1")
```

Mnemonic, path, public key and address in the vector all equal these. The vector cites the file but not the test function or lines (nit C9).

`ethereum-sign-eip1559-1` (`tests/chains/Ethereum/TWAnySignerTests.cpp`): the comment claims `TEST(TWAnySignerEthereum, SignERC1559Transfer_1442), lines 313-349`. Upstream has exactly that test at 313-349:

```
313: TEST(TWAnySignerEthereum, SignERC1559Transfer_1442) {
314:     auto chainId = store(uint256_t(3));
315:     auto nonce = store(uint256_t(6));
316:     auto gasLimit = store(uint256_t(21100));
317:     auto maxInclusionFeePerGas = store(uint256_t(2000000000));
318:     auto maxFeePerGas = store(uint256_t(3000000000));
319:     auto toAddress = "0xB9F5771C27664bF2282D98E09D7F50cEc7cB01a7";
320:     auto value = uint256_t(543210987654321);
322:     auto key = parse_hex("4f96ed80e9a7555a6f74b3d658afdd9c756b0a40d4ca30c42c2039eb449bb904");
338:     std::string expected = "02f8710306847735940084b2d05e0082526c94b9f5771c27664bf2282d98e09d7f50cec7cb01a78701ee0c29f50cb180c080a092c336138f7d0231fe9422bb30ee9ef10bf222761fe9e04442e3a11e88880c64a06487026011dae03dc281bc21c7d7ede5c2226d197befb813a4ecad686b559e58";
345:     EXPECT_EQ(hex(output.v()), "00");
346:     EXPECT_EQ(hex(output.r()), "92c336138f7d0231fe9422bb30ee9ef10bf222761fe9e04442e3a11e88880c64");
347:     EXPECT_EQ(hex(output.s()), "6487026011dae03dc281bc21c7d7ede5c2226d197befb813a4ecad686b559e58");
```

Every input and every expected value in the vector equals upstream's (including `v`, `r`, `s`); the vector's note that the Etherscan hash in the upstream comment is deliberately not asserted is right — the test never compares it. `data: ""` ↔ `transfer.set_data(Data().data(), 0)` ✓.

Caveat: `third_party/` is not a git checkout (a `git rev-parse` inside it resolves to the parent repo), so "at the pinned commit `d692ac27…`" is what the fetch tooling records, not something I verified against a `.git`. Separately, `third_party/wcf-native/…/libTrustWalletCore.dylib` is a local build (sha256 `bb9266dc…`, identity `as_4.8.0_000`) and is **not** the manifest's macOS artifact (`4e0fed0a…`, set 001); the suite is run against the former.

`invalid_input` entries — are the provenance lines meaningful?

| Vector | Cites | Assessment |
|---|---|---|
| `…invalid_input-n/a-1` (12× "abandon") | standard BIP-39 | Meaningful: the checksum word makes it invalid (the valid form ends "about"). No section cited. |
| `…invalid_input-n/a-2` (`0xZZZ…`) | standard EIP-55 | Weak: EIP-55 defines the mixed-case checksum, not rejection of non-hex digits. The vector is invalid by the plain `0x`+40-hex address syntax. |
| `…invalid_input-n/a-3` (`m/44/60/invalid`) | standard BIP-44 | Weak: path *syntax* (numeric, optional `'`) is BIP-32; BIP-44 defines the 5-level layout. |

The schema accepts all three (`kind: standard` + a `reference` string); `vectors:validate` checks presence, not meaning. The corpus is 5 vectors in total (`vectors:validate`), consumed by `engine_native_test`, `session_native_test`, `derivation_path_test`, `soft_native_failure_native_test`, `sign_handler_native_test`.

### B9. Forbidden wording (AGENTS.md rule 8)

Grep for `zeroiz*|secret-free|secret free|audited|reproducib*|AGPL|legal` over `README.md`, `docs/security`, `docs/architecture`, `docs/decisions`, the three package READMEs, `example/README.md`, `THIRD_PARTY_NOTICES.md`, `packages/*/lib`, `packages/*/lib/src/memory`:

- `zeroization`, `secret-free`, `audited`: **no match**.
- `reproducib*`: only `DECISION-9.md:86,100,143,166` ("PRD §12.4's Demonstrated reproducibility [REQ] reaches its M3 milestone", i.e. a requirement not yet met, not a claim about artifacts).
- `AGPL`: only `DECISION-8.md:198-199`, stating that the README draft makes no AGPL or legal claim.
- `legal`: `DECISION-12.md:24` ("the only legal way to free a handle", i.e. permitted by the runtime, not a legal claim).
- Excluded from the grep as non-product text: `docs/plan/`, `docs/archive/`, `docs/audit-resaults/`, the PRD (which states the rules).
- Disclaimer check (exact sentence) in README, example README, three package READMEs, `docs/security/*`, `docs/architecture/*`, `DECISION-1x`, `THIRD_PARTY_NOTICES.md`, `test_vectors/README.md`, every pubspec `description`: present everywhere except `test_vectors/README.md` and the workspace root `pubspec.yaml` ("Private workspace root … ships nothing"), neither of which describes the project to a reader (nit-level, not a finding). `example/pubspec.yaml` carries it across a folded line.
- Package names: `wallet_core_flutter`, `_bindings`, `_native`, `_example`, `wcf_tool_*`: none contains "trust".

### B10. Secrets in diagnostics

Error/diagnostic constructors, and what each can quote:

| Source | Message built from | Secret risk |
|---|---|---|
| `InvalidInputError` (`input_checks.dart`, `derivation_path.dart`, request ctor, engine) | constants, input *names*, counts (`got $strength`), coin/network ids | none; no input text |
| `UnknownCoinError` | the caller's coin id, truncated to 64 chars | a coin id is not a secret |
| `DisposedError`/`ClosedError` (SDK and bindings) | `resourceType` | none |
| `WorkerTerminatedError` | termination kind and `cause.runtimeType` | none; the executor's own message is withheld (`WorkerFault`, `worker_loop.dart:17-35`) |
| `SigningError.message` | upstream's `error_message` field, or fixed strings | upstream text; no key bytes by construction (`SigningOutput` carries none) — UNPROVEN what upstream writes for malformed input |
| `NativeResultError`, `RangeError.range` (`limits.dart`) | upstream function name, numbers | none |
| `NativeLoadError` | library locations and the OS loader's reason | file paths, not secrets |
| `ManifestMismatchError` | manifest ids/hashes | public |
| Protocol `toString()` | `<redacted>` for every secret-bearing field | none |
| `LeakReport`/`LeakRecord` | id, type name, allocation stack trace | none (stack traces carry no arguments) |
| bindings handles | type, length, disposed flag | length only |

**Probe P5** (`probe_diag_test.dart`): sentinel words `zebra ×12` and passphrase `SENTINELPASSPHRASE9f3a` through invalid-checksum mnemonic, NUL passphrase, over-long passphrase, wrong word count, bad strength, bad entropy length, `mnemonics.isValid/suggest`, unknown coin, bad path, use-after-close, plus `toString()` of `ImportWallet`, `CreateWallet`, `ValidateMnemonic`, `MnemonicExported`, `Failed`, `WorkerTerminatedError`, bindings `DisposedError`, and the leak report. Output lines (excerpt): `InvalidInputError: not a valid BIP-39 mnemonic`, `ImportWallet(#1, mnemonic: <redacted>, passphrase: <redacted>)`, `LeakReport(live: 0, disposed: 7, finalizedWithoutDispose: 0, stopped)`. Assertions that neither sentinel appears: pass. Stack-trace heads printed with them contain code locations only.

No `print(`, `debugPrint`, `developer.log`, `stdout`/`stderr`, `Platform.environment` or `String.fromEnvironment` in `packages/wallet_core_flutter/lib`, `packages/wallet_core_flutter_bindings/lib`, or `packages/wallet_core_flutter_native/lib` (grep, no output).

Residual, already recorded: the SDK cannot overwrite Dart `String`s, `TWStringHandle.fromString`/`toDartString` staging (memory_contract.md "Known gaps"), upstream's unwiped copies (rows 2, 6–8).

### B11. Threat-model rows — stated mitigation not found on main

I checked every row against the code or the CI file. Rows whose **as-built** text matches the code (verified by reading the cited lines or by a probe): TM-01, 02, 04, 06, 09, 11, 13, 17, 18, 19, 20, 22, 23, 24, 25, 26, 31, 32. Rows that are documentation or planned by design (cookbook, SECURITY.md, watcher, attestations: TM-03, 05, 07, 08, 12, 14–16 as far as they describe T3/T4 work, 27, 29, 33–35) have no implementation to find; I did not audit the build scripts (second debater / D1a).

Rows with a stated mitigation or status that does **not** hold on main:

| Row | Statement | Reality |
|---|---|---|
| TM-21 | "Addresses, derivation paths, amounts, chain ids, and lengths are validated in Dart; invalid input raises `InvalidInputError` without reaching native code" | `data` length is not validated; the failure is a session-killing `RangeError` (B5, C1). |
| TM-36 | "CI … not `test:native`, `lint:public-api`, `lint:runtime-deps` or `vectors:validate`; the device jobs are placeholders; `main` has not run in CI" | `ci.yml:53-60` runs `lint:public-api`, `vectors:validate`, `lint:runtime-deps`; `:153-196` the native job with `test:native` and `test:no-network`; `:198+` real device jobs; PROGRESS (4e1ff93) records CI green on `08e3b17`. |
| TM-10 | "the S4 runtime test … does not exist" | `melos run test:no-network` + `test/session/no_network_test.dart` exist and run in CI (`ci.yml:195-196`). |
| TM-23 | "`lint:public-api` … CI does not run it (TM-36)" | CI runs it (`ci.yml:53-54`). |
| TM-28 | "`lint:runtime-deps` … which CI does not run (TM-36)" | CI runs it (`ci.yml:59-60`). |
| §6 "Open for D1/D6" | "CI wiring (TM-36) and the S4 no-network runtime test (TM-10) — both T1.17; both pending" | Both done; list should shrink. |
| TM-30 | release-mode proof pending | Still true (honest) — no CI test; my AOT probe shows the tracker inert today (C5). |
| TM-26 | no public cancel; `OperationCancelledError` unreachable | True (honest); not repeated in the public docs (C7). |

### B12. Probe sources (as run)

Wrapper scripts only set `PATH` to the SDK's own `dart`, point `--packages` at the workspace `package_config.json`, and set `WCF_NATIVE_LIB`.

#### P1a–P1d session lifecycle, P2 oversize `data` — `scratch_D1B/probe_session_test.dart`

```dart
// D1-B probes: session lifecycle semantics against the real host library.
// Plain package:test (the SDK's own tests need flutter_test, whose runner
// needs a local socket the sandbox denies).
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wallet_core_flutter/src/coin/coin.dart';
import 'package:wallet_core_flutter/src/errors/errors.dart';
import 'package:wallet_core_flutter/src/lifecycle/session_state.dart';
import 'package:wallet_core_flutter/src/requests/requests.dart';
import 'package:wallet_core_flutter/src/session/session.dart';
import 'package:wallet_core_flutter/src/session/wallet_core.dart';
import 'package:wallet_core_flutter/src/signing/key_locator.dart';
import 'package:wallet_core_flutter/src/wallet/wallet.dart';

const _mn =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon about';

Future<WalletCoreSession> start({int queueLimit = 32}) => startSession(
  queueLimit: queueLimit,
  timeouts: const OperationTimeouts(),
  hostLibraryPath: Platform.environment['WCF_NATIVE_LIB'],
);

void main() {
  test('P1a close() queued behind an in-flight/queued op, then shutdown(); '
      'both idempotent', () async {
    final core = await start();
    final w = await core.wallets.importMnemonic(_mn);
    // queue three ops, close the wallet, queue another, shut down
    final f1 = w.exportMnemonic();
    final f2 = w.account(Coin.ethereum);
    final c1 = w.close();
    final c2 = w.close();
    expect(identical(c1, c2), isTrue, reason: 'close() memoised future');
    await expectLater(w.exportMnemonic(), throwsA(isA<ClosedError>()));
    expect(await f1, _mn);
    expect((await f2).derivationPath, isNotEmpty);
    await c1;
    await c2;
    final s1 = core.shutdown();
    final s2 = core.shutdown();
    expect(identical(s1, s2), isTrue);
    await s1;
    await core.shutdown(); // no-op after closed
    await w.close(); // no-op after closed
    expect(core.state, SessionState.closed);
  });

  test('P1b close() racing shutdown(): close future completes without error',
      () async {
    final core = await start();
    final w = await core.wallets.importMnemonic(_mn);
    final c = w.close();
    final s = core.shutdown();
    await c;
    await s;
    expect(core.state, SessionState.closed);
  });

  test('P1c shutdown() with pending calls: queued ones rejected '
      'SessionStateError, none hang', () async {
    final core = await start();
    final w = await core.wallets.importMnemonic(_mn);
    final pending = <Future<Object?>>[
      for (var i = 0; i < 5; i++) w.account(Coin.ethereum).then<Object?>((a) => a, onError: (Object e) => e),
    ];
    final s = core.shutdown();
    final results = await Future.wait(pending).timeout(const Duration(seconds: 10));
    await s;
    // ignore: avoid_print
    print('P1c results: ${results.map((r) => r.runtimeType).toList()}');
    expect(results.every((r) => r is! Future), isTrue);
  });

  test('P1d close() after the session closed is a no-op and does not throw',
      () async {
    final core = await start();
    final w = await core.wallets.create();
    await core.shutdown();
    await w.close();
    await w.close();
  });

  test('P2 oversize contractCall data: typed error or session death?',
      () async {
    final core = await start();
    final w = await core.wallets.importMnemonic(_mn);
    final locator = HdKeyLocator(
      w.ref,
      Coin.ethereum,
      "m/44'/60'/0'/0/0",
    );
    final req = EvmTransactionRequest.contractCall(
      coin: Coin.ethereum,
      chainId: 1,
      nonce: BigInt.zero,
      to: '0x' + '11' * 20,
      data: Uint8List(65 * 1024 * 1024),
      maxFeePerGas: BigInt.one,
      maxPriorityFeePerGas: BigInt.one,
      gasLimit: BigInt.from(21000),
    );
    Object? error;
    try {
      await core.signer.signWithKey(req, locator);
    } on Object catch (e) {
      error = e;
    }
    // ignore: avoid_print
    print('P2 error: ${error.runtimeType}: $error ; state=${core.state}');
    // ignore: avoid_print
    print('P2 session state afterwards: ${core.state}');
    await core.shutdown().catchError((Object _) {});
  });
}
```

#### key-field smuggling — `scratch_D1B/probe_keyfield_test.dart`

```dart
// D1-B probe: can a populated/hidden private_key in the "key-less" bytes get past
// checkKeylessInput / SyncSigningCore.sign (Approach A, the only injection path)?
@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wallet_core_flutter/src/coin/coin.dart';
import 'package:wallet_core_flutter/src/errors/errors.dart';
import 'package:wallet_core_flutter/src/families/evm/evm_family.dart';
import 'package:wallet_core_flutter/src/signing/key_field_check.dart';
import 'package:wallet_core_flutter/src/signing/signing_core.dart';
import 'package:wallet_core_flutter/advanced.dart' show NativeContext, WalletCoreBindings;

Uint8List b(List<int> v) => Uint8List.fromList(v);

// A valid key-less SigningInput: chain_id(1)=0x01, nonce(2)=0x00, to_address(6)="0x"+40 ... gas_limit(5)
Uint8List keyless() {
  final to = '0x' + '11' * 20;
  final out = <int>[
    0x0a, 0x01, 0x01, // chain_id
    0x12, 0x01, 0x00, // nonce
    0x42, to.length, ...to.codeUnits, // to_address (field 8 -> tag 0x42)
  ];
  return b(out);
}

void main() {
  late NativeContext context;
  setUpAll(() {
    context = NativeContext(
      WalletCoreBindings(DynamicLibrary.open(Platform.environment['WCF_NATIVE_LIB']!)),
    );
  });

  final key = List<int>.filled(32, 0xAA);
  final cases = <String, Uint8List>{
    'populated key 32B at end': b([...keyless(), 0x4a, 0x20, ...key]),
    'explicit EMPTY private_key (4a 00)': b([...keyless(), 0x4a, 0x00]),
    'populated then EMPTY (last wins)': b([...keyless(), 0x4a, 0x20, ...key, 0x4a, 0x00]),
    'EMPTY then populated': b([...keyless(), 0x4a, 0x00, 0x4a, 0x20, ...key]),
    'field 9 as varint (wrong wire type)': b([...keyless(), 0x48, 0x01]),
    'unknown field 100': b([...keyless(), 0xa2, 0x06, 0x01, 0x00]),
    'truncated length-delimited': b([...keyless(), 0x32, 0x20, 0x01]),
    'empty input (zero bytes)': b(const []),
  };

  for (final e in cases.entries) {
    test('check: ${e.key}', () {
      Object? thrown;
      try {
        checkKeylessInput(e.value, evmFamily);
      } on Object catch (x) {
        thrown = x;
      }
      // ignore: avoid_print
      print('${e.key.padRight(42)} -> ${thrown == null ? "ACCEPTED" : "${thrown.runtimeType}: ${thrown is InvalidInputError ? thrown.message : thrown}"}');
    });
  }

  test('what native receives for the accepted baseline', () {
    Uint8List? seen;
    final core = SyncSigningCore(
      context,
      anySignerSign: (input, coin) {
        final data = context.bindings.TWDataBytes(input.cast());
        final size = context.bindings.TWDataSize(input.cast());
        seen = Uint8List.fromList(data.asTypedList(size));
        return nullptr; // -> SigningError(malformedOutput); we only observe the input
      },
    );
    try {
      core.sign(keyless(),
          family: evmFamily,
          coin: Coin.ethereum,
          privateKey: b(List<int>.filled(32, 0x55)),
          usedKeys: const {});
    } on SigningError {
      // expected: null output
    }
    // ignore: avoid_print
    print('native input: ${seen!.map((x) => x.toRadixString(16).padLeft(2, "0")).join()}');
    expect(seen!.sublist(0, 2), [0x4a, 0x20]);
    expect(seen!.sublist(2, 34), List<int>.filled(32, 0x55));
  });
}
```

#### NativeFinalizer attach / detach / control — `scratch_D1B/probe_finalizer.dart`

```dart
// D1-B probe: does the REAL NativeResource wiring (a) free a forgotten handle through the
// NativeFinalizer, and (b) detach the finalizer on dispose (no second free)?
//
// The wrapper's delete symbol is redirected to libc `free`, and the "native object" is a
// malloc'd block, so a free is observable with malloc_zone_from_ptr (macOS) and a double
// free aborts the process (libmalloc).
//
// usage: dart probe_finalizer.dart <forgotten|disposed|control>
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart';

final DynamicLibrary _process = DynamicLibrary.process();
final DynamicLibrary _real = DynamicLibrary.open(Platform.environment['WCF_NATIVE_LIB']!);
final Pointer<NativeFunction<Void Function(Pointer<Void>)>> _free = _process.lookup('free');
final int Function(Pointer<Void>) _zoneOf = _process
    .lookupFunction<IntPtr Function(Pointer<Void>), int Function(Pointer<Void>)>('malloc_zone_from_ptr');

Pointer<T> _lookup<T extends NativeType>(String name) =>
    name == 'TWDataDelete' ? _free.cast<T>() : _real.lookup<T>(name);

Object? _sink;
Future<void> churn() async {
  for (var round = 0; round < 40; round++) {
    for (var i = 0; i < 200; i++) {
      _sink = Uint8List(1 << 16)..[0] = i;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  _sink = null;
}

/// Allocated in its own frame so nothing here keeps the wrapper reachable.
Pointer<Void> _makeForgotten(NativeContext ctx) {
  final block = malloc<Uint8>(64).cast<Void>();
  TWDataHandle.adopt(ctx, block.cast<TWData>()); // dropped immediately
  return block;
}

Pointer<Void> _makeDisposed(NativeContext ctx) {
  final block = malloc<Uint8>(64).cast<Void>();
  final h = TWDataHandle.adopt(ctx, block.cast<TWData>());
  h.dispose(); // Dart-side delete = libc free (once)
  return block;
}

class _Fin implements Finalizable {}

Future<void> main(List<String> args) async {
  final mode = args.single;
  final ctx = NativeContext(WalletCoreBindings.fromLookup(_lookup));
  switch (mode) {
    case 'forgotten':
      final blocks = [for (var i = 0; i < 50; i++) _makeForgotten(ctx)];
      await churn();
      final freed = blocks.where((p) => _zoneOf(p) == 0).length;
      print('forgotten: $freed/50 blocks freed by the NativeFinalizer after churn');
    case 'disposed':
      final blocks = [for (var i = 0; i < 50; i++) _makeDisposed(ctx)];
      await churn();
      print('disposed: survived churn without a double free (50 handles)');
    case 'control':
      // Same shape, but a finalizer that is NOT detached after a manual free.
      final fin = NativeFinalizer(_free.cast());
      void make() {
        final p = malloc<Uint8>(64).cast<Void>();
        final o = _Fin();
        fin.attach(o, p); // never detached
        malloc.free(p);
      }
      for (var i = 0; i < 50; i++) {
        make();
      }
      await churn();
      print('control: SURVIVED (probe has no power)');
  }
}
```

#### P4 proxy Finalizer — `scratch_D1B/probe_proxy_finalizer_test.dart`

```dart
// D1-B probe: PRD 11.2 item 8 — a forgotten public proxy is released through the managed Finalizer.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wallet_core_flutter/src/session/session.dart';
import 'package:wallet_core_flutter/src/session/wallet_core.dart';
import 'package:wallet_core_flutter/src/worker/handler.dart';
import 'package:wallet_core_flutter/src/worker/transport.dart';

Object? _sink;
final List<Object> _keep = <Object>[];
void garbage() {
  // retained-then-dropped large buffers push the old-generation threshold
  for (var i = 0; i < 8; i++) {
    _keep.add(Uint8List(8 << 20)..[0] = i);
  }
  _keep.clear();
  for (var i = 0; i < 64; i++) {
    _sink = <int>[for (var j = 0; j < 4096; j++) j];
  }
  _sink = null;
}

Future<void> createAndDrop(WalletCoreSession core) async {
  await core.wallets.create();
}

void main() {
  test('P4 dropped proxy -> Finalizer -> DisposeRef -> handle released', () async {
    final handler = EngineRequestHandler();
    final core = await startSession(
      queueLimit: 32,
      timeouts: const OperationTimeouts(),
      hostLibraryPath: Platform.environment['WCF_NATIVE_LIB'],
      transport: InProcessTransport.factory(handler),
    );
    await createAndDrop(core);
    expect(handler.liveRefCount, 1);
    final stop = DateTime.now().add(const Duration(seconds: 20));
    while (handler.liveRefCount > 0 && DateTime.now().isBefore(stop)) {
      garbage();
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    // ignore: avoid_print
    print('P4 liveRefCount after churn: ${handler.liveRefCount}');
    expect(handler.liveRefCount, 0);
    await core.shutdown();
  });
}
```

#### P5 secrets in diagnostics — `scratch_D1B/probe_diag_test.dart`

```dart
// D1-B probe (S8 / TM-09 / TM-31): do sentinel secrets reach any error or toString?
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wallet_core_flutter/src/coin/coin.dart';
import 'package:wallet_core_flutter/src/errors/errors.dart';
import 'package:wallet_core_flutter/src/session/session.dart';
import 'package:wallet_core_flutter/src/session/wallet_core.dart';
import 'package:wallet_core_flutter/src/worker/protocol.dart';
import 'package:wallet_core_flutter/src/worker/handler.dart';
import 'package:wallet_core_flutter/src/worker/transport.dart';
import 'package:wallet_core_flutter/src/worker/worker_loop.dart' show WorkerFault;
import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart'
    hide DisposedError;
import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart' as b show DisposedError;

const sentinelWords = 'zebra zebra zebra zebra zebra zebra zebra zebra zebra zebra zebra zebra';
const sentinel = 'SENTINELPASSPHRASE9f3a';

void main() {
  test('P5 sentinel never appears in any error/toString on rejected inputs', () async {
    final handler = EngineRequestHandler();
    final core = await startSession(
      queueLimit: 32,
      timeouts: const OperationTimeouts(),
      hostLibraryPath: Platform.environment['WCF_NATIVE_LIB'],
      transport: InProcessTransport.factory(handler),
    );
    final rendered = <String>[];
    Future<void> attempt(String label, Future<Object?> Function() f) async {
      try {
        await f();
        rendered.add('$label: (no error)');
      } on Object catch (e, st) {
        rendered.add('$label: ${e.runtimeType}: $e');
        rendered.add('$label (stack head): ${st.toString().split("\n").take(3).join(" | ")}');
      }
    }

    await attempt('invalid-checksum mnemonic', () => core.wallets.importMnemonic(sentinelWords));
    await attempt('mnemonic+passphrase NUL', () => core.wallets.importMnemonic('$sentinelWords', passphrase: '$sentinel\u0000x'));
    await attempt('passphrase too long', () => core.wallets.importMnemonic(sentinelWords, passphrase: sentinel * 200));
    await attempt('mnemonic wrong word count', () => core.wallets.importMnemonic('zebra $sentinel'));
    await attempt('create bad strength + passphrase NUL', () => core.wallets.create(strength: 100, passphrase: sentinel));
    await attempt('entropy wrong length', () => core.wallets.importEntropy(Uint8List(7)));
    await attempt('mnemonics.isValid', () async => core.mnemonics.isValid(sentinelWords));
    await attempt('mnemonics.suggest', () async => core.mnemonics.suggest('zeb'));
    await attempt('unknown coin id', () async => Coin.byId('COINIDX'));
    final w = await core.wallets.create();
    await attempt('bad path', () => w.account(Coin.ethereum, path: "m/44'/$sentinel"));
    await w.close();
    await attempt('use after close', () => w.exportMnemonic());

    // protocol + request toString
    rendered.add(ImportWallet.mnemonic(1, sentinelWords, passphrase: sentinel).toString());
    rendered.add(CreateWallet(2, strength: 128, passphrase: sentinel).toString());
    rendered.add(ValidateMnemonic(3, sentinelWords).toString());
    rendered.add(MnemonicExported(4, sentinelWords).toString());
    rendered.add(Failed(5, InvalidInputError('x')).toString());
    rendered.add(const WorkerTerminatedError(WorkerTerminationKind.uncaughtDartError, cause: WorkerFault('StateError')).toString());
    rendered.add(b.DisposedError('TWDataHandle').toString());

    // leak report (debug build: assertions on in `dart test`)
    await core.shutdown();
    final obs = handler.observer;
    if (obs is LeakTracker) rendered.add(obs.report.toString());

    for (final line in rendered) {
      // ignore: avoid_print
      print(line);
    }
    final joined = rendered.join('\n');
    expect(joined.contains('zebra zebra'), isFalse, reason: 'mnemonic text leaked');
    expect(joined.contains(sentinel), isFalse, reason: 'passphrase text leaked');
  });
}
```

#### bindings edge cases — `scratch_D1B/probe_edge_test.dart`

```dart
// D1-B probe: bindings edge cases (empty buffers, NUL in strings) at the wrapper boundary.
@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart';

void main() {
  late NativeContext ctx;
  setUpAll(() {
    ctx = NativeContext(
      WalletCoreBindings(DynamicLibrary.open(Platform.environment['WCF_NATIVE_LIB']!)),
    );
  });

  test('empty TWData and empty TWString', () {
    final d = TWDataHandle.fromBytes(ctx, Uint8List(0));
    expect(d.length, 0);
    expect(d.copyBytes(), isEmpty);
    d.dispose();
    final s = TWStringHandle.fromString(ctx, '');
    expect(s.toDartString(), '');
    s.dispose();
  });

  test('bindings-level string with embedded NUL is silently truncated (advanced surface)', () {
    final s = TWStringHandle.fromString(ctx, 'ab\u0000cd');
    // ignore: avoid_print
    print('NUL string round-trips as: "${s.toDartString().replaceAll("\u0000", "<NUL>")}" length=${s.length}');
    s.dispose();
  });

  test('bindings-level lone surrogate becomes U+FFFD (advanced surface)', () {
    final s = TWStringHandle.fromString(ctx, 'a\uD800b');
    // ignore: avoid_print
    print('lone surrogate round-trips as codeUnits=${s.toDartString().codeUnits}');
    s.dispose();
  });

  test('use after dispose / double dispose on rawPointer', () {
    final d = TWDataHandle.fromBytes(ctx, Uint8List.fromList([1, 2, 3]));
    d.dispose();
    d.dispose();
    expect(() => d.pointer, throwsA(isA<DisposedError>()));
    expect(() => d.copyBytes(), throwsA(isA<DisposedError>()));
    expect(d.toString(), 'TWDataHandle(disposed: true)');
  });
}
```

#### release-mode (AOT) inertness of the leak tracker — `scratch_D1B/probe_release.dart`

```dart
// D1-B probe: is the leak tracker inert when assertions are off (AOT / release semantics)?
import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart';

void main() {
  final tracker = LeakTracker.maybeCreate();
  print('LeakTracker.maybeCreate() -> ${tracker == null ? "null (inert)" : "ACTIVE"}');
}
```

#### shim: flutter_test — `scratch_D1B/shims/flutter_test/lib/flutter_test.dart`

```dart
// D1-B shim: lets plain `dart test` run the SDK's non-widget tests.
export 'package:test/test.dart';

void markTestSkipped(String message) => print('SKIPPED: $message');
```

#### shim: flutter/foundation — `scratch_D1B/shims/flutter/lib/foundation.dart`

```dart
export 'package:meta/meta.dart' show visibleForTesting;

bool listEquals<T>(List<T>? a, List<T>? b) {
  if (a == null) return b == null;
  if (b == null || a.length != b.length) return false;
  if (identical(a, b)) return true;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
```

#### runner: SDK suite under the shims — `scratch_D1B/sdktest.sh`

```sh
#!/bin/zsh
# usage: sdktest.sh <test args...>   (run from the SDK package; flutter / flutter_test replaced by shims)
R=/Users/yossefebrahim/Work/wallet-core-package.worktrees/D1-B
export WCF_NATIVE_LIB=$R/third_party/wcf-native/macos/arm64_x86_64/libTrustWalletCore.dylib
export WCF_NATIVE_REQUIRED=1
export PATH=/Users/yossefebrahim/flutter/bin/cache/dart-sdk/bin:/Users/yossefebrahim/.pub-cache/bin:/opt/homebrew/bin:/usr/bin:/bin
cd $R/packages/wallet_core_flutter
exec dart --packages=$R/.dart_tool/package_config_shim.json /Users/yossefebrahim/.pub-cache/hosted/pub.dev/test-1.31.1/bin/test.dart -r expanded "$@"
```

#### runner: package:test directly — `scratch_D1B/dtest.sh`

```sh
#!/bin/zsh
# usage: dtest.sh <dir relative to repo root> <test files / args...>
# Runs package:test's runner directly with the workspace package_config (`dart test` tries a pub get, which the sandbox denies).
R=/Users/yossefebrahim/Work/wallet-core-package.worktrees/D1-B
export WCF_NATIVE_LIB=$R/.dart_tool/hooks_runner/shared/wallet_core_flutter_native/build/artifacts/macos/arm64_x86_64/libTrustWalletCore.dylib
export WCF_NATIVE_REQUIRED=1
export PATH=/Users/yossefebrahim/flutter/bin/cache/dart-sdk/bin:/Users/yossefebrahim/.pub-cache/bin:/opt/homebrew/bin:/usr/bin:/bin
cd "$R/$1" || exit 2
shift
exec dart --packages=$R/.dart_tool/package_config.json /Users/yossefebrahim/.pub-cache/hosted/pub.dev/test-1.31.1/bin/test.dart "$@"
```

#### runner: gen:all without melos — `scratch_D1B/regen.sh`

```sh
#!/bin/zsh
# regenerate everything gen:all does, without melos (melos shells out to the flutter wrapper, which cannot write its cache in this sandbox)
export PATH=/Users/yossefebrahim/flutter/bin/cache/dart-sdk/bin:/Users/yossefebrahim/.pub-cache/bin:/opt/homebrew/bin:/usr/bin:/bin
cd /Users/yossefebrahim/Work/wallet-core-package.worktrees/D1-B
echo "== proto"; bash tools/gen/proto.sh 2>&1 | tail -6
echo "== registry"; dart run tools/gen/bin/registry_transform.dart 2>&1 | tail -6
echo "== manifest"; dart run tools/manifest/bin/embed.dart 2>&1 | tail -6
echo "== diff"
git diff --stat -- "packages/*/lib/src/generated/" "docs/capability_matrix.*" "packages/wallet_core_flutter_native/assets/compat_manifest.json"
git ls-files --others --exclude-standard -- 'packages/*/lib/src/generated' 'docs/capability_matrix.*' packages/wallet_core_flutter_native/assets/compat_manifest.json
echo "diff-exit-code:"; git diff --exit-code -- "packages/*/lib/src/generated/" "docs/capability_matrix.*" "packages/wallet_core_flutter_native/assets/compat_manifest.json" > /dev/null; echo $?
```

---

## C. Findings

**C1 — should-fix-before-T2.0 — one oversized EVM `data` ends the session and releases every wallet (S5, TM-21).**
`packages/wallet_core_flutter/lib/src/requests/evm/evm_transaction_request.dart:35` (no length cap on `data`) → `engine/secret_buffers.dart:118` (`checkNativeLength` → `RangeError`) → `worker/handler.dart:177` (`if (mapped == null) rethrow;`) → `worker/worker_loop.dart:290-310` (`_fault`: session `failed`, `releaseAll`). Probe P2. PRD §16 S5 asks for typed `InvalidInputError` before native code; DECISION-12 §3.10 reserves session death for defects and the handler doc calls an unmapped `RangeError` "a broken invariant of this SDK's own code" — here it is the caller's input.
Fix: validate `data.length` in the `EvmTransactionRequest` constructor against a cap that leaves room for the header and key (`maxNativeBufferBytes − 64`, or a tighter product limit) with `InvalidInputError(inputName: 'data')`; and in `SyncSigningCore.sign` map `RangeError` from `secretDataFromParts` to `InvalidInputError('signingInput')` so a future family cannot reintroduce it. Add the test to T2.12's list ("amounts/lengths wider than the chain's integer width"). Owner: **new T1.R2** (one-file fix + two tests); T2.12 keeps the fuzz coverage.

**C2 — should-fix-before-T2.0 — threat model v0.2 is stale after T1.17; PRD §16 S6 asks for a revision at each milestone.**
`docs/security/threat_model.md`: TM-36 (whole row), TM-10 (no-network test "does not exist"), TM-23 and TM-28 ("CI does not run it"), §6 "Open for D1/D6 — CI wiring … both pending", header "refreshed against 672e09e". The D1 outline in `docs/plan/phases/phase-1-m0-spike.md` also makes "which threat rows changed this phase" a mandatory debate question. Also TM-21 (C1). Also the "Describes the SDK as of task T1.12" headers on `docs/security/memory_contract.md` and `docs/security/lifecycle.md` and README "Memory and Lifecycle". The statements in those two pages that I checked against code (the copy tables, the finalizer table, the shutdown/forced-stop table, the failure taxonomy) were accurate.
Fix: restate TM-10/23/28/36 and §6 with the CI line numbers, TM-21 after C1, bump the header dates. Owner: **new T1.R2** (docs) — it is the mandatory "threat model updated?" item of the D1 brief.

**C3 — should-fix-before-T2.0 — the finalizer tests prove less than the contract wording they carry.**
(a) `disposal_contract_test` "item 2" and "item 5" assert attach/detach through `NativeResource.isFinalizerAttached` (`native_resource.dart:77`, set at `:55` and `:111`), a bool the wrapper sets itself; a regression that stops calling `NativeFinalizer.detach` would not fail them. (b) `session_native_test` "a dropped proxy is released by its finalizer…" and `leak_tracker_test` "a handle collected without dispose()…" use ~2 MB of short-lived garbage for ≤5 s and `markTestSkipped` on failure: run in isolation the first one **SKIPPED** here, so CI can stay green with item 8 never observed.
Fix: replace (a) with the redirect-to-`free` technique of `probe_finalizer.dart` (real attach, real detach, double free would abort); make (b) allocate retained-then-dropped multi-MB buffers as `probe_proxy_finalizer_test` does, and fail rather than skip after the budget. Owner: **new T1.R2** (tests only) or T2.12.

**C4 — should-fix-before-T2.0 — bindings-level strings silently change content (advanced surface).**
`packages/wallet_core_flutter_bindings/lib/src/memory/tw_string.dart:46-71`: `TWStringHandle.fromString` passes `utf8.encode(value)` to a C-string constructor, so an embedded NUL truncates (`"ab\0cd"` → `"ab"`, `probe_edge_test`) and a lone surrogate becomes U+FFFD. The SDK facade rejects both (`checkNativeString`), but `advanced.dart` exports the wrapper, and a truncated passphrase is a *different wallet* (TM-04 calls the passphrase "silently load-bearing").
Fix: throw `ArgumentError`/`RangeError` in `fromString` on NUL or unpaired surrogate (the same predicate as `isNativeSafeString`, moved down to the bindings), with a test. Owner: **new T1.R2**.

**C5 — should-fix-before-T2.0 — no CI gate for release-mode inertness of the leak tracker (S8 [REQ], TM-30).**
Today it is inert (my AOT probe: `maybeCreate()` → `null`), but nothing keeps it so, T1.17's text does not list it (TM-30), and `leak_tracker_test` only checks the debug side. Fix: a small `dart compile exe` probe (as `scratch_D1B/aot.sh`) wired into `melos run test` or the CI `gates` job asserting `null`. Owner: **new T1.R2** (or a T1.17 follow-up).

**C6 — nit — `PublicKeyHandle` and `AnyAddressHandle` docs omit "dispose() is the primary cleanup path"** (`handles.dart:87,111`); PRD §11.2 item 1 asks for it on every class. Add the sentence; add a direct dispose/double-dispose/use-after test per handle type.

**C7 — nit — `OperationCancelledError` is exported and unreachable.** `errors.dart:398-405` and `docs/security/lifecycle.md` do not say that no public cancel exists until T2.1 (only DECISION-12 §3.5 and TM-26 do). One sentence each. Owner: T1.R2 docs.

**C8 — nit — `_cancelsSent` never shrinks** (`session.dart:155,455,549`): one entry per timed-out operation for the session's life. Remove the id when its reply arrives. Owner: T2.1.

**C9 — nit — vector provenance precision.** `ethereum-address-n/a-1` should name `testGetPublicKeyFromXpub` and lines 240-256; the `invalid_input` entries should cite the clause that makes the input invalid (BIP-39 checksum; plain hex-address syntax rather than EIP-55; BIP-32 path syntax rather than BIP-44). `vectors:validate` accepts any non-empty `reference`. Owner: T2.2–T2.4 vector tasks / T1.10 follow-up.

**C10 — nit — `checkKeylessInput` accepts a zero-byte message** (probe). Harmless today; reject empty input in the family check so "complete message" is literally true. Owner: T2.0.

**C11 — nit — "the public surface cannot reach the test seams" is true by convention only.** `startSession(hostLibraryPath:, expectedIdentity:, manifestBytes:)` and `initializeForTesting` are importable from `package:wallet_core_flutter/src/…` (TM-13 footnote `[^tm13-load]`). Standard Dart `src/` privacy; say so in TM-13 rather than "cannot".

---

## D. Doc/PROGRESS claims found false or overstated

| Claim | Where | Correct statement |
|---|---|---|
| "CI … not `test:native`, `lint:public-api`, `lint:runtime-deps` or `vectors:validate`; the Android and iOS device jobs are placeholders; `main` … has not run in CI" | threat_model.md TM-36 | CI runs all of them (`ci.yml:53-60`, native job `:153-196` with `test:native` and `test:no-network`, device jobs `:198+`); CI green on `08e3b17` (PROGRESS, 4e1ff93). |
| "the S4 no-network runtime test … does not exist" | TM-10 | `test:no-network` and `test/session/no_network_test.dart` exist and run in CI. |
| "`lint:public-api` … CI does not run it" / "`lint:runtime-deps` … which CI does not run" | TM-23, TM-28 | CI runs both. |
| "CI wiring (TM-36) and the S4 no-network runtime test (TM-10) — both pending" | threat_model.md §6 "Open for D1/D6" | Both landed with T1.17. |
| "Addresses, derivation paths, amounts, chain ids, and lengths are validated in Dart; invalid input raises `InvalidInputError` without reaching native code" | TM-21; PRD §16 S5 as implemented | Not for the EVM `data` length: it reaches `secretDataFromParts` and ends the session (C1). |
| "a `RangeError` from a broken invariant of this SDK's own code … is rethrown" | `handler.dart:80-90` | A caller-supplied oversized `data` produces that `RangeError` (C1); the comment is right only after the fix. |
| `closed` state: "`close()` on any proxy (no-op)" | DECISION-12 §3.1 table | After `failed → closed`, or after a forced shutdown, `close()` completes with `WorkerTerminatedError` (code `session.dart:489-527`, `docs/security/lifecycle.md` table, test `session_test` "close() first called after failed → closed still completes with…"). PRD §14.3 supports the code; the decision's table should say so. |
| "documentation says so on every such class" (PRD §11.2 item 1) | as implemented | Two of six handle classes lack the sentence (C6). |
| README / memory_contract.md / lifecycle.md "as of task T1.12" | headers | T1.13–T1.17 have landed; the body statements I spot-checked still hold, the header dates the page wrongly. |
| "Session finalizer/`dropped proxy` test observes release" (implied by TM-23/T1.11 notes) | threat_model.md `[^tm23-proxy]`, PROGRESS | The native test is best-effort and can skip silently (C3); the behaviour itself is real (my probe P4). |

I found **no false statement** in `docs/security/memory_contract.md`: its copy tables (staging buffers zeroed in `finally`, entropy copies overwritten by sender/executor, the view over upstream's buffer, the "no Dart-heap copy of the key") match `secret_buffers.dart`, `signing_core.dart`, `hd_wallet.dart`, `transport.dart`, `protocol.dart:579-600`; its claim of 13 requests / 14 replies matches `protocol.dart` (13 `extends WorkerRequest`, 14 `extends WorkerReply`).

---

## E. Can Phase 1 close, from the contracts' point of view?

**Yes — conditionally: no contract is violated in a way that invalidates a decision, but the audit is not a clean bill: there is one real S5 defect (C1) and a stale threat model (C2) to land as a small T1.R2 before T2.0.** The most important reason: the contracts D1 is asked to audit hold under independent probing — PRD §11.2 items 1–8 are all satisfied (the NativeFinalizer fallback frees forgotten handles 50/50 and a disposed handle never double-frees; the proxy `Finalizer` releases a dropped wallet), no public object frees native memory synchronously, `close()`/`shutdown()` are idempotent and ordered as §14.3 says for a same-isolate executor, every key injection passes the key-field check before any key exists and nothing I tried smuggles a key field past it, generators reproduce the committed files byte for byte, the public export is free of FFI/protobuf/`CoinType`, and no secret reaches any diagnostic — while the one hole found (an oversized `data` field kills the session and every wallet in it, C1) is a one-file, test-covered fix that does not touch DECISION-11/12/13.
