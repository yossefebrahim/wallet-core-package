// DECISION-2 Option 2 evaluation (T1.9b): the release-mode half of PRD §12.2
// steps 2–4. `flutter test` has no release mode and Flutter Driver refuses
// one ("Flutter Driver (non-web) does not support running in release mode",
// Flutter 3.47.5), so a release build runs this entry point instead and
// eval/option2/run_eval.sh reads its one line from the device log:
//
//   flutter build apk --release -t lib/probe_main.dart \
//       --dart-define=WCF_EXPECT_ARTIFACT_SET_ID=<id> \
//       --dart-define=WCF_EXPECT_UPSTREAM_COMMIT=<sha>
//   adb install -r …/app-release.apk && adb shell am start -W -n <id>/.MainActivity
//   adb logcat -d -s flutter:I        # look for `WCF_PROBE PASS`
//
// The checks are integration_test/symbol_lookup_test.dart's: which default
// location provides the library, the identity against the manifest the build
// verified against, every bound and exported name plus wcf_build_info, and one
// real upstream call.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.

import 'package:flutter/material.dart';
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

String _probe() {
  if (_expectedSetId.isEmpty || _expectedCommit.isEmpty) {
    throw StateError(
      'pass --dart-define=WCF_EXPECT_ARTIFACT_SET_ID and '
      'WCF_EXPECT_UPSTREAM_COMMIT from the manifest the build used',
    );
  }
  String? resolvedBy;
  for (final location in defaultLocations(platform: NativePlatform.current)) {
    try {
      if (location.open().providesSymbol('wcf_build_info')) {
        resolvedBy = location.description;
        break;
      }
    } on Object {
      continue;
    }
  }
  if (resolvedBy == null) {
    throw StateError('no default location provided wcf_build_info');
  }

  final library = WalletCoreNative.load();
  final identity = verifyIdentity(
    library,
    expected: const ManifestIdentity(
      artifactSetId: _expectedSetId,
      upstreamCommit: _expectedCommit,
    ),
  );
  final names = <String>{
    ...boundFunctionNames,
    ...exportedTwFunctionNames,
    'wcf_build_info',
  };
  WalletCoreNative.requireSymbols(library, names);

  final context = NativeContext(WalletCoreBindings(library));
  bool isValid(String address) => withTWString(
    context,
    address,
    (s) => context.bindings.TWAnyAddressIsValid(
      s.pointer,
      TWCoinType.TWCoinTypeEthereum,
    ),
  );
  final valid = isValid(_ethereumAddress);
  final truncated = isValid(_ethereumAddress.substring(0, 41));
  if (!valid || truncated) {
    throw StateError(
      'TWAnyAddressIsValid: EIP-55 address $valid, truncated $truncated',
    );
  }
  return 'identity=${identity.artifactSetId}@${identity.upstreamCommit} '
      'symbols=${names.length}/${names.length} '
      'resolved_by=$resolvedBy TWAnyAddressIsValid=true/false';
}

void main() {
  String outcome;
  try {
    outcome = 'PASS ${_probe()}';
  } on Object catch (e) {
    outcome = 'FAIL ${e.toString().split('\n').first}';
  }
  // The device log line is the measurement: run_eval.sh greps it.
  // ignore: avoid_print
  print('WCF_PROBE $outcome');
  runApp(
    MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(outcome, key: const Key('wcf-probe-outcome')),
          ),
        ),
      ),
    ),
  );
}
