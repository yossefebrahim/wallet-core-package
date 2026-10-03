// Result rows: the one thing every command in this package produces and the
// only thing `report` consumes.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.
//
// A results file is JSON Lines: one row per line, so two commands can append
// to the same file, a partial run is still readable, and a diff between two
// runs is a line diff. `report` accepts any number of files or a directory of
// them.

import 'dart:convert';
import 'dart:io';

/// The four outcomes a measurement may report.
///
/// `unmeasured` is not a failure and not a pass: it is a check whose input
/// does not exist on the machine that ran it. Such a row still carries the
/// exact command the evaluation will run when the input does exist — that is
/// the whole point of the status (repo constraint: never report `pass` for a
/// check that could not run).
enum CheckStatus {
  pass,
  fail,
  skip,
  unmeasured;

  static CheckStatus parse(String name) => CheckStatus.values.firstWhere(
    (s) => s.name == name,
    orElse: () => throw FormatException('unknown status: $name'),
  );

  /// Worst-of, used when several rows land in one table cell.
  /// fail > unmeasured > skip > pass.
  static CheckStatus worst(CheckStatus a, CheckStatus b) =>
      _severity[a]! >= _severity[b]! ? a : b;

  static const Map<CheckStatus, int> _severity = {
    CheckStatus.pass: 0,
    CheckStatus.skip: 1,
    CheckStatus.unmeasured: 2,
    CheckStatus.fail: 3,
  };
}

/// One measurement of one check against one target.
class ResultRow {
  ResultRow({
    required this.check,
    required this.target,
    required this.status,
    required this.command,
    Map<String, Object?> values = const {},
    this.notes = '',
  }) : values = Map<String, Object?>.unmodifiable(values);

  /// The measurement family: `size`, `symbols`, `alignment`,
  /// `libcxx-conflict`, `ios-archive`, `min-version`, `consumer-gen`, or one
  /// of the evaluation-owned checks the step catalogue declares.
  final String check;

  /// The column this row lands in. A flat string, so the schema has no second
  /// axis: an artifact slice (`ios/arm64`), an app target and configuration
  /// (`android-emulator-x86_64/release`), or a non-device target
  /// (`host/toolchain`, `consumer/pub`).
  final String target;

  final CheckStatus status;

  /// Measured facts. `values['summary']`, when present, is the short string
  /// the table cell shows; everything else is the detail behind it.
  final Map<String, Object?> values;

  /// The exact system command that produced the row — or, for an `unmeasured`
  /// row, the exact command that will produce it once the input exists.
  final String command;

  final String notes;

  String get summary {
    final s = values['summary'];
    if (s is String && s.isNotEmpty) return s;
    final keys = values.keys.toList()..sort();
    return keys.map((k) => '$k=${values[k]}').join(' ');
  }

  Map<String, Object?> toJson() => {
    'check': check,
    'target': target,
    'status': status.name,
    'values': values,
    'command': command,
    'notes': notes,
  };

  static ResultRow fromJson(Map<String, Object?> json) => ResultRow(
    check: json['check']! as String,
    target: json['target']! as String,
    status: CheckStatus.parse(json['status']! as String),
    values: (json['values'] as Map<String, Object?>?) ?? const {},
    command: (json['command'] as String?) ?? '',
    notes: (json['notes'] as String?) ?? '',
  );

  @override
  String toString() => '$check/$target ${status.name}: $summary';
}

/// Reading and writing JSON Lines results files.
class ResultsFile {
  ResultsFile._();

  static String encode(Iterable<ResultRow> rows) =>
      rows.map((r) => jsonEncode(r.toJson())).join('\n');

  static List<ResultRow> decode(String contents) {
    final rows = <ResultRow>[];
    var lineNumber = 0;
    for (final line in const LineSplitter().convert(contents)) {
      lineNumber++;
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final Object? decoded;
      try {
        decoded = jsonDecode(trimmed);
      } on FormatException catch (e) {
        throw FormatException('line $lineNumber is not JSON: ${e.message}');
      }
      if (decoded is! Map<String, Object?>) {
        throw FormatException('line $lineNumber is not a JSON object');
      }
      rows.add(ResultRow.fromJson(decoded));
    }
    return rows;
  }

  /// Appends [rows] to [file], creating it and its parent directory.
  static void append(File file, Iterable<ResultRow> rows) {
    if (rows.isEmpty) return;
    file.parent.createSync(recursive: true);
    final existing = file.existsSync() ? file.readAsStringSync() : '';
    final needsNewline = existing.isNotEmpty && !existing.endsWith('\n');
    file.writeAsStringSync(
      '${needsNewline ? '\n' : ''}${encode(rows)}\n',
      mode: FileMode.append,
    );
  }

  static void write(File file, Iterable<ResultRow> rows) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('${encode(rows)}\n');
  }

  static List<ResultRow> read(File file) => decode(file.readAsStringSync());

  /// Reads every `.jsonl` under [paths]; a path may be a file or a directory.
  /// Directory entries are read in sorted order so the output is deterministic.
  static List<ResultRow> readAll(Iterable<String> paths) {
    final rows = <ResultRow>[];
    for (final path in paths) {
      final directory = Directory(path);
      if (directory.existsSync()) {
        final files =
            directory
                .listSync()
                .whereType<File>()
                .where((f) => f.path.endsWith('.jsonl'))
                .toList()
              ..sort((a, b) => a.path.compareTo(b.path));
        for (final file in files) {
          rows.addAll(read(file));
        }
        continue;
      }
      final file = File(path);
      if (!file.existsSync()) {
        throw FileSystemException('no such results file or directory', path);
      }
      rows.addAll(read(file));
    }
    return rows;
  }
}
