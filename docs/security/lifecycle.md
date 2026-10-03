# Lifecycle

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

Describes the SDK as of task T1.12 (EVM signing).

This page covers how objects are created, released and failed. What happens to secrets in memory is on the [Memory Contract](memory_contract.md) page. Paths are relative to the repository root.

## Two kinds of object

| | Public resource | Internal handle |
|---|---|---|
| Examples | `Wallet`, `WalletCore` | `TWDataHandle`, `TWStringHandle`, `HDWallet`, `PrivateKeyHandle`, `PublicKeyHandle`, `AnyAddressHandle` |
| Release | `Future<void> close()` / `shutdown()`, asynchronous and idempotent | `void dispose()`, synchronous |
| Use after release | `ClosedError` | `DisposedError` |
| Fallback | A managed `Finalizer` that posts a dispose message | A `NativeFinalizer` whose callback is upstream's delete |

Sources: DECISION-12 §3.11 (`docs/decisions/DECISION-12.md`), `WalletProxy` (`packages/wallet_core_flutter/lib/src/wallet/wallet.dart`) and `NativeResource` (`packages/wallet_core_flutter_bindings/lib/src/memory/native_resource.dart`).

## The executor in this version

The session never calls native code. It sends `WorkerRequest`s to an executor and receives `WorkerReply`s (`packages/wallet_core_flutter/lib/src/worker/protocol.dart`). In this version the executor is `InProcessTransport` (`packages/wallet_core_flutter/lib/src/worker/transport.dart`), which `startSession` sets up by default (`packages/wallet_core_flutter/lib/src/session/session.dart`). It runs `WorkerLoop` and `EngineRequestHandler` on the **calling isolate's** event loop:

- **Asynchronous both ways.** A request is handled in a later event-loop turn, and a reply is delivered in a later microtask.
- **Native work blocks the calling isolate.** No timer fires while it runs, so the executor checks deadlines itself, before an operation starts and after it ends.
- **Phase 2 (T2.1) swaps in a worker isolate.** It runs the same loop over the same protocol. Neither the session nor the protocol changes (`WorkerTransport` doc).

## `Wallet`: a public proxy

`Wallet.close()` (`WalletProxy.close`):

1. Marks the proxy closed at once. `isClosed` becomes `true`, and every other member throws `ClosedError` (`WalletProxy._checkOpen`).
2. Asks the session to release the wallet (`WalletCoreSession.releaseWallet`).
3. Detaches the proxy's finalizer.
4. Returns a future. Repeated and concurrent calls get the same future.

**The wait has no deadline** (DECISION-12 §3.5). What the future does depends on the session state:

| Session state | What `close()` does |
|---|---|
| `ready` | Sends `DisposeRef` and completes on `Disposed` |
| `closing` | Completes with shutdown's acknowledgement. If shutdown was forced, completes with `WorkerTerminatedError(isolateExited)` |
| `closed` | Completes at once, because shutdown released everything. If shutdown was forced, completes with `WorkerTerminatedError(isolateExited)` |
| `failed` | Completes with the session's termination error |

**Close waits for in-flight work.** Operations and `DisposeRef`s share one FIFO queue in `WorkerLoop` (`packages/wallet_core_flutter/lib/src/worker/worker_loop.dart`). A `close()` sent while an operation on the same wallet is queued or running is handled after that operation. Repeated `DisposeRef`s for one reference are folded into one.

**Wallet references:**

- Before submitting, `SessionSigner` (`packages/wallet_core_flutter/lib/src/signing/local_signer.dart`) calls `resolveWalletRef` (`wallet.dart`) for each wallet a `KeyLocator` names.
  - A reference from another session is rejected with `KeyResolutionError(foreignRef)`.
  - A closed wallet is rejected with `ClosedError`.
- The executor repeats these checks itself:
  - `EngineRequestHandler._resolveKeys` compares session tokens.
  - `EngineRequestHandler._resolve` answers `ClosedError` for a released reference and `InvalidInputError` for one it never issued (`packages/wallet_core_flutter/lib/src/worker/handler.dart`).

## Internal handles and `advanced.dart`

Each internal handle, including the same-isolate `HDWallet` exported by `packages/wallet_core_flutter/lib/advanced.dart`:

- On `dispose()`, calls its upstream delete (for `HDWallet`, `TWHDWalletDelete`), detaches the native finalizer and marks itself disposed (`NativeResource.dispose`).
- Does nothing on a second `dispose()`.
- Throws `DisposedError` on any later use.

`HDWallet` is not a proxy and has no session reference, so nothing acknowledges its disposal. It must never be shared across isolates (`advanced.dart` library doc).

## Finalizers

| | `NativeFinalizer` (internal handles) | Managed `Finalizer` (`WalletProxy`) |
|---|---|---|
| Attached in | The `NativeResource` constructor | The `WalletProxy` constructor (`WalletProxy._finalizer`) |
| Callback | Upstream's delete function. No Dart code runs | `WalletCoreSession.postFinalizerDispose`: posts `DisposeRef` only while the session is `ready`, otherwise does nothing; never throws |
| When it runs | "As early as possible" after the object becomes unreachable; guaranteed at the latest at isolate-group shutdown; not when the process is killed (PRD §11.1, `docs/wallet_core_flutter_prd.md`) | **May never run.** The PRD §11.1 guarantee covers `NativeFinalizer` only |

Neither finalizer is a release strategy. A `Wallet` that is never closed is released by `shutdown()`, or by its finalizer if that runs while the session is `ready`. A `WalletRef` keeps its proxy reachable, so a wallet whose reference is still held is never released by the finalizer (`WalletRef` doc).

## Session states

States are defined by `SessionState` (`packages/wallet_core_flutter/lib/src/lifecycle/session_state.dart`). The transitions are `initializing → ready`, `initializing → failed`, `ready → closing`, `ready → failed`, `closing → closed`, `closing → failed` and `failed → closed`. Nothing leaves `closed`. Recovery means starting a new session.

Operations are accepted only in `ready`. Otherwise `WalletCoreSession.checkReady` throws:

| State | Error |
|---|---|
| `initializing`, `closing` | `SessionStateError` |
| `closed` | `ClosedError` |
| `failed` | The session's `WorkerTerminatedError` |

## Starting a session: what `initialize()` can throw

`WalletCore.initialize` (`packages/wallet_core_flutter/lib/src/session/wallet_core.dart`) calls `startSession` (`session.dart`).

| Error | When | Where |
|---|---|---|
| `InvalidInputError` | `queueLimit` below 1 (`inputName: 'queueLimit'`) or a timeout that is not positive (`'timeouts'`), before anything is created | `startSession` |
| `NativeLoadError` | The library cannot be loaded, the identity symbol is absent, or a symbol is missing | `EngineRequestHandler._init`, mapped by `toWalletCoreException` (`packages/wallet_core_flutter/lib/src/errors/boundary.dart`) |
| `ManifestMismatchError` | The build identity or manifest hash does not match | `EngineRequestHandler._init` |
| `OperationTimeoutError` | No reply to `Init` within `OperationTimeouts.initialize` | `WalletCoreSession._expire` |
| `WorkerTerminatedError(initializationFailed)` | Any other error during `Init`: the executor stops | `WorkerLoop._fault`, `WalletCoreSession._onTerminated` |

In every case no session is handed out. The session moves to `failed`, fails anything pending and closes the transport (`WalletCoreSession._initialize`). The doc comment of `WalletCore.initialize` names only `NativeLoadError` and `ManifestMismatchError`.

## Scopes

**`WalletCore.scope`** (`runInScope`, `packages/wallet_core_flutter/lib/src/session/scope.dart`) closes every wallet created **through the scope**, meaning its own `createWallet`, `importMnemonic` and `importEntropy`. It closes them in reverse order of creation, whether the body returns or throws.

- A creation still running when the body ends is awaited, and its wallet is closed too.
- If the body throws, that error is rethrown. If the body returns and a close fails, the first close error is thrown after every wallet has been closed.
- After the body ends, the scope's members throw `ClosedError`.

**A wallet the body creates any other way is not closed by the scope.** For example, `core.wallets.create()` inside the body gives a wallet that stays open in the executor, holding its mnemonic, until `close()`, `shutdown()`, or its proxy finalizer.

**`ResourceScope`** (`runScope`, `packages/wallet_core_flutter_bindings/lib/src/memory/resource_scope.dart`) is internal. It disposes only the handles registered through it (`use`, `data`, `string`), last first. Its body must be synchronous.

## Queue, deadlines and late results

**The queue limit.** `WalletCoreSession.submit` throws `QueueFullError` when `queueLimit` operations are already outstanding. Control messages are never rejected for a full queue: `close()`'s `DisposeRef`, `Shutdown`, `Cancel`, and finalizer posts.

**When a deadline passes.** A deadline starts when an operation is submitted. When it passes, the caller's future completes with `OperationTimeoutError` (`WalletCoreSession._expire`), and the session posts `Cancel` while `ready`:

- **If the operation is still queued**, the executor removes it and it never runs (`WorkerLoop._cancel`). An operation still queued when its deadline has passed is also skipped when its turn comes (`WorkerLoop._drainOne`).
- **If the operation is already running**, native work cannot be stopped. It finishes, and its temporaries and any derived key are released as usual. Then the executor **drops the result without posting it** (`WorkerLoop._drainOne`):
  - `EngineRequestHandler.discard` releases a wallet the operation created.
  - A key-less `Failed(OperationTimeoutError)` is posted in its place.
  - A late exported mnemonic is never posted.

**The session's backstop.** A reply that arrives after the caller's future has completed is dropped (`WalletCoreSession._onReply`). If it is a `WalletCreated`, the session posts a `DisposeRef` for that wallet while `ready` (`WalletCoreSession._discardLate`).

## Failures

- **Soft native failure.** Upstream returns a null or an out-of-range size, which is raised as `NativeResultError`. This becomes a typed error for that **one operation**, and the session stays `ready` (`EngineRequestHandler.handle`, `softNativeFailure`):
  - `Sign` → `SigningError` with `SigningError.malformedOutputCode`.
  - Every other operation → `InvalidInputError` naming its main input.
- **Mapped error.** Any error `toWalletCoreException` maps is answered as a `Failed` reply for that operation.
- **Anything else is an executor fault** (`WorkerLoop._fault`):
  - The loop stops and releases every wallet, best effort (`EngineRequestHandler.releaseAll`).
  - It overwrites the entropy copies of queued requests and answers nothing more.
  - It reports `WorkerTerminatedError`: `uncaughtDartError`, or `initializationFailed` during `Init`. The cause is `WorkerFault`, which names only the error's type.
  - The session moves to `failed` and fails every pending call (`WalletCoreSession._onTerminated`).
- **Native crash.** A crash inside upstream ends the process, and nothing is reported (DECISION-12 §3.10).

## Shutdown

`WalletCore.shutdown()` (`WalletCoreSession.shutdown`, `_runShutdown`):

1. Moves `ready → closing`. New operations get `SessionStateError`.
2. Sends `Shutdown`. The executor rejects queued operations with `SessionStateError`, and lets queued `DisposeRef`s and the running operation finish (`WorkerLoop._shutdown`).
3. Releases every wallet (`EngineRequestHandler._shutdown`), stops the leak tracker, and replies `ShutdownComplete`.
4. Moves to `closed`. Anything still pending fails with `ClosedError`.

**Calling it again:** repeated calls return the same future. In `failed` it moves to `closed` on the Dart side only. In `initializing` it throws `SessionStateError`.

**If the executor dies during shutdown**, the session goes `closing → failed → closed` and `shutdown()` throws the `WorkerTerminatedError`.

**Forced shutdown.** If no acknowledgement arrives within `OperationTimeouts.shutdownGrace`, the session calls `WorkerTransport.kill()` and moves to `closed`. Pending calls, and later `close()` calls, fail with `WorkerTerminatedError(isolateExited)`. `shutdown()` itself completes normally. What the kill releases depends on the executor:

| Executor | What a forced stop releases |
|---|---|
| This version (`InProcessTransport`) | `InProcessTransport.kill` → `WorkerLoop.kill` → `WorkerLoop._stop` → `EngineRequestHandler.releaseAll`: **every wallet is still released** (best effort), and queued entropy copies are overwritten. The grace timer runs on the same isolate, so it cannot fire while a native call is running |
| Worker isolate (Phase 2, not built) | `OperationTimeouts.shutdownGrace` doc: "A forced stop does not wipe what that isolate owned" (also DECISION-12 §3.8) |

## Not verified

- **Managed `Finalizer` behaviour.** The Dart runtime's documentation for the managed `Finalizer` (`dart:core`) is not in this repository. This page relies on it only to say that `WalletProxy`'s finalizer may never run.
- **Phase 2 forced stop.** The worker-isolate behaviour comes from the code's doc comments and DECISION-12. That transport does not exist yet.
