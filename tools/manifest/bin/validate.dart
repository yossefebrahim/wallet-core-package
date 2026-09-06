import 'dart:convert';
import 'dart:io';
import 'package:wcf_tool_manifest/validator.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run validate.dart [path] [--strict]');
    exit(1);
  }

  bool strict = false;
  String path = '';

  for (final arg in args) {
    if (arg == '--strict') {
      strict = true;
    } else {
      path = arg;
    }
  }

  if (path.isEmpty) {
    stderr.writeln('Missing path argument');
    exit(1);
  }

  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('File not found: $path');
    exit(1);
  }

  final jsonStr = file.readAsStringSync();
  final dynamic decoded;
  try {
    decoded = jsonDecode(jsonStr);
  } catch (e) {
    stderr.writeln('Invalid JSON format: $e');
    exit(1);
  }

  if (decoded is! Map<String, dynamic>) {
    stderr.writeln('Manifest must be a JSON object at the root');
    exit(1);
  }

  final errors = validateManifest(decoded, strict: strict);
  if (errors.isNotEmpty) {
    for (final error in errors) {
      stderr.writeln(error);
    }
    exit(1);
  } else {
    print('Manifest is valid.');
    exit(0);
  }
}
