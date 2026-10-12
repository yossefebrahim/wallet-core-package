/// The Bitcoin test-vector values the M1 UTXO device test asserts, as
/// constants.
///
/// A device test cannot read the repository's YAML at run time, so the values
/// are transcribed here from `test_vectors/bitcoin/vectors.yaml`. The host test
/// `test/m1_utxo_vectors_consistency_test.dart` loads that file and asserts
/// every constant below equals its entry, so this copy cannot drift.
///
/// Provenance of each group is the vector's own `source` block, at upstream
/// commit d692ac27749d0c615e17c751b70ab4f0aa75c59b:
/// - `bitcoin-address-n/a-1`, `-2`: `tests/interface/TWHDWalletTests.cpp`,
///   `TEST(TWHDWallet, Derive_XpubPub_vs_PrivPub)`.
/// - `bitcoin-plan-p2wpkh-1`, `bitcoin-sign-p2wpkh-1`:
///   `tests/chains/Bitcoin/TWBitcoinSigningTests.cpp`,
///   `TEST(BitcoinSigning, SignPlanTransactionNoChange)`.
/// - `bitcoin-plan-multi_input-1`, `bitcoin-sign-multi_input-1`: the same
///   file, `TEST(BitcoinSigning, SignP2WPKH_MaxAmount)`.
///
/// **The `*Key` values are upstream's published test keys**, here only so that
/// the device test can make a native key handle from each for the
/// signing-core level; no request holds one.
library;

/// One input of a UTXO vector: `txid`, `index`, `amount`, `script_pub_key`,
/// `private_key`, exactly as the vector writes them.
typedef VectorUtxo = ({
  String txid,
  String index,
  String amount,
  String scriptPubKey,
  String privateKey,
});

/// `bitcoin-address-n/a-1` and `-2`, `input` and `expected`.
const String addressMnemonic =
    'ripple scissors kick mammal hire column oak again sun offer wealth '
    'tomorrow wagon turn fatal';
const String addressPath0 = "m/84'/0'/0'/0/0";
const String addressPath1 = "m/84'/0'/0'/0/2";
const String addressExpected0 = 'bc1qpsp72plnsqe6e2dvtsetxtww2cz36ztmfxghpd';
const String addressExpected1 = 'bc1q7zddsunzaftf4zlsg9exhzlkvc5374a6v32jf6';
const String publicKeyExpected0 =
    '02df9ef2a7a5552765178b181e1e1afdefc7849985c7dfe9647706dd4fa40df6ac';
const String publicKeyExpected1 =
    '031e1f64d2f6768dccb6814545b2e2d58e26ad5f91b7cbaffe881ed572c65060db';

/// `bitcoin-plan-p2wpkh-1` and `bitcoin-sign-p2wpkh-1`, `input`.
const String p2wpkhByteFee = '33';
const String p2wpkhAmount = '28035';
const bool p2wpkhUseMaxAmount = false;
const String p2wpkhToAddress = 'bc1q2dsdlq3343vk29runkgv4yc292hmq53jedfjmp';
const String p2wpkhChangeAddress = 'bc1qvrt7ukvhvmdny0a3j9k8l8jasx92lrqm30t2u2';
const List<VectorUtxo> p2wpkhUtxos = <VectorUtxo>[
  (
    txid: 'b33082a5fad105c1d9712e8d503971fe4d84713065bd323fd1019636ed940e8d',
    index: '1',
    amount: '30269',
    scriptPubKey: '001460d7ee599766db323fb1916c7f9e5d818aaf8c1b',
    privateKey:
        '9ea2172511ed73ae0096be8e593c3b75631700edaf729f1abbae607314a20e35',
  ),
  (
    txid: '1f62c18bfc5f8293a2b7b061587c427bf830fb224289f9a806e6ad48de6a4c7d',
    index: '1',
    amount: '4863',
    scriptPubKey: '001460d7ee599766db323fb1916c7f9e5d818aaf8c1b',
    privateKey:
        '9ea2172511ed73ae0096be8e593c3b75631700edaf729f1abbae607314a20e35',
  ),
  (
    txid: '71c3343dfca5f1914e1bfc04153517d73650cb9c931e8511d24d1f5290120f6f',
    index: '0',
    amount: '300',
    scriptPubKey: '001460d7ee599766db323fb1916c7f9e5d818aaf8c1b',
    privateKey:
        '9ea2172511ed73ae0096be8e593c3b75631700edaf729f1abbae607314a20e35',
  ),
];

/// `bitcoin-plan-p2wpkh-1`, `expected`.
const List<String> p2wpkhPlanSelectedAmounts = <String>['4863', '30269'];
const String p2wpkhPlanAmount = '28035';
const String p2wpkhPlanFee = '7097';
const String p2wpkhPlanAvailableAmount = '35132';
const String p2wpkhPlanChange = '0';

/// `bitcoin-sign-p2wpkh-1`, `expected`.
const String p2wpkhSignExpectedEncoded =
    '010000000001027d4c6ade48ade606a8f9894222fb30f87b427c5861b0b7a293825ffc8bc1621f01'
    '00000000ffffffff8d0e94ed369601d13f32bd653071844dfe7139508d2e71d9c105d1faa58230b3'
    '0100000000ffffffff01836d0000000000001600145360df8231ac5965147c9d90ca930a2aafb052'
    '3202483045022100f95f9ac5d39f4b47dcd8c86daaaeac86374258d9960f922333ba0d5fdaa15b7e'
    '0220761794672dc9fbd71398d608f72f5d21a0f6c1306c6b700ad0d82f747c221062012103a11506'
    '993946e20ea82686b157bf08f944759f43d91af8d84650ee73a482431c02483045022100eb6ba0dc'
    'c64af61b2186b7efdab1ff03784d585ee03437f9a53875e93429db080220015a268d308436d3564b'
    '83ceaed90bc7272ca164016298ea855d1936568002a7012103a11506993946e20ea82686b157bf08'
    'f944759f43d91af8d84650ee73a482431c00000000';
const String p2wpkhSignExpectedTxid =
    '5d6bf53576a54be4d92cd8abf58d28ecc9ea7956eaf970d24d6bfcb9fcfe9855';

/// `bitcoin-plan-multi_input-1` and `bitcoin-sign-multi_input-1`, `input`.
///
/// The ids are written the way upstream's test passed them to `OutPoint()`:
/// in the order of the serialized transaction, which is the reverse of the
/// display order the SDK's `OutPoint.transactionId` takes.
const String multiByteFee = '1';
const String multiAmount = '1224999773';
const bool multiUseMaxAmount = true;
const String multiToAddress = '1Bp9U1ogV3A14FMvKbRJms7ctyso4Z4Tcx';
const String multiChangeAddress = '1FQc5LdgGHMHEN9nwkjmz6tWkxhPpxBvBU';
const List<VectorUtxo> multiUtxos = <VectorUtxo>[
  (
    txid: 'fff7f7881a8099afa6940d42d1e7f6362bec38171ea3edf433541db4e4ad969f',
    index: '0',
    amount: '625000000',
    scriptPubKey: '2103c9f4836b9a4f77fc0d81f7bcb01b7f1b35916864b9476c241ce9fc198bd25432ac',
    privateKey:
        'bbc27228ddcb9209d7fd6f36b02f7dfa6252af40bb2f1cbc7a557da8027ff866',
  ),
  (
    txid: 'ef51e1b804cc89d182d279655c3aa89e815b1b309fe287d9b2b55d57b90ec68a',
    index: '1',
    amount: '600000000',
    scriptPubKey: '00141d0f172a0ecb48aee1be1f2687d2963ae33f71a1',
    privateKey:
        '619c335025c7f4012e556c2a58b2506e30b8511b53ade95ea316fd8c3286feb9',
  ),
];

/// `bitcoin-plan-multi_input-1`, `expected`.
const List<String> multiPlanSelectedAmounts = <String>[
  '625000000',
  '600000000',
];
const String multiPlanAmount = '1224999773';
const String multiPlanFee = '227';
const String multiPlanAvailableAmount = '1225000000';
const String multiPlanChange = '0';

/// `bitcoin-sign-multi_input-1`, `expected.encoded`.
const String multiSignExpectedEncoded =
    '01000000000102fff7f7881a8099afa6940d42d1e7f6362bec38171ea3edf433541db4e4ad969f00'
    '00000049483045022100a8b3c1619e985923994e80efdc0be0eac12f2419e11ce5e4286a0a5ac27c'
    '775d02205d6feee85ffe19ae0835cba1562beb3beb172107cd02ac4caf24a8be3749811f01ffffff'
    'ffef51e1b804cc89d182d279655c3aa89e815b1b309fe287d9b2b55d57b90ec68a0100000000ffff'
    'ffff015d030449000000001976a914769bdff96a02f9135a1d19b749db6a78fe07dc9088ac000248'
    '3045022100db1199de92f6fb638a0ba706d13ec686bb01138a254dec2c397616cd74bad30e02200'
    'd7286d6d2d4e00d145955bf3d3b848b03c0d1eef8899e4645687a3035d7def40121025476c2e8318'
    '8368da1ff3e292e7acafcdb3566bb0ad253f62fc70f07aeee635700000000';
