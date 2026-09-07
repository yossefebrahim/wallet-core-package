import 'package:test/test.dart';
import 'package:wcf_tool_upstream/paths.dart';

void main() {
  group('safeRelativePath accepts', () {
    for (final name in [
      'wallet-core-4.8.0/registry.json',
      'wallet-core-4.8.0/include/TrustWalletCore/TWCoinType.h',
      'a/b/../c',
      './a/b',
    ]) {
      test('"$name"', () {
        expect(() => safeRelativePath(name), returnsNormally);
      });
    }

    test('normalises away "." and redundant separators', () {
      expect(safeRelativePath('./a//b/./c'), equals('a/b/c'));
      expect(safeRelativePath('a/b/../c'), equals('a/c'));
    });
  });

  group('safeRelativePath rejects', () {
    final hostile = <String, String>{
      '': 'empty entry name',
      '/etc/passwd': 'absolute path',
      '/../../etc/passwd': 'absolute path',
      r'\\server\share\x': 'UNC or absolute Windows path',
      'C:/Windows/System32/x': 'Windows drive-qualified path',
      '..': 'path traversal',
      '../outside.txt': 'path traversal',
      '../../../../etc/passwd': 'path traversal',
      'wallet-core-4.8.0/../../escape.txt': 'path traversal',
      'a/b/../../../c': 'path traversal',
      '.': 'entry resolves to the root itself',
      './': 'entry resolves to the root itself',
    };

    hostile.forEach((name, reason) {
      test('"$name" ($reason)', () {
        expect(
          () => safeRelativePath(name),
          throwsA(
            isA<UnsafeArchiveEntry>().having(
              (e) => e.toString(),
              'message',
              contains(reason),
            ),
          ),
        );
      });
    });

    test('a NUL byte in the entry name', () {
      expect(
        () => safeRelativePath('a\u0000b/c.h'),
        throwsA(isA<UnsafeArchiveEntry>()),
      );
    });
  });

  group('safeSymlinkTarget', () {
    test('accepts a target that stays inside the root', () {
      expect(
        safeSymlinkTarget('flutter/include', '../include'),
        equals('../include'),
      );
      expect(safeSymlinkTarget('a/b/link', 'sibling'), equals('sibling'));
    });

    test('rejects an absolute target', () {
      expect(
        () => safeSymlinkTarget('a/link', '/etc/passwd'),
        throwsA(isA<UnsafeArchiveEntry>()),
      );
    });

    test('rejects a target that escapes the root', () {
      expect(
        () => safeSymlinkTarget('a/link', '../../outside'),
        throwsA(
          isA<UnsafeArchiveEntry>().having(
            (e) => e.toString(),
            'message',
            contains('escapes the extraction root'),
          ),
        ),
      );
    });

    test('rejects an empty target', () {
      expect(
        () => safeSymlinkTarget('a/link', ''),
        throwsA(isA<UnsafeArchiveEntry>()),
      );
    });
  });

  group('singleTopLevelDirectory', () {
    test('finds the one directory a source archive wraps the tree in', () {
      expect(
        singleTopLevelDirectory([
          'wallet-core-4.8.0/',
          'wallet-core-4.8.0/registry.json',
          'wallet-core-4.8.0/src/proto/Ethereum.proto',
        ]),
        equals('wallet-core-4.8.0'),
      );
    });

    test('rejects an archive with two top-level entries', () {
      expect(
        () => singleTopLevelDirectory(['a/x', 'b/y']),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects an empty archive', () {
      expect(
        () => singleTopLevelDirectory(const <String>[]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects an archive containing a traversal entry', () {
      expect(
        () => singleTopLevelDirectory(['a/x', '../evil']),
        throwsA(isA<UnsafeArchiveEntry>()),
      );
    });
  });

  group('stripTopLevel', () {
    test('removes the wrapper directory', () {
      expect(
        stripTopLevel('wallet-core-4.8.0/registry.json', 'wallet-core-4.8.0'),
        equals('registry.json'),
      );
      expect(
        stripTopLevel(
          'wallet-core-4.8.0/include/TrustWalletCore/TWCoinType.h',
          'wallet-core-4.8.0',
        ),
        equals('include/TrustWalletCore/TWCoinType.h'),
      );
    });

    test('returns null for the wrapper directory entry itself', () {
      expect(stripTopLevel('wallet-core-4.8.0', 'wallet-core-4.8.0'), isNull);
    });

    test('rejects an entry outside the wrapper', () {
      expect(
        () => stripTopLevel('other/x', 'wallet-core-4.8.0'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
