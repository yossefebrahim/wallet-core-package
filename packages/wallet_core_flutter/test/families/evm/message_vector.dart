/// The EVM message vectors, and the requests their `input` maps describe.
/// Every value is read from the inventory (`test_vectors/ethereum/vectors.yaml`)
/// and none is copied into a test.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:wallet_core_flutter/src/requests/requests.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart' show Coin;

import '../../support/fixtures.dart';

/// `TEST(TWEthereumMessageSigner, SignAndVerifyLegacy)`: `"Foo"`.
const String personalVectorId = 'ethereum-sign_message-personal-1';

/// `TEST(TWEthereumEip712, SignMessageAndVerifyLegacy)`: a `Person` document.
const String typedDataVectorId = 'ethereum-sign_message-eip712-1';

/// One message vector's input and expected output.
final class MessageVector {
  MessageVector._(this.input, this.expected);

  /// The vector with [id] from the inventory.
  factory MessageVector.load(String id) {
    final vector = vectorById(loadInventory(), id);
    return MessageVector._(
      vector.input as Map<dynamic, dynamic>,
      vector.expected as Map<dynamic, dynamic>,
    );
  }

  /// The vector's `input` map.
  final Map<dynamic, dynamic> input;

  /// The vector's `expected` map.
  final Map<dynamic, dynamic> expected;

  /// The upstream test key, as 64 hexadecimal digits. Raw key material: for
  /// tests only, which hand it to the signing core through a native handle.
  String get privateKeyHex => input['private_key'] as String;

  /// The signature the upstream test asserts, lowercase hexadecimal.
  String get signature => expected['signature'] as String;
}

/// The personal-message request of the `personal` vector.
EvmMessageRequest personalRequest(MessageVector vector, {int? chainId}) =>
    EvmMessageRequest.personal(
      Uint8List.fromList(utf8.encode(vector.input['message'] as String)),
      coin: Coin.ethereum,
      chainId: chainId,
    );

/// The typed-data request of the `eip712` vector.
EvmMessageRequest typedDataRequest(MessageVector vector, {int? chainId}) =>
    EvmMessageRequest.typedData(
      vector.input['typed_data'] as String,
      coin: Coin.ethereum,
      chainId: chainId,
    );

/// [hex] as bytes.
Uint8List unhex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);
