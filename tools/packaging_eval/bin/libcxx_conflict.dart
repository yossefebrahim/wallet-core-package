// PRD §12.2 step 9 — a second plugin that bundles libc++_shared.so.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.

import 'dart:io';

import 'package:wcf_tool_packaging_eval/cli.dart';
import 'package:wcf_tool_packaging_eval/measurements.dart';
import 'package:wcf_tool_packaging_eval/results.dart';

const _usage = r'''
Usage: dart run tools/packaging_eval/bin/libcxx_conflict.dart \
           --gradle-output FILE --target ID

Classifies an Android build log for how the packaging option resolved two
contributors that each bundle `lib/<abi>/libc++_shared.so`: a Gradle duplicate
failure, a `pickFirst` rule, a single copy, or a version conflict.

The other half of the check is the fixture plugin that creates the collision:

  tools/packaging_eval/fixtures/libcxx_plugin/

  1. tools/packaging_eval/fixtures/libcxx_plugin/tool/materialize_libcxx.sh
     copies $ANDROID_NDK's own libc++_shared.so into the plugin's
     android/src/main/jniLibs/<abi>/. The .so is never committed: it is 1 MB
     per ABI and it is the NDK's file.
  2. Add the fixture plugin and the SDK to the consumer app.
  3. flutter build apk --debug (and --release) 2>&1 | tee "$OUT/gradle.log"
  4. Feed the log back here.

Options:
  --gradle-output FILE  The build log to classify.
  --target ID           The column the row lands in.
  --build-command TEXT  The exact build command that produced the log, recorded
                        verbatim in the row.
  --out FILE            Append the JSON result rows to FILE.
  -h, --help            This text.

With no log this prints one `unmeasured` row carrying the command above. That
is the state today: there is no Android artifact anywhere — upstream publishes
none and none has been built (DECISION-9 §4) — so nothing can be built against.
''';

void main(List<String> arguments) {
  final args = Args.parse(arguments);
  if (args.flag('help')) {
    stdout.write(_usage);
    return;
  }

  final rows = <ResultRow>[
    ...measureLibcxxConflict(
      target: args.option('target') ?? 'android-emulator-x86_64/debug',
      gradleOutputPath: args.option('gradle-output'),
      buildCommand: args.option('build-command'),
    ),
  ];

  emit(rows, args.option('out'));
}
