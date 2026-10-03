// Running a system tool and recording the exact command that ran.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.
//
// The recorded command is what a decision document publishes and what someone
// re-runs a year later, so the quoting has to be right for the awkward paths.

import 'package:test/test.dart';
import 'package:wcf_tool_packaging_eval/proc.dart';

void main() {
  group('shellQuote', () {
    test('leaves a safe word bare', () {
      for (final word in const [
        'nm',
        '-gU',
        '--arch=arm64',
        '/usr/bin/otool',
        'third_party/wcf-native-all/artifacts/ios/arm64/lib.dylib',
        'a,b',
        'x@y',
        '50%',
        'k=v',
        '+',
      ]) {
        expect(shellQuote(word), word, reason: word);
      }
    });

    test('quotes a word with a space', () {
      expect(shellQuote('/a path/lib.dylib'), "'/a path/lib.dylib'");
    });

    test('quotes and escapes a single quote', () {
      expect(shellQuote("it's"), r"'it'\''s'");
    });

    test('quotes a double quote, a dollar and a backtick unexpanded', () {
      expect(shellQuote(r'$HOME'), r"'$HOME'");
      expect(shellQuote('say "hi"'), '\'say "hi"\'');
      expect(shellQuote(r'`id`'), r"'`id`'");
      expect(shellQuote(r'a\b'), r"'a\b'");
      expect(shellQuote('a;b'), "'a;b'");
      expect(shellQuote('a b && c'), "'a b && c'");
    });

    test('quotes the empty string, which must not vanish', () {
      expect(shellQuote(''), "''");
    });

    test('quotes a newline inside the word', () {
      expect(shellQuote('a\nb'), "'a\nb'");
    });
  });

  group('formatCommand', () {
    test('joins the executable and its arguments, each quoted', () {
      expect(
        formatCommand('nm', ['-gU', '-arch', 'arm64', '/a path/lib.dylib']),
        "nm -gU -arch arm64 '/a path/lib.dylib'",
      );
    });

    test('an executable with a space is quoted too', () {
      expect(formatCommand('/Xcode 26/nm', const []), "'/Xcode 26/nm'");
    });
  });

  group('run', () {
    test('captures stdout and the exact command', () {
      final result = run('/bin/echo', ['hello world']);
      expect(result.ok, isTrue);
      expect(result.exitCode, 0);
      expect(result.stdout.trim(), 'hello world');
      expect(result.command, "/bin/echo 'hello world'");
    });

    test('a non-zero exit is a measurement, not an exception', () {
      final result = run('/bin/sh', ['-c', 'echo out; echo err >&2; exit 3']);
      expect(result.ok, isFalse);
      expect(result.exitCode, 3);
      expect(result.stdout.trim(), 'out');
      expect(result.stderr.trim(), 'err');
      expect(result.combined, contains('out'));
      expect(result.combined, contains('err'));
    });

    test('a missing executable reports 127 rather than throwing', () {
      final result = run('/nonexistent/tool-that-is-not-here', const []);
      expect(result.exitCode, 127);
      expect(result.ok, isFalse);
      expect(result.stderr, contains('could not run'));
    });
  });

  group('runAsync and runStreaming', () {
    test('runAsync captures the same way run does', () async {
      final result = await runAsync('/bin/echo', ['async']);
      expect(result.ok, isTrue);
      expect(result.stdout.trim(), 'async');
      expect(result.command, '/bin/echo async');
    });

    test('runAsync reports a missing executable as 127', () async {
      final result = await runAsync('/nonexistent/tool', const []);
      expect(result.exitCode, 127);
    });

    test('runStreaming hands over one line at a time', () async {
      final lines = <String>[];
      final result = await runStreaming('/bin/sh', [
        '-c',
        'printf "a\\nb\\nc\\n"',
      ], lines.add);
      expect(result.ok, isTrue);
      expect(lines, ['a', 'b', 'c']);
      expect(
        result.stdout,
        isEmpty,
        reason: 'streamed output is not also buffered',
      );
    });

    test('runStreaming still returns stderr and the exit code', () async {
      final lines = <String>[];
      final result = await runStreaming('/bin/sh', [
        '-c',
        'echo boom >&2; exit 2',
      ], lines.add);
      expect(result.exitCode, 2);
      expect(result.stderr.trim(), 'boom');
      expect(lines, isEmpty);
    });
  });
}
