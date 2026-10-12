/// The sealed request hierarchies (`docs/architecture/signing.md` §3).
///
/// A request is an immutable, validated, plain-Dart description of what to
/// sign. It crosses isolates freely, is safe to log, and **never contains key
/// material** — not a private key, not a mnemonic, not a passphrase
/// (AGENTS.md rule 6, PRD §10.2). A request names keys only through
/// [KeyLocator]s, which are names and not secrets.
///
/// The bases are `sealed`, so every family's request type lives in this one
/// library, each in its own `part` under a family directory. The bases and the
/// value types the families share (`OutPoint`, `UtxoInput`) are in `base.dart`.
library;

import 'dart:typed_data';

import '../coin/chain_family.dart';
import '../coin/coin.dart';
import '../coin/network.dart';
import '../errors/errors.dart';
import '../signing/key_locator.dart';

part 'base.dart';
part 'evm/evm_transaction_request.dart';
part 'utxo/utxo_transaction_request.dart';
