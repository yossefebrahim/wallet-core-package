/// The UTXO requests the Bitcoin vectors' `input` maps describe, and the raw
/// test keys they name. Every value is read from the inventory
/// (`test_vectors/bitcoin/vectors.yaml`); none is copied into a test.
///
/// **Raw keys are test-only.** The vectors' `private_key` values are upstream's
/// published test keys. They are read here only so that a test can make a
/// `PrivateKeyHandle` from one for the signing-core level; no request holds
/// one, and nothing here is reachable from `lib/`.
library;

import 'dart:typed_data';

import 'package:wallet_core_flutter/src/requests/requests.dart';
import 'package:wallet_core_flutter/src/signing/key_locator.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart'
    show AddressStyle, Coin;

Uint8List unhex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

String hexOf(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// [hex] with its bytes in the opposite order.
String reversedHex(String hex) => hexOf(unhex(hex).reversed.toList());

/// A request from a Bitcoin `plan` or `sign` vector's `input` map, plus the
/// locator that stands for each input's raw key and that key.
///
/// **Byte order of the transaction id.** `p2wpkh` vectors give the id in
/// display order (the test reverses it before it reaches upstream), which is
/// what `OutPoint.transactionId` means. The `multi_input` vectors give the
/// bytes **as upstream's test passed them to `OutPoint()`**, i.e. in the
/// order they appear in the serialized transaction, so [wireOrderTxids]
/// reverses them into display order.
///
/// Every input uses `KeyLocator.imported` over a `KeyRef` issued per distinct
/// raw key: a stand-in for "the key at some path", so equal keys share a
/// locator and the request de-duplicates them.
final class VectorRequest {
  VectorRequest._(this.request, this.keys, this.inputKeys);

  /// The request.
  final UtxoTransactionRequest request;

  /// The raw key (hex) of each distinct locator in the request.
  final Map<KeyLocator, String> keys;

  /// The raw key (hex) of each input, in input order.
  final List<String> inputKeys;

  factory VectorRequest.of(
    Map<dynamic, dynamic> input, {
    bool wireOrderTxids = false,
  }) {
    final locatorOfKey = <String, KeyLocator>{};
    final inputs = <UtxoInput>[];
    final inputKeys = <String>[];
    for (final utxo in input['utxos'] as List<dynamic>) {
      final fields = utxo as Map<dynamic, dynamic>;
      final key = fields['private_key'] as String;
      final locator = locatorOfKey.putIfAbsent(
        key,
        () => KeyLocator.imported(issueKeyRef(locatorOfKey.length + 1)),
      );
      final script = unhex(fields['script_pub_key'] as String);
      final txid = fields['txid'] as String;
      inputs.add(
        UtxoInput(
          outPoint: OutPoint(
            transactionId: wireOrderTxids ? reversedHex(txid) : txid,
            index: int.parse(fields['index'] as String),
          ),
          amount: int.parse(fields['amount'] as String),
          script: script,
          addressStyle: script.length == 22
              ? AddressStyle.segwit
              : AddressStyle.legacy,
          keyLocator: locator,
        ),
      );
      inputKeys.add(key);
    }
    final request = UtxoTransactionRequest(
      coin: Coin.bitcoin,
      toAddress: input['to_address'] as String,
      amount: int.parse(input['amount'] as String),
      feeRatePerByte: int.parse(input['byte_fee'] as String),
      changeAddress: input['change_address'] as String,
      inputs: inputs,
      useMaxAmount: input['use_max_amount'] as bool,
    );
    return VectorRequest._(request, {
      for (final entry in locatorOfKey.entries) entry.value: entry.key,
    }, inputKeys);
  }

  /// The raw key (hex) behind a locator of [request]'s `keyLocators` — the
  /// role-carrying copy — by the role-less locator it was made from.
  String keyOfRoleLocator(KeyLocator roleLocator) {
    final imported = roleLocator as ImportedKeyLocator;
    return keys.entries
        .singleWhere(
          (entry) => (entry.key as ImportedKeyLocator).key == imported.key,
        )
        .value;
  }
}
