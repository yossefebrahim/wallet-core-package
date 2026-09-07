# DECISION-11 — Public coin / network / account model

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

| | |
|---|---|
| **Question** | What does a consumer of `package:wallet_core_flutter/wallet_core_flutter.dart` name when it wants to say "Bitcoin", "Bitcoin testnet", "Base", or "this account"? |
| **Governing PRD sections** | §8 (public import rules), §10.2 (accounts, addresses), §13.1 (capability levels), §16 S5 (input validation), §22 DECISION-11, §25 (public model, A-04 reframed) |
| **Evidence** | `docs/decisions/evidence/prefetch-2026-09-07/upstream-src/registry.json`, `.../TWCoinType.h`, `.../TWDerivation.h`, `.../TWAnyAddress.h`, `.../TWHDWallet.h`, all at commit `d692ac27749d0c615e17c751b70ab4f0aa75c59b` (tag 4.8.0) |
| **Interface sketch** | [`docs/architecture/public_model.md`](../architecture/public_model.md) |
| **Recommendation** | **Option A — thin stable facade**, in the exact shape of §4 |
| **Status** | recommended by T0.11; adjudicated at D0 (recommendation upheld); pending the human's recording |

---

## 1. Context

PRD §8 forbids the generated `CoinType` enum in any public signature, and AGENTS.md rule 12 repeats it. The reason is not aesthetic: `CoinType` is regenerated from `registry.json` at every upstream pin, so an upstream rename, addition, or removal would land in a consumer's `switch` statement as a compile error attributable to us. Something else has to be the public name of a chain, and it has to have a stability policy that upstream's registry does not have.

Three properties of upstream 4.8.0 shape the answer, and none of them is a design choice we get to make:

1. **EVM networks are already separate coins.** 60 of the 167 registry entries carry `"blockchain": "Ethereum"`, each with its own `coinId`, its own derivation path, and its own numeric `chainId`. Ethereum and Base are as different, to upstream, as Ethereum and Solana.
2. **Bitcoin testnet is not a coin.** It is one of four named entries in `bitcoin`'s `derivation` list, and it produces `TWDerivationBitcoinTestnet = 4` — the *same* `TWCoinType` value (0), a different derivation. Nothing in the registry expresses "Ethereum Sepolia" at all.
3. **Upstream's one `derivation` axis carries two of our concepts.** `bitcoin`'s four names are `segwit`, `legacy`, `testnet`, `taproot`: three address styles and one network, in one list, with no field distinguishing them.

So a faithful facade cannot be a one-to-one renaming of the registry. It has to (a) key on something upstream will not renumber, (b) add a network axis upstream lacks, and (c) split upstream's derivation axis into the two axes an application actually reasons about.

## 2. Options

### Option A — thin stable facade (the PRD's default)

A `Coin` value type keyed by the upstream registry **`id` string**, with a written stability policy; an explicit `Network` only where upstream has a distinct concept; an `AddressStyle` for the rest of the derivation axis; assets (ERC-20 and similar) deferred to family helpers; `Account` a plain descriptor owning nothing.

- Public surface: `Coin`, `Network`, `AddressStyle`, `ChainFamily`, `Account`, `Address`, and a lookup facade. Six types, no generated ones.
- Upstream churn is absorbed by a mapping table in the SDK, not by consumer code.
- Cost: the facade is hand-maintained where it exceeds the registry (network availability, family grouping, aliases). Three small tables that a human reviews at each pin.

### Option B — full chain-family / network / asset domain model

`ChainFamily → Chain → Network → Asset → Account`, five types with real behaviour, assets as first-class (`Asset.erc20(chain, contract, decimals)`), address types modelled per family.

- Honest to what a wallet application eventually needs.
- Rejected in PRD §25 as exceeding 1.0 scope, and the evidence supports that: an `Asset` type implies a token list, decimals, and contract metadata that this SDK deliberately does not ship (PRD §6 keeps balances, fees, and RPC out of scope), so `Asset` would be a type with no source of truth behind it. The five-type model also freezes a taxonomy over 57 distinct `blockchain` values before we have vectors for three of them.

### Option C — the generated `CoinType` enum, public, with a deprecation policy

Export the generated enum and promise to keep removed variants around for one major version.

- Zero mapping code, perfect fidelity, and the smallest diff.
- Rejected: it contradicts PRD §8 and AGENTS.md rule 12, and the promise is unkeepable in the shape it needs to be. The enum is a **generated** artifact (`gen:registry`, never hand-edited, rule 1); keeping a variant upstream deleted means hand-editing generated output or forking the generator's input. It also leaks `coinId` values as public API: `TWCoinTypeSmartChain = 20000714` and the deprecated `bsc = 10000714` are upstream's internal numbering, and a consumer that persisted one has persisted an upstream implementation detail.

## 3. Evidence

All counts produced from `docs/decisions/evidence/prefetch-2026-09-07/upstream-src/registry.json` (the pinned commit's registry) on 2026-09-07.

| Fact | Value | Where |
|---|---|---|
| Registry entries | **167** | `registry.json`, top-level JSON array |
| `TWCoinType` enum variants | **167** | `TWCoinType.h`, `grep -cE '^    TWCoinType[A-Za-z0-9]+ = '` |
| Entries with `"blockchain": "Ethereum"` | **60** | `registry.json` |
| Distinct `blockchain` values | **57** | `registry.json` (the brief's "58" is one high; recount before quoting it elsewhere) |
| Entries carrying `chainId` | **99** — 60 EVM (all numeric: `ethereum` `"1"`, `base` `"8453"`, `linea` `"59144"`, `mantle` `"5000"`) and 39 non-EVM (**not** numeric: `cosmos` `"cosmoshub-4"`, `juno` `"juno-1"`, `kujira` `"kaiyo-1"`) | `registry.json` |
| Entries with `"deprecated": true` | **2** — `kin` (`coinId` 2017), `bsc` (`coinId` 10000714) | `registry.json` |
| `id` collisions / `coinId` collisions | none; 167 unique of each | `registry.json` |
| `id` differing from `name` lower-cased | 20 entries | `registry.json` |
| Curves in use | `secp256k1` 140, `ed25519` 23, `nist256p1` 2, `ed25519Blake2bNano` 1, `ed25519ExtendedCardano` 1 | `registry.json` |

**Per-entry fields.** 26 distinct keys appear across the registry. Only **11** are present on all 167 entries: `blockchain`, `coinId`, `curve`, `decimals`, `derivation`, `explorer`, `id`, `info`, `name`, `publicKeyType`, `symbol`. The other 15 are optional and sparse: `addressHasher` (99), `chainId` (99), `hrp` (60), `displayName` (48), `nativeTokenName` (47), `base58Hasher` / `p2pkhPrefix` / `p2shPrefix` / `publicKeyHasher` (26 each), `slip44` (12), `testFolderName` (7), `ss58Prefix` / `staticPrefix` (4 each), `deprecated` (2), `url` (2). *(The brief's field list omitted `addressHasher`, `chainId`, `deprecated`, `displayName`, `nativeTokenName`, `slip44`, `ss58Prefix`, `staticPrefix`, `testFolderName`, and `url`; the list above is what the file contains.)* Consequence for the facade: every optional field must be nullable or absent from the public type, and `chainId` cannot be typed as an integer.

**Bitcoin's `derivation` entries**, verbatim from `registry.json` (`id: "bitcoin"`, `coinId: 0`):

```json
"derivation": [
  { "name": "segwit",  "path": "m/84'/0'/0'/0/0", "xpub": "zpub", "xprv": "zprv" },
  { "name": "legacy",  "path": "m/44'/0'/0'/0/0", "xpub": "xpub", "xprv": "xprv" },
  { "name": "testnet", "path": "m/84'/1'/0'/0/0", "xpub": "zpub", "xprv": "zprv" },
  { "name": "taproot", "path": "m/86'/0'/0'/0/0", "xpub": "zpub", "xprv": "zprv" }
]
```

Four named entries. The first is the default that `TWHDWalletGetAddressForCoin` uses; `testnet` differs from the others only in SLIP-44 coin type (`1'` rather than `0'`) and is selected through `TWHDWalletGetAddressDerivation(wallet, coin, derivation)` with the same `TWCoinType` value 0.

**Named derivations across the whole registry** (`name` present): `segwit` 2, `legacy` 2, `testnet` 2, `taproot` 1, `solana` 1, `stable_account` 1, `mainnet` 1 — against **164 unnamed** entries. The only two coins with a `testnet` derivation are `bitcoin` and `pactus`. `TWDerivation.h` enumerates exactly these as 12 variants (`TWDerivationDefault = 0`, `TWDerivationCustom = 1`, `TWDerivationBitcoinSegwit = 2` … `TWDerivationSmartChainStableAccount = 11`) and is itself generated from `registry.json`.

**No coin in the registry has "testnet" in its `id` or `name`.** There is no Sepolia, no Solana devnet, no Litecoin testnet. Whatever testnet support the SDK claims beyond Bitcoin and Pactus, it cannot get from upstream's registry at 4.8.0.

## 4. Recommendation

**Option A**, with these six rulings. The signatures are in [`docs/architecture/public_model.md`](../architecture/public_model.md).

### 4.1 `Coin` is keyed by the registry `id` string

`Coin.id` is upstream's `id` verbatim (`'bitcoin'`, `'ethereum'`, `'base'`, `'smartchain'`). It is the value a consumer persists, logs, and puts in a config file. `Coin` is a `final class` with a private constructor, not an `enum`: named constants (`Coin.bitcoin`, `Coin.ethereum`, `Coin.solana`) exist for the tested set, and `Coin.find(String id)` resolves any of the 167 without a code change on our side when upstream adds the 168th.

Why not an enum: a Dart `enum` fixes its member set at compile time, so every upstream addition would be a minor API change and every removal a breaking one — exactly the coupling this decision exists to break.

### 4.2 `Coin` → `CoinType` mapping, exactly

The mapping lives entirely in the bindings layer and is one lookup:

```
Coin.id  ──(generated registry table: id → coinId)──►  int coinId  ──(generated enum: value == coinId)──►  CoinType
```

**[VERIFIED]** the generated enum's value *is* `coinId` — `TWCoinType.h` declares `TWCoinTypeBitcoin = 0`, `TWCoinTypeEthereum = 60`, `TWCoinTypeSolana = 501`, matching `registry.json`'s `coinId`, and the enum has 167 variants for 167 entries. The SDK holds a `Coin` and hands the bindings a `Coin`; the bindings resolve `coinId`. No public signature, and no consumer-visible value, ever mentions `CoinType`. `lint:public-api` (T1.15) enforces this mechanically.

### 4.3 Stability policy (the part that is a promise, not a mapping)

Written into the doc comment of `Coin` and into `docs/architecture/public_model.md`:

1. **Ids are never reused.** Once `Coin.find('kin')` has resolved to a coin in a published version, that id never names a different chain. Upstream's `coinId` values are not part of the public surface and may be renumbered by upstream without affecting us.
2. **An upstream rename keeps the old id as an alias.** If upstream renames `id: "foo"` to `id: "bar"`, the SDK adds `bar` and keeps `foo` resolving to the same coin, marked `CoinStatus.renamed(to: 'bar')`. The alias table is hand-written (`lib/src/coin/aliases.dart`), reviewed in the pin PR, and never removed inside a major version. It is *not* generated, because its content is a historical record that the current registry no longer contains.
3. **An upstream removal deprecates, it does not delete.** A `Coin` whose registry entry disappears keeps resolving for **at least one minor version** with `CoinStatus.removedUpstream`; every operation on it throws `UnsupportedOperationError(coin, capability)` rather than failing to compile. It is removed from `Coin.all` immediately (so iteration reflects reality) but stays resolvable through `Coin.find`. Removal of the constant itself is a major-version change.
4. **`"deprecated": true` upstream is surfaced, not hidden.** `kin` and `bsc` carry it today. Those coins map to `CoinStatus.deprecatedUpstream`: resolvable, usable, and reported by `Coin.isDeprecated` so an application can warn. We do not silently redirect `bsc` to `smartchain`; both are distinct registry entries with distinct `coinId`s (10000714 and 20000714) and redirecting would sign against a chain the caller did not name.
5. **Adding a coin is a minor version.** New ids appear when the pin moves; the API diff (T4.1) lists them and the capability matrix marks them *generated*, never *tested*.
6. **The registry `id` is the only stable key we publish.** `name`, `displayName`, `symbol`, `explorer`, and `info` are passed through as data and may change at any pin without a semver event; the doc comment says so.

7. **The gate that enforces 2 and 3 must be operational before any pin merges.** Rules 2 and 3 are promises about a hand-written table (`lib/src/coin/aliases.dart`), and a hand-written table kept in step with upstream by good intentions will fall out of step at the pin where it matters. So the enforcement is mechanical and it is a *merge* gate, not a report:

   > A check on every pin PR compares the previous pin's registry ids against the new one's. If an id **disappeared** or was **renamed** — the id is gone and an entry with the same `coinId` appears under a different id — the check **fails** unless the same PR adds the corresponding alias or removal entry. The failure names the id and the required entry. The PR cannot merge until it is added.

   This runs as part of T4.1's API diff (§5), and the sequencing follows: the gate exists and passes **before the first pin PR is merged**, not after the first upstream rename is observed. If the gate is not in place, pins do not merge — an unenforced alias policy is worse than no policy, because consumers would have been told ids never break.

### 4.4 `Network` exists, and only where upstream has the concept

`Network` is a small value type with `Network.mainnet` and `Network.testnet` and an `id` string, not an enum, for the same reason as `Coin`.

- `Coin.networks` reports what the *pinned registry* supports. It contains `Network.testnet` only when the coin's registry entry has a derivation named `testnet` — at 4.8.0 that is exactly `bitcoin` and `pactus`.
- Requesting `Network.testnet` for any other coin throws `UnsupportedOperationError(coin, 'network:testnet')` **in Dart, before any native call** (PRD §16 S5, threat row TM-21). We do not silently fall back to mainnet; signing a mainnet transaction because the caller asked for testnet and we shrugged is the worst failure mode a signing SDK has.
- For EVM, `Network` is *not* the axis. Each EVM network is its own `Coin` with its own `Coin.evmChainId` (an `int`, populated only when `Coin.family == ChainFamily.evm`, from the 60 numeric registry `chainId`s). `Coin.ethereum.networks` is `{Network.mainnet}`. An Ethereum testnet is expressed the way upstream expresses it — it is not in the registry, so it is not in the facade; `EvmTransactionRequest` takes an explicit `chainId`, so a caller who has a testnet chain id can still sign with it, and the capability matrix records that no vector covers it.
- Non-numeric chain identifiers (`"cosmoshub-4"` and 38 others) are exposed as `Coin.chainIdTag`, a `String?`. They are never coerced to `int`.

### 4.5 Address style is a separate axis from network

`AddressStyle` (`standard`, `legacy`, `segwit`, `taproot`) carries the rest of upstream's derivation names. `(Coin, Network, AddressStyle)` resolves to one `TWDerivation` value inside the bindings; unrepresentable combinations (`taproot` + `testnet` at 4.8.0, because upstream has no such derivation entry) throw `UnsupportedOperationError` in Dart. `Coin.addressStyles` reports what the pinned registry offers, so the failure is discoverable before it is thrown.

This split is the one place the facade deliberately does not mirror upstream, and it is the reason `Network` cannot be a derivation name passed through: `segwit` and `testnet` sit in one JSON list and mean entirely different things.

**Family metadata is descriptive, unstable, and never a support claim.** Two members of the facade look like they answer "is this chain supported?" and must not be read that way:

- **`ChainFamily.other`** is the bucket for coins this SDK exposes for address operations but ships no request builder for. Its membership is *this SDK's* grouping at *this version*, it changes as families are implemented, and a coin moving out of `other` in a minor version is not a semver event on the facade.
- **`ChainFamily.hasRequestBuilders`** says only that a family has typed request builders at all. It says nothing about whether a *particular* coin in that family has a vector, whether an operation is tested, or whether an address style works — a coin can sit in a family with request builders and still have no tested operation of any kind.

Neither is stable across versions and neither is a claim of support. **The capability matrix (`docs/capability_matrix.md`, T2.8) is the only support claim this project makes**, it is generated rather than asserted, and it distinguishes *exposed* from *generated* from *tested* per coin and operation (PRD §13.1). The doc comments on both members say this, in those words, so a consumer reading the API rather than the docs still gets it. An application that needs to know what works reads the matrix; family metadata is for grouping a coin list in a UI.

### 4.6 Assets are deferred; `Account` is a descriptor

No `Asset`, `Token`, or `Erc20` type in the public surface for 1.0. ERC-20 and SPL transfers are *request builders* in the family helpers (`EvmTransactionRequest.erc20Transfer(contract:, to:, amount:)`, T3.6; SPL in T3.8), where the contract address and decimals are caller-supplied parameters. The SDK has no token list, no decimals source, and no way to verify a contract, so a first-class `Asset` would be a type whose invariants we cannot uphold (PRD §6 keeps balances and metadata out of scope).

`Account` is a plain immutable descriptor — `coin`, `network`, `addressStyle`, `derivationPath`, `address`, `publicKey` (`Uint8List`) — owning no native handle, no key, and no session reference. It crosses isolates by copy, is safe to persist, and is not a capability: holding one grants nothing. Keys are named separately at signing time (DECISION-13).

### 4.7 What this costs, honestly

Three hand-maintained tables — aliases (§4.3.2), per-coin network availability where it exceeds the registry, and family grouping — each of which can drift from upstream between pins. The mitigations are that all three are small, all three are diffed by T4.1 at every pin, and a drift produces `UnsupportedOperationError` (loud, typed, before native) rather than a wrong signature.

## 5. Consequences for tasks

| Task | What changes |
|---|---|
| **T1.5** — registry transform | Output must expose `id → coinId` and the per-coin derivation-name list as generated data the facade consumes; the generated `CoinType` stays bindings-internal. Add a generated `derivations` map (`coin id → [name, path]`) so §4.4 and §4.5 read availability from generation rather than a hand-written list. |
| **T1.11** — SDK core | Implements `Coin`, `Network`, `AddressStyle`, `ChainFamily`, `Account`, `Address` and the lookup facade exactly as `docs/architecture/public_model.md` sketches them; owns `lib/src/coin/aliases.dart` (empty at 4.8.0, with the policy in its header comment); rejects `Network.testnet` for the 165 coins that lack a `testnet` derivation, in Dart, before native. |
| **T1.12** — EVM path | `EvmTransactionRequest` takes `chainId` explicitly and does not read it from `Coin`; the coin is still required (it selects the signer), and a mismatch between `Coin.evmChainId` and the request's `chainId` is a **warning-free, deliberate allowance** so testnets remain signable — but the request records both and `parseSigningOutput` is not permitted to override either. |
| **T1.15** — public-API lint | Adds an explicit rejection for the generated `CoinType`, for `coinId`-typed public fields, and for any public signature reaching a `generated/` path. |
| **T2.5** — UTXO family | Address-style selection is `AddressStyle`, not a raw derivation string; a P2WPKH-only v1 rejects `legacy` and `taproot` with `UnsupportedOperationError` until a vector exists (PRD §13.1 *exposed* vs *tested*). |
| **T2.8** — capability matrix | Rows are keyed by the registry `id` (matching `test_vectors/`'s `coin` field), so the matrix, the vector inventory, and the public `Coin.id` share one identifier space. |
| **T3.6 / T3.8** — family helpers | Own the ERC-20 / SPL request builders; no `Asset` type is introduced without reopening this record. |
| **T4.1** — API diff | Gains three registry checks: an `id` that disappeared (must be added to the alias/removal table before the pin PR merges), an `id` whose `coinId` changed (must not silently change the mapping), and a new `id` (informational). |
| **T3.13** — v1 feature table | Lists Bitcoin testnet as *supported through `Network.testnet`* and every other coin's testnet as *not expressible at this upstream tag*. |

## 6. Answers to threat-model questions

`docs/security/threat_model.md` §6 addresses questions 1–3 to DECISION-12 and 4–6 to DECISION-13. None is addressed to this record. Two threat rows depend on it and are answered here:

- **TM-21 (input reaching native unvalidated).** The facade is what makes wrong-network validation expressible: `Address.parse(value, coin: Coin.bitcoin, network: Network.testnet)` names the network, so a mainnet address supplied for a testnet account fails in our layer. Without an explicit `Network` the check has nothing to compare against, because upstream's `TWAnyAddressIsValid` takes only a `TWCoinType` and would accept both.
- **TM-24 (a request carries key material).** `Account` is a descriptor with a public key and no key material and no handle, which is why it can be a request field at all; `Coin` and `Network` are pure data. Nothing in this record's public surface can carry a secret.

## 7. Revisit trigger

Re-open this record when any of the following occurs:

1. **Upstream adds testnet entries as coins or derivations** for chains beyond `bitcoin` and `pactus` — §4.4's availability rule changes shape, and `Network` may need a third member.
2. **Upstream renames or removes a registry `id`** for the first time — §4.3's alias table gets its first entry and the policy is exercised for real rather than asserted.
3. **A `chainId` appears on an `"blockchain": "Ethereum"` entry that is not numeric**, or an EVM coin appears without `chainId` — `Coin.evmChainId`'s `int` type stops being safe.
4. **An application need for `Asset` arrives with a source of truth** (a token list we are willing to ship or a caller-supplied registry) — Option B's asset half becomes evaluable on evidence instead of speculation.
5. **DECISION-7 splits families into separate packages** — `ChainFamily` stops being a value type in one package and becomes a package boundary.
