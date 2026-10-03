part of '../requests.dart';

/// The largest value of upstream's `uint256` fields: 2^256 − 1.
final BigInt _maxUint256 = (BigInt.one << 256) - BigInt.one;

/// `0x` and forty hexadecimal digits, in any case. Syntax only: the EIP-55
/// checksum of a mixed-case address is upstream's to judge, at sign time.
final RegExp _evmAddressSyntax = RegExp(r'^0x[0-9a-fA-F]{40}$');

/// A transaction on an EVM chain (`docs/architecture/signing.md` §3.1).
///
/// **Validated at construction.** Each constructor throws [InvalidInputError]
/// naming the offending input when an integer is negative or wider than
/// upstream's 256 bits, [chainId] is below 1, [to] is not `0x` and forty hex
/// digits, or [coin] is not in [ChainFamily.evm]. Whether [to] is a valid
/// address *for [coin]* — its EIP-55 checksum included — is upstream's
/// answer, asked for at sign time, because a request never calls native code.
///
/// The constructors are therefore not `const`; the sketch's `const` could not
/// validate anything.
///
/// Immutable: [data] is copied on the way in and exposed as a read-only view.
final class EvmTransactionRequest implements TransactionRequest {
  EvmTransactionRequest._({
    required this.coin,
    required this.chainId,
    required this.nonce,
    required this.to,
    required this.valueWei,
    required this.gasLimit,
    this.maxFeePerGas,
    this.maxPriorityFeePerGas,
    this.gasPrice,
    Uint8List? data,
  }) : _data = data == null ? null : Uint8List.fromList(data) {
    if (coin.family != ChainFamily.evm) {
      throw InvalidInputError(
        '${coin.id} is not an EVM coin; an EVM request needs one',
        inputName: 'coin',
      );
    }
    if (chainId < 1) {
      throw const InvalidInputError(
        'chainId must be at least 1',
        inputName: 'chainId',
      );
    }
    if (!_evmAddressSyntax.hasMatch(to)) {
      throw const InvalidInputError(
        'to must be "0x" followed by 40 hexadecimal digits',
        inputName: 'to',
      );
    }
    _checkUint256(nonce, 'nonce');
    _checkUint256(valueWei, 'valueWei');
    _checkUint256(gasLimit, 'gasLimit');
    if (maxFeePerGas case final fee?) _checkUint256(fee, 'maxFeePerGas');
    if (maxPriorityFeePerGas case final fee?) {
      _checkUint256(fee, 'maxPriorityFeePerGas');
    }
    if (gasPrice case final price?) _checkUint256(price, 'gasPrice');
  }

  /// An EIP-1559 native-value transfer.
  ///
  /// [chainId] is explicit and is not read from [coin]: an EVM network this
  /// SDK does not carry in its coin set — a testnet, for instance — is still
  /// signable by supplying its chain id here.
  factory EvmTransactionRequest.transfer({
    required Coin coin,
    required int chainId,
    required BigInt nonce,
    required String to,
    required BigInt valueWei,
    required BigInt maxFeePerGas,
    required BigInt maxPriorityFeePerGas,
    required BigInt gasLimit,
  }) => EvmTransactionRequest._(
    coin: coin,
    chainId: chainId,
    nonce: nonce,
    to: to,
    valueWei: valueWei,
    gasLimit: gasLimit,
    maxFeePerGas: maxFeePerGas,
    maxPriorityFeePerGas: maxPriorityFeePerGas,
  );

  /// A legacy (pre-EIP-1559) native-value transfer, priced by [gasPrice].
  factory EvmTransactionRequest.legacyTransfer({
    required Coin coin,
    required int chainId,
    required BigInt nonce,
    required String to,
    required BigInt valueWei,
    required BigInt gasPrice,
    required BigInt gasLimit,
  }) => EvmTransactionRequest._(
    coin: coin,
    chainId: chainId,
    nonce: nonce,
    to: to,
    valueWei: valueWei,
    gasLimit: gasLimit,
    gasPrice: gasPrice,
  );

  /// An EIP-1559 call of the contract at [to] with caller-supplied calldata
  /// [data], sending [valueWei] (zero when omitted). [data] is copied.
  factory EvmTransactionRequest.contractCall({
    required Coin coin,
    required int chainId,
    required BigInt nonce,
    required String to,
    required Uint8List data,
    BigInt? valueWei,
    required BigInt maxFeePerGas,
    required BigInt maxPriorityFeePerGas,
    required BigInt gasLimit,
  }) => EvmTransactionRequest._(
    coin: coin,
    chainId: chainId,
    nonce: nonce,
    to: to,
    valueWei: valueWei ?? BigInt.zero,
    gasLimit: gasLimit,
    maxFeePerGas: maxFeePerGas,
    maxPriorityFeePerGas: maxPriorityFeePerGas,
    data: data,
  );

  @override
  final Coin coin;

  /// Always [Network.mainnet]: EVM networks are told apart by [chainId] and
  /// by coin, not by this axis (DECISION-11 §4.4).
  @override
  Network get network => Network.mainnet;

  /// Always empty: an EVM transaction has one key slot, and the caller names
  /// the key in the set passed to the signer.
  @override
  Set<KeyLocator> get keyLocators => const <KeyLocator>{};

  /// The chain id the signature commits to (EIP-155).
  final int chainId;

  /// The sender's transaction count.
  final BigInt nonce;

  /// The recipient, or the contract called.
  final String to;

  /// The native value sent, in wei.
  final BigInt valueWei;

  /// The gas limit.
  final BigInt gasLimit;

  /// The EIP-1559 fee cap per gas; `null` for a legacy transaction.
  final BigInt? maxFeePerGas;

  /// The EIP-1559 priority fee (tip) per gas; `null` for a legacy
  /// transaction.
  final BigInt? maxPriorityFeePerGas;

  /// The legacy gas price; `null` for an EIP-1559 transaction.
  final BigInt? gasPrice;

  final Uint8List? _data;

  /// The calldata of a contract call, as a read-only view; `null` for a
  /// transfer.
  Uint8List? get data => _data?.asUnmodifiableView();

  /// Whether this is a legacy (pre-EIP-1559) transaction.
  bool get isLegacy => gasPrice != null;

  /// Every field but the calldata, which is shown by length. Nothing in a
  /// request is a secret; the calldata is left out only to keep a log line a
  /// line.
  @override
  String toString() {
    final kind = _data != null
        ? 'contractCall'
        : isLegacy
        ? 'legacyTransfer'
        : 'transfer';
    final fees = isLegacy
        ? 'gasPrice: $gasPrice'
        : 'maxFeePerGas: $maxFeePerGas, '
              'maxPriorityFeePerGas: $maxPriorityFeePerGas';
    final data = _data == null ? '' : ', data: ${_data.length} bytes';
    return 'EvmTransactionRequest.$kind(${coin.id}, chainId: $chainId, '
        'nonce: $nonce, to: $to, valueWei: $valueWei, gasLimit: $gasLimit, '
        '$fees$data)';
  }
}

void _checkUint256(BigInt value, String inputName) {
  if (value.isNegative) {
    throw InvalidInputError(
      '$inputName must not be negative',
      inputName: inputName,
    );
  }
  if (value > _maxUint256) {
    throw InvalidInputError(
      '$inputName does not fit in 256 bits',
      inputName: inputName,
    );
  }
}
