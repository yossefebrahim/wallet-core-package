/// [HDWallet]: a same-isolate owner of one upstream `TWHDWallet`.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart'
    hide DisposedError;

import '../account/account.dart';
import '../account/derivation_path.dart';
import '../address/address.dart';
import '../coin/coin.dart';
import '../coin/network.dart';
import '../core/input_checks.dart';
import '../errors/boundary.dart';
import '../errors/errors.dart';
import 'coin_bridge.dart';
import 'handles.dart';
import 'secret_buffers.dart';

/// A BIP-39/BIP-32 wallet whose upstream handle lives in **this** isolate.
///
/// **`dispose()` is the primary cleanup path.** It calls upstream's
/// `TWHDWalletDelete`, detaches the native finalizer, and marks the wallet
/// disposed; a second call does nothing. Any other member called afterwards
/// throws [DisposedError]. The native finalizer — whose callback is
/// `TWHDWalletDelete` itself and runs no Dart code — is only a fallback for a
/// wallet nobody disposed (PRD §11.2).
///
/// This is the internal, synchronous lifecycle of
/// `docs/architecture/lifecycle.md` §5, and three things follow from it
/// (§7):
///
/// 1. It is not a proxy and holds no session reference; nothing acknowledges
///    its disposal.
/// 2. It must never be shared across isolates. Two isolates each owning their
///    own handles is supported; one handle used from two isolates is not.
/// 3. Its creation and import calls take secrets as Dart values. This class
///    overwrites its own staging buffers and drops its references when a call
///    returns; it cannot erase the caller's copies (PRD §11.3).
///
/// Every operation is checked in Dart before it reaches native code
/// (PRD §16 S5), and a null or false result from upstream is reported with the
/// same typed error as the equivalent Dart-side rejection. No error message
/// and no [toString] contains a mnemonic, entropy, a passphrase, or a key
/// (threat model TM-09, TM-31).
final class HDWallet extends NativeResource {
  HDWallet._(NativeContext context, Pointer<TWHDWallet> pointer)
    : super(
        context: context,
        pointer: pointer.cast<Void>(),
        finalizer: EngineFinalizers.of(context).hdWallet,
      );

  /// Creates a wallet with a new random mnemonic of [strength] bits.
  ///
  /// [strength] must be 128, 160, 192, 224, or 256; anything else is rejected
  /// with [InvalidInputError] before any native call. [passphrase] is the
  /// BIP-39 passphrase — key material — and at most 1024 characters.
  factory HDWallet.create(
    NativeContext context, {
    int strength = 128,
    String passphrase = '',
  }) {
    checkStrength(strength);
    checkPassphrase(passphrase);
    final pass = secretString(context, passphrase, inputName: 'passphrase');
    try {
      final pointer = context.bindings.TWHDWalletCreate(strength, pass.pointer);
      if (pointer == nullptr) {
        throw const InvalidInputError(
          'upstream could not create a wallet with this strength',
          inputName: 'strength',
        );
      }
      return HDWallet._(context, pointer);
    } finally {
      pass.dispose();
    }
  }

  /// Imports a wallet from a BIP-39 English mnemonic.
  ///
  /// The word count (12, 15, 18, 21, or 24) and a length ceiling are checked
  /// in Dart; whether the words and checksum form a valid mnemonic is
  /// upstream's answer, and a rejection by either is the same
  /// [InvalidInputError] with `inputName: 'mnemonic'`.
  factory HDWallet.fromMnemonic(
    NativeContext context,
    String mnemonic, {
    String passphrase = '',
  }) {
    checkMnemonicShape(mnemonic);
    checkPassphrase(passphrase);
    return runScope(context, (scope) {
      final words = scope.use(
        secretString(context, mnemonic, inputName: 'mnemonic'),
      );
      final pass = scope.use(
        secretString(context, passphrase, inputName: 'passphrase'),
      );
      final pointer = context.bindings.TWHDWalletCreateWithMnemonic(
        words.pointer,
        pass.pointer,
      );
      if (pointer == nullptr) {
        throw const InvalidInputError(
          'not a valid BIP-39 mnemonic',
          inputName: 'mnemonic',
        );
      }
      return HDWallet._(context, pointer);
    });
  }

  /// Imports a wallet from BIP-39 entropy of 16, 20, 24, 28, or 32 bytes.
  ///
  /// [entropy] is read, never modified, and never retained.
  factory HDWallet.fromEntropy(
    NativeContext context,
    Uint8List entropy, {
    String passphrase = '',
  }) {
    checkEntropy(entropy);
    checkPassphrase(passphrase);
    return runScope(context, (scope) {
      final data = scope.use(secretData(context, entropy));
      final pass = scope.use(
        secretString(context, passphrase, inputName: 'passphrase'),
      );
      final pointer = context.bindings.TWHDWalletCreateWithEntropy(
        data.pointer,
        pass.pointer,
      );
      if (pointer == nullptr) {
        throw const InvalidInputError(
          'upstream rejected the entropy',
          inputName: 'entropy',
        );
      }
      return HDWallet._(context, pointer);
    });
  }

  /// The wallet's mnemonic.
  ///
  /// Returns a Dart `String` because it exists to be shown to a person. The
  /// string lives until it is collected and cannot be erased. Display it once
  /// and drop the reference. The native copy upstream returned is released —
  /// and zeroed by upstream — before this returns.
  ///
  /// Throws [DisposedError] after [dispose]. Throws `NativeResultError` if
  /// upstream returns no mnemonic, an empty one, or one it cannot read back:
  /// a soft native failure, which the session reports as a typed error of
  /// this one operation and survives (DECISION-12 §3.10).
  String exportMnemonic() {
    final wallet = _wallet;
    final pointer = context.bindings.TWHDWalletMnemonic(wallet);
    if (pointer == nullptr) {
      throw const NativeResultError('TWHDWalletMnemonic returned nullptr');
    }
    final handle = TWStringHandle.adopt(context, pointer);
    try {
      final mnemonic = readSecretString(handle);
      if (mnemonic.isEmpty) {
        throw const NativeResultError(
          'TWHDWalletMnemonic returned an empty mnemonic',
        );
      }
      return mnemonic;
    } finally {
      handle.dispose();
    }
  }

  /// Derives the account for [coin] on [network] in [style], at [path] or —
  /// when [path] is `null` — at the pinned registry's default path for that
  /// combination.
  ///
  /// Checked in Dart before any native call: the (coin, network, style)
  /// combination must exist at the pinned tag ([UnsupportedOperationError]),
  /// and [path] must be a well-formed BIP-32 path ([InvalidInputError] with
  /// `inputName: 'derivationPath'`).
  ///
  /// The key is derived by upstream, its public key and address are read into
  /// Dart-owned copies, and only then are the derived private key and every
  /// other temporary released — parse, release, return (DECISION-12 §3.9). The
  /// returned [Account] holds no key and no handle.
  Account deriveAccount(
    Coin coin, {
    Network network = Network.mainnet,
    AddressStyle style = AddressStyle.standard,
    String? path,
  }) {
    final wallet = _wallet;
    final derivation = resolveDerivation(coin, network, style);
    final derivationPath = path == null
        ? derivation.path
        : checkDerivationPath(path);
    final coinType = twCoinTypeOf(coin);
    final twDerivation = twDerivationOf(coin, derivation);
    final bindings = context.bindings;
    return runScope(context, (scope) {
      final pathString = readNative(
        'TWStringCreateWithUTF8Bytes',
        () => scope.string(derivationPath),
      );
      final keyPointer = bindings.TWHDWalletGetKey(
        wallet,
        coinType,
        pathString.pointer,
      );
      if (keyPointer == nullptr) {
        throw const InvalidInputError(
          'upstream could not derive a key at this derivation path',
          inputName: 'derivationPath',
        );
      }
      final key = scope.use(PrivateKeyHandle.adopt(context, keyPointer));

      final publicKeyPointer = bindings.TWPrivateKeyGetPublicKey(
        key.pointer,
        coinType,
      );
      if (publicKeyPointer == nullptr) {
        throw UnsupportedOperationError(coin, 'deriveAddress');
      }
      final publicKey = scope.use(
        PublicKeyHandle.adopt(context, publicKeyPointer),
      );

      final publicKeyData = bindings.TWPublicKeyData(publicKey.pointer);
      if (publicKeyData == nullptr) {
        throw UnsupportedOperationError(coin, 'deriveAddress');
      }
      final publicKeyHandle = scope.use(
        TWDataHandle.adopt(context, publicKeyData),
      );
      final publicKeyBytes = readNative(
        'TWPublicKeyData',
        publicKeyHandle.copyBytes,
      );

      final addressPointer = bindings.TWAnyAddressCreateWithPublicKeyDerivation(
        publicKey.pointer,
        coinType,
        twDerivation,
      );
      if (addressPointer == nullptr) {
        throw UnsupportedOperationError(coin, 'deriveAddress');
      }
      final address = scope.use(
        AnyAddressHandle.adopt(context, addressPointer),
      );
      final descriptionPointer = bindings.TWAnyAddressDescription(
        address.pointer,
      );
      if (descriptionPointer == nullptr) {
        throw UnsupportedOperationError(coin, 'deriveAddress');
      }
      final description = scope.use(
        TWStringHandle.adopt(context, descriptionPointer),
      );
      final addressString = readNative(
        'TWAnyAddressDescription',
        description.toDartString,
      );
      if (addressString.isEmpty || publicKeyBytes.isEmpty) {
        throw UnsupportedOperationError(coin, 'deriveAddress');
      }

      return Account(
        coin: coin,
        network: network,
        addressStyle: style,
        derivationPath: derivationPath,
        address: validatedAddress(addressString, coin, network),
        publicKey: publicKeyBytes.asUnmodifiableView(),
      );
    });
  }

  /// The native pointer, or [DisposedError] — the SDK's, not the bindings' —
  /// once this wallet has been disposed.
  Pointer<TWHDWallet> get _wallet {
    if (isDisposed) throw const DisposedError('HDWallet');
    return rawPointer.cast<TWHDWallet>();
  }

  @override
  void releaseNative(Pointer<Void> pointer) =>
      context.bindings.TWHDWalletDelete(pointer.cast<TWHDWallet>());
}

/// Derives the private key of [wallet] for [coin] at [derivationPath], runs
/// [use] with a read-only **view over upstream's native bytes** of it, and
/// releases the key before returning or throwing. **Internal**: the signing
/// path's only door to a key; never exported, not even by `advanced.dart`.
///
/// [derivationPath] must already have passed `checkDerivationPath`; the
/// caller validates before deriving, so that nothing is derived for a request
/// that is going to be rejected anyway.
///
/// In this order:
///
/// 1. `TWHDWalletGetKey(wallet, coin, path)` — upstream derives the key into
///    a new `TWPrivateKey`, owned from here by a [PrivateKeyHandle].
/// 2. `TWPrivateKeyData(key)` — upstream copies the key's bytes into a new
///    `TWData`, owned from here by a [TWDataHandle].
/// 3. [use] runs with `TWDataBytes(data).asTypedList(length)`: a `Uint8List`
///    whose storage *is* that `TWData`'s buffer. No Dart-heap copy of the key
///    is made here, and [use] must make none and must not retain the view —
///    it is dangling once this returns.
/// 4. In a `finally`, on every path: the `TWData` is disposed —
///    `TWDataDelete` overwrites its buffer with zeros before freeing it — and
///    then the key — `TWPrivateKeyDelete`, whose `PrivateKey` destructor
///    overwrites its bytes with zeros at the pinned commit
///    (`src/PrivateKey.h`, `~PrivateKey() { cleanup(); }`).
///
/// Throws [DisposedError] after [wallet] was disposed, before any native
/// call; [InvalidInputError] (`inputName: 'derivationPath'`) when upstream
/// derives no key at the path; and `NativeResultError` when upstream returns
/// no key bytes or a size out of range — a soft native failure of this one
/// operation (DECISION-12 §3.10). The key handle is released on those paths
/// too.
T withDerivedKey<T>(
  HDWallet wallet,
  Coin coin,
  String derivationPath,
  T Function(Uint8List privateKey) use,
) {
  final pointer = wallet._wallet;
  final context = wallet.context;
  final bindings = context.bindings;
  final coinType = twCoinTypeOf(coin);
  return runScope(context, (scope) {
    final path = readNative(
      'TWStringCreateWithUTF8Bytes',
      () => scope.string(derivationPath),
    );
    final keyPointer = bindings.TWHDWalletGetKey(
      pointer,
      coinType,
      path.pointer,
    );
    if (keyPointer == nullptr) {
      throw const InvalidInputError(
        'upstream could not derive a key at this derivation path',
        inputName: 'derivationPath',
      );
    }
    final key = scope.use(PrivateKeyHandle.adopt(context, keyPointer));
    final dataPointer = bindings.TWPrivateKeyData(key.pointer);
    if (dataPointer == nullptr) {
      throw const NativeResultError('TWPrivateKeyData returned nullptr');
    }
    final data = scope.use(TWDataHandle.adopt(context, dataPointer));
    final length = readNative('TWPrivateKeyData', () => data.length);
    if (length == 0) {
      throw const NativeResultError('TWPrivateKeyData returned no bytes');
    }
    final bytes = bindings.TWDataBytes(data.pointer);
    if (bytes == nullptr) {
      throw const NativeResultError('TWDataBytes returned nullptr');
    }
    return use(bytes.asTypedList(length));
  });
}
