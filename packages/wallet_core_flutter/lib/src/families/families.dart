/// Which [TransactionFamily] handles a request. **Internal**: never exported.
library;

import '../requests/requests.dart';
import '../signing/sign_result.dart';
import 'evm/evm_family.dart';
import 'evm/message_family.dart';
import 'family.dart';
import 'solana/solana_family.dart';

/// The family that encodes [request] and parses its output.
///
/// Exhaustive over the sealed [TransactionRequest]: a new request type does
/// not compile until it is given a family here.
TransactionFamily<TransactionRequest, SignResult> familyFor(
  TransactionRequest request,
) => switch (request) {
  EvmTransactionRequest() => evmFamily,
  SolanaTransactionRequest() => solanaFamily,
};

/// The family that encodes the message [request] and parses its output.
///
/// A separate function beside [familyFor], not another arm of it: messages
/// have their own sealed request hierarchy and their own family contract
/// ([MessageFamily]), and `familyFor`'s return type is the transaction one.
/// Exhaustive over the sealed [MessageRequest], so a new request type does not
/// compile until it is given a family here. The EVM families are one per
/// message kind (see [EvmMessageFamily]).
MessageFamily<MessageRequest, SignResult> familyForMessage(
  MessageRequest request,
) => switch (request) {
  EvmMessageRequest(:final type) => switch (type) {
    EvmMessageType.personal => evmPersonalMessageFamily,
    EvmMessageType.typedData => evmTypedDataMessageFamily,
  },
};
