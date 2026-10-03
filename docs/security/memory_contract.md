# Memory Contract

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

Describes the SDK as of task T1.12 (EVM signing).

This page lists where the SDK puts secrets (mnemonics, passphrases, entropy, private keys), which copies are overwritten and by whom, and which are not. It describes behaviour and its limits. It does not promise any security property.

- Paths are relative to the repository root.
- Upstream paths are under `third_party/wallet-core/`, at the pinned tag 4.8.0 (`docs/decisions/DECISION-1-approach-a.md`, "Pinned upstream").
- Statements about upstream come from reading its source. They were not observed at run time.
- Claims this page could not check are listed under [Not verified](#not-verified).

## The disposal contract

PRD §11.2 (`docs/wallet_core_flutter_prd.md`) governs every internal native handle. Each one extends `NativeResource` (`packages/wallet_core_flutter_bindings/lib/src/memory/native_resource.dart`):

| Handle | Defined in | Upstream delete |
|---|---|---|
| `TWDataHandle` | `packages/wallet_core_flutter_bindings/lib/src/memory/tw_data.dart` | `TWDataDelete` |
| `TWStringHandle` | `packages/wallet_core_flutter_bindings/lib/src/memory/tw_string.dart` | `TWStringDelete` |
| `HDWallet` | `packages/wallet_core_flutter/lib/src/engine/hd_wallet.dart` | `TWHDWalletDelete` |
| `PrivateKeyHandle` | `packages/wallet_core_flutter/lib/src/engine/handles.dart` | `TWPrivateKeyDelete` |
| `PublicKeyHandle` | `packages/wallet_core_flutter/lib/src/engine/handles.dart` | `TWPublicKeyDelete` |
| `AnyAddressHandle` | `packages/wallet_core_flutter/lib/src/engine/handles.dart` | `TWAnyAddressDelete` |

What each handle does:

1. **Disposal is the primary path.** The finalizer is a fallback for a handle someone forgot to dispose (`NativeResource` class doc).
2. **`dispose()`** calls the subclass's `releaseNative` (the upstream delete), detaches the native finalizer and marks the handle disposed (`NativeResource.dispose`).
3. **A second `dispose()` does nothing.** Any use after disposal throws `DisposedError` (`NativeResource.checkNotDisposed`, `NativeResource.rawPointer`). `HDWallet` throws the SDK's own `DisposedError` (`HDWallet._wallet`).
4. **Temporary `calloc` buffers are freed in a `finally`.** This applies to `TWDataHandle.fromBytes`, `TWStringHandle.fromString` and the secret helpers in `packages/wallet_core_flutter/lib/src/engine/secret_buffers.dart`.
5. **The native finalizer is attached at construction.** Its callback is the upstream delete function itself, so no Dart code runs in it. See the `NativeResource` constructor, `NativeContext.dataFinalizer` and `NativeContext.stringFinalizer` (`packages/wallet_core_flutter_bindings/lib/src/memory/native_context.dart`), and `EngineFinalizers` (`handles.dart`).
6. **`runScope` disposes everything registered through its `ResourceScope`** (`use`, `data`, `string`), in reverse order, whether the body returns or throws. A handle that was never registered is not disposed by the scope (`packages/wallet_core_flutter_bindings/lib/src/memory/resource_scope.dart`).
7. **Debug-only leak tracker.** See [The leak tracker](#the-leak-tracker).

## What upstream's delete functions overwrite

| Delete | Behaviour at the pinned tag | Source |
|---|---|---|
| `TWDataDelete` | `memzero` over the buffer's current `size()` bytes, then `delete` | `third_party/wallet-core/src/interface/TWData.cpp`, `TWDataDelete` |
| `TWStringDelete` | `memzero` over the string's current `size()` bytes, then `delete` | `third_party/wallet-core/src/interface/TWString.cpp`, `TWStringDelete` |
| `TWPrivateKeyDelete` | `delete pk`. `~PrivateKey()` calls `cleanup()`, which runs `memzero` over `bytes` | `third_party/wallet-core/src/interface/TWPrivateKey.cpp`, `TWPrivateKeyDelete`; `third_party/wallet-core/src/PrivateKey.h`, `~PrivateKey`; `third_party/wallet-core/src/PrivateKey.cpp`, `PrivateKey::cleanup` |
| `TWHDWalletDelete` | `delete wallet`. `~HDWallet` runs `memzero` over `seed`, `mnemonic` and `passphrase`. **It does not overwrite the `entropy` member**, which `updateSeedAndEntropy` fills for every wallet | `third_party/wallet-core/src/interface/TWHDWallet.cpp`, `TWHDWalletDelete`; `third_party/wallet-core/src/HDWallet.cpp`, `~HDWallet` and `updateSeedAndEntropy`; `third_party/wallet-core/src/HDWallet.h`, `entropy` |
| `TWPublicKeyDelete`, `TWAnyAddressDelete` | These objects hold public data and were not examined | — |

The `memzero` covers each buffer's current size only. It does not reach memory beyond that size, or a buffer the object owned before upstream reallocated it (PRD §11.3).

## Secrets going in: mnemonic, passphrase, entropy

The path is `WalletFacade.create` / `importMnemonic` / `importEntropy` (`packages/wallet_core_flutter/lib/src/wallet/wallet.dart`), then `CreateWallet` or `ImportWallet` (`packages/wallet_core_flutter/lib/src/worker/protocol.dart`), then the executor, then `HDWallet.create`, `HDWallet.fromMnemonic` or `HDWallet.fromEntropy`.

| Copy | Made by | Overwritten? |
|---|---|---|
| The caller's `String` (mnemonic, passphrase) | The caller | **No.** Dart strings are immutable. The requests hold references to the same `String` (`CreateWallet.passphrase`, `ImportWallet.mnemonic`, `ImportWallet.passphrase`), which are dropped with the request |
| The caller's entropy `Uint8List` | The caller | **No.** It is read and never modified (`HDWallet.fromEntropy` doc) |
| The request's entropy copy | The `ImportWallet.entropy` constructor (`Uint8List.fromList`), built inside `WalletCoreSession.submit` (`packages/wallet_core_flutter/lib/src/session/session.dart`) | **Yes, by the sender**, through `overwriteOwnedSecrets`: in `WalletCoreSession.submit` if the request is rejected, otherwise in `InProcessTransport.send` (`packages/wallet_core_flutter/lib/src/worker/transport.dart`) right after the executor's copy is made, and also when the transport is already closed |
| The executor's entropy copy | `executorCopy` (`protocol.dart`), called by `InProcessTransport.send` | **Yes, by the executor**: in the `finally` of `EngineRequestHandler.handle` (`packages/wallet_core_flutter/lib/src/worker/handler.dart`) and of `WorkerLoop._drainOne` (`packages/wallet_core_flutter/lib/src/worker/worker_loop.dart`). If the request never runs, the copy is overwritten when it is cancelled (`WorkerLoop._cancel`), rejected by shutdown (`WorkerLoop._shutdown`), past its deadline (`WorkerLoop._drainOne`), received after the loop stopped (`WorkerLoop.receive`), dropped when the loop stops (`WorkerLoop._stop`), or arrives after the transport closed (`InProcessTransport.send`) |
| UTF-8 encoding of a mnemonic, passphrase, word or prefix | `secretString` (`secret_buffers.dart`) | **Yes**, filled with zeros in a `finally` |
| `calloc` staging buffer | `secretString`, `secretData` (`secret_buffers.dart`) | **Yes**, filled with zeros and then freed, on success and on failure |
| Native `TWString` / `TWData` input | `secretString`, `secretData` | Released by the SDK (scope or `finally` in the `HDWallet` factories); upstream's delete overwrites it |
| Upstream's wallet: `seed`, `mnemonic`, `passphrase`, `entropy` | Upstream `HDWallet` | Released when the wallet is released (`close()`, `shutdown()`, the executor's `releaseAll`, or the native finalizer). On `TWHDWalletDelete`, `seed`, `mnemonic` and `passphrase` are overwritten by upstream. `entropy` is not, and neither is the local `entropyRaw` in `updateSeedAndEntropy` (`third_party/wallet-core/src/HDWallet.cpp`) |

`WorkerTransport.send` requires every transport to give the executor its own copy and to overwrite the sender's copy before returning (`transport.dart`, `WorkerTransport.send`). `InProcessTransport` is the only transport that exists today, and it does both.

## Secrets coming out: the mnemonic

`Wallet.exportMnemonic` (`wallet.dart`) sends `ExportMnemonic`. In the executor, `HDWallet.exportMnemonic`:

1. calls `TWHDWalletMnemonic`, which returns a new `TWString` (`third_party/wallet-core/src/interface/TWHDWallet.cpp`, `TWHDWalletMnemonic`);
2. decodes it with `readSecretString` (`secret_buffers.dart`), which reads a view over upstream's buffer, so no intermediate Dart byte list is made;
3. disposes the handle in a `finally`, and `TWStringDelete` overwrites the native copy.

The result is a Dart `String` carried by `MnemonicExported` (`protocol.dart`). It is one of the two replies that carry key material, with `MnemonicWordsSuggested` (DECISION-12 §3.2, amended 2026-10-03). The SDK cannot overwrite it. Display it once and drop the reference.

`WalletEngine.suggestMnemonicWords` (`packages/wallet_core_flutter/lib/src/engine/engine.dart`) also decodes with `readSecretString`. Its result is a list of `String`s.

The requests `ValidateMnemonic`, `ValidateMnemonicWord`, and `SuggestMnemonicWords` carry a mnemonic, a word, or a prefix as Dart `String`s that cannot be overwritten. They are redacted from `toString()` and errors, and are dropped by the executor after use (`packages/wallet_core_flutter/lib/src/worker/protocol.dart:328-377`). This completes the list of all eight secret-bearing payloads (DECISION-12 §3.2).

## Private keys and signing

### What the API returns

- **The default surface returns no private-key bytes.** No type exported by `packages/wallet_core_flutter/lib/wallet_core_flutter.dart` returns them:
  - `Account` holds an address, a public key and a path (`HDWallet.deriveAccount` doc: "holds no key and no handle").
  - `EvmSignResult` holds the encoded transaction, `v`, `r`, `s` and the pre-hash (`packages/wallet_core_flutter/lib/src/signing/sign_result.dart`).
- **PRD §11.3** requires that private-key bytes reach callers "only through explicit `advanced` APIs".
- **What `packages/wallet_core_flutter/lib/advanced.dart` exposes today:**
  - `HDWallet`. None of its members returns a private key: `create`, `fromMnemonic`, `fromEntropy`, `exportMnemonic` (a mnemonic), `deriveAccount` and `dispose`.
  - `NativeResultError`.
  - Everything in the bindings barrel (`packages/wallet_core_flutter_bindings/lib/wallet_core_flutter_bindings.dart`): the generated `WalletCoreBindings`, the memory wrappers and the coin registry.
- **No function `advanced.dart` provides returns key bytes.** `withDerivedKey` is never exported, not even from `advanced.dart` (`withDerivedKey` doc).
- **A caller of `advanced.dart` can still get key bytes by calling upstream directly.** The generated bindings include `TWHDWalletGetKey` and `TWPrivateKeyData` (`packages/wallet_core_flutter_bindings/lib/src/generated/ffi/wallet_core_bindings.dart`), and `HDWallet` inherits the public `NativeResource.rawPointer`. Anything done that way is outside this contract (`advanced.dart` library doc, statement 3).

### Deriving an account (`wallet.account(...)`)

Every call to `HDWallet.deriveAccount` works like this:

1. `TWHDWalletGetKey` creates a new `TWPrivateKey`, adopted as a `PrivateKeyHandle` and registered with the call's `ResourceScope`.
2. The public key and the address are copied into Dart.
3. The scope releases everything in reverse order. `TWPrivateKeyDelete` runs `~PrivateKey`, which overwrites the key's bytes (table above).

No Dart view or copy of the private key exists on this path.

### Signing (`wc.signer.sign`)

`SessionSigner.sign` (`packages/wallet_core_flutter/lib/src/signing/local_signer.dart`) sends a `Sign` request. It carries the transaction request and `LocatorSpec`s (names), never a key (`protocol.dart`, `Sign`).

In the executor, `EngineRequestHandler._sign` runs these steps in order, and no key exists before step 5:

1. Resolve the locators.
2. Check the path.
3. Check the recipient.
4. Encode the input with no key in it, and check that it has no key field.
5. Derive the key (`withDerivedKey`, `hd_wallet.dart`).
6. Sign (`SyncSigningCore.sign`, `packages/wallet_core_flutter/lib/src/signing/signing_core.dart`).
7. Parse the output, release everything, then reply.

Every place the key exists during one call:

| # | Where the key is | Created by | Released by | Overwritten by |
|---|---|---|---|---|
| 1 | Upstream `TWPrivateKey` (C++ `PrivateKey`) | `TWHDWalletGetKey`, in `withDerivedKey` | The SDK: `PrivateKeyHandle`, disposed by `withDerivedKey`'s scope, last | **Upstream**: `~PrivateKey` → `PrivateKey::cleanup` (`third_party/wallet-core/src/PrivateKey.h`, `third_party/wallet-core/src/PrivateKey.cpp`) |
| 2 | Upstream's derivation temporaries | `HDWallet::getKeyByCurve` (`third_party/wallet-core/src/HDWallet.cpp`) | Upstream, before `TWHDWalletGetKey` returns | The HD node is overwritten by upstream (`TW::memzero(&node)`). **The local `Data data` key copy is released with no overwrite** as far as that function shows. Deeper derivation code (`getNode`, trezor-crypto) was not traced |
| 3 | Upstream `TWData` holding the key's bytes | `TWPrivateKeyData`, which is `TWDataCreateWithBytes(pk->impl.bytes…)` (`third_party/wallet-core/src/interface/TWPrivateKey.cpp`) | The SDK: `TWDataHandle`, disposed by `withDerivedKey`'s scope before #1 | **Upstream**: `TWDataDelete` |
| — | Dart `Uint8List` **view** over #3's buffer | `TWDataBytes(…).asTypedList(length)` in `withDerivedKey` | Not a copy. It dangles once #3 is released and is never retained | Nothing to overwrite: no key bytes are on the Dart heap |
| 4 | `calloc` staging buffer: field header, key, then the key-less input | `secretDataFromParts` (`secret_buffers.dart`), called by `SyncSigningCore.sign` | The SDK, in `secretDataFromParts`'s `finally` | **This SDK**: filled with zeros before `calloc.free`, whether or not `TWDataCreateWithBytes` succeeded |
| 5 | Keyed-input `TWData` (C++ `Data`) | `TWDataCreateWithBytes`, from #4 | The SDK: `input?.dispose()` in `SyncSigningCore.sign`'s `finally` | **Upstream**: `TWDataDelete` |
| 6 | Rust copy of the keyed input | `RustCoinEntry::sign` calls `tw_data_create_with_bytes`, which copies into a Rust `TWData(Vec<u8>)` (`third_party/wallet-core/src/rust/RustCoinEntry.cpp`; `third_party/wallet-core/rust/tw_memory/src/ffi/tw_data.rs`, `TWData::from_raw_data`) | Upstream: `TWDataWrapper` (`third_party/wallet-core/src/rust/Wrapper.h`) deletes it with `tw_data_delete` when `RustCoinEntry::sign` returns | **No one, as far as the sources show.** `tw_data_delete` only drops the `Vec`, and `TWData` defines no drop behaviour that overwrites it (`tw_data.rs`, `tw_data_delete`, `TWData`) |
| 7 | The `private_key` field of the decoded Rust `SigningInput` | `tw_proto::deserialize` (`third_party/wallet-core/rust/tw_proto/src/lib.rs`) | Upstream | Not verified: whether the field borrows #6 or copies it |
| 8 | Rust `secp256k1::PrivateKey` | `Signer::sign_proto_impl` (`third_party/wallet-core/rust/tw_evm/src/modules/signer.rs`) | Upstream, when the value is dropped | Upstream declares an overwrite-on-drop derive on the type (`third_party/wallet-core/rust/tw_keypair/src/ecdsa/secp256k1/private.rs`, `PrivateKey`). What the external `k256` `SigningKey` it wraps does was not verified |

What the path does not hold:

- `TWAnySignerSign` passes #5 to `TW::anyCoinSign` by reference, without copying it (`third_party/wallet-core/src/interface/TWAnySigner.cpp`; `third_party/wallet-core/src/Coin.cpp`, `anyCoinSign`).
- The field header holds the key's length, not its bytes (`lengthDelimitedHeader`).
- The key-less input, the decoded key-less message, the request, the locators and the reply hold no key.
- Upstream's output holds no key: the fields of the EVM `SigningOutput` are `encoded`, `v`, `r`, `s`, `data`, `error`, `error_message` and `pre_hash` (`third_party/wallet-core/src/proto/Ethereum.proto`, `SigningOutput`). `SyncSigningCore.sign` copies it out with `TWDataHandle.copyBytes`.
- No protobuf message ever holds the key, because the key field is prepended as bytes (`SyncSigningCore.sign` doc).

Ordering:

- **Parse before release, release before reply** (DECISION-12 §3.9, `docs/decisions/DECISION-12.md`). #5 and the output are released in `SyncSigningCore.sign`'s `finally`. #3, then #1, are released in `withDerivedKey`'s scope. Only then does `EngineRequestHandler.handle` return the reply for the loop to post.
- **The same releases happen on every error path.** If the deadline passes while signing runs, the result is then dropped and never posted (`WorkerLoop._drainOne`).
- **No error carries key bytes** (`SyncSigningCore.sign` doc, "never puts key bytes in an error").

If the process is killed mid-operation, #1–#6 stay as they were, because a native finalizer runs only in a live process (PRD §11.1).

## Where the executor runs in this version

The executor is `InProcessTransport` (`transport.dart`), the default that `startSession` sets up (`session.dart`). It runs `WorkerLoop` and `EngineRequestHandler` on the calling isolate's event loop, asynchronously in both directions. Every copy listed on this page therefore lives in the application's own isolate.

The sender's copy and the executor's copy of entropy are kept separate by `executorCopy`, as an isolate boundary would keep them. Phase 2 (T2.1) replaces the transport with a worker isolate that runs the same loop over the same protocol (`WorkerTransport` doc). That transport does not exist yet.

## Dart-heap copies of secrets

| Copy | Where | Overwritten |
|---|---|---|
| UTF-8 list of a secret string | `secretString` | Yes |
| Request's entropy copy | `ImportWallet.entropy` constructor | Yes, by the sender (see above) |
| Executor's entropy copy | `executorCopy` | Yes, by the executor (see above) |
| `String` returned by `readSecretString` (an exported mnemonic, suggested words) | `HDWallet.exportMnemonic`, `WalletEngine.suggestMnemonicWords` | No: a Dart `String` |

No copy of the private key is made on the Dart heap on the signing path. The key reaches the signing core as a view over native memory (table above).

## Known gaps in the current code

The bindings' general-purpose wrappers do not overwrite what they stage or return:

| Member | What it stages or returns | Overwritten? |
|---|---|---|
| `TWStringHandle.fromString` | A Dart list (`utf8.encode`) and a `calloc` buffer | Neither |
| `TWDataHandle.fromBytes` | A `calloc` buffer. The input is the caller's list | No |
| `TWStringHandle.toDartString` | A Dart list copy before decoding, then the returned `String` | No |
| `TWDataHandle.copyBytes` | The returned Dart list | No |
| `ResourceScope.data` / `ResourceScope.string`, `withTWData` / `withTWString` | Go through `fromBytes` / `fromString` | No |

So a secret that reaches native code through these, instead of through `secretString`, `secretData` or `secretDataFromParts`, leaves staging copies behind.

Current callers in `packages/wallet_core_flutter/lib/`. None of them carries a mnemonic, passphrase, entropy or private key:

| File | Symbol | Call | Value |
|---|---|---|---|
| `packages/wallet_core_flutter/lib/src/engine/engine.dart` | `_string` | `ResourceScope.string` | Helper used by the next two rows |
| `packages/wallet_core_flutter/lib/src/engine/engine.dart` | `WalletEngine.isValidAddress` | `_string` | Address; testnet HRP |
| `packages/wallet_core_flutter/lib/src/engine/engine.dart` | `WalletEngine.checkRecipient` | `_string`, `TWStringHandle.toDartString` | Recipient address; upstream's rendering of it |
| `packages/wallet_core_flutter/lib/src/engine/hd_wallet.dart` | `HDWallet.deriveAccount` | `ResourceScope.string`, `TWDataHandle.copyBytes`, `TWStringHandle.toDartString` | Derivation path; public key; address |
| `packages/wallet_core_flutter/lib/src/engine/hd_wallet.dart` | `withDerivedKey` | `ResourceScope.string` | Derivation path |
| `packages/wallet_core_flutter/lib/src/signing/signing_core.dart` | `SyncSigningCore.sign` | `TWDataHandle.copyBytes` | Upstream's signing output (no key, see above) |

The only other callers are the wrappers themselves: `ResourceScope`'s `data`/`string`, `withTWData` and `withTWString`. Code written against `advanced.dart` can pass anything to these wrappers. That is outside this contract.

## What this SDK cannot overwrite

- Dart `String`s: an imported mnemonic, a passphrase, an exported mnemonic, suggested words.
- Copies the caller made, and platform keyboard or clipboard buffers.
- Copies the Dart garbage collector made while moving objects.
- Upstream's internal copies: those marked "no one" or "not verified" above, and any copy not traced here.
- Memory beyond a native buffer's current size, and buffers upstream reallocated.
- Memory swapped to disk or captured in a crash dump, and anything left behind when the process is killed.

## The leak tracker

`LeakTracker` (`packages/wallet_core_flutter_bindings/lib/src/memory/leak_tracker.dart`) reports handles the garbage collector took before anyone disposed them. Each record holds an id, a type name and the allocation stack trace. It never holds contents, pointers or lengths (`LeakRecord`). The report is a lower bound: a report with no leaks does not prove there are none (`LeakTracker` doc).

It is constructed only inside an `assert` in `LeakTracker.maybeCreate`. In a release build, with assertions disabled, it is never constructed, and the executor uses `NoopResourceObserver` (`EngineRequestHandler._init`).

This page does not claim that the compiler removes the class from release builds:

- The `LeakTracker` doc assigns the release-mode proof to T1.17.
- Code outside the assert still names the type: `observer is LeakTracker` in `EngineRequestHandler._shutdown` and in `debugLeakReportOf` (`packages/wallet_core_flutter/lib/src/session/testing.dart`).

## Not verified

- **Rust `SigningInput` decode:** whether its `private_key` field borrows the input bytes or copies them (row 7).
- **`k256` `SigningKey`:** whether the external crate behind the Rust `PrivateKey` overwrites its scalar on drop (row 8). The crate is not in this repository.
- **Deeper upstream derivation:** key derivation below `HDWallet::getKeyByCurve` (trezor-crypto) was not traced.
- **Dart runtime internals:** whether `utf8.encode` and `utf8.decode` allocate intermediate buffers.
- **Release-build tree-shaking of `LeakTracker`:** left to T1.17.
- **Phase 2 transport:** that a worker-isolate transport (T2.1) will honour the `WorkerTransport.send` copy-and-overwrite contract. It is not written yet.
