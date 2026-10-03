/// Shared pieces of the signing-path tests: the host library's identity, a
/// signing core that records whether — and how — it was called, and the
/// request and locators the tests sign with.
library;

import 'dart:typed_data';

import 'package:wallet_core_flutter/src/families/family.dart';
import 'package:wallet_core_flutter/src/requests/requests.dart';
import 'package:wallet_core_flutter/src/signing/key_locator.dart';
import 'package:wallet_core_flutter/src/signing/sign_result.dart';
import 'package:wallet_core_flutter/src/signing/signing_core.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart' show Coin;
import 'package:wallet_core_flutter_native/wallet_core_flutter_native.dart'
    show ManifestIdentity;

/// The host library's identity: `tools/native_build/build_apple.sh` at the
/// pinned commit, artifact set `as_4.8.0_000`, built locally.
const ManifestIdentity hostIdentity = ManifestIdentity(
  artifactSetId: 'as_4.8.0_000',
  upstreamCommit: 'd692ac27749d0c615e17c751b70ab4f0aa75c59b',
);

/// A [SigningCore] that counts its calls and records what it was given —
/// never the key itself, only its length — and signs through [delegate].
final class RecordingCore implements SigningCore {
  /// Records, then signs through [delegate].
  RecordingCore(this.delegate);

  /// The core that actually signs.
  final SigningCore delegate;

  /// How many times [sign] was called.
  int calls = 0;

  /// The length of the last key handed in.
  int? lastKeyLength;

  /// The coin of the last call.
  Coin? lastCoin;

  /// The `usedKeys` of the last call.
  Set<KeyLocator>? lastUsedKeys;

  @override
  S sign<S extends SignResult>(
    Uint8List keylessInput, {
    required TransactionFamily<TransactionRequest, S> family,
    required Coin coin,
    required Uint8List privateKey,
    required Set<KeyLocator> usedKeys,
  }) {
    calls++;
    lastKeyLength = privateKey.length;
    lastCoin = coin;
    lastUsedKeys = usedKeys;
    return delegate.sign(
      keylessInput,
      family: family,
      coin: coin,
      privateKey: privateKey,
      usedKeys: usedKeys,
    );
  }
}

/// An EIP-1559 Ethereum transfer to [to] — the shape of
/// `ethereum-sign-eip1559-1`, with values that are not the vector's: the
/// tests that use it compare two signers with each other, not with a vector.
EvmTransactionRequest transferTo(String to, {Coin? coin, int nonce = 6}) =>
    EvmTransactionRequest.transfer(
      coin: coin ?? Coin.ethereum,
      chainId: 1,
      nonce: BigInt.from(nonce),
      to: to,
      valueWei: BigInt.from(543210987654321),
      maxFeePerGas: BigInt.from(3000000000),
      maxPriorityFeePerGas: BigInt.from(2000000000),
      gasLimit: BigInt.from(21100),
    );

/// [address] with the case of its first hexadecimal letter flipped: still
/// forty hex digits after `0x`, so it passes the request's syntax check and
/// upstream's `TWAnyAddressIsValid`, but its EIP-55 checksum no longer holds.
String breakChecksum(String address) {
  for (var i = 2; i < address.length; i++) {
    final char = address[i];
    final flipped = char.toUpperCase() == char
        ? char.toLowerCase()
        : char.toUpperCase();
    if (flipped != char) {
      return '${address.substring(0, i)}$flipped${address.substring(i + 1)}';
    }
  }
  throw ArgumentError.value(address, 'address', 'has no letter to flip');
}
