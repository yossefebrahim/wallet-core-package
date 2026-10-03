// Host-side proof, on macOS, that the library the build hook bundled for
// `flutter test` is the pinned one and works: Flutter's test runner runs the
// hook for the host, copies the emitted file under build/native_assets/macos/
// and records, in native_assets.json, which file the asset id maps to. This
// test opens that file and runs the same probe the integration test runs in a
// built app.
//
//   flutter test test/bundled_library_test.dart \
//       --dart-define=WCF_EXPECTED_ARTIFACT_SET_ID=as_4.8.0_000 \
//       --dart-define=WCF_EXPECTED_UPSTREAM_COMMIT=d692ac27749d0c615e17c751b70ab4f0aa75c59b
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter_native/wallet_core_flutter_native.dart';
import 'package:wcf_eval_option1/wallet_core_probe.dart';

const String assetId = 'package:wallet_core_flutter_native/wallet_core';

/// The path native_assets.json maps [assetId] to, for the host target.
String? mappedPath() {
  final file = File('build/native_assets/macos/native_assets.json');
  if (!file.existsSync()) return null;
  final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final assets = json['native-assets'] as Map<String, Object?>? ?? const {};
  for (final perTarget in assets.values) {
    final entry = (perTarget as Map<String, Object?>)[assetId];
    if (entry is List && entry.length == 2 && entry.first == 'absolute') {
      return entry.last as String;
    }
  }
  return null;
}

void main() {
  test(
    'the asset id maps to the pinned library, which loads and works',
    () {
      final path = mappedPath();
      expect(path, isNotNull, reason: '$assetId is not in native_assets.json');
      final result = runProbe(locations: [LibraryFile(path!)]);
      // ignore: avoid_print
      print('WCF_PROBE PASS $result (host file $path)');
      expect(result.identity.artifactSetId, expectedArtifactSetId);
      expect(result.ethereumAddressValid, isTrue);
      expect(result.ethereumGarbageValid, isFalse);
    },
    skip: Platform.isMacOS
        ? false
        : 'the eval manifest ships a macOS library only',
  );
}
