/// [Address]: a validated address for one coin and network
/// (`docs/architecture/public_model.md` §4).
library;

import '../coin/chain_family.dart';
import '../coin/coin.dart';
import '../coin/network.dart';
import '../core/input_checks.dart';

/// A validated address for a specific coin and network.
///
/// Construction is the validation: an `Address` instance means the string was
/// accepted for that [coin] and [network] at the pinned upstream tag. There is
/// no public constructor; addresses come from the SDK's validation and
/// derivation paths only.
///
/// Two addresses are equal when their [value], [coin], and [network] are.
final class Address {
  const Address._(this.value, this.coin, this.network);

  /// The address as the chain writes it.
  final String value;

  /// The coin the address was validated for.
  final Coin coin;

  /// The network the address was validated for.
  final Network network;

  /// A cheap, purely local syntax check: length bounds, allowed characters,
  /// expected prefix. It performs **no** checksum verification and no chain
  /// logic, so it can be called at keystroke rate without a round trip.
  /// A `true` result does not mean the address is valid — use
  /// `WalletCore.addresses` for that.
  ///
  /// The check is deliberately permissive: it is a filter for obvious
  /// mistakes, and a chain it knows nothing specific about only has its length
  /// and characters checked. It is never stricter than upstream.
  ///
  /// Throws `UnsupportedOperationError` when [coin] has no [network] at the
  /// pinned upstream tag, like every other operation that names a network.
  static bool looksWellFormed(
    String value, {
    required Coin coin,
    Network network = Network.mainnet,
  }) {
    checkNetwork(coin, network);
    if (value.isEmpty || value.length > maxAddressLength) return false;
    if (value.trim() != value) return false;
    for (var i = 0; i < value.length; i++) {
      final unit = value.codeUnitAt(i);
      if (unit < 0x20 || unit == 0x7F) return false;
    }
    final testnetHrp = testnetBech32Hrp[coin.id];
    if (network == Network.testnet) {
      return testnetHrp != null && _looksBech32(value, testnetHrp);
    }
    if (testnetHrp != null &&
        value.toLowerCase().startsWith('${testnetHrp}1')) {
      return false;
    }
    final family = coin.family;
    if (family == ChainFamily.evm) return _evmAddress.hasMatch(value);
    if (family == ChainFamily.solana) return _looksBase58(value, 32, 44);
    if (family == ChainFamily.utxo) {
      final hrp = registryHrpOf(coin);
      if (hrp != null && value.toLowerCase().startsWith('${hrp}1')) {
        return _looksBech32(value, hrp);
      }
      return _looksBase58(value, 25, 62);
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is Address &&
      other.value == value &&
      other.coin == coin &&
      other.network == network;

  @override
  int get hashCode => Object.hash(value, coin, network);

  /// The address itself. An address is public data.
  @override
  String toString() => value;
}

/// Creates an [Address] the SDK has already validated for ([coin], [network])
/// — by upstream's validity check or because upstream derived it.
/// **Internal**: never exported, which is what keeps "construction is the
/// validation" true.
Address validatedAddress(String value, Coin coin, Network network) =>
    Address._(value, coin, network);

final RegExp _evmAddress = RegExp(r'^0x[0-9a-fA-F]{40}$');

const String _bech32Charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

const String _base58Charset =
    '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

/// `<hrp>1<data>` in one case, with data from the bech32 alphabet and at least
/// the six checksum characters. The checksum itself is not verified.
bool _looksBech32(String value, String hrp) {
  final lower = value.toLowerCase();
  if (value != lower && value != value.toUpperCase()) return false;
  final prefix = '${hrp}1';
  if (!lower.startsWith(prefix)) return false;
  final data = lower.substring(prefix.length);
  if (data.length < 6) return false;
  for (var i = 0; i < data.length; i++) {
    if (!_bech32Charset.contains(data[i])) return false;
  }
  return true;
}

bool _looksBase58(String value, int minLength, int maxLength) {
  if (value.length < minLength || value.length > maxLength) return false;
  for (var i = 0; i < value.length; i++) {
    if (!_base58Charset.contains(value[i])) return false;
  }
  return true;
}
