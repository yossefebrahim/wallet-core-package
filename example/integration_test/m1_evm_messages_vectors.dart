/// The EVM message-signing vector values the device test asserts, as
/// constants.
///
/// A device test cannot read the repository's YAML at run time, so the values
/// are transcribed here from `test_vectors/ethereum/vectors.yaml`. The host
/// test `test/m1_evm_messages_vectors_consistency_test.dart` loads that file
/// and asserts every constant below equals its entry, so this copy cannot
/// drift.
///
/// Provenance of each group is the vector's own `source` block, both at
/// upstream commit d692ac27749d0c615e17c751b70ab4f0aa75c59b, file
/// `tests/chains/Ethereum/EthereumMessageSignerTests.cpp`:
/// - `ethereum-sign_message-personal-1`: `TEST(TWEthereumMessageSigner,
///   SignAndVerifyLegacy)`, the C `TWEthereumMessageSignerSignMessage`; also
///   asserted through the protobuf entry point by
///   `rust/tw_tests/tests/chains/ethereum/ethereum_message_sign.rs`.
/// - `ethereum-sign_message-eip712-1`: `TEST(TWEthereumEip712,
///   SignMessageAndVerifyLegacy)`, the C `TWEthereumMessageSignerSignTypedMessage`.
///
/// The key is upstream's published test key, the same in both.
library;

/// The upstream test key of both vectors, `input.private_key`.
const String messagePrivateKey =
    '03a9ca895dca1623c7dfd69693f7b4111f5d819d2e145536e0b03c136025a25d';

/// `ethereum-sign_message-personal-1`, `input.message` (UTF-8 text).
const String personalMessage = 'Foo';

/// `ethereum-sign_message-personal-1`, `expected.signature`: `r ‖ s ‖ v`,
/// lowercase hexadecimal, `v` = `1b`.
const String personalExpectedSignature =
    '21a779d499957e7fd39392d49a079679009e60e492d9654a148829be43d2490736ec72bc'
    '4a5644047d979c3cf4ebe2c1c514044cf436b063cb89fc6676be71101b';

/// `ethereum-sign_message-eip712-1`, `input.typed_data`, as the YAML block
/// scalar yields it (a trailing newline included).
const String typedDataDocument = r'''
{
    "types": {
        "EIP712Domain": [
            {"name": "name", "type": "string"},
            {"name": "version", "type": "string"},
            {"name": "chainId", "type": "uint256"},
            {"name": "verifyingContract", "type": "address"}
        ],
        "Person": [
            {"name": "name", "type": "string"},
            {"name": "wallet", "type": "address"}
        ]
    },
    "primaryType": "Person",
    "domain": {
        "name": "Ether Person",
        "version": "1",
        "chainId": 0,
        "verifyingContract": "0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC"
    },
    "message": {
        "name": "Cow",
        "wallet": "CD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826"
    }
}
''';

/// `ethereum-sign_message-eip712-1`, `expected.signature`, `v` = `1c`.
const String typedDataExpectedSignature =
    '446434e4c34d6b7456e5f07a1b994b88bf85c057234c68d1e10c936b1c85706c4e19147c'
    '0ac3a983bc2d56ebfd7146f8b62bcea6114900fe8e7d7351f44bf3761c';

/// `ethereum-address-n/a-1`, `input` — the HD-derivable key the session path
/// signs with (its signature is asserted against the same session's core, not
/// against a vector: no vector exists for it).
const String addressMnemonic =
    'broom ramp luggage this language sketch door allow elbow wife moon '
    'impulse';
const String addressPath = "m/44'/60'/0'/0/1";
