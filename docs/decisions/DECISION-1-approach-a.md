# DECISION-1 evidence — Approach A as built (T1.12)

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

| | |
|---|---|
| **Question** | PRD §11.4: where is the signing protobuf, with its private key, assembled — in Dart (Approach A), in a thin native adapter (Approach B), or A now and B later behind the same `Signer`? |
| **This document** | Evidence for one side of that question: Approach A as it was built for the EVM family in T1.12a/T1.12b, measured from the code and the host-library tests. Approach B's evidence is T1.13's. |
| **Status** | **Evidence only.** DECISION-1 is the owner's to decide at M0 exit; nothing here decides it. |
| **Pinned upstream** | tag `4.8.0`, commit `d692ac27749d0c615e17c751b70ab4f0aa75c59b`; host library `third_party/wcf-native/macos/arm64_x86_64/libTrustWalletCore.dylib` (artifact set `as_4.8.0_000`, built locally) |
| **Date** | 2026-10-02; revised the same day after two reviews (T1.12 delta 1): the key field is now **prepended**, not appended (§1, §5) |

---

## 1. What Approach A is, as built

PRD §11.4 sketches Approach A as "build the `SigningInput` in Dart, inject `private_key`, serialize, pass to `TWAnySignerSign`, overwrite our own copies". The build keeps that division of labour but changes the injection, and the change is the main finding of this document:

- **The key is never set on a protobuf message.** The family encodes a *key-less* `SigningInput` (it has no parameter that could carry a key). The signing core then **prepends** one length-delimited field — tag of `private_key`, key length, key — to the serialized key-less bytes (`keyedInputParts`). A serialized message is a sequence of fields, so one complete field followed by one complete message is that message with the field set.
- **The precondition, and what enforces it.** The key-less input must be a *complete, well-formed* message of the family's signing-input type with *every key field absent*. `checkKeylessInput` enforces both: its decode rejects bytes that are not one complete message, and its walk rejects a key field at any depth. No caller may skip it — the handler runs it, and the core runs it again.
- **Why prepend (REVIEW B finding 1).** The first build *appended* the field. Appended, the key lands wherever the key-less bytes leave the parser: after bytes that end inside a length-delimited field — a contract call's calldata, say — it is read as that field's payload, and upstream signs a broadcastable transaction carrying the key in its calldata (the reviewer measured this against the Approach B adapter, which shares the technique). The decode in `checkKeylessInput` rejects such bytes, so the path was not exploitable, but only while every caller decodes. Prepended, the key is always a complete field of its own at the start of the message, whatever follows. The decode stays required for the opposite reason: a key field present *after* the prepended one would win (for a singular field the last occurrence is the one parsed), so absence still has to be proved.
- **The keyed input is assembled outside the Dart heap.** The three parts are copied straight into one `calloc` buffer, which becomes a `TWData`; the buffer is overwritten with zeros and freed in a `finally`.
- **The key reaches the core as a view over upstream's own buffer.** The handler derives the key with `TWHDWalletGetKey`, asks `TWPrivateKeyData` for its bytes, and hands the core `TWDataBytes(...).asTypedList(length)` — a `Uint8List` whose storage *is* that `TWData`.

So the "Dart-managed secret copies" row of the PRD §11.4 table — "protobuf message field, serialized bytes, possibly builder intermediates" — does not describe what was built: on this path there is no protobuf message holding the key, no Dart-heap serialized buffer holding it, and no builder intermediate holding it (§2).

### 1.1 File map

| File (`packages/wallet_core_flutter/lib/src/…`) | Role |
|---|---|
| `signing/signer.dart` | Public `Signer` / `LocalSigner` interfaces |
| `signing/local_signer.dart` | `SessionSigner`, the session-backed `LocalSigner` at `WalletCore.signer`: snapshots the locator set, runs the pre-submission checks, sends `Sign`, puts the caller's locators back on the result |
| `signing/key_locator.dart`, `signing/sign_result.dart`, `requests/` | Public value types: locators, sealed results, key-less requests |
| `worker/protocol.dart` | `Sign` (request + `LocatorSpec`s) and `Signed` (result); no key crosses |
| `worker/handler.dart` | `EngineRequestHandler._sign` and `_resolveKeys`: the executor's order of checks, the key's derivation and release, the `SigningCore` seam |
| `engine/hd_wallet.dart` | `withDerivedKey`: `TWHDWalletGetKey` → `TWPrivateKeyData` → view → `finally` release |
| `engine/engine.dart` | `checkRecipient`: upstream's address validation plus the EIP-55 comparison |
| `families/family.dart`, `families/families.dart`, `families/evm/` | Family boundary; EVM key-less encoder, output parser, reviewed key-field list |
| `signing/key_field_check.dart` | The key-field check on key-less bytes |
| `signing/signing_core.dart` | `SigningCore` (the DECISION-1 seam), `SyncSigningCore` (Approach A): check, prepend, sign, parse, release; `keyedInputParts` |
| `errors/boundary.dart` | `NativeResultError` / `readNative`: a null or out-of-range value from upstream becomes a typed error of the one operation (DECISION-12 §3.10), on the signing path as `SigningError` |
| `engine/secret_buffers.dart` | `secretDataFromParts`: the one Dart-allocated buffer that holds the key |

## 2. The key, copy by copy, during one signing operation

Counted from the code, for one `wc.signer.sign(request, {KeyLocator.hdPath(...)})` on the EVM path.

**Copies of the key on the Dart heap: 0.**
**Dart-allocated native buffers holding the key: 1.**
**Native objects holding the key that this SDK causes to exist: 3.**

| # | Where the key is | Created by | Lifetime | What becomes of it |
|---|---|---|---|---|
| 1 | Upstream `TWPrivateKey` (a C++ `PrivateKey`) | `TWHDWalletGetKey`, in `withDerivedKey` | From derivation until `withDerivedKey`'s `finally`, after the core has parsed upstream's output | `TWPrivateKeyDelete`. At the pinned commit `~PrivateKey() { cleanup(); }` and `cleanup()` is `memzero(bytes)` (`src/PrivateKey.h:93`, `src/PrivateKey.cpp:399–400`) — read from the source, not observed at run time |
| 2 | Upstream `TWData` holding the key's bytes | `TWPrivateKeyData` (which is `TWDataCreateWithBytes(pk->impl.bytes…)`) | Same as #1; released just before it | `TWDataDelete`, which overwrites the buffer with zeros before freeing it (PRD §11.1, verified) |
| — | A `Uint8List` **view** over #2's buffer | `TWDataBytes(...).asTypedList(length)` | Passed to the core for one call; dangling once #2 is released, and never retained | Not a copy: no bytes are on the Dart heap. Nothing to overwrite |
| 3 | `calloc` staging buffer: tag-and-length ‖ key ‖ key-less input | `secretDataFromParts`, inside `SyncSigningCore.sign` | Microseconds: allocated, filled, copied by `TWDataCreateWithBytes`, then released — before `TWAnySignerSign` is called | **Overwritten with zeros by this SDK and freed**, in a `finally`, whether or not `TWDataCreateWithBytes` succeeded |
| 4 | Upstream `TWData`: the keyed signing input | `TWDataCreateWithBytes`, from #3 | From injection until `SyncSigningCore.sign`'s `finally`, after the output was parsed | `TWDataDelete` (overwrites with zeros) |

The tag-and-length header holds the key's *length*, not its bytes. The key-less input, the decoded key-less message the key-field check walks, the request, the locators and the reply hold no key.

**Order** (handler `_sign`, then core `sign`): resolve → path → recipient → encode → key-field check → derive (#1, #2, view) → stage (#3) → keyed `TWData` (#4) → free #3 → `TWAnySignerSign` → copy and parse the output → release #4 and the output → return to the handler → release #2, #1 → return the reply. Parse before release, release before reply (DECISION-12 §3.9). If the operation's deadline passed while it ran, the executor then drops the parsed result unposted and posts a key-less `Failed(OperationTimeoutError)` instead (DECISION-12 §3.9); nothing about the key's lifetime changes.

### 2.1 What cannot be overwritten by this SDK

- **Copies upstream makes while signing.** `TWAnySignerSign` passes the input by reference into `TW::anyCoinSign`, which hands it to upstream's Rust EVM signer; whatever that path copies, decodes, or derives (its own `Data`, its protobuf parse, its private-key value) is upstream's to wipe or not. Not reachable from Dart, not verified here.
- **Copies upstream makes while deriving.** `TWHDWalletGetKey` derives through trezor-crypto's HD node; its intermediates are upstream's.
- **The wallet's seed.** It lives in the `TWHDWallet` for as long as the wallet is open, not per operation; `Wallet.close()` and `shutdown()` release it.
- **A process killed mid-operation.** #1–#4 stay as they were. A native finalizer runs only in a live process.
- **Anything the caller put on the Dart heap.** The mnemonic a caller imported is a `String` (PRD §11.3).

These are limits, stated as such; this document makes no claim about upstream's internal handling beyond the two lines of source cited in the table.

## 3. Native calls involved

`TWStringCreateWithUTF8Bytes` (the path; the recipient), `TWAnyAddressIsValid` (recipient), `TWAnyAddressCreateWithString` + `TWAnyAddressDescription` + `TWStringSize` + `TWStringUTF8Bytes` + `TWAnyAddressDelete` (EIP-55 comparison, mixed-case recipients only: the rendering is read back as a string), `TWHDWalletGetKey`, `TWPrivateKeyData`, `TWDataSize`, `TWDataBytes`, `TWDataCreateWithBytes`, `TWAnySignerSign`, `TWDataDelete` (×3: output, keyed input, key bytes), `TWPrivateKeyDelete`, `TWStringDelete`. No new symbol: `TWPrivateKeyDelete` was already one of the engine's native-finalizer callbacks (`engine/handles.dart`), so `ffigen.yaml` and the generated bindings are unchanged.

## 4. Review scope

What a reviewer must read to check every claim in §2 (line numbers at the time of writing, `packages/wallet_core_flutter/lib/src/`):

| File | Lines | What |
|---|---|---|
| `worker/handler.dart` | 297–456 (160) | `_sign`, `_resolveKeys`: order of checks, the one derivation, the core call |
| `engine/hd_wallet.dart` | 296–369 (74) | `withDerivedKey`: derivation, the view, the `finally` |
| `signing/signing_core.dart` | 84–249 (166) | `SyncSigningCore.sign`, `keyedInputParts`, `lengthDelimitedHeader` |
| `engine/secret_buffers.dart` | 100–141 (42) | `secretDataFromParts` |
| `signing/key_field_check.dart` | 19–117 (99) | the key-field check, and its refusal of groups and unknown fields |
| `families/family.dart` | 94–146 (53) | `KeyFieldList.presentIn` |
| `families/evm/evm_family.dart` | 49–189 (141) | encoder (no key parameter), parser, `injectionField` |
| `families/evm/key_fields.dart` | all (30) | the reviewed list |
| `engine/handles.dart` | 59–85 (27) | `PrivateKeyHandle` |
| `errors/boundary.dart` | 21–61 (41) | `NativeResultError`, `readNative` |

833 lines of Dart, doc comments included, plus the bindings' `TWDataHandle` and `ResourceScope` (`wallet_core_flutter_bindings/lib/src/memory/`), which earlier tasks reviewed. No C or C++ of this project's is in scope. The session side (`signing/local_signer.dart`, `session/session.dart`) never touches a key and is out of scope for the key's lifetime.

## 5. Generalizing: Bitcoin's repeated field, Solana's three fields

`key_fields.json` (generated, `packages/wallet_core_flutter_bindings/lib/src/generated/proto/`) at the pinned commit:

| Message | Field | Number | Repeated | Where |
|---|---|---|---|---|
| `TW.Ethereum.Proto.SigningInput` | `private_key` | 9 | no | top level |
| `TW.Ethereum.Proto.MessageSigningInput` | `private_key` | 1 | no | top level (message signing, T2.7) |
| `TW.Bitcoin.Proto.SigningInput` | `private_key` | 6 | **yes** | top level |
| `TW.BitcoinV2.Proto.SigningInput` | `private_keys` | 1 | **yes** | nested: `Bitcoin.SigningInput.signing_v2 = 21` |
| `TW.Solana.Proto.SigningInput` | `private_key` | 1 | no | top level |
| `TW.Solana.Proto.SigningInput` | `fee_payer_private_key` | 17 | no | top level |
| `TW.Solana.Proto.CreateNonceAccount` | `nonce_account_private_key` | 3 | no | nested: `SigningInput.create_nonce_account = 13`, a `oneof` arm |
| `TW.Solana.Proto.MessageSigningInput` | `private_key` | 1 | no | top level (message signing) |

What each case requires of `injectionField` and the prepend technique:

- **A second top-level singular field (Solana `fee_payer_private_key`).** Works as is: one more prepended field. `injectionField(KeyRole.feePayer)` returns entry 17, and `SigningCore.sign` must take one key per role instead of one key. That is an interface change to the internal seam, not to the public API. **Measured** for a top-level Solana field (table below): prepending `private_key = 1` to otherwise complete bytes signs identically — as appending did.
- **A repeated top-level field (Bitcoin `private_key = 6`).** By the protobuf encoding rules every occurrence of a non-packed repeated field adds an element wherever it occurs, so prepending N fields gives N keys; upstream matches keys to inputs by script, so order is irrelevant (DECISION-13 §3.2). `injectionField(KeyRole.input(n))` would map every input role to the same entry, and the core prepends one field per distinct key. **Not measured here** — needs a UTXO vector (T2.5).
- **A nested field (Solana `nonce_account_private_key`; BitcoinV2's `private_keys` inside `signing_v2`).** **Neither appending nor prepending a second occurrence of the enclosing sub-message works against upstream.** Measured on the host library with upstream's own Rust test input (`rust/tw_tests/tests/chains/solana/solana_sign.rs`, `test_solana_sign_create_nonce_account`):

  | Input to `TWAnySignerSign` (Solana) | Result |
  |---|---|
  | Both keys set on the message, serialized | `error = 0`, `encoded` = upstream test's expected value |
  | Nested key set on the message, only `private_key = 1` prepended | `error = 0`, equal to the first row |
  | Nested key set on the message, only `private_key = 1` appended | `error = 0`, equal to the first row |
  | Key-less bytes + appended `private_key` + appended `create_nonce_account = 13 { nonce_account_private_key = 3 }` | `error = 0`, **a different `encoded`** — silently wrong |
  | Key-less bytes + appended `private_key` + appended **whole** `create_nonce_account` (key-less fields re-emitted, plus the key) | `error = 0`, equal to the first row |
  | Prepended `private_key` + prepended `create_nonce_account = 13 { nonce_account_private_key = 3 }` + key-less bytes | `error = 15` (upstream's invalid-private-key code) |
  | Prepended `private_key` + prepended **whole** `create_nonce_account` + key-less bytes | `error = 15` |
  | Dart's protobuf runtime decoding the nested-only variants | merges: `rent` kept, 32-byte key present |

  Upstream's Rust parser *replaces* a sub-message that occurs twice — the last occurrence wins — while Dart's runtime *merges* it. Appended, the key-carrying occurrence comes last and replaces the key-less one: correct only if it re-emits the whole sub-message, and *silently* wrong (rent lost, success reported) if it carries only the key. Prepended, the key-less occurrence comes last and replaces the key-carrying one, so the nested key is lost; upstream fails loudly (error 15) rather than silently, which is the safer failure, but it does not sign. The key-field check, which decodes with Dart's merging runtime, cannot see either problem.

  So for a nested key field the injector cannot add a second occurrence at all: it must **splice** — remove the enclosing sub-message's occurrence from the key-less bytes and emit one occurrence that carries both the key-less fields and the key, still assembled only in the native staging buffer. `injectionField` therefore needs a *path* (enclosing field numbers) rather than one `KeyFieldEntry`, and the core needs to split the key-less input by top-level field. DECISION-13 §5 keeps the nonce-account key unexposed in v1, so this is not on the v1 path; it is on Approach B's path too, since B injects bytes the same way.

  The measurements were throwaway tests against the host library, not committed (they are not vectors); the appended rows were measured before the switch to prepend, the prepended rows after it, with the same inputs. To repeat them: build the inputs with `Solana.pb.dart`, `lengthDelimitedHeader`, and `secretDataFromParts`, and compare `SigningOutput.error` and `encoded`.

## 6. SignJSON as an alternative path

At the pinned commit `TWAnySignerSignJSON(json, key, coin)` takes the key as a separate `TWData`; upstream parses the JSON into the signing input, sets `private_key` from the key, serializes, and signs (`src/rust/RustCoinEntry.h:42–60`). T1.14 measured coverage: **106 of 167 coins** report `TWAnySignerSupportsJSON`; **Ethereum and Solana yes, Bitcoin no**.

Why it does not replace the path above:

- **It drops what the typed result needs.** Ethereum's JSON entry returns `hex(output.encoded())` only (`src/Ethereum/Entry.cpp`): no `v`, `r`, `s`, pre-hash, and no error code — a failure is an empty string. `EvmSignResult` and `SigningError(upstreamCode, message)` could not be produced from it.
- **It fills one top-level field.** `set_private_key` only: no fee payer, no nested key, no repeated keys. Bitcoin is not covered at all.
- **The key-less input becomes JSON text** (`toProto3Json`), a second encoding of every request that the binary path does not need.
- **Its gain over the build is small.** It would remove buffer #3 and #4 of §2 from this SDK's side, but the key still exists in #1 and #2, and upstream then makes its own keyed, serialized `std::string` that nothing wipes.

It could serve as a cross-check in tests (sign the same request both ways, compare `encoded`) for coins where it is supported.

## 7. Test evidence

New tests: `test/signing/sign_handler_native_test.dart` (15: every resolution and validation failure is typed, derives no key — `EngineRequestHandler.keysDerived` stays 0 — and never reaches a recording core; a valid request derives exactly one 32-byte key and leaves only the wallet live), `test/signing/signer_native_test.dart` (5: the public flow import → derive → request → sign equals the engine-level core's result for the same path, `usedKeys` is the locator set; closed wallet → `ClosedError`; second-session reference → `foreignRef`; wrong coin and bad EIP-55 checksum → typed errors before derivation; 20 signs leave zero undisposed), `test/signing/signer_session_test.dart` (11: what crosses in `Sign`, the queue bound and deadline applied to signing, checks before submission), `test/signing/sign_protocol_test.dart` (5). The byte-for-byte vector `ethereum-sign-eip1559-1` stays covered at core level by `test/signing/signing_core_native_test.dart` (12).

Added in the delta-1 revision:

- `signing_core_native_test.dart` +3: the keyed bytes upstream receives are tag ‖ key ‖ key-less bytes, the vector still byte for byte (fails on the appending build); a key-less input that ends inside a length-delimited field is rejected before any staging buffer or `TWData` exists; and, with the check bypassed by building the bytes directly from `keyedInputParts`, the first field on the wire is `private_key` holding the key, the appended layout would have decoded with the key as calldata, and upstream's output for the prepended bytes does not contain the key.
- `key_identity_native_test.dart` (2): `withDerivedKey` at the `ethereum-address-n/a-1` path yields the vector's public key and address, computed straight through the bindings; the public flow's signature is reproduced with a key obtained through a different upstream entry point (`TWHDWalletGetDerivedKey`), and `TWPublicKeyRecover` recovers the vector's public key from `r ‖ s ‖ v` and the reported pre-hash.
- `test/engine/soft_native_failure_native_test.dart` (3): `TWPrivateKeyData` returning null while signing is a `SigningError` with the key still released, and the session stays ready (DECISION-12 §3.10).

Gate tails, 2026-10-02 (delta 1):

```
$ melos run analyze
[wallet_core_flutter]: No issues found!
     └> SUCCESS

$ melos run format:check
Formatted 390 files (0 changed)

$ melos run test
[wallet_core_flutter]: +265: All tests passed!
[wallet_core_flutter_bindings]: +64: All tests passed!
SUCCESS

$ melos run test:native
00:00 +42: All tests passed!        (wallet_core_flutter_bindings, --tags native)
00:02 +74: All tests passed!        (wallet_core_flutter, --tags native)

$ WCF_NATIVE_REQUIRED=1 flutter test --tags native   (wallet_core_flutter, three runs)
run 1: 00:02 +74: All tests passed!
run 2: 00:02 +74: All tests passed!
run 3: 00:02 +74: All tests passed!

$ melos run inventory:check
functions: {in_headers: 466, in_generated: 466, missing: 0}
packages/wallet_core_flutter_bindings/lib/src/generated/inventory.json: up to date
```

## 8. Open items for DECISION-1

1. **Key-length checking.** Upstream signs with a 31-byte key at the pinned tag (T1.12a's core test); it rejects empty, 33-, 64-byte and all-zero keys with a typed `SigningError`. The core does not judge key lengths, and on this path every key comes from `TWHDWalletGetKey`, which the handler test shows is 32 bytes. Whether the core should reject a non-32-byte key for secp256k1/ed25519 families — relevant once imported keys exist (`KeyLocator.imported`, T3.4) — is open.
2. **`Signer.plan`.** Omitted: no `UtxoTransactionRequest` exists yet (T2.5). `signing.md` §1 declares it; the interface gains it with the UTXO family, which is additive.
3. **`nonceAccount` role.** DECISION-13 §4.2 lists `nonceAccount` among the roles; `signing.md` §2 and the built `KeyRole` have `primary`, `feePayer`, `input(n)` only. Consistent with DECISION-13 §5 keeping the nonce-account key unexposed in v1, but the two documents disagree on the role list; §5 above shows what supporting it would require.
4. **Multi-key injection.** `SigningCore.sign` takes one key for `KeyRole.primary`; Solana's fee payer and Bitcoin's inputs need one key per role. An internal interface change, for whichever approach is chosen.
5. **Nested key fields** need the splice of §5 — one occurrence of the enclosing sub-message, carrying the key — for A and B alike.
6. **`advanced.dart` raw protobuf signing** (`RawSigningInput`, signing.md §6) does not exist yet; not added here. When it is written, its caller-supplied bytes must go through `checkKeylessInput` like every other input (§1).
7. **SignJSON as a test cross-check** (§6), if wanted.
8. **Approach B's adapter** shares the injection technique and must prepend too, with the same precondition (REVIEW B finding 1).
