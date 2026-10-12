/// The Solana test-vector values the device tests assert, as constants.
///
/// A device test cannot read the repository's YAML at run time, so the values
/// are transcribed here from `test_vectors/solana/vectors.yaml`. The host test
/// `test/m1_solana_vectors_consistency_test.dart` loads that file and asserts
/// every constant below equals its entry, so this copy cannot drift.
///
/// Provenance of each group is the vector's own `source` block, upstream
/// commit d692ac27749d0c615e17c751b70ab4f0aa75c59b:
/// - `solana-address-n/a-1`: `tests/chains/Solana/TWSolanaAddressTests.cpp`,
///   `TEST(TWSolanaAddress, HDWallet)`; the path is the registry's default
///   derivation for Solana.
/// - `solana-sign-legacy-1`: `tests/chains/Solana/TWAnySignerTests.cpp`,
///   `TEST(TWAnySignerSolana, SignTransfer)`. The key is upstream's published
///   test key in upstream's own form, base58.
library;

/// `solana-address-n/a-1`, `input` and `expected.address`.
const String addressMnemonic =
    'shoot island position soft burden budget tooth cruel issue economy '
    'destroy above';
const String addressPath = "m/44'/501'/0'";
const String addressExpected = '2bUBiBNZyD29gP1oV6de7nxowMLoDBtopMMTGgMvjG5m';

/// `solana-sign-legacy-1`, `input`.
const String signPrivateKeyBase58 =
    'A7psj2GW7ZMdY4E5hJq14KMeYg7HFjULSsWSrTXZLvYr';
const String signToAddress = 'EN2sCsJ1WDV8UFqsiTXHcUPUxQ4juE71eCknHYYMifkd';
const String signLamports = '42';
const String signRecentBlockhash = '11111111111111111111111111111111';

/// `solana-sign-legacy-1`, `expected`: both base58.
const String signExpectedEncoded =
    '3p2kzZ1DvquqC6LApPuxpTg5CCDVPqJFokGSnGhnBHrta4uq7S2EyehV1XNUVXp51D69GxGzQZU'
    'jikfDzbWBG2aFtG3gHT1QfLzyFKHM4HQtMQMNXqay1NAeiiYZjNhx9UvMX4uAQZ4Q6rx6m2AYfQ'
    '7aoMUrejq298q1wBFdtS9XVB5QTiStnzC7zs97FUEK2T4XapjF1519EyFBViTfHpGpnf5bfizDz'
    'sW9kYUtRDW1UC2LgHr7npgq5W9TBmHf9hSmRgM9XXucjXLqubNWE7HUMhbKjuBqkirRM';
const String signExpectedUnsignedTx =
    '87PYsiS4MUU1UqXrsDoCBmD5FcKsXhwEBD8hc4zbq78yePu7bLENmbnmjmVbsj4VvaxnZhy4bERn'
    'dPFzjSRH5WpwKwMLSCKvn9eSDmPESNcdkqne2UdMfWiFoq8ZeQBnF9h98dP8GM9kfzWPjvLmhjwu'
    'wA1E2k5WCtfii7LKQ34v6AtmFQGZqgdKiNqygP7ZKusHWGT8ZkTZ';

/// An address that is base58 and the length of a public key, and is not a
/// Solana address (33 zero bytes). Not a vector value: it only has to pass the
/// request's syntax check and fail upstream's address validation.
const String notAnAddress = '111111111111111111111111111111111';
