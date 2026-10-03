/// The keyed-input layout probes (`../keyed_layout_probes.dart`) against
/// Approach B's one layout-deciding place, the body of `wcf_sign_ethereum`,
/// on the shim library — the same probes `../keyed_layout_native_test.dart`
/// runs against Approach A. Includes REVIEW B finding 1's truncated-input
/// probe as a regression test: the key never appears in the output.
///
/// Skips when the shim library is absent (see `shim_library.dart`);
/// `WCF_NATIVE_SHIM_REQUIRED=1` turns that into a failure.
@Tags(['native', 'shim'])
library;

import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/advanced.dart' show WalletCoreBindings;

import '../keyed_layout_probes.dart';
import 'shim_library.dart';

void main() {
  group(
    'Approach B — wcf_sign_ethereum — on the shim library',
    skip: shimLibrarySkipReason(),
    () {
      late DynamicLibrary library;
      setUpAll(() => library = openShimLibrary());
      layoutProbes(() => WalletCoreBindings(library), () => injectB(library));
    },
  );
}
