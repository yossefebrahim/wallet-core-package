import 'dart:io';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:wcf_tool_upstream/extract.dart';
import 'package:wcf_tool_upstream/paths.dart';

Archive _archive(List<ArchiveFile> files) {
  final archive = Archive();
  for (final file in files) {
    archive.add(file);
  }
  return archive;
}

void main() {
  late Directory destination;

  setUp(() {
    destination = Directory.systemTemp.createTempSync('wcf-extract-');
  });

  tearDown(() {
    if (destination.existsSync()) destination.deleteSync(recursive: true);
  });

  test('strips the single top-level directory', () {
    final report = extractArchiveTo(
      archive: _archive([
        ArchiveFile.string('wallet-core-4.8.0/registry.json', '{"x":1}'),
        ArchiveFile.string(
          'wallet-core-4.8.0/include/TrustWalletCore/TWCoinType.h',
          '// header',
        ),
      ]),
      destination: destination,
    );

    expect(report.strippedTopLevel, equals('wallet-core-4.8.0'));
    expect(report.fileCount, equals(2));
    expect(File('${destination.path}/registry.json').existsSync(), isTrue);
    expect(
      File(
        '${destination.path}/include/TrustWalletCore/TWCoinType.h',
      ).readAsStringSync(),
      equals('// header'),
    );
  });

  test('empties the destination first, so no stale file survives', () {
    File('${destination.path}/stale.txt').writeAsStringSync('old pin');
    extractArchiveTo(
      archive: _archive([ArchiveFile.string('top/new.txt', 'new pin')]),
      destination: destination,
    );
    expect(File('${destination.path}/stale.txt').existsSync(), isFalse);
    expect(File('${destination.path}/new.txt').existsSync(), isTrue);
  });

  test('recreates a symlink that stays inside the destination', () {
    final report = extractArchiveTo(
      archive: _archive([
        ArchiveFile.string('top/include/TWData.h', '// header'),
        ArchiveFile.symlink('top/flutter/include', '../include'),
      ]),
      destination: destination,
    );
    expect(report.symlinkCount, equals(1));
    expect(
      Link('${destination.path}/flutter/include').targetSync(),
      equals('../include'),
    );
  });

  group('rejects a hostile archive', () {
    test('with a traversal entry', () {
      expect(
        () => extractArchiveTo(
          archive: _archive([
            ArchiveFile.string('top/ok.txt', 'ok'),
            ArchiveFile.string('top/../../../../etc/pwned', 'pwned'),
          ]),
          destination: destination,
        ),
        throwsA(isA<UnsafeArchiveEntry>()),
      );
      expect(File('/etc/pwned').existsSync(), isFalse);
    });

    test('with an absolute entry', () {
      expect(
        () => extractArchiveTo(
          archive: _archive([
            ArchiveFile.string('top/ok.txt', 'ok'),
            ArchiveFile.string('/tmp/wcf-pwned', 'pwned'),
          ]),
          destination: destination,
        ),
        throwsA(isA<UnsafeArchiveEntry>()),
      );
      expect(File('/tmp/wcf-pwned').existsSync(), isFalse);
    });

    test('with a symlink pointing outside the destination', () {
      expect(
        () => extractArchiveTo(
          archive: _archive([
            ArchiveFile.string('top/ok.txt', 'ok'),
            ArchiveFile.symlink('top/escape', '../../../../etc'),
          ]),
          destination: destination,
        ),
        throwsA(
          isA<UnsafeArchiveEntry>().having(
            (e) => e.toString(),
            'message',
            contains('escapes the extraction root'),
          ),
        ),
      );
      expect(Link('${destination.path}/escape').existsSync(), isFalse);
    });

    test('with an absolute symlink target', () {
      expect(
        () => extractArchiveTo(
          archive: _archive([
            ArchiveFile.string('top/ok.txt', 'ok'),
            ArchiveFile.symlink('top/escape', '/etc/passwd'),
          ]),
          destination: destination,
        ),
        throwsA(isA<UnsafeArchiveEntry>()),
      );
    });

    test('with more than one top-level directory', () {
      expect(
        () => extractArchiveTo(
          archive: _archive([
            ArchiveFile.string('a/x.txt', 'x'),
            ArchiveFile.string('b/y.txt', 'y'),
          ]),
          destination: destination,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  test('decodeSourceArchive round-trips a gzip tar', () {
    final tar = TarEncoder().encodeBytes(
      _archive([ArchiveFile.string('top/registry.json', '{"x":1}')]),
    );
    final gz = GZipEncoder().encodeBytes(tar);
    final decoded = decodeSourceArchive(gz);
    expect(decoded.files.map((f) => f.name), contains('top/registry.json'));
  });
}
