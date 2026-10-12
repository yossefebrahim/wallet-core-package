import 'dart:io';

final RegExp _messageClass = RegExp(
  r'^class (\w+) extends \$pb\.GeneratedMessage\b',
  multiLine: true,
);

/// Proto file stem (`Bitcoin`) → the message classes the generated Dart
/// defines for it (`SigningInput`, `TransactionPlan`, …), read from the
/// `<Stem>.pb.dart` files under [protoDir]. The classes are protoc's rendering
/// of the descriptors, so a message upstream defines is a class here.
Map<String, Set<String>> readProtoMessages(Directory protoDir) {
  if (!protoDir.existsSync()) {
    throw FormatException(
      'generated proto tree missing: ${protoDir.path}; run `melos run gen:proto`',
    );
  }
  final byFile = <String, Set<String>>{};
  final files = protoDir.listSync().whereType<File>().where(
    (f) => f.path.endsWith('.pb.dart'),
  );
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final stem = name.substring(0, name.length - '.pb.dart'.length);
    byFile[stem] = {
      for (final m in _messageClass.allMatches(file.readAsStringSync()))
        m.group(1)!,
    };
  }
  if (byFile.isEmpty) {
    throw FormatException('no *.pb.dart files in ${protoDir.path}');
  }
  return byFile;
}
