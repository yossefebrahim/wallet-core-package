// What the DECISION-2 Option 1 evaluation proves inside a built app.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.
//
// Load the library from where the build hook bundled it, check its build
// identity against the evaluation manifest, resolve every symbol the generated
// bindings bind plus the identity symbol, and make one real call. Shared by
// the integration test and by lib/probe_main.dart (the entry point for a
// release run on a device, where integration tests do not run).

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart';
import 'package:wallet_core_flutter_native/wallet_core_flutter_native.dart';

/// The expected identity, injected at build time from eval/option1's
/// eval_manifest.json by run_eval.sh:
///
/// ```
/// --dart-define=WCF_EXPECTED_ARTIFACT_SET_ID=<identity.artifact_set_id>
/// --dart-define=WCF_EXPECTED_UPSTREAM_COMMIT=<identity.upstream_commit>
/// ```
///
/// Not the package's embedded expectation: that comes from the root
/// compat_manifest.json, which has no artifact set yet (TBD-T1.2), so no
/// library can match it.
const String expectedArtifactSetId = String.fromEnvironment(
  'WCF_EXPECTED_ARTIFACT_SET_ID',
);
const String expectedUpstreamCommit = String.fromEnvironment(
  'WCF_EXPECTED_UPSTREAM_COMMIT',
);

/// An address `TWAnyAddressIsValid` must accept for Ethereum (the EIP-55
/// checksummed example of the EIP-55 specification).
const String ethereumAddress = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';

/// What one run found.
final class ProbeResult {
  const ProbeResult({
    required this.identity,
    required this.symbolsResolved,
    required this.ethereumAddressValid,
    required this.ethereumGarbageValid,
  });

  final BuildIdentity identity;

  /// Number of names resolved: bound + exported `TW*` names (deduplicated) and
  /// `wcf_build_info`.
  final int symbolsResolved;

  final bool ethereumAddressValid;
  final bool ethereumGarbageValid;

  @override
  String toString() =>
      'identity ${identity.artifactSetId} @ ${identity.upstreamCommit}; '
      '$symbolsResolved symbols resolved; '
      'TWAnyAddressIsValid(eth) = $ethereumAddressValid, '
      'garbage = $ethereumGarbageValid';
}

/// Runs the probe. Throws whatever the loader or the identity check throws.
///
/// [locations] defaults to where an app built with the hook has the library
/// ([codeAssetLocations]); the host-side `flutter test` passes the file
/// Flutter's test runner mapped the asset id to.
ProbeResult runProbe({Iterable<LibraryLocation>? locations}) {
  if (expectedArtifactSetId.isEmpty || expectedUpstreamCommit.isEmpty) {
    throw StateError(
      'build with --dart-define=WCF_EXPECTED_ARTIFACT_SET_ID=… and '
      '--dart-define=WCF_EXPECTED_UPSTREAM_COMMIT=… (run_eval.sh does)',
    );
  }

  final library = WalletCoreNative.load(
    locations:
        locations ?? codeAssetLocations(platform: NativePlatform.current),
  );

  final identity = verifyIdentity(
    library,
    expected: const ManifestIdentity(
      artifactSetId: expectedArtifactSetId,
      upstreamCommit: expectedUpstreamCommit,
    ),
  );

  final names = <String>{
    ...boundFunctionNames,
    ...exportedTwFunctionNames,
    'wcf_build_info',
  };
  WalletCoreNative.requireSymbols(library, names);

  final bindings = WalletCoreBindings(library);
  return ProbeResult(
    identity: identity,
    symbolsResolved: names.length,
    ethereumAddressValid: _isValid(bindings, ethereumAddress),
    ethereumGarbageValid: _isValid(bindings, '0xnot-an-address'),
  );
}

bool _isValid(WalletCoreBindings bindings, String address) {
  final utf8 = address.toNativeUtf8();
  Pointer<TWString> string = nullptr;
  try {
    string = bindings.TWStringCreateWithUTF8Bytes(utf8.cast<Char>());
    return bindings.TWAnyAddressIsValid(string, TWCoinType.TWCoinTypeEthereum);
  } finally {
    if (string != nullptr) bindings.TWStringDelete(string);
    malloc.free(utf8);
  }
}
