import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

const exitClean = 0;
const exitViolations = 1;

const denyList = [
  'http',
  'dio',
  'web_socket_channel',
  'grpc',
  'socket_io_client',
  'chopper',
  'retrofit',
  'connectivity_plus',
  'url_launcher',
];

bool isDenied(String package) {
  if (denyList.contains(package)) return true;
  if (package.startsWith('firebase_')) return true;
  if (package.startsWith('sentry')) return true;
  return false;
}

const allowList = {
  'ffi': 'Dart FFI is required for C interop',
  'protobuf': 'Required for Trust Wallet Core protobuf serialization',
  'fixnum': 'Required by protobuf for 64-bit integers',
  'crypto':
      'Cryptographic hashing (SHA-256) for artifact/manifest verification',
  'collection': 'Collections utility used for Dart types',
  'meta': 'Dart meta annotations',
  'typed_data': 'Typed data wrappers',
  'flutter': 'Flutter SDK',
  'sky_engine': 'Flutter internal engine',
  'characters': 'Dart string characters utility',
  'material_color_utilities': 'Flutter material colors',
  'vector_math': 'Flutter vector math',
  'wallet_core_flutter': 'Sibling package in workspace',
  'wallet_core_flutter_bindings': 'Sibling package in workspace',
  'wallet_core_flutter_native': 'Sibling package in workspace',
};

/// The packages a build hook (`hook/build.dart`) imports. A package that has
/// a hook may list them under `dependencies:` because pub resolves a hook's
/// imports from there, but they run in the consumer's build, inside the
/// hooks runner, and never in the app (DECISION-2: build hooks). The closure
/// walk therefore does not count them as run-time dependencies of a package
/// with a `hook/build.dart`; it classifies them, and everything reachable
/// only through them, as **build-time (hook)**.
const hookEntryPackages = {'hooks', 'code_assets'};

/// Packages reviewed for use at build time inside a hook, reachable only
/// through [hookEntryPackages]. A package reachable at run time as well is
/// checked against [allowList] instead. The deny list applies here too.
const buildTimeHookAllowList = {
  'hooks':
      'build-time (hook): the build hook protocol (input, output, '
      'BuildError); imported only by hook/build.dart',
  'code_assets':
      'build-time (hook): CodeAsset, DynamicLoadingBundled and '
      'the target OS/architecture; imported only by hook/',
  'logging': 'build-time (hook): dependency of hooks',
  'pub_semver': 'build-time (hook): dependency of hooks',
  'record_use': 'build-time (hook): dependency of hooks',
  'yaml': 'build-time (hook): dependency of hooks (reads pubspec.yaml)',
  'source_span': 'build-time (hook): dependency of yaml',
  'string_scanner': 'build-time (hook): dependency of yaml',
  'term_glyph': 'build-time (hook): dependency of source_span',
  'path': 'build-time (hook): dependency of source_span',
};

const siblingPackages = {
  'wallet_core_flutter',
  'wallet_core_flutter_bindings',
  'wallet_core_flutter_native',
};

class DependencyReport {
  final String packageName;

  /// The run-time closure: what can execute in the app.
  final Set<String> closure;

  /// Reachable only through [hookEntryPackages] of a package with a build
  /// hook: what executes in the consumer's build, never in the app.
  final Set<String> buildTime;
  final List<String> violations;

  DependencyReport(
    this.packageName,
    this.closure,
    this.violations, {
    this.buildTime = const {},
  });
}

Future<int> runRuntimeDepsCheck(List<String> args) async {
  String root = Directory.current.path;
  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--root' && i + 1 < args.length) {
      root = p.absolute(args[i + 1]);
    }
  }

  final packageConfigPath = p.join(root, '.dart_tool', 'package_config.json');
  if (!File(packageConfigPath).existsSync()) {
    stderr.writeln(
      'Error: .dart_tool/package_config.json not found. Run melos bootstrap.',
    );
    return 2;
  }

  final packageConfigContent = File(packageConfigPath).readAsStringSync();
  final packageConfig =
      jsonDecode(packageConfigContent) as Map<String, dynamic>;
  final packages = packageConfig['packages'] as List<dynamic>;

  final packageMap = <String, String>{};
  for (final pkg in packages) {
    final name = pkg['name'] as String;
    String rootUri = pkg['rootUri'] as String;
    if (rootUri.startsWith('file://')) {
      rootUri = Uri.parse(rootUri).toFilePath();
    } else {
      rootUri = p.normalize(p.join(p.dirname(packageConfigPath), rootUri));
    }
    packageMap[name] = rootUri;
  }

  final lockFile = File(p.join(root, 'pubspec.lock'));
  Map<String, dynamic>? lockPackages;
  if (lockFile.existsSync()) {
    final lockDoc = loadYaml(lockFile.readAsStringSync());
    if (lockDoc != null && lockDoc['packages'] is YamlMap) {
      lockPackages = (lockDoc['packages'] as YamlMap).cast<String, dynamic>();
    }
  }

  final rootPubspecFile = File(p.join(root, 'pubspec.yaml'));
  YamlMap? rootOverrides;
  if (rootPubspecFile.existsSync()) {
    final rootPubspecDoc = loadYaml(rootPubspecFile.readAsStringSync());
    if (rootPubspecDoc != null &&
        rootPubspecDoc['dependency_overrides'] is YamlMap) {
      rootOverrides = rootPubspecDoc['dependency_overrides'] as YamlMap;
    }
  }

  int totalViolations = 0;
  final buildTimeOnly = <String>{};
  final runTime = <String>{};
  for (final pkg in siblingPackages) {
    final report = _checkPackage(pkg, packageMap, lockPackages, rootOverrides);
    buildTimeOnly.addAll(report.buildTime);
    runTime.addAll(report.closure);
    stdout.writeln('Package: $pkg');
    stdout.writeln('Closure: ${report.closure.toList()..sort()}');
    if (report.buildTime.isNotEmpty) {
      stdout.writeln('Build-time (hook): ${report.buildTime.toList()..sort()}');
    }
    if (report.violations.isEmpty) {
      stdout.writeln('Status: OK');
    } else {
      stdout.writeln('Status: Violations found:');
      for (final v in report.violations) {
        stdout.writeln('  - $v');
      }
      totalViolations += report.violations.length;
    }
    stdout.writeln('');
  }

  final netViolations = _checkNetworkSymbols(root);
  if (netViolations.isNotEmpty) {
    stdout.writeln('Network Symbol Violations:');
    for (final v in netViolations) {
      stdout.writeln('  - $v');
    }
    totalViolations += netViolations.length;
  } else {
    stdout.writeln('Network Symbols: OK');
  }

  final importViolations = _checkBuildTimeImports(root, {
    ...hookEntryPackages,
    ...buildTimeOnly.difference(runTime),
  });
  if (importViolations.isNotEmpty) {
    stdout.writeln('Build-time (hook) Import Violations:');
    for (final v in importViolations) {
      stdout.writeln('  - $v');
    }
    totalViolations += importViolations.length;
  } else {
    stdout.writeln('Build-time (hook) imports: OK');
  }

  return totalViolations == 0 ? exitClean : exitViolations;
}

DependencyReport _checkPackage(
  String entryPackage,
  Map<String, String> packageMap,
  Map<String, dynamic>? lockPackages,
  YamlMap? rootOverrides,
) {
  final closure = <String>{};
  final queue = <String>[entryPackage];
  final violations = <String>[];

  // We check for git/path sources in the published packages' pubspecs
  if (packageMap.containsKey(entryPackage)) {
    final pubspecPath = p.join(packageMap[entryPackage]!, 'pubspec.yaml');
    if (File(pubspecPath).existsSync()) {
      final doc = loadYaml(File(pubspecPath).readAsStringSync());
      final deps = doc['dependencies'];
      if (deps is YamlMap) {
        for (final entry in deps.entries) {
          final depName = entry.key as String;
          final depValue = entry.value;
          if (depValue is YamlMap) {
            if (depValue.containsKey('git')) {
              violations.add(
                '$depName has a git: source in $entryPackage pubspec.',
              );
            }
            if (depValue.containsKey('path') &&
                !siblingPackages.contains(depName)) {
              violations.add(
                '$depName has a path: source in $entryPackage pubspec (path is allowed only for the three siblings while they are workspace members).',
              );
            }
          }
        }
      }
    }
  }

  // Run-time closure first. A package with a build hook lists the hook's
  // imports under `dependencies:` too; those start the build-time walk below
  // instead of this one.
  final hookRoots = <String>{};
  _walk(queue, closure, packageMap, onHookDependency: hookRoots.add);

  // Build-time (hook): reachable from the hook's imports and not at run time.
  final reachedByHook = <String>{};
  _walk(
    hookRoots.toList(),
    reachedByHook,
    packageMap,
    onHookDependency: (_) {},
    followHookDependencies: true,
  );
  final buildTime = reachedByHook.difference(closure);

  for (final pkg in [...closure, ...buildTime]) {
    final isBuildTime = buildTime.contains(pkg);
    if (rootOverrides != null &&
        rootOverrides.containsKey(pkg) &&
        !siblingPackages.contains(pkg)) {
      violations.add('$pkg has a dependency_override in the root pubspec.');
    }

    if (lockPackages != null && lockPackages.containsKey(pkg)) {
      final lockEntry = lockPackages[pkg];
      if (lockEntry is YamlMap) {
        final source = lockEntry['source'];
        if (source == 'hosted') {
          final desc = lockEntry['description'];
          if (desc is YamlMap) {
            final url = desc['url'];
            if (url != 'https://pub.dev') {
              violations.add('$pkg source-not-allowed: custom hosted URL.');
            }
          }
        } else if (source == 'sdk') {
          // ok
        } else if (source == 'path') {
          if (!siblingPackages.contains(pkg)) {
            violations.add('$pkg source-not-allowed: path source.');
          }
        } else {
          violations.add('$pkg source-not-allowed: $source.');
        }
      }
    }

    if (isDenied(pkg)) {
      violations.add(
        '$pkg is on the deny list of networking/telemetry packages'
        '${isBuildTime ? ' (build-time, through the hook)' : ''}.',
      );
    } else if (isBuildTime) {
      if (!allowList.containsKey(pkg) &&
          !buildTimeHookAllowList.containsKey(pkg)) {
        violations.add(
          '$pkg is not on the allow list of packages whose build-time (hook) '
          'use is reviewed.',
        );
      }
    } else if (!allowList.containsKey(pkg)) {
      violations.add(
        '$pkg is not on the allow list of packages whose runtime use is reviewed.',
      );
    }
  }

  return DependencyReport(
    entryPackage,
    closure,
    violations,
    buildTime: buildTime,
  );
}

/// Breadth-first over `dependencies:` from [queue], adding to [seen].
///
/// A dependency in [hookEntryPackages] of a package that has a
/// `hook/build.dart` is handed to [onHookDependency] and not followed, unless
/// [followHookDependencies] is set (the build-time walk).
void _walk(
  List<String> queue,
  Set<String> seen,
  Map<String, String> packageMap, {
  required void Function(String) onHookDependency,
  bool followHookDependencies = false,
}) {
  while (queue.isNotEmpty) {
    final current = queue.removeAt(0);
    if (seen.contains(current)) continue;
    seen.add(current);

    final pkgDir = packageMap[current];
    if (pkgDir == null) continue;

    final pubspecPath = p.join(pkgDir, 'pubspec.yaml');
    if (!File(pubspecPath).existsSync()) continue;

    final hasHook = File(p.join(pkgDir, 'hook', 'build.dart')).existsSync();
    final doc = loadYaml(File(pubspecPath).readAsStringSync());
    final deps = doc['dependencies'];
    if (deps is YamlMap) {
      for (final key in deps.keys) {
        final dep = key as String;
        if (hasHook &&
            !followHookDependencies &&
            hookEntryPackages.contains(dep)) {
          onHookDependency(dep);
        } else {
          queue.add(dep);
        }
      }
    }
  }
}

/// `lib/` of the three packages must not import or export a build-time
/// (hook) package: that would make it a run-time dependency the closure walk
/// classified as build-time.
List<String> _checkBuildTimeImports(String root, Set<String> buildTimeOnly) {
  final violations = <String>[];
  final directive = RegExp(
    r'''^\s*(?:import|export)\s+['"]package:([A-Za-z0-9_]+)/''',
  );
  for (final pkg in siblingPackages) {
    final libDir = Directory(p.join(root, 'packages', pkg, 'lib'));
    if (!libDir.existsSync()) continue;
    for (final file in libDir.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final match = directive.firstMatch(lines[i]);
        if (match == null) continue;
        final imported = match.group(1)!;
        if (buildTimeOnly.contains(imported)) {
          violations.add(
            '${file.path}:${i + 1}: imports build-time (hook) package '
            '$imported from lib/; it may be used only under hook/.',
          );
        }
      }
    }
  }
  return violations;
}

List<String> _checkNetworkSymbols(String root) {
  final violations = <String>[];
  final networkSymbols = [
    'SecureSocket',
    'RawSecureSocket',
    'ServerSocket',
    'RawServerSocket',
    'RawDatagramSocket',
    'WebSocketTransformer',
    'NetworkImage',
    'Image.network',
    'HttpClient',
    'HttpServer',
    'Process.run',
    'Process.start',
    'Socket',
    'WebSocket',
    'package:http',
    'InternetAddress',
    'RawSocket',
    'SecureServerSocket',
    'RawSecureServerSocket',
    'ConnectionTask',
    'NetworkInterface',
    'HttpClientRequest',
    'HttpClientResponse',
    'WebSocketChannel',
    'package:web_socket_channel',
    'package:dio',
    'package:grpc',
    'dart:html',
    'HttpRequest',
  ];

  for (final pkg in siblingPackages) {
    final pkgPath = p.join(root, 'packages', pkg);
    final libDir = Directory(p.join(pkgPath, 'lib'));
    final toolDir = Directory(p.join(pkgPath, 'tool'));
    final hookDir = Directory(p.join(pkgPath, 'hook'));

    void scanDir(Directory dir, bool isToolOrHook) {
      if (!dir.existsSync()) return;
      final isNativeTool =
          pkg == 'wallet_core_flutter_native' && dir.path == toolDir.path;

      for (final file in dir.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final originalLine = lines[i];

          // Basic stripping of comments and string literals
          // This is a naive approach but sufficient for the requested fixture tests
          var cleanLine = originalLine.replaceAll(RegExp(r'//.*'), '');
          cleanLine = cleanLine.replaceAll(RegExp(r"'.*?'"), "''");
          cleanLine = cleanLine.replaceAll(RegExp(r'".*?"'), '""');

          for (final sym in networkSymbols) {
            bool match = false;
            if (sym == 'package:http' || sym.contains('.')) {
              match = cleanLine.contains(sym);
            } else {
              match = RegExp(r'\b' + sym + r'\b').hasMatch(cleanLine);
            }

            if (match) {
              if (isNativeTool) {
                stdout.writeln(
                  '${file.path}:${i + 1}: build-time, network allowed by rule 3',
                );
              } else if (isToolOrHook) {
                if (originalLine.contains('// wcf: network-ok')) {
                  stdout.writeln(
                    '${file.path}:${i + 1}: build-time, network allowed by rule 3',
                  );
                } else {
                  violations.add(
                    '${file.path}:${i + 1}: contains network symbol $sym without an allowed marker.',
                  );
                }
              } else {
                violations.add(
                  '${file.path}:${i + 1}: contains network symbol $sym (not allowed in lib/).',
                );
              }
            }
          }
        }
      }
    }

    scanDir(libDir, false);
    scanDir(toolDir, true);
    scanDir(hookDir, true);
  }

  return violations;
}
