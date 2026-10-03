import 'dart:io';

import 'package:wcf_tool_upstream/fetch.dart';

Future<void> main(List<String> args) async {
  final FetchOptions options;
  try {
    options = FetchOptions.parse(args);
  } on UsageError catch (e) {
    stderr.writeln(e.message);
    exit(e.message == FetchOptions.usage ? 0 : 2);
  }

  try {
    await runFetch(options);
  } on UsageError catch (e) {
    stderr.writeln('error: ${e.message}');
    exit(2);
  } on Exception catch (e) {
    stderr.writeln('error: $e');
    exit(1);
  }
}
