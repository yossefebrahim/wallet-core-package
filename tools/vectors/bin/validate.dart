import 'dart:io';
import 'package:wcf_tool_vectors/inventory.dart';
import 'package:wcf_tool_vectors/validator.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    print('Usage: dart run tools/vectors/bin/validate.dart [test_vectors dir]');
    exit(1);
  }

  final dir = Directory(args[0]);
  final inventory = Inventory.load(dir);

  final errors = validateInventory(inventory);

  if (errors.isNotEmpty) {
    for (final error in errors) {
      print(error);
    }
    exit(1);
  }

  print('Files: ${inventory.filesCount}');
  print('Vectors: ${inventory.vectors.length}');
  print('Exclusions: ${inventory.exclusions.length}');
  exit(0);
}
