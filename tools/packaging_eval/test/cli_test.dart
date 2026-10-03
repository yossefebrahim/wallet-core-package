// The `--flag value` parser every command in this package shares.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.
//
// Only well-formed argument lists are exercised here: the malformed shapes
// (`--flag` with no value, a bare word) call `exit(2)` by design, which a test
// process cannot survive.

import 'package:test/test.dart';
import 'package:wcf_tool_packaging_eval/cli.dart';

void main() {
  group('Args.parse', () {
    test('reads `--flag value` and `--flag=value` the same way', () {
      final args = Args.parse([
        '--artifact',
        'lib.dylib',
        '--target=ios/arm64',
      ]);
      expect(args.option('artifact'), 'lib.dylib');
      expect(args.option('target'), 'ios/arm64');
    });

    test('keeps every occurrence of a repeated flag, in order', () {
      final args = Args.parse([
        '--duplicate-scan',
        'a.dylib',
        '--duplicate-scan',
        'b.dylib',
        '--duplicate-scan=c.dylib',
      ]);
      expect(args.options('duplicate-scan'), ['a.dylib', 'b.dylib', 'c.dylib']);
      expect(
        args.option('duplicate-scan'),
        'c.dylib',
        reason: 'option() is the last one given',
      );
    });

    test('a declared switch takes no value', () {
      final args = Args.parse(
        ['--skip-consumer-gen', '--out-dir', '/tmp/x'],
        switches: {'skip-consumer-gen'},
      );
      expect(args.flag('skip-consumer-gen'), isTrue);
      expect(args.option('out-dir'), '/tmp/x');
      expect(args.options('skip-consumer-gen'), isEmpty);
    });

    test('--help and -h are always switches', () {
      expect(Args.parse(['--help']).flag('help'), isTrue);
      expect(Args.parse(['-h']).flag('help'), isTrue);
      expect(Args.parse(const []).flag('help'), isFalse);
    });

    test('`--switch=value` is a value, not a switch', () {
      final args = Args.parse(
        ['--skip-consumer-gen=false'],
        switches: {'skip-consumer-gen'},
      );
      expect(args.flag('skip-consumer-gen'), isFalse);
      expect(args.option('skip-consumer-gen'), 'false');
    });

    test('an absent option is null and an absent list is empty', () {
      final args = Args.parse(const []);
      expect(args.option('artifact'), isNull);
      expect(args.options('artifact'), isEmpty);
      expect(args.flag('anything'), isFalse);
    });

    test('a value may look like a flag or hold spaces', () {
      final args = Args.parse([
        '--command',
        '--not-a-flag here',
        '--path=/a path/with spaces',
      ]);
      expect(args.option('command'), '--not-a-flag here');
      expect(args.option('path'), '/a path/with spaces');
    });

    test('an empty inline value is kept', () {
      expect(Args.parse(['--notes=']).option('notes'), '');
    });
  });
}
