/// The family boundary: [TransactionFamily], [KeyFieldList], [KeyFieldEntry]
/// (`docs/architecture/signing.md` §6, DECISION-13 §4.4). **Internal**: never
/// exported.
///
/// Family code is the only place upstream's message shapes are known, and it
/// never sees a key: it encodes key-less inputs and parses outputs. Only the
/// signing core injects a key (AGENTS.md rule 6, PRD §11.4).
library;

import 'dart:typed_data';

import 'package:protobuf/protobuf.dart' show GeneratedMessage;

import '../coin/chain_family.dart';
import '../coin/coin.dart';
import '../requests/requests.dart';
import '../signing/key_locator.dart';
import '../signing/sign_result.dart';

/// What every chain family implements.
///
/// [R] is the family's request type and [S] its result type.
abstract interface class TransactionFamily<
  R extends TransactionRequest,
  S extends SignResult
> {
  /// The facade family whose coins this family signs for.
  ChainFamily get chainFamily;

  /// The fully-qualified name of upstream's signing-input message, e.g.
  /// `'TW.Ethereum.Proto.SigningInput'` — the root the key-field check walks
  /// from and the message the signing core injects into.
  String get signingInputMessage;

  /// Encodes [request] into upstream's serialized signing input **with no key
  /// field set**.
  ///
  /// This function never receives key bytes and has no parameter that could
  /// carry them. That is the whole point of the signature.
  ///
  /// The result must be one complete, well-formed [signingInputMessage] with
  /// every key field absent: the signing core prepends the key field to
  /// exactly these bytes, after `checkKeylessInput` has decoded them.
  Uint8List encodeKeylessInput(R request);

  /// Decodes serialized signing-input bytes into the generated message, for
  /// the key-field check only. Throws the protobuf runtime's
  /// `InvalidProtocolBufferException` on bytes that do not decode.
  GeneratedMessage decodeSigningInput(Uint8List bytes);

  /// Parses upstream's serialized output into a typed result.
  ///
  /// The bytes are treated as untrusted, whatever produced them: the error
  /// code and message are read **first** and mapped to `SigningError` without
  /// interpreting the rest; field sizes are bounded before any copy; and an
  /// output whose shape does not match the family fails rather than being
  /// coerced.
  S parseSigningOutput(
    Uint8List bytes, {
    required Coin coin,
    required Set<KeyLocator> usedKeys,
  });

  /// The roles this family needs filled, in order of necessity.
  List<KeyRole> requiredRoles(R request);

  /// The reviewed list of fields that carry key material in this family's
  /// messages. See [KeyFieldList].
  KeyFieldList get keyFields;

  /// The field of [signingInputMessage] the key for [role] is injected into.
  /// Throws [ArgumentError] for a role this family has no slot for.
  KeyFieldEntry injectionField(KeyRole role);
}

/// The reviewed per-family list of key-carrying fields.
///
/// Two layers, and the test between them is the mechanism (DECISION-13 §6 Q4):
///
/// * a **generated** inventory, `key_fields.json`, produced from the pinned
///   schema descriptors by a recursive walk;
/// * this **reviewed** list, written by a human, naming both the field and
///   the message it occurs in.
///
/// A unit test asserts the reviewed list equals the generated set for the
/// family. The signing core checks against the reviewed list.
final class KeyFieldList {
  /// Creates a list of [entries].
  const KeyFieldList(this.entries);

  /// One entry per key-carrying field.
  final List<KeyFieldEntry> entries;

  /// Every entry present anywhere in [message], walking every set message
  /// field, repeated message field, and message-valued map entry recursively.
  ///
  /// "Present" means on the wire, not merely non-empty: a singular field
  /// decoded with zero bytes counts, a repeated one with at least one element
  /// counts, and so does a field number of a listed field that arrived as an
  /// unknown field (a wire-type mismatch). The check fails closed.
  ///
  /// Throws [StateError] when the generated classes were compiled without
  /// message names (`protobuf.omit_message_names`): the walk matches on
  /// names, and with none it could only ever answer "nothing found".
  List<KeyFieldEntry> presentIn(GeneratedMessage message) {
    final found = <KeyFieldEntry>[];
    _walk(message, found);
    return found;
  }

  void _walk(GeneratedMessage message, List<KeyFieldEntry> found) {
    final info = message.info_;
    final name = info.qualifiedMessageName;
    if (name.isEmpty) {
      throw StateError(
        'protobuf message names were omitted from this build; the key-field '
        'check cannot run',
      );
    }
    for (final entry in entries) {
      if (entry.messagePath != name) continue;
      final value = message.getFieldOrNull(entry.fieldNumber);
      final present = entry.repeated
          ? value is List && value.isNotEmpty
          : value != null;
      if (present || message.unknownFields.hasField(entry.fieldNumber)) {
        found.add(entry);
      }
    }
    for (final field in info.byIndex) {
      if (!field.isGroupOrMessage && !field.isMapField) continue;
      final value = message.getFieldOrNull(field.tagNumber);
      if (value is GeneratedMessage) {
        _walk(value, found);
      } else if (value is List) {
        for (final element in value) {
          if (element is GeneratedMessage) _walk(element, found);
        }
      } else if (value is Map) {
        for (final element in value.values) {
          if (element is GeneratedMessage) _walk(element, found);
        }
      }
    }
  }
}

/// One key-carrying field: the message it occurs in, its name and number, and
/// whether it is repeated.
///
/// [fieldNumber] goes beyond the sketch of `docs/architecture/signing.md` §6:
/// the key-field check and the injection both work on wire field numbers, so
/// that neither depends on field names surviving compilation.
final class KeyFieldEntry {
  /// Creates an entry.
  const KeyFieldEntry({
    required this.messagePath,
    required this.fieldName,
    required this.fieldNumber,
    required this.repeated,
  });

  /// The fully-qualified message name, e.g. `'TW.Ethereum.Proto.SigningInput'`.
  final String messagePath;

  /// The field's name in the `.proto` file, e.g. `'private_key'`.
  final String fieldName;

  /// The field's number in the `.proto` file.
  final int fieldNumber;

  /// Whether the field is `repeated`.
  final bool repeated;

  @override
  bool operator ==(Object other) =>
      other is KeyFieldEntry &&
      other.messagePath == messagePath &&
      other.fieldName == fieldName &&
      other.fieldNumber == fieldNumber &&
      other.repeated == repeated;

  @override
  int get hashCode =>
      Object.hash(messagePath, fieldName, fieldNumber, repeated);

  @override
  String toString() =>
      '$messagePath.$fieldName = $fieldNumber${repeated ? ' (repeated)' : ''}';
}
