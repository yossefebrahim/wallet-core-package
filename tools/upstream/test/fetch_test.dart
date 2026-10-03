import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:wcf_tool_upstream/dist.dart';
import 'package:wcf_tool_upstream/fetch.dart';
import 'package:wcf_tool_upstream/manifest_edit.dart';

const _commit = 'd692ac27749d0c615e17c751b70ab4f0aa75c59b';
const _license = 'Apache License\n\n   Version 2.0, January 2004\n';
const _thirdParty = 'Third-party components\n\n- secp256k1 (MIT)\n';

/// A miniature stand-in for the upstream tree: the three inputs the schema
/// digests cover, plus the two licence files. The real archive is 16 MB and
/// lives outside the repository, so the end-to-end behaviour is exercised on a
/// tree this test builds itself.
List<int> _fakeSourceArchive({String registry = '{"coins":[]}'}) {
  final archive = Archive()
    ..add(ArchiveFile.string('wallet-core-4.8.0/registry.json', registry))
    ..add(
      ArchiveFile.string(
        'wallet-core-4.8.0/include/TrustWalletCore/TWCoinType.h',
        '// TWCoinType.h\n',
      ),
    )
    ..add(
      ArchiveFile.string(
        'wallet-core-4.8.0/include/TrustWalletCore/TWData.h',
        '// TWData.h\n',
      ),
    )
    ..add(
      ArchiveFile.string(
        'wallet-core-4.8.0/src/proto/Ethereum.proto',
        'syntax = "proto3";\n',
      ),
    )
    ..add(ArchiveFile.string('wallet-core-4.8.0/LICENSE', _license))
    ..add(
      ArchiveFile.string(
        'wallet-core-4.8.0/LICENSE-3RD-PARTY.txt',
        _thirdParty,
      ),
    );
  return GZipEncoder().encodeBytes(TarEncoder().encodeBytes(archive));
}

void main() {
  late Directory work;
  late File manifest;
  late File notices;
  late File archive;
  late String destination;

  setUp(() {
    work = Directory.systemTemp.createTempSync('wcf-fetch-');
    manifest = File(
      '${work.path}/compat_manifest.json',
    )..writeAsStringSync(File('../../compat_manifest.json').readAsStringSync());
    notices = File('${work.path}/THIRD_PARTY_NOTICES.md');
    archive = File('${work.path}/wallet-core-4.8.0.tar.gz')
      ..writeAsBytesSync(_fakeSourceArchive());
    destination = '${work.path}/third_party/wallet-core';
  });

  tearDown(() => work.deleteSync(recursive: true));

  FetchOptions options({
    String? commit = _commit,
    String? from,
    String? fromDist,
    bool distOnly = false,
  }) => FetchOptions(
    from: from ?? archive.path,
    manifestPath: manifest.path,
    destination: destination,
    noticesPath: notices.path,
    commit: commit,
    distOnly: distOnly,
    fromDist: fromDist,
    distDestination: '${work.path}/third_party/wallet-core-dist',
  );

  Future<FetchResult> run({String? commit = _commit}) =>
      runFetch(options(commit: commit), log: StringBuffer());

  test('extracts the tree, strips the wrapper directory', () async {
    final result = await run();
    expect(result.extraction!.strippedTopLevel, equals('wallet-core-4.8.0'));
    expect(File('$destination/registry.json').existsSync(), isTrue);
    expect(
      File('$destination/include/TrustWalletCore/TWCoinType.h').existsSync(),
      isTrue,
    );
  });

  test('fills upstream.commit and the three schemas digests', () async {
    final result = await run();
    final written =
        jsonDecode(manifest.readAsStringSync()) as Map<String, Object?>;
    final upstream = written['upstream'] as Map<String, Object?>;
    final schemas = written['schemas'] as Map<String, Object?>;

    expect(upstream['commit'], equals(_commit));
    expect(schemas['headers_sha'], equals(result.headersSha));
    expect(schemas['proto_dir_sha'], equals(result.protoDirSha));
    expect(schemas['registry_json_sha'], equals(result.registryJsonSha));
    for (final value in schemas.values) {
      expect(value, matches(RegExp(r'^[0-9a-f]{64}$')));
    }
  });

  test('fills identity.upstream_commit from the same pin', () async {
    await run();
    final written =
        jsonDecode(manifest.readAsStringSync()) as Map<String, Object?>;
    final identity = written['identity'] as Map<String, Object?>;
    expect(identity['upstream_commit'], equals(_commit));
  });

  test('leaves every other manifest field alone', () async {
    final before =
        jsonDecode(manifest.readAsStringSync()) as Map<String, Object?>;
    await run();
    final after =
        jsonDecode(manifest.readAsStringSync()) as Map<String, Object?>;
    expect(after['artifacts'], equals(before['artifacts']));
    expect(after['generators'], equals(before['generators']));
    expect(after['toolchain'], equals(before['toolchain']));
    expect(after['packages'], equals(before['packages']));
    expect(after['release_set'], equals(before['release_set']));
  });

  test('is idempotent: a second run changes no byte of either file', () async {
    final first = await run();
    expect(first.manifestChanged, isTrue);
    expect(first.noticesChanged, isTrue);
    final manifestBytes = manifest.readAsBytesSync();
    final noticesBytes = notices.readAsBytesSync();

    final second = await run();
    expect(second.manifestChanged, isFalse);
    expect(second.noticesChanged, isFalse);
    expect(manifest.readAsBytesSync(), equals(manifestBytes));
    expect(notices.readAsBytesSync(), equals(noticesBytes));
    expect(second.headersSha, equals(first.headersSha));
    expect(second.protoDirSha, equals(first.protoDirSha));
    expect(second.registryJsonSha, equals(first.registryJsonSha));
  });

  test('verifies the pin on a later run instead of repinning', () async {
    await run();
    await expectLater(
      run(commit: '0000000000000000000000000000000000000000'),
      throwsA(isA<CommitPinMismatch>()),
    );
    await expectLater(run(commit: null), completes);
  });

  test('a changed input changes the digest it belongs to', () async {
    final first = await run();
    archive.writeAsBytesSync(_fakeSourceArchive(registry: '{"coins":[1]}'));
    final second = await run();
    expect(second.registryJsonSha, isNot(equals(first.registryJsonSha)));
    expect(second.headersSha, equals(first.headersSha));
    expect(second.protoDirSha, equals(first.protoDirSha));
  });

  test('copies both upstream licence files verbatim', () async {
    await run();
    final text = notices.readAsStringSync();
    expect(text, contains(_license));
    expect(text, contains(_thirdParty));
    expect(text, contains('`LICENSE-3RD-PARTY.txt`'));
    expect(text, contains(_commit));
  });

  test('refuses an archive that is not the upstream source tree', () async {
    archive.writeAsBytesSync(
      GZipEncoder().encodeBytes(
        TarEncoder().encodeBytes(
          Archive()..add(ArchiveFile.string('other-1.0/README.md', 'hi')),
        ),
      ),
    );
    await expectLater(
      run(),
      throwsA(
        isA<UsageError>().having(
          (e) => e.message,
          'message',
          contains('missing'),
        ),
      ),
    );
  });

  test('refuses a missing archive', () async {
    await expectLater(
      runFetch(
        options(from: '${work.path}/absent.tar.gz'),
        log: StringBuffer(),
      ),
      throwsA(isA<UsageError>()),
    );
  });

  group('--from-dist', () {
    // The release asset ships 143 public headers to the git tree's 67; ffigen
    // (T1.3) runs over the asset's set, so `upstream:fetch` can place it.
    late File asset;

    setUp(() {
      asset = File('${work.path}/TrustWalletCore-4.8.0.tar.xz')
        ..writeAsBytesSync(
          XZEncoder().encodeBytes(
            TarEncoder().encodeBytes(
              Archive()
                ..add(
                  ArchiveFile.string(
                    './include/TrustWalletCore/TWData.h',
                    '// TWData.h (from the asset)\n',
                  ),
                )
                ..add(
                  ArchiveFile.string('./Sources/Wallet.swift', 'let x=1\n'),
                ),
            ),
          ),
        );
    });

    test('is off unless asked for', () async {
      final result = await run();
      expect(result.distHeaders, isNull);
      expect(
        Directory('${work.path}/third_party/wallet-core-dist').existsSync(),
        isFalse,
      );
    });

    test('places the asset headers beside the source tree', () async {
      final result = await runFetch(
        options(fromDist: asset.path),
        log: StringBuffer(),
      );
      final dist = result.distHeaders;
      expect(dist, isNotNull);
      expect(dist!.archiveName, equals('TrustWalletCore-4.8.0.tar.xz'));
      expect(dist.tag, equals('4.8.0'));
      expect(dist.commit, equals(_commit));
      expect(dist.fileCount, equals(1));
      expect(
        File(
          '${work.path}/third_party/wallet-core-dist/include/TrustWalletCore/'
          'TWData.h',
        ).readAsStringSync(),
        equals('// TWData.h (from the asset)\n'),
      );
      // The source tree is still placed, and still the thing schemas describes.
      expect(
        File('$destination/include/TrustWalletCore/TWData.h').existsSync(),
        isTrue,
      );
    });

    test('leaves schemas.headers_sha describing the git tree', () async {
      final withoutDist = await run();
      final gitTreeHeadersSha = withoutDist.headersSha;

      final result = await runFetch(
        options(fromDist: asset.path),
        log: StringBuffer(),
      );
      final schemas =
          (jsonDecode(manifest.readAsStringSync())
                  as Map<String, Object?>)['schemas']!
              as Map<String, Object?>;
      expect(schemas['headers_sha'], equals(gitTreeHeadersSha));
      expect(result.headersSha, equals(gitTreeHeadersSha));
      expect(result.distHeaders!.dirSha256, isNot(equals(gitTreeHeadersSha)));
    });

    test('refuses a missing asset', () async {
      await expectLater(
        runFetch(
          options(fromDist: '${work.path}/absent.tar.xz'),
          log: StringBuffer(),
        ),
        throwsA(isA<UsageError>()),
      );
    });

    test(
      '--dist-only touches neither the source tree nor the manifest',
      () async {
        final before = manifest.readAsBytesSync();
        final result = await runFetch(
          options(fromDist: asset.path, distOnly: true),
          log: StringBuffer(),
        );

        expect(result.distHeaders, isNotNull);
        expect(result.extraction, isNull);
        expect(result.headersSha, isNull);
        expect(result.manifestChanged, isNull);
        expect(
          File(
            '${work.path}/third_party/wallet-core-dist/include/TrustWalletCore/'
            'TWData.h',
          ).existsSync(),
          isTrue,
        );
        expect(Directory(destination).existsSync(), isFalse);
        expect(notices.existsSync(), isFalse);
        expect(manifest.readAsBytesSync(), equals(before));
      },
    );

    test('--dist-only still verifies the commit pin', () async {
      await expectLater(
        runFetch(
          options(
            fromDist: asset.path,
            distOnly: true,
            commit: '0000000000000000000000000000000000000000',
          ),
          log: StringBuffer(),
        ),
        throwsA(isA<CommitPinMismatch>()),
      );
    });
  });

  group('FetchOptions.parse', () {
    test('defaults to the repository-root paths', () {
      final parsed = FetchOptions.parse(const []);
      expect(parsed.manifestPath, equals('compat_manifest.json'));
      expect(parsed.destination, equals(defaultDestination));
      expect(parsed.noticesPath, equals('THIRD_PARTY_NOTICES.md'));
      expect(parsed.from, isNull);
      expect(parsed.commit, isNull);
      expect(parsed.dist, isFalse);
      expect(parsed.distOnly, isFalse);
      expect(parsed.fromDist, isNull);
      expect(parsed.wantsDist, isFalse);
      expect(parsed.distDestination, equals(defaultDistDestination));
    });

    test('reads every flag', () {
      final parsed = FetchOptions.parse([
        '--from',
        '/tmp/a.tar.gz',
        '--commit',
        _commit,
        '--manifest',
        'm.json',
        '--dest',
        'out',
        '--notices',
        'n.md',
        '--from-dist',
        '/tmp/TrustWalletCore-4.8.0.tar.xz',
        '--dist-dest',
        'dist-out',
      ]);
      expect(parsed.from, equals('/tmp/a.tar.gz'));
      expect(parsed.commit, equals(_commit));
      expect(parsed.manifestPath, equals('m.json'));
      expect(parsed.destination, equals('out'));
      expect(parsed.noticesPath, equals('n.md'));
      expect(parsed.fromDist, equals('/tmp/TrustWalletCore-4.8.0.tar.xz'));
      expect(parsed.distDestination, equals('dist-out'));
    });

    test('--dist is a flag; --from-dist and --dist-only imply it', () {
      expect(FetchOptions.parse(['--dist']).dist, isTrue);
      expect(FetchOptions.parse(['--dist']).wantsDist, isTrue);
      final fromDist = FetchOptions.parse(['--from-dist', '/tmp/a.tar.xz']);
      expect(fromDist.dist, isFalse);
      expect(fromDist.wantsDist, isTrue);
      final distOnly = FetchOptions.parse(['--dist-only']);
      expect(distOnly.distOnly, isTrue);
      expect(distOnly.wantsDist, isTrue);
      expect(
        () => FetchOptions.parse(['--from-dist']),
        throwsA(isA<UsageError>()),
      );
    });

    test('rejects an unknown flag and a flag without a value', () {
      expect(() => FetchOptions.parse(['--nope']), throwsA(isA<UsageError>()));
      expect(() => FetchOptions.parse(['--from']), throwsA(isA<UsageError>()));
    });

    test('treats --help as a usage request', () {
      expect(
        () => FetchOptions.parse(['--help']),
        throwsA(
          isA<UsageError>().having(
            (e) => e.message,
            'message',
            equals(FetchOptions.usage),
          ),
        ),
      );
    });
  });
}
