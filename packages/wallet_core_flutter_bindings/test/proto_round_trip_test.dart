/// Round-trip of a generated protobuf signing input.
///
/// This is the *encode* half of the PRD §11.4 family boundary: chain-family
/// code has to be able to build upstream's `SigningInput` in Dart and get the
/// same bytes back, and T1.12 onward cannot be written until it does. Nothing
/// here signs anything or reaches native code — it only proves the generated
/// classes serialize and parse. The `privateKey` field is exercised because
/// PRD §11.4 turns on its existence; the value is thirty-two 0x01 bytes, an
/// obvious dummy, never a key from a test vector or any published source.
library;

import 'package:protobuf/protobuf.dart';
import 'package:test/test.dart';
import 'package:wallet_core_flutter_bindings/src/generated/proto/Bitcoin.pb.dart'
    as bitcoin;
import 'package:wallet_core_flutter_bindings/src/generated/proto/Ethereum.pb.dart';

/// An obvious non-key: thirty-two 0x01 bytes.
final List<int> dummyKey = List<int>.filled(32, 0x01);

void main() {
  group('Ethereum.SigningInput', () {
    test('exposes the private_key field as privateKey', () {
      final input = SigningInput();
      expect(input.hasPrivateKey(), isFalse);

      input.privateKey = dummyKey;

      expect(input.hasPrivateKey(), isTrue);
      expect(input.privateKey, dummyKey);
    });

    test('is keyed in key_fields.json by its qualifiedMessageName', () {
      // key_fields.json keys messages by fully-qualified protobuf name so a
      // caller can look one up from a live message with no reflection. That
      // only works if the runtime reports the same string.
      expect(
        SigningInput().info_.qualifiedMessageName,
        'TW.Ethereum.Proto.SigningInput',
      );
    });

    test('round-trips through serialization with field equality', () {
      final built = SigningInput(
        chainId: [0x01],
        nonce: [0x09],
        gasPrice: [0x04, 0xa8, 0x17, 0xc8, 0x00],
        gasLimit: [0x52, 0x08],
        toAddress: '0x3535353535353535353535353535353535353535',
        privateKey: dummyKey,
        transaction: Transaction(
          transfer: Transaction_Transfer(
            amount: [0x0d, 0xe0, 0xb6, 0xb3, 0xa7, 0x64, 0x00, 0x00],
            data: const <int>[],
          ),
        ),
      );

      final bytes = built.writeToBuffer();
      final parsed = SigningInput.fromBuffer(bytes);

      expect(parsed.chainId, built.chainId);
      expect(parsed.nonce, built.nonce);
      expect(parsed.gasPrice, built.gasPrice);
      expect(parsed.gasLimit, built.gasLimit);
      expect(parsed.toAddress, built.toAddress);
      expect(parsed.privateKey, dummyKey);
      expect(parsed.hasTransaction(), isTrue);
      expect(
        parsed.transaction.whichTransactionOneof(),
        Transaction_TransactionOneof.transfer,
      );
      expect(
        parsed.transaction.transfer.amount,
        built.transaction.transfer.amount,
      );

      // Serialization is deterministic for this message, so the strongest
      // statement available is byte equality of a re-encode.
      expect(parsed.writeToBuffer(), bytes);
      expect(parsed, built);
    });

    test('a repeated key field round-trips as a list (Bitcoin shape)', () {
      // Bitcoin declares `repeated bytes private_key`; PRD §10.2 relies on
      // that being representable, so check the generated list semantics on the
      // one family whose signer needs more than one key.
      final input = bitcoin.SigningInput();
      input.privateKey.add(dummyKey);
      input.privateKey.add(List<int>.filled(32, 0x02));

      final parsed = bitcoin.SigningInput.fromBuffer(input.writeToBuffer());

      expect(parsed.privateKey, hasLength(2));
      expect(parsed.privateKey.first, dummyKey);
      expect(parsed.privateKey, isA<PbList<List<int>>>());
    });
  });
}
