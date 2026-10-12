# Signing model — interface sketch

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

| | |
|---|---|
| **Decision** | [DECISION-13](../decisions/DECISION-13.md) — signing model |
| **Binding on** | T1.12 (EVM path), T2.0 (signing model in code), T2.5 (UTXO), T2.6 (Solana), T2.7 (EVM messages), T2.12 (hostile-input suite) |
| **Status** | sections 1–5 are the public sketch: signatures and doc comments only, no bodies. **Section 6 describes the internal seam as built by T2.0** (2026-10-12): `SigningCore.sign` takes a borrowed `PrivateKeyHandle` per `KeyRole`; `withDerivedKeys` derives them; `UtxoInput` and `OutPoint` exist as values. The UTXO and Solana families that use the seam are T2.5 and T2.6. The record was **recorded 2026-09-07** (see the linked DECISION file); binding on the tasks named there. |

Sections 1–5 are the public surface (`package:wallet_core_flutter/wallet_core_flutter.dart`) and name no foreign-function, generated, or serialization type. Section 6 is internal to the SDK's family code and is labelled as such.

The rule the whole file exists to encode: **a request says what to sign; a signer says with what.** Requests are pure values with no key material, and only the signer ever holds a key.

---

## 1. `Signer`

```dart
/// Signs requests with keys named by [KeyLocator]s.
///
/// The 1.0 implementation is [LocalSigner], which resolves keys inside the
/// session's owning isolate. The interface is shaped so that a future signer
/// backed by a hardware device or a remote service implements it without any
/// change to the request types.
abstract interface class Signer {
  /// Signs [request] with the keys named by [keys].
  ///
  /// [keys] is a set because order is meaningless — upstream matches keys to
  /// transaction inputs by script, not by position — and because a duplicate
  /// locator should be harmless. A single-key chain takes one locator; a spend
  /// from several derivation paths takes one per path.
  ///
  /// Resolution happens before any native call and before any key is derived.
  /// Throws [KeyResolutionError] when a role the family needs has no locator,
  /// when a locator no role consumes was supplied, or when a locator names a
  /// reference from another session.
  Future<SignResult> sign(TransactionRequest request, Set<KeyLocator> keys);

  /// Convenience for the single-key case. Exactly equivalent to
  /// `sign(request, {key})`; it is sugar over the set, not an alternative path.
  ///
  /// It takes a [KeyLocator] and not an [Account] on purpose. An `Account`
  /// (see [public_model.md](public_model.md) §4) is a descriptor: it carries a
  /// coin, a path, an address, and a public key, and deliberately no reference
  /// to the wallet it was derived from, so nothing can turn one back into a key.
  /// Naming the key is therefore always the caller's explicit act.
  Future<SignResult> signWithKey(TransactionRequest request, KeyLocator key);

  /// Signs a message request (personal-style or typed structured data).
  Future<SignResult> signMessage(MessageRequest request, Set<KeyLocator> keys);

  /// Plans a UTXO transaction: input selection, fee, and change.
  ///
  /// Takes **no keys at all** — planning needs no secret, and the signature says
  /// so. Available for UTXO chains only; anything else throws
  /// [UnsupportedOperationError].
  Future<UtxoPlan> plan(UtxoTransactionRequest request);
}

/// The 1.0 signer: keys live in the session's owning isolate, are derived for a
/// single operation, and are released before that operation's result is
/// returned.
abstract interface class LocalSigner implements Signer {}
```

## 2. `KeyLocator`

```dart
/// Names a key without carrying it.
///
/// A locator crosses the isolate boundary as plain data. Resolving it into an
/// actual key happens only inside the isolate that owns the wallet, only for the
/// duration of one operation.
sealed class KeyLocator {
  /// Which slot of the operation this key fills. When omitted, a family with a
  /// single key slot assigns it implicitly; a family with several slots requires
  /// it explicitly.
  KeyRole? get role;

  /// A key derived from a session-owned wallet at an explicit path.
  const factory KeyLocator.hdPath(
    WalletRef wallet,
    Coin coin,
    String derivationPath, {
    KeyRole? role,
  }) = HdKeyLocator;

  /// A key imported into the session, for example from an encrypted keystore.
  const factory KeyLocator.imported(KeyRef key, {KeyRole? role}) = ImportedKeyLocator;

  /// A key held by an external signing device.
  ///
  /// **Reserved.** Declared in 1.0 so that adding external signing later is not
  /// a breaking change to this sealed hierarchy. Every 1.0 signer rejects it
  /// with [UnsupportedOperationError] for capability `'external-signer'`.
  const factory KeyLocator.external(
    String deviceId,
    Uint8List publicKey, {
    KeyRole? role,
  }) = ExternalKeyLocator;
}

final class HdKeyLocator implements KeyLocator { … }
final class ImportedKeyLocator implements KeyLocator { … }
final class ExternalKeyLocator implements KeyLocator { … }

/// The slot a key fills in an operation.
final class KeyRole {
  const KeyRole._();

  String get id;

  /// The transaction's own signer. The only role most chains have.
  static const KeyRole primary = KeyRole._();

  /// A separate account paying the fee, where the chain supports one.
  static const KeyRole feePayer = KeyRole._();

  /// The key for transaction input number [n] of a UTXO spend.
  static KeyRole input(int n);
}

/// An opaque, session-scoped reference to an imported key. Not a key.
final class KeyRef {
  const KeyRef._();
}
```

## 3. Requests

```dart
/// Base of every transaction request.
///
/// A request is an immutable, validated, plain-Dart description of a transaction.
/// It crosses isolates freely, is safe to log, and **never contains key
/// material** — not a private key, not a mnemonic, not a passphrase. A request
/// names keys only through [KeyLocator]s, which are names and not secrets.
sealed class TransactionRequest {
  Coin get coin;
  Network get network;

  /// Every locator this request needs, collected from wherever they appear in
  /// it. For most families this is empty and the caller supplies the set; for
  /// UTXO it is the per-input locators.
  Set<KeyLocator> get keyLocators;
}

sealed class MessageRequest {
  Coin get coin;
}
```

### 3.1 EVM

```dart
final class EvmTransactionRequest implements TransactionRequest {
  /// An EIP-1559 native-value transfer.
  ///
  /// [chainId] is explicit and is not read from [coin]: an EVM network this SDK
  /// does not carry in its coin set — a testnet, for instance — is still
  /// signable by supplying its chain id here.
  const EvmTransactionRequest.transfer({
    required Coin coin,
    required int chainId,
    required BigInt nonce,
    required String to,
    required BigInt valueWei,
    required BigInt maxFeePerGas,
    required BigInt maxPriorityFeePerGas,
    required BigInt gasLimit,
  });

  /// A legacy (pre-EIP-1559) transfer.
  const EvmTransactionRequest.legacyTransfer({ … });

  /// A contract call with caller-supplied calldata.
  const EvmTransactionRequest.contractCall({ …, required Uint8List data });
}

final class EvmMessageRequest implements MessageRequest {
  /// A personal-style message.
  const EvmMessageRequest.personal(Uint8List message, {required Coin coin, int? chainId});

  /// Typed structured data, as its JSON document.
  const EvmMessageRequest.typedData(String json, {required Coin coin, required int chainId});
}
```

### 3.2 UTXO

```dart
/// One transaction input, and the name of the key that can spend it.
///
/// The locator lives on the input because that is where the caller knows it: the
/// UTXO was chosen because it belongs to a particular derivation path. The
/// locator itself never reaches upstream — upstream has nowhere to put it, and
/// matches keys to inputs by script.
final class UtxoInput {
  const UtxoInput({
    required this.outPoint,
    required this.amount,
    required this.script,
    required this.addressStyle,
    required this.keyLocator,
  });

  final OutPoint outPoint;
  final int amount;
  final Uint8List script;
  final AddressStyle addressStyle;
  final KeyLocator keyLocator;
}

// Note: [script] is the locking script of the output being spent, and building
// those bytes for a given account and address style needs a helper the UTXO
// family provides in Phase 3 (T3.7). The request type itself is unchanged by
// that; until the helper exists the caller supplies the bytes.

final class OutPoint {
  const OutPoint({required this.transactionId, required this.index});
  final String transactionId;
  final int index;
}

final class UtxoTransactionRequest implements TransactionRequest {
  const UtxoTransactionRequest({
    required this.coin,
    this.network = Network.mainnet,
    required this.toAddress,
    required this.amount,
    required this.feeRatePerByte,
    required this.changeAddress,
    required this.inputs,
    this.useMaxAmount = false,
    this.lockTime = 0,
  });

  final List<UtxoInput> inputs;

  /// The de-duplicated locators of [inputs]. Two inputs on one derivation path
  /// yield one locator, and therefore one derived key.
  @override
  Set<KeyLocator> get keyLocators;
}

/// The result of planning: which inputs were selected, what it costs.
final class UtxoPlan {
  final List<UtxoInput> selectedInputs;
  final int amount;
  final int availableAmount;
  final int fee;
  final int change;
}
```

### 3.3 Solana

```dart
final class SolanaTransactionRequest implements TransactionRequest {
  const SolanaTransactionRequest.transfer({
    required String to,
    required int lamports,
    required String recentBlockhash,
    this.encoding = SolanaEncoding.base58,
    this.feePayer,
  });

  /// The encoding upstream will use for the signed transaction string. Upstream's
  /// default is base58; base64 must be asked for.
  final SolanaEncoding encoding;

  /// The fee-paying account, when it is not the sender. Supplying this **requires**
  /// a locator with [KeyRole.feePayer] in the key set; omitting one is a
  /// [KeyResolutionError], never a silent fallback to the sender paying.
  final Account? feePayer;
}

enum SolanaEncoding { base58, base64 }
```

## 4. `SignResult`

```dart
/// What a signer produced. Sealed and per-family, because upstream's outputs
/// differ by chain in both shape and type: bytes on some chains, a string on
/// others; a transaction id on some, none on others.
///
/// There is deliberately no common `encoded` member: it could only be typed
/// `Object`, which would push a cast onto every caller. Switch exhaustively
/// instead.
sealed class SignResult {
  Coin get coin;

  /// The locators actually consumed to produce this result. Lets a caller, a
  /// test, or an audit log assert exactly which keys signed, without any key
  /// material being exposed.
  Set<KeyLocator> get usedKeys;
}

final class EvmSignResult implements SignResult {
  /// The signed, encoded transaction, ready to broadcast.
  Uint8List get encoded;

  /// The signature components, big-endian.
  Uint8List get v;
  Uint8List get r;
  Uint8List get s;

  /// The pre-hash upstream reports, when it reports one.
  Uint8List? get preHash;
}

final class EvmMessageSignResult implements SignResult {
  /// Hex-encoded signature, as upstream returns it for message signing.
  String get signature;
}

final class UtxoSignResult implements SignResult {
  /// The signed, encoded transaction.
  Uint8List get encoded;

  /// The transaction id, normalised to lowercase hex.
  ///
  /// Upstream returns it as a string in one protocol version and as bytes in
  /// another; this member is the same shape either way, and the normalisation is
  /// part of the contract rather than an implementation detail.
  String get transactionId;

  int? get virtualSize;
  int? get weight;
  int? get fee;
}

final class SolanaSignResult implements SignResult {
  /// The signed transaction, encoded per [encoding].
  String get encoded;

  /// The encoding upstream used. Reported because it is an input choice, not a
  /// constant.
  SolanaEncoding get encoding;

  String? get unsignedTransaction;
}
```

## 5. What the signing surface refuses, and how

| Case | Error | Capability / reason string |
|---|---|---|
| Multisig | `UnsupportedOperationError` | `'multisig'` |
| Partially signed transactions | `UnsupportedOperationError` | `'psbt'` |
| An external-signer locator, in 1.0 | `UnsupportedOperationError` | `'external-signer'` |
| An address style with no vector | `UnsupportedOperationError` | `'addressStyle:<id>'` |
| A watch-only account (no key behind it) | `KeyResolutionError` | `noKeyForAccount` |
| A required role with no locator | `KeyResolutionError` | `missingRole` |
| A locator no role consumes | `KeyResolutionError` | `unusedLocator` |
| A locator naming another session's reference | `KeyResolutionError` | `foreignRef` |
| Upstream reported a signing failure | `SigningError` | upstream's code and message, verbatim |

Every one of these is raised **before** a key is derived, except `SigningError`, which by definition comes from upstream.

## 6. Family boundary — **SDK-internal, not exported**

Family code lives under `lib/src/families/<family>/` and is not part of the public surface. It is described here because DECISION-13 §4.4 makes it a contract between T1.12, T2.0, and the family tasks, and because it is the seam that keeps key material out of everything else.

```dart
/// What every chain family implements, and the only place upstream's message
/// shapes are known.
abstract interface class TransactionFamily {
  /// The facade family whose coins this family signs for, and the fully
  /// qualified name of upstream's signing-input message — the root the
  /// key-field check walks from and the message keys are injected into.
  ChainFamily get chainFamily;
  String get signingInputMessage;

  /// Encodes [request] into upstream's serialized signing input **with no key
  /// field set**.
  ///
  /// This function never receives key bytes and has no parameter that could
  /// carry them. That is the whole point of the signature.
  Uint8List encodeKeylessInput(TransactionRequest request);

  /// Parses upstream's serialized output into a typed result.
  ///
  /// The bytes are treated as untrusted, whatever produced them: the error code
  /// and message are read **first** and mapped to [SigningError] without
  /// interpreting the rest; field sizes are bounded before any copy; and an
  /// output whose shape does not match the requested family fails rather than
  /// being coerced.
  SignResult parseSigningOutput(Uint8List bytes, {required Coin coin, required Set<KeyLocator> usedKeys});

  /// The roles this family needs filled. **The order is the injection order**
  /// (section 6.1).
  List<KeyRole> requiredRoles(TransactionRequest request);

  /// The reviewed list of field names that carry key material in this family's
  /// messages. See [KeyFieldList].
  KeyFieldList get keyFields;

  /// The field of [signingInputMessage] the key for [role] is injected into.
  /// Several roles may name the same `repeated` field (UTXO inputs) or
  /// different fields (Solana's `primary` and `feePayer`). Throws
  /// [ArgumentError] for a role the family has no slot for.
  KeyFieldEntry injectionField(KeyRole role);

  /// Decodes serialized signing-input bytes into the generated message, for
  /// the key-field check only.
  GeneratedMessage decodeSigningInput(Uint8List bytes);
}

/// The reviewed per-family list of key-carrying field names.
///
/// Two layers, and the test between them is the mechanism (DECISION-13 §6 Q4):
///
/// * a **generated** inventory, produced from the pinned schema descriptors by a
///   recursive walk — the walk must be recursive, because at least one chain
///   declares a key field inside a nested message rather than in the top-level
///   signing input;
/// * this **reviewed** list, written by a human, naming both the field and the
///   message it occurs in.
///
/// A unit test asserts the reviewed list equals the generated set for this
/// family. The pin-time API diff fails when the two drift, so an upstream change
/// cannot land without a human updating this list in the same change.
final class KeyFieldList {
  const KeyFieldList(this.entries);
  final List<KeyFieldEntry> entries;
}

final class KeyFieldEntry {
  const KeyFieldEntry({
    required this.messagePath,
    required this.fieldName,
    required this.fieldNumber, // the key-field check and the injection work on wire numbers
    required this.repeated,
  });
  final String messagePath;
  final String fieldName;
  final int fieldNumber;
  final bool repeated;
}
```

**The injection rule, which only the signer performs.** For each operation, in this order:

1. Resolve every locator into the roles the family requires; fail with `KeyResolutionError` if the sets do not match.
2. Call `encodeKeylessInput(request)`.
3. Verify, against `keyFields`, that the encoded bytes carry none of those fields. A match means the family encoder is defective; the operation fails with `InvalidInputError` before any key is derived.
4. Derive one key per role, inject each into the field `injectionField(role)` names, and call upstream. Section 6.1 is the exact mechanism.
5. **Still inside the `try`, and before anything is released:** `parseSigningOutput` upstream's output into a `SignResult`. Upstream's output lives in an allocation that step 6 frees, so it must be read while it is alive; parsing produces Dart-owned copies of the signed bytes, the signature components, and the transaction id.
6. **In a `finally`:** release every derived key handle, the injected input buffer, and every other temporary allocation, and overwrite the SDK's own key-bearing byte buffers. This block runs before the result is returned or the reply is posted — on the success, error, deadline, and cancellation paths alike, and also when step 5 throws.

The rule in one line: **parse before releasing, release before replying** (DECISION-12 §3.9). The two categories must not be confused. The `SignResult` retained from step 5 is *not* key-bearing — a signed transaction carries signatures and public data, never the private key that produced them — so keeping it is not a secret held past the `finally`. What the `finally` releases is the key-bearing set: derived key handles, the serialized input after injection, and the temporaries around them. On a discarded path (a deadline that has already elapsed, a cancellation) the parsed result is dropped rather than posted, and the release happens exactly as it would have.

Steps 2 and 5 are the family's; steps 1, 3, 4, and 6 are the signer's; no other component sees a key. `RawSigningInput`, which takes caller-supplied serialized bytes, exists only under `advanced.dart` — arbitrary bytes can contain key fields and this SDK cannot prove otherwise, so the caller accepts that responsibility explicitly (PRD §10.2).

### 6.1 The signing seam, as built (T2.0)

Steps 3, 4 and 6 of the injection rule are one function, `SigningCore.sign` (`lib/src/signing/signing_core.dart`). DECISION-1 (owner, 2026-10-12) is *Approach A now, Approach B later behind the same `Signer`*; this is the seam that makes the later move local.

```dart
abstract interface class SigningCore {
  S sign<S extends SignResult>(
    Uint8List keylessInput, {
    required TransactionFamily<TransactionRequest, S> family,
    required Coin coin,
    required List<KeyRole> requiredRoles,
    required Map<KeyRole, PrivateKeyHandle> keys,
    required Set<KeyLocator> usedKeys,
  });
}
```

`SyncSigningCore` is Approach A: it runs in the isolate that owns the native context, synchronously.

**Ownership: borrowed.** Each `PrivateKeyHandle` (the internal handle of `engine/handles.dart`, one upstream `TWPrivateKey`) is read during the call only; the core never disposes, retains, or modifies one. The handler derives them in one scope (`withDerivedKeys`, `engine/hd_wallet.dart`: one handle per `KeyRole` → (wallet, coin, path), all disposed when the scope closes — on return, on a throw from the callback, and when a later derivation fails) and so owns every handle for the whole of the operation. No key bytes cross the seam in either direction: not as an argument, not in a result, not in an error.

**Injection order.** Keys are injected in the order of `requiredRoles`, which is `TransactionFamily.requiredRoles(request)` as the handler passes it. The map's iteration order has no effect. Two roles that name one `repeated` field become consecutive elements of it in that order (UTXO: `input(0)`, `input(1)`, … give `repeated bytes private_key` in input order — upstream matches keys to inputs by script, so the order carries no meaning for Bitcoin and is fixed only so that a test can state it). Roles on different fields land in `requiredRoles` order on the wire.

**What the core does, in order.**

1. `coin` must belong to `family.chainFamily` (`InvalidInputError`, `inputName: 'coin'`).
2. **Key-field check, before any key is read:** `keylessInput` must decode as one complete `signingInputMessage` and carry no field of `keyFields` at any depth and no group or unknown field (`InvalidInputError`, `inputName: 'signingInput'`).
3. **Role checks** — a defect of the caller inside the SDK, so `StateError`, still before any key is read: `requiredRoles` is non-empty and repeats no role; `keys` has exactly the roles in `requiredRoles`; `family.injectionField(role)` exists for each, is a field of `signingInputMessage` itself, and no two roles share one *singular* field. (User mistakes — a missing, unused, foreign, or imported locator — were already turned into `KeyResolutionError` by the handler's `_resolveKeys`; no new reason was needed.)
4. **Assembly.** For each role in order, `TWPrivateKeyData(handle)` gives a `TWData` copy of the key; the field header (`varint(number << 3 | 2)`, `varint(length)`), a **view** over that `TWData`'s native buffer, and finally the key-less bytes are copied straight into **one** `calloc` staging buffer, which becomes the keyed-input `TWData`. The key `TWData`s are disposed immediately after the assembly, before upstream is called. Keys are **prepended** as complete fields, never appended (an appended key lands inside whatever field the key-less bytes end in).
5. `TWAnySignerSign(keyedInput, coinType)`; then `parseSigningOutput` on a copy of the output — parse before releasing.
6. **`finally`:** the output `TWData` and the keyed-input `TWData` are disposed (upstream's `TWDataDelete` overwrites them). The staging buffer was overwritten with zeros and freed inside the assembly's own `finally`, whether or not the `TWData` was created.

**Where the key bytes are, and for how long** (one sign, `n` keys):

| # | What | Memory | Lives from → until | Ends by |
|---|---|---|---|---|
| 1 | `TWPrivateKey` per role (upstream's C++ `PrivateKey`) | upstream heap | `withDerivedKeys` → scope close, after the core returned | the handler's scope disposes it; upstream's `~PrivateKey` overwrites it |
| 2 | `TWData` copy of each key (`TWPrivateKeyData`) | upstream heap | start of assembly → end of assembly | the core disposes it; upstream's `TWDataDelete` overwrites it |
| 3 | `Uint8List` view over #2 | none — aliases #2's buffer | during assembly | dropped with #2; never a copy |
| 4 | staging buffer: `n` × (header, key), then the key-less input | `calloc`, outside the Dart heap | during assembly | overwritten with zeros, then freed, in `secretDataFromParts`' `finally` |
| 5 | keyed-input `TWData` | upstream heap | end of assembly → end of the call | the core disposes it; `TWDataDelete` overwrites it |
| 6 | upstream's own copies while it signs (C++ `Data`, the Rust copy, the decoded Rust `SigningInput`, its private-key objects) | upstream heap | inside `TWAnySignerSign` | upstream's; see `docs/security/memory_contract.md` for what was and was not verified |

**No Dart-heap copy of any key exists.** There is no `Uint8List.fromList`, no `List<int>` of key bytes, and no protobuf message holding a key: the message decoded by the key-field check is the key-less input, and the key fields are written as bytes, so no `CodedBufferWriter` chunk contains one. What the SDK returns (the result), throws (typed errors, which name a field or a role, never a value) and holds (nothing between calls) contains no key.

**Why Approach B can go behind this seam without touching the handler.** The seam already takes the native object, not bytes. A B adapter (a C function taking a key-less input, a coin, and `TWPrivateKey*`s in injection order and doing steps 4–5 natively) implements `SigningCore` with the same parameters: locator resolution, derivation, the key-field check, the family's encoder and parser, and the handler's ownership of the handles are unchanged; only #2–#5 of the table move into C, where DECISION-13 §7 item 5 requires the key-field check to be re-established on the adapter's side as well.
