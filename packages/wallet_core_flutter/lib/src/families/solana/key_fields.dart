/// The reviewed key-field list of the Solana family. **Internal**.
///
/// Written by hand from `Solana.proto` at the pinned upstream commit
/// `d692ac27749d0c615e17c751b70ab4f0aa75c59b` (tag 4.8.0), DECISION-13 §3.1.
/// `test/families/solana/solana_family_test.dart` asserts it equals the
/// generated `key_fields.json` for every message reachable from the signing
/// input and every message of `Solana.proto`; an upstream change that adds,
/// removes, renames, or renumbers a key field fails that test until this list
/// is updated in the same change (DECISION-13 §6 Q4).
library;

import '../family.dart';

/// Every field of upstream's Solana messages that carries key material.
///
/// Two of them are injected into `SigningInput` by the signing core
/// ([solanaSignerKeyField] and [solanaFeePayerKeyField]); the other two are
/// listed so that the key-field check rejects them, and are never injected.
const KeyFieldList solanaKeyFields = KeyFieldList(<KeyFieldEntry>[
  // The transaction signing input: `bytes private_key = 1;`.
  solanaSignerKeyField,
  // The optional external fee payer: `bytes fee_payer_private_key = 17;`.
  // Wired to `KeyRole.feePayer`; the public request does not expose a fee
  // payer yet, so no request needs the slot.
  solanaFeePayerKeyField,
  // Nested, one message down: `CreateNonceAccount.nonce_account_private_key
  // = 3`, reachable through the signing input's `transaction_type` oneof.
  // Never injected and not expressible by a request; listed so that bytes
  // carrying it are rejected, which only a recursive walk finds.
  KeyFieldEntry(
    messagePath: 'TW.Solana.Proto.CreateNonceAccount',
    fieldName: 'nonce_account_private_key',
    fieldNumber: 3,
    repeated: false,
  ),
  // The message signing input (not a transaction): `bytes private_key = 1;`.
  KeyFieldEntry(
    messagePath: 'TW.Solana.Proto.MessageSigningInput',
    fieldName: 'private_key',
    fieldNumber: 1,
    repeated: false,
  ),
]);

/// `SigningInput.private_key`, the sender's key: [KeyRole.primary]'s slot.
const KeyFieldEntry solanaSignerKeyField = KeyFieldEntry(
  messagePath: 'TW.Solana.Proto.SigningInput',
  fieldName: 'private_key',
  fieldNumber: 1,
  repeated: false,
);

/// `SigningInput.fee_payer_private_key`, an external fee payer's key:
/// [KeyRole.feePayer]'s slot.
const KeyFieldEntry solanaFeePayerKeyField = KeyFieldEntry(
  messagePath: 'TW.Solana.Proto.SigningInput',
  fieldName: 'fee_payer_private_key',
  fieldNumber: 17,
  repeated: false,
);
