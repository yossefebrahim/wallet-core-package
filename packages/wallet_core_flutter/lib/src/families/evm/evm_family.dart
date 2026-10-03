/// The EVM family: key-less encoding of [EvmTransactionRequest] into
/// upstream's `TW.Ethereum.Proto.SigningInput`, and parsing of its
/// `SigningOutput` into an [EvmSignResult]. **Internal**: never exported.
///
/// Nothing here sees a key. The encoder has no parameter that could carry one,
/// and the parser reads upstream's output, which holds none.
library;

import 'dart:typed_data';

import 'package:protobuf/protobuf.dart' show GeneratedMessage;
// The bindings package has no library entry point for its generated protobuf
// classes yet; which of them join a public surface is decided with
// `advanced.dart` (T1.12b). This file is SDK-internal and never re-exported.
// ignore: implementation_imports
import 'package:wallet_core_flutter_bindings/src/generated/proto/Ethereum.pb.dart'
    as eth;
import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart'
    show maxNativeBufferBytes;

import '../../coin/chain_family.dart';
import '../../coin/coin.dart';
import '../../errors/errors.dart';
import '../../requests/requests.dart';
import '../../signing/key_locator.dart';
import '../../signing/sign_result.dart';
import '../family.dart';
import 'key_fields.dart';

/// The longest `v`, `r`, `s`, or pre-hash upstream can legitimately return:
/// each is a `uint256` or a 32-byte hash.
const int maxEvmWordBytes = 32;

/// The EVM family, as one constant.
const EvmFamily evmFamily = EvmFamily();

/// [TransactionFamily] for [ChainFamily.evm].
final class EvmFamily
    implements TransactionFamily<EvmTransactionRequest, EvmSignResult> {
  /// The family has no state; use [evmFamily].
  const EvmFamily();

  @override
  ChainFamily get chainFamily => ChainFamily.evm;

  @override
  String get signingInputMessage => 'TW.Ethereum.Proto.SigningInput';

  /// Builds `TW.Ethereum.Proto.SigningInput` for [request] the way upstream's
  /// own tests do, and serializes it. **No key field is set.**
  ///
  /// Every integer is upstream's `uint256` — big-endian, minimal, zero as one
  /// `0x00` byte (upstream's `store(uint256_t)`). `tx_mode` is `Enveloped` for
  /// EIP-1559 and `Legacy` otherwise; the payload is a `Transfer` for a
  /// transfer and a `ContractGeneric` for a contract call.
  ///
  /// Pure: no isolate, pointer, engine, or key is involved. Validation already
  /// happened when [request] was constructed.
  @override
  Uint8List encodeKeylessInput(EvmTransactionRequest request) {
    final input = eth.SigningInput(
      chainId: _uint256(BigInt.from(request.chainId)),
      nonce: _uint256(request.nonce),
      gasLimit: _uint256(request.gasLimit),
      toAddress: request.to,
    );
    if (request.gasPrice case final gasPrice?) {
      input
        ..txMode = eth.TransactionMode.Legacy
        ..gasPrice = _uint256(gasPrice);
    } else {
      input
        ..txMode = eth.TransactionMode.Enveloped
        ..maxInclusionFeePerGas = _uint256(request.maxPriorityFeePerGas!)
        ..maxFeePerGas = _uint256(request.maxFeePerGas!);
    }
    final value = _uint256(request.valueWei);
    final data = request.data;
    input.transaction = data == null
        ? eth.Transaction(transfer: eth.Transaction_Transfer(amount: value))
        : eth.Transaction(
            contractGeneric: eth.Transaction_ContractGeneric(
              amount: value,
              data: data,
            ),
          );
    return input.writeToBuffer();
  }

  @override
  GeneratedMessage decodeSigningInput(Uint8List bytes) =>
      eth.SigningInput.fromBuffer(bytes);

  /// Parses upstream's `TW.Ethereum.Proto.SigningOutput`.
  ///
  /// In this order: the length of [bytes] is bounded; the bytes are decoded;
  /// the error code (field 6) and message (field 7) are read and a non-`OK`
  /// code becomes [SigningError] with upstream's code and message verbatim —
  /// including a code this build's generated enum does not know, which the
  /// protobuf runtime files as an unknown field rather than as the enum, and
  /// which would otherwise read as `OK`; any other unknown field rejects the
  /// output as not an Ethereum one; `v`, `r`, `s`, and the pre-hash are
  /// bounded at [maxEvmWordBytes]; and an empty `encoded` is rejected. Only
  /// then is anything copied into the result.
  ///
  /// Every rejection that is not upstream's own error is a [SigningError]
  /// with [SigningError.malformedOutputCode]; nothing here throws anything
  /// else, whatever [bytes] holds.
  @override
  EvmSignResult parseSigningOutput(
    Uint8List bytes, {
    required Coin coin,
    required Set<KeyLocator> usedKeys,
  }) {
    if (bytes.length > maxNativeBufferBytes) {
      throw _malformed('it is longer than $maxNativeBufferBytes bytes');
    }
    final eth.SigningOutput output;
    try {
      output = eth.SigningOutput.fromBuffer(bytes);
    } on Object {
      // Not only `InvalidProtocolBufferException`: on some malformed lengths
      // the protobuf runtime throws a `RangeError` from inside its reader.
      // Whatever it throws, these bytes are not an output we accept.
      throw _malformed('it does not decode as an Ethereum SigningOutput');
    }

    // Error first. `Common.Proto.SigningError.OK` is 0.
    final unknown = output.unknownFields;
    final unknownError = unknown.getField(_errorField);
    if (unknownError != null) {
      if (unknownError.varints.isEmpty) {
        throw _malformed('its error field has the wrong wire type');
      }
      throw SigningError(
        unknownError.varints.last.toInt(),
        output.errorMessage,
      );
    }
    if (output.error.value != 0) {
      throw SigningError(output.error.value, output.errorMessage);
    }

    if (unknown.isNotEmpty) {
      throw _malformed('it carries fields an Ethereum SigningOutput does not');
    }
    for (final (name, field) in <(String, List<int>)>[
      ('v', output.v),
      ('r', output.r),
      ('s', output.s),
      ('pre_hash', output.preHash),
    ]) {
      if (field.length > maxEvmWordBytes) {
        throw _malformed('its $name is longer than $maxEvmWordBytes bytes');
      }
    }
    if (output.encoded.isEmpty) {
      throw _malformed('it reports success with no encoded transaction');
    }
    final preHash = output.preHash;
    return EvmSignResult(
      coin: coin,
      encoded: _bytes(output.encoded),
      v: _bytes(output.v),
      r: _bytes(output.r),
      s: _bytes(output.s),
      preHash: preHash.isEmpty ? null : _bytes(preHash),
      usedKeys: usedKeys,
    );
  }

  /// One key, the transaction's own signer.
  @override
  List<KeyRole> requiredRoles(EvmTransactionRequest request) => const <KeyRole>[
    KeyRole.primary,
  ];

  @override
  KeyFieldList get keyFields => evmKeyFields;

  /// [KeyRole.primary] → `SigningInput.private_key` (field 9).
  @override
  KeyFieldEntry injectionField(KeyRole role) {
    if (role != KeyRole.primary) {
      throw ArgumentError.value(role, 'role', 'the EVM family has no such key');
    }
    return evmKeyFields.entries.first;
  }
}

/// Field number of `SigningOutput.error`.
const int _errorField = 6;

SigningError _malformed(String why) => SigningError(
  SigningError.malformedOutputCode,
  'upstream returned a signing output this SDK cannot accept: $why',
);

/// [value] as upstream's `uint256` bytes: big-endian, no leading zero bytes,
/// and zero as the single byte `0x00`. The caller has bounded [value] to
/// `0 ≤ value < 2^256`.
Uint8List _uint256(BigInt value) {
  if (value == BigInt.zero) return Uint8List(1);
  final length = (value.bitLength + 7) >> 3;
  final bytes = Uint8List(length);
  var rest = value;
  final mask = BigInt.from(0xff);
  for (var i = length - 1; i >= 0; i--) {
    bytes[i] = (rest & mask).toInt();
    rest = rest >> 8;
  }
  return bytes;
}

Uint8List _bytes(List<int> field) => Uint8List.fromList(field);
