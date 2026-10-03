import 'package:test/test.dart';
import 'package:wcf_tool_upstream/notices.dart';

const _commit = 'd692ac27749d0c615e17c751b70ab4f0aa75c59b';

String _render(List<NoticeSection> sections) => renderThirdPartyNotices(
  repo: 'trustwallet/wallet-core',
  tag: '4.8.0',
  commit: _commit,
  sections: sections,
);

void main() {
  test('carries the PRD §17 disclaimer and trademark notice', () {
    final rendered = _render(const []);
    expect(
      rendered,
      contains(
        'Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core '
        'library. Not affiliated with or endorsed by Trust Wallet.',
      ),
    );
    expect(rendered, contains('third-party trademark'));
  });

  test('names the repo, tag, and commit the text was taken from', () {
    final rendered = _render([
      NoticeSection(
        upstreamPath: 'LICENSE',
        title: 'Apache License 2.0',
        text: 'Apache License\nVersion 2.0\n',
      ),
    ]);
    expect(rendered, contains('| Pinned tag | `4.8.0` |'));
    expect(rendered, contains('| Pinned commit | `$_commit` |'));
    expect(
      rendered,
      contains('## `LICENSE` — trustwallet/wallet-core @ 4.8.0 ($_commit)'),
    );
  });

  test('reproduces upstream text verbatim, including blank lines', () {
    const text = 'Apache License\n\n   Version 2.0, January 2004\n\n\nEND\n';
    final rendered = _render([
      NoticeSection(
        upstreamPath: 'LICENSE',
        title: 'Apache License 2.0',
        text: text,
      ),
    ]);
    expect(rendered, contains(text));
  });

  test('is a pure function of its inputs', () {
    final sections = [
      NoticeSection(upstreamPath: 'LICENSE', title: 'A', text: 'x\n'),
    ];
    expect(_render(sections), equals(_render(sections)));
  });

  group('fenceLengthFor', () {
    test('uses three backticks for ordinary text', () {
      expect(fenceLengthFor('Apache License\n'), equals(3));
    });

    test('outgrows the longest backtick run in the text', () {
      expect(fenceLengthFor('a ``` b'), equals(4));
      expect(fenceLengthFor('a `````` b'), equals(7));
    });
  });

  test('a licence containing a code fence does not break out of the block', () {
    const text = 'preamble\n```\nnot the end\n```\ntail\n';
    final rendered = _render([
      NoticeSection(upstreamPath: 'LICENSE', title: 'A', text: text),
    ]);
    expect(rendered, contains('````text\n$text````\n'));
  });

  test('upstreamNoticeFiles names the two upstream licence files', () {
    expect(
      upstreamNoticeFiles.keys,
      orderedEquals(['LICENSE', 'LICENSE-3RD-PARTY.txt']),
    );
  });
}
