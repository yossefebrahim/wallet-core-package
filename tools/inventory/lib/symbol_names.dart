/// Renders `lib/src/generated/ffi/symbol_names.dart`: the bound symbol names
/// as Dart constants.
///
/// The inventory answers "does the binding set cover the header set" and is
/// JSON, read by people and by CI. This file answers a different question at
/// run time — "which symbols must the loaded library resolve" — and so it is
/// Dart: the native loader's health check (T1.7's `symbolLookupAll`, wired up
/// by T1.11) needs the list in a released app, where reading a JSON asset would
/// mean bundling one and doing I/O to learn something that was fixed when the
/// bindings were generated.
///
/// Both files come from the same scan of the same generated bindings in the
/// same run, so the two cannot drift apart.
library;

/// The `TW` prefix that marks upstream's exported C API.
const String _twPrefix = 'TW';

/// The header every generated file in this repository carries: what regenerates
/// it, why hand edits do not survive, what it is, and the project disclaimer.
const String _header = '''
// GENERATED FILE — DO NOT EDIT.
//
// Regenerate with `melos run gen:ffi`. Edits here are erased by the next
// run and are caught by `melos run gen:check` (AGENTS.md rule 1).
//
// The names of the native functions the generated bindings bind, as Dart
// constants. They are the symbol list the native package's loader resolves
// against a loaded library to prove it is the right one and is complete
// (PRD §9, §16 S2) — a run-time question, which is why it is answered by a
// compiled-in constant and not by reading `inventory.json`. That file, beside
// this one, is the same fact with its provenance and is produced by the same
// run of `tools/inventory/bin/symbols.dart`.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core
// library. Not affiliated with or endorsed by Trust Wallet.
''';

/// The `symbol_names.dart` source for [boundFunctions].
///
/// [boundFunctions] is every native function the generated bindings look up —
/// the same set `inventory.json` marks `in_generated`. It is sorted and
/// deduplicated here, so the output is a function of the set alone and never of
/// the order it was scanned in.
///
/// The `TW`-prefixed subset is written out as well. That is the list the
/// artifact export gate uses (`tools/native_build/check_exports.sh`, 464 names
/// at 4.8.0); the two names outside it, `hrpForString` and `stringForHRP`, are
/// bound and exported but carry no `TW` prefix.
String renderSymbolNames(Iterable<String> boundFunctions) {
  final bound = boundFunctions.toSet().toList()..sort();
  final exported = bound.where((n) => n.startsWith(_twPrefix)).toList();

  final buffer = StringBuffer(_header);
  _writeList(buffer, 'boundFunctionNames', bound, <String>[
    'Every native function name the generated bindings bind.',
    '',
    'Sorted, ${bound.length} names: the set `inventory.json` marks',
    '`in_generated`, and the set a loaded library has to resolve in full for',
    'the bindings to work at all.',
    '',
    "The loader's own build-info symbol is not here: it is a symbol of the",
    'artifact, not one the bindings bind, and the loader adds it itself.',
  ]);
  _writeList(buffer, 'exportedTwFunctionNames', exported, <String>[
    "The `TW`-prefixed subset of [boundFunctionNames]: upstream's exported",
    'C API.',
    '',
    'Sorted, ${exported.length} names — the list the artifact export gate',
    'reconciles against a built library',
    '(`tools/native_build/check_exports.sh`). The names [boundFunctionNames]',
    'has beyond these are bound and exported too, but carry no `TW` prefix.',
  ]);

  return buffer.toString();
}

/// Writes one documented `const List<String>` declaration, one name per line.
///
/// The layout is what `dart format` produces for a list this long, because
/// `melos run gen:ffi` formats the generated directory after this file is
/// written and `--check` compares what a run *would* write against what is on
/// disk. If the two disagreed, the file would be permanently stale.
void _writeList(
  StringBuffer buffer,
  String name,
  List<String> names,
  List<String> doc,
) {
  buffer.writeln();
  for (final line in doc) {
    buffer.writeln(line.isEmpty ? '///' : '/// $line');
  }
  buffer.writeln('const List<String> $name = <String>[');
  for (final symbol in names) {
    buffer.writeln("  '$symbol',");
  }
  buffer.writeln('];');
}
