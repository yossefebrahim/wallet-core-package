/// Which [TransactionFamily] handles a request. **Internal**: never exported.
library;

import '../requests/requests.dart';
import '../signing/sign_result.dart';
import 'evm/evm_family.dart';
import 'family.dart';

/// The family that encodes [request] and parses its output.
///
/// Exhaustive over the sealed [TransactionRequest]: a new request type does
/// not compile until it is given a family here.
TransactionFamily<TransactionRequest, SignResult> familyFor(
  TransactionRequest request,
) => switch (request) {
  EvmTransactionRequest() => evmFamily,
};
