// Address.looksWellFormed and the Account descriptor. Pure Dart.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/src/address/address.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';

import '../support/fixtures.dart';

void main() {
  group('looksWellFormed', () {
    test('accepts the Ethereum vector address and rejects the invalid one', () {
      final inventory = loadInventory();
      final valid =
          vectorById(inventory, 'ethereum-address-n/a-1').expected['address']
              as String;
      final invalid =
          vectorById(inventory, 'ethereum-invalid_input-n/a-2').input['address']
              as String;
      expect(Address.looksWellFormed(valid, coin: Coin.ethereum), isTrue);
      expect(
        Address.looksWellFormed(valid.toLowerCase(), coin: Coin.ethereum),
        isTrue,
      );
      expect(Address.looksWellFormed(invalid, coin: Coin.ethereum), isFalse);
    });

    test('rejects EVM strings of the wrong shape', () {
      for (final value in [
        '',
        '996891c410FB76C19DBA72C6f6cEFF2d9DD069b1',
        '0x996891c410FB76C19DBA72C6f6cEFF2d9DD069b',
        '0x996891c410FB76C19DBA72C6f6cEFF2d9DD069b1a',
        ' 0x996891c410FB76C19DBA72C6f6cEFF2d9DD069b1',
        '0x996891c410FB76C19DBA72C6f6cEFF2d9DD069b1\n',
      ]) {
        expect(
          Address.looksWellFormed(value, coin: Coin.byId('base')),
          isFalse,
          reason: value,
        );
      }
    });

    test('bitcoin: bech32 with the network prefix, or base58 on mainnet', () {
      const segwit = 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq';
      const legacy = '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa';
      const testnet = 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx';
      expect(Address.looksWellFormed(segwit, coin: Coin.bitcoin), isTrue);
      expect(Address.looksWellFormed(legacy, coin: Coin.bitcoin), isTrue);
      expect(Address.looksWellFormed(testnet, coin: Coin.bitcoin), isFalse);
      expect(
        Address.looksWellFormed(
          testnet,
          coin: Coin.bitcoin,
          network: Network.testnet,
        ),
        isTrue,
      );
      expect(
        Address.looksWellFormed(
          segwit,
          coin: Coin.bitcoin,
          network: Network.testnet,
        ),
        isFalse,
      );
      expect(
        Address.looksWellFormed(
          'bc1QAR0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq',
          coin: Coin.bitcoin,
        ),
        isFalse,
        reason: 'mixed-case bech32',
      );
      expect(
        Address.looksWellFormed(
          '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfN0',
          coin: Coin.bitcoin,
        ),
        isFalse,
        reason: '0 is not base58',
      );
    });

    test('a network the coin lacks is an error, not false', () {
      expect(
        () => Address.looksWellFormed(
          '0x996891c410FB76C19DBA72C6f6cEFF2d9DD069b1',
          coin: Coin.ethereum,
          network: Network.testnet,
        ),
        throwsA(isA<UnsupportedOperationError>()),
      );
    });

    test('chains without specific rules get length and characters only', () {
      const cosmos = 'cosmos1hsk6jryyqjfhp5dhc55tc9jtckygx0eph6dd02';
      expect(
        Address.looksWellFormed(cosmos, coin: Coin.byId('cosmos')),
        isTrue,
      );
      expect(
        Address.looksWellFormed('a' * 513, coin: Coin.byId('cosmos')),
        isFalse,
      );
      expect(
        Address.looksWellFormed('abc\u0000', coin: Coin.byId('cosmos')),
        isFalse,
      );
    });
  });

  group('Address and Account values', () {
    final address = validatedAddress(
      '0x996891c410FB76C19DBA72C6f6cEFF2d9DD069b1',
      Coin.ethereum,
      Network.mainnet,
    );

    test('an address is equal by value, coin and network', () {
      expect(
        address,
        validatedAddress(address.value, Coin.byId('ethereum'), Network.mainnet),
      );
      expect(
        address,
        isNot(
          validatedAddress(address.value, Coin.byId('base'), Network.mainnet),
        ),
      );
      expect(address.toString(), address.value);
    });

    test('an account is equal field by field, the key byte by byte', () {
      Account account(List<int> key) => Account(
        coin: Coin.ethereum,
        network: Network.mainnet,
        addressStyle: AddressStyle.standard,
        derivationPath: "m/44'/60'/0'/0/1",
        address: address,
        publicKey: Uint8List.fromList(key),
      );
      expect(account([4, 1, 2]), account([4, 1, 2]));
      expect(account([4, 1, 2]).hashCode, account([4, 1, 2]).hashCode);
      expect(account([4, 1, 2]), isNot(account([4, 1, 3])));
      expect(account([4, 1, 2]).toString(), contains("m/44'/60'/0'/0/1"));
    });
  });
}
