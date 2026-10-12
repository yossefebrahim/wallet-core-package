# Chain families

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

Everything under `lib/src/families/` is SDK-internal and is not exported. A family is the only place upstream's message shapes are known. It never sees a key: it turns a request into a key-less serialized signing input, and it turns upstream's serialized output into a typed result. The signer owns keys. Rules: [`AGENTS.md`](../../../../../AGENTS.md) 2 and 6; design: [`docs/architecture/signing.md`](../../../../../docs/architecture/signing.md) §6 and [DECISION-13](../../../../../docs/decisions/DECISION-13.md) §4.4.

## The contract

A family implements `TransactionFamily<R, S>` (`family.dart`), `R` its request type and `S` its result type:

| Member | What it is | Constraint |
|---|---|---|
| `encodeKeylessInput(R)` | pure function: request → serialized upstream `SigningInput` | no key field set; **no parameter that could carry a key**; one complete, well-formed message of `signingInputMessage`; no isolate, pointer, engine, or native call |
| `parseSigningOutput(bytes, coin:, usedKeys:)` | pure function: upstream's serialized output → `S` | treats the bytes as untrusted (TM-22): length bounded, error code and message read **first** and mapped to `SigningError` verbatim, unknown fields rejected, every field bounded before it is copied; every rejection is a `SigningError(malformedOutputCode)` |
| `requiredRoles(R)` | the `KeyRole`s the request needs a key for | **the order is the injection order** (below); no duplicates |
| `injectionField(KeyRole)` | the `KeyFieldEntry` the key for that role is written into | a field of `signingInputMessage` itself; throws `ArgumentError` for a role the family has no slot for; a singular field serves one role, a `repeated` field may serve several |
| `keyFields` | the reviewed `KeyFieldList` of every key-carrying field of the family's messages, at any depth | equals the generated `key_fields.json` for the family's protos (a test asserts it); a nested key field (Solana's `nonce_account_private_key`) is listed too even though it is never injected |
| `chainFamily`, `signingInputMessage`, `decodeSigningInput(bytes)` | which coins the family signs for, upstream's message name, and the generated decoder the key-field check walks | |

`familyFor` (`families.dart`) maps a request to its family with an exhaustive `switch` over the sealed `TransactionRequest`: a new request type does not compile until it has a family.

## What a family may and may not touch

May: its request type (`lib/src/requests/<family>/`), upstream's generated protobuf classes for its own messages, `KeyRole`, `KeyFieldList`/`KeyFieldEntry`, the SDK's typed errors, `maxNativeBufferBytes`.

May not:

- hold, receive, derive, or print a private key, a mnemonic, or a passphrase — not in a parameter, a field, a log line, or an error message;
- call native code: no `TW*` function, no `Pointer`, no `NativeContext`, no handle (including `PrivateKeyHandle`);
- inject a key, or set a field of `keyFields` on the message it encodes — the signing core prepends the keys and rejects key-less bytes that already carry one;
- compute a signature, derive a key, or serialize a signed transaction (AGENTS.md rule 2): upstream signs;
- reach for a coin by `CoinType`: the default surface works in `Coin`; the core maps it;
- decide which key signs: the request holds `KeyLocator`s (names), the signer resolves them.

## How a key gets in — the injection order

For one signature the handler resolves the caller's locators to one `KeyRole` each, derives one `PrivateKeyHandle` per role in one scope (`withDerivedKeys`), and calls `SigningCore.sign(keyless, family:, coin:, requiredRoles:, keys:, usedKeys:)`. The core:

1. checks the key-less bytes against `keyFields` (decode + walk) **before any key is read**;
2. for each role of `requiredRoles`, **in that order**, reads the key through `TWPrivateKeyData`, and emits `tag(injectionField(role)) · length · key`;
3. emits the key-less bytes after all of them (keys are **prepended**, never appended — see `SyncSigningCore.sign`);
4. calls upstream and hands the output to `parseSigningOutput`.

Two roles on one `repeated` field become consecutive elements of it, in `requiredRoles` order — for UTXO `input(0)`, `input(1)`, … give `private_key` in input order. Two roles on different fields (Solana `primary` → `private_key`, `feePayer` → `fee_payer_private_key`) land in `requiredRoles` order on the wire, which no parser depends on. A required role without a key, a key for a role that is not required, a role without a slot, a slot outside the signing input, or two roles on one singular field are defects of the caller inside the SDK and fail with `StateError` before any key is read; the handler has already turned the user's mistakes (missing, unused, or foreign locators) into `KeyResolutionError`.

## Plugging a family in

1. Request type in `lib/src/requests/<family>/`, a `part` of `requests.dart` (the bases are `sealed`), pure and validated at construction; value types shared by families (`OutPoint`, `UtxoInput`) are in `requests/base.dart`. Never a key — a request names keys through `KeyLocator`s only.
2. `lib/src/families/<family>/key_fields.dart` (the reviewed list) and `<family>_family.dart` (the contract above), then one arm in `familyFor`.
3. Result type: a new member of the sealed `SignResult` (`signing/sign_result.dart`).
4. In the handler (`worker/handler.dart`): the request-specific pre-checks that need the engine (the EVM recipient check is the model) — and nothing about keys; `_resolveKeys` already returns a locator per required role.
5. Tests: a `test/families/<family>/` suite — byte-for-byte against the vector, the generated-list equality test, the tampered-key-less-input rejection, and a sign that never leaves a handle undisposed.

What each follow-up task adds:

- **T2.5 UTXO** — `requiredRoles` is `[input(0) … input(n−1)]` for the request's inputs, all with `injectionField` = Bitcoin `SigningInput.private_key` (field 6, `repeated`). The request's `UtxoInput.keyLocator`s become the locator set; two inputs on one derivation path are one locator (de-duplicate before deriving) — at that point the family has to say how a role per input maps onto a de-duplicated key set, because the core takes one handle per role: either one role per distinct key (and the input order of `private_key` is by first use) or the same handle under several roles. `withDerivedKeys` derives per map entry, so the first costs one derivation per distinct key. Upstream matches keys to inputs by script, so the order in `private_key` is not semantic.
- **T2.6 Solana** — `requiredRoles` is `[primary]`, or `[primary, feePayer]` when the request names a separate fee payer; `injectionField` gives `private_key` (1) and `fee_payer_private_key` (17). The nested `nonce_account_private_key` stays unexposed in v1 but stays in `keyFields`.
- **T2.7 EVM messages** — a second `MessageSigningInput` on the existing EVM family (`private_key`, field 1, already in `evmKeyFields`). The family contract is generic over the request type but `signingInputMessage` names one message, so message signing is either a second family object or a family that takes the message from the request; `MessageRequest` has no member yet and `familyFor` covers transaction requests only.
