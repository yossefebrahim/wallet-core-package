// `EvmMessageRequest`: validation at construction, the copy and the read-only
// views, and that no error or rendering quotes the message. Pure Dart.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/src/requests/requests.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart'
    show Coin, InvalidInputError;
import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart'
    show maxNativeBufferBytes;

import 'message_vector.dart';

Matcher _invalid(String inputName) => throwsA(
  isA<InvalidInputError>().having((e) => e.inputName, 'inputName', inputName),
);

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  group('EvmMessageRequest.personal', () {
    test('accepts the personal vector and keeps its bytes as a copy', () {
      final vector = MessageVector.load(personalVectorId);
      final source = _bytes(vector.input['message'] as String);
      final request = personalRequest(vector);
      source[0] = 0;
      expect(request.type, EvmMessageType.personal);
      expect(request.coin, Coin.ethereum);
      expect(request.chainId, isNull);
      expect(utf8.decode(request.message!), vector.input['message']);
      expect(request.typedDataJson, isNull);
      expect(() => request.message![0] = 1, throwsUnsupportedError);
    });

    test('rejects an empty message, naming message', () {
      expect(
        () => EvmMessageRequest.personal(Uint8List(0), coin: Coin.ethereum),
        _invalid('message'),
      );
    });

    test('rejects a message of more than 1 MiB, accepts exactly 1 MiB', () {
      expect(
        EvmMessageRequest.personal(
          Uint8List(maxEvmMessageBytes)..fillRange(0, maxEvmMessageBytes, 0x61),
          coin: Coin.ethereum,
        ).message,
        hasLength(maxEvmMessageBytes),
      );
      expect(
        () => EvmMessageRequest.personal(
          Uint8List(maxEvmMessageBytes + 1)
            ..fillRange(0, maxEvmMessageBytes + 1, 0x61),
          coin: Coin.ethereum,
        ),
        _invalid('message'),
      );
    });

    test('the bound is far below the native buffer ceiling', () {
      expect(maxEvmMessageBytes, lessThan(maxNativeBufferBytes ~/ 8));
    });

    test('rejects bytes that are not UTF-8, naming message and quoting '
        'nothing', () {
      for (final bad in <List<int>>[
        [0xFF, 0xFE, 0x41],
        [0xC3],
        [0xED, 0xA0, 0x80],
      ]) {
        expect(
          () => EvmMessageRequest.personal(
            Uint8List.fromList(bad),
            coin: Coin.ethereum,
          ),
          _invalid('message'),
        );
      }
    });

    test('a leading byte order mark survives: the text round-trips to the '
        'same bytes', () {
      final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, 0x41]);
      final request = EvmMessageRequest.personal(bytes, coin: Coin.ethereum);
      expect(utf8.encode(evmMessageText(request.message!)), bytes);
    });

    test('rejects a coin outside the EVM family, naming coin', () {
      expect(
        () => EvmMessageRequest.personal(_bytes('Foo'), coin: Coin.bitcoin),
        _invalid('coin'),
      );
    });

    test('rejects a chain id below 1, accepts 1 and records it', () {
      for (final bad in [0, -1]) {
        expect(
          () => EvmMessageRequest.personal(
            _bytes('Foo'),
            coin: Coin.ethereum,
            chainId: bad,
          ),
          _invalid('chainId'),
        );
      }
      expect(
        EvmMessageRequest.personal(
          _bytes('Foo'),
          coin: Coin.ethereum,
          chainId: 1,
        ).chainId,
        1,
      );
    });

    test('the rendering names the kind, coin and length, never the '
        'content', () {
      final request = EvmMessageRequest.personal(
        _bytes('a secret phrase'),
        coin: Coin.ethereum,
      );
      expect(
        request.toString(),
        'EvmMessageRequest.personal(ethereum, 15 bytes)',
      );
    });
  });

  group('EvmMessageRequest.typedData', () {
    test('accepts the typed-data vector document unchanged', () {
      final vector = MessageVector.load(typedDataVectorId);
      final request = typedDataRequest(vector);
      expect(request.type, EvmMessageType.typedData);
      expect(request.typedDataJson, vector.input['typed_data']);
      expect(request.message, isNull);
      expect(request.chainId, isNull);
    });

    test('checks well-formedness only: JSON that is not an EIP-712 document '
        'is accepted', () {
      for (final json in ['{}', '[]', '1', '"x"', 'null']) {
        expect(
          EvmMessageRequest.typedData(json, coin: Coin.ethereum).typedDataJson,
          json,
        );
      }
    });

    test('rejects malformed JSON, naming typedData and quoting nothing', () {
      for (final bad in ['', '   ', '{', '{"a":', "{'a':1}", '{"a":1,}', 'x']) {
        late Object error;
        try {
          EvmMessageRequest.typedData(bad, coin: Coin.ethereum);
          fail('accepted malformed JSON');
        } on InvalidInputError catch (e) {
          error = e;
          expect(e.inputName, 'typedData');
        }
        if (bad.length > 1) {
          expect(error.toString(), isNot(contains(bad)));
        }
      }
    });

    test('bounds the document at 1 MiB of UTF-8 before parsing it', () {
      String padded(int bytes) {
        // `{"a":"…"}` is 8 bytes of structure around the string.
        return '{"a":"${'x' * (bytes - 8)}"}';
      }

      expect(
        EvmMessageRequest.typedData(
          padded(maxEvmMessageBytes),
          coin: Coin.ethereum,
        ).typedDataJson,
        hasLength(maxEvmMessageBytes),
      );
      expect(
        () => EvmMessageRequest.typedData(
          padded(maxEvmMessageBytes + 1),
          coin: Coin.ethereum,
        ),
        _invalid('typedData'),
      );
      // Few code units, many bytes: 3 bytes each.
      final wide = '{"a":"${'€' * (maxEvmMessageBytes ~/ 3)}"}';
      expect(
        () => EvmMessageRequest.typedData(wide, coin: Coin.ethereum),
        _invalid('typedData'),
      );
    });

    test('rejects a coin outside the EVM family and a chain id below 1', () {
      expect(
        () => EvmMessageRequest.typedData('{}', coin: Coin.bitcoin),
        _invalid('coin'),
      );
      expect(
        () =>
            EvmMessageRequest.typedData('{}', coin: Coin.ethereum, chainId: 0),
        _invalid('chainId'),
      );
    });

    test('the rendering shows the length, never the document', () {
      final request = EvmMessageRequest.typedData(
        '{"name":"hidden"}',
        coin: Coin.ethereum,
        chainId: 5,
      );
      expect(
        request.toString(),
        'EvmMessageRequest.typedData(ethereum, 17 bytes, chainId: 5)',
      );
    });
  });
}
