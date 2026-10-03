/// [ChainFamily]: this SDK's grouping of coins (DECISION-11 §4.5).
library;

/// The family whose helpers implement a coin.
///
/// A value type rather than an `enum`, for the same reason as `Coin`: a family
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
///
/// At this version a coin is in [evm] when the pinned registry's `blockchain`
/// is `Ethereum`, in [utxo] when it is `Bitcoin`, in [solana] when it is
/// `Solana`, and in [other] otherwise.
final class ChainFamily {
  const ChainFamily._(this.id, {required this.hasRequestBuilders});

  /// Stable id, e.g. `'evm'`, `'utxo'`, `'solana'`.
  final String id;

  /// Whether this SDK ships typed request builders for the family, as opposed to
  /// exposing the coin for address operations only.
  ///
  /// Unstable metadata, and **not a support claim**: it is a fact about the
  /// family, not about any coin in it. A coin in a family with request builders
  /// may still have no vector and no tested operation. Read the capability
  /// matrix to learn what works.
  ///
  /// `false` for every family at this version: no request builder has been
  /// written yet.
  final bool hasRequestBuilders;

  /// Chains whose pinned registry entry is an Ethereum-family chain.
  static const ChainFamily evm = ChainFamily._(
    'evm',
    hasRequestBuilders: false,
  );

  /// Bitcoin-family chains.
  static const ChainFamily utxo = ChainFamily._(
    'utxo',
    hasRequestBuilders: false,
  );

  /// Solana.
  static const ChainFamily solana = ChainFamily._(
    'solana',
    hasRequestBuilders: false,
  );

  /// Coins this SDK exposes for address operations but for which it ships no
  /// request builder at this version.
  ///
  /// Unstable metadata, and **not a support claim** in either direction: a coin
  /// here is not "unsupported" (its addresses work), and a coin leaving this
  /// bucket when a family is implemented is not a promise that any operation on
  /// it is tested. Membership changes as families land, which is a minor version
  /// and not a breaking change. Read the capability matrix to learn what works.
  static const ChainFamily other = ChainFamily._(
    'other',
    hasRequestBuilders: false,
  );

  @override
  bool operator ==(Object other) => other is ChainFamily && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ChainFamily($id)';
}

/// The family of a coin whose pinned registry `blockchain` is [blockchain].
/// Internal to the facade.
ChainFamily familyOfBlockchain(String blockchain) => switch (blockchain) {
  'Ethereum' => ChainFamily.evm,
  'Bitcoin' => ChainFamily.utxo,
  'Solana' => ChainFamily.solana,
  _ => ChainFamily.other,
};

/// The family whose [ChainFamily.id] is [id], for the records of
/// `aliases.dart`. Internal to the facade.
ChainFamily familyById(String id) => switch (id) {
  'evm' => ChainFamily.evm,
  'utxo' => ChainFamily.utxo,
  'solana' => ChainFamily.solana,
  _ => ChainFamily.other,
};
