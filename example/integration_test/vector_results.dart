/// The one line a device test prints for each vector it has proven, which
/// `tools/matrix/bin/collect_results.dart` turns into
/// `test_vectors/results/<platform>.json` (schema in
/// `test_vectors/results/README.md`).
///
/// Call [recordVectorPass] only after every assertion for that vector has
/// passed. A test that fails before the call prints nothing, so the vector has
/// no entry and a `platforms_verified` claim for it fails `matrix:check`. The
/// line carries a vector id and a status, nothing else.
library;

import 'dart:convert';

/// Prefix of the line; the collector looks for exactly this token.
const String vectorResultMarker = 'WCF_VECTOR_RESULT';

/// Prints `WCF_VECTOR_RESULT {"id":"<vectorId>","status":"pass"}`.
void recordVectorPass(String vectorId) {
  // ignore: avoid_print
  print(
    '$vectorResultMarker ${jsonEncode({'id': vectorId, 'status': 'pass'})}',
  );
}
