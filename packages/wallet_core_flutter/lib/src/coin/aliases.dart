/// The coin alias and removal table of DECISION-11 §4.3. **Hand-written, not
/// generated**, and internal to the facade.
///
/// ## Policy
///
/// * **Ids are never reused.** Once an id has resolved to a chain in a
///   published version, it never names a different chain.
/// * **An upstream rename keeps the old id as an alias.** When upstream renames
///   `id: "foo"` to `id: "bar"`, the pin PR adds `'foo': 'bar'` to
///   [renamedCoinIds]. `Coin.find('foo')` then keeps resolving, to the same
///   chain, with `CoinStatus.renamed`. An alias is never removed within a major
///   version.
/// * **An upstream removal deprecates, it does not delete.** When an id
///   disappears from the registry, the pin PR adds its last known descriptor to
///   [removedCoins]. The coin keeps resolving for at least one minor version
///   with `CoinStatus.removedUpstream`; every operation on it throws
///   `UnsupportedOperationError(coin, 'coin:removedUpstream')`, and it leaves
///   `Coin.all` immediately.
///
/// This file lives outside every generated directory because its content is a
/// historical record the current registry no longer contains. Both tables are
/// empty at upstream 4.8.0 (commit `d692ac27749d0c615e17c751b70ab4f0aa75c59b`):
/// no id has yet been renamed or removed since the facade was introduced. The
/// check that fails a pin PR which drops or renames an id without the matching
/// entry here is DECISION-11 §4.3 rule 7's, owned by T4.1.
library;

/// Old registry id → the current registry id it was renamed to.
const Map<String, String> renamedCoinIds = <String, String>{};

/// Registry id no longer present upstream → its last known descriptor.
const Map<String, RemovedCoinRecord> removedCoins =
    <String, RemovedCoinRecord>{};

/// What the facade still knows about a coin upstream removed.
///
/// Enough to describe the coin and nothing to operate on it with: there is no
/// upstream coin type behind it any more.
final class RemovedCoinRecord {
  /// Records the descriptor a removed coin last had.
  const RemovedCoinRecord({
    required this.name,
    required this.symbol,
    required this.decimals,
    required this.familyId,
  });

  /// Display name at the last pin that had the coin.
  final String name;

  /// Ticker symbol at the last pin that had the coin.
  final String symbol;

  /// Decimal places of the native unit at the last pin that had the coin.
  final int decimals;

  /// The `ChainFamily.id` the coin belonged to.
  final String familyId;
}
