# DECISION-13 — Signing model

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

| | |
|---|---|
| **Question** | How does a caller say *what* to sign and *with which keys*, when upstream's signing inputs embed the keys, one chain needs several of them, and every chain returns a different result shape? |
| **Governing PRD sections** | §10.2 (requests, signers, errors), §11.4 (family boundary, Approach A/B), §13.1 (variants), §16 S5 (validation), §22 DECISION-13, §25 (signing model, A-03/A-05/A-13) |
| **Evidence** | `docs/decisions/evidence/prefetch-2026-09-07/upstream-src/proto/{Bitcoin,BitcoinV2,Solana,Ethereum,Common}.proto` and `.../TWTransactionCompiler.h`, at commit `d692ac27749d0c615e17c751b70ab4f0aa75c59b` (tag 4.8.0) |
| **Interface sketch** | [`docs/architecture/signing.md`](../architecture/signing.md) |
| **Recommendation** | **`Signer.sign(request, Set<KeyLocator>)` returning a sealed `SignResult`**, in the shape of §4 |
| **Status** | **Recorded 2026-09-07** - recommendation adopted as written, with the T0.R2/T0.R4 fixes. See the Decision section. Recorded by the orchestrator under the owner's standing authorization; subject to their ratification. |

---

## 1. Context

PRD §10.2 states the rule in one line: *a request is "what to sign"; a signer decides "with what"*. The reason it has to be stated is that upstream's protobufs do not separate the two — the private key is a field of the signing input, so anything that builds the input in Dart has, at that moment, both. The design question is where the seam goes, and it has to survive three upstream facts that are not negotiable:

1. **One chain, several keys.** Bitcoin's `SigningInput` takes a *repeated* key list, and nothing in the input associates a key with an input; upstream matches keys to UTXOs by script.
2. **Different chains, differently named keys.** Solana has three distinct key fields in two different messages. There is no field-name convention and no marker bit that says "this is a secret".
3. **Different chains, different results.** Bitcoin returns bytes plus a transaction-id *string*; Bitcoin V2 returns bytes plus a transaction-id *bytes*; Solana returns one *string* whose encoding is chosen by the input; Ethereum returns bytes plus `v`/`r`/`s`. There is no useful common result type beyond "it worked or it did not".

## 2. Options

### Option A — the signer resolves a *set* of key locators (recommended)

`Signer.sign(request, Set<KeyLocator>)`. The request is key-less and pure data; the locator set names keys without carrying them; the signer resolves the set inside the isolate that owns the wallet, injects, calls upstream, and parses.

### Option B — one account per request

`Signer.sign(request, Account)` — the shape the PRD's v1.0 example used and the shape most single-chain SDKs have.

**Rejected**, and the rejection is forced by the evidence rather than argued: `Bitcoin.SigningInput` field 6 is `repeated bytes private_key`, and the M1 acceptance vector is a two-input spend from two derivation paths (PRD §13.3, §18 M1). One `Account` cannot express two derivation paths. Solana's optional `fee_payer_private_key` (field 17) is a second, independent counter-example on a chain that is otherwise single-key. Option B would need an escape hatch on its first non-trivial Bitcoin transaction, and an escape hatch that appears in v1.0 is a v2.0 breaking change.

A convenience overload — `signer.signWithKey(request, locator)`, sugar for a single-element locator set — is kept, because for EVM and Solana transfers the one-key case is the common case. It takes a locator rather than an `Account`, for the reason given in §4.1. The sugar is defined *in terms of* the set, never beside it.

## 3. Evidence

Field names and numbers below are quoted from the pinned protos. Every path is `docs/decisions/evidence/prefetch-2026-09-07/upstream-src/proto/`.

### 3.1 Where the keys are

| Proto | Message | Field | Number | Type |
|---|---|---|---|---|
| `Bitcoin.proto` | `SigningInput` | `private_key` | **6** | **`repeated bytes`** — comment: *"The available secret private key or keys required for signing (32 bytes each)"* |
| `BitcoinV2.proto` | `SigningInput` | `private_keys` | **1** | **`repeated bytes`** — *"Only required if the `sign` method is called"*; the sibling `public_keys` (2) is *"Only required if the `plan`, `preImageHash` methods are called"* |
| `Solana.proto` | `SigningInput` | `private_key` | **1** | `bytes` |
| `Solana.proto` | `SigningInput` | `fee_payer_private_key` | **17** | `bytes` — *"Optional external fee payer private key. support: TokenTransfer, CreateAndTransferToken"* |
| `Solana.proto` | `CreateNonceAccount` | `nonce_account_private_key` | **3** | `bytes` — a key field in a **nested message**, not in `SigningInput` |
| `Ethereum.proto` | `SigningInput` | `private_key` | **9** | `bytes` |
| `Ethereum.proto` | `MessageSigningInput` | `private_key` | **1** | `bytes` |

Three consequences. (a) A key-field check cannot be a top-level field scan: Solana's third key hides one message down, inside a `oneof` arm. (b) There is no naming convention to rely on — `private_key`, `private_keys`, `fee_payer_private_key`, `nonce_account_private_key`. (c) Field *numbers* differ across chains for the same concept (1, 6, 9), so a "append field N" shortcut is per-family by construction, exactly as PRD §11.4 says.

### 3.2 How Bitcoin associates a key with an input — it does not

`Bitcoin.proto`'s `UnspentTransaction` has `out_point` (1), `script` (2), `amount` (3), `variant` (4), `spendingScript` (5). **There is no key field, no key index, and no key reference.** The key list is flat and unordered relative to the inputs; upstream matches a key to a UTXO through the script (the pubkey hash in the `script`). This is why the per-input `KeyLocator` in `UtxoTransactionRequest` is *our* construct: it exists so the SDK knows which keys to derive, and it is flattened and de-duplicated into upstream's `repeated bytes private_key` at injection time. It is not passed through to upstream, because upstream has nowhere to put it.

### 3.3 Why `SignResult` must be sealed and per-family

| Proto | `SigningOutput` fields |
|---|---|
| `Bitcoin.proto` | `Transaction transaction = 1`, **`bytes encoded = 2`**, **`string transaction_id = 3`**, `Common.Proto.SigningError error = 4`, `string error_message = 5`, `BitcoinV2.Proto.SigningOutput signing_result_v2 = 7` |
| `BitcoinV2.proto` | `error = 1`, `error_message = 2`, **`bytes encoded = 4`**, **`bytes txid = 5`**, `uint64 vsize = 6`, `uint64 weight = 7`, `int64 fee = 8`, `Psbt psbt = 9`, `oneof transaction { bitcoin = 15, zcash = 16, decred = 17 }` |
| `Solana.proto` | **`string encoded = 1`**, `error = 2`, `error_message = 3`, `string unsigned_tx = 4`, `repeated PubkeySignature signatures = 5` |
| `Ethereum.proto` | **`bytes encoded = 1`**, `bytes v = 2`, `bytes r = 3`, `bytes s = 4`, `bytes data = 5`, `error = 6`, `error_message = 7`, `bytes pre_hash = 8` |
| `Ethereum.proto` | `MessageSigningOutput`: `string signature = 1`, `error = 2`, `error_message = 3` |

`encoded` is `bytes` on Bitcoin and Ethereum and `string` on Solana; the transaction id is `string` in Bitcoin V1 and `bytes` in V2 and absent entirely from Solana and Ethereum. Only `error` + `error_message` are universal — and their field *numbers* differ (4/5, 1/2, 2/3, 6/7), so even the error path is per-family parsing.

**A correction the PRD needs.** PRD §10.2 says Solana returns "a base64 string". `Solana.proto` declares `enum Encoding { Base58 = 0; Base64 = 1; }` and `SigningInput.tx_encoding = 21`, so the **default is Base58** and the encoding is an input choice. `SolanaSignResult` must therefore carry the string *and* the encoding that produced it; calling it "base64" in the type or the docs would be wrong at the default setting.

### 3.4 Common error surface

`Common.proto` defines `enum SigningError` with `OK = 0` and 20-odd codes, several of which are directly about keys: `Error_missing_private_key = 5` (*"One required key is missing (too few or wrong keys are provided)"*) and `Error_invalid_private_key = 15`. These are the codes a wrong locator set produces if we let it reach native — which is the argument for resolving and counting keys in Dart first, so the caller gets `KeyResolutionError` with a name rather than `SigningError(5)`.

### 3.5 The external-signature path exists in the C API

`TWTransactionCompiler.h` declares `TWTransactionCompilerPreImageHashes(coin, txInputData)` and `TWTransactionCompilerCompileWithSignatures(coin, txInputData, signatures, publicKeys)`, with the doc comment *"The signatures must match the hashes returned by TWTransactionCompilerPreImageHashes, in the same order. The publicKeyHash attached to the hashes enable identifying the private key needed for signing the hash."* Per-coin availability is **[UNVERIFIED]** (T2.9 probes it). This is the mechanism a future `ExternalSigner` uses, and it takes the *same key-less input bytes* the local signer builds — which is the structural reason the family boundary of §4.4 is worth having independently of DECISION-1.

## 4. Recommendation

Signatures in [`docs/architecture/signing.md`](../architecture/signing.md).

### 4.1 `Signer.sign(request, Set<KeyLocator>)`

```
Future<SignResult> sign(TransactionRequest request, Set<KeyLocator> keys)
Future<SignResult> signWithKey(TransactionRequest request, KeyLocator key)   // sugar for a one-element set
Future<SignResult> signMessage(MessageRequest request, Set<KeyLocator> keys)
Future<UtxoPlan>   plan(UtxoTransactionRequest request)          // UTXO chains only, no keys
```

A `Set`, not a `List`: order is meaningless to upstream (§3.2) and a set makes duplicate locators harmless. The signer resolves it, and resolution is a checked step with its own error:

- Every locator in the set must be usable by *this* signer and *this* session, or `KeyResolutionError`.
- The family declares how many keys it needs and for which roles; a set that leaves a required role unfilled fails with `KeyResolutionError(reason: missingRole)` **before** any derivation, and a set with locators no role consumes fails with `KeyResolutionError(reason: unusedLocator)` — an unused locator usually means the caller believed a different key would be used, which is precisely the mistake worth failing on.
- `SignResult.usedKeys` reports the locators actually consumed, so a test or an audit log can assert what signed without ever seeing a key.

**The single-key sugar takes a `KeyLocator`, not an `Account`.** An earlier draft of this record offered an overload taking an `Account` in place of the key, and it cannot exist: an `Account` is a descriptor of coin, network, address style, derivation path, address, and public key, and it deliberately carries **no** `WalletRef` (DECISION-11 §4.6). There is nothing in it from which an `HdKeyLocator` could be built, and the two ways to make one work are both wrong — giving `Account` a wallet reference would make a descriptor into a half-capability and break its "safe to persist, grants nothing" property, and having the signer guess the wallet would reintroduce exactly the implicit key selection §6 Q5 rules out. `signWithKey(request, key)` keeps the convenience (one argument instead of a set literal) with none of that: the caller still names the key, and the sugar is defined as `sign(request, {key})`.

### 4.2 `KeyLocator` shapes

A sealed class with three members, **all three declared in 1.0**:

| Member | Fields | Meaning |
|---|---|---|
| `HdKeyLocator` | `walletRef`, `coin`, `derivationPath` (explicit, full BIP-32 string), optional `role` | derive from a session-owned HD wallet |
| `ImportedKeyLocator` | `keyRef`, optional `role` | a key imported from an encrypted keystore or (advanced only) raw bytes |
| `ExternalKeyLocator` | `deviceId`, `keyPath`/`publicKey`, optional `role` | **reserved.** Every 1.0 signer rejects it with `UnsupportedOperationError(coin, 'external-signer')` |

`ExternalKeyLocator` is declared now and rejected at runtime *on purpose*: adding a member to a sealed class later would break every exhaustive `switch` a consumer wrote, which is a breaking change for a feature we already know is coming (PRD §10.2, §18 M5). Declaring it in 1.0 costs one unreachable branch and buys a non-breaking future.

`role` is a small value (`primary`, `feePayer`, `nonceAccount`, `input(n)`) that lets a caller be explicit when a family has more than one slot. When omitted, the family assigns roles positionally for single-role families and requires them for multi-role ones (Solana with a fee payer).

### 4.3 How a UTXO request names the key per input

`UtxoTransactionRequest.inputs` is a list of `UtxoInput(outPoint, amount, script, addressStyle, keyLocator)`. The locator lives *on the input*, because that is where the caller knows it: the caller chose that UTXO because it belongs to a particular derivation path. At signing:

1. The family encoder builds the key-less input from the outpoints, scripts, and amounts (no locator crosses into upstream's message — §3.2).
2. The signer collects `{input.keyLocator for every selected input}`, **de-duplicates** (two inputs from one path need one key), and resolves each once.
3. The resolved keys are injected into `private_key` (field 6) as an unordered list.

Two inputs on one path therefore derive one key, not two — measurable and testable, and it matters for TM-01's residence-time claim.

### 4.4 The family boundary (PRD §11.4), stated as an interface

Every family implements exactly two functions and nothing else touches upstream's message shapes:

```
Uint8List encodeKeylessInput(TransactionRequest request)   // never receives key bytes
SignResult parseSigningOutput(Uint8List bytes, …)          // treats the bytes as untrusted (TM-22)
```

Plus one declaration:

```
KeyFieldList get keyFields    // the reviewed per-family list of key field names
```

The signer is the only component that sees key material. Before injecting, it verifies against `keyFields` that the key-less bytes contain none of those fields; a non-empty match is a bug in the family encoder and fails the operation with `InvalidInputError` before any native call (this is the check T1.12's acceptance criterion exercises with a tampered input).

`parseSigningOutput` reads `error`/`error_message` **first** and maps a non-`OK` code to `SigningError(upstreamCode, message)` without interpreting the rest (TM-22), bounds every field size before copy-out, and rejects an output whose shape does not match the requested family.

### 4.5 v1 policy for multisig, partial signing, and watch-only

| Case | v1 behaviour | Error | Why |
|---|---|---|---|
| **Multisig** | not expressible | `UnsupportedOperationError(coin, 'multisig')` | Bitcoin's redeem-script map (`SigningInput.scripts`, field 7) is the vehicle upstream offers; we ship no request shape for it and no vector, so it is *not generated* in our sense and stays out (PRD §13.1). |
| **Partially signed transactions (PSBT)** | not exposed | `UnsupportedOperationError(coin, 'psbt')` | Upstream *does* support it — `BitcoinV2.SigningInput.psbt` (oneof arm 11) and `SigningOutput.psbt` (9) — so this is a scope choice, not a limitation, and it is listed as such in the v1 feature table (PRD §16 S9). |
| **Watch-only account** | rejected at resolution | `KeyResolutionError(reason: noKeyForAccount)` | An `Account` is a descriptor with a public key and no key (DECISION-11 §4.6); signing needs a locator, and there is none to give. Failure happens in Dart, before native, so upstream's `Error_missing_private_key = 5` never surfaces. |
| **Fee payer / extra signer without a locator** | rejected at resolution | `KeyResolutionError(reason: missingRole)` | Solana's `fee_payer_private_key` is optional to upstream; leaving it empty silently changes who pays. We require an explicit locator or an explicit "no fee payer". |

All four are listed by name in `docs/features_v1.md` (T3.13) as explicit exclusions, per PRD §16 S9.

### 4.6 Sealed `SignResult`

```
sealed class SignResult { Set<KeyLocator> usedKeys; Coin coin; }
  EvmSignResult      : Uint8List encoded, Uint8List v, r, s, Uint8List? preHash
  EvmMessageSignResult: String signature                       // hex, per the proto comment
  UtxoSignResult     : Uint8List encoded, String transactionId, int? vsize, int? weight, int? fee
  SolanaSignResult   : String encoded, SolanaEncoding encoding, String? unsignedTx
```

No common `encoded` accessor on the base class: it would have to be `Object` (bytes on three families, a string on Solana) and would push a cast onto every caller. Sealed + exhaustive `switch` is the ergonomic replacement. `UtxoSignResult.transactionId` is normalised to a lowercase hex `String` across V1 (`string transaction_id`) and V2 (`bytes txid`), with the normalisation documented on the field.

### 4.7 The M1 Bitcoin proof, expressed without key material

The transaction T2.2/T2.5 must prove — two inputs, two derivation paths, no secret in the request:

```dart
final wallet = await wc.wallets.importMnemonic(mnemonic);          // secret enters once, here
final a0 = await wallet.account(Coin.bitcoin, path: "m/84'/0'/0'/0/0");
final a1 = await wallet.account(Coin.bitcoin, path: "m/84'/0'/0'/1/0");

final request = UtxoTransactionRequest(
  coin: Coin.bitcoin,
  toAddress: 'bc1q…',
  amount: 30000,
  feeRatePerByte: 12,
  changeAddress: a0.address,
  inputs: [
    UtxoInput(outPoint: OutPoint(txId: '…', index: 0), amount: 25000,
              script: scriptFor(a0), addressStyle: AddressStyle.segwit,
              keyLocator: KeyLocator.hdPath(wallet.ref, Coin.bitcoin, "m/84'/0'/0'/0/0")),
    UtxoInput(outPoint: OutPoint(txId: '…', index: 1), amount: 20000,
              script: scriptFor(a1), addressStyle: AddressStyle.segwit,
              keyLocator: KeyLocator.hdPath(wallet.ref, Coin.bitcoin, "m/84'/0'/0'/1/0")),
  ],
);

final plan = await wc.signer.plan(request);                        // no keys at all
final result = await wc.signer.sign(request, request.keyLocators);  // the two locators
// result is UtxoSignResult; result.usedKeys has exactly the two locators above
```

Everything crossing the isolate boundary is a plain value: outpoints, amounts, scripts, an address, and two *names* of keys. The two private keys exist only inside the worker, only for the duration of the `Sign` operation, and are disposed before the reply (DECISION-12 §3.9).

## 5. Consequences for tasks

| Task | What changes |
|---|---|
| **T1.4** — protobuf generation | Emits `key_fields.json` from the descriptors, and it must be a **recursive** walk, not a top-level field scan: Solana's `nonce_account_private_key` lives in `CreateNonceAccount`, not in `SigningInput` (§3.1). Acceptance gains that case. |
| **T1.12** — EVM path | `Signer.sign(request, keys)` from the start, with the single-locator sugar; the key-field check runs against the generated list before injection; `EvmSignResult` carries `v`/`r`/`s` and `preHash` because the proto has them. |
| **T2.0** — signing model in code | Implements §4.1–§4.6 exactly; `ExternalKeyLocator` is declared and rejected; `role` is introduced now, not retrofitted; the Phase 1 EVM path is refactored onto the sealed hierarchy without changing its vector result. |
| **T2.5** — UTXO family | Per-input locators, de-duplication before derivation, `plan` without keys, `UtxoSignResult.transactionId` normalised across V1/V2 shapes. Non-P2WPKH styles throw `UnsupportedOperationError` until a vector exists. |
| **T2.6** — Solana | `SolanaSignResult` carries the encoding (§3.3); a request needing a fee payer requires an explicit `feePayer` role locator or fails with `KeyResolutionError`; the `nonce_account_private_key` path stays unexposed in v1. |
| **T2.7** — EVM message signing | `EvmMessageSignResult.signature` is a hex `String` per the proto comment, not bytes. |
| **T2.12** — hostile-input suite | Adds: tampered key-less bytes containing each family's key fields; a locator set missing a role; an unused locator; a watch-only account; a `SigningOutput` with `error` set and a plausible `encoded` (must produce `SigningError`, never a result). |
| **T4.1** — API diff | Gains the key-field gate of §6 Q4. |
| **T3.13** — v1 feature table | Lists multisig, PSBT, watch-only, Solana fee payer, and external signers as explicit exclusions with these error names. |
| **T5.7** — threat model v1 | Adds the external-signer section described in §6 Q6. |

## 6. Answers to threat-model questions

### Q4 — Where do the per-family key-field lists live, and what forces re-review?

**Two layers, and the test between them is the mechanism.**

1. **Generated** (`packages/*_bindings/lib/src/generated/proto/key_fields.json`, T1.4): produced by walking the proto descriptors recursively and collecting every field whose name matches a key-like pattern — `private_key`, `private_keys`, `fee_payer_private_key`, `nonce_account_private_key` today. It is regenerated at every pin and is covered by `gen:check`, so it cannot be hand-edited.
2. **Reviewed** (`lib/src/families/<family>/key_fields.dart`, T2.0): a `const KeyFieldList` per family, written by a human, carrying the field names *and the message path they occur in*. A unit test asserts the reviewed list equals the generated set for that family's protos. The reviewed list is what the signer checks against; the generated file is what proves it is complete.

**What forces re-review** — a check added to T4.1's API diff, run on every pin PR before it can merge:

> For every proto in the pinned tag, compute the key-like field set. If it differs from the committed reviewed list for that family — a field added, removed, renamed, or renumbered — the diff **fails** with the family name and the field, and the PR cannot merge until a human updates the reviewed list in the same PR.

Two properties make this honest rather than reassuring. The pattern is name-based, so a new upstream key field with an unlike name (`signing_secret`, say) is missed — which is TM-24's residual risk, unchanged, and the reason the check reports *all* new fields on a `SigningInput`-shaped message, not only matching ones, so a human sees the addition even when the pattern does not fire. And the check binds only families we implement; an unimplemented family's protos are reported informationally.

### Q5 — Can a `KeyLocator` name a key in a different wallet or session?

**Different session: no, structurally.** A `WalletRef`/`KeyRef` carries its owning session's identity and is validated against that session's ref table on every use (DECISION-12 §3.3). A locator from session A used in session B fails with `KeyResolutionError(reason: foreignRef)` in the UI isolate, before a message is posted. There is no API that transfers a ref between sessions, and a ref is not a plain integer a caller could fabricate.

**Different wallet, same session: yes, deliberately** — Solana's fee payer is the concrete case, and refusing it would make a supported upstream feature unexpressible. Three things keep it from becoming a way to sign with an unintended key:

1. **Nothing is implicit.** The signer uses only locators the caller passed in `keys`; it never falls back to "the wallet the request came from" or "the only wallet in the session". The request itself holds no key reference at all except the per-input locators the caller wrote (§4.3).
2. **Unused locators are an error.** A set containing a locator no role consumes fails (§4.1), so a stray locator cannot sit unnoticed in a set and be picked up by a later change.
3. **The result names what signed.** `SignResult.usedKeys` lets a caller, a test, or an audit log assert the exact locator set that produced the bytes, without any key material being exposed.

The residual risk is honest: a caller who passes the wrong locator gets a valid signature by the wrong key. Nothing in the SDK can detect that, because "intended" is not a property we can see. What we can do — and do — is refuse to guess.

### Q6 — For a future `ExternalSigner`, which parts of the threat model change owner, and must v1 of the document cover it?

**Yes, threat model v1 (T5.7) must add an external-signer section**, even if no `ExternalSigner` ships, because `ExternalKeyLocator` is declared in the 1.0 API (§4.2) and a declared type invites the question.

What changes:

- **Drops out of scope for that path:** TM-01 (key residence — no key is ever derived by us), TM-23 (proxy freeing a worker-owned pointer — no wallet handle exists), TM-25 (worker termination with key material in flight — the worker is not involved; PRD §14.2 says an external signer never touches it). TM-24 still applies to the *request*, which is still built by our family code.
- **Appears, and is not modelled at v0:** transport to the device (pairing, authentication, replay, and a malicious or spoofed device); what the user actually confirms on a small screen versus what our request contains (the classic blind-signing gap — our `encoded` bytes and the device's display must correspond, and we cannot verify the device's rendering); the `TWTransactionCompiler` path itself (§3.5), whose pre-image hashes and signature ordering are a new correctness surface — *"the signatures must match the hashes … in the same order"* is an invariant a bug in our code can violate silently; and the fact that per-coin compiler availability is **[UNVERIFIED]** at 4.8.0, so an external signer's chain coverage is an open measurement (T2.9).
- **Stays where it is:** artifact integrity (§4.3 of the threat model), manifest verification, and everything about the library we load, because an external signer still runs our parsing code over bytes upstream produced.

v1 should state that these threats are *deferred, not absent*, and name the milestone (M5) at which the section becomes normative.

## 7. Revisit trigger

Re-open this record when any of the following occurs:

1. **Upstream adds a key field whose name does not match the pattern of §6 Q4**, or moves an existing one into a new message — the two-layer list and its diff check are exercised, and the pattern may need to widen.
2. **A family needs more than the roles of §4.2** (a chain with two independent fee payers, a threshold scheme) — `role` stops being a small closed value and becomes a family-defined type.
3. **PSBT or multisig gets a vector and a product decision** — §4.5's two `UnsupportedOperationError`s become request shapes, and `KeyLocator` may need a "sign only these inputs" qualifier.
4. **T2.9's compiler probe shows broad per-coin availability** — the external-signature path becomes cheap enough that `ExternalSigner` could land before M5, and §6 Q6's deferral shortens.
5. **DECISION-1 selects Approach B** — §4.4's injection step moves into C, and the key-field check must be re-established on the adapter side as well as in Dart (threat model §6, D0 question 9).
6. **Upstream's Bitcoin V2 protocol replaces V1 for the coins we support** — §4.6's `transactionId` normalisation and §3.1's field numbers change, and `UtxoSignResult` gains the V2-only fields as non-null.

---

## Decision

**`Signer.sign(request, Set<KeyLocator>)` returning a sealed `SignResult` is adopted**, in the shape of section 4,
together with the single-key convenience `signWithKey(request, KeyLocator)` that replaced `signWithAccount` at D0, and
the rule that an unused locator is an error rather than a silent no-op.

Binding on **T2.0** (family boundary) and **T2.2**-**T2.8** (family encoders and signers), and it is what AGENTS.md
rule 6 points at: family code encodes key-less inputs and parses results, and only the signer injects keys.

Recorded **2026-09-07 by the orchestrator**, under the repository owner's standing authorization to keep Phase 0 moving while they were unavailable, and **subject to the owner's ratification** (`docs/plan/PROGRESS.md` -> Needs your eyes -> "Decisions recorded on your behalf"). The choice is reversible at the cost stated in the revisit trigger; nothing is published.

Deferred by this record, not decided against: `ExternalSigner` (section 6 Q6, milestone M5) and the `UtxoInput.script`
construction helper (T3.7).
