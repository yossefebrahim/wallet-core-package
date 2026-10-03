# DECISION-12 — Session lifecycle and worker protocol

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

| | |
|---|---|
| **Question** | What exactly is the contract between the UI isolate and the isolate that owns native handles: which states exist, which messages exist, what a full queue / a timeout / a cancellation / a `close()` during in-flight work / a dead worker each do, and which lifecycle each object follows? |
| **Governing PRD sections** | §10.2 (errors, lifecycle), §11.2 (disposal contract, items 5 and 8), §14.1–14.3, §16 S5 (worker fault testing), §22 DECISION-12 and DECISION-3 |
| **Evidence** | `docs/security/threat_model.md` §1.4, TM-01, TM-23, TM-25, TM-26; `docs/decisions/evidence/prefetch-2026-09-07/upstream-src/TWHDWallet.h` (handle-returning constructors, all `_Nullable`, all requiring `TWHDWalletDelete`) |
| **Interface sketch** | [`docs/architecture/lifecycle.md`](../architecture/lifecycle.md) |
| **Recommendation** | **Protocol as specified below** (PRD §14.3 written out in full); per-call isolates rejected here, and the residual worker-vs-pool question left to DECISION-3 |
| **Status** | **Recorded 2026-09-07** - recommendation adopted as written, with the T0.R2/T0.R4 fixes. See the Decision section. Recorded by the orchestrator under the owner's standing authorization; subject to their ratification. |
| **Amended** | **2026-10-03**, by the owner's decision: §8 trigger 6 fired, and the secret-bearing payload set of §3.2 was reopened and amended from four to eight; §3.5 records the per-operation `OperationDeadline`; §3.2's message table now lists the messages the code declares, with the absent ones marked planned. See "Amendment 2026-10-03" in the Decision section. |

---

## 1. Context

PRD §14.3 is four paragraphs of requirements. T2.1 has to build a state machine from them, T1.11 has to expose a public API shaped by them a phase earlier, and T2.12 has to write fault tests against them. This record turns the paragraphs into a protocol precise enough that all three can be written independently and agree.

Two constraints are not negotiable and everything else follows from them:

- **A native handle belongs to exactly one isolate.** A `Pointer` can be sent between isolates, but the object it addresses has no cross-isolate ownership, no synchronization, and a finalizer attached in one isolate does not follow it (PRD §14.1). Upstream documents no thread-safety for `TWHDWallet` (**[UNVERIFIED]**), so we assume none.
- **`NativeFinalizer` cannot run Dart code; a managed Dart `Finalizer` can.** That asymmetry is what makes a public proxy releasable at all: the proxy's finalizer can *post a message*, which is the only legal way to free a handle owned by another isolate (PRD §11.2 items 5 and 8; threat model §1.4).

**One ruling before the protocol, because everything else depends on it: exactly one isolate per session loads the native library and calls native.** The UI isolate never calls upstream, not even for a stateless check such as address validation. This makes the disposal contract of §11.2 apply to exactly one isolate, makes the build-identity check (PRD §12.3) a single point, and makes TM-23 ("a public proxy frees a worker-owned pointer") unexpressible rather than merely discouraged. It costs ergonomics — `Address.isValid` is a `Future` — and it means keystroke-rate validation queues behind a signature. The mitigation is that cheap, non-cryptographic syntax checks (length, charset, `0x` prefix and hex, HRP match) run in Dart in the UI isolate and reject most bad input without a message (PRD §16 S5); anything that needs upstream's answer is asynchronous.

In M0 the "worker" is an in-process executor in the same isolate that speaks this identical protocol (T1.11); T2.1 swaps in the real isolate without changing the public API. The protocol below is written for the isolate case and is what the executor must emulate.

## 2. Options

### Option A — long-lived session worker, this protocol (recommended)

One background isolate per `WalletCore` session owns every native handle for the session's lifetime. The UI isolate holds opaque refs and plain values. Operations are messages, processed sequentially.

### Option B — per-call isolates

`Isolate.run` per operation; the wallet is reconstructed inside the call from a mnemonic or an encrypted keystore, used, and thrown away.

**Rejected here, on design grounds rather than measurement**, for three reasons:

1. It moves a secret across the isolate boundary **on every call**. PRD §14.1 names this outcome specifically ("would move the mnemonic across isolates on every sign — unacceptable"). Reconstruction from a `StoredKey` instead of a mnemonic replaces the mnemonic with a password, which is not an improvement (threat model TM-05).
2. Refs cannot exist. `Wallet`, `wallet.close()`, and `Dispose(ref)` all presuppose a handle that outlives one call, so the public API of PRD §10.2 and §14.3 would have to be different — which means the choice cannot be deferred to M1 as a pure implementation swap.
3. It multiplies rather than removes the disposal problem: every call creates and destroys a wallet handle, so the per-call path is the *only* thing standing between the app and a leaked seed, with no session-level `shutdown()` to catch a mistake.

What Option B genuinely buys — no long-lived seed residency (TM-02) — is available inside Option A as an application pattern: `wallet.close()` and `WalletCore.shutdown()` are the lock primitive, documented in the cookbook (T3.10).

**Left open for DECISION-3:** whether one sequential worker is fast enough, measured at M1 by T2.10 (median and 95th-percentile sign latency, memory after 1 000 signatures). The escalation, if it is not, is a per-wallet worker **pool** — more isolates, each still owning its own handles — not shared handles and not per-call isolates. A pool does not change one line of this protocol; it changes which isolate a ref routes to.

## 3. The protocol

### 3.1 States

```
                 initialize()
        ┌──────────────────────────► initializing ──────────────┐
        │                                 │                     │ init fails
        │                          health check ok              │ (load, identity,
   (no session)                           │                     │  symbol lookup)
                                          ▼                     ▼
                                        ready ──────────────► failed
                                          │    worker died       ▲
                                shutdown()│                      │ worker died
                                          ▼                      │
                                       closing ──────────────────┘
                                          │
                              all handles disposed,
                              isolate exited
                                          ▼
                                       closed
```

| State | Accepts | Rejects with |
|---|---|---|
| `initializing` | nothing from the caller; `initialize()` has not returned yet. A second `initialize()` on the same session object returns the same `Future`. | `SessionStateError(actual: initializing)` for any operation reached through a leaked reference |
| `ready` | every operation; `close()` on any proxy; `shutdown()` | — |
| `closing` | a `Dispose(ref)` still in flight from `ready`, or one posted by an explicit `close()` racing `shutdown()` (accepted, §3.7 — a finalizer posts nothing once the session leaves `ready`); a second `shutdown()` (returns the same `Future`); a second `close()` on a proxy already closing (returns the same `Future`) | every new operation with `SessionStateError(actual: closing)` |
| `closed` | `shutdown()` (no-op, returns immediately); `close()` on any proxy (no-op); a late `Dispose` that was already in flight (dropped) | every operation with `ClosedError` |
| `failed` | `shutdown()` (transitions to `closed` without a worker round trip) | every operation with `WorkerTerminatedError(kind)` |

Transitions, exhaustively: `initializing → ready` (health check passed), `initializing → failed` (library load, identity mismatch, or symbol lookup failed — the failure cause is attached), `ready → closing` (`shutdown()`), `ready → failed` (worker terminated unexpectedly), `closing → closed` (worker acknowledged shutdown and exited, **or** the shutdown grace period elapsed), `closing → failed` (the worker died during shutdown; handles may not have been disposed, and the session says so), `failed → closed` (`shutdown()` after a failure, which only tears down the Dart side). There is no transition out of `closed`; recovery is a new `WalletCore.initialize()`.

`WalletCore.state` is observable synchronously (`SessionState get state`) and as a broadcast `Stream<SessionState>`, so an application can react to `failed` without polling.

### 3.2 Messages

Every message carries a `requestId`: a monotonically increasing `int` allocated by the UI isolate, unique within a session, never reused. Every request gets exactly one reply, correlated by `requestId`, except `Dispose` posted by a finalizer (§3.7) and `Cancel` (§3.6), which are acknowledged but whose acknowledgement nobody awaits.

| Request | Payload | Reply | Notes |
|---|---|---|---|
| `Init` | queue bound, session token, the expected manifest identity, the shipped manifest's bytes (optional), a host library path (internal test seam only) | `InitOk(symbolCount)` / `Failed` | sent once, by `initialize()`, before the session is `ready`. Carries **no timeouts** (§3.5) and **no reply port**: the port the worker answers on belongs to T2.1's isolate transport, not to this value |
| `CreateWallet` | `strength`, `passphrase` | `WalletCreated(walletRef)` | **secret-carrying request** (the passphrase). The reply carries **no mnemonic**: a freshly created wallet's mnemonic is obtained the same way any other wallet's is, through `ExportMnemonic` |
| `ImportWallet` | `mnemonic` **or** `entropy`, `passphrase` | `WalletCreated(walletRef)` | **secret-carrying request**; documented as such in code (TM-04, TM-06). The `entropy` is a copy the request owns, overwritten with zeros by the sender once handed over and by the executor once handled |
| `ExportMnemonic` | `walletRef` | `MnemonicExported(mnemonic)` / `Failed` | the request carries no secret; **the reply does**. Backs `Wallet.exportMnemonic()` (PRD §11.3), which exists to display the mnemonic once |
| `DeriveAddress` | `walletRef`, coin id, network, address style, explicit path | `AddressDerived(address, publicKey, path)` | returns a descriptor; no handle crosses back |
| `ValidateAddress` | address string, coin id, network | `AddressValidated(bool)` | the stateless native call §1 rules must still happen in the owning isolate |
| `ValidateMnemonic` | a candidate mnemonic | `MnemonicValidated(bool)` | **secret-carrying request**: the candidate is very likely somebody's real mnemonic. Backs `MnemonicFacade.isValid`; sent only when the Dart-side shape check cannot already answer |
| `ValidateMnemonicWord` | one word | `MnemonicWordValidated(bool)` | **secret-carrying request**: a word of a mnemonic being typed. Backs `MnemonicFacade.isValidWord` |
| `SuggestMnemonicWords` | a word prefix | `MnemonicWordsSuggested(words)` | **secret-carrying request and reply**: the prefix, and the suggested words, every one of which shares it. Backs `MnemonicFacade.suggest` |
| `Sign` | request value, `Set<LocatorSpec>` (the names each `KeyLocator` carries) | `Signed(SignResult)` / `Failed` | key-less request in, sealed result out (DECISION-13). `usedKeys` is empty on the wire; the session puts the caller's locators back |
| `DisposeRef` | `walletRef` | `Disposed(walletRef)` | idempotent; unknown ref is a no-op (§3.7). Written `Dispose(ref)` in the rest of this record |
| `Cancel` | `target` request id | `Cancelled(target)` / `NotCancellable(target)` | §3.6 |
| `Shutdown` | grace period | `ShutdownComplete(disposedCount)` | §3.8 |
| *planned:* `ImportKey` | encrypted keystore blob + password, or raw key bytes (advanced only) | `KeyImported(keyRef)` | **not declared yet** (T3.4/T3.5); a **secret-carrying request** when it is |
| *planned:* `SignMessage` | message request value, `Set<LocatorSpec>` | `MessageSigned(SignResult)` / `Failed` | **not declared yet** (T2.7) |
| *planned:* `Plan` | UTXO request value | `Planned(UtxoPlan)` / `Failed` | **not declared yet** (T2.5); UTXO chains only |

**Thirteen request types and fourteen reply types are declared today**, exactly as `docs/architecture/lifecycle.md` §6 lists them. Requests: `Init`, `CreateWallet`, `ImportWallet`, `ExportMnemonic`, `DeriveAddress`, `ValidateAddress`, `ValidateMnemonic`, `ValidateMnemonicWord`, `SuggestMnemonicWords`, `Sign`, `DisposeRef`, `Cancel`, `Shutdown`. Replies: `InitOk`, `WalletCreated`, `MnemonicExported`, `AddressDerived`, `AddressValidated`, `MnemonicValidated`, `MnemonicWordValidated`, `MnemonicWordsSuggested`, `Signed`, `Disposed`, `Cancelled`, `NotCancellable`, `ShutdownComplete`, and `Failed`, which any request may receive. The three planned requests and their replies (`KeyImported`, `MessageSigned`, `Planned`) are not declared; both families are `sealed`, so each one's arrival is a compile error at every `switch` that must handle it.

Replies are a sealed family; the failure member is `Failed(requestId, WalletCoreException)` carrying an already-typed error, so the UI isolate never reconstructs an exception from a string. All request and reply types are plain immutable Dart values with no native pointer, no handle, and no `SendPort` — the reply port belongs to the transport, not to any message. `Sign` carries `LocatorSpec`s, not the caller's `KeyLocator`s: a locator's `WalletRef` holds session-side objects that cannot cross an isolate, so what crosses is the names it carries (the issuing session's token, the wallet reference's number, the coin, the path, the role). It names keys, it does not carry them (DECISION-13).

**Which payloads carry a secret, enumerated.** The message set has no single "the secret-carrying message"; it has **eight** payloads — six requests and two replies — of which seven are declared today and one, `ImportKey`, is planned. Each declared one is marked as such in its doc comment, and `docs/security/memory_contract.md` (T1.18; TM-04, TM-06) is to cover all eight:

| Payload | Direction | What it carries | |
|---|---|---|---|
| `CreateWallet` | request | `passphrase` (a BIP-39 passphrase is key material: it selects the seed) | |
| `ImportWallet` | request | `mnemonic` **or** `entropy`, plus `passphrase` | |
| `ImportKey` | request | an encrypted keystore blob **and** its password, or raw key bytes under `advanced.dart` | planned (T3.4/T3.5) |
| `ValidateMnemonic` | request | a whole candidate mnemonic | added 2026-10-03 |
| `ValidateMnemonicWord` | request | one word of a mnemonic | added 2026-10-03 |
| `SuggestMnemonicWords` | request | the beginning of a word of a mnemonic | added 2026-10-03 |
| `MnemonicExported` | reply | the wallet's `mnemonic` | |
| `MnemonicWordsSuggested` | reply | the candidate words, every one of which shares the caller's prefix | added 2026-10-03 |

**`WalletCreated` carries no mnemonic, and there is no way to ask it for one.** An earlier draft returned `WalletCreated(walletRef, mnemonic?)` "if the caller asked", but nothing in `CreateWallet`'s payload or in the public `WalletFacade.create` signature could express the asking — the option was unreachable, and an unreachable option on a secret-bearing reply is worse than none: it invites an implementation to add the flag later without revisiting this table. So creation returns a ref and nothing else. A freshly created wallet's mnemonic is obtained exactly the way any other wallet's is, by calling `Wallet.exportMnemonic()` → `ExportMnemonic(walletRef)` → `MnemonicExported(mnemonic)`. That costs one extra round trip on the seed-display screen and buys a single, explicit, auditable path by which a wallet's mnemonic can come back across the boundary — one reply type to review, one call site to grep for, one place for the "display once and drop it" rule to live.

Every other request and reply is key-less by construction: refs, coin and network ids, paths, addresses, public keys, request values, locators, booleans, counts, and typed errors. Two consequences the implementation is held to. First, the secret-bearing set is *closed*: adding a message that carries key material in either direction reopens this record (§8), as the four mnemonic-validation payloads did on 2026-10-03. Second, a secret in a **reply** is the harder half — it exists because a person has to read it (PRD §11.3) — so each of the two secret-bearing replies is produced only in response to an explicit request for that value (`ExportMnemonic`, `SuggestMnemonicWords`), is never logged (its `toString()` names its fields, never their values), never included in an error message, and never cached in the worker after the reply is posted. The SDK drops its own references once the value has crossed; it cannot erase the caller's copy, and the doc comments say so.

### 3.3 Refs

A `WalletRef` / `KeyRef` is an opaque object wrapping a session-scoped `int` id. It is:

- **allocated by the worker** and returned in the reply, so an id the worker never issued cannot be forged by accident;
- **validated on every use** against the worker's own ref table — an unknown ref fails with `ClosedError` (it was closed) or `InvalidInputError` (it was never issued), never with a native call;
- **session-scoped**: a ref from session A is not valid in session B, and there is no API that could hand it over, because the ref object holds the owning session's identity and every entry point checks it (`KeyResolutionError` on mismatch; see DECISION-13 §Q5);
- **not a capability to key material.** A ref names a wallet; deriving from it still requires a `KeyLocator` and still happens inside the worker.

### 3.4 The queue

A single FIFO queue in the worker, bounded (**default 32 pending operations**, configurable at `initialize()`, minimum 1). The bound counts queued *and* the one in-flight operation.

- When full, the **submission** fails immediately with `QueueFullError(limit)`. It does not block, does not drop the oldest, and does not grow (TM-26).
- `Dispose`, `Cancel`, and `Shutdown` are **control messages and are not subject to the operation bound.** A full queue must not prevent a caller from tearing down; that would turn a load spike into a stuck seed in memory.
- Ordering is FIFO among operations. `Shutdown` jumps the queue in the sense that no *new* operation starts after it arrives, but already-queued operations are still resolved or rejected per §3.8.

**The control path is exempt from the operation bound but is not unbounded.** "Not subject to the bound" would otherwise mean a caller can post control messages without limit and defeat TM-26 through the other door. Four rules bound it, and together they make the pending control set finite without ever refusing a teardown:

1. **Coalescing.** At most one `Dispose` may be pending per ref and at most one `Cancel` per target request id. A repeat for the same target is folded into the pending one and completes with the same reply, which is also what makes `close()`'s idempotence (§3.8) cheap: two concurrent `close()` calls produce one queued `Dispose`, not two.
2. **Immediate rejection of a `Cancel` with no live target.** A `Cancel` naming a request id the session never issued, or one whose future has already completed, is answered `NotCancellable(targetRequestId)` **without being enqueued** — in the UI isolate when it can be decided there (the id is not in the pending-reply table), otherwise by the worker on arrival, before any queue is touched. Cancels therefore cannot accumulate for work that no longer exists.
3. **A reserved, bounded control capacity.** The worker reserves control slots separately from the operation queue: `queueLimit` slots (one possible `Cancel` per operation that can be pending) plus one slot per live ref for `Dispose`, plus a fixed reserve of 8. With rules 1 and 2 the pending control set cannot exceed that number, so the reserve is a bound the implementation asserts rather than a quota it enforces against callers. If the assertion ever fails, that is a bug in coalescing and the worker fails the session rather than growing.
4. **`Shutdown` is always admissible.** It is accepted in every state that has a worker, counts against nothing, and is never refused for capacity — if control slots were somehow exhausted, `Shutdown` still lands and supersedes every pending control message, since §3.8 disposes everything anyway. A pending `Dispose` whose ref `Shutdown` then frees is answered `Disposed(ref)` all the same (§3.7).

### 3.5 Timeouts

Every *operation* carries a deadline; the control messages `Dispose`, `Cancel`, and `Shutdown` carry none. Defaults, all overridable through `OperationTimeouts` at `initialize()`: `Init` 30 s; `CreateWallet` / `ImportWallet` / `ExportMnemonic` 20 s (and the planned `ImportKey`); `DeriveAddress` / `ValidateAddress` / `ValidateMnemonic` / `ValidateMnemonicWord` / `SuggestMnemonicWords` 5 s; `Sign` 15 s (and the planned `SignMessage` / `Plan`); `Shutdown` grace period 10 s. The timeouts stay in the session: `Init` does not carry them, and the executor never holds a table of them — it receives one deadline per operation, below. The deadline starts when the operation is **submitted**, not when it starts running, so queue time counts against it — otherwise a bounded queue plus a slow operation still yields an unbounded wait.

**The deadline crosses beside the operation, as an `OperationDeadline`.** It is a plain value of two fields: the operation's `timeout` (what `OperationTimeoutError` reports) and `atMicros`, the instant it expires, in microseconds on the process's monotonic clock — the clock `Timeline.now` reads (`monotonicMicros()`), which every isolate of the process reads alike, so a deadline taken in the session's isolate names the same instant in the executor's.

- **Created** by the session at submission, `OperationDeadline.after(timeout)`, for every operation including `Init`, before the session starts its own timer for the same operation, so the executor's deadline is never later than the session's.
- **Saturating.** A timeout too long to add to the clock without overflowing 64 bits gives `OperationDeadline.neverMicros`, a deadline that never passes, rather than a wrapped negative instant that has always passed.
- **Carried** by `WorkerTransport.send(request, deadline: …)`, beside the request and not inside it. Control messages are sent without one, and the executor ignores any given with them.
- **Checked by the executor**, twice. When the operation's turn comes, a deadline that has passed means the operation is not run at all. When the handler returns — after it has parsed and released (§3.9) — a deadline that passed while it ran means its result is **dropped without being posted, not posted and ignored** (§3.9): whatever the result named is released in the executor (the wallet a `WalletCreated` names), and a key-less `Failed(OperationTimeoutError)` is posted in its place, so that the session's accounting of the request id closes and nothing a caller will no longer receive — a mnemonic included — ever crosses.
- **The session times the operation as well.** Its own timer completes the caller's future with `OperationTimeoutError` on expiry, without waiting for the executor, and posts a `Cancel` for the target so that one still queued never runs. A reply that reaches the session for a request already completed is discarded, and a wallet a late `WalletCreated` names is released with a `Dispose`. That is a backstop for the edge where the session's timer and the executor's clock disagree; the executor's check is the rule. In M0 it is also the only check that can fire during native work: the in-process executor runs on the session's event loop, so no timer fires while a native call blocks it.

**Recorded for T2.1 (decided 2026-10-03; not built yet).** The worker isolate transport's envelope must carry the `OperationDeadline` beside each operation — the instant, not only the timeout, so that the worker measures from the session's submission and not from its own receipt. T2.1 also adds a public cancel-before-start, which is what makes `OperationCancelledError` reachable by a caller; until then the only `Cancel` the session posts is the one on a passed deadline, whose caller already holds `OperationTimeoutError`.

**`Dispose` has no deadline at all, and the reason is that no honest one can be written.** An explicit `close()` must wait behind an operation already running in native code, which cannot be interrupted (§3.6), so a deadline measured from submission would expire `close()` for a reason that is not a fault, at exactly the moment the caller is trying to release a seed. An earlier draft answered that by bounding "the worker's own dispose step" instead — the interval from the worker picking the `Dispose` message up to the native delete returning. That bound cannot be enforced by anything in this protocol:

- **The worker cannot time itself out of it.** A Dart isolate blocked inside `TWHDWalletDelete` runs no event loop, so a timer it armed before the call cannot fire until the call it was meant to bound has already returned.
- **No other isolate can measure it.** The protocol has no "dispose started" message, and adding one would not help: it would be posted before the native call and would prove only that the worker was alive a moment earlier, which is what the pending reply already tells us.

So the rule is the simple one:

> **The acknowledgement of an explicit `close()` has no deadline.** The future returned by `close()` completes when `Disposed(ref)` arrives, or with `WorkerTerminatedError` if the session's isolate ends first, or with `SessionStateError`/`ClosedError` per §3.1. It never completes with `OperationTimeoutError`, and there is no `dispose` entry in `OperationTimeouts`.

**A worker stuck inside a native delete is indistinguishable from a worker stuck inside any other native call**, and it is handled the same way: the session has one in-flight message that never completes, and the only recovery is `shutdown()`, whose `shutdownGrace` *does* expire and kills the isolate on expiry (§3.8). That kill is not clean — native allocations owned by that isolate are not wiped, exactly as TM-25's residual risk describes — so the recovery is a real recovery with a real cost, not a tidy timeout. `Dispose` posted by a finalizer (§3.7) awaits nothing and so has no deadline either, for a different reason: nobody is waiting.

For every deadline that does exist, on expiry the caller's `Future` completes with `OperationTimeoutError(operation, timeout)`. **The native call is not aborted** — there is no mechanism to abort it, and inventing one would mean interrupting upstream mid-computation. The worker finishes the operation, disposes its temporaries and any derived key exactly as it would normally (§3.9), and drops the result unposted, as above. A late result is never delivered under a `requestId` whose future is already completed.

### 3.6 Cancellation

`Cancel(targetRequestId)` has two possible outcomes and no others:

- **The target is still queued.** It is removed; its future completes with `OperationCancelledError`; no key is derived and no native call is made. Reply: `Cancelled`.
- **The target is running in native code.** It runs to completion, with the same disposal path as a timeout. Reply: `NotCancellable`, and the caller's original future still completes normally (or with its own error). Cancellation is a request, never a guarantee, and the API says so in the doc comment.

There is no third state: because the worker is sequential, an operation is either not started or is the one in flight.

### 3.7 `Dispose`, unknown refs, and finalizers — **threat-model Q1**

`Dispose(ref)` is **idempotent and total**: for a ref the worker does not know, for a ref it already disposed, and for a ref belonging to a wallet freed by `Shutdown`, the worker does nothing and replies `Disposed(ref)`. It never throws, never logs the ref's contents, and never touches native code for an unknown ref. This is the behaviour TM-23 assumes, and it is now stated normatively rather than assumed.

The managed `Finalizer` on a public proxy (PRD §11.2 item 8) behaves as follows, which is the explicit answer to threat-model question 1:

- **The callback may *run* at any time; it *posts* only while the session is `ready`.** Those are two different statements and the distinction is the whole rule. Collection timing is not ours to control — a proxy may be collected during `ready`, during `closing`, after `closed`, or after `failed`, and the callback runs whenever the runtime decides.
- What the callback does is decided by the state it observes when it runs. In `ready` it posts `Dispose(ref)` fire-and-forget and awaits nothing. In `closing`, `closed`, or `failed` it **posts nothing and does nothing**: `Shutdown` has already disposed every handle the session owned (§3.8), so there is nothing to free, and the reply port may be gone. The callback never throws, never allocates a `Future` the caller could see, and never reports an error to the app.
- A `Dispose` that does arrive at the worker while the session is `closing` — one posted during `ready` that has not been processed yet, or an explicit `close()` racing `shutdown()` — is **safe to receive in any state**: the worker treats it per the idempotence rule above. Safety of receipt is why the callback needs no lock; it is not a licence to post after `ready`.
- A `Dispose` that arrives at the worker **after** `Shutdown` has been processed is dropped without a reply, because the worker is already tearing down its ports; a `Dispose` that arrives *during* `closing` but before the handles are freed is treated as a normal idempotent dispose.
- After `Shutdown`, no `Dispose` can arrive at a live worker at all, because the isolate has exited. Messages to a dead isolate's port are discarded by the runtime; we rely on that rather than on ordering.

Consequence for the leak tracker (T1.6): a proxy collected while the session was already closed is **not** a leak and is not counted, because closing freed the handle.

### 3.8 `close()` and `shutdown()`

`close()` on a public proxy is `Future<void>`, idempotent, and does exactly this:

1. If the proxy is already closed or closing, return the existing future (idempotence is by memoised future, not by a boolean, so two concurrent `close()` calls await the same acknowledgement).
2. Mark the proxy closed **locally and immediately** — any subsequent method on it throws `ClosedError` even before the worker replies. A closed proxy is unusable the moment `close()` is called, not when it completes.
3. Post `Dispose(ref)` and await `Disposed(ref)`. **This wait has no deadline** (§3.5): there is none that could be enforced, so the future completes on the acknowledgement or on the session's isolate ending, and never with `OperationTimeoutError`.
4. Detach the managed `Finalizer` (the proxy is the detach key), so a later collection posts nothing.

**`close()` during an in-flight operation on the same handle** (PRD §14.3): the worker processes messages sequentially, so `Dispose` is simply queued behind the running operation and cannot interleave with it. The operation completes, its key material is disposed (§3.9), its reply is posted, and only then is the handle deleted. The caller's `close()` future therefore completes strictly after the in-flight operation's future. No native pointer is freed while a call is using it — not by discipline, but because there is no point in the schedule at which it could be.

This is exactly why step 3 carries no deadline: an in-flight `Sign` may take arbitrarily long, and expiring `close()` because a signature was slow would report a fault that did not happen and would leave the caller without an answer about a handle that is about to be freed anyway (§3.5). Step 2 is what makes an unbounded wait acceptable in practice — the proxy is unusable from the instant `close()` is called, so the only thing the caller waits for is the confirmation, not the effect. A caller that must not block indefinitely has `shutdown()`, whose grace period *does* expire and which kills the isolate on expiry (below); that kill is the only recovery from a worker wedged inside a native call, delete or otherwise, and it does not wipe what the worker owned.

`WalletCore.shutdown()` is idempotent and does:

1. `ready → closing`. New operations are rejected with `SessionStateError` from this instant, in the UI isolate, without a round trip.
2. Post `Shutdown(grace)`.
3. The worker stops accepting work, **rejects every queued operation with `SessionStateError`**, lets the one in-flight operation finish (its future completes normally), disposes every handle in its ref table, detaches every native finalizer it attached, replies `ShutdownComplete(disposedCount)`, closes its ports, and exits.
4. The UI isolate awaits `ShutdownComplete` up to the grace period. On expiry it **kills the isolate** (`Isolate.kill(priority: immediate)`), moves to `closed`, and records that a forced termination happened. Killing is worse than a clean exit — native allocations owned by that isolate are not wiped, exactly as TM-25's residual risk describes — so the grace period exists to make it rare, not to make it impossible.
5. `closing → closed`. Every proxy of the session reports `ClosedError`; every ref is invalid.

### 3.9 Key material and the acknowledgement order — **threat-model Q2**

**Key material derived for an operation is disposed before that operation's reply is posted.** Concretely, the worker's operation body is:

```
derive key(s) from walletRef via the locators
try:
    encode key-less input, inject key, call upstream
    parse the output into a typed SignResult                             ← still inside the try
finally:
    dispose every derived key handle and every key-bearing buffer        ← here
post Signed(result) / Failed(error)                                      ← then here
```

**Parsing happens before the `finally`, and that is normative, not incidental.** Upstream's output lives in a native allocation that the worker must read while it still exists, so `parseSigningOutput` (DECISION-13 §4.4) runs inside the `try`, producing a Dart-owned `SignResult` built from copies of the output bytes. Two categories of memory are involved and they are released differently:

| | What it is | When it goes |
|---|---|---|
| **The retained output copy** | the parsed `SignResult` and the Dart byte copies inside it — signed transaction bytes, signature components, a transaction id | kept: it is the reply. It is **not key-bearing**; a signed transaction contains signatures and public data, never the private key that produced them |
| **Key-bearing buffers** | derived key handles, the serialized signing input after injection, every temporary native allocation made for the call, and the SDK's own byte buffers that held key material | released in the `finally`, before the reply is posted, on every path |

Writing the two orderings as one rule: **parse before releasing, release before replying.** The reply is therefore proof to any observer in the UI isolate that the key is already gone from the worker's own allocations, while the result it carries was read while the output was still alive. That ordering also holds for the timeout and cancellation paths (§3.5, §3.6): the `finally` runs even when the parsed result is then discarded, and a discarded result is dropped without being posted, not posted and ignored. If parsing throws, the `finally` still runs and the operation fails with a typed error — a parse failure never skips the release.

It follows *a fortiori* that keys are disposed before any `Disposed(ref)` acknowledgement, since `Dispose` is a separate later message (§3.8). The residual, unchanged from TM-01, is that under Approach A (PRD §11.4) the serialized signing input held the key in a Dart `Uint8List` whose GC-internal copies we overwrite but cannot erase.

### 3.10 Failure taxonomy — **threat-model Q3**

The honest answer to "should a native crash be distinguishable from a Dart uncaught error at the API level" is that **the first is not observable to us at all**, and the API must not pretend otherwise.

- A **Dart uncaught error** in the worker fires the isolate's `onError` port. We learn the error and its stack, move the session to `failed`, and fail every pending and future call with `WorkerTerminatedError(kind: WorkerTerminationKind.uncaughtDartError, cause: …)`.
- An **isolate exit without an error** (killed, out of memory in that isolate) fires `onExit` only. `WorkerTerminatedError(kind: WorkerTerminationKind.isolateExited)`.
- A **hard native crash** — a segmentation fault inside upstream — terminates the *process*. There is no isolate left to report it, no Dart handler runs, and the SDK cannot surface anything, because the SDK is gone too. The app's platform crash reporter is the only observer. `WorkerTerminationKind` therefore has **no** `nativeCrash` member: adding one would imply a signal we can never emit.
- A **soft native failure** (a null return, an error code, a malformed output) is not a termination at all; it is a typed `SigningError` / `InvalidInputError` from that one operation and the session stays `ready` (TM-19, TM-20).

So the answer is: yes, distinguishable — but along the axis that actually exists (`uncaughtDartError` vs `isolateExited` vs `initializationFailed`), not along the crash-versus-error axis the question proposed. Nothing is retried silently in any case (TM-25). **This is a fact threat model v1 should record**, replacing TM-25's implicit assumption that a native crash produces a `WorkerTerminatedError`.

### 3.11 The two lifecycles, stated together

| | Internal handle (PRD §11.2) | Public resource (PRD §14.3) |
|---|---|---|
| Examples | the bindings' data/string wrappers, the worker's wallet and key handles, the same-isolate `HDWallet` of `advanced.dart` | `Wallet`, `WalletCore`, signers |
| Contract | synchronous `void dispose()` | asynchronous idempotent `Future<void> close()` |
| Where it may be called | **only inside the isolate that owns the handle** | from any isolate that holds the proxy |
| Double call | no-op | returns the same future |
| Use after | `DisposedError` | `ClosedError` |
| Finalizer fallback | `NativeFinalizer`, token = the native pointer, detach key = the wrapper; the callback is a native delete function and runs no Dart code | managed `Finalizer`, detach key = the proxy; the callback posts `Dispose(ref)` per §3.7 |
| Guarantee | upstream wipes the buffer that object currently owns; nothing beyond it (PRD §11.3) | the acknowledgement proves the worker freed the handle |

There is no synchronous `dispose()` anywhere on the public surface, and `lint:public-api` (T1.15) rejects a public type holding a native pointer, so the mistake TM-23 describes cannot be written.

### 3.12 `advanced.dart`

`advanced.dart` exports a **same-isolate** `HDWallet` with the synchronous contract of §11.2: it owns its handle in the caller's isolate, exposes `dispose()`, throws `DisposedError` after disposal, and carries a `NativeFinalizer`. It exists for tests, CLIs, and callers who accept ownership (PRD §14.3 last paragraph). Its documentation states three things explicitly: it is not a proxy and holds no ref; it must never be shared across isolates; and using it concurrently with a session's worker means two isolates each holding their own handles, which is supported, while sharing one handle between them is not.

## 4. Sequence diagrams

### 4.1 One `sign` call

```
UI isolate                          worker isolate                       upstream
    │                                     │                                 │
    │ signer.sign(request, {locator})     │                                 │
    │  validate request in Dart           │                                 │
    │  (S5: amounts, address syntax)      │                                 │
    │  reqId = 42, deadline = now + 15s   │                                 │
    │─── Sign(42, request, {locator}) ───►│                                 │
    │                                     │ queue depth 0 < 32 → accept     │
    │                                     │ resolve locator → derive key    │
    │                                     │──── TWHDWalletGetKey ──────────►│
    │                                     │◄─── key handle ─────────────────│
    │                                     │ encodeKeylessInput(request)     │
    │                                     │ assert no key field present     │
    │                                     │ inject key, serialize           │
    │                                     │──── TWAnySignerSign ───────────►│
    │                                     │◄─── output bytes ───────────────│
    │                                     │ parseSigningOutput → SignResult │
    │                                     │ finally: dispose key handle,    │
    │                                     │   free temporaries, overwrite   │
    │                                     │   our own byte buffers          │
    │◄── Signed(42, EvmSignResult) ───────│                                 │
    │ future completes                    │                                 │
```

The reply crossing the boundary is the proof of §3.9: it is posted after the `finally`.

### 4.2 `close()` during an in-flight `sign` on the same wallet

```
UI isolate                                   worker isolate
    │                                              │
    │─── Sign(42, request, {locator}) ────────────►│  starts immediately
    │                                              │  ├ derive key
    │ wallet.close()                               │  ├ TWAnySignerSign  (in native, not interruptible)
    │  proxy marked closed locally, now            │  │
    │  any wallet.* → ClosedError                  │  │
    │─── Dispose(43, walletRef) ──────────────────►│  │ queued behind 42 (control message,
    │                                              │  │ not subject to the queue bound)
    │                                              │  ├ parse output
    │                                              │  └ finally: dispose derived key   ← key gone
    │◄── Signed(42, result) ───────────────────────│
    │ sign() future completes normally             │  now processes 43:
    │                                              │  TWHDWalletDelete(wallet), detach
    │                                              │  native finalizer, drop ref
    │◄── Disposed(43) ─────────────────────────────│
    │ close() future completes                     │
    │ managed Finalizer detached                   │
```

The sequential queue is what makes this safe: `Dispose` cannot be processed between "derive key" and "dispose key", so there is no window in which the wallet handle is deleted under a running signature.

## 5. Consequences for tasks

| Task | What changes |
|---|---|
| **T1.11** — SDK core | The M0 in-process executor implements §3.1–§3.10 message-for-message so the public API is already asynchronous and message-shaped; `WalletCore.state` + state stream; `Wallet` proxies with memoised idempotent `close()`, local-immediate closure, and the managed `Finalizer` of §3.7; `Address` validation routed through the session per §1. Adds four error types (§6). |
| **T1.15** — public-API lint | Also fails on a public member named `dispose` returning `void` (the two lifecycles must not be confusable) in addition to rejecting `dart:ffi`, generated, and protobuf types. |
| **T1.6** — wrappers | Unchanged in substance; §3.11 fixes the vocabulary its tests use (`DisposedError` internal, `ClosedError` public) and confirms that leak-tracker accounting must not count proxies collected after `shutdown()`. |
| **T1.7** — loader | The identity and release-set check runs **in the worker isolate**, during `Init`, before `initialize()` returns; a failure produces `initializing → failed` with `ManifestMismatchError` or `NativeLoadError` as the cause, and no session is handed to the caller. |
| **T2.1** — worker | Implements this record verbatim. The message table of §3.2 is the message set; the defaults of §3.4 and §3.5 are the defaults; §3.7 and §3.9 are testable statements. |
| **T2.12** — hostile-input and fault suite | Gains named tests: queue-full rejection at the bound and the exemption of control messages; the control-path bounds of §3.4 (repeated `Dispose`/`Cancel` for one target coalescing to one pending message, a `Cancel` for an unknown or finished id answered without being enqueued, `Shutdown` admitted with control capacity exhausted); deadline measured from submission; `close()` behind a long in-flight operation completing normally, however long it waits, rather than with `OperationTimeoutError` (§3.5), and a worker wedged inside a native delete recovered only by `shutdown()`'s grace-period kill; cancel-before-start vs cancel-in-native; `Dispose` for unknown / already-disposed / post-shutdown refs; `close()` during in-flight sign asserting reply order (§4.2); grace-period expiry forcing a kill; `onError`-vs-`onExit` producing the two `WorkerTerminationKind`s. |
| **T2.10** — measurements | Records queue-wait separately from native time, since §3.5 makes queue time count against the deadline; feeds DECISION-3. |
| **T1.18 / T3.9** — docs | "close vs dispose", the state machine, and the "shutdown is the lock primitive" pattern (TM-02, TM-03) come from §3.1, §3.8, §3.11. |
| **T5.7** — threat model v1 | Must record §3.10: a hard native crash is not observable to the SDK, so TM-25's mapping is refined rather than restated. |
| **DECISION-3** | Unaffected by this record except that its escalation path is fixed: a worker **pool**, never shared handles, never per-call isolates. |

## 6. PRD deltas this record requires

The error hierarchy of PRD §10.2 does not contain a type for a full queue, a timeout, a cancellation, or an operation attempted in the wrong session state, although §14.3 requires all four behaviours. This record adds four members, all under `WalletCoreException`:

`SessionStateError(actual, attempted)` · `QueueFullError(limit)` · `OperationTimeoutError(operation, timeout)` · `OperationCancelledError(requestId)`

D0 should ratify them explicitly, since PRD §10.2 is quoted as the error surface by T1.11, T2.0, and T3.1.

## 7. Answers to threat-model questions

| Q | Question | Answer | Where |
|---|---|---|---|
| **Q1** | May a proxy's managed `Finalizer` post `Dispose(ref)` after `closing`/`closed`, and what does the worker do with a `Dispose` after `Shutdown`? | The callback may **run** at any time but **posts** only while the session is `ready`; in `closing`/`closed`/`failed` it does nothing, because shutdown already freed everything. Receiving a `Dispose` is safe in every state: for an unknown, already-disposed, or shutdown-freed ref it is a no-op that still replies `Disposed`, and one that arrives after the isolate exited is discarded by the runtime. | §3.7 |
| **Q2** | Is key material for an in-flight operation disposed before or after the acknowledgement? | **Before.** The order is parse, then release, then reply: the output is parsed into a Dart-owned result inside the `try`, every key-bearing buffer is released in the `finally`, and only then is the reply posted — on the success, error, timeout, and cancellation paths alike. | §3.9 |
| **Q3** | Should a native crash be distinguishable from a Dart uncaught error at the API level? | Along that axis, no — a hard native crash kills the process and leaves nothing to report, so `WorkerTerminationKind` deliberately has no `nativeCrash` member. What *is* distinguished, and is what an app can act on, is `uncaughtDartError` vs `isolateExited` vs `initializationFailed`. Soft native failures are per-operation typed errors and do not terminate the session. | §3.10 |

## 8. Revisit trigger

Re-open this record when any of the following occurs:

1. **T2.10's measurements fail DECISION-3's bar** — a worker pool arrives, and §3.3's ref routing and §3.4's single queue become per-worker.
2. **A user-visible operation needs to interrupt native work** (a very long UTXO plan, a large batch) — §3.6's "cancellation is a request" stops being adequate and the answer is an operation-splitting redesign, not a kill.
3. **Upstream documents thread-safety for its handles** — the sequential-worker justification of §1 weakens, and concurrency inside one session becomes evaluable.
4. **Dart gains a way to observe a native crash from a surviving isolate** — §3.10's answer to Q3 changes and `WorkerTerminationKind` grows a member.
5. **Approach B (PRD §11.4) is selected at D1a** — §3.9's `finally` block moves partly into C, and the "parse, release, reply" ordering must be re-established for the adapter's own buffers.
6. **A message that carries key material in either direction is added to §3.2** — the enumerated secret-bearing set is closed at eight payloads (four until the amendment of 2026-10-03), so a ninth is a change to what crosses the isolate boundary and needs the same scrutiny the first eight got (TM-04, TM-06). Returning a mnemonic from `WalletCreated` again, rather than through `ExportMnemonic`, is exactly such a change and is not an implementation detail.

   **Fired 2026-10-03.** The protocol as built added three requests and one reply that carry a mnemonic or part of one — `ValidateMnemonic` (a whole candidate mnemonic), `ValidateMnemonicWord` (one word), `SuggestMnemonicWords` (a word prefix), and the reply `MnemonicWordsSuggested` (words sharing that prefix) — so the record was reopened, and on that date the owner amended the set from four to eight (§3.2). These four additions are accepted because they are the mnemonic-validation and word-suggestion paths, which cannot answer without seeing the mnemonic or the part of it being typed, and because none of them accepts or returns a derived key: their replies are a boolean or words of the BIP-39 English list. They are held to the same handling as the original four — `toString()` names their fields and never their values, no error carries them, the executor keeps nothing once it has replied — and each crosses only when the Dart-side check (a mnemonic's shape, a word's length, a prefix's characters) cannot already answer.

---

## Decision

**The protocol of section 3 is adopted in full**, including the four rulings that were contested at D0 and then
conceded: only the session isolate calls native (so address validation is asynchronous, with a pure-Dart
`looksWellFormed` for keystroke-rate checks); the secret-bearing payload set is **closed at four** (section 3.2; amended to eight on 2026-10-03, below); the
explicit-close acknowledgement is **non-expiring** (section 3.5); and `WorkerTerminationKind` has **no `nativeCrash`
member** (section 3.10).

Binding on **T1.11**, **T2.1** (state machine), and **T2.12** (fault tests). The residual worker-versus-pool question
stays with DECISION-3 at D2; adopting this record does not pre-judge it.

Recorded **2026-09-07 by the orchestrator**, under the repository owner's standing authorization to keep Phase 0 moving while they were unavailable, and **subject to the owner's ratification** (`docs/plan/PROGRESS.md` -> Needs your eyes -> "Decisions recorded on your behalf"). The choice is reversible at the cost stated in the revisit trigger; nothing is published.

Read before ratifying: section 3.2 (the four payloads) and section 3.5 (why no dispose deadline exists). Section 3.4's
reserved control capacity is the implementer's number, not a fixed part of this record.

### Amendment 2026-10-03

Decided by the repository owner on 2026-10-03, after section 8 trigger 6 fired:

1. **The secret-bearing payload set is eight, not four** (section 3.2): the requests `CreateWallet`, `ImportWallet`,
   `ImportKey` (planned), `ValidateMnemonic`, `ValidateMnemonicWord`, `SuggestMnemonicWords`, and the replies
   `MnemonicExported` and `MnemonicWordsSuggested`. The set stays closed; a ninth reopens this record. Why the four
   additions are accepted is recorded under trigger 6.
2. **Each operation's deadline crosses beside it as an `OperationDeadline`** on the process's monotonic clock, measured
   from submission and saturating; `Init` carries no timeouts; the executor drops a result whose deadline has passed
   without posting it (section 3.5).
3. **Forward to T2.1:** the worker isolate transport's envelope carries the `OperationDeadline`, and T2.1 adds a public
   cancel-before-start that makes `OperationCancelledError` reachable (section 3.5). Neither exists yet.

Section 3.2's message table was also brought into line with the declared protocol: 13 requests and 14 replies, with
`ImportKey`, `SignMessage`, and `Plan` (and their replies) marked planned. Every other ruling above is unchanged.
