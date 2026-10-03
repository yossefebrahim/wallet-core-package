import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:wcf_tool_upstream/dist.dart';
import 'package:wcf_tool_upstream/hashing.dart';
import 'package:wcf_tool_upstream/paths.dart';

const _commit = 'd692ac27749d0c615e17c751b70ab4f0aa75c59b';

/// A miniature stand-in for `TrustWalletCore-<tag>.tar.xz`: the header subtree
/// the tool takes, plus the parts of the asset it must ignore. The real asset
/// is 54 MB compressed and lives outside the repository.
List<int> _fakeAsset({
  String twData = '// TWData.h\n',
  List<ArchiveFile> extra = const [],
}) {
  final archive = Archive()
    // The real asset carries its own root as a `./` directory entry.
    ..add(ArchiveFile.directory('./'))
    ..add(ArchiveFile.directory('./include/'))
    ..add(ArchiveFile.directory('./include/TrustWalletCore/'))
    ..add(ArchiveFile.string('./License', 'Apache License\n'))
    ..add(ArchiveFile.string('./include/TrustWalletCore/TWData.h', twData))
    ..add(
      ArchiveFile.string(
        './include/TrustWalletCore/TWCoinType.h',
        '// TWCoinType.h\n',
      ),
    )
    ..add(ArchiveFile.string('./Sources/Wallet.swift', 'let x = 1\n'))
    ..add(
      ArchiveFile.string(
        './WalletCoreCommon.xcframework/Info.plist',
        '<plist/>\n',
      ),
    );
  for (final file in extra) {
    archive.add(file);
  }
  return XZEncoder().encodeBytes(TarEncoder().encodeBytes(archive));
}

void main() {
  group('releaseAssetUrl', () {
    test('builds the pinned release-asset URL', () {
      expect(
        releaseAssetUrl(repo: 'trustwallet/wallet-core', tag: '4.8.0'),
        equals(
          'https://github.com/trustwallet/wallet-core/releases/download/'
          '4.8.0/TrustWalletCore-4.8.0.tar.xz',
        ),
      );
    });

    test('is a pure function of the two manifest fields', () {
      expect(
        releaseAssetUrl(repo: 'a/b', tag: 'v1'),
        equals(
          'https://github.com/a/b/releases/download/v1/'
          'TrustWalletCore-v1.tar.xz',
        ),
      );
      expect(
        releaseAssetUrl(repo: 'trustwallet/wallet-core', tag: '4.8.0'),
        equals(releaseAssetUrl(repo: 'trustwallet/wallet-core', tag: '4.8.0')),
      );
    });

    test('rejects a repo that is not "<owner>/<name>"', () {
      for (final repo in <String>[
        'wallet-core',
        'a/b/c',
        '../../etc',
        'a/b?x=1',
        '',
      ]) {
        expect(
          () => releaseAssetUrl(repo: repo, tag: '4.8.0'),
          throwsA(isA<ArgumentError>()),
          reason: repo,
        );
      }
    });

    test('rejects a tag that could reshape the URL', () {
      for (final tag in <String>['', '../4.8.0', 'a/b', '%2e%2e']) {
        expect(
          () => releaseAssetUrl(repo: 'trustwallet/wallet-core', tag: tag),
          throwsA(isA<ArgumentError>()),
          reason: tag,
        );
      }
    });
  });

  group('distArchiveName', () {
    test('is the asset name upstream publishes', () {
      expect(
        distArchiveName(tag: '4.8.0'),
        equals('TrustWalletCore-4.8.0.tar.xz'),
      );
    });
  });

  group('extractDistHeaders', () {
    late Directory work;
    late File asset;
    late Directory destination;

    setUp(() {
      work = Directory.systemTemp.createTempSync('wcf-dist-test-');
      asset = File('${work.path}/TrustWalletCore-4.8.0.tar.xz')
        ..writeAsBytesSync(_fakeAsset());
      destination = Directory('${work.path}/third_party/wallet-core-dist');
    });

    tearDown(() => work.deleteSync(recursive: true));

    DistHeaders run({File? from}) => extractDistHeaders(
      archiveFile: from ?? asset,
      destination: destination,
      tag: '4.8.0',
      commit: _commit,
    );

    test('writes the header subtree and nothing else', () {
      final headers = run();
      expect(
        File(
          '${destination.path}/include/TrustWalletCore/TWData.h',
        ).readAsStringSync(),
        equals('// TWData.h\n'),
      );
      expect(
        File(
          '${destination.path}/include/TrustWalletCore/TWCoinType.h',
        ).existsSync(),
        isTrue,
      );
      expect(Directory('${destination.path}/Sources').existsSync(), isFalse);
      expect(File('${destination.path}/License').existsSync(), isFalse);
      expect(headers.fileCount, equals(2));
    });

    test('records the provenance of the header set', () {
      final headers = run();
      expect(headers.archiveName, equals('TrustWalletCore-4.8.0.tar.xz'));
      expect(headers.archiveSha256, equals(sha256OfFile(asset)));
      expect(headers.tag, equals('4.8.0'));
      expect(headers.commit, equals(_commit));
      expect(headers.dirSha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(
        headers.dirSha256,
        equals(
          hashDirectory(
            Directory('${destination.path}/include/TrustWalletCore'),
          ).sha256,
        ),
      );
    });

    test('writes the provenance record next to the headers', () {
      final headers = run();
      final file = File('${destination.path}/dist_provenance.json');
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), endsWith('\n'));
      expect(jsonDecode(file.readAsStringSync()), equals(headers.toJson()));
      final read = readDistProvenance(destination);
      expect(read.toJson(), equals(headers.toJson()));
    });

    test('readDistProvenance explains how to place the headers', () {
      expect(
        () => readDistProvenance(Directory('${work.path}/absent')),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('upstream:fetch'),
          ),
        ),
      );
    });

    test('is idempotent and empties the destination first', () {
      final first = run();
      final stale = File('${destination.path}/include/TrustWalletCore/Old.h')
        ..writeAsStringSync('// left over from an earlier pin\n');
      expect(stale.existsSync(), isTrue);

      final second = run();
      expect(stale.existsSync(), isFalse);
      expect(second.fileCount, equals(first.fileCount));
      expect(second.dirSha256, equals(first.dirSha256));
    });

    test('a changed header changes the directory digest', () {
      final first = run();
      asset.writeAsBytesSync(_fakeAsset(twData: '// TWData.h (edited)\n'));
      final second = run();
      expect(second.dirSha256, isNot(equals(first.dirSha256)));
      expect(second.archiveSha256, isNot(equals(first.archiveSha256)));
    });

    test('rejects an archive with no header subtree', () {
      final other = File('${work.path}/other.tar.xz')
        ..writeAsBytesSync(
          XZEncoder().encodeBytes(
            TarEncoder().encodeBytes(
              Archive()..add(ArchiveFile.string('./README.md', 'hi')),
            ),
          ),
        );
      expect(() => run(from: other), throwsA(isA<ArgumentError>()));
    });

    test('rejects a traversing entry name before writing anything', () {
      final hostile = File('${work.path}/hostile.tar.xz')
        ..writeAsBytesSync(
          _fakeAsset(
            extra: [
              ArchiveFile.string(
                './include/TrustWalletCore/../../../../evil.h',
                '// pwned\n',
              ),
            ],
          ),
        );
      expect(() => run(from: hostile), throwsA(isA<UnsafeArchiveEntry>()));
      expect(File('${work.path}/../../../../evil.h').existsSync(), isFalse);
    });

    test('rejects a symlink that escapes the extraction root', () {
      final hostile = File('${work.path}/symlink.tar.xz')
        ..writeAsBytesSync(
          _fakeAsset(
            extra: [
              ArchiveFile.symlink(
                './include/TrustWalletCore/escape.h',
                '../../../../../etc/passwd',
              ),
            ],
          ),
        );
      expect(() => run(from: hostile), throwsA(isA<UnsafeArchiveEntry>()));
    });
  });
}
