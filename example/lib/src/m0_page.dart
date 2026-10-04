/// The M0 flow as one scrolling page: six steps, each with its call, its
/// controls, and its visible result.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// Widget keys name controls, never values. The shown mnemonic is excluded
/// from the semantics tree, and the import field is obscured, so neither
/// reaches accessibility services or a semantics dump.
library;

import 'package:flutter/material.dart';

import 'm0_flow.dart';

/// The page. [startSession] is step 1's call.
class M0Page extends StatefulWidget {
  /// A page whose step 1 calls [startSession].
  const M0Page({super.key, required this.startSession});

  /// `WalletCore.initialize` in the app.
  final SessionStarter startSession;

  @override
  State<M0Page> createState() => _M0PageState();
}

class _M0PageState extends State<M0Page> {
  late final M0Flow _flow;
  final TextEditingController _importText = TextEditingController();
  final TextEditingController _path = TextEditingController();
  late final List<_TxField> _txFields;

  @override
  void initState() {
    super.initState();
    _flow = M0Flow(startSession: widget.startSession);
    final form = _flow.form;
    _txFields = [
      _TxField('chainId', form.chainId, (v) => form.chainId = v),
      _TxField('nonce', form.nonce, (v) => form.nonce = v),
      _TxField('to', form.to, (v) => form.to = v),
      _TxField('valueWei', form.valueWei, (v) => form.valueWei = v),
      _TxField('maxFeePerGas', form.maxFeePerGas, (v) => form.maxFeePerGas = v),
      _TxField(
        'maxPriorityFeePerGas',
        form.maxPriorityFeePerGas,
        (v) => form.maxPriorityFeePerGas = v,
      ),
      _TxField('gasLimit', form.gasLimit, (v) => form.gasLimit = v),
    ];
  }

  @override
  void dispose() {
    _importText.dispose();
    _path.dispose();
    for (final field in _txFields) {
      field.controller.dispose();
    }
    _flow.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    if (await _flow.importWallet(_importText.text)) _importText.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('wallet_core_flutter · M0 flow')),
      body: ListenableBuilder(
        listenable: _flow,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Every call on this page goes through '
                'package:wallet_core_flutter/wallet_core_flutter.dart. '
                'Nothing is logged and nothing leaves the device.',
              ),
              const SizedBox(height: 12),
              _initializeStep(context),
              _createStep(context),
              _importStep(context),
              _deriveStep(context),
              _signStep(context),
              _closeStep(context),
              const SizedBox(height: 12),
              Text(
                'Unofficial Dart/Flutter SDK for the open-source Trust Wallet '
                'Core library. Not affiliated with or endorsed by Trust Wallet.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _idle => !_flow.isBusy;

  bool get _canOperate => _idle && _flow.isReady;

  Widget _initializeStep(BuildContext context) => _Step(
    number: 1,
    title: 'Start a session',
    call: 'WalletCore.initialize()',
    children: [
      Text(
        'SessionState: ${_flow.state?.name ?? 'no session'}',
        key: const ValueKey('session-state'),
      ),
      if (_flow.states.isNotEmpty)
        Text(
          'states seen: ${_flow.states.map((s) => s.name).join(' → ')}',
          key: const ValueKey('session-states'),
        ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton(
            key: const ValueKey('initialize'),
            onPressed: _idle && _flow.state == null ? _flow.initialize : null,
            child: const Text('Initialize'),
          ),
          if (_flow.hasEnded)
            OutlinedButton(
              key: const ValueKey('start-over'),
              onPressed: _idle ? _flow.startOver : null,
              child: const Text('Start over'),
            ),
        ],
      ),
      _Outcome(_flow.initialized, key: const ValueKey('outcome-initialize')),
      if (_flow.initialized?.error != null)
        const Text(
          'No session was returned, so nothing needs closing. Until the '
          'native packaging lands (DECISION-2, T1.16b) this is the expected '
          'result on a device: see the README.',
        ),
    ],
  );

  Widget _createStep(BuildContext context) => _Step(
    number: 2,
    title: 'Create a wallet',
    call: 'wallets.create(strength:) → wallet.exportMnemonic()',
    children: [
      DropdownButton<int>(
        key: const ValueKey('strength'),
        value: _flow.strength,
        onChanged: _canOperate ? (v) => _flow.chooseStrength(v!) : null,
        items: [
          for (final bits in mnemonicStrengths)
            DropdownMenuItem(
              value: bits,
              child: Text('$bits bits (${bits * 3 ~/ 32} words)'),
            ),
        ],
      ),
      FilledButton(
        key: const ValueKey('create'),
        onPressed: _canOperate ? _flow.createWallet : null,
        child: const Text('Create'),
      ),
      _Outcome(_flow.created, key: const ValueKey('outcome-create')),
      const SizedBox(height: 8),
      OutlinedButton(
        key: const ValueKey('reveal'),
        onPressed: _idle && _flow.canReveal ? _flow.revealMnemonic : null,
        child: const Text('Show the mnemonic once'),
      ),
      if (_flow.shownMnemonic case final mnemonic?) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                label:
                    'The mnemonic is on screen. It is withheld from '
                    'accessibility services.',
                child: const Text('Write these words down, then hide them:'),
              ),
              const SizedBox(height: 8),
              ExcludeSemantics(
                child: Text(
                  mnemonic,
                  key: const ValueKey('mnemonic-words'),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                key: const ValueKey('hide'),
                onPressed: _flow.hideMnemonic,
                child: const Text('I have written it down — hide'),
              ),
            ],
          ),
        ),
      ],
      _Outcome(_flow.revealed, key: const ValueKey('outcome-reveal')),
    ],
  );

  Widget _importStep(BuildContext context) => _Step(
    number: 3,
    title: 'Import a mnemonic',
    call:
        'mnemonics.isValidWord / suggest / isValid → wallets.importMnemonic()',
    children: [
      TextField(
        key: const ValueKey('import-field'),
        controller: _importText,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
        keyboardType: TextInputType.visiblePassword,
        enabled: _flow.isReady,
        onChanged: _flow.checkImportText,
        decoration: const InputDecoration(
          labelText: 'Mnemonic (12–24 words, obscured)',
        ),
      ),
      const SizedBox(height: 4),
      _ImportCheckView(_flow.importCheck, key: const ValueKey('import-check')),
      const SizedBox(height: 8),
      FilledButton(
        key: const ValueKey('import'),
        onPressed: _canOperate ? _import : null,
        child: const Text('Import'),
      ),
      _Outcome(_flow.imported, key: const ValueKey('outcome-import')),
    ],
  );

  Widget _deriveStep(BuildContext context) => _Step(
    number: 4,
    title: 'Derive an Ethereum address',
    call: 'wallet.account(Coin.ethereum, path:)',
    children: [
      SegmentedButton<WalletChoice>(
        key: const ValueKey('wallet-choice'),
        segments: [
          for (final choice in WalletChoice.values)
            ButtonSegment(
              value: choice,
              label: Text('${choice.name} wallet'),
              enabled: _flow.hasWallet(choice),
            ),
        ],
        selected: {_flow.choice},
        onSelectionChanged: _idle ? (s) => _flow.choose(s.first) : null,
      ),
      TextField(
        key: const ValueKey('path-field'),
        controller: _path,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: 'Derivation path (empty: the coin default)',
          hintText: "m/44'/60'/0'/0/0",
        ),
      ),
      const SizedBox(height: 8),
      FilledButton(
        key: const ValueKey('derive'),
        onPressed: _canOperate ? () => _flow.deriveAddress(_path.text) : null,
        child: const Text('Derive'),
      ),
      _Outcome(_flow.derived, key: const ValueKey('outcome-derive')),
    ],
  );

  Widget _signStep(BuildContext context) => _Step(
    number: 5,
    title: 'Sign an EIP-1559 transfer',
    call:
        'EvmTransactionRequest.transfer(…) → '
        'signer.sign(request, {KeyLocator.hdPath(wallet.ref, coin, path)})',
    children: [
      const Text(
        'The request carries no key; the locator names step 4\'s key. '
        'Defaults: the request of vector ethereum-sign-eip1559-1 (chain id 3, '
        'a deprecated testnet).',
      ),
      for (final field in _txFields)
        TextField(
          key: ValueKey('tx-${field.name}'),
          controller: field.controller,
          onChanged: field.onChanged,
          autocorrect: false,
          decoration: InputDecoration(labelText: field.name, isDense: true),
        ),
      const SizedBox(height: 8),
      FilledButton(
        key: const ValueKey('sign'),
        onPressed: _canOperate && _flow.hasSigningKey
            ? _flow.signTransfer
            : null,
        child: const Text('Sign'),
      ),
      _Outcome(_flow.signed, key: const ValueKey('outcome-sign')),
    ],
  );

  Widget _closeStep(BuildContext context) => _Step(
    number: 6,
    title: 'Close and shut down',
    call: 'wallet.close() → WalletCore.shutdown()',
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
            key: const ValueKey('close-wallets'),
            onPressed: _idle && _flow.state != null ? _flow.closeWallets : null,
            child: const Text('Close wallets'),
          ),
          FilledButton(
            key: const ValueKey('shutdown'),
            onPressed: _canOperate ? _flow.shutdown : null,
            child: const Text('Shut down'),
          ),
        ],
      ),
      _Outcome(_flow.walletsClosed, key: const ValueKey('outcome-close')),
      _Outcome(_flow.shutDown, key: const ValueKey('outcome-shutdown')),
      const Text(
        'The leak tracker\'s report is not part of the public surface, so this '
        'app cannot show it; the states above are what a consumer can see.',
      ),
    ],
  );
}

/// One editable field of the step 5 request.
final class _TxField {
  _TxField(this.name, String initial, this.onChanged)
    : controller = TextEditingController(text: initial);

  final String name;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
}

/// A numbered card: title, the SDK call it makes, its contents.
class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.call,
    required this.children,
  });

  final int number;
  final String title;
  final String call;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$number · $title', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              call,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A step's result: its facts, or its error's public type name and details.
class _Outcome extends StatelessWidget {
  const _Outcome(this.outcome, {super.key});

  final StepOutcome? outcome;

  @override
  Widget build(BuildContext context) {
    final outcome = this.outcome;
    if (outcome == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final error = outcome.error;
    if (error != null) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(8),
        color: scheme.errorContainer,
        child: DefaultTextStyle.merge(
          style: TextStyle(color: scheme.onErrorContainer),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                error.title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              for (final line in error.lines) Text(line),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final fact in outcome.facts)
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${fact.label}: ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(
                    text: fact.value,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The live import check: counts and positions, never a word.
class _ImportCheckView extends StatelessWidget {
  const _ImportCheckView(this.check, {super.key});

  final ImportCheck? check;

  @override
  Widget build(BuildContext context) {
    final check = this.check;
    if (check == null) return const Text('Type a mnemonic to check it.');
    final error = check.error;
    if (error != null) return Text('Check failed: ${error.title}');
    final parts = <String>[
      '${check.wordCount} words',
      if (check.unknownWords.isEmpty)
        'every finished word is in the BIP-39 English list'
      else
        'not in the list: word ${check.unknownWords.join(', ')}',
      if (check.incompleteWord case final position?)
        'word $position still being typed',
      'valid mnemonic: ${check.isValid ? 'yes' : 'no'}',
    ];
    return Text(parts.join(' · '));
  }
}
