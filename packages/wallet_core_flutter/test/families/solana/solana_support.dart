/// Shared pieces of the Solana tests: the request a sign vector's `input` map
/// describes, and upstream's base58 decoder for the vector's key.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:wallet_core_flutter/src/requests/requests.dart';
import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart'
    show NativeContext, TWDataHandle, TWStringHandle;

/// The vector `solana-sign-legacy-1`, whose `input` and `expected` the tests
/// read from the inventory.
const String signVectorId = 'solana-sign-legacy-1';

/// The vector `solana-address-n/a-1`.
const String addressVectorId = 'solana-address-n/a-1';

/// The transfer of a `sign`/`legacy` vector, built from its `input` map —
/// every value read from the inventory, none copied into the test.
SolanaTransactionRequest vectorRequest(Map<dynamic, dynamic> input) =>
    SolanaTransactionRequest.transfer(
      to: input['to_address'] as String,
      lamports: int.parse(input['lamports'] as String),
      recentBlockhash: input['recent_blockhash'] as String,
    );

/// [text] decoded by upstream's `TWBase58DecodeNoCheck` — the decoder the
/// upstream test itself uses for the vector's key (`Base58::decode`, no
/// checksum). Tests only: the SDK never converts a key.
Uint8List base58DecodeByUpstream(NativeContext context, String text) {
  final string = TWStringHandle.fromString(context, text);
  try {
    final pointer = context.bindings.TWBase58DecodeNoCheck(string.pointer);
    if (pointer == nullptr) {
      throw StateError('upstream could not decode the base58 text');
    }
    final data = TWDataHandle.adopt(context, pointer);
    try {
      return data.copyBytes();
    } finally {
      data.dispose();
    }
  } finally {
    string.dispose();
  }
}
