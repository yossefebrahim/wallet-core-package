/// The example app's M0 flow against the real host library, driven through
/// the page. Skips when the library is absent; `WCF_NATIVE_REQUIRED=1` turns
/// that into a failure (support/host_library.dart).
///
/// The session starts through the SDK's internal test entry point
/// (support/test_seam.dart) because the public `initialize()` takes no
/// library path; everything after that is the app's public-surface calls.
@Tags(['native'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';
import 'package:wallet_core_flutter_example/main.dart';

import 'support/host_library.dart';
import 'support/test_seam.dart';
import 'support/ui.dart';

/// Test vector `ethereum-address-n/a-1` (test_vectors/ethereum/vectors.yaml):
/// upstream swift/Tests/Blockchains/EthereumTests.swift at commit
/// d692ac27749d0c615e17c751b70ab4f0aa75c59b.
const String _vectorMnemonic =
    'broom ramp luggage this language sketch door allow elbow wife moon '
    'impulse';
const String _vectorPath = "m/44'/60'/0'/0/1";
const String _vectorAddress = '0x996891c410FB76C19DBA72C6f6cEFF2d9DD069b1';
const String _vectorPublicKey =
    '044516c4aa5352035e1bb5be132694e1389a4ac37d32e5e717d35ee4c4dfab5132'
    '26a9d14ea37a55962ad3644a08e2ce551b4495beabb9b09e688c7b92eba18acc';

/// Test vector `ethereum-invalid_input-n/a-1` (test_vectors/ethereum/
/// vectors.yaml; BIP-39): twelve known words, a wrong checksum.
const String _invalidMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon';

void main() {
  final skip = hostLibrarySkipReason();

  testWidgets('the M0 flow against the host library', (tester) async {
    final libraryPath = findHostLibrary()!;
    WalletCore? core;
    await tester.pumpWidget(
      ExampleApp(
        startSession: () async => core = await startHostSession(libraryPath),
      ),
    );

    // 1 · initialize
    await tapKey(tester, 'initialize');
    expect(textUnder(tester, 'session-state'), 'SessionState: ready');

    // 2 · create at 256 bits; 24 words, shown once
    await tester.tap(byKey('strength'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('256 bits (24 words)').last);
    await tester.pumpAndSettle();
    await tapKey(tester, 'create');
    expect(textUnder(tester, 'outcome-create'), contains('256 bits'));
    await tapKey(tester, 'reveal');
    expect(textUnder(tester, 'outcome-reveal'), 'exportMnemonic(): 24 words');
    await tapKey(tester, 'hide');
    expect(byKey('mnemonic-words'), findsNothing);
    expect(isEnabled(tester, 'reveal'), isFalse);

    // 3 · live validation by upstream, then import the vector's mnemonic
    await enterKey(tester, 'import-field', _invalidMnemonic);
    expect(
      textUnder(tester, 'import-check'),
      '12 words · every finished word is in the BIP-39 English list · '
      'valid mnemonic: no',
    );
    await enterKey(tester, 'import-field', _vectorMnemonic);
    expect(textUnder(tester, 'import-check'), endsWith('valid mnemonic: yes'));
    await tapKey(tester, 'import');
    expect(textUnder(tester, 'outcome-import'), contains('Wallet(#2)'));

    // 4 · the vector's address at the vector's path
    await enterKey(tester, 'path-field', _vectorPath);
    await tapKey(tester, 'derive');
    final derived = textUnder(tester, 'outcome-derive');
    expect(derived, contains('address: $_vectorAddress'));
    expect(derived, contains('public key: 65 bytes, $_vectorPublicKey'));

    // 5 · sign the default request with that account's key. The vector's
    // expected bytes belong to a raw key this flow cannot use, so the check
    // is the shape: an EIP-1559 (type 2) envelope and 32-byte r and s.
    await tapKey(tester, 'sign');
    final signed = textUnder(tester, 'outcome-sign');
    expect(signed, contains('result: EvmSignResult (ethereum)'));
    expect(signed, matches(RegExp(r'encoded hex: 02f8[0-9a-f]+\n')));
    expect(signed, matches(RegExp(r'\nr: [0-9a-f]{64}\n')));
    expect(signed, matches(RegExp(r'\ns: [0-9a-f]{64}')));
    expect(signed, contains('$_vectorPath)'), reason: 'usedKeys names it');

    // 6 · close: the leak tracker (not public; read through the seam) has
    // nothing live and nothing finalized without disposal.
    await tapKey(tester, 'close-wallets');
    expect(liveWalletCount(core!), 0);
    final leaks = leakCounts(core!);
    expect(leaks, isNotNull, reason: 'a debug build has a tracker');
    expect(leaks!.live, 0);
    expect(leaks.finalizedWithoutDispose, 0);
    await tapKey(tester, 'shutdown');
    expect(textUnder(tester, 'session-state'), 'SessionState: closed');
  }, skip: skip != null);
}
