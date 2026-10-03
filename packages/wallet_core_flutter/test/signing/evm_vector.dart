/// The EVM request a sign vector's `input` map describes.
library;

import 'package:wallet_core_flutter/src/requests/requests.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart' show Coin;

/// The EIP-1559 transfer of a `sign`/`eip1559` vector, built from its `input`
/// map — every value read from the inventory, none copied into the test.
EvmTransactionRequest vectorRequest(Map<dynamic, dynamic> input) =>
    EvmTransactionRequest.transfer(
      coin: Coin.ethereum,
      chainId: int.parse(input['chain_id'] as String),
      nonce: BigInt.parse(input['nonce'] as String),
      to: input['to_address'] as String,
      valueWei: BigInt.parse(input['value'] as String),
      maxFeePerGas: BigInt.parse(input['max_fee_per_gas'] as String),
      maxPriorityFeePerGas: BigInt.parse(
        input['max_priority_fee_per_gas'] as String,
      ),
      gasLimit: BigInt.parse(input['gas_limit'] as String),
    );
