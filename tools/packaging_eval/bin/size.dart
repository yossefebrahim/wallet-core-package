// PRD §12.2 step 5 — size per ABI/slice, and app-size delta.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.

import 'dart:io';

import 'package:wcf_tool_packaging_eval/cli.dart';
import 'package:wcf_tool_packaging_eval/measurements.dart';
import 'package:wcf_tool_packaging_eval/results.dart';

const _usage = '''
Usage: dart run tools/packaging_eval/bin/size.dart --artifact FILE --target ID
       dart run tools/packaging_eval/bin/size.dart --baseline-app PATH \\
           --sdk-app PATH --target ID

Records the size of a shipped library, the thin-slice sizes of a universal
Mach-O, and — given two app bundles — the app-size delta the SDK costs.

Options:
  --artifact FILE      A library to size. Repeatable.
  --baseline-app PATH  An app bundle, .apk, .aab or .ipa built without the SDK.
  --sdk-app PATH       The same app built with it.
  --target ID          The column the row lands in, e.g. `ios/arm64` or
                       `android-emulator-x86_64/release`. Repeat once per
                       --artifact, or give one for all of them.
  --out FILE           Append the JSON result rows to FILE (JSON Lines).
  -h, --help           This text.

The exact commands behind it:
  wc -c <artifact>
  lipo -detailed_info <artifact>     (thin-slice sizes of a universal Mach-O)
  lipo -info <artifact>
  shasum -a 256 <artifact>           (cross-check against the DECISION-14 §5.1
                                      record next to the artifact)
''';

void main(List<String> arguments) {
  final args = Args.parse(arguments);
  if (args.flag('help')) {
    stdout.write(_usage);
    return;
  }

  final artifacts = args.options('artifact');
  final targets = args.options('target');
  final baseline = args.option('baseline-app');
  final sdkApp = args.option('sdk-app');
  final rows = <ResultRow>[];

  if (artifacts.isEmpty && baseline == null && sdkApp == null) {
    stdout.write(_usage);
    stderr.writeln('error: give --artifact, or --baseline-app and --sdk-app');
    exit(2);
  }

  for (var i = 0; i < artifacts.length; i++) {
    final target = targets.length == artifacts.length
        ? targets[i]
        : (targets.isEmpty ? artifacts[i] : targets.first);
    rows.addAll(measureSize(artifact: artifacts[i], target: target));
  }

  if (baseline != null || sdkApp != null) {
    rows.addAll(
      measureAppSizeDelta(
        baselineApp: baseline ?? '<baseline app>',
        sdkApp: sdkApp ?? '<app with the SDK>',
        target: targets.isEmpty
            ? 'android-emulator-x86_64/release'
            : targets.last,
      ),
    );
  }

  emit(rows, args.option('out'));
}
