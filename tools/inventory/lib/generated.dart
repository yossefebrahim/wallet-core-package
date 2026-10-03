import 'dart:io';

/// What the generated Dart actually binds.
class GeneratedSymbols {
  /// Native symbols looked up as functions, sorted.
  final List<String> functions;

  /// Native symbols looked up as something other than a function — a global,
  /// say. Reported separately because a symbol bound as data is not a bound
  /// function, and counting it as one would make the inventory lie.
  final List<String> nonFunctionLookups;

  /// Dart enums the file declares, sorted.
  final List<String> enums;

  GeneratedSymbols({
    required this.functions,
    required this.nonFunctionLookups,
    required this.enums,
  });
}

const _lookupCall = '_lookup<';

/// A top-level Dart enum declaration, which is how ffigen emits a C enum.
final _enum = RegExp(r'^enum ([A-Za-z_$][A-Za-z0-9_$]*)\s*\{', multiLine: true);

/// Reads the ffigen output and returns the symbols it binds.
///
/// Every native symbol the bindings reach reaches it through exactly one
/// `_lookup<T>('name')` call, so that call is what this counts — not the Dart
/// method names, which are a rename away from the symbol they call. The type
/// argument spans several lines after `dart format`, so it is found by
/// matching angle brackets rather than by a line regex.
GeneratedSymbols scanGenerated(File file) {
  if (!file.existsSync()) {
    throw ArgumentError(
      'No generated bindings at ${file.path}. Run `melos run gen:ffi` first.',
    );
  }
  final source = file.readAsStringSync();

  final functions = <String>{};
  final others = <String>{};

  var index = source.indexOf(_lookupCall);
  while (index >= 0) {
    final typeStart = index + _lookupCall.length;
    final typeEnd = _matchingAngle(source, typeStart - 1, file.path);
    final type = source.substring(typeStart, typeEnd);
    final name = _symbolAfter(source, typeEnd + 1, file.path);
    if (type.contains('NativeFunction')) {
      functions.add(name);
    } else {
      others.add(name);
    }
    index = source.indexOf(_lookupCall, typeEnd);
  }

  return GeneratedSymbols(
    functions: functions.toList()..sort(),
    nonFunctionLookups: others.toList()..sort(),
    enums: _enum.allMatches(source).map((m) => m[1]!).toSet().toList()..sort(),
  );
}

/// Index of the `>` that closes the `<` at [open].
int _matchingAngle(String source, int open, String path) {
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    final char = source[i];
    if (char == '<') {
      depth++;
    } else if (char == '>') {
      depth--;
      if (depth == 0) return i;
    }
  }
  throw FormatException(
    '$path: unterminated type argument after "$_lookupCall"',
  );
}

/// The `'name'` of a `('name')` argument list starting at or after [from].
String _symbolAfter(String source, int from, String path) {
  final match = RegExp(
    r"^\s*\(\s*'([A-Za-z0-9_]+)'\s*,?\s*\)",
  ).firstMatch(source.substring(from, (from + 200).clamp(0, source.length)));
  if (match == null) {
    throw FormatException(
      '$path: expected a symbol-name argument after a "$_lookupCall…>" call.',
    );
  }
  return match[1]!;
}
