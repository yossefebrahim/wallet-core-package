/// The UTXO operations that need the engine: the pre-check of a request's
/// addresses and scripts, and upstream's planner. **Internal**: never
/// exported.
///
/// This is not the family (`utxo_family.dart` is pure and never touches
/// native code, `families/README.md`). It is the executor-side half the
/// handler calls — the UTXO analogue of the EVM recipient check — kept beside
/// the family so that everything UTXO-specific is in one directory. Nothing
/// here holds, receives, or derives a key.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart'
    hide DisposedError;

import '../../coin/coin.dart';
import '../../coin/network.dart';
import '../../engine/coin_bridge.dart';
import '../../engine/engine.dart';
import '../../errors/boundary.dart' show NativeResultError;
import '../../errors/errors.dart';
import '../../requests/requests.dart';

/// The script types an input's locking script can be, as upstream's
/// `TWBitcoinScript` matchers tell them apart.
enum UtxoScriptType {
  /// `OP_0 <20-byte key hash>`: the one type the SDK signs.
  p2wpkh('p2wpkh', supported: true),

  /// `<33-byte key> OP_CHECKSIG`: supported, covered by
  /// `bitcoin-sign-multi_input-1`.
  p2pk('p2pk', supported: true),

  /// A pay-to-public-key script with a 65-byte key. Upstream's matcher
  /// returns only the first 33 bytes of it (`Script::matchPayToPublicKey`,
  /// `src/Bitcoin/Script.cpp:64-80`), so it could never find the key.
  p2pkUncompressed('p2pk-uncompressed', supported: false),

  /// `OP_DUP OP_HASH160 <20 bytes> OP_EQUALVERIFY OP_CHECKSIG`.
  p2pkh('p2pkh', supported: false),

  /// Pay to script hash.
  p2sh('p2sh', supported: false),

  /// Pay to witness script hash.
  p2wsh('p2wsh', supported: false),

  /// Any other witness program (taproot among them).
  witnessProgram('witness-program', supported: false),

  /// Anything else (multisig, a bare custom script).
  other('other', supported: false);

  const UtxoScriptType(this.id, {required this.supported});

  /// The name `UnsupportedOperationError.capability` carries after `script:`.
  final String id;

  /// Whether a request may spend an input of this type.
  final bool supported;
}

/// Checks everything about [request] that only upstream can answer, before
/// any key exists, in this order:
///
/// 1. The recipient with `TWAnyAddress`: [InvalidInputError]
///    (`inputName: 'toAddress'`).
/// 2. The change address likewise (`inputName: 'changeAddress'`).
/// 3. The script of every input the signature will spend — the plan's
///    selection when the request has one, else every input: its type by
///    `TWBitcoinScript`. An unsupported type is [UnsupportedOperationError]
///    (`script:<type>`); a supported type under an address style that cannot
///    own it — P2WPKH under [AddressStyle.legacy], P2PK under
///    [AddressStyle.segwit] — is an [InvalidInputError]
///    (`inputName: 'inputs'`).
///
/// Throws [UnsupportedOperationError] for a network the coin does not have
/// (none can happen here), and a `NativeResultError` for a null upstream
/// returns.
void checkUtxoRequest(WalletEngine engine, UtxoTransactionRequest request) {
  final coin = request.coin;
  final network = request.network;
  if (!engine.isValidAddress(request.toAddress, coin, network: network)) {
    throw InvalidInputError(
      'not a valid ${coin.id} address on ${network.id}',
      inputName: 'toAddress',
    );
  }
  if (!engine.isValidAddress(request.changeAddress, coin, network: network)) {
    throw InvalidInputError(
      'not a valid ${coin.id} address on ${network.id}',
      inputName: 'changeAddress',
    );
  }
  final native = UtxoNative(engine.context);
  for (final (index, input)
      in (request.plan?.selectedInputs ?? request.inputs).indexed) {
    final type = native.classify(input.script);
    if (!type.supported) {
      throw UnsupportedOperationError(coin, 'script:${type.id}');
    }
    final style = input.addressStyle;
    final consistent = switch (type) {
      UtxoScriptType.p2wpkh =>
        style == AddressStyle.standard || style == AddressStyle.segwit,
      _ => style == AddressStyle.standard || style == AddressStyle.legacy,
    };
    if (!consistent) {
      throw InvalidInputError(
        'inputs[$index] is a ${type.id} script, which a ${style.id} address '
        'style cannot own',
        inputName: 'inputs',
      );
    }
  }
}

/// The calls into upstream that [checkUtxoRequest] and planning make, over
/// one [NativeContext].
final class UtxoNative {
  /// Creates the calls over [context].
  UtxoNative(this.context);

  /// The loaded library and its bindings.
  final NativeContext context;

  /// What `TWBitcoinScript` says [script] is. Always releases the script
  /// object and every `TWData` it made, whatever it returns or throws.
  UtxoScriptType classify(Uint8List script) {
    final bindings = context.bindings;
    return runScope(context, (scope) {
      final data = scope.data(script);
      final handle = bindings.TWBitcoinScriptCreateWithData(data.pointer);
      if (handle == nullptr) {
        throw const NativeResultError(
          'TWBitcoinScriptCreateWithData returned nullptr',
        );
      }
      try {
        if (bindings.TWBitcoinScriptIsPayToWitnessPublicKeyHash(handle)) {
          return UtxoScriptType.p2wpkh;
        }
        final pubkey = bindings.TWBitcoinScriptMatchPayToPubkey(handle);
        if (pubkey != nullptr) {
          scope.use(TWDataHandle.adopt(context, pubkey));
          return script.length == 35
              ? UtxoScriptType.p2pk
              : UtxoScriptType.p2pkUncompressed;
        }
        final pubkeyHash = bindings.TWBitcoinScriptMatchPayToPubkeyHash(handle);
        if (pubkeyHash != nullptr) {
          scope.use(TWDataHandle.adopt(context, pubkeyHash));
          return UtxoScriptType.p2pkh;
        }
        if (bindings.TWBitcoinScriptIsPayToScriptHash(handle)) {
          return UtxoScriptType.p2sh;
        }
        if (bindings.TWBitcoinScriptIsPayToWitnessScriptHash(handle)) {
          return UtxoScriptType.p2wsh;
        }
        if (bindings.TWBitcoinScriptIsWitnessProgram(handle)) {
          return UtxoScriptType.witnessProgram;
        }
        return UtxoScriptType.other;
      } finally {
        bindings.TWBitcoinScriptDelete(handle);
      }
    });
  }

  /// `TWAnySignerPlan(keylessInput, coin)`: upstream's serialized
  /// `TransactionPlan`. [keylessInput] holds no key, so neither do the
  /// buffers; both `TWData`s are released before this returns.
  ///
  /// Throws [SigningError] (`malformedOutputCode`) when upstream returns no
  /// output or an out-of-range length.
  Uint8List plan(Uint8List keylessInput, Coin coin) {
    final coinType = twCoinTypeOf(coin);
    return runScope(context, (scope) {
      final input = scope.data(keylessInput);
      final pointer = context.bindings.TWAnySignerPlan(input.pointer, coinType);
      if (pointer == nullptr) {
        throw const SigningError(
          SigningError.malformedOutputCode,
          'TWAnySignerPlan returned no output',
        );
      }
      final output = scope.use(TWDataHandle.adopt(context, pointer));
      try {
        return output.copyBytes();
      } on RangeError {
        throw const SigningError(
          SigningError.malformedOutputCode,
          'TWAnySignerPlan reported an output length out of range',
        );
      } on StateError {
        throw const SigningError(
          SigningError.malformedOutputCode,
          'TWAnySignerPlan reported output bytes but returned no buffer',
        );
      }
    });
  }
}
