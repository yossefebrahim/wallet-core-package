// The rendered table: a pure function of the result rows.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.

import 'dart:io';

import 'package:test/test.dart';
import 'package:wcf_tool_packaging_eval/report.dart';
import 'package:wcf_tool_packaging_eval/results.dart';
import 'package:wcf_tool_packaging_eval/steps.dart';

import 'fixtures.dart';

List<ResultRow> sampleRows() =>
    ResultsFile.read(File('${fixturesDirectory().path}/results/sample.jsonl'));

/// The `| … |` lines of the table body, one per catalogue row.
List<String> bodyRows(String markdown) => markdown
    .split('\n')
    .where((l) => RegExp(r'^\| \d+\. ').hasMatch(l))
    .toList();

/// The cells of one body row, as written.
List<String> cells(String row) => row
    .split(' | ')
    .map((c) => c.replaceAll(RegExp(r'^\| |\s*\|$'), ''))
    .toList();

void main() {
  group('renderReport over the committed sample results', () {
    test('is deterministic: the same rows render the same bytes', () {
      final first = renderReport(sampleRows());
      final second = renderReport(sampleRows());
      expect(second, first);
      // And the ordering of the input does not leak into the output through a
      // hash-ordered map.
      final reversed = renderReport(sampleRows().reversed.toList());
      expect(
        bodyRows(reversed),
        bodyRows(first),
        reason: 'row order must not change the table body',
      );
    });

    test('renders one body row per catalogue entry, all eleven steps', () {
      final markdown = renderReport(sampleRows());
      final body = bodyRows(markdown);
      expect(body, hasLength(stepCatalogue.length));
      final numbers = <int>{
        for (final row in body)
          int.parse(RegExp(r'^\| (\d+)\. ').firstMatch(row)!.group(1)!),
      }.toList()..sort();
      expect(numbers, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
      for (final specification in stepCatalogue) {
        expect(
          markdown,
          contains(
            '| ${specification.step}. ${specification.label} '
            '(`${specification.check}`, ${specification.ownedBy}) |',
          ),
        );
      }
    });

    test('carries the disclaimer and the header row of columns', () {
      final markdown = renderReport(sampleRows());
      expect(
        markdown,
        contains(
          'Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core '
          'library. Not affiliated with or endorsed by Trust Wallet.',
        ),
      );
      expect(markdown, contains('| PRD §12.2 step |'));
      expect(markdown, contains('| ios/arm64 |'));
      expect(
        markdown,
        contains('consumer/pub'),
        reason: 'a canonical column is rendered even when nothing measured it',
      );
    });

    test('a measured cell shows its status and value', () {
      final markdown = renderReport(sampleRows());
      expect(
        markdown,
        contains('pass arm64: 464/464 TW*, 29434 defined external'),
      );
      expect(markdown, contains('fail 2 LOAD @ 0x4000, 2 below'));
      expect(markdown, contains('pass 18.81 MiB'));
    });

    test('an unmeasured cell carries the footnote of its own command', () {
      final markdown = renderReport(sampleRows());
      final libcxx = bodyRows(
        markdown,
      ).singleWhere((r) => r.contains('(`libcxx-conflict`'));
      final cell = cells(libcxx).firstWhere((c) => c.startsWith('unmeasured'));
      final footnote = RegExp(
        r'unmeasured \[(\d+)\]',
      ).firstMatch(cell)!.group(1);
      final specification = stepCatalogue.singleWhere(
        (s) => s.check == 'libcxx-conflict',
      );
      expect(
        markdown,
        contains('[$footnote] `${specification.command}`'),
        reason: 'the footnote is the exact command that will measure it',
      );
      expect(markdown, contains('## Commands'));
    });

    test('a column outside a row targets renders as not applicable', () {
      final markdown = renderReport(sampleRows());
      final size = bodyRows(
        markdown,
      ).singleWhere((r) => r.contains('(`size`, harness)'));
      final header = markdown
          .split('\n')
          .firstWhere((l) => l.startsWith('| PRD §12.2 step |'));
      final columns = cells(header);
      final values = cells(size);
      final appColumn = columns.indexOf('ios-device-arm64/release');
      expect(appColumn, greaterThan(0));
      expect(
        values[appColumn],
        '—',
        reason: 'a library row has no consumer-app column',
      );
    });

    test('a result no catalogue row claims is reported, never dropped', () {
      final markdown = renderReport(sampleRows());
      expect(markdown, contains('## Results with no catalogue row'));
      expect(markdown, contains('`invented-check` / `nowhere/at-all`'));
    });

    test('notes are rendered under the table', () {
      final markdown = renderReport(sampleRows());
      expect(markdown, contains('## Notes'));
      expect(
        markdown,
        contains('**alignment / android/arm64-v8a** — rebuild with NDK r27+'),
      );
    });
  });

  group('renderReport aggregation', () {
    ResultRow row(String target, CheckStatus status, String summary) =>
        ResultRow(
          check: 'size',
          target: target,
          status: status,
          command: 'wc -c $target',
          values: {'summary': summary},
        );

    test('two rows in one cell take the worst status and both values', () {
      final markdown = renderReport([
        row('ios/arm64', CheckStatus.pass, 'first'),
        row('ios/arm64', CheckStatus.fail, 'second'),
      ]);
      final size = bodyRows(
        markdown,
      ).singleWhere((r) => r.contains('(`size`, harness)'));
      expect(size, contains('fail first; second'));
    });

    test('an empty result set still renders the whole protocol', () {
      final markdown = renderReport(const []);
      expect(bodyRows(markdown), hasLength(stepCatalogue.length));
      expect(markdown, isNot(contains('## Notes')));
      expect(markdown, isNot(contains('## Results with no catalogue row')));
      expect(markdown, contains('unmeasured [1]'));
    });

    test('the title is configurable and appears once', () {
      final markdown = renderReport(const [], title: 'T1.8 option 1');
      expect(markdown, startsWith('# T1.8 option 1\n'));
    });
  });
}
