import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
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

  FetchOptions options({String? commit = _commit, String? from}) =>
      FetchOptions(
        from: from ?? archive.path,
        manifestPath: manifest.path,
        destination: destination,
        noticesPath: notices.path,
        commit: commit,
      );

  Future<FetchResult> run({String? commit = _commit}) =>
      runFetch(options(commit: commit), log: StringBuffer());

  test('extracts the tree, strips the wrapper directory', () async {
    final result = await run();
    expect(result.extraction.strippedTopLevel, equals('wallet-core-4.8.0'));
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

  group('FetchOptions.parse', () {
    test('defaults to the repository-root paths', () {
      final parsed = FetchOptions.parse(const []);
      expect(parsed.manifestPath, equals('compat_manifest.json'));
      expect(parsed.destination, equals(defaultDestination));
      expect(parsed.noticesPath, equals('THIRD_PARTY_NOTICES.md'));
      expect(parsed.from, isNull);
      expect(parsed.commit, isNull);
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
      ]);
      expect(parsed.from, equals('/tmp/a.tar.gz'));
      expect(parsed.commit, equals(_commit));
      expect(parsed.manifestPath, equals('m.json'));
      expect(parsed.destination, equals('out'));
      expect(parsed.noticesPath, equals('n.md'));
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
