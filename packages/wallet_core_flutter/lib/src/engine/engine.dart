/// [WalletEngine]: the synchronous, single-isolate core every session
/// operation runs on. **Internal**: never exported from
/// `package:wallet_core_flutter/wallet_core_flutter.dart`.
///
/// The session (T1.11b) calls this from the message loop of the isolate that
/// owns the handles, and converts each result into a sendable reply. Every
/// method is synchronous, every result is a plain immutable Dart value — a
/// `String`, a `bool`, an [Account], an [Address] — or the one handle type
/// the session keeps in its reference table, [HDWallet].
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart'
    hide DisposedError;

import '../account/account.dart';
import '../address/address.dart';
import '../coin/chain_family.dart';
import '../coin/coin.dart';
import '../coin/network.dart';
import '../core/input_checks.dart';
import '../errors/boundary.dart';
import '../errors/errors.dart';
import 'coin_bridge.dart';
import 'handles.dart';
import 'hd_wallet.dart';
import 'secret_buffers.dart';

/// The native operations of one session, over one [NativeContext].
///
/// Constructed in, and used only from, the isolate that loaded the library:
/// the [HDWallet]s it returns belong to that isolate (DECISION-12 §1).
/// Nothing here is retained between calls — no secret, no temporary, no
/// handle other than the wallets it hands back.
final class WalletEngine {
  /// Creates an engine over an already loaded [context].
  WalletEngine(this.context);

  /// The loaded library, its bindings, and the observer its handles report to.
  final NativeContext context;

  // --- wallets --------------------------------------------------------------

  /// Creates a wallet with a new random mnemonic; see [HDWallet.create].
  HDWallet createWallet({int strength = 128, String passphrase = ''}) =>
      HDWallet.create(context, strength: strength, passphrase: passphrase);

  /// Imports a wallet from a mnemonic; see [HDWallet.fromMnemonic].
  HDWallet importMnemonic(String mnemonic, {String passphrase = ''}) =>
      HDWallet.fromMnemonic(context, mnemonic, passphrase: passphrase);

  /// Imports a wallet from entropy; see [HDWallet.fromEntropy].
  HDWallet importEntropy(Uint8List entropy, {String passphrase = ''}) =>
      HDWallet.fromEntropy(context, entropy, passphrase: passphrase);

  /// The mnemonic of [wallet]; see [HDWallet.exportMnemonic].
  String exportMnemonic(HDWallet wallet) => wallet.exportMnemonic();

  /// Derives an account from [wallet]; see [HDWallet.deriveAccount].
  Account deriveAccount(
    HDWallet wallet,
    Coin coin, {
    Network network = Network.mainnet,
    AddressStyle style = AddressStyle.standard,
    String? path,
  }) => wallet.deriveAccount(coin, network: network, style: style, path: path);

  // --- addresses ------------------------------------------------------------

  /// Whether [value] is a valid address for [coin] on [network], by upstream's
  /// `TWAnyAddress` checks plus the network's address prefix.
  ///
  /// Upstream's checks alone cannot tell the networks apart: at the pinned tag
  /// `TWAnyAddressIsValid` rejects a Bitcoin testnet address but accepts a
  /// Pactus one, and `TWAnyAddressIsValidBech32` accepts a Bitcoin testnet
  /// address but rejects every Pactus address. So the network is decided here,
  /// by the address's bech32 prefix, and upstream decides validity:
  ///
  /// * On [Network.testnet] the address must start with the coin's testnet
  ///   prefix and be accepted by `TWAnyAddressIsValid` or by
  ///   `TWAnyAddressIsValidBech32` with that prefix.
  /// * On [Network.mainnet] it must be accepted by `TWAnyAddressIsValid` and
  ///   must not carry the coin's testnet prefix.
  ///
  /// A mainnet address supplied for a testnet account is therefore rejected,
  /// and the reverse — the check an explicit network exists to make possible
  /// (DECISION-11 §6, TM-21).
  ///
  /// Throws [UnsupportedOperationError] when [coin] has no [network], before
  /// any native call. An empty or over-long [value], or one that is not
  /// [isNativeSafeString], is simply not valid and never reaches native code.
  bool isValidAddress(
    String value,
    Coin coin, {
    Network network = Network.mainnet,
  }) {
    checkNetwork(coin, network);
    final coinType = twCoinTypeOf(coin);
    if (value.isEmpty || value.length > maxAddressLength) return false;
    // A NUL would end the C string early and let a valid prefix vouch for the
    // whole text; an unpaired surrogate would reach upstream as U+FFFD.
    if (!isNativeSafeString(value)) return false;
    final testnetHrp = testnetBech32Hrp[coin.id];
    final hasTestnetPrefix =
        testnetHrp != null && value.toLowerCase().startsWith('${testnetHrp}1');
    if (network == Network.testnet && !hasTestnetPrefix) return false;
    if (network == Network.mainnet && hasTestnetPrefix) return false;
    final bindings = context.bindings;
    return runScope(context, (scope) {
      final address = _string(scope, value);
      if (bindings.TWAnyAddressIsValid(address.pointer, coinType)) return true;
      if (network != Network.testnet) return false;
      return bindings.TWAnyAddressIsValidBech32(
        address.pointer,
        coinType,
        _string(scope, testnetHrp!).pointer,
      );
    });
  }

  /// Validates [value] for [coin] on [network] and returns it as an
  /// [Address].
  ///
  /// Throws [InvalidInputError] (`inputName: 'address'`) when it is not
  /// valid, and [UnsupportedOperationError] when [coin] has no [network].
  Address parseAddress(
    String value,
    Coin coin, {
    Network network = Network.mainnet,
  }) {
    if (!isValidAddress(value, coin, network: network)) {
      throw InvalidInputError(
        'not a valid ${coin.id} address on ${network.id}',
        inputName: 'address',
      );
    }
    return validatedAddress(value, coin, network);
  }

  /// Rejects [value] as the recipient of a transaction on [coin] with
  /// [InvalidInputError] (`inputName: 'to'`) unless upstream accepts it.
  ///
  /// Two checks, both upstream's:
  ///
  /// 1. [isValidAddress] on [network].
  /// 2. For an EVM coin, the EIP-55 checksum. Upstream's `TWAnyAddressIsValid`
  ///    checks an EVM address's length and hex digits only — at the pinned
  ///    commit neither `Ethereum::Address::isValid` nor `tw_evm`'s parser
  ///    reads its letter case — so a mistyped mixed-case address would be
  ///    signed. Following EIP-55, an address written in one case asserts no
  ///    checksum and passes; one in mixed case must equal, character for
  ///    character, the form upstream renders for it (`TWAnyAddressDescription`,
  ///    which applies the checksum). The checksum's hash is computed by
  ///    upstream; this only compares two strings.
  ///
  /// Throws [UnsupportedOperationError] when [coin] has no [network].
  void checkRecipient(
    String value,
    Coin coin, {
    Network network = Network.mainnet,
  }) {
    if (!isValidAddress(value, coin, network: network)) {
      throw InvalidInputError(
        'not a valid ${coin.id} address on ${network.id}',
        inputName: 'to',
      );
    }
    if (coin.family != ChainFamily.evm || !_hasMixedCase(value)) return;
    final coinType = twCoinTypeOf(coin);
    final bindings = context.bindings;
    final rendered = runScope(context, (scope) {
      final pointer = bindings.TWAnyAddressCreateWithString(
        _string(scope, value).pointer,
        coinType,
      );
      if (pointer == nullptr) return null;
      final address = scope.use(AnyAddressHandle.adopt(context, pointer));
      final description = bindings.TWAnyAddressDescription(address.pointer);
      if (description == nullptr) return null;
      final text = scope.use(TWStringHandle.adopt(context, description));
      return readNative('TWAnyAddressDescription', text.toDartString);
    });
    if (rendered != value) {
      throw InvalidInputError(
        'the mixed-case ${coin.id} address does not match its EIP-55 checksum',
        inputName: 'to',
      );
    }
  }

  // --- mnemonics ------------------------------------------------------------

  /// Whether [mnemonic] is a valid BIP-39 English mnemonic, by upstream's
  /// `TWMnemonicIsValid`.
  ///
  /// A text with the wrong number of words, over the length ceiling, or not
  /// [isNativeSafeString] is not valid and never reaches native code. Never
  /// throws for any input.
  bool isValidMnemonic(String mnemonic) {
    if (!mnemonicHasPlausibleShape(mnemonic)) return false;
    final handle = secretString(context, mnemonic, inputName: 'mnemonic');
    try {
      return context.bindings.TWMnemonicIsValid(handle.pointer);
    } finally {
      handle.dispose();
    }
  }

  /// Whether [word] is in the BIP-39 English word list, by upstream's
  /// `TWMnemonicIsValidWord`. A word that is not [isNativeSafeString] is not
  /// valid. Never throws for any input.
  bool isValidMnemonicWord(String word) {
    if (word.isEmpty || word.length > maxMnemonicWordLength) return false;
    if (!isNativeSafeString(word)) return false;
    final handle = secretString(context, word, inputName: 'word');
    try {
      return context.bindings.TWMnemonicIsValidWord(handle.pointer);
    } finally {
      handle.dispose();
    }
  }

  /// The BIP-39 English words that start with [prefix], by upstream's
  /// `TWMnemonicSuggest`, in upstream's order.
  ///
  /// Upstream caps how many words it suggests, so this is a typing aid, not
  /// access to the whole list; upstream exposes no other word-list access.
  /// A prefix that cannot begin a word — empty, longer than
  /// [maxMnemonicWordLength], or containing anything but `a`–`z` — yields an
  /// empty list without a native call.
  List<String> suggestMnemonicWords(String prefix) {
    if (prefix.isEmpty || prefix.length > maxMnemonicWordLength) {
      return const <String>[];
    }
    for (var i = 0; i < prefix.length; i++) {
      final unit = prefix.codeUnitAt(i);
      if (unit < 0x61 || unit > 0x7A) return const <String>[];
    }
    return runScope(context, (scope) {
      final input = scope.use(
        secretString(context, prefix, inputName: 'prefix'),
      );
      final pointer = context.bindings.TWMnemonicSuggest(input.pointer);
      if (pointer == nullptr) return const <String>[];
      final suggestions = scope.use(TWStringHandle.adopt(context, pointer));
      final text = readSecretString(suggestions);
      return List<String>.unmodifiable(
        text.split(' ').where((word) => word.isNotEmpty),
      );
    });
  }
}

/// A native copy of the public text [value], registered with [scope]; a null
/// from upstream is a `NativeResultError` (DECISION-12 §3.10).
TWStringHandle _string(ResourceScope scope, String value) =>
    readNative('TWStringCreateWithUTF8Bytes', () => scope.string(value));

/// Whether [value], after a leading `0x`, contains both a lower-case and an
/// upper-case ASCII letter. The prefix's `x` is not a digit and asserts
/// nothing about case.
bool _hasMixedCase(String value) {
  var lower = false;
  var upper = false;
  final digits = value.startsWith('0x') ? value.substring(2) : value;
  for (final unit in digits.codeUnits) {
    if (unit >= 0x61 && unit <= 0x7A) lower = true;
    if (unit >= 0x41 && unit <= 0x5A) upper = true;
  }
  return lower && upper;
}
