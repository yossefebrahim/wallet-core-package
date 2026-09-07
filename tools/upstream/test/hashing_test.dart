import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:wcf_tool_upstream/hashing.dart';

/// Writes a tree of `relative path -> contents` under a fresh directory.
Directory _tree(Map<String, String> files, {String prefix = 'wcf-hash-'}) {
  final root = Directory.systemTemp.createTempSync(prefix);
  files.forEach((relative, contents) {
    final file = File('${root.path}/$relative');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  });
  return root;
}

void main() {
  group('directoryHashInput', () {
    test('is sorted by relative path, one line per field', () {
      final input = directoryHashInput({
        'b.h': 'bb',
        'a.h': 'aa',
        'sub/c.h': 'cc',
      });
      expect(input, equals('a.h\naa\nb.h\nbb\nsub/c.h\ncc\n'));
    });

    test('is independent of insertion order', () {
      expect(
        directoryHashInput({'z': '1', 'a': '2'}),
        equals(directoryHashInput({'a': '2', 'z': '1'})),
      );
    });

    test('is empty for an empty tree', () {
      expect(directoryHashInput(const {}), isEmpty);
    });
  });

  group('hashDirectory', () {
    test('matches the definition documented in README.md', () {
      final root = _tree({'a.h': 'alpha', 'sub/b.h': 'beta'});
      addTearDown(() => root.deleteSync(recursive: true));

      final shaA = sha256.convert(utf8.encode('alpha')).toString();
      final shaB = sha256.convert(utf8.encode('beta')).toString();
      final expected = sha256
          .convert(utf8.encode('a.h\n$shaA\nsub/b.h\n$shaB\n'))
          .toString();

      final digest = hashDirectory(root);
      expect(digest.sha256, equals(expected));
      expect(digest.fileCount, equals(2));
    });

    test('is stable across two runs', () {
      final root = _tree({'a.h': 'alpha', 'sub/b.h': 'beta'});
      addTearDown(() => root.deleteSync(recursive: true));
      expect(hashDirectory(root).sha256, equals(hashDirectory(root).sha256));
    });

    test('is independent of the absolute path of the root', () {
      final one = _tree({'a.h': 'alpha', 'sub/b.h': 'beta'}, prefix: 'wcf-x-');
      final two = _tree({'a.h': 'alpha', 'sub/b.h': 'beta'}, prefix: 'wcf-y-');
      addTearDown(() {
        one.deleteSync(recursive: true);
        two.deleteSync(recursive: true);
      });
      expect(one.path, isNot(equals(two.path)));
      expect(hashDirectory(one).sha256, equals(hashDirectory(two).sha256));
    });

    test('is independent of file creation order and mtime', () {
      final one = _tree({'a.h': 'alpha', 'sub/b.h': 'beta'}, prefix: 'wcf-o1-');
      final two = Directory.systemTemp.createTempSync('wcf-o2-');
      addTearDown(() {
        one.deleteSync(recursive: true);
        two.deleteSync(recursive: true);
      });
      // Same contents, written in the opposite order, later in time.
      File('${two.path}/sub/b.h')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('beta');
      File('${two.path}/a.h').writeAsStringSync('alpha');
      File(
        '${two.path}/a.h',
      ).setLastModifiedSync(DateTime.utc(2001, 2, 3, 4, 5, 6));

      expect(hashDirectory(one).sha256, equals(hashDirectory(two).sha256));
    });

    test('changes when a file changes', () {
      final one = _tree({'a.h': 'alpha'}, prefix: 'wcf-c1-');
      final two = _tree({'a.h': 'alphb'}, prefix: 'wcf-c2-');
      addTearDown(() {
        one.deleteSync(recursive: true);
        two.deleteSync(recursive: true);
      });
      expect(
        hashDirectory(one).sha256,
        isNot(equals(hashDirectory(two).sha256)),
      );
    });

    test('changes when a file is renamed', () {
      final one = _tree({'a.h': 'alpha'}, prefix: 'wcf-r1-');
      final two = _tree({'b.h': 'alpha'}, prefix: 'wcf-r2-');
      addTearDown(() {
        one.deleteSync(recursive: true);
        two.deleteSync(recursive: true);
      });
      expect(
        hashDirectory(one).sha256,
        isNot(equals(hashDirectory(two).sha256)),
      );
    });

    test('ignores empty directories', () {
      final one = _tree({'a.h': 'alpha'}, prefix: 'wcf-e1-');
      final two = _tree({'a.h': 'alpha'}, prefix: 'wcf-e2-');
      addTearDown(() {
        one.deleteSync(recursive: true);
        two.deleteSync(recursive: true);
      });
      Directory('${two.path}/empty').createSync();
      expect(hashDirectory(one).sha256, equals(hashDirectory(two).sha256));
    });

    test('refuses to hash a tree containing a symbolic link', () {
      final root = _tree({'a.h': 'alpha'}, prefix: 'wcf-l-');
      addTearDown(() => root.deleteSync(recursive: true));
      Link('${root.path}/link.h').createSync('a.h');
      expect(
        () => hashDirectory(root),
        throwsA(
          isA<UnhashableEntry>().having(
            (e) => e.toString(),
            'message',
            contains('symbolic link'),
          ),
        ),
      );
    });

    test('rejects a missing directory', () {
      expect(
        () => hashDirectory(Directory('/nonexistent/wcf-upstream-test')),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  test('sha256OfFile hashes the file bytes', () {
    final root = _tree({'a.bin': 'abc'}, prefix: 'wcf-f-');
    addTearDown(() => root.deleteSync(recursive: true));
    expect(
      sha256OfFile(File('${root.path}/a.bin')),
      equals(
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      ),
    );
  });
}
