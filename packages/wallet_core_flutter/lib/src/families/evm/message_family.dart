/// The EVM message family: key-less encoding of [EvmMessageRequest] into
/// upstream's `TW.Ethereum.Proto.MessageSigningInput`, and parsing of its
/// `MessageSigningOutput` into an [EvmMessageSignResult]. **Internal**: never
/// exported.
///
/// A second family object beside [EvmFamily] and not a second mode of it,
/// because the family contract is generic over one request type and names one
/// signing-input message (`families/README.md`); messages have their own
/// request hierarchy, their own input message, their own output message and
/// their own native entry point (`TWMessageSignerSign`). They share the key
/// field list and the whole of the key handling, which is the core's.
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

/// The length of the signature upstream returns for the message types this
/// family signs: `r` (32) ‖ `s` (32) ‖ `v` (1).
const int evmMessageSignatureBytes = 65;

/// The personal-message family, as one constant.
const EvmMessageFamily evmPersonalMessageFamily = EvmMessageFamily._(
  EvmMessageType.personal,
);

/// The typed-data family, as one constant.
const EvmMessageFamily evmTypedDataMessageFamily = EvmMessageFamily._(
  EvmMessageType.typedData,
);

/// [MessageFamily] for [ChainFamily.evm], one object per [EvmMessageType]
/// (use [evmPersonalMessageFamily] and [evmTypedDataMessageFamily]).
///
/// The kind is part of the family because the signing output does not say
/// which kind of message it signed, and a parser sees only the output: the
/// result's `messageType` is the family's, known before anything is signed.
///
/// **Which upstream message type each kind uses** (`Ethereum.proto`
/// `MessageType`):
///
/// * [EvmMessageType.personal] → `MessageType_legacy` (0): EIP-191, signature
///   with `v` of 27/28. It is the type of `TWEthereumMessageSignerSignMessage`
///   — the entry point `ethereum-sign_message-personal-1` is asserted through
///   — and of upstream's protobuf twin test
///   (`ethereum_message_sign.rs::test_tw_message_signer_sign`).
/// * [EvmMessageType.typedData] → `MessageType_typed` (2): EIP-712 v4 with
///   `Legacy` signature type (`v` of 27/28), the type of
///   `TWEthereumMessageSignerSignTypedMessage` (`ethereum-sign_message-eip712-1`).
///   `chain_id` stays unset, so upstream does not cross-check the document's
///   `domain.chainId`.
///
/// The EIP-155 variants (`MessageType_eip155`, `MessageType_typed_eip155`) are
/// not signed: [encodeKeylessInput] throws [UnsupportedOperationError] for a
/// request with a chain id.
final class EvmMessageFamily
    implements MessageFamily<EvmMessageRequest, EvmMessageSignResult> {
  const EvmMessageFamily._(this.type);

  /// The kind of message this family signs.
  final EvmMessageType type;

  @override
  ChainFamily get chainFamily => ChainFamily.evm;

  @override
  String get signingInputMessage => 'TW.Ethereum.Proto.MessageSigningInput';

  /// Builds `TW.Ethereum.Proto.MessageSigningInput` for [request] and
  /// serializes it. **No key field is set.**
  ///
  /// Throws [UnsupportedOperationError] for an EIP-155 variant (a request
  /// with a chain id), and [ArgumentError] — a defect of the caller inside
  /// this SDK — for a request of the other kind.
  ///
  /// Pure: no isolate, pointer, engine, or key is involved. Validation
  /// already happened when [request] was constructed.
  @override
  Uint8List encodeKeylessInput(EvmMessageRequest request) {
    if (request.type != type) {
      throw ArgumentError.value(
        request.type,
        'request',
        'this family signs ${type.name} messages',
      );
    }
    if (request.chainId != null) {
      throw UnsupportedOperationError(request.coin, switch (type) {
        EvmMessageType.personal => 'messageType:eip155',
        EvmMessageType.typedData => 'messageType:typed_eip155',
      });
    }
    final input = switch (type) {
      EvmMessageType.personal => eth.MessageSigningInput(
        message: evmMessageText(request.message!),
        messageType: eth.MessageType.MessageType_legacy,
      ),
      EvmMessageType.typedData => eth.MessageSigningInput(
        message: request.typedDataJson,
        messageType: eth.MessageType.MessageType_typed,
      ),
    };
    return input.writeToBuffer();
  }

  @override
  GeneratedMessage decodeSigningInput(Uint8List bytes) =>
      eth.MessageSigningInput.fromBuffer(bytes);

  /// Parses upstream's `TW.Ethereum.Proto.MessageSigningOutput`.
  ///
  /// In this order: the length of [bytes] is bounded; the bytes are decoded;
  /// the error code (field 2) and message (field 3) are read and a non-`OK`
  /// code becomes [SigningError] with upstream's code and message verbatim —
  /// including a code this build's generated enum does not know, which the
  /// protobuf runtime files as an unknown field and which would otherwise
  /// read as `OK`; any other unknown field rejects the output as not an
  /// Ethereum message one; and the signature must be exactly
  /// [evmMessageSignatureBytes] bytes as `2 ×` that many hexadecimal digits.
  /// Only then is anything decoded into the result.
  ///
  /// Every rejection that is not upstream's own error is a [SigningError]
  /// with [SigningError.malformedOutputCode]; nothing here throws anything
  /// else, whatever [bytes] holds.
  @override
  EvmMessageSignResult parseSigningOutput(
    Uint8List bytes, {
    required Coin coin,
    required Set<KeyLocator> usedKeys,
  }) {
    if (bytes.length > maxNativeBufferBytes) {
      throw _malformed('it is longer than $maxNativeBufferBytes bytes');
    }
    final eth.MessageSigningOutput output;
    try {
      output = eth.MessageSigningOutput.fromBuffer(bytes);
    } on Object {
      // Not only `InvalidProtocolBufferException`: on some malformed lengths
      // the protobuf runtime throws a `RangeError` from inside its reader.
      throw _malformed(
        'it does not decode as an Ethereum MessageSigningOutput',
      );
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
      throw _malformed(
        'it carries fields an Ethereum MessageSigningOutput does not',
      );
    }
    final signature = _decodeSignature(output.signature);
    return EvmMessageSignResult(
      coin: coin,
      messageType: type,
      signature: signature,
      usedKeys: usedKeys,
    );
  }

  /// One key, the message signer.
  @override
  List<KeyRole> requiredRoles(EvmMessageRequest request) => const <KeyRole>[
    KeyRole.primary,
  ];

  @override
  KeyFieldList get keyFields => evmKeyFields;

  /// [KeyRole.primary] → `MessageSigningInput.private_key` (field 1).
  @override
  KeyFieldEntry injectionField(KeyRole role) {
    if (role != KeyRole.primary) {
      throw ArgumentError.value(role, 'role', 'the EVM family has no such key');
    }
    return evmKeyFields.entries.singleWhere(
      (entry) => entry.messagePath == signingInputMessage,
    );
  }
}

/// Field number of `MessageSigningOutput.error`.
const int _errorField = 2;

SigningError _malformed(String why) => SigningError(
  SigningError.malformedOutputCode,
  'upstream returned a signing output this SDK cannot accept: $why',
);

/// The bytes of [hex], which must be exactly [evmMessageSignatureBytes]
/// bytes as hexadecimal digits; anything else is a malformed output. No
/// content of [hex] reaches the error.
Uint8List _decodeSignature(String hex) {
  if (hex.length != 2 * evmMessageSignatureBytes) {
    throw _malformed(
      'its signature is not $evmMessageSignatureBytes bytes of hexadecimal',
    );
  }
  final bytes = Uint8List(evmMessageSignatureBytes);
  for (var i = 0; i < bytes.length; i++) {
    final high = _hexValue(hex.codeUnitAt(2 * i));
    final low = _hexValue(hex.codeUnitAt(2 * i + 1));
    if (high < 0 || low < 0) {
      throw _malformed('its signature is not hexadecimal');
    }
    bytes[i] = (high << 4) | low;
  }
  return bytes;
}

int _hexValue(int unit) {
  if (unit >= 0x30 && unit <= 0x39) return unit - 0x30;
  if (unit >= 0x61 && unit <= 0x66) return unit - 0x61 + 10;
  if (unit >= 0x41 && unit <= 0x46) return unit - 0x41 + 10;
  return -1;
}
