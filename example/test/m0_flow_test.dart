// The example app with no native library: the SDK's real session, queue, and
// in-process executor over a fake request handler (support/test_seam.dart),
// plus the public `WalletCore.initialize()` failing as it must until the
// native packaging lands. Runs under plain `flutter test`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';
import 'package:wallet_core_flutter_example/main.dart';

import 'support/test_seam.dart';
import 'support/ui.dart';

void main() {
  testWidgets('the public initialize() fails typed and is shown as a state; '
      'no session, nothing to close', (tester) async {
    // The real `WalletCore.initialize`: it takes no library path, and the
    // shipped identity is still a placeholder, so it fails here.
    await tester.pumpWidget(const ExampleApp());
    await tapKey(tester, 'initialize');

    expect(
      textUnder(tester, 'outcome-initialize'),
      anyOf(startsWith('NativeLoadError'), startsWith('ManifestMismatchError')),
    );
    expect(textUnder(tester, 'session-state'), 'SessionState: no session');
    expect(isEnabled(tester, 'initialize'), isTrue, reason: 'retry allowed');
    expect(isEnabled(tester, 'create'), isFalse);
  });

  testWidgets('the M0 flow, step by step, over the fake handler', (
    tester,
  ) async {
    WalletCore? core;
    await tester.pumpWidget(
      ExampleApp(startSession: () async => core = await startFakeSession()),
    );

    // 1 · initialize
    await tapKey(tester, 'initialize');
    expect(textUnder(tester, 'session-state'), 'SessionState: ready');

    // 2 · create; the mnemonic only through exportMnemonic(), once
    await tapKey(tester, 'create');
    expect(textUnder(tester, 'outcome-create'), contains('wallet: Wallet(#1)'));
    expect(byKey('mnemonic-words'), findsNothing);
    await tapKey(tester, 'reveal');
    expect(find.text(fakeMnemonic), findsOneWidget);
    expect(textUnder(tester, 'outcome-reveal'), 'exportMnemonic(): 12 words');
    await tapKey(tester, 'hide');
    expect(find.text(fakeMnemonic), findsNothing);
    expect(isEnabled(tester, 'reveal'), isFalse, reason: 'shown once');

    // 3 · import, validated live through `mnemonics`
    await enterKey(tester, 'import-field', 'abandon abou');
    expect(
      textUnder(tester, 'import-check'),
      '2 words · every finished word is in the BIP-39 English list · '
      'word 2 still being typed · valid mnemonic: no',
    );
    await enterKey(tester, 'import-field', 'abandon zzzz about');
    expect(
      textUnder(tester, 'import-check'),
      '3 words · not in the list: word 2 · valid mnemonic: no',
    );
    await enterKey(tester, 'import-field', fakeMnemonic);
    expect(
      textUnder(tester, 'import-check'),
      '12 words · every finished word is in the BIP-39 English list · '
      'valid mnemonic: yes',
    );
    await tapKey(tester, 'import');
    expect(textUnder(tester, 'outcome-import'), contains('Wallet(#2)'));
    final field = tester.widget<TextField>(byKey('import-field'));
    expect(field.controller!.text, isEmpty, reason: 'the app keeps no copy');

    // 4 · derive from the imported wallet (selected after the import)
    await tapKey(tester, 'derive');
    final derived = textUnder(tester, 'outcome-derive');
    expect(derived, contains('wallet: Wallet(#2)'));
    expect(derived, contains('coin: Ethereum (ethereum)'));
    expect(derived, contains("path: m/44'/60'/0'/0/0"));
    expect(derived, contains('address: 0x${'ab' * 19}02'));

    // 5 · a key-less request, signed with a KeyLocator
    await tapKey(tester, 'sign');
    final signed = textUnder(tester, 'outcome-sign');
    expect(signed, contains('result: EvmSignResult (ethereum)'));
    expect(signed, contains('encoded: 4 bytes'));
    expect(signed, contains('r: ${'11' * 32}'));
    expect(
      signed,
      contains(
        "usedKeys: HdKeyLocator(WalletRef(#2), ethereum, "
        "m/44'/60'/0'/0/0)",
      ),
    );

    // 6 · close and shut down
    await tapKey(tester, 'close-wallets');
    final closed = textUnder(tester, 'outcome-close');
    expect(closed, contains('created wallet: Wallet(#1, closed)'));
    expect(closed, contains('imported wallet: Wallet(#2, closed)'));
    expect(liveWalletCount(core!), 0);
    await tapKey(tester, 'shutdown');
    expect(textUnder(tester, 'session-state'), 'SessionState: closed');
    expect(
      textUnder(tester, 'session-states'),
      'states seen: ready → closing → closed',
    );
    await tapKey(tester, 'start-over');
    expect(textUnder(tester, 'session-state'), 'SessionState: no session');
  });

  testWidgets('the shown mnemonic and the typed one stay out of the '
      'semantics tree', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const ExampleApp(startSession: startFakeSession));
    await tapKey(tester, 'initialize');
    await tapKey(tester, 'create');
    await tapKey(tester, 'reveal');
    await enterKey(tester, 'import-field', fakeMnemonic);

    // On screen: shown, and typed into the (obscured) import field.
    expect(byKey('mnemonic-words'), findsOneWidget);
    expect(find.text(fakeMnemonic), findsNWidgets(2));
    expect(find.semantics.byLabel(RegExp('abandon|about')), findsNothing);
    expect(find.semantics.byValue(RegExp('abandon|about')), findsNothing);
    // The semantics tree is live: the notice beside the words is in it.
    expect(find.semantics.byLabel(RegExp('withheld')), findsOneWidget);

    await tapKey(tester, 'shutdown');
    semantics.dispose();
  });

  testWidgets('invalid inputs surface as their public error types', (
    tester,
  ) async {
    await tester.pumpWidget(const ExampleApp(startSession: startFakeSession));
    await tapKey(tester, 'initialize');

    // Wrong word count: rejected in Dart before anything crosses.
    await enterKey(tester, 'import-field', 'abandon about');
    await tapKey(tester, 'import');
    expect(
      textUnder(tester, 'outcome-import'),
      allOf(startsWith('InvalidInputError'), contains('input: mnemonic')),
    );

    await tapKey(tester, 'create');
    // A malformed path: test vector ethereum-invalid_input-n/a-3
    // (test_vectors/ethereum/vectors.yaml; BIP-44).
    await enterKey(tester, 'path-field', 'm/44/60/invalid');
    await tapKey(tester, 'derive');
    expect(
      textUnder(tester, 'outcome-derive'),
      allOf(startsWith('InvalidInputError'), contains('input: derivationPath')),
    );
    await enterKey(tester, 'path-field', '');
    await tapKey(tester, 'derive');

    // A malformed recipient: test vector ethereum-invalid_input-n/a-2
    // (test_vectors/ethereum/vectors.yaml; EIP-55).
    await enterKey(
      tester,
      'tx-to',
      '0xZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ',
    );
    await tapKey(tester, 'sign');
    expect(
      textUnder(tester, 'outcome-sign'),
      allOf(startsWith('InvalidInputError'), contains('input: to')),
    );

    // Not a number: the app refuses it before the SDK sees anything.
    await enterKey(
      tester,
      'tx-to',
      '0xB9F5771C27664bF2282D98E09D7F50cEc7cB01a7',
    );
    await enterKey(tester, 'tx-nonce', 'seven');
    await tapKey(tester, 'sign');
    expect(
      textUnder(tester, 'outcome-sign'),
      'Not sent\nnonce is not a whole number',
    );

    // Signing with a closed wallet's key.
    await enterKey(tester, 'tx-nonce', '6');
    await tapKey(tester, 'close-wallets');
    await tapKey(tester, 'sign');
    expect(textUnder(tester, 'outcome-sign'), startsWith('ClosedError'));

    await tapKey(tester, 'shutdown');
  });
}
