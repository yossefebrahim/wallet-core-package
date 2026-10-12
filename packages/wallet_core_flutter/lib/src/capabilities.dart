/// What this SDK exposes today: the *Exposed* column of the capability matrix
/// (PRD §13.1, T2.8).
///
/// Internal. Not exported by `package:wallet_core_flutter/wallet_core_flutter.dart`
/// and never part of a public signature. It is a hand-maintained table, one of
/// the few the project accepts, and it is held to the code by
/// `test/capabilities_test.dart`: every coin the facade accepts for a path
/// appears, and no entry names a coin the facade rejects.
///
/// `docs/capability_exposed.json` is a snapshot of [capabilityGroups] that the
/// same test keeps byte-identical to this file. `tools/matrix` reads the
/// snapshot, never this Dart source and never the SDK package, so changing
/// what the SDK exposes is: edit this file, run
/// `flutter test --dart-define=WCF_UPDATE_CAPABILITY_SNAPSHOT=true test/capabilities_test.dart`
/// in `packages/wallet_core_flutter`, then `melos run gen:matrix`.
///
/// An operation that is absent here is not exposed. Message signing
/// (`LocalSigner.signMessage` throws `UnsupportedOperationError`), UTXO
/// planning, and external-signature compilation have no entry because the SDK
/// has no path to them at this version.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
library;

/// How the public SDK reaches an operation.
enum Exposure {
  /// A typed request or facade method (`EvmTransactionRequest`,
  /// `AddressFacade`, `Wallet`).
  typed,

  /// A generic path that takes serialized input (`advanced.dart`). Nothing at
  /// this version.
  generic,
}

/// One (operation, variant) the SDK exposes, for [coins] (or for every coin of
/// the pinned registry when [coins] is `null`).
final class CapabilityGroup {
  const CapabilityGroup({
    required this.operation,
    required this.variant,
    required this.exposure,
    this.coins,
  });

  /// One of the matrix operations: `address`, `sign`, `sign_message`, `plan`,
  /// `compile`.
  final String operation;

  /// A variant of the operation, `n/a` for `address`. The variant names are the
  /// ones of `test_vectors/README.md`.
  final String variant;

  final Exposure exposure;

  /// Registry ids (`Coin.id`), sorted; `null` means every coin in the pinned
  /// registry.
  final List<String>? coins;
}

/// The registry ids of the coins whose `Coin.family` is `ChainFamily.evm` at
/// the pinned tag — every coin `EvmTransactionRequest` accepts.
const List<String> evmCoinIds = <String>[
  'acalaevm',
  'arbitrum',
  'arbitrumnova',
  'aurora',
  'avalanchec',
  'base',
  'blast',
  'boba',
  'bouncebit',
  'bsc',
  'callisto',
  'celo',
  'cfxevm',
  'classic',
  'cronos',
  'ethereum',
  'evmos',
  'fantom',
  'gochain',
  'heco',
  'hyperevm',
  'iotexevm',
  'kaia',
  'kavaevm',
  'kcc',
  'lightlink',
  'linea',
  'manta',
  'mantle',
  'megaeth',
  'merlin',
  'meter',
  'metis',
  'monad',
  'moonbeam',
  'moonriver',
  'neon',
  'okc',
  'opbnb',
  'optimism',
  'plasma',
  'poa',
  'polygon',
  'polygonzkevm',
  'robinhoodchain',
  'rootstock',
  'scroll',
  'seievm',
  'smartbch',
  'smartchain',
  'sonic',
  'tfuelevm',
  'thundertoken',
  'viction',
  'wanchain',
  'xdai',
  'zeneon',
  'zetaevm',
  'zklinknova',
  'zksync',
];

/// Everything the SDK exposes, grouped by (operation, variant).
const List<CapabilityGroup> capabilityGroups = <CapabilityGroup>[
  // Address derivation (`Wallet.derive`) and validation (`AddressFacade`) take
  // any coin of the pinned registry; a coin upstream removed is not in it.
  CapabilityGroup(
    operation: 'address',
    variant: 'n/a',
    exposure: Exposure.typed,
  ),
  // `EvmTransactionRequest.contractCall`: an EIP-1559 call carrying data.
  CapabilityGroup(
    operation: 'sign',
    variant: 'contract_call',
    exposure: Exposure.typed,
    coins: evmCoinIds,
  ),
  // `EvmTransactionRequest.transfer`.
  CapabilityGroup(
    operation: 'sign',
    variant: 'eip1559',
    exposure: Exposure.typed,
    coins: evmCoinIds,
  ),
  // `EvmTransactionRequest.legacyTransfer`.
  CapabilityGroup(
    operation: 'sign',
    variant: 'legacy',
    exposure: Exposure.typed,
    coins: evmCoinIds,
  ),
];
