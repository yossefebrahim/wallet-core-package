# DECISION-1 — Where the signing input and its private key are assembled

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

| | |
|---|---|
| **Question** | PRD §11.4: is the signing protobuf, with its private key, assembled in Dart (Approach A), in a thin native adapter (Approach B), or in Dart now with the adapter held in reserve behind the same `Signer` (A now, B later)? |
| **Status** | **Decided 2026-10-12 (D1, owner): "A now, B later".** Approach A ships. Approach B stays on `eval/approach-b`, unmerged, behind the same public `Signer`, and moves in only on a trigger of §4. |
| **Evidence** | [`DECISION-1-approach-a.md`](DECISION-1-approach-a.md) (Approach A as built, T1.12); Approach B as prototyped (T1.13), on the branch only: `git show eval/approach-b:docs/decisions/DECISION-1-approach-b.md` (branch head `333eb51`); [`D1-A debate`](../plan/reviews/D1-A-sonnet-debate.md) (§A.1, §C.0, §C.4, §C.5); [`D1-B debate`](../plan/reviews/D1-B-sonnet-debate.md) (§B4, §B11, §C); [`sign_json_coverage.md`](evidence/sign_json_coverage.md) |
| **Pinned upstream** | tag `4.8.0`, commit `d692ac27749d0c615e17c751b70ab4f0aa75c59b` |

## 1. Positions and Data

PRD §11.4 left three positions open. The two debaters of D1 (Sonnet 5.5, 2026-10-12) read the code on `main` and the branch and both recommended the third.

- **Approach A — Dart assembles the keyed input.** The family encodes a key-less `SigningInput`; the signing core prepends one length-delimited key field to the serialized bytes inside one native staging buffer and calls `TWAnySignerSign`. No protobuf message and no Dart list ever holds the key.
- **Approach B — a native adapter assembles it.** Dart hands a key-less `TWData` and the pointer of the `TWPrivateKey` to a C function (`wcf_sign_ethereum`) that writes the keyed input straight into an upstream `TWData`. No Dart code reads a key byte.
- **A now, B later** — the chosen position, D1-A §A.1 "Position C".

### 1.1 Approach A, copy by copy

Counted from the code on this branch, one `wc.signer.sign(request, {KeyLocator.hdPath(...)})` on the EVM path (D1-A §A.1 point 1 recounted it the same way):

| | Count | Where |
|---|---|---|
| Copies of the key on the Dart heap | **0** | no protobuf message or Dart list holds it: the key field is prepended as tag ‖ length ‖ key into the native buffer (`signing_core.dart:180-182`, `:230`) |
| Dart-visible objects over key bytes | **1** | a `Uint8List` view over upstream's key `TWData` (`engine/hd_wallet.dart:367`), for one call, never retained |
| Dart-allocated native buffers holding the key | **1** | the `calloc` staging buffer, zeroed with `fillRange` and freed in a `finally` (`engine/secret_buffers.dart:113-141`, `:138-139`) |
| Upstream objects holding the key that this SDK causes to exist | **3** | `TWPrivateKey`, the key `TWData`, the keyed-input `TWData`; each released before the reply, upstream overwriting each (`DECISION-1-approach-a.md` §2) |

`DECISION-1-approach-a.md` counts "3 native objects + 1 buffer" and the Approach B document counts "4 native objects" for A: the same four items, the three upstream ones plus the SDK-allocated staging buffer. What B removes is the view, the staging buffer, and the time the key `TWData` stays alive (B holds the key `TWData` only until before `TWAnySignerSign`, A holds it across the call).

### 1.2 Approach B, measured and what it would take to ship on mobile

Measured on the macOS host only (`DECISION-1-approach-b.md` §4–§5.1): about 105 lines of C statements (263 lines with header), about 130 lines of Dart, +109 lines of build scripts; one session of 143 turns (PROGRESS, T1.13 row); the shim library is **+384 bytes** and builds in the same 5 s. It passed its own 22 shim tests.

It does not exist for Android or iOS (D1-A §C.4, re-checked on the branch):

- The shim is wired into `build_apple.sh --with-shim` only, and that refuses every slice except `macos-arm64_x86_64` (`build_apple.sh:38-40` on the branch). `build_android.sh` and `.github/workflows/build-native.yml` mention "shim" 0 times on the branch; `build_apple.sh` 47 times.
- The branch has no `hook/` directory (`git ls-tree eval/approach-b packages/wallet_core_flutter_native/`); it was cut before T1.R1 ported Option 1 and is 80 commits behind `main` at `0d7e274`.
- To ship it: lift the macOS-only guard; add a generated `src/` file for Android as is done for the identity file; require `wcf_sign_ethereum` in the export gate for 2 ABIs and 3 Apple slices; add a third `provenance` value and the adapter's source hash to the manifest schema and validator; publish a new artifact set (`as_<tag>-shim_nnn`) and re-run the T1.16b and T1.17b device evidence. The hook needs no change under "relink-in" (one library with one more export); a second library would need two code assets per target and a loader change, and is not recommended (D1-A §C.4; B document §5.2–§5.3).
- D1-A's estimate, labelled an inference from T1.13's own numbers: about one implementer session plus one delta plus one publish cycle; the dominant cost is re-evidence, since T1.16b took deltas d1–d9 and T1.17b d1–d2.
- Provenance changes: the library stops being "upstream's object code plus a label"; our C sits on the key path in every artifact (B document §6).

### 1.3 The residual that neither approach removes

On every signing operation, under A and B alike, a copy of the key-carrying input is freed without being overwritten. Read from the source at the pinned commit:

- `RustCoinEntry::sign` copies the whole keyed input into a Rust `TWData` with `tw_data_create_with_bytes` (`third_party/wallet-core/src/rust/RustCoinEntry.cpp:98-100`; Ethereum's `Entry` derives from `RustCoinEntryWithSignJSON`, itself a `RustCoinEntry`: `src/Ethereum/Entry.h:13`, `src/rust/RustCoinEntry.h:17`, `:30`).
- That `TWData` is a `Vec<u8>` filled by `to_vec()` (`rust/tw_memory/src/ffi/tw_data.rs:14`, `:23-24`), and `tw_data_delete` frees it by dropping the owner (`:75-78`). `TWData` has no `Drop` implementation, and nothing under `rust/tw_memory/src` calls a memory-wiping routine (`memzero`, a wiping crate, or a fill with zeros).

What the Rust signer copies beyond that (its protobuf parse, its key value) was not traced. The copy is upstream's; this SDK cannot reach it. It is the reason "key stays native" must never be written as "key is wiped" (AGENTS.md rule 8 and `docs/security/memory_contract.md`).

Upstream does overwrite what it controls on the C++ side: `~PrivateKey` (`src/PrivateKey.cpp:399-400`), `TWDataDelete` (`src/interface/TWData.cpp:106-115`), and `~HDWallet` for seed, mnemonic and passphrase (`src/HDWallet.cpp:101-105`) (D1-A §A.1).

### 1.4 SignJSON does not bear on this decision

`TWAnySignerSignJSON` (106 of 167 coins at `as_4.8.0_000`; Ethereum and Solana yes, Bitcoin no, `evidence/sign_json_coverage.md`) matters to Phase-5 breadth only, and raw protobuf signing in `advanced.dart` covers every coin. For the key it is not better than A: upstream parses the JSON, sets `private_key`, serializes into a `std::string`, copies into a `Data` and signs through the same Rust copy (`src/rust/RustCoinEntry.h:36-60`), leaving more unwiped native copies than A makes; it returns only the encoded hex for Ethereum (`src/Ethereum/Entry.cpp:13-19`), with no v/r/s and no error code (D1-A §A.1, `DECISION-1-approach-a.md` §6).

### 1.5 Against, as recorded

B is cheap on the host and removes the only two pieces of key handling that the SDK controls: `fillRange` carries no `volatile` guarantee (B document §2.3), and a later edit could retain the view. Deferral also gets dearer with each family, because Bitcoin and Solana signing written against `Uint8List` keys would be redone if B comes later. The seam decision of §2.2 exists to remove the second cost.

## 2. Decision and Conditions

### 2.1 Approach A ships; B stays in reserve

**"A now, B later."** The shipped signing core is `SyncSigningCore` (Approach A). `eval/approach-b` is kept, unmerged and unmaintained against `main`, as the reserve. Choosing B later is a packaging and provenance change, not a change to the public API: the public `Signer.sign(TransactionRequest, Set<KeyLocator>) → Future<SignResult>` (`signing/signer.dart:36`) names no key bytes and no handle; `lint:public-api` reports 49 elements and 0 violations (D1-A §A.1; re-run on the base of this record, `0d7e274`); `CoinType` is not exported. `SigningCore` is internal and never exported (`signing/signing_core.dart:30`), created through `SigningCoreFactory` (`worker/handler.dart:29`, default at `:139`).

### 2.2 The seam: a borrowed native key handle per `KeyRole`

Decided with the above (owner, 2026-10-12). Today the seam takes one key as bytes: `SigningCore.sign` takes `Uint8List privateKey` (`signing_core.dart:58`, `:159`), and the handler refuses anything but exactly `KeyRole.primary` (`worker/handler.dart:452-453`). Bitcoin (one key per input) and Solana (fee payer) need one key per role, and for the byte-typed seam and the handle-typed seam of B the interface differs. It is fixed now:

- The internal signing core takes a **borrowed native key handle per `KeyRole`** (never disposed, never retained by the core), so that Approach B can be inserted by supplying a different `SigningCore` through `SigningCoreFactory`, without touching the handler.
- Approach A, behind that seam, derives the `TWPrivateKeyData` view itself inside the core (as T1.13 did on its branch, `DECISION-1-approach-b.md` §1.2).
- **T2.0 owns the change**: its owned paths gain `signing/signing_core.dart`, `engine/hd_wallet.dart` and `worker/handler.dart` (`docs/plan/phases/phase-2-m1-bitcoin-solana-worker.md`). T2.5 (Bitcoin: one key per input) and T2.6 (Solana: fee payer) inject through it and own only `requests/` and `families/`.

D1-A finding D6 recorded that no Phase-2 task owned this seam before the decision.

### 2.3 What this decision does not settle

- Whether a future `RawSigningInput` in `advanced.dart` (not declared yet) runs `checkKeylessInput`: it must (`DECISION-1-approach-a.md` §8 item 6).
- Whether the core should reject a non-32-byte key for secp256k1/ed25519 (`DECISION-1-approach-a.md` §8 item 1), relevant when imported keys exist (T3.4).
- The nested key field (Solana's `nonce_account_private_key`, BitcoinV2's `private_keys`) needs a splice rather than a prepended second occurrence, for A and B alike (`DECISION-1-approach-a.md` §5); DECISION-13 §5 keeps the nonce-account key unexposed in v1.

## 3. Measured Facts that Drove It

- **A's measured residual is small and counted the same way by both debaters** (§1.1): 0 Dart-heap copies, one Dart-visible view, one staging buffer zeroed in a `finally`, three upstream objects each wiped by upstream.
- **The dominant residual is approach-independent** (§1.3), so B cannot remove it.
- **B's cost is in build, provenance and evidence, and none of it exists for mobile** (§1.2). Every Phase-1 device result is for the standard set `as_4.8.0_001`; B would invalidate it.
- **The seam is neutral at the public API** (§2.1), so deferral does not lock the product in.
- **The release-mode behaviour of A's staging buffer is not a reason to switch:** no measurement shows its zeroing elided; the question stays open as trigger (a) below.

## 4. Residual Risks and What Would Reopen It

Moving to B is reconsidered when any of these is recorded (D1-A §A.1 "What would flip me", and the T2.5 trigger):

- **(a)** A release/AOT measurement shows the staging-buffer zeroing is elided or not performed. Not measured: the debaters could not build in their sandbox, and no such test exists in the tree.
- **(b)** A P1 user requirement, or the external review (T5.8), that no Dart-visible key view may exist.
- **(c)** Upstream wipes the Rust copy of §1.3 **and** exposes a signing entry point that takes a key handle, which would make B's gain real and its C trivial.
- **(d)** B is built with relink-in on Android and the iOS device slice, the manifest/provenance schema change is accepted by the owner, and the device evidence is re-run in under about one T1.16b + T1.17b cycle.
- **(e)** T2.5 shows that the multi-key seam of §2.2 cannot take a borrowed native key handle (or the byte view behind it) without a copy.

Residuals recorded here and not owned by this decision: the nested-field splice of §2.3, and the residence-time measurement (T2.10).

## 5. What Changes if Overturned

If B is adopted on a trigger: `eval/approach-b` is rebased on `main` (it predates `hook/`); the adapter, the build-script and workflow changes, the schema and validator change, and a new artifact set of §1.2 land; DECISION-9 and DECISION-14 are amended for the third `provenance` value; the loader requires the new symbol at `Init`; T1.16b and T1.17b evidence is re-run; and the threat model gains the adapter as a component (rows TM-01, TM-15, TM-17, TM-19, TM-20, TM-24, TM-33, TM-34, TM-36 change, `docs/security/threat_model.md`, D1-A §C.0). The public API and the handler do not change, if the seam of §2.2 was built as decided.

## 6. Ratification

Decided by the repository owner on 2026-10-12, in chat at D1, with the three other D1 answers (ratifications of DECISION-2, -6, -9, -11, -12, -13 and -14 §§2–5; one physical iPhone run before `phase-1-closed`; physical Android waived), all recorded in `docs/plan/PROGRESS.md` → "D1 (2026-10-12)".
