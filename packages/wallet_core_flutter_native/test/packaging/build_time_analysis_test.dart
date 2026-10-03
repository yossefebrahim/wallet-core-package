/// The build-time Dart that `android/build.gradle` and the podspec run is
/// analyzed, under the options file as `flutter pub get` writes it.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// `flutter pub get` rewrites this package's `analysis_options.yaml` and adds
/// `android/**` and `ios/**` to `analyzer.exclude` (Flutter 3.47.5), so no
/// Dart may live there: it would silently drop out of `melos run analyze`
/// (review T1.9a-d3, finding 10). The build-time Dart lives under `tool/`
/// instead. These tests fail if a Dart file appears under `android/` or
/// `ios/`, if an exclude in the current options file covers a file under
/// `tool/`, or if `dart analyze --fatal-infos tool` reports anything.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every `.dart` file under [directory], relative to the package root.
List<String> _dartFiles(String directory) {
  final root = Directory(directory);
  if (!root.existsSync()) return const [];
  return root
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path)
      .where((p) => p.endsWith('.dart'))
      .toList()
    ..sort();
}

/// The `analyzer.exclude` globs of [optionsYaml]: the `- ` items between
/// `exclude:` and the next key at the same or a lower indentation.
List<String> _excludes(String optionsYaml) {
  final globs = <String>[];
  int? listIndent;
  for (final line in optionsYaml.split('\n')) {
    final trimmed = line.trimLeft();
    final indent = line.length - trimmed.length;
    if (trimmed == 'exclude:') {
      listIndent = indent;
      continue;
    }
    if (listIndent == null || trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }
    if (trimmed.startsWith('- ') && indent >= listIndent) {
      var glob = trimmed.substring(2).trim();
      if (glob.length > 1 &&
          (glob.startsWith('"') || glob.startsWith("'")) &&
          glob.endsWith(glob[0])) {
        glob = glob.substring(1, glob.length - 1);
      }
      globs.add(glob);
    } else if (indent <= listIndent) {
      listIndent = null;
    }
  }
  return globs;
}

/// [glob] as the analyzer applies it: relative to the options file's
/// directory, `**` any number of segments, `*` and `?` within one segment.
RegExp _globRegExp(String glob) {
  final out = StringBuffer('^');
  for (var i = 0; i < glob.length; i++) {
    final c = glob[i];
    if (c == '*' && i + 1 < glob.length && glob[i + 1] == '*') {
      out.write('.*');
      i++;
    } else if (c == '*') {
      out.write('[^/]*');
    } else if (c == '?') {
      out.write('[^/]');
    } else {
      out.write(RegExp.escape(c));
    }
  }
  out.write(r'$');
  return RegExp(out.toString());
}

/// The Flutter SDK's `dart`, else the one on PATH.
String _dartExecutable() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty && File('$root/bin/dart').existsSync()) {
    return '$root/bin/dart';
  }
  return 'dart';
}

void main() {
  test('no Dart file lives under android/ or ios/', () {
    expect([..._dartFiles('android'), ..._dartFiles('ios')], isEmpty);
  });

  test('the build-time Dart the platform builds run is under tool/', () {
    final files = _dartFiles('tool/option2');
    expect(
      files.map((p) => p.substring('tool/option2/'.length)),
      containsAll([
        'prepare_jni_libs.dart',
        'prepare_xcframework.dart',
        'src/jni_libs_plan.dart',
        'src/verified_acquisition.dart',
        'src/xcframework_plan.dart',
      ]),
    );
  });

  test('no analyzer exclude covers a file under tool/', () {
    final globs = _excludes(File('analysis_options.yaml').readAsStringSync());
    // The options file as `flutter pub get` leaves it excludes at least
    // these; the parser must find them, or the check below proves nothing.
    expect(globs, containsAll(['android/**', 'ios/**']));
    for (final file in _dartFiles('tool')) {
      for (final glob in globs) {
        expect(
          _globRegExp(glob).hasMatch(file),
          isFalse,
          reason: 'analysis_options.yaml excludes $file through "$glob"',
        );
      }
    }
  });

  test('dart analyze --fatal-infos reports nothing in tool/', () {
    final ProcessResult result;
    try {
      result = Process.runSync(_dartExecutable(), [
        'analyze',
        '--fatal-infos',
        'tool',
      ]);
    } on ProcessException catch (e) {
      fail('cannot run dart analyze: $e');
    }
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect('${result.stdout}', contains('No issues found!'));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
