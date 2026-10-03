/// The reviewed key-field list of the EVM family. **Internal**.
///
/// Written by hand from `Ethereum.proto` at the pinned upstream commit
/// `d692ac27749d0c615e17c751b70ab4f0aa75c59b` (tag 4.8.0), DECISION-13 §3.1.
/// `test/signing/evm_family_test.dart` asserts it equals the generated
/// `key_fields.json` for every message reachable from the signing input and
/// every message of `Ethereum.proto`; an upstream change that adds, removes,
/// renames, or renumbers a key field fails that test until this list is
/// updated in the same change (DECISION-13 §6 Q4).
library;

import '../family.dart';

/// Every field of upstream's Ethereum messages that carries key material.
const KeyFieldList evmKeyFields = KeyFieldList(<KeyFieldEntry>[
  // The transaction signing input: `bytes private_key = 9;`.
  KeyFieldEntry(
    messagePath: 'TW.Ethereum.Proto.SigningInput',
    fieldName: 'private_key',
    fieldNumber: 9,
    repeated: false,
  ),
  // The message signing input (T2.7): `bytes private_key = 1;`.
  KeyFieldEntry(
    messagePath: 'TW.Ethereum.Proto.MessageSigningInput',
    fieldName: 'private_key',
    fieldNumber: 1,
    repeated: false,
  ),
]);
