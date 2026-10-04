// Acquisition through the fetch tool: arguments, failure messages, and the
// real verification path against a vendored directory.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../hook/src/acquire.dart';
import '../../tool/src/asset_names.dart' as names;
import '../../tool/src/fetcher.dart' as fetcher;
import 'fixtures.dart';

String _cachePath(String dir, String name) => names.cachePathFor(dir, name);

/// The digest of requests whose fetch tool is a fake that never yields a file.
final String _anyDigest = 'a' * 64;

void main() {
  const name = 'macos/arm64_x86_64/libTrustWalletCore.dylib';

  group('the fetch tool command line', () {
    test('is explicit about manifest, cache and artifact', () {
      final r = AcquireRequest(
        logicalName: name,
        manifestPath: '/m.json',
        cacheDir: '/cache',
        toolDir: '/pkg/tool',
        sha256: _anyDigest,
        size: 10,
      );
      expect(r.arguments, [
        '--manifest',
        '/m.json',
        '--cache-dir',
        '/cache',
        '--only',
        name,
      ]);
    });

    test('carries vendored and offline when set', () {
      final r = AcquireRequest(
        logicalName: name,
        manifestPath: '/m.json',
        cacheDir: '/cache',
        toolDir: '/pkg/tool',
        sha256: _anyDigest,
        size: 10,
        vendoredDir: '/v',
        offline: true,
      );
      expect(
        r.arguments,
        containsAllInOrder(['--vendored', '/v', '--offline']),
      );
      expect(r.commandLine, startsWith('dart run tool/fetch_artifacts.dart '));
    });

    test('runs with an empty environment', () async {
      Map<String, String>? seen;
      // The fake succeeds without writing a file, so the read that follows
      // fails; only the environment the fetch tool saw matters here.
      await expectLater(
        acquireArtifact(
          AcquireRequest(
            logicalName: name,
            manifestPath: '/m.json',
            cacheDir: '/cache',
            toolDir: '/pkg/tool',
            sha256: _anyDigest,
            size: 10,
          ),
          run: (args, {required scriptDir, environment, out, err}) async {
            seen = environment;
            return 0;
          },
          cachePathFor: _cachePath,
        ),
        throwsA(isA<AcquireError>()),
      );
      expect(seen, isEmpty);
    });
  });

  group('failure messages (fake fetch tool)', () {
    final request = AcquireRequest(
      logicalName: name,
      manifestPath: '/m.json',
      cacheDir: '/cache',
      toolDir: '/pkg/tool',
      sha256: _anyDigest,
      size: 10,
      vendoredDir: '/v',
      offline: true,
    );

    Future<AcquireError> failWith(int code, List<String> lines) async {
      try {
        await acquireArtifact(
          request,
          run: (args, {required scriptDir, environment, out, err}) async {
            lines.forEach(out!);
            return code;
          },
          cachePathFor: _cachePath,
        );
      } on AcquireError catch (e) {
        return e;
      }
      fail('expected an AcquireError');
    }

    test('a digest mismatch names the artifact and both digests', () async {
      final e = await failWith(1, [
        'failed    $name',
        '          vendored /v/$name',
        '          expected sha256 ${'a' * 64} size 10',
        '          found    sha256 ${'b' * 64} size 10',
      ]);
      expect(e.exitCode, 1);
      expect(e.message, contains('$name could not be verified'));
      expect(e.message, contains('expected sha256 ${'a' * 64}'));
      expect(e.message, contains('found    sha256 ${'b' * 64}'));
      expect(e.message, contains('never overridable'));
      expect(e.message, contains('--vendored /v --offline'));
    });

    test('the first line is the one Xcode keeps, with both digests', () async {
      final e = await failWith(1, [
        'failed    $name',
        '          vendored /v/$name',
        '          expected sha256 ${'a' * 64} size 10',
        '          found    sha256 ${'b' * 64} size 12',
      ]);
      expect(
        e.message.split('\n').first,
        'error: wallet_core_flutter_native: $name: sha256 mismatch: '
        'expected ${'a' * 64} (10 bytes), found ${'b' * 64} (12 bytes) '
        'from vendored /v/$name; nothing was bundled',
      );
    });

    test('without a digest pair the first line is still an error line', () {
      final line = failureMessage(
        AcquireRequest(
          logicalName: name,
          manifestPath: '/m.json',
          cacheDir: '/cache',
          toolDir: '/pkg/tool',
          sha256: _anyDigest,
          size: 10,
        ),
        2,
        out: const ['retention.primary: is the unfilled placeholder'],
        err: const [],
      ).split('\n').first;
      expect(line, startsWith('error: wallet_core_flutter_native: /m.json'));
      expect(xcodeErrorLine(name, const ['offline: not in the cache']), isNull);
    });

    test('a cache entry and a vendored file both wrong: the last pair', () {
      expect(
        xcodeErrorLine(name, [
          'corrupt   $name  cache entry deleted: /c',
          '          expected sha256 ${'a' * 64} size 10',
          '          found    sha256 ${'c' * 64} size 10',
          'vendored /v/$name',
          'expected sha256 ${'a' * 64} size 10',
          'found    sha256 ${'d' * 64} size 11',
        ]),
        contains('found ${'d' * 64} (11 bytes) from vendored /v/$name'),
      );
    });

    test('a blocked manifest says what to configure', () async {
      final e = await failWith(2, [
        'retention.primary: is the unfilled placeholder "TBD-T0.11" (T0.11)',
      ]);
      expect(e.message, contains('cannot supply $name'));
      expect(e.message, contains('TBD-T0.11'));
      expect(e.message, contains('hooks:'));
      expect(e.message, contains('vendored_dir:'));
    });

    test('offline with nothing vendored says so', () async {
      final e = await failWith(1, ['failed    $name', 'offline: not in']);
      expect(e.message, contains('offline is set'));
    });
  });

  group('the real fetch tool against a vendored directory', () {
    late Directory dir;
    final artifact = fatMachO([
      thinMachO(cpuX86_64, length: 128),
      thinMachO(cpuArm64, length: 160),
    ]);

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('wcf-hook-acquire');
      writeVendored(Directory('${dir.path}/vendored'), {name: artifact});
    });
    tearDown(() => dir.deleteSync(recursive: true));

    AcquireRequest requestFor(String manifest, {String? cacheDir}) {
      final path = '${dir.path}/manifest.json';
      File(path).writeAsStringSync(manifest);
      final record =
          ((jsonDecode(manifest) as Map)['artifacts'] as Map)[name] as Map;
      return AcquireRequest(
        logicalName: name,
        manifestPath: path,
        cacheDir: cacheDir ?? '${dir.path}/cache',
        toolDir: '${Directory.current.path}/tool',
        sha256: record['sha256'] as String,
        size: record['size'] as int,
        vendoredDir: '${dir.path}/vendored',
        offline: true,
      );
    }

    test('a matching file is verified into the cache', () async {
      final ok = await acquireArtifact(
        requestFor(manifestFor({name: artifact})),
        cachePathFor: _cachePath,
      );
      expect(File(ok.cachePath).readAsBytesSync(), artifact);
      expect(ok.bytes, artifact);
    });

    // Review finding 1 (T1.8a-d4), the reviewer's scenario: apps A and B
    // share a cache_dir and pin different manifests. The fetch tool verifies
    // A's file; before A's hook reads it, B's fetch finds it "corrupt" against
    // B's manifest, deletes it and installs B's bytes. The pre-fix hook then
    // read the path again and bundled B's library under a log line saying
    // A's digest was verified.
    group('a cache file replaced after the fetch tool verified it', () {
      final other = fatMachO([
        thinMachO(cpuX86_64, length: 128, fill: 0x51),
        thinMachO(cpuArm64, length: 160, fill: 0x52),
      ]);

      /// The real fetch tool, then [after] — the other writer's turn.
      FetchRunner racing(void Function() after) =>
          (args, {required scriptDir, environment, out, err}) async {
            final code = await fetcher.runFetchArtifacts(
              args,
              scriptDir: scriptDir,
              environment: environment,
              out: out,
              err: err,
            );
            after();
            return code;
          };

      test('by another manifest\'s bytes: fails, nothing returned', () async {
        final shared = '${dir.path}/shared-cache';
        final a = requestFor(manifestFor({name: artifact}), cacheDir: shared);
        final cached = File(_cachePath(shared, name));
        await expectLater(
          acquireArtifact(
            a,
            run: racing(() => cached.writeAsBytesSync(other)),
            cachePathFor: _cachePath,
          ),
          throwsA(
            isA<AcquireError>()
                .having((e) => e.exitCode, 'exitCode', 1)
                .having(
                  (e) => e.message,
                  'message',
                  allOf(
                    startsWith(
                      'error: wallet_core_flutter_native: $name: sha256 '
                      'mismatch: expected ${sha256Hex(artifact)} '
                      '(${artifact.length} bytes), found ${sha256Hex(other)} '
                      '(${other.length} bytes) from cache file ${cached.path} '
                      'read after verification; nothing was bundled',
                    ),
                    contains('cache_dir'),
                  ),
                ),
          ),
        );
      });

      test('by a file of the right size: still the digest decides', () async {
        expect(other.length, artifact.length);
        final a = requestFor(manifestFor({name: artifact}));
        final cached = File(_cachePath(a.cacheDir, name));
        await expectLater(
          acquireArtifact(
            a,
            run: racing(() => cached.writeAsBytesSync(other)),
            cachePathFor: _cachePath,
          ),
          throwsA(isA<AcquireError>()),
        );
      });

      test('by nothing (deleted): fails, nothing returned', () async {
        final a = requestFor(manifestFor({name: artifact}));
        final cached = File(_cachePath(a.cacheDir, name));
        await expectLater(
          acquireArtifact(
            a,
            run: racing(cached.deleteSync),
            cachePathFor: _cachePath,
          ),
          throwsA(
            isA<AcquireError>().having(
              (e) => e.message,
              'message',
              startsWith(
                'error: wallet_core_flutter_native: $name: the verified '
                'cache file ${cached.path} could not be read',
              ),
            ),
          ),
        );
      });

      test(
        'after the read: the returned bytes are still the artifact',
        () async {
          final a = requestFor(manifestFor({name: artifact}));
          final ok = await acquireArtifact(a, cachePathFor: _cachePath);
          File(ok.cachePath).writeAsBytesSync(other);
          expect(ok.bytes, artifact);
        },
      );
    });

    test('a flipped digest fails, naming the artifact and both digests, '
        'and writes nothing to the cache', () async {
      final real = sha256Hex(artifact);
      final flipped = flipDigest(real);
      final request = requestFor(
        manifestFor({name: artifact}, digestOverrides: {name: flipped}),
      );
      await expectLater(
        acquireArtifact(request, cachePathFor: _cachePath),
        throwsA(
          isA<AcquireError>()
              .having((e) => e.exitCode, 'exitCode', 1)
              .having(
                (e) => e.message,
                'message',
                allOf(
                  contains(name),
                  contains('expected sha256 $flipped'),
                  contains('found    sha256 $real'),
                  contains('not copied'),
                  // The real fetch tool's lines, folded into the one line
                  // an Xcode build surfaces.
                  startsWith(
                    'error: wallet_core_flutter_native: $name: sha256 '
                    'mismatch: expected $flipped (${artifact.length} bytes), '
                    'found $real (${artifact.length} bytes) from vendored ',
                  ),
                ),
              ),
        ),
      );
      expect(File(_cachePath(request.cacheDir, name)).existsSync(), isFalse);
    });

    test('a verified cache entry that no longer matches is not used', () async {
      final ok = await acquireArtifact(
        requestFor(manifestFor({name: artifact})),
        cachePathFor: _cachePath,
      );
      expect(File(ok.cachePath).existsSync(), isTrue);
      final flipped = flipDigest(sha256Hex(artifact));
      await expectLater(
        acquireArtifact(
          requestFor(
            manifestFor({name: artifact}, digestOverrides: {name: flipped}),
          ),
          cachePathFor: _cachePath,
        ),
        throwsA(isA<AcquireError>()),
      );
      expect(File(ok.cachePath).existsSync(), isFalse);
    });

    test('a placeholder manifest is blocked before any file is read', () async {
      final e = acquireArtifact(
        requestFor(
          manifestFor({name: artifact}).replaceFirst(
            RegExp(r'"sha256": "[0-9a-f]{64}"'),
            '"sha256": '
            '"TBD-T1.2"',
          ),
        ),
        cachePathFor: _cachePath,
      );
      await expectLater(
        e,
        throwsA(
          isA<AcquireError>()
              .having((e) => e.exitCode, 'exitCode', 2)
              .having((e) => e.message, 'message', contains('TBD-T1.2')),
        ),
      );
    });
  });
}
