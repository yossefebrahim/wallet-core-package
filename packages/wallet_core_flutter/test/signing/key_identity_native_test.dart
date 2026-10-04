/// The key the signing path uses is the key the caller named, checked by
/// means that share no code with that path:
///
/// * `withDerivedKey` at the `ethereum-address-n/a-1` vector's path yields a
///   key whose public key and address — computed here straight through the
///   bindings, not through `HDWallet.deriveAccount` — are the vector's.
/// * The public flow's signature is reproduced by the signing core with a key
///   obtained independently (`TWHDWalletGetDerivedKey` by account, change and
///   index, not `TWHDWalletGetKey` by path), and upstream's
///   `TWPublicKeyRecover` recovers the vector's public key from the
///   signature and the pre-hash the result reports.
///
/// Skips when the library is absent; `WCF_NATIVE_REQUIRED=1` turns that into
/// a failure (see `../support/host_library.dart`).
@Tags(['native'])
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/advanced.dart'
    show
        HDWallet,
        NativeContext,
        TWCoinType,
        TWDataHandle,
        TWStringHandle,
        WalletCoreBindings;
import 'package:wallet_core_flutter/src/engine/hd_wallet.dart'
    show withDerivedKey;
import 'package:wallet_core_flutter/src/families/evm/evm_family.dart';
import 'package:wallet_core_flutter/src/session/testing.dart';
import 'package:wallet_core_flutter/src/signing/signing_core.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';

import '../support/fixtures.dart';
import '../support/host_library.dart';
import 'signing_support.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

const TWCoinType _eth = TWCoinType.TWCoinTypeEthereum;

void main() {
  final skip = hostLibrarySkipReason();

  group('the key that signs is the key named', skip: skip, () {
    late WalletCoreBindings bindings;
    late NativeContext context;
    late String mnemonic;
    late String path;
    late String publicKeyHex;
    late String address;
    late String to;

    setUpAll(() {
      bindings = openHostBindings();
      context = NativeContext(bindings);
      final inventory = loadInventory();
      final vector = vectorById(inventory, 'ethereum-address-n/a-1');
      mnemonic = (vector.input as Map)['mnemonic'] as String;
      path = (vector.input as Map)['derivation_path'] as String;
      publicKeyHex = (vector.expected as Map)['public_key'] as String;
      address = (vector.expected as Map)['address'] as String;
      to =
          (vectorById(inventory, 'ethereum-sign-eip1559-1').input
                  as Map)['to_address']
              as String;
    });

    /// The uncompressed secp256k1 public key and the Ethereum address of the
    /// key [privateKey], straight through the bindings.
    (String, String) publicIdentity(Uint8List privateKey) {
      final data = TWDataHandle.fromBytes(context, privateKey);
      final key = bindings.TWPrivateKeyCreateWithData(data.pointer);
      data.dispose();
      expect(key, isNot(nullptr));
      final publicKey = bindings.TWPrivateKeyGetPublicKeySecp256k1(key, false);
      final publicData = TWDataHandle.adopt(
        context,
        bindings.TWPublicKeyData(publicKey),
      );
      final anyAddress = bindings.TWAnyAddressCreateWithPublicKey(
        publicKey,
        _eth,
      );
      final description = TWStringHandle.adopt(
        context,
        bindings.TWAnyAddressDescription(anyAddress),
      );
      try {
        return (_hex(publicData.copyBytes()), description.toDartString());
      } finally {
        description.dispose();
        bindings.TWAnyAddressDelete(anyAddress);
        publicData.dispose();
        bindings.TWPublicKeyDelete(publicKey);
        bindings.TWPrivateKeyDelete(key);
      }
    }

    /// The key at [path], obtained by account, change and index through
    /// `TWHDWalletGetDerivedKey` — a different upstream entry point from the
    /// path-string `TWHDWalletGetKey` the signing path uses — as a list the
    /// test owns and overwrites.
    Uint8List independentKey() {
      final components = path.split('/');
      int index(String c) => int.parse(c.replaceAll("'", ''));
      final account = index(components[3]);
      final change = index(components[4]);
      final addressIndex = index(components[5]);
      final words = TWStringHandle.fromString(context, mnemonic);
      final passphrase = TWStringHandle.fromString(context, '');
      final wallet = bindings.TWHDWalletCreateWithMnemonic(
        words.pointer,
        passphrase.pointer,
      );
      words.dispose();
      passphrase.dispose();
      final key = bindings.TWHDWalletGetDerivedKey(
        wallet,
        _eth,
        account,
        change,
        addressIndex,
      );
      final data = TWDataHandle.adopt(context, bindings.TWPrivateKeyData(key));
      try {
        return data.copyBytes();
      } finally {
        data.dispose();
        bindings.TWPrivateKeyDelete(key);
        bindings.TWHDWalletDelete(wallet);
      }
    }

    test("withDerivedKey at the vector's path yields the vector's public key "
        'and address', () {
      final wallet = HDWallet.fromMnemonic(context, mnemonic);
      try {
        final (publicKey, derivedAddress) = withDerivedKey(
          wallet,
          Coin.ethereum,
          path,
          (key) => publicIdentity(key),
        );
        expect(publicKey, publicKeyHex);
        expect(derivedAddress, address);
      } finally {
        wallet.dispose();
      }
    });

    test('the public flow signs with that key: an independently obtained key '
        'reproduces it, and the signature recovers to the vector', () async {
      final core = await initializeForTesting(
        hostLibraryPath: findHostLibrary(),
        expectedIdentity: hostIdentity,
      );
      final request = transferTo(to);
      final EvmSignResult result;
      final wallet = await core.wallets.importMnemonic(mnemonic);
      try {
        result = await core.signer.sign(request, {
          KeyLocator.hdPath(wallet.ref, Coin.ethereum, path),
        }) as EvmSignResult;
      } finally {
        await wallet.close();
        await core.shutdown();
      }

      // 1. Same signature from a key that never went near withDerivedKey.
      final key = independentKey();
      try {
        expect(publicIdentity(key).$1, publicKeyHex);
        final reference = SyncSigningCore(context).sign(
          evmFamily.encodeKeylessInput(request),
          family: evmFamily,
          coin: Coin.ethereum,
          privateKey: key,
          usedKeys: const <KeyLocator>{},
        );
        expect(listEquals(reference.encoded, result.encoded), isTrue);
      } finally {
        key.fillRange(0, key.length, 0);
      }

      // 2. Upstream recovers the signer from r ‖ s ‖ v and the pre-hash.
      final preHash = result.preHash;
      expect(preHash, isNotNull, reason: 'upstream reports the pre-hash');
      Uint8List word(Uint8List bytes) =>
          Uint8List(32)..setAll(32 - bytes.length, bytes);
      final v = result.v.isEmpty ? 0 : result.v.last;
      final signature = TWDataHandle.fromBytes(
        context,
        Uint8List.fromList([...word(result.r), ...word(result.s), v]),
      );
      final message = TWDataHandle.fromBytes(context, preHash!);
      final recovered = bindings.TWPublicKeyRecover(
        signature.pointer,
        message.pointer,
      );
      signature.dispose();
      message.dispose();
      expect(recovered, isNot(nullptr));
      final recoveredData = TWDataHandle.adopt(
        context,
        bindings.TWPublicKeyData(recovered),
      );
      try {
        expect(_hex(recoveredData.copyBytes()), publicKeyHex);
      } finally {
        recoveredData.dispose();
        bindings.TWPublicKeyDelete(recovered);
      }
    });
  });
}
