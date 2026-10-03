import 'dart:io';

import 'package:wcf_tool_lint/public_api_lint.dart';

Future<void> main(List<String> args) async {
  exitCode = await runPublicApiLint(args);
}
