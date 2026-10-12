part of 'requests.dart';

/// Base of every transaction request.
sealed class TransactionRequest {
  /// The coin the transaction is for.
  Coin get coin;

  /// The network the transaction is for.
  Network get network;

  /// Every locator this request needs, collected from wherever they appear in
  /// it. For most families this is empty and the caller supplies the set; for
  /// UTXO it is the per-input locators.
  Set<KeyLocator> get keyLocators;
}

/// Base of every message-signing request. No member exists at this version;
/// EVM messages are T2.7's.
sealed class MessageRequest {
  /// The coin whose message format and key the request is for.
  Coin get coin;
}

/// A transaction output, named by the id of the transaction that created it
/// and its position in that transaction's outputs
/// (`docs/architecture/signing.md` §3.2).
///
/// **Validated at construction**: [transactionId] is 64 hexadecimal digits and
/// [index] fits an unsigned 32-bit integer, else [InvalidInputError] naming the
/// input. A pure value; whether the output exists is not this type's to know.
final class OutPoint {
  /// Names output [index] of the transaction [transactionId].
  ///
  /// [transactionId] is kept as written; the byte order upstream wants is the
  /// UTXO family's to apply (T2.5).
  OutPoint({required this.transactionId, required this.index}) {
    if (!_txidSyntax.hasMatch(transactionId)) {
      throw const InvalidInputError(
        'transactionId must be 64 hexadecimal digits',
        inputName: 'transactionId',
      );
    }
    if (index < 0 || index > 0xFFFFFFFF) {
      throw const InvalidInputError(
        'index must fit an unsigned 32-bit integer',
        inputName: 'index',
      );
    }
  }

  /// The creating transaction's id, 64 hexadecimal digits.
  final String transactionId;

  /// The position among that transaction's outputs.
  final int index;

  @override
  bool operator ==(Object other) =>
      other is OutPoint &&
      other.transactionId.toLowerCase() == transactionId.toLowerCase() &&
      other.index == index;

  @override
  int get hashCode => Object.hash(transactionId.toLowerCase(), index);

  @override
  String toString() => 'OutPoint($transactionId:$index)';
}

final RegExp _txidSyntax = RegExp(r'^[0-9a-fA-F]{64}$');

/// One transaction input, and the name of the key that can spend it
/// (`docs/architecture/signing.md` §3.2, DECISION-13 §4.3).
///
/// **A pure value.** It holds an outpoint, an amount, the locking script of
/// the output being spent, an address style, and a [KeyLocator]; a locator is a
/// name, not key material, and nothing here can hold a key. The locator lives
/// on the input because that is where the caller knows it: the UTXO was chosen
/// because it belongs to a particular derivation path. It never reaches
/// upstream, which has nowhere to put it and matches keys to inputs by script;
/// the signer turns the locators of the inputs into key roles
/// (`KeyRole.input(n)`) and derives the keys (T2.5).
///
/// **Validated at construction**: [amount] must not be negative
/// ([InvalidInputError], `inputName: 'amount'`). [script] is copied on the way
/// in and exposed as a read-only view; whether it is a script this SDK can
/// sign for is the UTXO family's to judge.
final class UtxoInput {
  /// An input spending [outPoint], worth [amount] in the coin's smallest unit,
  /// locked by [script], of [addressStyle], spendable with the key [keyLocator]
  /// names.
  UtxoInput({
    required this.outPoint,
    required this.amount,
    required Uint8List script,
    required this.addressStyle,
    required this.keyLocator,
  }) : _script = Uint8List.fromList(script) {
    if (amount < 0) {
      throw const InvalidInputError(
        'amount must not be negative',
        inputName: 'amount',
      );
    }
  }

  /// The output being spent.
  final OutPoint outPoint;

  /// The value of that output, in the coin's smallest unit.
  final int amount;

  final Uint8List _script;

  /// The locking script of the output being spent. A read-only view; the input
  /// keeps its own copy.
  Uint8List get script => _script.asUnmodifiableView();

  /// The address form the output was paid to; selects the script type the
  /// family signs it as.
  final AddressStyle addressStyle;

  /// The name of the key that can spend this output. Not the key.
  final KeyLocator keyLocator;

  @override
  bool operator ==(Object other) {
    if (other is! UtxoInput ||
        other.outPoint != outPoint ||
        other.amount != amount ||
        other.addressStyle != addressStyle ||
        other.keyLocator != keyLocator ||
        other._script.length != _script.length) {
      return false;
    }
    for (var i = 0; i < _script.length; i++) {
      if (other._script[i] != _script[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    outPoint,
    amount,
    addressStyle,
    keyLocator,
    Object.hashAll(_script),
  );

  /// The outpoint, amount, script *length*, style, and locator name.
  @override
  String toString() =>
      'UtxoInput($outPoint, $amount, script: ${_script.length} bytes, '
      '$addressStyle, $keyLocator)';
}
