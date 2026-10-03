/// The keyed-input layout probes (`keyed_layout_probes.dart`) against
/// Approach A's one layout-deciding place, `keyedInputParts`, on the standard
/// host library. Approach B's run of the same probes is
/// `adapter/keyed_layout_shim_test.dart`.
///
/// Skips when the library is absent; `WCF_NATIVE_REQUIRED=1` turns that into
/// a failure (see `../support/host_library.dart`).
@Tags(['native'])
library;

import 'package:flutter_test/flutter_test.dart';

import '../support/host_library.dart';
import 'keyed_layout_probes.dart';

void main() {
  group(
    'Approach A — keyedInputParts — on the standard library',
    skip: hostLibrarySkipReason(),
    () => layoutProbes(openHostBindings, () => injectA),
  );
}
