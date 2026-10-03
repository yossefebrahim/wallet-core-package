// DECISION-2 Option 2 evaluation (T1.9): the host side of a release-mode run.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.
//
// `flutter test` has no --release option, so eval/option2/run_eval.sh runs
// integration_test/symbol_lookup_test.dart in release through
//
//   flutter drive --driver=test_driver/integration_test.dart \
//       --target=integration_test/symbol_lookup_test.dart -d <id> --release
//
// This is the integration_test package's standard driver, unchanged.

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
