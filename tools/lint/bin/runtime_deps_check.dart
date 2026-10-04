import 'dart:io';

import 'package:wcf_tool_lint/runtime_deps_check.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--help')) {
    stdout.writeln('Usage: dart run tools/lint/bin/runtime_deps_check.dart');
    stdout.writeln(
      'Checks transitive runtime dependency closure for network packages.',
    );
    exitCode = exitClean;
    return;
  }
  exitCode = await runRuntimeDepsCheck(args);
}
