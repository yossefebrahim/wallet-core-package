// PRD §12.2 step 6 — the minimum Flutter/Dart version the option needs.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.

import 'dart:io';

import 'package:wcf_tool_packaging_eval/cli.dart';
import 'package:wcf_tool_packaging_eval/measurements.dart';
import 'package:wcf_tool_packaging_eval/results.dart';

const _usage = '''
Usage: dart run tools/packaging_eval/bin/min_version.dart [--target ID]

Records the evidence step 6 is answered from:

  flutter --version --machine
  the `environment:` constraints of the three packages' pubspecs

What it does *not* do is answer the step. "The minimum Flutter this packaging
option needs" is a statement the evaluation makes from a successful build on
the oldest Flutter it tried, and PRD §12.2 step 6 says the SDK's `environment`
constraints are then set from that measurement rather than from assumption.
This command gives the row its shape and its evidence; `report` carries the
`min-version-floor` row as `unmeasured` with the command that fills it.

Options:
  --target ID      The column the row lands in. Default `host/toolchain`.
  --package DIR    A package whose constraints to record. Repeatable; defaults
                   to the three workspace packages.
  --out FILE       Append the JSON result rows to FILE.
  -h, --help       This text.
''';

void main(List<String> arguments) {
  final args = Args.parse(arguments);
  if (args.flag('help')) {
    stdout.write(_usage);
    return;
  }

  final packages = args.options('package');
  final rows = <ResultRow>[
    ...measureMinVersion(
      target: args.option('target') ?? 'host/toolchain',
      packagePaths: packages.isEmpty ? null : packages,
    ),
  ];

  emit(rows, args.option('out'));
}
