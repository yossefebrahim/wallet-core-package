// A very small `--flag value` parser, so this package keeps no dependencies.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.

import 'dart:io';

import 'results.dart';

class Args {
  Args(this._values, this._flags);

  final Map<String, List<String>> _values;
  final Set<String> _flags;

  String? option(String name) => _values[name]?.last;

  List<String> options(String name) => _values[name] ?? const [];

  bool flag(String name) => _flags.contains(name);

  String require(String name, void Function() usage) {
    final value = option(name);
    if (value == null) {
      usage();
      stderr.writeln('error: --$name is required');
      exit(2);
    }
    return value;
  }

  /// `--flag value` for every option and bare `--flag` for every switch.
  /// `--help`/`-h` is always a switch. Unknown shapes fail loudly.
  static Args parse(List<String> arguments, {Set<String> switches = const {}}) {
    final values = <String, List<String>>{};
    final flags = <String>{};
    final all = {...switches, 'help'};
    for (var i = 0; i < arguments.length; i++) {
      final argument = arguments[i];
      if (argument == '-h') {
        flags.add('help');
        continue;
      }
      if (!argument.startsWith('--')) {
        stderr.writeln('error: unexpected argument `$argument`');
        exit(2);
      }
      var name = argument.substring(2);
      String? inline;
      final equals = name.indexOf('=');
      if (equals >= 0) {
        inline = name.substring(equals + 1);
        name = name.substring(0, equals);
      }
      if (all.contains(name) && inline == null) {
        flags.add(name);
        continue;
      }
      final value =
          inline ?? (i + 1 < arguments.length ? arguments[++i] : null);
      if (value == null) {
        stderr.writeln('error: --$name needs a value');
        exit(2);
      }
      values.putIfAbsent(name, () => []).add(value);
    }
    return Args(values, flags);
  }
}

/// Writes [rows] to `--out` when given, and always prints them to stdout so a
/// run is readable without a results file.
void emit(List<ResultRow> rows, String? outPath) {
  for (final row in rows) {
    stdout.writeln(
      '${row.status.name.padRight(10)} ${row.check} '
      '${row.target}: ${row.summary}',
    );
  }
  if (outPath != null) {
    ResultsFile.append(File(outPath), rows);
    stderr.writeln('${rows.length} row(s) appended to $outPath');
  }
}
