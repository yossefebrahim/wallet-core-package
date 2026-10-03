/// The sealed request hierarchies (`docs/architecture/signing.md` §3).
///
/// A request is an immutable, validated, plain-Dart description of what to
/// sign. It crosses isolates freely, is safe to log, and **never contains key
/// material** — not a private key, not a mnemonic, not a passphrase
/// (AGENTS.md rule 6, PRD §10.2). A request names keys only through
/// [KeyLocator]s, which are names and not secrets.
///
/// The bases are `sealed`, so every family's request type lives in this one
/// library, each in its own `part` under a family directory.
library;

import 'dart:typed_data';

import '../coin/chain_family.dart';
import '../coin/coin.dart';
import '../coin/network.dart';
import '../errors/errors.dart';
import '../signing/key_locator.dart';

part 'evm/evm_transaction_request.dart';

/// Base of every transaction request.
sealed class TransactionRequest {
  /// The coin the transaction is for.
  Coin get coin;

  /// The network the transaction is for.
  Network get network;

  /// Every locator this request needs, collected from wherever they appear in
  /// it. For most families this is empty and the caller supplies the set; for
  /// UTXO it is the per-input locators.
  Set<KeyLocator> get keyLocators;
}

/// Base of every message-signing request. No member exists at this version;
/// EVM messages are T2.7's.
sealed class MessageRequest {
  /// The coin whose message format and key the request is for.
  Coin get coin;
}
