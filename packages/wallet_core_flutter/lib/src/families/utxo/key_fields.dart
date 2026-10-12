/// The reviewed key-field list of the UTXO family. **Internal**.
///
/// Written by hand from `Bitcoin.proto` and `BitcoinV2.proto` at the pinned
/// upstream commit `d692ac27749d0c615e17c751b70ab4f0aa75c59b` (tag 4.8.0),
/// DECISION-13 §3.1. `test/families/utxo/utxo_family_test.dart` asserts it
/// equals the generated `key_fields.json` for every message of `Bitcoin.proto`
/// and every message reachable from its signing input; an upstream change
/// that adds, removes, renames, or renumbers a key field fails that test
/// until this list is updated in the same change (DECISION-13 §6 Q4).
library;

import '../family.dart';

/// Every field of upstream's Bitcoin messages that carries key material.
const KeyFieldList utxoKeyFields = KeyFieldList(<KeyFieldEntry>[
  // The signing input: `repeated bytes private_key = 6;` — one 32-byte key per
  // distinct key, matched to inputs by script, not by position.
  KeyFieldEntry(
    messagePath: 'TW.Bitcoin.Proto.SigningInput',
    fieldName: 'private_key',
    fieldNumber: 6,
    repeated: true,
  ),
  // `signing_v2` (field 21) holds the BitcoinV2 signing input, whose own key
  // field is one message down. This family never sets `signing_v2`; the entry
  // is listed so that the key-field check walks into it and refuses a
  // key-less input that does.
  KeyFieldEntry(
    messagePath: 'TW.BitcoinV2.Proto.SigningInput',
    fieldName: 'private_keys',
    fieldNumber: 1,
    repeated: true,
  ),
]);
