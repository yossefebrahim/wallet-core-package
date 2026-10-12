part of '../requests.dart';

/// The most satoshis any amount of a [UtxoTransactionRequest] may name: the
/// 21 000 000 coins of Bitcoin's supply, in its smallest unit.
const int maxUtxoAmount = 2100000000000000;

/// The highest fee rate, in smallest units per byte, a request accepts. Far
/// above any fee market; it exists so that upstream's `fee = rate × size`
/// cannot overflow its 64-bit arithmetic.
const int maxUtxoFeeRatePerByte = 1000000;

/// The most inputs a request names. Upstream cuts its own selection off at
/// 3000; this SDK stops well short of it.
const int maxUtxoInputs = 1000;

/// The longest locking script an input may carry: Bitcoin's consensus limit
/// on a script's size.
const int maxUtxoScriptBytes = 10000;

/// Letters and digits only, 1–90 of them: every Bitcoin address form this
/// request takes (base58 and bech32/bech32m, at most 90 characters). Syntax
/// only; whether the address is *valid* is upstream's answer, asked for at
/// sign time (`TWAnyAddress`).
final RegExp _utxoAddressSyntax = RegExp(r'^[0-9A-Za-z]{1,90}$');

/// A UTXO spend from several outputs, with the name of the key behind each
/// (`docs/architecture/signing.md` §3.2). Bitcoin mainnet at this version.
///
/// **Validated at construction.** [InvalidInputError] names the input when
/// [coin] is not a UTXO coin, [toAddress] or [changeAddress] is not 1–90
/// letters and digits, [amount] is outside `1 … 2.1e15`, [feeRatePerByte] is
/// outside `1 … 1 000 000`, [inputs] is empty, longer than 1000, or names one
/// output twice, an input's amount or script is out of bounds, or an input's
/// locator carries a role (the request assigns them). Any UTXO coin but
/// Bitcoin, and an input of [AddressStyle.taproot], are
/// [UnsupportedOperationError]s. Whether the addresses are valid, and what
/// script type each input's script is, are upstream's answers
/// (`TWAnyAddress`, `TWBitcoinScript`), asked for in the signing isolate
/// before any key exists — a request never calls native code.
///
/// **What it accepts, exactly.** An input is spendable when its [UtxoInput.script]
/// is a P2WPKH script (`OP_0 <20 bytes>`) with [AddressStyle.standard] or
/// [AddressStyle.segwit], or a pay-to-public-key script (`<33-byte key>
/// OP_CHECKSIG`) with [AddressStyle.standard] or [AddressStyle.legacy].
/// Anything else — P2PKH, P2SH, P2WSH, multisig, taproot, a P2PK script with
/// an uncompressed key, an unknown script — is an
/// [UnsupportedOperationError] naming the script type (`script:p2pkh`, …).
/// Upstream's own helpers tell the types apart, in the signing isolate; the
/// SDK builds no script. The recipient and
/// change addresses may be any address upstream accepts for Bitcoin.
///
/// **Keys.** Each input names the key that spends it. Inputs that name equal
/// locators share one key: [keyLocators] holds one locator per *distinct*
/// key, in the order of first use, and each carries the role
/// `KeyRole.input(n)` where `n` is the position of the first input that uses
/// it. Pass [keyLocators] to `Signer.sign`; with a single distinct key,
/// `Signer.signWithKey` takes that one locator as it is. A request built with
/// [withPlan] needs only the keys of the inputs its plan selected.
///
/// Immutable: [inputs] is copied.
final class UtxoTransactionRequest implements TransactionRequest {
  /// A spend of [inputs] paying [amount] to [toAddress], with change to
  /// [changeAddress], at [feeRatePerByte].
  ///
  /// Upstream chooses which inputs to spend ([Signer.plan] shows its choice).
  /// With [useMaxAmount] it spends all of them, less the fee, and [amount] is
  /// not used — pass any positive value.
  UtxoTransactionRequest({
    required Coin coin,
    required String toAddress,
    required int amount,
    required int feeRatePerByte,
    required String changeAddress,
    required List<UtxoInput> inputs,
    bool useMaxAmount = false,
  }) : this._(
         coin: coin,
         toAddress: toAddress,
         amount: amount,
         feeRatePerByte: feeRatePerByte,
         changeAddress: changeAddress,
         inputs: _copyUtxoInputs(inputs),
         useMaxAmount: useMaxAmount,
       );

  UtxoTransactionRequest._({
    required this.coin,
    required this.toAddress,
    required this.amount,
    required this.feeRatePerByte,
    required this.changeAddress,
    required this.inputs,
    required this.useMaxAmount,
    this.plan,
  }) {
    if (coin.family != ChainFamily.utxo) {
      throw InvalidInputError(
        '${coin.id} is not a UTXO coin; a UTXO request needs one',
        inputName: 'coin',
      );
    }
    if (coin != Coin.bitcoin) {
      throw UnsupportedOperationError(coin, 'utxo-transaction');
    }
    if (!_utxoAddressSyntax.hasMatch(toAddress)) {
      throw const InvalidInputError(
        'toAddress must be 1 to 90 letters and digits',
        inputName: 'toAddress',
      );
    }
    if (!_utxoAddressSyntax.hasMatch(changeAddress)) {
      throw const InvalidInputError(
        'changeAddress must be 1 to 90 letters and digits',
        inputName: 'changeAddress',
      );
    }
    if (amount < 1 || amount > maxUtxoAmount) {
      throw const InvalidInputError(
        'amount must be between 1 and $maxUtxoAmount',
        inputName: 'amount',
      );
    }
    if (feeRatePerByte < 1 || feeRatePerByte > maxUtxoFeeRatePerByte) {
      throw const InvalidInputError(
        'feeRatePerByte must be between 1 and $maxUtxoFeeRatePerByte',
        inputName: 'feeRatePerByte',
      );
    }
    if (inputs.isEmpty) {
      throw const InvalidInputError(
        'a UTXO request needs at least one input',
        inputName: 'inputs',
      );
    }
    final outPoints = <OutPoint>{};
    for (final (index, input) in inputs.indexed) {
      if (input.amount > maxUtxoAmount) {
        throw InvalidInputError(
          'inputs[$index].amount must not exceed $maxUtxoAmount',
          inputName: 'inputs',
        );
      }
      final scriptLength = input.script.length;
      if (scriptLength < 1 || scriptLength > maxUtxoScriptBytes) {
        throw InvalidInputError(
          'inputs[$index].script must be 1 to $maxUtxoScriptBytes bytes',
          inputName: 'inputs',
        );
      }
      if (input.keyLocator.role != null) {
        throw InvalidInputError(
          'inputs[$index].keyLocator names a role; the request assigns the '
          'input roles itself',
          inputName: 'inputs',
        );
      }
      if (input.addressStyle == AddressStyle.taproot) {
        throw UnsupportedOperationError(coin, 'addressStyle:taproot');
      }
      if (!outPoints.add(input.outPoint)) {
        throw InvalidInputError(
          'inputs[$index] spends an output an earlier input already spends',
          inputName: 'inputs',
        );
      }
    }
    if (plan case final plan?) {
      for (final selected in plan.selectedInputs) {
        if (!inputs.contains(selected)) {
          throw const InvalidInputError(
            'the plan selects an input this request does not have',
            inputName: 'plan',
          );
        }
      }
    }
    final seen = <KeyLocator>{};
    final keys = <KeyLocator>[];
    for (final (index, input) in (plan?.selectedInputs ?? inputs).indexed) {
      if (!seen.add(input.keyLocator)) continue;
      keys.add(_utxoLocatorWithRole(input.keyLocator, KeyRole.input(index)));
    }
    keyLocators = Set<KeyLocator>.unmodifiable(keys);
  }

  @override
  final Coin coin;

  /// Always [Network.mainnet]: only Bitcoin mainnet is supported.
  @override
  Network get network => Network.mainnet;

  /// One locator per distinct key the signature needs, in the order of first
  /// use, each carrying the role `KeyRole.input(n)` of the first input that
  /// uses it. The set `Signer.sign` takes for this request.
  @override
  late final Set<KeyLocator> keyLocators;

  /// The recipient's address.
  final String toAddress;

  /// The amount to pay [toAddress], in satoshis. Not used with
  /// [useMaxAmount].
  final int amount;

  /// The fee rate, in satoshis per byte.
  final int feeRatePerByte;

  /// Where the change goes.
  final String changeAddress;

  /// The outputs that may be spent. Upstream selects among them unless a
  /// [plan] says which.
  final List<UtxoInput> inputs;

  /// Whether to spend every input, less the fee, instead of [amount].
  final bool useMaxAmount;

  /// The plan this request signs, or `null` when upstream plans internally.
  final UtxoPlan? plan;

  /// This request, signing exactly the inputs [plan] selected and paying what
  /// it says.
  ///
  /// Throws [InvalidInputError] (`inputName: 'plan'`) when [plan] selects an
  /// input this request does not have. The plan is *used*, not re-checked:
  /// upstream signs the amount, fee and change it carries.
  UtxoTransactionRequest withPlan(UtxoPlan plan) => UtxoTransactionRequest._(
    coin: coin,
    toAddress: toAddress,
    amount: amount,
    feeRatePerByte: feeRatePerByte,
    changeAddress: changeAddress,
    inputs: inputs,
    useMaxAmount: useMaxAmount,
    plan: plan,
  );

  /// The coin, the amount, the fee rate, how many inputs and keys, and the
  /// addresses. Nothing in a request is a secret.
  @override
  String toString() =>
      'UtxoTransactionRequest(${coin.id}, to: $toAddress, amount: $amount, '
      'feeRatePerByte: $feeRatePerByte, change: $changeAddress, '
      'inputs: ${inputs.length}, keys: ${keyLocators.length}'
      '${useMaxAmount ? ', useMaxAmount' : ''}'
      '${plan == null ? '' : ', planned'})';
}

/// What upstream's planner chose for a [UtxoTransactionRequest]: which inputs
/// to spend, and what it costs (`docs/architecture/signing.md` §3.2).
///
/// A plain value; sign it with [UtxoTransactionRequest.withPlan]. All
/// amounts are in satoshis.
final class UtxoPlan {
  /// A plan spending [selectedInputs], in the order upstream selected them.
  ///
  /// Throws [InvalidInputError] (`inputName: 'plan'`) when [selectedInputs]
  /// is empty or longer than 1000, or an amount is negative or above
  /// 2.1e15. [selectedInputs] is copied.
  UtxoPlan({
    required List<UtxoInput> selectedInputs,
    required this.amount,
    required this.availableAmount,
    required this.fee,
    required this.change,
  }) : selectedInputs = _copyUtxoInputs(selectedInputs) {
    if (selectedInputs.isEmpty) {
      throw const InvalidInputError(
        'a plan selects at least one input',
        inputName: 'plan',
      );
    }
    for (final value in <int>[amount, availableAmount, fee, change]) {
      if (value < 0 || value > maxUtxoAmount) {
        throw const InvalidInputError(
          'a plan amount must be between 0 and $maxUtxoAmount',
          inputName: 'plan',
        );
      }
    }
  }

  /// The inputs upstream selected, in its order — the order of the
  /// transaction's inputs.
  final List<UtxoInput> selectedInputs;

  /// What the recipient receives.
  final int amount;

  /// The sum of the selected inputs, as upstream reports it (an input below
  /// its dust threshold is neither selected nor counted).
  final int availableAmount;

  /// The fee.
  final int fee;

  /// What returns to the change address; zero when upstream adds no change
  /// output.
  final int change;

  @override
  String toString() =>
      'UtxoPlan(inputs: ${selectedInputs.length}, amount: $amount, '
      'fee: $fee, change: $change, available: $availableAmount)';
}

/// The inputs, copied after their count was checked, so that an over-long
/// list is rejected before anything of that size is allocated.
List<UtxoInput> _copyUtxoInputs(List<UtxoInput> inputs) {
  if (inputs.length > maxUtxoInputs) {
    throw const InvalidInputError(
      'at most $maxUtxoInputs inputs are accepted',
      inputName: 'inputs',
    );
  }
  return List<UtxoInput>.unmodifiable(inputs);
}

/// [locator] naming the same key in [role].
KeyLocator _utxoLocatorWithRole(KeyLocator locator, KeyRole role) =>
    switch (locator) {
      HdKeyLocator(:final wallet, :final coin, :final derivationPath) =>
        HdKeyLocator(wallet, coin, derivationPath, role: role),
      ImportedKeyLocator(:final key) => ImportedKeyLocator(key, role: role),
      ExternalKeyLocator(:final deviceId, :final publicKey) =>
        ExternalKeyLocator(deviceId, publicKey, role: role),
    };
