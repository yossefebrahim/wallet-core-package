/// End-to-end behaviour of `tool/fetch_artifacts.dart` against a loopback fake
/// release, a fake mirror, and a temporary cache.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// Every assertion about "no network" is made against the server's own request
/// log, not against the tool's output: the server is the only thing that can
/// say whether a socket was opened.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/fetcher.dart';
import 'fake_release.dart';

const String _setId = 'as_4.8.0_001';
const String _tag = '4.8.0';

typedef _Run = ({int code, String output});

void main() {
  late Directory root;
  late Directory cache;
  late Directory vendored;
  late FakeReleaseServer server;
  late FakeArtifact android;
  late FakeArtifact ios;
  late String scriptDir;

  String manifestPath(String name) => '${root.path}/$name.json';

  void writeManifest(String name, String json) =>
      File(manifestPath(name)).writeAsStringSync(json);

  Future<_Run> run(List<String> args) async {
    final lines = <String>[];
    final code = await runFetchArtifacts(
      args,
      scriptDir: scriptDir,
      environment: <String, String>{'HOME': root.path},
      out: lines.add,
      err: lines.add,
    );
    return (code: code, output: lines.join('\n'));
  }

  /// The default arguments: the fake manifest, the temporary cache, and the
  /// loopback override the fake server needs.
  List<String> base(String manifest, [List<String> extra = const []]) => [
    '--manifest',
    manifestPath(manifest),
    '--cache-dir',
    cache.path,
    '--allow-insecure-loopback',
    ...extra,
  ];

  File cachedFile(FakeArtifact artifact) =>
      File('${cache.path}/${artifact.logicalName}');

  List<String> strayTempFiles() => cache
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path)
      .where((p) => p.endsWith('.part'))
      .toList();

  setUp(() async {
    final tmp = Platform.environment['TMPDIR'] ?? Directory.systemTemp.path;
    root = Directory(tmp).createTempSync('wcf-fetch-test-');
    cache = Directory('${root.path}/cache')..createSync(recursive: true);
    vendored = Directory('${root.path}/vendored')..createSync(recursive: true);
    scriptDir = '${Directory.current.path}/tool';

    android = FakeArtifact.generated('android/arm64-v8a/libTrustWalletCore.so');
    ios = FakeArtifact.generated(
      'ios/TrustWalletCore.xcframework.zip',
      length: 4096,
      seed: 2,
    );
    server = await FakeReleaseServer.start(
      setId: _setId,
      artifacts: [android, ios],
    );

    writeManifest(
      'ok',
      fakeManifestJson(
        setId: _setId,
        upstreamTag: _tag,
        primary: server.primaryBase,
        mirror: null,
        artifacts: [android, ios],
      ),
    );
    writeManifest(
      'mirrored',
      fakeManifestJson(
        setId: _setId,
        upstreamTag: _tag,
        primary: server.primaryBase,
        mirror: server.mirrorBase,
        artifacts: [android, ios],
      ),
    );
  });

  tearDown(() async {
    await server.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  group('the happy path', () {
    test('fetches, verifies, caches, and reports every artifact', () async {
      final result = await run(base('ok'));
      expect(result.code, exitOk, reason: result.output);
      expect(result.output, contains('fetched   ${android.logicalName}'));
      expect(result.output, contains('fetched   ${ios.logicalName}'));
      expect(result.output, contains('2 requested'));
      expect(result.output, contains('2 downloaded'));
      expect(result.output, contains('0 failed'));

      expect(cachedFile(android).readAsBytesSync(), android.bytes);
      expect(cachedFile(ios).readAsBytesSync(), ios.bytes);
      expect(server.requests, hasLength(2));
      expect(strayTempFiles(), isEmpty);
    });

    test('a second run makes no request at all', () async {
      expect((await run(base('ok'))).code, exitOk);
      expect(server.requests, hasLength(2));

      final second = await run(base('ok'));
      expect(second.code, exitOk, reason: second.output);
      expect(second.output, contains('verified  ${android.logicalName}'));
      expect(second.output, contains('2 already verified in the cache'));
      expect(
        server.requests,
        hasLength(2),
        reason:
            'the cached bytes hashed to the manifest digest, so nothing '
            'should have been asked for a second time',
      );
    });

    test('--only fetches just the named artifact', () async {
      final result = await run(base('ok', ['--only', ios.logicalName]));
      expect(result.code, exitOk, reason: result.output);
      expect(cachedFile(ios).existsSync(), isTrue);
      expect(cachedFile(android).existsSync(), isFalse);
      expect(server.requests, hasLength(1));
      expect(server.requests.single, contains(ios.flatName));
      expect(result.output, contains('1 requested'));
    });

    test('--only is repeatable', () async {
      final result = await run(
        base('ok', ['--only', ios.logicalName, '--only', android.logicalName]),
      );
      expect(result.code, exitOk, reason: result.output);
      expect(server.requests, hasLength(2));
    });

    test('--only rejects a name the manifest does not have', () async {
      final result = await run(base('ok', ['--only', 'no/such.so']));
      expect(result.code, exitUsage);
      expect(result.output, contains('the manifest lists:'));
      expect(result.output, contains(android.logicalName));
      expect(server.requests, isEmpty);
    });
  });

  group('verification failures', () {
    test(
      'substituted bytes: reported with both digests, nothing cached',
      () async {
        final wrong = List<int>.filled(android.size, 0xAB);
        server.publishPrimaryBody(android, wrong);

        final result = await run(base('ok', ['--only', android.logicalName]));
        expect(result.code, exitFetchFailed);
        expect(result.output, contains('failed    ${android.logicalName}'));
        expect(result.output, contains('expected sha256 ${android.sha256Hex}'));
        expect(result.output, contains('found    sha256 '));
        expect(
          result.output,
          isNot(contains('found    sha256 ${android.sha256Hex}')),
        );
        expect(cachedFile(android).existsSync(), isFalse);
        expect(strayTempFiles(), isEmpty);
      },
    );

    test('a truncated body fails on both the digest and the size', () async {
      server.publishPrimaryBody(android, android.bytes.sublist(0, 100));

      final result = await run(base('ok', ['--only', android.logicalName]));
      expect(result.code, exitFetchFailed);
      expect(
        result.output,
        contains('expected sha256 ${android.sha256Hex} size ${android.size}'),
      );
      expect(result.output, contains('size 100'));
      expect(cachedFile(android).existsSync(), isFalse);
    });

    test('right digest, wrong recorded size: still refused', () async {
      writeManifest(
        'badsize',
        fakeManifestJson(
          setId: _setId,
          upstreamTag: _tag,
          primary: server.primaryBase,
          mirror: null,
          artifacts: [android],
          overrideRecord: (a) => <String, Object?>{
            'sha256': a.sha256Hex,
            'size': a.size + 1,
            'asset_name': a.assetName(_setId),
            'logical_name': a.logicalName,
          },
        ),
      );

      final result = await run(base('badsize'));
      expect(result.code, exitFetchFailed);
      expect(
        result.output,
        contains(
          'expected sha256 ${android.sha256Hex} size ${android.size + 1}',
        ),
      );
      expect(result.output, contains('size ${android.size}'));
      expect(cachedFile(android).existsSync(), isFalse);
    });

    test('a mismatch does not fall through to the mirror', () async {
      server.publishPrimaryBody(android, List<int>.filled(android.size, 9));

      final result = await run(
        base('mirrored', ['--only', android.logicalName]),
      );
      expect(result.code, exitFetchFailed);
      expect(
        server.requests.where((p) => p.startsWith('/mirror')),
        isEmpty,
        reason:
            'DECISION-14 §3.1 leaves no "continue anyway" path; a location '
            'that served the wrong bytes has answered the question',
      );
    });

    test('the first failure stops the run unless --keep-going', () async {
      server.publishPrimaryBody(android, List<int>.filled(android.size, 9));
      server.publishPrimaryBody(ios, List<int>.filled(ios.size, 9));

      final stopping = await run(base('ok'));
      expect(stopping.code, exitFetchFailed);
      expect(stopping.output, contains('1 not attempted'));

      cache.deleteSync(recursive: true);
      cache.createSync(recursive: true);

      final keepGoing = await run(base('ok', ['--keep-going']));
      expect(keepGoing.code, exitFetchFailed);
      expect(keepGoing.output, contains('failed    ${android.logicalName}'));
      expect(keepGoing.output, contains('failed    ${ios.logicalName}'));
      expect(keepGoing.output, contains('2 failed'));
      expect(keepGoing.output, isNot(contains('not attempted')));
    });
  });

  group('the mirror', () {
    test(
      'a 404 on the primary falls back when a mirror is configured',
      () async {
        server.withdrawPrimary(android);

        final result = await run(
          base('mirrored', ['--only', android.logicalName]),
        );
        expect(result.code, exitOk, reason: result.output);
        expect(result.output, contains('<- ${server.mirrorBase}'));
        expect(cachedFile(android).readAsBytesSync(), android.bytes);
        expect(server.requests, hasLength(2));
        expect(server.requests.first, startsWith('/releases'));
        expect(server.requests.last, startsWith('/mirror'));
      },
    );

    test('the mirror URL uses the hierarchical template', () async {
      server.withdrawPrimary(android);
      await run(base('mirrored', ['--only', android.logicalName]));
      expect(
        server.requests.last,
        '/mirror/$_setId/${android.sha256Hex}/${android.logicalName}',
      );
    });

    test('a 404 with no mirror fails and says the mirror is null', () async {
      server.withdrawPrimary(android);

      final result = await run(base('ok', ['--only', android.logicalName]));
      expect(result.code, exitFetchFailed);
      expect(result.output, contains('HTTP 404'));
      expect(result.output, contains('retention.mirror is null'));
      expect(server.requests, hasLength(1));
      expect(cachedFile(android).existsSync(), isFalse);
    });

    test('a 404 at both locations names both URLs', () async {
      server.withdrawPrimary(android);
      server.withdrawMirror(android);

      final result = await run(
        base('mirrored', ['--only', android.logicalName]),
      );
      expect(result.code, exitFetchFailed);
      expect(result.output, contains('primary ${server.primaryBase}/'));
      expect(result.output, contains('mirror ${server.mirrorBase}/'));
      expect(server.requests, hasLength(2));
    });
  });

  group('the cache', () {
    test('a corrupt entry is deleted and re-fetched', () async {
      final file = cachedFile(android);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(List<int>.filled(android.size, 0));

      final result = await run(base('ok', ['--only', android.logicalName]));
      expect(result.code, exitOk, reason: result.output);
      expect(result.output, contains('corrupt   ${android.logicalName}'));
      expect(result.output, contains('cache entry deleted'));
      expect(result.output, contains('fetched   ${android.logicalName}'));
      expect(file.readAsBytesSync(), android.bytes);
      expect(server.requests, hasLength(1));
    });

    test('an entry of the right size but the wrong bytes is corrupt', () async {
      final file = cachedFile(android);
      file.parent.createSync(recursive: true);
      final flipped = List<int>.of(android.bytes);
      flipped[0] = flipped[0] ^ 0xFF;
      file.writeAsBytesSync(flipped);

      final result = await run(base('ok', ['--only', android.logicalName]));
      expect(result.code, exitOk, reason: result.output);
      expect(result.output, contains('cache entry deleted'));
      expect(file.readAsBytesSync(), android.bytes);
    });

    test(
      'WCF_ARTIFACT_DIR is the default when no --cache-dir is given',
      () async {
        final lines = <String>[];
        final envCache = '${root.path}/env-cache';
        final code = await runFetchArtifacts(
          [
            '--manifest',
            manifestPath('ok'),
            '--allow-insecure-loopback',
            '--only',
            android.logicalName,
          ],
          scriptDir: scriptDir,
          environment: <String, String>{
            'HOME': root.path,
            'WCF_ARTIFACT_DIR': envCache,
          },
          out: lines.add,
          err: lines.add,
        );
        expect(code, exitOk, reason: lines.join('\n'));
        expect(File('$envCache/${android.logicalName}').existsSync(), isTrue);
      },
    );

    test(
      'the default falls back to ~/.cache/wallet_core_flutter/<tag>',
      () async {
        final lines = <String>[];
        final code = await runFetchArtifacts(
          [
            '--manifest',
            manifestPath('ok'),
            '--allow-insecure-loopback',
            '--only',
            android.logicalName,
          ],
          scriptDir: scriptDir,
          environment: <String, String>{'HOME': root.path},
          out: lines.add,
          err: lines.add,
        );
        expect(code, exitOk, reason: lines.join('\n'));
        expect(
          File(
            '${root.path}/.cache/wallet_core_flutter/$_tag/'
            '${android.logicalName}',
          ).existsSync(),
          isTrue,
        );
      },
    );
  });

  group('--offline', () {
    test('succeeds from a warm cache without opening a socket', () async {
      expect((await run(base('ok'))).code, exitOk);
      final warmed = server.requests.length;

      final offline = await run(base('ok', ['--offline']));
      expect(offline.code, exitOk, reason: offline.output);
      expect(offline.output, contains('2 already verified in the cache'));
      expect(server.requests, hasLength(warmed));
    });

    test(
      'fails from a cold cache, naming what is missing, with no request',
      () async {
        final result = await run(base('ok', ['--offline']));
        expect(result.code, exitFetchFailed);
        expect(result.output, contains('offline: not in the cache'));
        expect(result.output, contains('${cache.path}/${android.logicalName}'));
        expect(
          server.requests,
          isEmpty,
          reason: '--offline must never open a socket',
        );
      },
    );

    test('a corrupt entry is still deleted, and offline then fails', () async {
      final file = cachedFile(android);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(List<int>.filled(android.size, 0));

      final result = await run(
        base('ok', ['--offline', '--only', android.logicalName]),
      );
      expect(result.code, exitFetchFailed);
      expect(result.output, contains('cache entry deleted'));
      expect(file.existsSync(), isFalse);
      expect(server.requests, isEmpty);
    });
  });

  group('--vendored', () {
    void vendor(FakeArtifact artifact, List<int> bytes) {
      final file = File('${vendored.path}/${artifact.logicalName}')
        ..parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes);
    }

    test('verifies and copies, with no request', () async {
      vendor(android, android.bytes);

      final result = await run(
        base('ok', [
          '--vendored',
          vendored.path,
          '--only',
          android.logicalName,
        ]),
      );
      expect(result.code, exitOk, reason: result.output);
      expect(result.output, contains('vendored  ${android.logicalName}'));
      expect(cachedFile(android).readAsBytesSync(), android.bytes);
      expect(server.requests, isEmpty);
    });

    test('rejects a bad vendored file and does not copy it', () async {
      vendor(android, List<int>.filled(android.size, 0x7F));

      final result = await run(
        base('ok', [
          '--vendored',
          vendored.path,
          '--offline',
          '--only',
          android.logicalName,
        ]),
      );
      expect(result.code, exitFetchFailed);
      expect(result.output, contains('it was not copied'));
      expect(result.output, contains('expected sha256 ${android.sha256Hex}'));
      expect(cachedFile(android).existsSync(), isFalse);
      expect(strayTempFiles(), isEmpty);
      expect(server.requests, isEmpty);
    });

    test(
      'falls back to the network for an artifact it does not hold',
      () async {
        vendor(android, android.bytes);

        final result = await run(base('ok', ['--vendored', vendored.path]));
        expect(result.code, exitOk, reason: result.output);
        expect(result.output, contains('vendored  ${android.logicalName}'));
        expect(result.output, contains('fetched   ${ios.logicalName}'));
        expect(server.requests, hasLength(1));
      },
    );

    test('with --offline, a missing vendored file names both places', () async {
      final result = await run(
        base('ok', [
          '--vendored',
          vendored.path,
          '--offline',
          '--only',
          ios.logicalName,
        ]),
      );
      expect(result.code, exitFetchFailed);
      expect(result.output, contains('not in the cache'));
      expect(result.output, contains('not in the vendored directory'));
      expect(server.requests, isEmpty);
    });
  });

  group('redirects', () {
    test('a 302 to another path is followed and verified', () async {
      server.serveAt('/objects/blob', android.bytes);
      server.redirectPrimary(android, '${server.origin}/objects/blob');

      final result = await run(base('ok', ['--only', android.logicalName]));
      expect(result.code, exitOk, reason: result.output);
      expect(server.requests, [
        '/releases/${android.assetName(_setId)}',
        '/objects/blob',
      ]);
      expect(cachedFile(android).readAsBytesSync(), android.bytes);
    });

    test(
      'a 302 whose target serves other bytes still fails verification',
      () async {
        server.serveAt('/objects/blob', List<int>.filled(android.size, 3));
        server.redirectPrimary(android, '${server.origin}/objects/blob');

        final result = await run(base('ok', ['--only', android.logicalName]));
        expect(result.code, exitFetchFailed);
        expect(result.output, contains('expected sha256 ${android.sha256Hex}'));
        expect(cachedFile(android).existsSync(), isFalse);
      },
    );

    test('a 302 off loopback is refused rather than followed', () async {
      server.redirectPrimary(android, 'http://evil.invalid/blob');

      final result = await run(base('ok', ['--only', android.logicalName]));
      expect(result.code, exitFetchFailed);
      expect(result.output, contains('not a loopback host'));
      expect(cachedFile(android).existsSync(), isFalse);
    });

    test('a redirect loop stops at the hop limit', () async {
      server.redirectPrimary(android, '${server.origin}/loop');
      // /loop is not published, so it 404s; the loop limit is exercised by
      // pointing the asset at itself instead.
      server.redirectPrimary(
        android,
        '${server.origin}/releases/${android.assetName(_setId)}',
      );

      final result = await run(base('ok', ['--only', android.logicalName]));
      expect(result.code, exitFetchFailed);
      expect(result.output, contains('more than $maxRedirects redirects'));
      expect(server.requests, hasLength(maxRedirects + 1));
    });
  });

  group('the manifest gate at run time', () {
    test('a placeholder manifest is refused before any socket', () async {
      writeManifest(
        'placeholder',
        fakeManifestJson(
          setId: 'TBD-T1.2',
          upstreamTag: _tag,
          primary: 'TBD-T0.11',
          mirror: null,
          artifacts: [android],
          overrideRecord: (_) => <String, Object?>{
            'sha256': 'TBD-T1.2',
            'size': 0,
          },
        ),
      );

      final result = await run(base('placeholder'));
      expect(result.code, exitManifestBlocked);
      expect(result.output, contains('cannot be fetched from'));
      expect(result.output, contains('retention.primary'));
      expect(result.output, contains('(T0.11)'));
      expect(result.output, contains('(T1.2)'));
      expect(result.output, contains('Nothing was downloaded'));
      expect(server.requests, isEmpty);
    });

    test('a plain-http primary without the override is refused', () async {
      final result = await run([
        '--manifest',
        manifestPath('ok'),
        '--cache-dir',
        cache.path,
      ]);
      expect(result.code, exitManifestBlocked);
      expect(result.output, contains('https'));
      expect(server.requests, isEmpty);
    });

    test('an asset_name that contradicts its own record is refused', () async {
      writeManifest(
        'contradictory',
        fakeManifestJson(
          setId: _setId,
          upstreamTag: _tag,
          primary: server.primaryBase,
          mirror: null,
          artifacts: [android],
          overrideRecord: (a) => <String, Object?>{
            'sha256': a.sha256Hex,
            'size': a.size,
            'asset_name': '${_setId}__${'c' * 64}__${a.flatName}',
            'logical_name': a.logicalName,
          },
        ),
      );

      final result = await run(base('contradictory'));
      expect(result.code, exitManifestBlocked);
      expect(result.output, contains('carries digest ${'c' * 64}'));
      expect(server.requests, isEmpty);
    });

    test('a manifest that is not there is a blocked manifest', () async {
      final result = await run(base('absent'));
      expect(result.code, exitManifestBlocked);
      expect(result.output, contains('no manifest at'));
    });

    test('a manifest that is not JSON', () async {
      writeManifest('garbage', 'not a manifest');
      final result = await run(base('garbage'));
      expect(result.code, exitManifestBlocked);
      expect(result.output, contains('not valid JSON'));
    });
  });

  group('--dry-run', () {
    test('prints URLs, cache path, and state, and makes no request', () async {
      final result = await run(base('mirrored', ['--dry-run']));
      expect(result.code, exitOk, reason: result.output);
      expect(result.output, contains('manifest gate: passed'));
      expect(
        result.output,
        contains('primary: ${server.primaryBase}/${android.assetName(_setId)}'),
      );
      expect(
        result.output,
        contains(
          'mirror:  ${server.mirrorBase}/$_setId/${android.sha256Hex}/'
          '${android.logicalName}',
        ),
      );
      expect(
        result.output,
        contains('cache:   ${cache.path}/${android.logicalName}'),
      );
      expect(result.output, contains('state:   missing'));
      expect(server.requests, isEmpty);
    });

    test('says "no mirror" when retention.mirror is null', () async {
      final result = await run(base('ok', ['--dry-run']));
      expect(result.output, contains('mirror:  no mirror'));
    });

    test('reports a verified and a corrupt cache entry', () async {
      expect(
        (await run(base('ok', ['--only', android.logicalName]))).code,
        exitOk,
      );
      final iosFile = cachedFile(ios)..parent.createSync(recursive: true);
      iosFile.writeAsBytesSync(List<int>.filled(ios.size, 1));

      final result = await run(base('ok', ['--dry-run']));
      expect(result.output, contains('state:   verified'));
      expect(result.output, contains('state:   corrupt'));
      expect(iosFile.existsSync(), isTrue, reason: 'a dry run changes nothing');
    });

    test('--print-urls is the same thing', () async {
      final dry = await run(base('ok', ['--dry-run']));
      final urls = await run(base('ok', ['--print-urls']));
      expect(urls.code, dry.code);
      expect(urls.output, dry.output);
    });

    test('exits 2 on a blocked manifest, still without a request', () async {
      writeManifest(
        'placeholder',
        fakeManifestJson(
          setId: 'TBD-T1.2',
          upstreamTag: _tag,
          primary: 'TBD-T0.11',
          mirror: null,
          artifacts: [android],
          overrideRecord: (_) => <String, Object?>{
            'sha256': 'TBD-T1.2',
            'size': 0,
          },
        ),
      );

      final result = await run(base('placeholder', ['--dry-run']));
      expect(result.code, exitManifestBlocked);
      expect(result.output, contains('manifest gate: BLOCKED'));
      expect(result.output, contains('unavailable'));
      expect(server.requests, isEmpty);
    });
  });

  group('a placeholder manifest', () {
    test(
      '--dry-run lists the blockers, exits 2, and opens no socket',
      () async {
        final placeholderFile = File(
          'test/fixtures/compat_manifest.placeholder.json',
        );
        final lines = <String>[];
        final code = await runFetchArtifacts(
          [
            '--dry-run',
            '--manifest',
            placeholderFile.absolute.path,
            '--cache-dir',
            cache.path,
          ],
          scriptDir: scriptDir,
          environment: <String, String>{'HOME': root.path},
          out: lines.add,
          err: lines.add,
        );
        final output = lines.join('\n');
        expect(code, exitManifestBlocked, reason: output);
        expect(output, contains('compat_manifest.placeholder.json'));
        expect(output, contains('retention.primary'));
        expect(output, contains('TBD-T0.11'));
        expect(output, contains('identity.artifact_set_id'));
        expect(output, contains('TBD-T1.2'));
        expect(output, contains('no mirror'));
        expect(output, contains('no request was made'));
        expect(server.requests, isEmpty);

        // Every artifact the placeholder manifest lists appears, whichever they are:
        // the map is a path grammar, not a fixed set (D0 finding F14).
        final manifest = jsonDecode(
          placeholderFile.readAsStringSync(),
        ) as Map<String, Object?>;
        final artifacts = manifest['artifacts']! as Map<String, Object?>;
        expect(artifacts, isNotEmpty);
        for (final key in artifacts.keys) {
          expect(output, contains(key));
        }
      },
    );

    test('a real run refuses it too, before any socket', () async {
      final placeholderFile = File(
        'test/fixtures/compat_manifest.placeholder.json',
      );
      final lines = <String>[];
      final code = await runFetchArtifacts(
        [
          '--manifest',
          placeholderFile.absolute.path,
          '--cache-dir',
          cache.path,
        ],
        scriptDir: scriptDir,
        environment: <String, String>{'HOME': root.path},
        out: lines.add,
        err: lines.add,
      );
      expect(code, exitManifestBlocked, reason: lines.join('\n'));
      expect(server.requests, isEmpty);
    });
  });

  group('the shipped manifest', () {
    test('--dry-run exits 0, mentions retention.primary, lists artifacts, and opens no socket', () async {
      final lines = <String>[];
      final code = await runFetchArtifacts(
        ['--dry-run', '--cache-dir', cache.path],
        scriptDir: scriptDir,
        environment: <String, String>{'HOME': root.path},
        out: lines.add,
        err: lines.add,
      );
      final output = lines.join('\n');
      expect(code, exitOk, reason: output);
      expect(server.requests, isEmpty);

      final manifestFile = File(
        '${Directory.current.path}/assets/compat_manifest.json',
      );
      final manifest =
          jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;

      final retention = manifest['retention'] as Map<String, Object?>;
      final primary = retention['primary'] as String;
      expect(output, contains(primary));

      final artifacts = manifest['artifacts']! as Map<String, Object?>;
      expect(artifacts, isNotEmpty);
      for (final key in artifacts.keys) {
        expect(output, contains(key));
      }
    });
  });

  group('the command line', () {
    test('--help prints the usage and exits 0', () async {
      final result = await run(['--help']);
      expect(result.code, exitOk);
      expect(result.output, contains('--allow-insecure-loopback'));
      expect(
        result.output,
        contains(
          'There is no flag that accepts a '
          'mismatch.',
        ),
      );
    });

    test('an unknown option is a usage error', () async {
      final result = await run(['--force']);
      expect(result.code, exitUsage);
      expect(result.output, contains('unknown option: --force'));
    });

    test('there is no flag that accepts a mismatch', () async {
      for (final attempt in const [
        '--skip-verify',
        '--no-verify',
        '--insecure',
        '--force',
        '--allow-mismatch',
        '--ignore-checksum',
      ]) {
        final result = await run(base('ok', [attempt]));
        expect(result.code, exitUsage, reason: '$attempt must not be accepted');
      }
      expect(server.requests, isEmpty);
    });
  });
}
