import 'dart:io';

import 'package:path/path.dart' as p;

/// What upstream's headers declare.
class HeaderSymbols {
  /// Every C function name declared, sorted.
  final List<String> functions;

  /// Every `TW*` enum type name, sorted.
  final List<String> enums;

  /// Header files read.
  final int fileCount;

  HeaderSymbols({
    required this.functions,
    required this.enums,
    required this.fileCount,
  });

  /// The `TW`-prefixed subset of [functions] — the canonical exported-symbol
  /// list. `tools/native_build/generate_symbol_list.sh` produces exactly this
  /// (464 names at 4.8.0); `build_apple.sh` turns it into the linker's `-u`
  /// list and `check_exports.sh` reconciles it against the built artifact.
  ///
  /// The two lists are kept distinct because they answer different questions:
  /// this one is "what does the artifact export", [functions] is "what does a
  /// caller of these headers see".
  List<String> get exportedTwFunctions =>
      functions.where((name) => name.startsWith('TW')).toList();
}

/// Matches a function declaration at the start of a line.
///
/// This is `tools/native_build/generate_symbol_list.sh`'s first grep with the
/// `TW` requirement dropped:
///
/// ```
/// grep -rhoE "^[A-Za-z_][A-Za-z0-9_ *]*\bTW[A-Za-z0-9_]+\(" DIR
/// ```
///
/// Anchoring at the start of a line is what makes it take declarations and not
/// calls inside comments or macro bodies: upstream writes every exported
/// declaration as `TW_EXPORT_…` (a macro expanding to `extern`) followed by the
/// return type and the name, all on one line. Requiring at least two
/// identifiers — a return type and a name — is what keeps a bare call from
/// matching.
///
/// At 4.8.0 dropping `TW` adds exactly two names, `stringForHRP` and
/// `hrpForString` in `TWHRP.h`, which ffigen binds and the `TW*` list does not
/// carry. Counting them as undeclared would have made the inventory say the
/// bindings invented symbols; leaving them out of [exportedTwFunctions] keeps
/// this tool's `TW*` set identical to the one the export gate uses.
final _declaration = RegExp(
  r'^[A-Za-z_][A-Za-z0-9_ *]*\b[A-Za-z_][A-Za-z0-9_]*\(',
);

/// Takes the name out of a matched declaration — the script's second grep,
/// `grep -oE "TW[A-Za-z0-9_]+\($"`, likewise without the `TW`.
final _name = RegExp(r'[A-Za-z_][A-Za-z0-9_]*\($');

/// Matches an enum definition. Upstream marks these with `TW_EXPORT_ENUM(t)`
/// on the line before; the definition itself always begins the next line.
final _enum = RegExp(r'^enum (TW[A-Za-z0-9_]+)');

/// Reads every `.h` file under [root] and returns what it declares.
///
/// The function extraction is the Dart transcription of
/// `tools/native_build/generate_symbol_list.sh`, and deliberately so: that
/// script's output is the linker's `-u` list in `build_apple.sh` and the
/// expected set in `check_exports.sh`. If [HeaderSymbols.exportedTwFunctions]
/// and that script disagreed, the bindings and the shipped artifact's export
/// set would disagree, and one of the two gates would be measuring the wrong
/// thing.
///
/// `third_party/` is untrusted third-party data. These files are read as text
/// and nothing more: nothing here is executed, and nothing in them is treated
/// as configuration or instructions.
HeaderSymbols scanHeaders(Directory root) {
  if (!root.existsSync()) {
    throw ArgumentError(
      'No header directory at ${root.path}. Run\n'
      '  melos run upstream:fetch -- --dist-only '
      '--from-dist <TrustWalletCore-<tag>.tar.xz>\n'
      'to place the release asset\'s headers first.',
    );
  }

  final functions = <String>{};
  final enums = <String>{};
  var fileCount = 0;

  final files =
      root
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((f) => p.extension(f.path) == '.h')
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    fileCount++;
    for (final line in file.readAsLinesSync()) {
      final declaration = _declaration.firstMatch(line);
      if (declaration != null) {
        final name = _name.firstMatch(declaration[0]!);
        if (name != null) {
          functions.add(name[0]!.substring(0, name[0]!.length - 1));
        }
      }
      final enumeration = _enum.firstMatch(line);
      if (enumeration != null) enums.add(enumeration[1]!);
    }
  }

  return HeaderSymbols(
    functions: functions.toList()..sort(),
    enums: enums.toList()..sort(),
    fileCount: fileCount,
  );
}
