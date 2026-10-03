/// The command line of `tool/fetch_artifacts.dart`, parsed without running
/// anything.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
library;

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/options.dart';

FetchOptions _parse(List<String> args) =>
    FetchOptions.parse(args, defaultManifestPath: '/pkg/assets/m.json');

void main() {
  test('an empty command line is the shipped manifest and every artifact', () {
    final options = _parse(const []);
    expect(options.manifestPath, '/pkg/assets/m.json');
    expect(options.cacheDirOverride, isNull);
    expect(options.only, isEmpty);
    expect(options.offline, isFalse);
    expect(options.vendoredDir, isNull);
    expect(options.dryRun, isFalse);
    expect(options.keepGoing, isFalse);
    expect(options.allowInsecureLoopback, isFalse);
    expect(options.help, isFalse);
  });

  test('values may be separate or joined with =', () {
    expect(_parse(['--manifest', '/a.json']).manifestPath, '/a.json');
    expect(_parse(['--manifest=/a.json']).manifestPath, '/a.json');
    expect(_parse(['--cache-dir=/c']).cacheDirOverride, '/c');
    expect(_parse(['--vendored=/v']).vendoredDir, '/v');
  });

  test('--only is repeatable and keeps its order', () {
    expect(_parse(['--only', 'a/b.so', '--only=c/d.zip']).only, [
      'a/b.so',
      'c/d.zip',
    ]);
  });

  test('--only is unmodifiable, so nothing downstream can widen the run', () {
    expect(
      () => _parse(['--only', 'a/b.so']).only.add('c/d.so'),
      throwsUnsupportedError,
    );
  });

  test('--print-urls is --dry-run', () {
    expect(_parse(['--print-urls']).dryRun, isTrue);
    expect(_parse(['--dry-run']).dryRun, isTrue);
  });

  test('the boolean flags', () {
    final options = _parse([
      '--offline',
      '--keep-going',
      '--allow-insecure-loopback',
    ]);
    expect(options.offline, isTrue);
    expect(options.keepGoing, isTrue);
    expect(options.allowInsecureLoopback, isTrue);
  });

  test('-h and --help', () {
    expect(_parse(['-h']).help, isTrue);
    expect(_parse(['--help']).help, isTrue);
  });

  group('usage errors', () {
    test('an unknown option', () {
      expect(
        () => _parse(['--force']),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            'unknown option: --force',
          ),
        ),
      );
    });

    test('a bare positional argument', () {
      expect(() => _parse(['artifact.so']), throwsA(isA<UsageException>()));
    });

    test('an option with no value', () {
      expect(() => _parse(['--manifest']), throwsA(isA<UsageException>()));
      expect(() => _parse(['--only']), throwsA(isA<UsageException>()));
    });

    test('an empty value', () {
      expect(() => _parse(['--manifest=']), throwsA(isA<UsageException>()));
      expect(() => _parse(['--cache-dir=']), throwsA(isA<UsageException>()));
      expect(() => _parse(['--vendored=']), throwsA(isA<UsageException>()));
      expect(() => _parse(['--only=']), throwsA(isA<UsageException>()));
    });

    test('a value on a flag that takes none', () {
      expect(() => _parse(['--offline=yes']), throwsA(isA<UsageException>()));
      expect(() => _parse(['--dry-run=1']), throwsA(isA<UsageException>()));
    });

    test('a repeated single-valued option', () {
      expect(
        () => _parse(['--manifest', '/a', '--manifest', '/b']),
        throwsA(isA<UsageException>()),
      );
      expect(
        () => _parse(['--cache-dir', '/a', '--cache-dir', '/b']),
        throwsA(isA<UsageException>()),
      );
      expect(
        () => _parse(['--vendored', '/a', '--vendored', '/b']),
        throwsA(isA<UsageException>()),
      );
    });
  });

  group('helpText', () {
    test('documents every flag the parser accepts', () {
      for (final flag in const [
        '--manifest',
        '--cache-dir',
        '--only',
        '--offline',
        '--vendored',
        '--dry-run',
        '--print-urls',
        '--keep-going',
        '--allow-insecure-loopback',
        '--help',
      ]) {
        expect(helpText, contains(flag), reason: '$flag is undocumented');
      }
    });

    test('states the cache-directory rule and the offline mode', () {
      expect(helpText, contains(r'$WCF_ARTIFACT_DIR'));
      expect(
        helpText,
        contains('~/.cache/wallet_core_flutter/<upstream.tag>/'),
      );
      expect(helpText, contains('Never open a socket'));
    });

    test('states that nothing skips verification', () {
      expect(helpText, contains('There is no flag that accepts a mismatch.'));
    });

    test('marks the loopback override as test-only', () {
      expect(helpText, contains('TEST ONLY'));
      expect(helpText, contains('127.0.0.1'));
    });

    test('lists the exit codes', () {
      expect(helpText, contains('Exit codes:'));
      expect(helpText, contains('64  the command line was wrong'));
    });
  });
}
