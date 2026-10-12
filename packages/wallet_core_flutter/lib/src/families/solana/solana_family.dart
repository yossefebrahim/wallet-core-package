/// The Solana family: key-less encoding of [SolanaTransactionRequest] into
/// upstream's `TW.Solana.Proto.SigningInput`, and parsing of its
/// `SigningOutput` into a [SolanaSignResult]. **Internal**: never exported.
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
import 'package:wallet_core_flutter_bindings/src/generated/proto/Solana.pb.dart'
    as sol;
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

/// The longest transaction string upstream can legitimately return.
///
/// A Solana transaction is at most 1232 bytes (the packet size), which is at
/// most 1,700 base58 characters; 2,048 leaves room and still bounds what is
/// copied. The transfers this family signs are about 215 bytes.
const int maxSolanaEncodedChars = 2048;

/// The most signatures upstream reports. A transaction of at most 1232 bytes
/// carries at most 19; a transfer carries one.
const int maxSolanaSignatures = 32;

/// The longest public key or signature string in a reported signature: a
/// 32-byte key is at most 44 base58 characters, a 64-byte signature at most
/// 88.
const int maxSolanaSignatureChars = 128;

/// The Solana family, as one constant.
const SolanaFamily solanaFamily = SolanaFamily();

/// [TransactionFamily] for [ChainFamily.solana].
final class SolanaFamily
    implements TransactionFamily<SolanaTransactionRequest, SolanaSignResult> {
  /// The family has no state; use [solanaFamily].
  const SolanaFamily();

  @override
  ChainFamily get chainFamily => ChainFamily.solana;

  @override
  String get signingInputMessage => 'TW.Solana.Proto.SigningInput';

  /// Builds `TW.Solana.Proto.SigningInput` for [request] the way upstream's
  /// own test does (`TWAnySignerSolana.SignTransfer`), and serializes it.
  /// **No key field is set.**
  ///
  /// Sets `transfer_transaction` (recipient, value) and `recent_blockhash`;
  /// nothing else. In particular `tx_encoding` is left at upstream's default,
  /// base58, which is the encoding [SolanaSignResult] names, and neither
  /// `sender`, a fee payer, a memo, a nonce account nor a priority fee is
  /// set: the signing key is the only signer and therefore the fee payer.
  ///
  /// Pure: no isolate, pointer, engine, or key is involved. Validation already
  /// happened when [request] was constructed.
  @override
  Uint8List encodeKeylessInput(SolanaTransactionRequest request) {
    // `Transfer.value` is a `uint64` held by the generated class as a
    // fixnum `Int64`, a type this package does not import: it is made from
    // the message's own zero, which `+` promotes an `int` against.
    final transfer = sol.Transfer(recipient: request.to);
    transfer.value = transfer.value + request.lamports;
    return sol.SigningInput(
      recentBlockhash: request.recentBlockhash,
      transferTransaction: transfer,
    ).writeToBuffer();
  }

  @override
  GeneratedMessage decodeSigningInput(Uint8List bytes) =>
      sol.SigningInput.fromBuffer(bytes);

  /// Parses upstream's `TW.Solana.Proto.SigningOutput`.
  ///
  /// In this order: the length of [bytes] is bounded; the bytes are decoded;
  /// the error code (field 2) and message (field 3) are read and a non-`OK`
  /// code becomes [SigningError] with upstream's code and message verbatim —
  /// including a code this build's generated enum does not know, which the
  /// protobuf runtime files as an unknown field rather than as the enum, and
  /// which would otherwise read as `OK`; any other unknown field rejects the
  /// output as not a Solana one; the transaction strings and every reported
  /// signature are bounded and checked to be base58, the encoding this family
  /// asks for; and an empty `encoded` is rejected. Only then is anything
  /// copied into the result.
  ///
  /// Every rejection that is not upstream's own error is a [SigningError]
  /// with [SigningError.malformedOutputCode]; nothing here throws anything
  /// else, whatever [bytes] holds.
  @override
  SolanaSignResult parseSigningOutput(
    Uint8List bytes, {
    required Coin coin,
    required Set<KeyLocator> usedKeys,
  }) {
    if (bytes.length > maxNativeBufferBytes) {
      throw _malformed('it is longer than $maxNativeBufferBytes bytes');
    }
    final sol.SigningOutput output;
    try {
      output = sol.SigningOutput.fromBuffer(bytes);
    } on Object {
      // Not only `InvalidProtocolBufferException`: on some malformed lengths
      // the protobuf runtime throws a `RangeError` from inside its reader.
      // Whatever it throws, these bytes are not an output we accept.
      throw _malformed('it does not decode as a Solana SigningOutput');
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
      throw _malformed('it carries fields a Solana SigningOutput does not');
    }
    _checkBase58('encoded', output.encoded, maxSolanaEncodedChars);
    _checkBase58('unsigned_tx', output.unsignedTx, maxSolanaEncodedChars);
    if (output.signatures.length > maxSolanaSignatures) {
      throw _malformed('it reports more than $maxSolanaSignatures signatures');
    }
    for (final signature in output.signatures) {
      if (signature.unknownFields.isNotEmpty) {
        throw _malformed('a signature carries fields it should not');
      }
      _checkBase58(
        'signature pubkey',
        signature.pubkey,
        maxSolanaSignatureChars,
      );
      _checkBase58('signature', signature.signature, maxSolanaSignatureChars);
    }
    if (output.encoded.isEmpty) {
      throw _malformed('it reports success with no encoded transaction');
    }
    return SolanaSignResult(
      coin: coin,
      encoded: output.encoded,
      unsignedTransaction: output.unsignedTx.isEmpty ? null : output.unsignedTx,
      usedKeys: usedKeys,
    );
  }

  /// One key, the transaction's own signer, which is also the fee payer.
  /// A request needing [KeyRole.feePayer] too is not expressible
  /// ([SolanaTransactionRequest] has no fee payer); when one is, this is
  /// where it would name `[primary, feePayer]`.
  @override
  List<KeyRole> requiredRoles(SolanaTransactionRequest request) =>
      const <KeyRole>[KeyRole.primary];

  @override
  KeyFieldList get keyFields => solanaKeyFields;

  /// [KeyRole.primary] → `SigningInput.private_key` (field 1);
  /// [KeyRole.feePayer] → `SigningInput.fee_payer_private_key` (field 17).
  /// Any other role has no slot.
  @override
  KeyFieldEntry injectionField(KeyRole role) {
    if (role == KeyRole.primary) return solanaSignerKeyField;
    if (role == KeyRole.feePayer) return solanaFeePayerKeyField;
    throw ArgumentError.value(
      role,
      'role',
      'the Solana family has no such key',
    );
  }
}

/// Field number of `SigningOutput.error`.
const int _errorField = 2;

SigningError _malformed(String why) => SigningError(
  SigningError.malformedOutputCode,
  'upstream returned a signing output this SDK cannot accept: $why',
);

/// The Bitcoin base58 alphabet: no `0`, `O`, `I` or `l`.
final RegExp _base58Characters = RegExp(r'^[1-9A-HJ-NP-Za-km-z]*$');

/// Rejects [value] — a string field of upstream's output — when it is longer
/// than [maxChars] or has a character outside the base58 alphabet. Empty
/// passes: whether a field may be empty is the caller's rule.
void _checkBase58(String name, String value, int maxChars) {
  if (value.length > maxChars) {
    throw _malformed('its $name is longer than $maxChars characters');
  }
  if (!_base58Characters.hasMatch(value)) {
    throw _malformed('its $name is not base58');
  }
}
