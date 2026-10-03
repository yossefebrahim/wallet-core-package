/// [Network] and [AddressStyle]: the two axes DECISION-11 §4.4 and §4.5 split
/// upstream's single list of named derivations into.
library;

/// Mainnet or testnet, where upstream distinguishes them.
///
/// Upstream expresses a testnet, when it expresses one at all, as a named
/// derivation on the same coin rather than as a separate coin — so
/// `(Coin.bitcoin, Network.testnet)` is one coin and one derivation, not two
/// coins. EVM networks are the opposite case: each is its own `Coin` with its
/// own `Coin.evmChainId`, and `Coin.ethereum.networks` is `{Network.mainnet}`.
///
/// Asking for a network a coin does not have throws `UnsupportedOperationError`
/// before any native call. This SDK never falls back to mainnet.
///
/// A value type rather than an `enum`, so that a network can be added in a
/// minor version without breaking an exhaustive `switch` in consumer code.
/// Two instances are equal when their [id]s are, which is what keeps a value
/// that crossed an isolate boundary by copy equal to the constant it was.
final class Network {
  const Network._(this.id);

  /// `'mainnet'` or `'testnet'`.
  final String id;

  /// The network every coin has.
  static const Network mainnet = Network._('mainnet');

  /// The test network, for the few coins upstream models one for.
  static const Network testnet = Network._('testnet');

  @override
  bool operator ==(Object other) => other is Network && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Network($id)';
}

/// The address form to derive, for chains that have more than one.
///
/// Upstream keeps address styles and networks in one list of named derivations;
/// this SDK separates them because they mean different things (DECISION-11 §4.5).
/// [standard] means "whatever the pinned registry uses by default for this coin".
///
/// Equal by [id], like [Network].
final class AddressStyle {
  const AddressStyle._(this.id);

  /// `'standard'`, `'legacy'`, `'segwit'`, or `'taproot'`.
  final String id;

  /// The pinned registry's default address form for the coin.
  static const AddressStyle standard = AddressStyle._('standard');

  /// The registry derivation named `legacy` (e.g. Bitcoin P2PKH).
  static const AddressStyle legacy = AddressStyle._('legacy');

  /// The registry derivation named `segwit`.
  static const AddressStyle segwit = AddressStyle._('segwit');

  /// The registry derivation named `taproot`.
  static const AddressStyle taproot = AddressStyle._('taproot');

  @override
  bool operator ==(Object other) => other is AddressStyle && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'AddressStyle($id)';
}
