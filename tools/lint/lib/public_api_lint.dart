import 'dart:collection';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:path/path.dart' as p;

/// Exit code: the public surface is clean.
const int exitClean = 0;

/// Exit code: at least one violation was found.
const int exitViolations = 1;

/// Exit code: an entry point could not be resolved, or analysis reported
/// errors in it or in anything it exports, so no verdict is possible.
const int exitUnresolved = 2;

/// Exit code: the command line was malformed.
const int exitUsage = 64;

/// The one top-level library of the SDK package that may expose bindings,
/// FFI and protobuf types (AGENTS.md rule 4); never checked by default.
const String advancedLibrary = 'advanced.dart';

/// A type the default public surface must never expose, found in one place.
///
/// Rule ids:
/// - `ffi`: a type from `dart:ffi` or `package:ffi/…` in a public signature.
/// - `generated`: a type from a library whose URI contains `/src/generated/`
///   (generated `CoinType`, `TW*` bindings, generated protobuf classes).
/// - `protobuf`: a type from `package:protobuf/…` or `package:fixnum/…`.
/// - `pointer-field`: a type on the surface stores, in an instance field of
///   any visibility (declared, or inherited through `extends`/`with`), a
///   `dart:ffi` or `package:ffi/…` type, also when it is wrapped in an
///   extension type.
/// - `sync-dispose`: a type on the surface has a public instance `dispose`
///   that can be called: a method, or a getter/field of a callable type,
///   declared, inherited, or added by an exported extension.
///
/// A type is *on the surface* when it is exported, or when it is reachable
/// from an exported name through public signatures; see [elementName] and
/// [memberName].
class Violation implements Comparable<Violation> {
  /// Creates a violation record.
  const Violation({
    required this.rule,
    required this.elementName,
    required this.memberName,
    required this.typeString,
    required this.libraryUri,
  });

  /// The rule id (see the class documentation).
  final String rule;

  /// The exported name through which the offending type is reachable.
  final String elementName;

  /// Where under [elementName] the type appears: a member name or a position
  /// marker (`self`, `supertype`, `typeParam`, `alias`, `signature`, …). A
  /// type that is not exported but reachable adds a hop per type, so
  /// `context→NativeContext.bindings` is the `bindings` member of the
  /// non-exported `NativeContext` returned by `context`.
  final String memberName;

  /// The offending type as displayed by the analyzer.
  final String typeString;

  /// The URI of the library that defines the offending type.
  final String libraryUri;

  @override
  String toString() =>
      '$rule\t$elementName.$memberName\t$typeString\t($libraryUri)';

  @override
  bool operator ==(Object other) =>
      other is Violation &&
      other.rule == rule &&
      other.elementName == elementName &&
      other.memberName == memberName &&
      other.typeString == typeString &&
      other.libraryUri == libraryUri;

  @override
  int get hashCode =>
      Object.hash(rule, elementName, memberName, typeString, libraryUri);

  @override
  int compareTo(Violation other) => toString().compareTo(other.toString());
}

/// The outcome of checking one entry library.
class LintResult {
  /// Creates a result; [violations] must already be de-duplicated and sorted.
  const LintResult({
    required this.entryPoint,
    required this.checkedElements,
    required this.violations,
  });

  /// The entry library, as given (relative to the package root, or absolute).
  final String entryPoint;

  /// The number of names in the entry library's export namespace.
  final int checkedElements;

  /// Every distinct violation, sorted by [Violation.compareTo].
  final List<Violation> violations;
}

/// Thrown when the lint cannot reach a verdict: an entry point is missing or
/// is not a library, or analysis reports errors in an entry library, in a
/// library it exports (transitively), or as an unresolved type in a walked
/// signature.
class PublicApiLintException implements Exception {
  /// Creates an exception carrying a human-readable [message].
  const PublicApiLintException(this.message);

  /// What could not be resolved.
  final String message;

  @override
  String toString() => message;
}

/// The entry libraries checked by default: every `lib/*.dart` of the package
/// except [advancedLibrary], sorted, relative to [packageRoot].
List<String> defaultEntryPoints(String packageRoot) {
  final lib = Directory(p.join(packageRoot, 'lib'));
  if (!lib.existsSync()) return const [];
  return [
    for (final file in lib.listSync().whereType<File>())
      if (p.extension(file.path) == '.dart' &&
          p.basename(file.path) != advancedLibrary)
        p.posix.join('lib', p.basename(file.path)),
  ]..sort();
}

/// Checks one entry library; see [checkPublicApiEntries].
Future<LintResult> checkPublicApi({
  required String packageRoot,
  String entryPoint = 'lib/wallet_core_flutter.dart',
}) async => (await checkPublicApiEntries(
  packageRoot: packageRoot,
  entryPoints: [entryPoint],
)).single;

/// Checks every public signature reachable from the export namespace of each
/// of [entryPoints] (relative to [packageRoot], or absolute). Without
/// [entryPoints], checks [defaultEntryPoints] and skips any of them that turns
/// out to be a `part` file.
///
/// Throws [PublicApiLintException] when no verdict is possible.
Future<List<LintResult>> checkPublicApiEntries({
  required String packageRoot,
  List<String>? entryPoints,
}) async {
  final root = p.normalize(p.absolute(packageRoot));
  if (!Directory(root).existsSync()) {
    throw PublicApiLintException('package root not found: $root');
  }
  final explicit = entryPoints != null && entryPoints.isNotEmpty;
  final entries = explicit ? entryPoints : defaultEntryPoints(root);
  if (entries.isEmpty) {
    throw PublicApiLintException('no entry libraries under $root/lib');
  }

  final collection = AnalysisContextCollection(includedPaths: [root]);
  try {
    final results = <LintResult>[];
    for (final entry in entries) {
      final result = await _checkEntry(collection, root, entry, explicit);
      if (result != null) results.add(result);
    }
    if (results.isEmpty) {
      throw PublicApiLintException('no entry libraries under $root/lib');
    }
    return results;
  } finally {
    await collection.dispose();
  }
}

Future<LintResult?> _checkEntry(
  AnalysisContextCollection collection,
  String root,
  String entryPoint,
  bool explicit,
) async {
  final entryPath = p.normalize(p.join(root, entryPoint));
  if (!File(entryPath).existsSync()) {
    throw PublicApiLintException('entry point not found: $entryPath');
  }
  final AnalysisSession session;
  try {
    session = collection.contextFor(entryPath).currentSession;
  } on StateError catch (e) {
    throw PublicApiLintException('cannot analyze $entryPath: ${e.message}');
  }

  final resolved = await session.getResolvedLibrary(entryPath);
  if (resolved is NotLibraryButPartResult && !explicit) return null;
  if (resolved is! ResolvedLibraryResult) {
    throw PublicApiLintException(
      'cannot resolve $entryPath as a library (${resolved.runtimeType})',
    );
  }

  final errors = await _analysisErrors(session, resolved);
  if (errors.isNotEmpty) {
    throw PublicApiLintException(
      _limited('analysis errors in the entry library or its exports', errors),
    );
  }

  final namespace = resolved.element.exportNamespace.definedNames2;
  final walker = _Walker(namespace.values.toSet());
  var checked = 0;
  for (final MapEntry(key: name, value: element) in namespace.entries) {
    if (name.startsWith('_')) continue;
    checked++;
    walker.checkExported(name, element);
  }
  if (walker.unresolved.isNotEmpty) {
    throw PublicApiLintException(
      _limited(
        'unresolved types in public signatures',
        walker.unresolved.toList()..sort(),
      ),
    );
  }

  return LintResult(
    entryPoint: entryPoint,
    checkedElements: checked,
    violations: List.unmodifiable(walker.violations.toList()..sort()),
  );
}

/// Runs the command-line lint and returns its exit code.
///
/// Flags: `--package <dir>` (default `packages/wallet_core_flutter`) and a
/// repeatable `--entry <path relative to the package>` (default: every
/// `lib/*.dart` except `lib/advanced.dart`).
Future<int> runPublicApiLint(
  List<String> args, {
  StringSink? out,
  StringSink? err,
}) async {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;
  var packageRoot = 'packages/wallet_core_flutter';
  final entryPoints = <String>[];

  for (var i = 0; i < args.length; i++) {
    final flag = args[i];
    if ((flag == '--package' || flag == '--entry') && i + 1 < args.length) {
      final value = args[++i];
      if (flag == '--package') {
        packageRoot = value;
      } else {
        entryPoints.add(value);
      }
    } else {
      stderrSink.writeln(
        'Usage: dart run tools/lint/bin/public_api_lint.dart '
        '[--package <dir>] [--entry <path relative to the package>]...',
      );
      return exitUsage;
    }
  }

  final List<LintResult> results;
  try {
    results = await checkPublicApiEntries(
      packageRoot: packageRoot,
      entryPoints: entryPoints,
    );
  } on PublicApiLintException catch (e) {
    stderrSink.writeln('public-api: $e');
    return exitUnresolved;
  }

  var checked = 0;
  var violations = 0;
  for (final result in results) {
    result.violations.forEach(stdoutSink.writeln);
    stdoutSink.writeln(
      'public-api: ${result.entryPoint}: ${result.checkedElements} exported '
      'elements checked, ${result.violations.length} violations',
    );
    checked += result.checkedElements;
    violations += result.violations.length;
  }
  stdoutSink.writeln(
    'public-api: $checked exported elements checked, $violations violations',
  );
  return violations == 0 ? exitClean : exitViolations;
}

String _limited(String heading, List<String> lines) {
  final shown = lines.take(10).join('\n');
  final more = lines.length > 10 ? '\n… and ${lines.length - 10} more' : '';
  return '$heading:\n$shown$more';
}

/// Severity-error diagnostics in every unit (parts included) of [entry] and of
/// every non-SDK library it exports, transitively.
Future<List<String>> _analysisErrors(
  AnalysisSession session,
  ResolvedLibraryResult entry,
) async {
  final errors = <String>[];
  final seen = <Uri>{entry.element.uri};
  final pending = <LibraryElement>[...entry.element.exportedLibraries];

  void collect(ResolvedLibraryResult library) {
    for (final unit in library.units) {
      for (final diagnostic in unit.diagnostics) {
        if (diagnostic.severity != Severity.error) continue;
        final at = unit.lineInfo.getLocation(diagnostic.offset);
        errors.add(
          '${unit.path}:${at.lineNumber}:${at.columnNumber}: '
          '${diagnostic.message}',
        );
      }
    }
  }

  collect(entry);
  while (pending.isNotEmpty) {
    final library = pending.removeLast();
    if (library.isInSdk || !seen.add(library.uri)) continue;
    pending.addAll(library.exportedLibraries);
    final result = await session.getResolvedLibraryByElement(library);
    if (result is ResolvedLibraryResult) {
      collect(result);
    } else {
      errors.add('${library.uri}: cannot resolve (${result.runtimeType})');
    }
  }
  return errors;
}

String? _ruleFor(String uri) {
  if (uri == 'dart:ffi' || uri.startsWith('package:ffi/')) return 'ffi';
  if (uri.contains('/src/generated/')) return 'generated';
  if (uri.startsWith('package:protobuf/') ||
      uri.startsWith('package:fixnum/')) {
    return 'protobuf';
  }
  return null;
}

/// Walks the signatures of the exported elements of one entry library, and of
/// every type reachable from them, and accumulates findings.
///
/// Reachability: a non-SDK interface type met in a public position (return,
/// parameter, getter/setter, bound, type argument, typedef target, extended
/// type) that is neither exported by this entry nor itself a violation is
/// queued and checked like an exported type, its findings attributed to the
/// exported name it was reached from. Each type is visited once per exported
/// name, which also breaks cycles. Supertypes are not queued: their members
/// are already part of the subtype's interface.
class _Walker {
  _Walker(this._exported);

  /// Elements of the entry's export namespace; checked under their own name.
  final Set<Element> _exported;

  final Set<Violation> violations = {};
  final Set<String> unresolved = {};

  String _root = '';
  final Set<InterfaceElement> _visited = {};
  final Queue<(InterfaceElement, String)> _pending = Queue();
  final Set<ExtensionTypeElement> _unwrapping = {};

  void checkExported(String name, Element element) {
    _root = name;
    _visited.clear();
    _pending.clear();

    final uri = element.library?.uri.toString() ?? '';
    _report(_ruleFor(uri), 'self', name, uri);

    switch (element) {
      case InterfaceElement():
        _visited.add(element);
        _checkInterface(element, '', reachable: false);
      case ExtensionElement():
        _checkType(element.extendedType, 'extendedType');
        _checkBounds(element.typeParameters, 'typeParam');
        for (final member in [
          ...element.getters,
          ...element.setters,
          ...element.methods,
        ]) {
          if (!member.isPublic) continue;
          _checkDispose(member, _nameOf(member));
          _checkExecutable(member, _nameOf(member));
        }
      case TypeAliasElement():
        _checkType(element.aliasedType, 'alias');
        _checkBounds(element.typeParameters, 'typeParam');
      case ExecutableElement():
        _checkExecutable(element, 'signature');
      case VariableElement():
        _checkType(element.type, 'type');
      default:
        break;
    }

    while (_pending.isNotEmpty) {
      final (reached, prefix) = _pending.removeFirst();
      _checkInterface(reached, prefix, reachable: true);
    }
  }

  /// Classes, mixins, enums and extension types: own and inherited members.
  ///
  /// Instance members come from [InterfaceElement.interfaceMembers]: one entry
  /// per name, the most specific override, with supertype type arguments
  /// substituted (`extends Base<Pointer<Void>>` exposes `T get value` as
  /// `Pointer<Void> get value`). Members declared in SDK libraries are not
  /// attributed to the element: they cannot mention a forbidden type except
  /// through a type argument, and the supertype itself is checked. Static
  /// members and constructors are checked only on an exported element: a
  /// subtype does not expose them, and a type that is merely reachable cannot
  /// be named to call them.
  void _checkInterface(
    InterfaceElement element,
    String prefix, {
    required bool reachable,
  }) {
    _checkBounds(element.typeParameters, '${prefix}typeParam');
    for (final supertype in element.allSupertypes) {
      _checkType(supertype, '${prefix}supertype', reach: false);
    }

    for (final type in _storageChain(element)) {
      for (final field in type.element.fields) {
        // A field synthesized from a getter/setter stores nothing.
        if (field.isStatic || field.isOriginGetterSetter) continue;
        final fieldName = _nameOf(field);
        final fieldType = type.getGetter(fieldName)?.returnType ?? field.type;
        _checkType(fieldType, '$prefix$fieldName', pointerField: true);
      }
    }

    final members = <ExecutableElement>[
      for (final member in element.interfaceMembers.values)
        if (!member.library.isInSdk) member,
      if (!reachable)
        for (final member in <ExecutableElement>[
          ...element.getters,
          ...element.setters,
          ...element.methods,
        ])
          if (member.isStatic) member,
    ];
    for (final member in members) {
      if (!member.isPublic) continue;
      final at = '$prefix${_nameOf(member)}';
      _checkDispose(member, at);
      _checkExecutable(member, at);
    }

    if (reachable) return;
    for (final constructor in element.constructors) {
      if (!constructor.isPublic) continue;
      final ctorName = _nameOf(constructor);
      _checkExecutable(
        constructor,
        ctorName.isEmpty || ctorName == 'new' ? 'new' : ctorName,
      );
    }
  }

  /// The types whose fields an instance of [element] actually stores: the
  /// element itself, its superclass chain, and the mixins applied along it —
  /// not implemented interfaces, whose fields are not inherited.
  static Iterable<InterfaceType> _storageChain(InterfaceElement element) sync* {
    for (
      InterfaceType? type = element.thisType;
      type != null && !type.element.library.isInSdk;
      type = type.superclass
    ) {
      yield type;
      for (final mixin in type.mixins) {
        if (!mixin.element.library.isInSdk) yield mixin;
      }
    }
  }

  /// `sync-dispose`: an instance member named `dispose` that a caller can
  /// invoke as `x.dispose()`.
  void _checkDispose(ExecutableElement member, String at) {
    if (member.isStatic || _nameOf(member) != 'dispose') return;
    final type = switch (member) {
      MethodElement() => member.returnType,
      GetterElement() when _isCallable(member.returnType) => member.returnType,
      _ => null,
    };
    if (type == null) return;
    _report(
      'sync-dispose',
      at,
      type.getDisplayString(),
      member.library.uri.toString(),
    );
  }

  static bool _isCallable(DartType type) =>
      type is FunctionType ||
      (type is InterfaceType &&
          (type.isDartCoreFunction ||
              [
                type,
                ...type.allSupertypes,
              ].any((t) => t.getMethod('call') != null)));

  void _checkExecutable(ExecutableElement e, String at) {
    _checkType(e.returnType, at);
    for (final parameter in e.formalParameters) {
      _checkType(parameter.type, at);
    }
    _checkBounds(e.typeParameters, at);
  }

  void _checkBounds(List<TypeParameterElement> parameters, String at) {
    for (final parameter in parameters) {
      final bound = parameter.bound;
      if (bound != null) _checkType(bound, at);
    }
  }

  /// Reports every forbidden type mentioned anywhere in [type], and queues the
  /// non-exported types it makes reachable (unless [reach] is false for the
  /// outermost type).
  ///
  /// With [pointerField], only FFI types are reported, as `pointer-field`,
  /// looking through extension types to their representation: the field may
  /// be private, so the other rules (which concern public signatures) do not
  /// apply to it, and nothing is made reachable. [within] is the rule already
  /// reported for an enclosing type; it is not repeated for the types nested
  /// in it (`Pointer<Void>` is one `ffi` exposure, not two).
  void _checkType(
    DartType type,
    String at, {
    bool pointerField = false,
    bool reach = true,
    String? within,
  }) {
    void nested(DartType inner, String? rule) => _checkType(
      inner,
      at,
      pointerField: pointerField,
      within: rule ?? within,
    );

    // Every link of a typedef chain (`typedef A = B; typedef B = C;`).
    final aliases = <TypeAliasElement>{};
    for (
      var alias = type.alias;
      alias != null && aliases.add(alias.element);
      alias = alias.element.aliasedType.alias
    ) {
      String? aliasRule;
      if (!pointerField) {
        final uri = alias.element.library.uri.toString();
        aliasRule = _ruleFor(uri);
        _report(aliasRule, at, alias.element.displayName, uri, within);
      }
      for (final argument in alias.typeArguments) {
        nested(argument, aliasRule);
      }
    }

    switch (type) {
      case InvalidType():
        unresolved.add('$_root.$at');
      case InterfaceType():
        final element = type.element;
        final uri = element.library.uri.toString();
        if (pointerField) {
          final rule = _ruleFor(uri) == 'ffi' ? 'pointer-field' : null;
          _report(rule, at, type.getDisplayString(), uri, within);
          for (final argument in type.typeArguments) {
            nested(argument, rule);
          }
          if (rule == null &&
              element is ExtensionTypeElement &&
              !element.library.isInSdk &&
              _unwrapping.add(element)) {
            nested(element.representation.type, null);
            _unwrapping.remove(element);
          }
        } else {
          final rule = _ruleFor(uri);
          _report(rule, at, type.getDisplayString(), uri, within);
          for (final argument in type.typeArguments) {
            nested(argument, rule);
          }
          if (reach && rule == null) _reach(element, at);
        }
      case FunctionType():
        nested(type.returnType, null);
        for (final parameter in type.formalParameters) {
          nested(parameter.type, null);
        }
        for (final parameter in type.typeParameters) {
          final bound = parameter.bound;
          if (bound != null) nested(bound, null);
        }
      case RecordType():
        for (final field in [...type.positionalFields, ...type.namedFields]) {
          nested(field.type, null);
        }
      default:
        // dynamic, void, Never, and type parameters (whose bounds are walked
        // where they are declared).
        break;
    }
  }

  void _reach(InterfaceElement element, String at) {
    if (element.library.isInSdk ||
        _exported.contains(element) ||
        !_visited.add(element)) {
      return;
    }
    _pending.add((element, '$at→${element.displayName}.'));
  }

  void _report(
    String? rule,
    String at,
    String typeString,
    String libraryUri, [
    String? within,
  ]) {
    if (rule == null || rule == within) return;
    violations.add(
      Violation(
        rule: rule,
        elementName: _root,
        memberName: at,
        typeString: typeString,
        libraryUri: libraryUri,
      ),
    );
  }

  static String _nameOf(Element element) => element.name ?? '';
}
