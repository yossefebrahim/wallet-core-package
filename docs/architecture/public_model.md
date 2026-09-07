# Public model — interface sketch

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

| | |
|---|---|
| **Decision** | [DECISION-11](../decisions/DECISION-11.md) — public coin / network / account model |
| **Binding on** | T1.11 (SDK core), T1.12 (EVM path), T2.5 (UTXO family), T2.8 (capability matrix), T3.6 / T3.8 (family helpers) |
| **Status** | sketch: signatures and doc comments only, no bodies. Its record was **recorded 2026-09-07** (see the linked DECISION file); binding on the tasks named there. |

Everything below belongs to `package:wallet_core_flutter/wallet_core_flutter.dart`. Per AGENTS.md rule 4 and rule 12, no signature here names a foreign-function type, a generated type, or a serialization type; the mapping to upstream's coin identifiers happens one layer down, inside the bindings package, and is described in DECISION-11 §4.2. `Uint8List` (`dart:typed_data`) is a plain Dart value type and is used freely.

---

## 1. `Coin`

```dart
/// A chain this SDK can address, named by upstream's registry id.
///
/// ## Stability policy (DECISION-11 §4.3)
///
/// * [id] is the stable public key of a chain. Persist it, log it, put it in
///   configuration. Ids are **never reused**: once an id has resolved to a chain
///   in a published version, it never names a different chain.
/// * An upstream **rename** keeps the old id resolving, as an alias to the same
///   chain, with [status] reporting [CoinStatus.renamed]. Aliases are never
///   removed within a major version.
/// * An upstream **removal** does not delete the coin. It keeps resolving for at
///   least one minor version with [CoinStatus.removedUpstream]; every operation
///   on it then throws [UnsupportedOperationError]. It disappears from [all]
///   immediately, so iteration reflects the pinned registry.
/// * A coin upstream marks deprecated is reported as [CoinStatus.deprecatedUpstream]
///   and stays fully usable. This SDK never redirects one coin to another.
/// * **Only [id] is stable.** [name], [symbol], [decimals], and every other field
///   are data passed through from the pinned registry and may change at any
///   upstream pin without a semver event on this package.
/// * A new chain appearing upstream is a minor version here. It is reported as
///   *generated* in the capability matrix and never as *tested* until a vector
///   exists.
///
/// The rename and removal rules are not a matter of care at review time. They
/// are enforced by a check on every upstream-pin PR that **fails the PR** when
/// a registry id disappears or is renamed without the corresponding alias or
/// removal entry in the same change, and that check is operational before any
/// pin is merged (DECISION-11 §4.3).
///
/// Whether an operation on a coin actually works is a separate question from
/// whether the coin resolves here, and it is answered only by the capability
/// matrix (`docs/capability_matrix.md`). A `Coin` existing means an id resolves.
final class Coin {
  const Coin._();

  /// Upstream's registry id, e.g. `'bitcoin'`, `'ethereum'`, `'base'`.
  String get id;

  /// Display name from the pinned registry. Not stable across pins.
  String get name;

  /// Ticker symbol from the pinned registry. Not stable across pins.
  String get symbol;

  /// Decimal places of the chain's native unit.
  int get decimals;

  /// Which of this SDK's chain families implements this coin.
  ChainFamily get family;

  /// Lifecycle of this coin relative to the pinned registry.
  CoinStatus get status;

  /// Whether upstream marks this coin deprecated at the pinned tag.
  bool get isDeprecated;

  /// EVM chain id, present only when [family] is [ChainFamily.evm].
  ///
  /// At the pinned tag every EVM coin carries a numeric chain id. Chains whose
  /// identifier is not numeric expose it through [chainIdTag] instead.
  int? get evmChainId;

  /// Non-numeric chain identifier where upstream declares one, e.g. a Cosmos
  /// chain id. `null` for chains that have none.
  String? get chainIdTag;

  /// Networks this coin can be used with at the pinned upstream tag.
  ///
  /// Always contains [Network.mainnet]. It contains [Network.testnet] only when
  /// upstream models a testnet for this coin; at the pinned tag that is true for
  /// very few coins, and it is never true for EVM chains, whose networks are
  /// separate [Coin]s with their own [evmChainId].
  Set<Network> get networks;

  /// Address styles this coin supports at the pinned upstream tag.
  Set<AddressStyle> get addressStyles;

  /// The default BIP-32 derivation path for a (network, style) combination.
  ///
  /// Throws [UnsupportedOperationError] when the combination does not exist
  /// upstream at the pinned tag — see [networks] and [addressStyles].
  String defaultDerivationPath({
    Network network = Network.mainnet,
    AddressStyle style = AddressStyle.standard,
  });

  /// Explorer URL for a transaction id, or `null` when the pinned registry has
  /// no template for this coin. Pure string formatting; performs no network call.
  String? explorerTransactionUrl(String transactionId);

  // --- lookup ---------------------------------------------------------------

  /// Resolves an id, including an alias for a renamed coin. Returns `null` when
  /// the id is unknown at the pinned tag.
  static Coin? find(String id);

  /// Like [find], but throws [UnknownCoinError] instead of returning `null`.
  static Coin byId(String id);

  /// Every coin present in the pinned registry, sorted by [id].
  static List<Coin> get all;

  /// Every coin of one family, sorted by [id].
  static List<Coin> byFamily(ChainFamily family);

  // --- named constants for the families this SDK implements -----------------

  static const Coin bitcoin = Coin._();
  static const Coin ethereum = Coin._();
  static const Coin solana = Coin._();
  // … one constant per coin with a family implementation; every other coin in
  // the registry is reachable through [find] without a code change here.
}

/// Lifecycle of a [Coin] relative to the pinned upstream registry.
enum CoinStatus {
  /// Present in the pinned registry and not marked deprecated upstream.
  active,

  /// Present in the pinned registry and marked deprecated by upstream.
  deprecatedUpstream,

  /// Resolvable through an alias because upstream renamed its id.
  renamed,

  /// No longer present in the pinned registry. Resolvable for at least one
  /// minor version; every operation throws [UnsupportedOperationError].
  removedUpstream,
}
```

## 2. `ChainFamily`

```dart
/// The family whose helpers implement a coin.
///
/// A value type rather than an `enum`, for the same reason as [Coin]: a family
/// can be added in a minor version without breaking an exhaustive `switch` in
/// consumer code. This is *this SDK's* grouping, not upstream's blockchain
/// field, and the two do not correspond one to one.
///
/// **This type is unstable metadata and is never a support claim.** Which family
/// a coin belongs to, and whether that family has request builders, describe how
/// this version of this SDK is organised; both can change in a minor version.
/// Neither tells you whether an operation on a given coin is tested, or works.
/// The capability matrix (`docs/capability_matrix.md`) is the only support claim
/// this project makes, and it is generated per coin and per operation with
/// *exposed*, *generated*, and *tested* distinguished (DECISION-11 §4.5).
final class ChainFamily {
  const ChainFamily._();

  /// Stable id, e.g. `'evm'`, `'utxo'`, `'solana'`.
  String get id;

  /// Whether this SDK ships typed request builders for the family, as opposed to
  /// exposing the coin for address operations only.
  ///
  /// Unstable metadata, and **not a support claim**: it is a fact about the
  /// family, not about any coin in it. A coin in a family with request builders
  /// may still have no vector and no tested operation. Read the capability
  /// matrix to learn what works.
  bool get hasRequestBuilders;

  static const ChainFamily evm = ChainFamily._();
  static const ChainFamily utxo = ChainFamily._();
  static const ChainFamily solana = ChainFamily._();

  /// Coins this SDK exposes for address operations but for which it ships no
  /// request builder at this version.
  ///
  /// Unstable metadata, and **not a support claim** in either direction: a coin
  /// here is not "unsupported" (its addresses work), and a coin leaving this
  /// bucket when a family is implemented is not a promise that any operation on
  /// it is tested. Membership changes as families land, which is a minor version
  /// and not a breaking change. Read the capability matrix to learn what works.
  static const ChainFamily other = ChainFamily._();
}
```

## 3. `Network` and `AddressStyle`

```dart
/// Mainnet or testnet, where upstream distinguishes them.
///
/// Upstream expresses a testnet, when it expresses one at all, as a named
/// derivation on the same coin rather than as a separate coin — so
/// `(Coin.bitcoin, Network.testnet)` is one coin and one derivation, not two
/// coins. EVM networks are the opposite case: each is its own [Coin] with its
/// own [Coin.evmChainId], and `Coin.ethereum.networks` is `{Network.mainnet}`.
///
/// Asking for a network a coin does not have throws [UnsupportedOperationError]
/// before any native call. This SDK never falls back to mainnet.
final class Network {
  const Network._();

  /// `'mainnet'` or `'testnet'`.
  String get id;

  static const Network mainnet = Network._();
  static const Network testnet = Network._();
}

/// The address form to derive, for chains that have more than one.
///
/// Upstream keeps address styles and networks in one list of named derivations;
/// this SDK separates them because they mean different things (DECISION-11 §4.5).
/// [standard] means "whatever the pinned registry uses by default for this coin".
final class AddressStyle {
  const AddressStyle._();

  String get id;

  static const AddressStyle standard = AddressStyle._();
  static const AddressStyle legacy = AddressStyle._();
  static const AddressStyle segwit = AddressStyle._();
  static const AddressStyle taproot = AddressStyle._();
}
```

## 4. `Account` and `Address`

```dart
/// A derived account: a plain descriptor.
///
/// An `Account` owns no native resource, holds no key, and grants no capability.
/// It is immutable, safe to persist, safe to log (it contains no secret), and
/// crosses isolate boundaries by copy. Signing with the key behind an account
/// requires naming that key separately — see `KeyLocator` in
/// [signing.md](signing.md).
final class Account {
  const Account({
    required this.coin,
    required this.network,
    required this.addressStyle,
    required this.derivationPath,
    required this.address,
    required this.publicKey,
  });

  final Coin coin;
  final Network network;
  final AddressStyle addressStyle;

  /// The full BIP-32 path this account was derived at.
  final String derivationPath;

  final Address address;

  /// The account's public key bytes. Never a private key: this SDK's default
  /// surface returns no private key material at all.
  final Uint8List publicKey;
}

/// A validated address for a specific coin and network.
///
/// Construction is the validation: an `Address` instance means the string was
/// accepted for that [coin] and [network] at the pinned upstream tag.
final class Address {
  const Address._();

  /// The address as the chain writes it.
  String get value;

  Coin get coin;
  Network get network;

  /// A cheap, purely local syntax check: length bounds, allowed characters,
  /// expected prefix. It performs **no** checksum verification and no chain
  /// logic, so it can be called at keystroke rate without a round trip.
  /// A `true` result does not mean the address is valid — use
  /// [WalletCore.addresses] for that.
  static bool looksWellFormed(String value, {required Coin coin, Network network = Network.mainnet});
}
```

Full validation and parsing are asynchronous and live on the session, because exactly one isolate per session calls into the native library (DECISION-12 §1):

```dart
/// Address operations for a session. Obtained from `WalletCore.addresses`.
abstract interface class AddressFacade {
  /// Fully validates [value] for [coin] on [network].
  ///
  /// A mainnet address supplied for a testnet account is invalid here, which is
  /// the check an explicit [Network] exists to make possible.
  Future<bool> isValid(String value, {required Coin coin, Network network = Network.mainnet});

  /// Validates and returns an [Address].
  ///
  /// Throws [InvalidInputError] when [value] is not a valid address for
  /// ([coin], [network]).
  Future<Address> parse(String value, {required Coin coin, Network network = Network.mainnet});
}
```

## 5. Errors this file introduces

```dart
/// The requested coin id is not known at the pinned upstream tag, and is not a
/// recognised alias for one that is.
final class UnknownCoinError extends InvalidInputError {
  const UnknownCoinError(this.coinId);
  final String coinId;
}
```

`UnsupportedOperationError(coin, capability)` (PRD §10.2) carries the capability strings this model produces: `'network:testnet'`, `'addressStyle:taproot'`, `'coin:removedUpstream'`.

## 6. Notes on the layer below — **bindings-internal, not public surface**

The following describes the bindings package and is here only so that T1.5 and T1.11 implement the same mapping. **None of it appears in any public signature**, and `lint:public-api` (T1.15) fails the build if it does.

- `Coin.id → coinId → the generated coin-type enum` is one table lookup followed by one enum lookup; the generated enum's numeric value *is* the registry's `coinId` (DECISION-11 §4.2, verified against the pinned headers).
- `(Coin, Network, AddressStyle) → the generated derivation enum` is a second table, built by the registry transform (T1.5) from the pinned registry's named derivation entries. A combination with no entry has no mapping, which is what makes the Dart-side `UnsupportedOperationError` of §3 possible before any call.
- Address validation calls upstream's any-address entry points, which take a coin-type value and, for some chains, an HRP or an SS58 prefix; the facade supplies those from the pinned registry rather than from the caller.
- The alias table of DECISION-11 §4.3 lives in the SDK (`lib/src/coin/aliases.dart`), **not** in a generated directory, because it records ids the current registry no longer contains.
