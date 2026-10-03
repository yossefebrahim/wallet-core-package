/// The key-field check: key-less signing-input bytes carry none of the
/// family's key fields (`docs/architecture/signing.md` §6 step 3,
/// DECISION-13 §4.4). **Internal**: never exported.
///
/// It works on **bytes**, not on a request, because that is what every
/// consumer of it holds: the same-isolate core (Approach A), the C adapter's
/// Dart side (Approach B, T1.13), and the worker, which receives bytes.
library;

import 'dart:typed_data';

import 'package:protobuf/protobuf.dart' show GeneratedMessage, PbFieldType;

import '../errors/errors.dart';
import '../families/family.dart';
import '../requests/requests.dart';
import 'sign_result.dart';

/// Throws [InvalidInputError] (`inputName: 'signingInput'`) unless
/// [keylessInput] decodes as [family]'s signing input and carries none of the
/// fields in its reviewed key-field list, at any depth.
///
/// A key field present means the family encoder — or whoever produced the
/// bytes — is defective, and the operation must stop before any key is
/// touched. The error names the field, never its contents.
///
/// **The decode is half of the check, not a preliminary.** Injection
/// (`keyedInputParts`) works on bytes and is correct only for a complete,
/// well-formed message of the family's signing-input type with every key
/// field absent. A successful decode is what establishes "complete and
/// well-formed" — bytes ending inside a length-delimited field do not decode
/// — and the walk establishes "no key field". Every path that injects a key
/// calls this first; none may skip it, including any future path that takes
/// caller-supplied bytes.
///
/// **Nothing the walk cannot see is accepted.** The walk sees only fields the
/// schema names; anything else the decoder keeps as opaque unknown-field
/// bytes, which the walk does not descend into. So the input is also
/// rejected when, at any depth, it carries a group (wire types 3/4) — known
/// or unknown — or any unknown field: a key field nested inside either could
/// not be found, and the family encoder never writes one.
///
/// Throws [StateError] when [family] decodes the bytes as some other message
/// than the one it names, or when the generated classes were compiled without
/// message names; both are defects of this build, not of the input.
void checkKeylessInput(
  Uint8List keylessInput,
  TransactionFamily<TransactionRequest, SignResult> family,
) {
  final GeneratedMessage message;
  try {
    message = family.decodeSigningInput(keylessInput);
  } on Object {
    // Not only `InvalidProtocolBufferException`: on some malformed lengths the
    // protobuf runtime throws a `RangeError` from inside its reader.
    throw InvalidInputError(
      'the key-less signing input does not decode as '
      '${family.signingInputMessage}',
      inputName: 'signingInput',
    );
  }
  final decodedAs = message.info_.qualifiedMessageName;
  if (decodedAs != family.signingInputMessage) {
    throw StateError(
      'the family decodes ${family.signingInputMessage} as "$decodedAs"',
    );
  }
  final present = family.keyFields.presentIn(message);
  if (present.isNotEmpty) {
    throw InvalidInputError(
      'the key-less signing input already carries the key field '
      '${present.first.messagePath}.${present.first.fieldName}; the family '
      'encoder is defective, and no key was injected',
      inputName: 'signingInput',
    );
  }
  final opaque = _opaqueFieldIn(message);
  if (opaque != null) {
    throw InvalidInputError(
      'the key-less signing input carries $opaque, which the key-field check '
      'cannot see into; no key was injected',
      inputName: 'signingInput',
    );
  }
}

/// A description of the first group or unknown field anywhere in [message] —
/// by message name and field number, never by contents — or `null` when
/// there is none. Walks the same fields as `KeyFieldList.presentIn`.
String? _opaqueFieldIn(GeneratedMessage message) {
  final info = message.info_;
  final unknown = message.unknownFields;
  if (unknown.isNotEmpty) {
    return 'an unknown field (${info.qualifiedMessageName} field '
        '${unknown.asMap().keys.first})';
  }
  for (final field in info.byIndex) {
    if (!field.isGroupOrMessage && !field.isMapField) continue;
    final value = message.getFieldOrNull(field.tagNumber);
    if (value == null || value is List && value.isEmpty) continue;
    if (field.type & PbFieldType.GROUP_BIT != 0) {
      return 'a group (${info.qualifiedMessageName} field ${field.tagNumber})';
    }
    final Iterable<Object?> children = switch (value) {
      final GeneratedMessage child => [child],
      final List<Object?> list => list,
      final Map<Object?, Object?> map => map.values,
      _ => const [],
    };
    for (final child in children) {
      if (child is! GeneratedMessage) continue;
      final found = _opaqueFieldIn(child);
      if (found != null) return found;
    }
  }
  return null;
}
