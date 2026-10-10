import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wallet_core_flutter_example/src/m0_flow.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('M0 Flow Test', (WidgetTester tester) async {
    final flow = M0Flow();

    // 1. Initialize
    await flow.initialize();
    expect(flow.isReady, isTrue);

    // 2. Create wallet
    flow.chooseStrength(128);
    await flow.createWallet();
    expect(flow.created, isNotNull);
    expect(flow.created!.error, isNull);

    // Reveal mnemonic (required by the flow)
    await flow.revealMnemonic();
    flow.hideMnemonic();

    // 3. Import wallet
    // Invalid mnemonic check
    await flow.importWallet(
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon',
    );
    expect(flow.imported, isNotNull);
    expect(flow.imported!.error, isNotNull);
    expect(flow.imported!.error!.title, 'InvalidInputError');

    // Valid mnemonic
    final mnemonic =
        'broom ramp luggage this language sketch door allow elbow wife moon impulse';
    final imported = await flow.importWallet(mnemonic);
    expect(imported, isTrue);
    expect(flow.imported!.error, isNull);

    // 4. Derive address
    flow.choose(WalletChoice.imported);
    await flow.deriveAddress("m/44'/60'/0'/0/1");
    expect(flow.derived!.error, isNull);
    expect(
      flow.derived!.facts.any(
        (f) =>
            f.label == 'address' &&
            f.value == '0x996891c410FB76C19DBA72C6f6cEFF2d9DD069b1',
      ),
      isTrue,
    );

    // 5. Sign EIP-1559 transfer
    await flow.signTransfer();
    expect(flow.signed!.error, isNull);

    // 6. Close wallets and shutdown
    await flow.closeWallets();
    expect(flow.walletsClosed!.error, isNull);

    await flow.shutdown();
    expect(flow.shutDown!.error, isNull);
    expect(flow.hasEnded, isTrue);
  });
}
