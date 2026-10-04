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
  'path': 'Path manipulation',
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

const siblingPackages = {
  'wallet_core_flutter',
  'wallet_core_flutter_bindings',
  'wallet_core_flutter_native',
};

class DependencyReport {
  final String packageName;
  final Set<String> closure;
  final List<String> violations;

  DependencyReport(this.packageName, this.closure, this.violations);
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
    return exitViolations;
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

  int totalViolations = 0;
  for (final pkg in siblingPackages) {
    final report = _checkPackage(pkg, packageMap);
    stdout.writeln('Package: $pkg');
    stdout.writeln('Closure: ${report.closure.toList()..sort()}');
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

  return totalViolations == 0 ? exitClean : exitViolations;
}

DependencyReport _checkPackage(
  String entryPackage,
  Map<String, String> packageMap,
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

  while (queue.isNotEmpty) {
    final current = queue.removeAt(0);
    if (closure.contains(current)) continue;
    closure.add(current);

    final pkgDir = packageMap[current];
    if (pkgDir == null) continue;

    final pubspecPath = p.join(pkgDir, 'pubspec.yaml');
    if (!File(pubspecPath).existsSync()) continue;

    final doc = loadYaml(File(pubspecPath).readAsStringSync());
    final deps = doc['dependencies'];
    if (deps is YamlMap) {
      for (final key in deps.keys) {
        queue.add(key as String);
      }
    }
  }

  for (final pkg in closure) {
    if (isDenied(pkg)) {
      violations.add(
        '$pkg is on the deny list of networking/telemetry packages.',
      );
    } else if (!allowList.containsKey(pkg)) {
      violations.add(
        '$pkg is not on the allow list of packages whose runtime use is reviewed.',
      );
    }
  }

  return DependencyReport(entryPackage, closure, violations);
}

List<String> _checkNetworkSymbols(String root) {
  final violations = <String>[];
  final networkSymbols = [
    'HttpClient',
    'Socket',
    'RawDatagramSocket',
    'WebSocket',
    'HttpServer',
    'package:http',
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
          final line = lines[i];
          for (final sym in networkSymbols) {
            // simple check; we could use regex, but string matching is fine as requested.
            // to avoid partial matches like "MySocket", let's make sure it's surrounded by non-word chars if possible
            // or just rely on contains as before, but let's just use regex for whole word except package:http
            bool match = false;
            if (sym == 'package:http') {
              match = line.contains(sym);
            } else {
              match = RegExp(r'\b' + sym + r'\b').hasMatch(line);
            }

            if (match) {
              if (isNativeTool) {
                stdout.writeln(
                  '${file.path}:${i + 1}: build-time, network allowed by rule 3',
                );
              } else if (isToolOrHook) {
                if (line.contains('// wcf: network-ok')) {
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
