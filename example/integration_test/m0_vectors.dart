/// The test-vector values the device tests assert, as constants.
///
/// A device test cannot read the repository's YAML at run time, so the values
/// are transcribed here from `test_vectors/ethereum/vectors.yaml`. The host
/// test `test/m0_vectors_consistency_test.dart` loads that file and asserts
/// every constant below equals its entry, so this copy cannot drift.
///
/// Provenance of each group is the vector's own `source` block:
/// - `ethereum-sign-eip1559-1`: upstream `tests/chains/Ethereum/
///   TWAnySignerTests.cpp`, `SignERC1559Transfer_1442`, at commit
///   d692ac27749d0c615e17c751b70ab4f0aa75c59b. The key is upstream's
///   published test key (Ropsten, chain id 3).
/// - `ethereum-invalid_input-n/a-1` (BIP-39), `-2` (EIP-55), `-3` (BIP-44):
///   standards, no upstream file.
/// - `ethereum-address-n/a-1`: upstream
///   `swift/Tests/Blockchains/EthereumTests.swift` at the same commit.
library;

/// `ethereum-sign-eip1559-1`, `input`.
const String signChainId = '3';
const String signNonce = '6';
const String signMaxPriorityFeePerGas = '2000000000';
const String signMaxFeePerGas = '3000000000';
const String signGasLimit = '21100';
const String signToAddress = '0xB9F5771C27664bF2282D98E09D7F50cEc7cB01a7';
const String signValue = '543210987654321';
const String signPrivateKey =
    '4f96ed80e9a7555a6f74b3d658afdd9c756b0a40d4ca30c42c2039eb449bb904';

/// `ethereum-sign-eip1559-1`, `expected`.
const String signExpectedEncoded =
    '02f8710306847735940084b2d05e0082526c94b9f5771c27664bf2282d98e09d7f50cec7cb01a7'
    '8701ee0c29f50cb180c080a092c336138f7d0231fe9422bb30ee9ef10bf222761fe9e04442e3a1'
    '1e88880c64a06487026011dae03dc281bc21c7d7ede5c2226d197befb813a4ecad686b559e58';
const String signExpectedV = '00';
const String signExpectedR =
    '92c336138f7d0231fe9422bb30ee9ef10bf222761fe9e04442e3a11e88880c64';
const String signExpectedS =
    '6487026011dae03dc281bc21c7d7ede5c2226d197befb813a4ecad686b559e58';

/// `ethereum-invalid_input-n/a-1`, `input.mnemonic`.
const String invalidMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon';

/// `ethereum-invalid_input-n/a-2`, `input.address`.
const String invalidAddress = '0xZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ';

/// `ethereum-invalid_input-n/a-3`, `input.derivation_path`.
const String invalidDerivationPath = 'm/44/60/invalid';

/// `ethereum-address-n/a-1`, `input` and `expected.address`.
const String addressMnemonic =
    'broom ramp luggage this language sketch door allow elbow wife moon '
    'impulse';
const String addressPath = "m/44'/60'/0'/0/1";
const String addressExpected = '0x996891c410FB76C19DBA72C6f6cEFF2d9DD069b1';

/// An artifact-set id that is not the shipped library's. Not a vector value:
/// it only has to differ from the manifest's `identity.artifact_set_id`.
const String wrongArtifactSetId = 'as_wrong';

/// `compat_manifest.json` `identity.upstream_commit`, the same commit every
/// upstream-sourced vector above cites.
const String upstreamCommit = 'd692ac27749d0c615e17c751b70ab4f0aa75c59b';
