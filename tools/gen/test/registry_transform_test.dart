import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Generated CoinType has all members and correct normalizeId', () {
    final typeContent = File(
      '../../packages/wallet_core_flutter_bindings/lib/src/generated/registry/coin_type.dart',
    ).readAsStringSync();

    expect(typeContent, contains('enum CoinType {'));
    expect(typeContent, contains('  bitcoin(0),'));
    expect(typeContent, contains('  ethereum(60),'));
    expect(typeContent, contains('  nebl(146),'));
    expect(typeContent, contains('  internetComputer(223),'));
    expect(typeContent, contains('  kin(2017),'));

    // Count assertion
    final registryData =
        jsonDecode(
              File(
                '../../third_party/wallet-core/registry.json',
              ).readAsStringSync(),
            )
            as List<dynamic>;

    // The number of commas (plus one for the last semi-colon) between enum members is count-1.
    // However, it's easier to check if the number of lines matching `  identifier(number)[,;]` is exactly the registry count.
    final memberRegex = RegExp(r'^  [a-zA-Z0-9]+\(\d+\)[,;]$', multiLine: true);
    final matchCount = memberRegex.allMatches(typeContent).length;
    expect(matchCount, equals(registryData.length));
  });

  test('Generated CoinInfo matches expected text for sample entries', () {
    final infoContent = File(
      '../../packages/wallet_core_flutter_bindings/lib/src/generated/registry/coin_info.dart',
    ).readAsStringSync();

    // Test base for chainId
    expect(
      infoContent,
      contains('''
  CoinType.base: CoinInfo(
    name: "Base",
    symbol: "ETH",
    decimals: 18,
    derivation: [
      Derivation(name: null, path: "m/44'/60'/0'/0/0", xpub: null, xprv: null),
    ],
    curve: "secp256k1",
    publicKeyType: "secp256k1Extended",
    blockchain: "Ethereum",
    explorer: Explorer(
      url: "https://basescan.org",
      txPath: "/tx/",
      accountPath: "/address/",
    ),
    chainId: "8453",
  ),'''),
    );

    // Test kin for deprecated
    expect(
      infoContent,
      contains('''
  CoinType.kin: CoinInfo(
    name: "Kin",
    symbol: "KIN",
    decimals: 5,
    derivation: [
      Derivation(name: null, path: "m/44'/2017'/0'", xpub: null, xprv: null),
    ],
    curve: "ed25519",
    publicKeyType: "ed25519",
    blockchain: "Stellar",
    explorer: Explorer(
      url: "https://www.kin.org",
      txPath: "/blockchainInfoPage/?&dataType=public&header=Transaction&id=",
      accountPath: "/blockchainAccount/?&dataType=public&header=accountID&id=",
    ),
    deprecated: true,
  ),'''),
    );

    // Test nebl for normalisation
    expect(
      infoContent,
      contains('''
  CoinType.nebl: CoinInfo(
    name: "Nebl",
    symbol: "NEBL",
    decimals: 8,
    derivation: [
      Derivation(
        name: null,
        path: "m/44'/146'/0'/0/0",
        xpub: "xpub",
        xprv: "xprv",
      ),
    ],
    curve: "secp256k1",
    publicKeyType: "secp256k1",
    blockchain: "Verge",
    explorer: Explorer(
      url: "https://explorer.nebl.io",
      txPath: "/tx/",
      accountPath: "/address/",
    ),
  ),'''),
    );

    // Test internetComputer for normalisation
    expect(
      infoContent,
      contains('''
  CoinType.internetComputer: CoinInfo(
    name: "Internet Computer",
    symbol: "ICP",
    decimals: 8,
    derivation: [
      Derivation(
        name: null,
        path: "m/44'/223'/0'/0/0",
        xpub: "xpub",
        xprv: null,
      ),
    ],
    curve: "secp256k1",
    publicKeyType: "secp256k1Extended",
    blockchain: "InternetComputer",
    explorer: Explorer(
      url: "https://dashboard.internetcomputer.org",
      txPath: "/transaction/",
      accountPath: "/account/",
    ),
  ),'''),
    );

    // Test bitcoin: the multi-derivation case, and the only sample carrying hrp.
    expect(
      infoContent,
      contains('''
  CoinType.bitcoin: CoinInfo(
    name: "Bitcoin",
    symbol: "BTC",
    decimals: 8,
    derivation: [
      Derivation(
        name: "segwit",
        path: "m/84'/0'/0'/0/0",
        xpub: "zpub",
        xprv: "zprv",
      ),
      Derivation(
        name: "legacy",
        path: "m/44'/0'/0'/0/0",
        xpub: "xpub",
        xprv: "xprv",
      ),
      Derivation(
        name: "testnet",
        path: "m/84'/1'/0'/0/0",
        xpub: "zpub",
        xprv: "zprv",
      ),
      Derivation(
        name: "taproot",
        path: "m/86'/0'/0'/0/0",
        xpub: "zpub",
        xprv: "zprv",
      ),
    ],
    curve: "secp256k1",
    publicKeyType: "secp256k1",
    blockchain: "Bitcoin",
    explorer: Explorer(
      url: "https://mempool.space",
      txPath: "/tx/",
      accountPath: "/address/",
    ),
    hrp: "bc",
  ),'''),
    );

    // Test ethereum
    expect(
      infoContent,
      contains('''
  CoinType.ethereum: CoinInfo(
    name: "Ethereum",
    symbol: "ETH",
    decimals: 18,
    derivation: [
      Derivation(name: null, path: "m/44'/60'/0'/0/0", xpub: null, xprv: null),
    ],
    curve: "secp256k1",
    publicKeyType: "secp256k1Extended",
    blockchain: "Ethereum",
    explorer: Explorer(
      url: "https://etherscan.io",
      txPath: "/tx/",
      accountPath: "/address/",
    ),
    chainId: "1",
  ),'''),
    );
  });
}
