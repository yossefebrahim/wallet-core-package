import 'package:test/test.dart';
import 'package:wcf_tool_upstream/download.dart';

void main() {
  group('sourceArchiveUrl', () {
    test('builds the codeload URL for the pinned repo and tag', () {
      expect(
        sourceArchiveUrl(repo: 'trustwallet/wallet-core', tag: '4.8.0'),
        equals(
          'https://codeload.github.com/trustwallet/wallet-core/'
          'tar.gz/refs/tags/4.8.0',
        ),
      );
    });

    test('is a pure function of its two arguments', () {
      expect(
        sourceArchiveUrl(repo: 'a/b', tag: 'v1.2.3'),
        equals(sourceArchiveUrl(repo: 'a/b', tag: 'v1.2.3')),
      );
      expect(
        sourceArchiveUrl(repo: 'a/b', tag: 'v1.2.3'),
        isNot(equals(sourceArchiveUrl(repo: 'a/b', tag: 'v1.2.4'))),
      );
    });

    test('accepts tags with dots and dashes', () {
      expect(
        sourceArchiveUrl(repo: 'trustwallet/wallet-core', tag: '4.8.0-rc.1'),
        endsWith('/tar.gz/refs/tags/4.8.0-rc.1'),
      );
    });

    test('rejects a repo that is not "<owner>/<name>"', () {
      for (final repo in ['', 'wallet-core', 'a/b/c', 'a b/c', '../../etc']) {
        expect(
          () => sourceArchiveUrl(repo: repo, tag: '4.8.0'),
          throwsA(isA<ArgumentError>()),
          reason: 'repo "$repo"',
        );
      }
    });

    test('rejects a tag that could rewrite the path', () {
      for (final tag in ['', '../heads/master', 'a/b', '%2e%2e']) {
        expect(
          () => sourceArchiveUrl(repo: 'trustwallet/wallet-core', tag: tag),
          throwsA(isA<ArgumentError>()),
          reason: 'tag "$tag"',
        );
      }
    });
  });
}
