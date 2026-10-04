import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:wcf_tool_lint/runtime_deps_check.dart';

void main() {
  group('runtime_deps_check', () {
    late Directory tempDir;
    late String root;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('runtime_deps_test');
      root = tempDir.path;

      final dartTool = Directory(p.join(root, '.dart_tool'))..createSync();

      final pkgs = {
        'wallet_core_flutter': p.join(root, 'packages', 'wallet_core_flutter'),
        'wallet_core_flutter_bindings': p.join(
          root,
          'packages',
          'wallet_core_flutter_bindings',
        ),
        'wallet_core_flutter_native': p.join(
          root,
          'packages',
          'wallet_core_flutter_native',
        ),
        'http': p.join(root, 'hosted', 'http'),
        'ffi': p.join(root, 'hosted', 'ffi'),
        'bad_pkg': p.join(root, 'hosted', 'bad_pkg'),
      };

      for (final path in pkgs.values) {
        Directory(p.join(path, 'lib')).createSync(recursive: true);
        Directory(p.join(path, 'tool')).createSync(recursive: true);
      }

      final packageConfig = {
        'configVersion': 2,
        'packages': pkgs.entries
            .map(
              (e) => {'name': e.key, 'rootUri': e.value, 'packageUri': 'lib/'},
            )
            .toList(),
      };

      File(
        p.join(dartTool.path, 'package_config.json'),
      ).writeAsStringSync(jsonEncode(packageConfig));
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('clean repository', () async {
      for (final name in [
        'wallet_core_flutter',
        'wallet_core_flutter_bindings',
        'wallet_core_flutter_native',
      ]) {
        File(p.join(root, 'packages', name, 'pubspec.yaml')).writeAsStringSync(
          '''
name: $name
dependencies:
  ffi: ^2.1.0
''',
        );
      }

      File(p.join(root, 'hosted', 'ffi', 'pubspec.yaml')).writeAsStringSync('''
name: ffi
''');

      var outBuffer = StringBuffer();
      var errBuffer = StringBuffer();

      int code = await IOOverrides.runZoned(
        () => runRuntimeDepsCheck(['--root', root]),
        stdout: () => _MockStdout(outBuffer),
        stderr: () => _MockStdout(errBuffer),
      );

      expect(code, exitClean);
      expect(outBuffer.toString(), contains('Status: OK'));
      expect(outBuffer.toString(), isNot(contains('Violations found')));
    });

    test('depends on http -> violation', () async {
      for (final name in [
        'wallet_core_flutter',
        'wallet_core_flutter_bindings',
        'wallet_core_flutter_native',
      ]) {
        File(p.join(root, 'packages', name, 'pubspec.yaml')).writeAsStringSync(
          '''
name: $name
dependencies:
  http: ^1.0.0
''',
        );
      }

      File(p.join(root, 'hosted', 'http', 'pubspec.yaml')).writeAsStringSync('''
name: http
''');

      var outBuffer = StringBuffer();
      int code = await IOOverrides.runZoned(
        () => runRuntimeDepsCheck(['--root', root]),
        stdout: () => _MockStdout(outBuffer),
      );

      expect(code, exitViolations);
      expect(outBuffer.toString(), contains('http is on the deny list'));
    });

    test('dev_dependencies on http -> OK', () async {
      for (final name in [
        'wallet_core_flutter',
        'wallet_core_flutter_bindings',
        'wallet_core_flutter_native',
      ]) {
        File(p.join(root, 'packages', name, 'pubspec.yaml')).writeAsStringSync(
          '''
name: $name
dev_dependencies:
  http: ^1.0.0
''',
        );
      }

      File(p.join(root, 'hosted', 'http', 'pubspec.yaml')).writeAsStringSync('''
name: http
''');

      var outBuffer = StringBuffer();
      int code = await IOOverrides.runZoned(
        () => runRuntimeDepsCheck(['--root', root]),
        stdout: () => _MockStdout(outBuffer),
      );

      expect(code, exitClean);
      expect(outBuffer.toString(), isNot(contains('http is on the deny list')));
    });

    test('git runtime source -> violation', () async {
      File(
        p.join(root, 'packages', 'wallet_core_flutter', 'pubspec.yaml'),
      ).writeAsStringSync('''
name: wallet_core_flutter
dependencies:
  ffi:
    git:
      url: "https://example.com"
''');

      var outBuffer = StringBuffer();
      int code = await IOOverrides.runZoned(
        () => runRuntimeDepsCheck(['--root', root]),
        stdout: () => _MockStdout(outBuffer),
      );

      expect(code, exitViolations);
      expect(outBuffer.toString(), contains('ffi has a git: source'));
    });

    test('lib/ file using HttpClient -> violation', () async {
      for (final name in [
        'wallet_core_flutter',
        'wallet_core_flutter_bindings',
        'wallet_core_flutter_native',
      ]) {
        File(p.join(root, 'packages', name, 'pubspec.yaml')).writeAsStringSync(
          '''
name: $name
''',
        );
      }

      File(
        p.join(root, 'packages', 'wallet_core_flutter', 'lib', 'test.dart'),
      ).writeAsStringSync('var client = HttpClient();');

      var outBuffer = StringBuffer();
      int code = await IOOverrides.runZoned(
        () => runRuntimeDepsCheck(['--root', root]),
        stdout: () => _MockStdout(outBuffer),
      );

      expect(code, exitViolations);
      expect(
        outBuffer.toString(),
        contains('contains network symbol HttpClient (not allowed in lib/)'),
      );
    });

    test('tool/ file using HttpClient without marker -> violation', () async {
      for (final name in [
        'wallet_core_flutter',
        'wallet_core_flutter_bindings',
        'wallet_core_flutter_native',
      ]) {
        File(p.join(root, 'packages', name, 'pubspec.yaml')).writeAsStringSync(
          '''
name: $name
''',
        );
      }

      File(
        p.join(root, 'packages', 'wallet_core_flutter', 'tool', 'test.dart'),
      ).writeAsStringSync('var client = HttpClient();');

      var outBuffer = StringBuffer();
      int code = await IOOverrides.runZoned(
        () => runRuntimeDepsCheck(['--root', root]),
        stdout: () => _MockStdout(outBuffer),
      );

      expect(code, exitViolations);
      expect(outBuffer.toString(), contains('without an allowed marker'));
    });

    test('tool/ file using HttpClient with marker -> OK', () async {
      for (final name in [
        'wallet_core_flutter',
        'wallet_core_flutter_bindings',
        'wallet_core_flutter_native',
      ]) {
        File(p.join(root, 'packages', name, 'pubspec.yaml')).writeAsStringSync(
          '''
name: $name
''',
        );
      }

      File(
        p.join(root, 'packages', 'wallet_core_flutter', 'tool', 'test.dart'),
      ).writeAsStringSync('var client = HttpClient(); // wcf: network-ok');

      var outBuffer = StringBuffer();
      int code = await IOOverrides.runZoned(
        () => runRuntimeDepsCheck(['--root', root]),
        stdout: () => _MockStdout(outBuffer),
      );

      expect(code, exitClean);
      expect(
        outBuffer.toString(),
        contains('build-time, network allowed by rule 3'),
      );
    });

    test(
      'packages/wallet_core_flutter_native/tool/ allowed implicitly',
      () async {
        for (final name in [
          'wallet_core_flutter',
          'wallet_core_flutter_bindings',
          'wallet_core_flutter_native',
        ]) {
          File(
            p.join(root, 'packages', name, 'pubspec.yaml'),
          ).writeAsStringSync('''
name: $name
''');
        }

        File(
          p.join(
            root,
            'packages',
            'wallet_core_flutter_native',
            'tool',
            'test.dart',
          ),
        ).writeAsStringSync('var client = HttpClient();');

        var outBuffer = StringBuffer();
        int code = await IOOverrides.runZoned(
          () => runRuntimeDepsCheck(['--root', root]),
          stdout: () => _MockStdout(outBuffer),
        );

        expect(code, exitClean);
        expect(
          outBuffer.toString(),
          contains('build-time, network allowed by rule 3'),
        );
      },
    );

    test('the real three packages -> OK', () async {
      // Runs against the actual repository directory.
      final actualRoot = Directory.current.parent.parent.path;
      var outBuffer = StringBuffer();
      int code = await IOOverrides.runZoned(
        () => runRuntimeDepsCheck(['--root', actualRoot]),
        stdout: () => _MockStdout(outBuffer),
      );

      expect(code, exitClean);
    });
  });
}

class _MockStdout implements Stdout {
  final StringBuffer _buffer;
  _MockStdout(this._buffer);
  @override
  void writeln([Object? object = ""]) {
    _buffer.writeln(object);
  }

  @override
  void write(Object? object) {
    _buffer.write(object);
  }

  @override
  void writeAll(Iterable<dynamic> objects, [String sep = ""]) {
    _buffer.writeAll(objects, sep);
  }

  @override
  void writeCharCode(int charCode) {
    _buffer.writeCharCode(charCode);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
