import 'dart:convert';

import 'package:wcf_tool_upstream/dist.dart';

import 'generated.dart';
import 'headers.dart';

/// One row of the inventory: a name, what kind of thing it is, and whether
/// each side has it.
class SymbolRow {
  final String name;

  /// `function` or `enum`.
  final String kind;
  final bool inHeaders;
  final bool inGenerated;

  SymbolRow({
    required this.name,
    required this.kind,
    required this.inHeaders,
    required this.inGenerated,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'in_headers': inHeaders,
    'in_generated': inGenerated,
  };
}

/// The generated symbol inventory (PRD §9, last bullet).
///
/// Two questions, answered from one file: what produced these bindings, and
/// does the binding set cover the header set.
class Inventory {
  /// Provenance of the ffigen input — the release asset's header set.
  final DistHeaders headers;

  /// Path of the generated bindings, relative to the bindings package.
  final String generatedPath;

  /// Every name either side declares, sorted, functions and enums together.
  final List<SymbolRow> symbols;

  /// How many of the declared functions carry the `TW` prefix — the count the
  /// artifact export gate uses (464 at 4.8.0).
  final int exportedTwFunctionCount;

  Inventory({
    required this.headers,
    required this.generatedPath,
    required this.symbols,
    required this.exportedTwFunctionCount,
  });

  /// Names the headers declare that the bindings do not bind. Non-empty is a
  /// build failure: PRD §9 requires bindings for every declared function and
  /// enum.
  List<String> get missing => symbols
      .where((s) => s.inHeaders && !s.inGenerated)
      .map((s) => s.name)
      .toList();

  /// Names the bindings bind that the headers do not declare. Non-empty means
  /// the two inputs have drifted apart; it is reported, not tolerated
  /// silently.
  List<String> get extra => symbols
      .where((s) => !s.inHeaders && s.inGenerated)
      .map((s) => s.name)
      .toList();

  int _count(String kind, bool Function(SymbolRow) predicate) =>
      symbols.where((s) => s.kind == kind && predicate(s)).length;

  Map<String, Object?> toJson() => <String, Object?>{
    'generated_by': 'melos run gen:ffi (tools/inventory/bin/symbols.dart)',
    'headers': headers.toJson(),
    'generated': <String, Object?>{'file': generatedPath},
    'counts': <String, Object?>{
      for (final kind in const ['function', 'enum'])
        '${kind}s': <String, Object?>{
          'in_headers': _count(kind, (s) => s.inHeaders),
          'in_generated': _count(kind, (s) => s.inGenerated),
          'missing': _count(kind, (s) => s.inHeaders && !s.inGenerated),
        },
      // The `TW*` subset, which is what the artifact export gate counts
      // (tools/native_build/check_exports.sh). Recorded so the two numbers can
      // be compared without re-deriving either.
      'exported_tw_functions': exportedTwFunctionCount,
    },
    'missing': missing,
    'extra': extra,
    'symbols': <String, Object?>{
      for (final symbol in symbols) symbol.name: symbol.toJson(),
    },
  };

  /// The bytes written to `inventory.json`: two-space indent and one trailing
  /// newline, matching `compat_manifest.json`, so that `git diff` over the
  /// generated paths is about content and never about formatting.
  String render() =>
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';
}

/// Builds the inventory by joining the two symbol sets on name.
///
/// Sorted by (kind, name) so the output is a function of the inputs alone.
Inventory buildInventory({
  required DistHeaders headers,
  required HeaderSymbols declared,
  required GeneratedSymbols bound,
  required String generatedPath,
}) {
  final rows = <SymbolRow>[];

  void add(String kind, Set<String> inHeaders, Set<String> inGenerated) {
    final names = <String>{...inHeaders, ...inGenerated}.toList()..sort();
    for (final name in names) {
      rows.add(
        SymbolRow(
          name: name,
          kind: kind,
          inHeaders: inHeaders.contains(name),
          inGenerated: inGenerated.contains(name),
        ),
      );
    }
  }

  add('enum', declared.enums.toSet(), bound.enums.toSet());
  add('function', declared.functions.toSet(), bound.functions.toSet());

  return Inventory(
    headers: headers,
    generatedPath: generatedPath,
    symbols: rows,
    exportedTwFunctionCount: declared.exportedTwFunctions.length,
  );
}
