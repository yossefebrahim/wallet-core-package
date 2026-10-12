part of '../requests.dart';

/// The most bytes an [EvmMessageRequest] accepts: the personal message's
/// UTF-8 bytes, or the typed-data document's UTF-8 bytes — 1 MiB.
///
/// An SDK policy, far below the bindings' native buffer ceiling
/// (`maxNativeBufferBytes`): a message is something a person is asked to read
/// and approve, and typed-data documents of real applications are a few KiB.
/// Checked at construction, before the document is parsed or copied. Not
/// exported: the constructors' documentation states the bound, and a test pins
/// it below the ceiling.
const int maxEvmMessageBytes = 1024 * 1024;

/// The kind of message an [EvmMessageRequest] carries, and the kind an
/// `EvmMessageSignResult` reports.
enum EvmMessageType {
  /// A personal-style message (EIP-191 `personal_sign`): upstream's
  /// `MessageType_legacy`.
  personal,

  /// Typed structured data (EIP-712 v4): upstream's `MessageType_typed`.
  typedData,
}

/// A message to sign on an EVM chain (`docs/architecture/signing.md` §3.1).
///
/// **Validated at construction.** Each constructor throws [InvalidInputError]
/// naming the offending input when [coin] is not in [ChainFamily.evm]
/// (`inputName: 'coin'`), the message is empty or longer than 1 MiB
/// (`inputName: 'message'` or `'typedData'`), or [chainId] is below 1
/// (`inputName: 'chainId'`). A personal message must be valid UTF-8 — upstream
/// takes it as a string — and a typed-data document must parse as JSON. The
/// document is checked for well-formedness **only**: whether it is a valid
/// EIP-712 structure (types, primary type, domain, values) is upstream's
/// answer, asked for at sign time and reported as a `SigningError`. No error
/// quotes the message or the document.
///
/// [chainId] selects an EIP-155 replay-protected variant. **Not signed at this
/// version**: a request with a [chainId] is constructible, and the signer
/// rejects it with `UnsupportedOperationError` before any key is derived,
/// because this SDK holds no vector for it yet.
///
/// Immutable: the personal message is copied on the way in and exposed as a
/// read-only view.
final class EvmMessageRequest implements MessageRequest {
  EvmMessageRequest._({
    required this.coin,
    required this.type,
    this.chainId,
    Uint8List? messageBytes,
    this.typedDataJson,
  }) : _message = messageBytes {
    if (coin.family != ChainFamily.evm) {
      throw InvalidInputError(
        '${coin.id} is not an EVM coin; an EVM request needs one',
        inputName: 'coin',
      );
    }
    if (chainId case final id? when id < 1) {
      throw const InvalidInputError(
        'chainId must be at least 1',
        inputName: 'chainId',
      );
    }
  }

  /// A personal-style message ([EvmMessageType.personal]).
  ///
  /// [message] is the message's bytes and must be valid UTF-8, between 1 byte
  /// and 1 MiB: upstream's message-signing input carries the message as a
  /// string, so bytes that are not text cannot be signed through it. [message]
  /// is copied.
  factory EvmMessageRequest.personal(
    Uint8List message, {
    required Coin coin,
    int? chainId,
  }) {
    if (message.isEmpty) {
      throw const InvalidInputError(
        'message must not be empty',
        inputName: 'message',
      );
    }
    if (message.length > maxEvmMessageBytes) {
      throw const InvalidInputError(
        'message is longer than $maxEvmMessageBytes bytes',
        inputName: 'message',
      );
    }
    try {
      evmMessageText(message);
    } on FormatException {
      throw const InvalidInputError(
        'message must be valid UTF-8',
        inputName: 'message',
      );
    }
    return EvmMessageRequest._(
      coin: coin,
      type: EvmMessageType.personal,
      chainId: chainId,
      messageBytes: Uint8List.fromList(message),
    );
  }

  /// Typed structured data ([EvmMessageType.typedData]): [json] is the
  /// EIP-712 document, between 1 byte and 1 MiB of UTF-8 and well-formed JSON.
  /// Its EIP-712 meaning is upstream's to judge.
  factory EvmMessageRequest.typedData(
    String json, {
    required Coin coin,
    int? chainId,
  }) {
    // The UTF-8 length is at least the number of UTF-16 code units, so a
    // string over the bound is refused before anything is encoded or parsed.
    if (json.length > maxEvmMessageBytes ||
        utf8.encode(json).length > maxEvmMessageBytes) {
      throw const InvalidInputError(
        'typedData is longer than $maxEvmMessageBytes bytes',
        inputName: 'typedData',
      );
    }
    try {
      jsonDecode(json);
    } on FormatException {
      throw const InvalidInputError(
        'typedData is not well-formed JSON',
        inputName: 'typedData',
      );
    }
    return EvmMessageRequest._(
      coin: coin,
      type: EvmMessageType.typedData,
      chainId: chainId,
      typedDataJson: json,
    );
  }

  @override
  final Coin coin;

  /// Which kind of message this is.
  final EvmMessageType type;

  /// The EIP-155 chain id of a replay-protected variant, or `null`. Not
  /// signed at this version (see the class documentation).
  final int? chainId;

  final Uint8List? _message;

  /// The personal message's bytes, as a read-only view; `null` for typed
  /// data.
  Uint8List? get message => _message?.asUnmodifiableView();

  /// The typed-data JSON document; `null` for a personal message.
  final String? typedDataJson;

  /// The kind, the coin, and the message's length — never its content.
  @override
  String toString() {
    final length = _message?.length ?? utf8.encode(typedDataJson!).length;
    return 'EvmMessageRequest.${type.name}(${coin.id}, $length bytes'
        '${chainId == null ? '' : ', chainId: $chainId'})';
  }
}

/// [bytes] as the string upstream's message-signing input carries, exactly:
/// every byte survives the round trip.
///
/// `utf8.decode` drops a leading byte order mark, which would sign a message
/// other than the caller's, so it is put back. Throws [FormatException] for
/// bytes that are not valid UTF-8, never quoting them.
String evmMessageText(Uint8List bytes) {
  final text = utf8.decode(bytes);
  final hasBom =
      bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF;
  return hasBom ? '﻿$text' : text;
}
