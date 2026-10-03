// The one Markdown table both DECISION-2 option documents embed.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.

import 'dart:io';

import 'package:wcf_tool_packaging_eval/cli.dart';
import 'package:wcf_tool_packaging_eval/report.dart';
import 'package:wcf_tool_packaging_eval/results.dart';

const _usage = '''
Usage: dart run tools/packaging_eval/bin/report.dart RESULTS... [--out FILE]

Renders the measurement table. Rows are the eleven PRD §12.2 steps, columns are
the targets, cells are pass/fail/skip/unmeasured with the measured value and a
footnote pointing at the exact command that produced it. A step nobody has run
shows as `unmeasured` with the command that will run it — never as a gap and
never as a pass.

RESULTS is any number of JSON Lines results files, or directories of them.

Options:
  --results PATH   A results file or directory. Repeatable; positional
                   arguments work too.
  --out FILE       Write the Markdown there as well as to stdout.
  --title TEXT     Override the table title.
  -h, --help       This text.

Deterministic: the same rows render the same bytes.
''';

void main(List<String> arguments) {
  final positional = arguments.where((a) => !a.startsWith('-')).toList();
  final flags = <String>[];
  for (var i = 0; i < arguments.length; i++) {
    if (!arguments[i].startsWith('-')) continue;
    flags.add(arguments[i]);
    if (arguments[i] != '-h' &&
        arguments[i] != '--help' &&
        !arguments[i].contains('=') &&
        i + 1 < arguments.length) {
      flags.add(arguments[++i]);
    }
  }
  final args = Args.parse(flags);
  if (args.flag('help')) {
    stdout.write(_usage);
    return;
  }

  final paths = [...args.options('results'), ...positional];
  if (paths.isEmpty) {
    stdout.write(_usage);
    stderr.writeln('error: give at least one results file or directory');
    exit(2);
  }

  final rows = ResultsFile.readAll(paths);
  final markdown = renderReport(
    rows,
    title:
        args.option('title') ??
        'PRD §12.2 packaging evaluation — measurement table',
  );
  stdout.write(markdown);

  final out = args.option('out');
  if (out != null) {
    File(out)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(markdown);
    stderr.writeln('table written to $out');
  }
}
