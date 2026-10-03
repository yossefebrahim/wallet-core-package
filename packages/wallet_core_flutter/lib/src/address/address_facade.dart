/// [AddressFacade]: full address validation, through the session
/// (`docs/architecture/public_model.md` §4).
library;

import '../coin/coin.dart';
import '../coin/network.dart';
import '../errors/errors.dart';
import '../session/session.dart';
import '../worker/protocol.dart';
import 'address.dart';

/// Address operations for a session. Obtained from `WalletCore.addresses`.
///
/// Asynchronous because exactly one isolate per session calls into the
/// native library, even for a stateless check (DECISION-12 §1). For a check
/// at keystroke rate, [Address.looksWellFormed] answers locally.
abstract interface class AddressFacade {
  /// Fully validates [value] for [coin] on [network].
  ///
  /// A mainnet address supplied for a testnet account is invalid here, which
  /// is the check an explicit [Network] exists to make possible. Throws
  /// [UnsupportedOperationError] when [coin] has no [network], before
  /// anything crosses.
  Future<bool> isValid(
    String value, {
    required Coin coin,
    Network network = Network.mainnet,
  });

  /// Validates and returns an [Address].
  ///
  /// Throws [InvalidInputError] (`inputName: 'address'`) when [value] is not a
  /// valid address for ([coin], [network]).
  Future<Address> parse(
    String value, {
    required Coin coin,
    Network network = Network.mainnet,
  });
}

/// The [AddressFacade] of [WalletCoreSession]. **Internal.**
final class AddressFacadeImpl implements AddressFacade {
  /// Creates the facade over [session].
  AddressFacadeImpl(this._session);

  final WalletCoreSession _session;

  @override
  Future<bool> isValid(
    String value, {
    required Coin coin,
    Network network = Network.mainnet,
  }) async {
    checkNetwork(coin, network);
    return _session.submit(
      (id) => ValidateAddress(id, value: value, coin: coin, network: network),
      timeout: _session.timeouts.derivation,
      parse: (reply) => switch (reply) {
        AddressValidated(:final isValid) => isValid,
        _ => throw StateError('unexpected reply ${reply.runtimeType}'),
      },
    );
  }

  @override
  Future<Address> parse(
    String value, {
    required Coin coin,
    Network network = Network.mainnet,
  }) async {
    if (!await isValid(value, coin: coin, network: network)) {
      throw InvalidInputError(
        'not a valid ${coin.id} address on ${network.id}',
        inputName: 'address',
      );
    }
    return validatedAddress(value, coin, network);
  }
}
