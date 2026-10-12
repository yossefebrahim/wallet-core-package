part of '../requests.dart';

/// A base58 string of the length of a Solana public key or blockhash.
///
/// A 32-byte value is 32 to 44 characters of Bitcoin-alphabet base58 (no `0`,
/// `O`, `I` or `l`). Syntax only: whether a recipient is a valid address, and
/// whether a blockhash decodes to exactly 32 bytes, is upstream's answer at
/// sign time, because a request never calls native code.
final RegExp _solanaBase58Syntax = RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$');

/// A transaction on Solana (`docs/architecture/signing.md` §3.3).
///
/// **Validated at construction.** [InvalidInputError] naming the input when
/// [to] is not 32 to 44 base58 characters, [lamports] is negative, or
/// [recentBlockhash] is not 32 to 44 base58 characters. Whether [to] is a
/// valid Solana address, and whether [recentBlockhash] is a 32-byte hash, is
/// upstream's answer, asked for at sign time: the recipient before any key is
/// derived, the blockhash by the signing call itself.
///
/// The one signer is the sender and therefore the fee payer. A transaction
/// with a separate fee payer, a durable nonce, a memo, extra signers, a
/// priority fee or a version-0 message is not expressible here: no vector
/// covers it, and this version does not guess.
///
/// The coin is always [Coin.solana] and the network always [Network.mainnet].
/// Immutable.
final class SolanaTransactionRequest implements TransactionRequest {
  SolanaTransactionRequest._({
    required this.to,
    required this.lamports,
    required this.recentBlockhash,
  }) {
    if (!_solanaBase58Syntax.hasMatch(to)) {
      throw const InvalidInputError(
        'to must be 32 to 44 base58 characters',
        inputName: 'to',
      );
    }
    if (lamports < 0) {
      throw const InvalidInputError(
        'lamports must not be negative',
        inputName: 'lamports',
      );
    }
    if (!_solanaBase58Syntax.hasMatch(recentBlockhash)) {
      throw const InvalidInputError(
        'recentBlockhash must be 32 to 44 base58 characters',
        inputName: 'recentBlockhash',
      );
    }
  }

  /// A native SOL transfer of [lamports] (1 SOL = 10^9 lamports) to [to],
  /// valid against [recentBlockhash], signed by the sender's key.
  ///
  /// [to] is a base58 address and [recentBlockhash] a base58 block hash, both
  /// as the network's RPC reports them. [lamports] is between 0 and 2^63 − 1:
  /// upstream's amount is a `uint64`, and a Dart `int` is the signed 64-bit half
  /// of it, which is over 9 billion SOL, far above Solana's total supply.
  factory SolanaTransactionRequest.transfer({
    required String to,
    required int lamports,
    required String recentBlockhash,
  }) => SolanaTransactionRequest._(
    to: to,
    lamports: lamports,
    recentBlockhash: recentBlockhash,
  );

  /// Always [Coin.solana].
  @override
  Coin get coin => Coin.solana;

  /// Always [Network.mainnet]: upstream models no Solana test network.
  @override
  Network get network => Network.mainnet;

  /// Always empty: a Solana transfer has one key slot, and the caller names
  /// the key in the set passed to the signer.
  @override
  Set<KeyLocator> get keyLocators => const <KeyLocator>{};

  /// The recipient's address, base58.
  final String to;

  /// The amount sent, in lamports.
  final int lamports;

  /// The recent block hash the transaction is valid against, base58.
  final String recentBlockhash;

  @override
  String toString() =>
      'SolanaTransactionRequest.transfer(to: $to, lamports: $lamports, '
      'recentBlockhash: $recentBlockhash)';
}
