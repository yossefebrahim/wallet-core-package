// PRD §12.2 steps 2 and 4 (runtime half) for DECISION-2 Option 1, in a built
// app: the library the build hook bundled loads from its code-asset location,
// carries the evaluation manifest's identity, resolves every bound symbol,
// and answers one real call.
//
//   flutter test integration_test/wallet_core_test.dart -d <device> \
//       --dart-define=WCF_EXPECTED_ARTIFACT_SET_ID=as_4.8.0_000 \
//       --dart-define=WCF_EXPECTED_UPSTREAM_COMMIT=d692ac27749d0c615e17c751b70ab4f0aa75c59b
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart';
import 'package:wcf_eval_option1/wallet_core_probe.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('the hook-bundled library loads, identifies itself and works', () {
    final result = runProbe();
    // ignore: avoid_print
    print('WCF_PROBE PASS $result');

    expect(result.identity.artifactSetId, expectedArtifactSetId);
    expect(result.identity.upstreamCommit, expectedUpstreamCommit);
    expect(
      result.symbolsResolved,
      {...boundFunctionNames, ...exportedTwFunctionNames}.length + 1,
    );
    expect(result.ethereumAddressValid, isTrue);
    expect(result.ethereumGarbageValid, isFalse);
  });
}
