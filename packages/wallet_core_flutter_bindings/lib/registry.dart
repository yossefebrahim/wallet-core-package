/// The generated coin registry of the pinned upstream tag.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// Exports the `CoinType` enum and the `coinInfo` metadata table that
/// `melos run gen:registry` produces from upstream's `registry.json`
/// (PRD §9), together with the record types the table is built from. All of it
/// is regenerated at every upstream pin and is never hand-edited.
///
/// This is **not** public SDK surface. The default import of the SDK,
/// `package:wallet_core_flutter/wallet_core_flutter.dart`, never names
/// `CoinType` in a signature: it exposes the stable coin facade of
/// DECISION-11 and maps it onto this registry internally, so that an upstream
/// rename or removal is absorbed by that mapping rather than landing in a
/// consumer's code (PRD §8, AGENTS.md rule 12). This library reaches a
/// consumer only through `package:wallet_core_flutter/advanced.dart` or by
/// depending on this package directly.
///
/// `CoinType.coinId` is upstream's numeric coin id, the same value the
/// generated foreign-function enum `TWCoinType` carries, so the bridge between
/// the two is `TWCoinType.fromValue(coinType.coinId)`.
library;

export 'src/generated/registry/coin_info.dart'
    show CoinInfo, Derivation, Explorer, coinInfo;
export 'src/generated/registry/coin_type.dart' show CoinType;
