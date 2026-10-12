/// The UTXO family: key-less encoding of [UtxoTransactionRequest] into
/// upstream's `TW.Bitcoin.Proto.SigningInput`, and parsing of its
/// `SigningOutput` into a [UtxoSignResult] and of its `TransactionPlan` into
/// a [UtxoPlan]. **Internal**: never exported.
///
/// **Which upstream signer this reaches.** `TWAnySignerSign` for Bitcoin runs
/// `Bitcoin::Entry::sign` (`src/Bitcoin/Entry.cpp:163-164`), which calls
/// `Bitcoin::Signer::sign` (`src/Bitcoin/Signer.cpp:25`): the **C++ legacy
/// signer**, `TransactionSigner<Transaction, TransactionBuilder>::sign`
/// (`src/Bitcoin/TransactionSigner.cpp:26`, called at `Signer.cpp:31`),
/// because `signing_v2` is unset. The Rust BitcoinV2 signer
/// (`rust/chains/tw_bitcoin`) is reached only when `SigningInput.signing_v2`
/// is set (`Signer.cpp:26-28`), which this family never does and the
/// key-field check would refuse in a key-less input. `TWAnySignerPlan`
/// reaches `Signer::plan` → `TransactionBuilder::plan` (`Entry.cpp:167-168`,
/// `Signer.cpp:17-22`).
///
/// **What it needs for each script type.** The legacy signer finds the key of
/// an input by the hash of the key's public key: for a P2WPKH or P2PKH script
/// it is the 20-byte hash in the script, for a pay-to-public-key script the
/// hash of the key in the script (`SignatureBuilder.cpp:151-153`, `180-226`,
/// key lookup `319-330`). **`SigningInput.scripts` is read only for P2SH and
/// P2WSH inputs** (`signStep`, `SignatureBuilder.cpp:134-150`), which this
/// SDK does not accept; so it is never set, and the P2PKH redeem-script entry
/// that upstream's multi-input test sets for its P2WPKH input is not needed
/// (`test/families/utxo/utxo_vectors_native_test.dart` proves the bytes do
/// not change with it).
///
/// Nothing here sees a key. The encoder has no parameter that could carry
/// one, and the parsers read upstream's output, which holds none.
library;

import 'dart:typed_data';

import 'package:protobuf/protobuf.dart' show GeneratedMessage;
// The bindings package has no library entry point for its generated protobuf
// classes yet; which of them join a public surface is decided with
// `advanced.dart` (T1.12b). This file is SDK-internal and never re-exported.
// ignore: implementation_imports
import 'package:wallet_core_flutter_bindings/src/generated/proto/Bitcoin.pb.dart'
    as btc;
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

/// The UTXO family, as one constant.
const UtxoFamily utxoFamily = UtxoFamily();

/// `TWBitcoinSigHashTypeAll`: every input and output is signed
/// (`include/TrustWalletCore/TWBitcoin.h`, `TWBitcoinSigHashType`).
const int _sigHashAll = 0x01;

/// The sequence of a final input, which every input of this family has.
const int _finalSequence = 0xFFFFFFFF;

/// Field number of `TransactionPlan.error`.
const int _planErrorField = 7;

/// Field number of `SigningOutput.error`.
const int _outputErrorField = 4;

/// A zero `Int64` from the generated message, so that this file needs no
/// import of `package:fixnum`: `Int64`'s operators accept a Dart `int`.
final _zero = btc.SigningInput().amount;

/// [TransactionFamily] for [ChainFamily.utxo].
final class UtxoFamily
    implements TransactionFamily<UtxoTransactionRequest, UtxoSignResult> {
  /// The family has no state; use [utxoFamily].
  const UtxoFamily();

  @override
  ChainFamily get chainFamily => ChainFamily.utxo;

  @override
  String get signingInputMessage => 'TW.Bitcoin.Proto.SigningInput';

  /// Builds `TW.Bitcoin.Proto.SigningInput` for [request] the way upstream's
  /// own tests do, and serializes it. **No key field is set.**
  ///
  /// `hash_type` is `SIGHASH_ALL`; `coin_type` is left at 0, which is Bitcoin
  /// (the only coin a request accepts); `byte_fee`, `amount`, `to_address`,
  /// `change_address` and `use_max_amount` are the request's. Each input of the
  /// request — or of its plan, when it has one — becomes an
  /// `UnspentTransaction`: the outpoint's `hash` is the transaction id **in
  /// reverse byte order** (upstream wants the order of the transaction's own
  /// serialization; the id is shown in the opposite order), its `sequence` is
  /// final (`0xFFFFFFFF`), `script` and `amount` are the input's. A request
  /// with a plan also carries it as `plan`, so that upstream signs it rather
  /// than planning again.
  ///
  /// Pure: no isolate, pointer, engine, or key is involved. Validation already
  /// happened when [request] was constructed.
  @override
  Uint8List encodeKeylessInput(UtxoTransactionRequest request) {
    final plan = request.plan;
    final spent = plan?.selectedInputs ?? request.inputs;
    final input = btc.SigningInput(
      hashType: _sigHashAll,
      amount: _zero + request.amount,
      byteFee: _zero + request.feeRatePerByte,
      toAddress: request.toAddress,
      changeAddress: request.changeAddress,
      useMaxAmount: request.useMaxAmount,
      utxo: spent.map(_unspent),
    );
    if (plan != null) {
      input.plan = btc.TransactionPlan(
        amount: _zero + plan.amount,
        availableAmount: _zero + plan.availableAmount,
        fee: _zero + plan.fee,
        change: _zero + plan.change,
        utxos: spent.map(_unspent),
      );
    }
    return input.writeToBuffer();
  }

  @override
  GeneratedMessage decodeSigningInput(Uint8List bytes) =>
      btc.SigningInput.fromBuffer(bytes);

  /// Parses upstream's `TW.Bitcoin.Proto.SigningOutput`.
  ///
  /// In this order: the length of [bytes] is bounded; the bytes are decoded;
  /// the error code (field 4) and message (field 5) are read and a non-`OK`
  /// code becomes [SigningError] with upstream's code and message verbatim —
  /// including a code this build's generated enum does not know, which the
  /// protobuf runtime files as an unknown field rather than as the enum, and
  /// which would otherwise read as `OK`; any other unknown field, and the
  /// BitcoinV2 result this family never asks for, reject the output as not
  /// the one asked for; the transaction id must be 64 lower-case hexadecimal
  /// digits and `encoded` must be present and no longer than one native
  /// buffer. Only then is anything copied into the result.
  ///
  /// Every rejection that is not upstream's own error is a [SigningError]
  /// with [SigningError.malformedOutputCode]; nothing here throws anything
  /// else, whatever [bytes] holds.
  @override
  UtxoSignResult parseSigningOutput(
    Uint8List bytes, {
    required Coin coin,
    required Set<KeyLocator> usedKeys,
  }) {
    if (bytes.length > maxNativeBufferBytes) {
      throw _malformed('it is longer than $maxNativeBufferBytes bytes');
    }
    final btc.SigningOutput output;
    try {
      output = btc.SigningOutput.fromBuffer(bytes);
    } on Object {
      // Not only `InvalidProtocolBufferException`: on some malformed lengths
      // the protobuf runtime throws a `RangeError` from inside its reader.
      throw _malformed('it does not decode as a Bitcoin SigningOutput');
    }

    // Error first. `Common.Proto.SigningError.OK` is 0.
    final unknown = output.unknownFields;
    final unknownError = unknown.getField(_outputErrorField);
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
      throw _malformed('it carries fields a Bitcoin SigningOutput does not');
    }
    if (output.hasSigningResultV2()) {
      throw _malformed(
        'it carries a BitcoinV2 result, which was not asked for',
      );
    }
    if (output.encoded.isEmpty) {
      throw _malformed('it reports success with no encoded transaction');
    }
    if (!_transactionId.hasMatch(output.transactionId)) {
      throw _malformed('its transaction id is not 64 lower-case hex digits');
    }
    return UtxoSignResult(
      coin: coin,
      encoded: Uint8List.fromList(output.encoded),
      transactionId: output.transactionId,
      usedKeys: usedKeys,
    );
  }

  /// Parses upstream's `TW.Bitcoin.Proto.TransactionPlan`, returned for
  /// [request], into a [UtxoPlan].
  ///
  /// The same discipline as [parseSigningOutput]: length bound; decode; the
  /// error (field 7) read first and mapped to [SigningError] — its message is
  /// upstream's name for the code, because a plan carries no message; unknown
  /// fields, a Zcash branch id, a BitcoinV2 plan and the other chain-specific
  /// fields reject the plan as not the one asked for. Every selected
  /// `UnspentTransaction` must be one of [request]'s inputs, once, with the
  /// amount and script the request gave it — the plan never names an input
  /// the caller did not offer — and every amount must be between 0 and
  /// `2.1e15`. The selected inputs are the request's own [UtxoInput]s, so the
  /// plan carries the locators of the keys that will spend them.
  ///
  /// Every rejection that is not upstream's own error is a [SigningError]
  /// with [SigningError.malformedOutputCode].
  UtxoPlan parsePlan(
    Uint8List bytes, {
    required UtxoTransactionRequest request,
  }) {
    if (bytes.length > maxNativeBufferBytes) {
      throw _malformed('it is longer than $maxNativeBufferBytes bytes', 'plan');
    }
    final btc.TransactionPlan plan;
    try {
      plan = btc.TransactionPlan.fromBuffer(bytes);
    } on Object {
      throw _malformed(
        'it does not decode as a Bitcoin TransactionPlan',
        'plan',
      );
    }

    final unknown = plan.unknownFields;
    final unknownError = unknown.getField(_planErrorField);
    if (unknownError != null) {
      if (unknownError.varints.isEmpty) {
        throw _malformed('its error field has the wrong wire type', 'plan');
      }
      final code = unknownError.varints.last.toInt();
      throw SigningError(code, 'upstream error code $code');
    }
    if (plan.error.value != 0) {
      throw SigningError(plan.error.value, plan.error.name);
    }

    if (unknown.isNotEmpty ||
        plan.branchId.isNotEmpty ||
        plan.outputOpReturn.isNotEmpty ||
        plan.hasOutputOpReturnIndex() ||
        plan.preblockhash.isNotEmpty ||
        plan.preblockheight != _zero ||
        plan.hasPlanningResultV2()) {
      throw _malformed(
        'it carries fields a Bitcoin plan here does not',
        'plan',
      );
    }
    if (plan.utxos.isEmpty || plan.utxos.length > maxUtxoInputs) {
      throw _malformed(
        'it selects no input, or more than $maxUtxoInputs',
        'plan',
      );
    }
    final offered = <String, UtxoInput>{
      for (final input in request.inputs)
        _outPointKey(input.outPoint.transactionId, input.outPoint.index): input,
    };
    final selected = <UtxoInput>[];
    final seen = <String>{};
    for (final utxo in plan.utxos) {
      final hash = utxo.outPoint.hash;
      if (hash.length != 32) {
        throw _malformed('a selected input has no 32-byte hash', 'plan');
      }
      final key = _outPointKey(_hex(hash.reversed), utxo.outPoint.index);
      final input = offered[key];
      if (input == null || !seen.add(key)) {
        throw _malformed(
          'it selects an input that was not offered, or one twice',
          'plan',
        );
      }
      if (utxo.amount != _zero + input.amount ||
          !_sameBytes(utxo.script, input.script)) {
        throw _malformed(
          'a selected input differs from the one offered',
          'plan',
        );
      }
      selected.add(input);
    }
    final amounts = <int>[
      plan.amount.toInt(),
      plan.availableAmount.toInt(),
      plan.fee.toInt(),
      plan.change.toInt(),
    ];
    for (final value in amounts) {
      if (value < 0 || value > maxUtxoAmount) {
        throw _malformed('an amount of the plan is out of range', 'plan');
      }
    }
    return UtxoPlan(
      selectedInputs: selected,
      amount: amounts[0],
      availableAmount: amounts[1],
      fee: amounts[2],
      change: amounts[3],
    );
  }

  /// One role per **distinct** key, `input(n)` where `n` is the position of
  /// the first input that uses it, in that order — the roles of
  /// [UtxoTransactionRequest.keyLocators].
  ///
  /// This is the "one role per distinct key" of the two shapes
  /// `families/README.md` lays out: two inputs on one derivation path are one
  /// locator and one derived key, so the key is derived once and appears once
  /// in `private_key`; the alternative — one handle under several roles —
  /// would put the same key into the signing input once per input. Upstream
  /// matches keys to inputs by the hash of the public key, so the order is
  /// not semantic.
  @override
  List<KeyRole> requiredRoles(UtxoTransactionRequest request) => <KeyRole>[
    for (final locator in request.keyLocators) locator.role!,
  ];

  @override
  KeyFieldList get keyFields => utxoKeyFields;

  /// Every `input(n)` → `SigningInput.private_key` (field 6, repeated).
  @override
  KeyFieldEntry injectionField(KeyRole role) {
    if (!role.id.startsWith('input:')) {
      throw ArgumentError.value(
        role,
        'role',
        'the UTXO family has no such key',
      );
    }
    return utxoKeyFields.entries.first;
  }
}

SigningError _malformed(String why, [String what = 'signing output']) =>
    SigningError(
      SigningError.malformedOutputCode,
      'upstream returned a $what this SDK cannot accept: $why',
    );

/// A transaction id as upstream renders it: 64 lower-case hex digits.
final RegExp _transactionId = RegExp(r'^[0-9a-f]{64}$');

/// The `UnspentTransaction` for [input]. Its `variant` is left at the default:
/// the legacy signer reads only the outpoint, script and amount
/// (`src/Bitcoin/UTXO.h`).
btc.UnspentTransaction _unspent(UtxoInput input) => btc.UnspentTransaction(
  outPoint: btc.OutPoint(
    hash: _hashOf(input.outPoint.transactionId),
    index: input.outPoint.index,
    sequence: _finalSequence,
  ),
  script: input.script,
  amount: _zero + input.amount,
);

/// The bytes of the transaction id [txid] (64 hex digits, as displayed) in
/// reverse order — the order upstream's `OutPoint.hash` has.
Uint8List _hashOf(String txid) {
  final bytes = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    bytes[31 - i] = int.parse(txid.substring(2 * i, 2 * i + 2), radix: 16);
  }
  return bytes;
}

String _hex(Iterable<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

String _outPointKey(String txid, int index) => '${txid.toLowerCase()}:$index';

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
