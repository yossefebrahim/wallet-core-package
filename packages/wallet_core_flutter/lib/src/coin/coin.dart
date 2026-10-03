/// [Coin] and [CoinStatus]: the stable public name of a chain
/// (DECISION-11 §4.1–§4.4), and the facade-internal mapping onto the generated
/// registry.
///
/// Only [Coin] and [CoinStatus] are public. Everything else declared here is
/// for the SDK's own use, is not exported by
/// `package:wallet_core_flutter/wallet_core_flutter.dart`, and is the only
/// code in the SDK that names the generated `CoinType` (DECISION-11 §4.2,
/// AGENTS.md rule 12).
library;

import 'package:wallet_core_flutter_bindings/registry.dart';

import '../errors/errors.dart';
import 'aliases.dart';
import 'chain_family.dart';
import 'network.dart';

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
///
/// Two coins are equal when their [id]s are, so a coin that crossed an isolate
/// boundary by copy is equal to the constant it was copied from.
final class Coin {
  const Coin._(this.id, this._type, [this._renamedTo, this._removed]);

  /// Upstream's registry id, e.g. `'bitcoin'`, `'ethereum'`, `'base'`.
  final String id;

  /// The generated registry entry behind this coin; `null` only for a coin
  /// upstream removed. Private: the generated type appears in no public
  /// signature.
  final CoinType? _type;

  /// The current id, for a coin resolved through a rename alias.
  final String? _renamedTo;

  /// The last known descriptor, for a coin upstream removed.
  final RemovedCoinRecord? _removed;

  CoinInfo? get _info {
    final type = _type;
    return type == null ? null : coinInfo[type];
  }

  /// Display name from the pinned registry. Not stable across pins.
  String get name => _info?.name ?? _removed!.name;

  /// Ticker symbol from the pinned registry. Not stable across pins.
  String get symbol => _info?.symbol ?? _removed!.symbol;

  /// Decimal places of the chain's native unit.
  int get decimals => _info?.decimals ?? _removed!.decimals;

  /// Which of this SDK's chain families implements this coin.
  ChainFamily get family {
    final info = _info;
    return info == null
        ? familyById(_removed!.familyId)
        : familyOfBlockchain(info.blockchain);
  }

  /// Lifecycle of this coin relative to the pinned registry.
  CoinStatus get status {
    if (_removed != null) return CoinStatus.removedUpstream;
    if (_renamedTo != null) return CoinStatus.renamed;
    if (isDeprecated) return CoinStatus.deprecatedUpstream;
    return CoinStatus.active;
  }

  /// Whether upstream marks this coin deprecated at the pinned tag.
  bool get isDeprecated => _info?.deprecated ?? false;

  /// EVM chain id, present only when [family] is [ChainFamily.evm].
  ///
  /// At the pinned tag every EVM coin carries a numeric chain id. Chains whose
  /// identifier is not numeric expose it through [chainIdTag] instead.
  int? get evmChainId {
    final chainId = _info?.chainId;
    if (chainId == null || family != ChainFamily.evm) return null;
    return int.tryParse(chainId);
  }

  /// Non-numeric chain identifier where upstream declares one, e.g. a Cosmos
  /// chain id. `null` for chains that have none.
  String? get chainIdTag {
    final chainId = _info?.chainId;
    if (chainId == null || evmChainId != null) return null;
    return chainId;
  }

  /// Networks this coin can be used with at the pinned upstream tag.
  ///
  /// Always contains [Network.mainnet]. It contains [Network.testnet] only when
  /// upstream models a testnet for this coin; at the pinned tag that is true for
  /// very few coins, and it is never true for EVM chains, whose networks are
  /// separate [Coin]s with their own [evmChainId].
  Set<Network> get networks {
    final info = _info;
    return Set<Network>.unmodifiable(<Network>{
      Network.mainnet,
      if (info != null && _named(info, _testnetName) != null) Network.testnet,
    });
  }

  /// Address styles this coin supports at the pinned upstream tag.
  Set<AddressStyle> get addressStyles {
    final info = _info;
    return Set<AddressStyle>.unmodifiable(<AddressStyle>{
      AddressStyle.standard,
      if (info != null)
        for (final style in _namedStyles)
          if (_named(info, style.id) != null) style,
    });
  }

  /// The default BIP-32 derivation path for a (network, style) combination.
  ///
  /// Throws [UnsupportedOperationError] when the combination does not exist
  /// upstream at the pinned tag — see [networks] and [addressStyles].
  String defaultDerivationPath({
    Network network = Network.mainnet,
    AddressStyle style = AddressStyle.standard,
  }) => resolveDerivation(this, network, style).path;

  /// Explorer URL for a transaction id, or `null` when the pinned registry has
  /// no template for this coin. Pure string formatting; performs no network call.
  String? explorerTransactionUrl(String transactionId) {
    final explorer = _info?.explorer;
    if (explorer == null || explorer.url.isEmpty) return null;
    return '${explorer.url}${explorer.txPath}$transactionId';
  }

  // --- lookup ---------------------------------------------------------------

  /// Resolves an id, including an alias for a renamed coin. Returns `null` when
  /// the id is unknown at the pinned tag.
  static Coin? find(String id) =>
      resolveCoinId(id, renamed: renamedCoinIds, removed: removedCoins);

  /// Like [find], but throws [UnknownCoinError] instead of returning `null`.
  static Coin byId(String id) => find(id) ?? (throw UnknownCoinError(id));

  /// Every coin present in the pinned registry, sorted by [id].
  static List<Coin> get all => _all;

  /// Every coin of one family, sorted by [id].
  static List<Coin> byFamily(ChainFamily family) =>
      List<Coin>.unmodifiable(_all.where((coin) => coin.family == family));

  // --- named constants for the families this SDK implements -----------------

  /// Bitcoin (`'bitcoin'`).
  static const Coin bitcoin = Coin._('bitcoin', CoinType.bitcoin);

  /// Ethereum mainnet (`'ethereum'`).
  static const Coin ethereum = Coin._('ethereum', CoinType.ethereum);

  /// Solana (`'solana'`).
  static const Coin solana = Coin._('solana', CoinType.solana);

  @override
  bool operator ==(Object other) => other is Coin && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Coin($id)';
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

// --- facade-internal ---------------------------------------------------------
//
// Nothing below is exported from the public barrel.

const String _testnetName = 'testnet';

const List<AddressStyle> _namedStyles = <AddressStyle>[
  AddressStyle.legacy,
  AddressStyle.segwit,
  AddressStyle.taproot,
];

/// Registry ids the generator's identifier normalisation does not invert.
///
/// `gen:registry` names each `CoinType` member by lower-casing the first
/// letter of the registry id and camel-casing at underscores, and emits no
/// field carrying the id itself. Undoing that — snake-casing the member name —
/// recovers every id at the pinned tag except those that start with a capital
/// letter, which are listed here. A test reads the committed copy of the
/// pinned `registry.json` and fails if any of its 167 ids does not round-trip,
/// so a new exception is caught at the pin that introduces it.
const Map<CoinType, String> _registryIdExceptions = <CoinType, String>{
  CoinType.nebl: 'Nebl',
};

/// The upstream registry id of [type].
String registryIdOf(CoinType type) =>
    _registryIdExceptions[type] ??
    type.name.replaceAllMapped(
      RegExp('[A-Z]'),
      (match) => '_${match[0]!.toLowerCase()}',
    );

final Map<String, Coin> _registryCoins = _buildRegistryCoins();

Map<String, Coin> _buildRegistryCoins() {
  const named = <Coin>[Coin.bitcoin, Coin.ethereum, Coin.solana];
  final coins = <String, Coin>{for (final coin in named) coin.id: coin};
  for (final type in CoinType.values) {
    final id = registryIdOf(type);
    coins.putIfAbsent(id, () => Coin._(id, type));
  }
  return Map<String, Coin>.unmodifiable(coins);
}

final List<Coin> _all = List<Coin>.unmodifiable(
  _registryCoins.values.toList()..sort((a, b) => a.id.compareTo(b.id)),
);

/// Resolves [id] against the pinned registry, then the [renamed] aliases, then
/// the [removed] records. The tables are parameters so that the alias and
/// removal paths, empty at the pinned tag, can be tested.
Coin? resolveCoinId(
  String id, {
  required Map<String, String> renamed,
  required Map<String, RemovedCoinRecord> removed,
}) {
  final registered = _registryCoins[id];
  if (registered != null) return registered;
  final renamedTo = renamed[id];
  if (renamedTo != null) {
    final target = _registryCoins[renamedTo];
    if (target != null) return Coin._(id, target._type, renamedTo);
  }
  final record = removed[id];
  if (record != null) return Coin._(id, null, null, record);
  return null;
}

/// The generated registry entry behind [coin].
///
/// Throws [UnsupportedOperationError] with `'coin:removedUpstream'` for a coin
/// upstream removed — the one case with nothing behind it.
CoinType registryCoinTypeOf(Coin coin) =>
    coin._type ??
    (throw UnsupportedOperationError(coin, 'coin:removedUpstream'));

/// The pinned registry's bech32 human-readable part for [coin]'s mainnet
/// addresses, or `null` when the registry declares none.
String? registryHrpOf(Coin coin) => coin._info?.hrp;

/// Bech32 human-readable part of each coin's **testnet** addresses.
///
/// Upstream's registry models a testnet only as a derivation named `testnet`
/// and records no testnet prefix, and upstream's validity checks do not tell
/// the two networks apart consistently, so address validation decides the
/// network by this prefix. One of the hand-maintained tables DECISION-11 §4.7
/// accepts: a test fails when a registry coin offers [Network.testnet]
/// without an entry, and a native test checks each entry against the address
/// upstream itself derives on that testnet.
const Map<String, String> testnetBech32Hrp = <String, String>{
  'bitcoin': 'tb',
  'pactus': 'tpc',
};

/// One registry derivation, resolved from a (coin, network, style) triple.
final class ResolvedDerivation {
  const ResolvedDerivation._({
    required this.name,
    required this.path,
    required this.isDefault,
  });

  /// The registry's name for the derivation, `null` when it has none.
  final String? name;

  /// The registry's default derivation path for it.
  final String path;

  /// Whether this is the coin's first, default derivation — the one upstream
  /// selects with its default derivation value.
  final bool isDefault;
}

/// Resolves ([coin], [network], [style]) to one registry derivation, in Dart,
/// before any native call (DECISION-11 §4.4–§4.5, PRD §16 S5).
///
/// * [Network.testnet] selects the derivation named `testnet`, and only with
///   [AddressStyle.standard].
/// * [AddressStyle.standard] on mainnet selects the coin's first, default
///   derivation; any other style selects the derivation named after it.
///
/// Throws [UnsupportedOperationError] — `'coin:removedUpstream'`,
/// `'network:<id>'`, or `'addressStyle:<id>'` — when there is no such
/// derivation. Nothing ever falls back to mainnet or to the default style.
ResolvedDerivation resolveDerivation(
  Coin coin,
  Network network,
  AddressStyle style,
) {
  final type = registryCoinTypeOf(coin);
  final entries = coinInfo[type]!.derivation;
  if (network == Network.testnet) {
    final testnet = _named(coinInfo[type]!, _testnetName);
    if (testnet == null) {
      throw UnsupportedOperationError(coin, 'network:${network.id}');
    }
    if (style != AddressStyle.standard) {
      throw UnsupportedOperationError(coin, 'addressStyle:${style.id}');
    }
    return ResolvedDerivation._(
      name: testnet.name,
      path: testnet.path,
      isDefault: identical(testnet, entries.first),
    );
  }
  if (network != Network.mainnet) {
    throw UnsupportedOperationError(coin, 'network:${network.id}');
  }
  if (style == AddressStyle.standard) {
    final first = entries.first;
    return ResolvedDerivation._(
      name: first.name,
      path: first.path,
      isDefault: true,
    );
  }
  final named = _namedStyles.contains(style)
      ? _named(coinInfo[type]!, style.id)
      : null;
  if (named == null) {
    throw UnsupportedOperationError(coin, 'addressStyle:${style.id}');
  }
  return ResolvedDerivation._(
    name: named.name,
    path: named.path,
    isDefault: identical(named, entries.first),
  );
}

/// Throws [UnsupportedOperationError] unless [coin] can be used on [network].
void checkNetwork(Coin coin, Network network) {
  registryCoinTypeOf(coin);
  if (!coin.networks.contains(network)) {
    throw UnsupportedOperationError(coin, 'network:${network.id}');
  }
}

Derivation? _named(CoinInfo info, String name) {
  for (final derivation in info.derivation) {
    if (derivation.name == name) return derivation;
  }
  return null;
}
