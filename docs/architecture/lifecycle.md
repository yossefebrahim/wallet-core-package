# Session lifecycle — interface sketch

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

| | |
|---|---|
| **Decision** | [DECISION-12](../decisions/DECISION-12.md) — session lifecycle and worker protocol |
| **Binding on** | T1.11 (session, proxies, errors), T2.1 (worker), T1.6 (internal handles), T1.7 (loader), T2.12 (fault suite) |
| **Status** | sketch: signatures and doc comments only, no bodies. recommended by T0.11; adjudicated at D0 (recommendation upheld); pending the human's recording. |

Sections 1–4 are the public surface (`package:wallet_core_flutter/wallet_core_flutter.dart`) and contain no foreign-function, generated, or serialization types. Sections 5–7 are internal to the SDK and the bindings package and are labelled as such.

---

## 1. `WalletCore` — the session

```dart
/// A session: one loaded native library, one owning isolate, and the handles
/// that isolate holds.
///
/// A session is the unit of teardown. `close()` on a single wallet frees that
/// wallet; [shutdown] frees everything and ends the session. There is no "lock"
/// flag: locking an application is [shutdown], and unlocking is a new
/// [initialize] followed by re-importing from an encrypted keystore.
abstract interface class WalletCore {
  /// Spawns the session's isolate, loads the native library there, verifies the
  /// build identity and the release set against the shipped manifest, runs a
  /// symbol-lookup health check, and returns only once the session is
  /// [SessionState.ready].
  ///
  /// Throws [NativeLoadError] when the library cannot be loaded or the build
  /// identity symbol is absent, and [ManifestMismatchError] when the identity,
  /// the manifest hash, or the three packages' release-set ids disagree. In
  /// either case no session is returned and nothing needs closing.
  static Future<WalletCore> initialize({
    /// Maximum number of queued plus in-flight operations. Submitting beyond it
    /// throws [QueueFullError] rather than queueing without bound.
    int queueLimit = 32,
    OperationTimeouts timeouts = const OperationTimeouts(),
  });

  /// The current state. Synchronous and always safe to read.
  SessionState get state;

  /// State changes, as a broadcast stream, so an application can react to
  /// [SessionState.failed] without polling.
  Stream<SessionState> get states;

  WalletFacade get wallets;
  AddressFacade get addresses;
  Signer get signer;

  /// Runs [body] and closes every public resource created inside it, in reverse
  /// order of creation, whether [body] returns or throws.
  Future<T> scope<T>(Future<T> Function(SessionScope scope) body);

  /// Stops accepting work, rejects queued operations with [SessionStateError],
  /// lets the one in-flight operation finish, disposes every handle, and ends
  /// the isolate.
  ///
  /// Idempotent: concurrent and repeated calls await the same completion. If the
  /// isolate does not acknowledge within the shutdown grace period it is killed,
  /// which is recorded — a killed isolate does not wipe what it owned.
  Future<void> shutdown();
}

/// Lifecycle of a [WalletCore] session. Operations are accepted only in [ready].
enum SessionState { initializing, ready, closing, closed, failed }

/// Per-operation deadlines. A deadline starts when the operation is *submitted*,
/// so time spent queued counts against it.
///
/// A deadline does not abort work already running in native code — there is no
/// mechanism to do that. The operation runs to completion, its key material and
/// temporaries are released as usual, and its result is discarded.
///
/// There is deliberately **no** deadline for releasing a resource. [Wallet.close]
/// waits without one, because no bound on it could be enforced: an isolate
/// blocked inside a native delete runs no timer of its own, and no other isolate
/// can tell that case apart from any other slow native call (DECISION-12 §3.5).
/// [shutdownGrace] is the only bound on teardown, and the only recovery.
final class OperationTimeouts {
  const OperationTimeouts({
    this.initialize = const Duration(seconds: 30),
    this.walletOperation = const Duration(seconds: 20),
    this.derivation = const Duration(seconds: 5),
    this.signing = const Duration(seconds: 15),
    this.shutdownGrace = const Duration(seconds: 10),
  });

  final Duration initialize;
  final Duration walletOperation;
  final Duration derivation;
  final Duration signing;

  /// Bounds teardown as a whole. This one **does** expire: on expiry the owning
  /// isolate is killed and the session moves to [SessionState.closed], which is
  /// recorded, because the alternative is a session that never closes. A kill
  /// does not wipe what that isolate owned.
  final Duration shutdownGrace;
}
```

## 2. `Wallet` — a proxy, not a handle

```dart
abstract interface class WalletFacade {
  /// Creates a wallet with a new random mnemonic of [strength] bits.
  ///
  /// [passphrase] crosses to the owning isolate and is key material. **The new
  /// mnemonic does not come back from this call**: it is obtained the same way
  /// any other wallet's is, by calling [Wallet.exportMnemonic] on the result,
  /// so that a mnemonic crosses the boundary by exactly one path. See the
  /// enumeration in [Wallet.exportMnemonic] and
  /// `docs/security/memory_contract.md`.
  Future<Wallet> create({int strength = 128, String passphrase = ''});

  /// Imports a wallet from a BIP-39 mnemonic.
  ///
  /// Carries a secret across the isolate boundary. The mnemonic is a Dart
  /// `String`: this SDK drops its own references once the wallet exists and
  /// cannot erase the caller's copy or the platform's input buffers. See
  /// `docs/security/memory_contract.md`.
  Future<Wallet> importMnemonic(String mnemonic, {String passphrase = ''});

  /// Imports a wallet from entropy. Same secret-handling note as
  /// [importMnemonic].
  Future<Wallet> importEntropy(Uint8List entropy, {String passphrase = ''});
}

/// A handle-free reference to a wallet owned by the session's isolate.
///
/// The object in the calling isolate holds an opaque reference and plain values
/// only. It cannot free anything itself; [close] asks the owner to free it and
/// awaits the acknowledgement.
abstract interface class Wallet {
  /// Opaque, session-scoped identity of this wallet. Used to name keys when
  /// signing (see `KeyLocator` in [signing.md](signing.md)). It is not a
  /// capability to key material and carries no key.
  WalletRef get ref;

  /// Whether [close] has been called. `true` from the moment [close] is called,
  /// not from the moment it completes.
  bool get isClosed;

  /// Derives an account descriptor. Nothing native crosses back: the result is
  /// an address, a public key, and a path.
  ///
  /// Throws [UnsupportedOperationError] when ([coin], [network], [style]) has no
  /// derivation at the pinned upstream tag, before any native call.
  Future<Account> account(
    Coin coin, {
    Network network = Network.mainnet,
    AddressStyle style = AddressStyle.standard,
    String? path,
  });

  /// The wallet's mnemonic.
  ///
  /// Returns a Dart `String` because it exists to be shown to a person. The
  /// string lives until it is collected and cannot be erased. Display it once
  /// and drop the reference.
  ///
  /// This is the **only** payload that carries key material *back* across the
  /// isolate boundary, and one of four that carry it in either direction: the
  /// request names only this wallet, the reply is the mnemonic. The other three
  /// all go outward — [WalletFacade.create] (a passphrase), [importMnemonic]
  /// and [importEntropy] (a mnemonic or entropy, and a passphrase), and
  /// keystore import (a blob and its password). Nothing else crosses in either
  /// direction (DECISION-12 §3.2). A wallet made by [WalletFacade.create]
  /// surrenders its mnemonic here too, and nowhere else.
  Future<String> exportMnemonic();

  /// Releases this wallet in the owning isolate and awaits the acknowledgement.
  ///
  /// Idempotent: repeated and concurrent calls await the same completion.
  /// The proxy is unusable from the moment this is called — every other member
  /// then throws [ClosedError] — and the underlying handle is freed after any
  /// operation already in flight on it has finished.
  ///
  /// **This wait has no deadline**, and there is no timeout setting for it. An
  /// operation already running in native code cannot be interrupted, so the
  /// acknowledgement can legitimately take arbitrarily long, and a deadline on
  /// it could not be enforced anyway: an isolate blocked inside a native delete
  /// runs no timer, and from outside it looks like any other slow native call
  /// (DECISION-12 §3.5). The returned future completes when the acknowledgement
  /// arrives, or with [WorkerTerminatedError] if the session's isolate ends
  /// first — never with [OperationTimeoutError]. A caller that must bound its
  /// wait uses [WalletCore.shutdown], whose [OperationTimeouts.shutdownGrace]
  /// does expire and kills the isolate; that kill does not wipe what the
  /// isolate owned.
  Future<void> close();
}

/// An opaque, session-scoped reference. Not forgeable, not transferable between
/// sessions, not a key.
final class WalletRef {
  const WalletRef._();
}

/// A scope that closes what was created inside it.
abstract interface class SessionScope {
  Future<Wallet> createWallet({int strength = 128, String passphrase = ''});
  Future<Wallet> importMnemonic(String mnemonic, {String passphrase = ''});
}
```

## 3. Error hierarchy

PRD §10.2, with the four members DECISION-12 §6 adds.

```dart
/// Base of every error this SDK raises. Sealed: a caller can switch
/// exhaustively, and a new member is a breaking change we take deliberately.
sealed class WalletCoreException implements Exception {
  String get message;
}

/// Input rejected by this SDK before reaching native code.
class InvalidInputError extends WalletCoreException { … }

/// The coin, capability, variant, or combination is not offered at this version
/// or at the pinned upstream tag. Carries the coin and a capability string, e.g.
/// `'network:testnet'`, `'multisig'`, `'psbt'`, `'external-signer'`.
final class UnsupportedOperationError extends WalletCoreException { … }

/// Upstream reported a signing failure. Carries upstream's numeric code and its
/// message, verbatim and unmodified; never the input that caused it.
final class SigningError extends WalletCoreException { … }

/// The named keys could not be resolved into the set the operation needs:
/// a missing role, an unused locator, a reference from another session, or an
/// account with no key behind it.
final class KeyResolutionError extends WalletCoreException { … }

/// An **internal** native-backed object was used after `dispose()`.
/// Never raised by the public surface; visible through `advanced.dart`.
final class DisposedError extends WalletCoreException { … }

/// A **public** resource was used after `close()`.
final class ClosedError extends WalletCoreException { … }

/// The session's owning isolate ended. Every reference is invalid and the
/// session must be re-initialized. Nothing is ever retried silently.
final class WorkerTerminatedError extends WalletCoreException {
  WorkerTerminationKind get kind;
  Object? get cause;
}

/// Why the owning isolate ended.
///
/// There is deliberately no member for a hard native crash: such a crash ends
/// the whole process, so no code of ours survives to report it. The application's
/// platform crash reporter is the only observer of that case.
enum WorkerTerminationKind { initializationFailed, uncaughtDartError, isolateExited }

/// The native library could not be located, loaded, or resolved — including the
/// case where the build-identity symbol is absent, which means the loaded
/// library is not one of ours.
final class NativeLoadError extends WalletCoreException { … }

/// The shipped manifest, the three packages' embedded release-set ids, and the
/// loaded library's build identity do not agree. [check] names which comparison
/// failed.
final class ManifestMismatchError extends WalletCoreException {
  ManifestCheck get check;
}

enum ManifestCheck {
  releaseSetMismatch,
  manifestHashMismatch,
  artifactSetMismatch,
  upstreamCommitMismatch,
}

// --- added by DECISION-12 §6 ------------------------------------------------

/// An operation was attempted in a session state that does not accept it.
final class SessionStateError extends WalletCoreException {
  SessionState get actual;
}

/// The bounded queue was full. The operation was not queued and did not run.
final class QueueFullError extends WalletCoreException {
  int get limit;
}

/// The operation's deadline elapsed. Work already running in native code was not
/// aborted; its result was discarded and its temporaries released.
final class OperationTimeoutError extends WalletCoreException {
  Duration get timeout;
}

/// The operation was cancelled before it started. It never ran and no key was
/// derived for it.
final class OperationCancelledError extends WalletCoreException { … }
```

## 4. What the public surface deliberately does not have

- No synchronous `dispose()` anywhere. Public resources close asynchronously; `lint:public-api` (T1.15) fails a public member named `dispose` returning `void`.
- No public type holding a native address, and no public signature naming a foreign-function, generated, or serialization type (AGENTS.md rules 4 and 12).
- No way to obtain a wallet reference from one session and use it in another.
- No retry, anywhere. A failed operation fails.

## 5. Internal disposal contract — **SDK- and bindings-internal, not public surface**

This section describes objects that live inside one isolate and are never exported from `wallet_core_flutter.dart`. The synchronous contract below is PRD §11.2 and is the counterpart to the asynchronous `close()` above.

```dart
/// Something that owns a native resource and must be released explicitly.
///
/// Disposal is the primary cleanup path. The finalizer is a fallback for objects
/// a caller forgot, not a strategy.
abstract interface class Disposable {
  /// Releases the resource. Calling it twice is a no-op.
  void dispose();

  bool get isDisposed;
}

/// Base for a wrapper around one native-owned object.
///
/// On [dispose] it calls upstream's delete function for that object, detaches
/// its native finalizer using the detach key registered when it was attached,
/// and marks itself disposed. Any use after that throws [DisposedError], checked
/// at this boundary and never in native code.
///
/// A `NativeFinalizer` (from `dart:ffi`; **bindings-internal**, never attached to
/// a public proxy) is attached at construction with the native address as its
/// token and this wrapper as its detach key. Its callback is upstream's delete
/// function directly: no Dart code runs in it, which is exactly why it cannot be
/// used to release something owned by another isolate.
abstract base class NativeResource implements Disposable { … }

/// Disposes everything created inside it, in reverse order, on the way out —
/// including when the body throws.
abstract interface class ResourceScope {
  T use<T extends Disposable>(T resource);
}
```

**The two lifecycles side by side** (DECISION-12 §3.11):

| | Internal handle | Public resource |
|---|---|---|
| Contract | synchronous `void dispose()` | asynchronous idempotent `Future<void> close()` |
| Callable from | only the isolate that owns the handle | any isolate holding the proxy |
| After use | `DisposedError` | `ClosedError` |
| Fallback | native finalizer, callback = upstream delete, runs no Dart code | managed `Finalizer`, callback posts a dispose message |
| Guarantee | upstream wipes the buffer that object currently owns, and nothing beyond it | the acknowledgement proves the owner released the handle |

**Proxy finalizer rule.** A public proxy attaches a *managed* `Finalizer` whose callback posts a dispose message for its reference. The callback may **run** at any time — collection timing is the runtime's to choose — but it **posts** only while the session is `ready`; in `closing`, `closed`, or `failed` it does nothing at all, because shutdown already released every handle. Receiving a dispose message is safe in any state, which is why the callback needs no lock. It never throws and never reports to the application. A proxy collected after the session closed is not counted as a leak.

## 6. Worker protocol types — **internal to the SDK, not exported**

These types cross the isolate boundary: **13 requests and 14 replies**. Every one of them is a plain immutable value with no native address and no reference to anything unsendable except the one reply port in `Init`.

Four of the 27 carry key material, and they are enumerated rather than counted loosely (DECISION-12 §3.2): the requests `CreateWallet` (a passphrase), `ImportWallet` (a mnemonic or entropy, and a passphrase) and `ImportKey` (a keystore blob and its password, or raw key bytes under `advanced.dart`); and one reply, `MnemonicExported` (the wallet's mnemonic). `WalletCreated` carries a reference and nothing else — a newly created wallet's mnemonic comes back through `ExportMnemonic` like any other, so a mnemonic crosses the boundary by exactly one reply type. Every other request and reply is key-less by construction. A secret-bearing payload is never logged, never put into an error, and never retained by the worker after it has crossed; the SDK drops its own references, and cannot erase the caller's.

```dart
sealed class WorkerRequest {
  /// Monotonic within a session, never reused. Every reply carries the same id.
  int get id;
}

final class Init extends WorkerRequest { … }             // manifest snapshot, reply port, limits
final class CreateWallet extends WorkerRequest { … }     // strength, passphrase — carries a secret
final class ImportWallet extends WorkerRequest { … }     // mnemonic OR entropy, passphrase — carries a secret
final class ImportKey extends WorkerRequest { … }        // keystore blob + password — carries a secret
final class ExportMnemonic extends WorkerRequest { … }   // walletRef — key-less request, secret-bearing reply
final class DeriveAddress extends WorkerRequest { … }    // walletRef, coin, network, style, path
final class ValidateAddress extends WorkerRequest { … }  // value, coin, network
final class Sign extends WorkerRequest { … }             // request value, Set<KeyLocator>
final class SignMessage extends WorkerRequest { … }      // message request value, Set<KeyLocator>
final class Plan extends WorkerRequest { … }             // UTXO request value, no keys
final class DisposeRef extends WorkerRequest { … }       // ref — control message, exempt from the queue bound
final class Cancel extends WorkerRequest { … }           // target request id — control message
final class Shutdown extends WorkerRequest { … }         // grace period — control message

sealed class WorkerReply {
  int get id;
}

final class InitOk extends WorkerReply { … }             // resolved symbol count
final class WalletCreated extends WorkerReply { … }      // walletRef only — no mnemonic, no secret
final class KeyImported extends WorkerReply { … }        // keyRef
final class MnemonicExported extends WorkerReply { … }   // mnemonic — carries a secret
final class AddressDerived extends WorkerReply { … }     // address, public key, path
final class AddressValidated extends WorkerReply { … }   // bool
final class Signed extends WorkerReply { … }             // SignResult
final class MessageSigned extends WorkerReply { … }      // SignResult
final class Planned extends WorkerReply { … }            // UtxoPlan
final class Disposed extends WorkerReply { … }           // ref — sent for unknown refs too
final class Cancelled extends WorkerReply { … }
final class NotCancellable extends WorkerReply { … }     // already running in native code
final class ShutdownComplete extends WorkerReply { … }   // count of handles disposed
final class Failed extends WorkerReply {                 // an already-typed error, never a string
  WalletCoreException get error;
}
```

Rules the types encode, from DECISION-12 §3:

- Exactly one reply per request, correlated by `id`. The exceptions are a dispose posted by a finalizer and a cancel, whose replies nobody awaits.
- `DisposeRef`, `Cancel`, and `Shutdown` are control messages and are never rejected for a full queue: a load spike must not prevent teardown. The control path is nonetheless bounded (DECISION-12 §3.4): at most one pending `DisposeRef` per reference and one pending `Cancel` per target id, a `Cancel` for an unknown or finished id answered `NotCancellable` without being enqueued, a reserved control capacity, and `Shutdown` admissible always.
- `DisposeRef` for an unknown, already-disposed, or shutdown-freed reference is a no-op that still replies `Disposed`.
- An operation parses upstream's output into a Dart-owned result **before** its `finally` releases the derived keys and every other key-bearing buffer, and the reply is posted after that release: parse, release, reply (DECISION-12 §3.9). The retained result is not key-bearing.
- `Failed` carries a constructed exception, so the calling isolate never rebuilds an error from text.

## 7. `advanced.dart` — **explicitly outside the public contract**

`package:wallet_core_flutter/advanced.dart` exports a **same-isolate** `HDWallet` that owns its handle in the caller's isolate and follows the synchronous contract of §5: `dispose()`, `DisposedError` after disposal, a native finalizer as fallback. It is for tests, command-line tools, and callers who accept the ownership and secret-handling responsibilities of PRD §11.

Three statements belong in its documentation and in the cookbook (T3.3):

1. It is not a proxy and holds no session reference; nothing acknowledges its disposal.
2. It must never be shared across isolates. Two isolates each owning their own handles is supported; one handle used from two isolates is not.
3. The generated bindings and the serialization classes are re-exported here, and only here. Anything a caller does with them is outside the memory contract this SDK upholds elsewhere.
