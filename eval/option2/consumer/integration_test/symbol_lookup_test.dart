// DECISION-2 Option 2 evaluation (T1.9): the on-target half of PRD §12.2
// steps 2 and 4 for a library packaged by Gradle (Android) or the podspec's
// xcframework (iOS).
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.
//
// Run by eval/option2/run_eval.sh:
//
//   flutter test integration_test/symbol_lookup_test.dart -d <device> \
//       --dart-define=WCF_EXPECT_ARTIFACT_SET_ID=<id> \
//       --dart-define=WCF_EXPECT_UPSTREAM_COMMIT=<sha>
//
// The expected identity is injected from the manifest the build verified
// against (eval/option2/eval_manifest.json), not taken from the package's
// embedded constants, which still carry the root manifest's `TBD-`
// placeholders. Lines printed as `WCF-EVAL key=value` are harvested into the
// results row.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart';
import 'package:wallet_core_flutter_native/wallet_core_flutter_native.dart';

const String _expectedSetId = String.fromEnvironment(
  'WCF_EXPECT_ARTIFACT_SET_ID',
);
const String _expectedCommit = String.fromEnvironment(
  'WCF_EXPECT_UPSTREAM_COMMIT',
);

// EIP-55's own checksummed test address (EIP-55, "Test Cases").
const String _ethereumAddress = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';

// The test's output is the measurement: run_eval.sh greps these lines.
// ignore: avoid_print
void _report(String key, Object value) => print('WCF-EVAL $key=$value');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('records which default location provides the library', () {
    final locations = defaultLocations(platform: NativePlatform.current);
    String? resolvedBy;
    for (final (i, location) in locations.indexed) {
      String outcome;
      try {
        final library = location.open();
        final hasIdentity = library.providesSymbol('wcf_build_info');
        outcome = hasIdentity
            ? 'opens, provides wcf_build_info'
            : 'opens, no wcf_build_info';
        if (hasIdentity) resolvedBy ??= location.description;
      } on Object catch (e) {
        outcome = 'fails: ${e.toString().split('\n').first}';
      }
      _report('location_${i + 1}', '${location.description}: $outcome');
    }
    _report('resolved_by', resolvedBy ?? 'none');
    expect(
      resolvedBy,
      isNotNull,
      reason: 'no default location provided wcf_build_info',
    );
  });

  test('verifies identity, resolves every bound symbol, calls upstream', () {
    expect(
      _expectedSetId.isNotEmpty && _expectedCommit.isNotEmpty,
      isTrue,
      reason:
          'pass --dart-define=WCF_EXPECT_ARTIFACT_SET_ID and '
          'WCF_EXPECT_UPSTREAM_COMMIT from the manifest the build used',
    );
    final library = WalletCoreNative.load();

    final identity = verifyIdentity(
      library,
      expected: const ManifestIdentity(
        artifactSetId: _expectedSetId,
        upstreamCommit: _expectedCommit,
      ),
    );
    _report('identity_artifact_set_id', identity.artifactSetId);
    _report('identity_upstream_commit', identity.upstreamCommit);

    final names = <String>{
      ...boundFunctionNames,
      ...exportedTwFunctionNames,
      'wcf_build_info',
    };
    WalletCoreNative.requireSymbols(library, names);
    _report('symbols_resolved', '${names.length}/${names.length}');

    final context = NativeContext(WalletCoreBindings(library));
    bool isValid(String address) => withTWString(
      context,
      address,
      (s) => context.bindings.TWAnyAddressIsValid(
        s.pointer,
        TWCoinType.TWCoinTypeEthereum,
      ),
    );
    expect(isValid(_ethereumAddress), isTrue);
    expect(isValid(_ethereumAddress.substring(0, 41)), isFalse);
    _report('TWAnyAddressIsValid_ethereum', 'true/false as expected');
  });
}
