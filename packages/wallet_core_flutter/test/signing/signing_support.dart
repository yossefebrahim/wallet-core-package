/// Shared pieces of the signing-path tests: the host library's identity, a
/// signing core that records whether — and how — it was called, and the
/// request and locators the tests sign with.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:wallet_core_flutter/advanced.dart' show NativeContext;
import 'package:wallet_core_flutter/src/engine/handles.dart';
import 'package:wallet_core_flutter/src/engine/secret_buffers.dart';
import 'package:wallet_core_flutter/src/families/evm/evm_family.dart';
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
/// never the key's bytes, only its handle and whether that handle was live —
/// and signs through [delegate].
final class RecordingCore implements SigningCore {
  /// Records, then signs through [delegate].
  RecordingCore(this.delegate);

  /// The core that actually signs.
  final SigningCore delegate;

  /// How many times [sign] was called.
  int calls = 0;

  /// The last key handle handed in. Kept only so a test can check, after the
  /// reply, that the handler disposed it; never read through.
  PrivateKeyHandle? lastKey;

  /// Whether [lastKey] was live (not yet disposed) when it was handed in.
  bool? lastKeyWasLive;

  /// The coin of the last call.
  Coin? lastCoin;

  /// The `usedKeys` of the last call.
  Set<KeyLocator>? lastUsedKeys;

  @override
  S sign<S extends SignResult>(
    Uint8List keylessInput, {
    required TransactionFamily<TransactionRequest, S> family,
    required Coin coin,
    required PrivateKeyHandle privateKey,
    required Set<KeyLocator> usedKeys,
  }) {
    calls++;
    lastKey = privateKey;
    lastKeyWasLive = !privateKey.isDisposed;
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

/// Runs [use] with a `TWPrivateKey` made from [keyBytes] by upstream's
/// `TWPrivateKeyCreateWithData`, and releases it — and the `TWData` it was
/// made from — before returning or throwing. For the core tests, which sign
/// a published vector's key rather than a derived one.
///
/// Throws [StateError] when upstream rejects [keyBytes] as a key; the message
/// names no byte of it.
T withKeyHandle<T>(
  NativeContext context,
  Uint8List keyBytes,
  T Function(PrivateKeyHandle key) use,
) {
  final data = secretData(context, keyBytes);
  PrivateKeyHandle? key;
  try {
    final pointer = context.bindings.TWPrivateKeyCreateWithData(data.pointer);
    if (pointer == nullptr) {
      throw StateError('upstream rejected the test key');
    }
    key = PrivateKeyHandle.adopt(context, pointer);
    return use(key);
  } finally {
    key?.dispose();
    data.dispose();
  }
}

/// Whether [haystack] contains [needle] as a contiguous run. A boolean, so a
/// failing assertion prints neither.
bool containsRun(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}

/// The length of the key field for a 32-byte key: tag, length, key.
final int keyFieldLength = lengthDelimitedHeader(9, 32).length + 32;

/// REVIEW B finding 1's input: the key-less bytes of a contract call to [to]
/// whose calldata is exactly as long as the key field, cut so that the bytes
/// end right after the calldata's length prefix. A key field *appended* to
/// these bytes becomes the calldata — a signed, broadcastable transaction
/// carrying the key; prepended, it stays a field of its own.
Uint8List truncatedKeylessInput(String to) {
  final complete = evmFamily.encodeKeylessInput(
    EvmTransactionRequest.contractCall(
      coin: Coin.ethereum,
      chainId: 1,
      nonce: BigInt.one,
      to: to,
      data: Uint8List(keyFieldLength)..fillRange(0, keyFieldLength, 0xaa),
      maxFeePerGas: BigInt.one,
      maxPriorityFeePerGas: BigInt.one,
      gasLimit: BigInt.from(60000),
    ),
  );
  return Uint8List.sublistView(complete, 0, complete.length - keyFieldLength);
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
