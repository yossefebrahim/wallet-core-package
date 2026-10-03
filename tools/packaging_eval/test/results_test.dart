// The result-row schema: every command in this package writes it and `report`
// is the only thing that reads it.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.

import 'dart:io';

import 'package:test/test.dart';
import 'package:wcf_tool_packaging_eval/results.dart';

import 'fixtures.dart';

void main() {
  group('CheckStatus', () {
    test('the four names are the schema and do not drift', () {
      expect(CheckStatus.values.map((s) => s.name), [
        'pass',
        'fail',
        'skip',
        'unmeasured',
      ]);
    });

    test('parses its own names and rejects anything else', () {
      for (final status in CheckStatus.values) {
        expect(CheckStatus.parse(status.name), status);
      }
      expect(() => CheckStatus.parse('PASS'), throwsFormatException);
      expect(() => CheckStatus.parse('unknown'), throwsFormatException);
    });

    test('worst-of ranks fail > unmeasured > skip > pass', () {
      expect(
        CheckStatus.worst(CheckStatus.pass, CheckStatus.skip),
        CheckStatus.skip,
      );
      expect(
        CheckStatus.worst(CheckStatus.skip, CheckStatus.unmeasured),
        CheckStatus.unmeasured,
      );
      expect(
        CheckStatus.worst(CheckStatus.unmeasured, CheckStatus.fail),
        CheckStatus.fail,
      );
      expect(
        CheckStatus.worst(CheckStatus.fail, CheckStatus.pass),
        CheckStatus.fail,
      );
      expect(
        CheckStatus.worst(CheckStatus.pass, CheckStatus.pass),
        CheckStatus.pass,
      );
    });
  });

  group('ResultRow', () {
    test('round-trips through JSON with every field intact', () {
      final row = ResultRow(
        check: 'size',
        target: 'ios/arm64',
        status: CheckStatus.fail,
        command: "wc -c 'a file.dylib'",
        values: {
          'size_bytes': 19721208,
          'summary': '18.81 MiB',
          'slices': [
            {'arch': 'arm64', 'size': 12},
          ],
        },
        notes: 'record disagrees',
      );

      final decoded = ResultRow.fromJson(row.toJson());
      expect(decoded.check, row.check);
      expect(decoded.target, row.target);
      expect(decoded.status, CheckStatus.fail);
      expect(decoded.command, row.command);
      expect(decoded.notes, row.notes);
      expect(decoded.values, row.values);
      expect(decoded.toJson(), row.toJson());
    });

    test(
      'values are unmodifiable, so a row cannot be edited after the fact',
      () {
        final row = ResultRow(
          check: 'size',
          target: 'ios/arm64',
          status: CheckStatus.pass,
          command: 'wc -c x',
          values: {'size_bytes': 1},
        );
        expect(() => row.values['size_bytes'] = 2, throwsUnsupportedError);
      },
    );

    test('summary prefers values[summary] and otherwise sorts the keys', () {
      final withSummary = ResultRow(
        check: 'c',
        target: 't',
        status: CheckStatus.pass,
        command: '',
        values: {'b': 2, 'summary': 'short form', 'a': 1},
      );
      expect(withSummary.summary, 'short form');

      final without = ResultRow(
        check: 'c',
        target: 't',
        status: CheckStatus.pass,
        command: '',
        values: {'b': 2, 'a': 1},
      );
      expect(without.summary, 'a=1 b=2');
      expect(without.toString(), 'c/t pass: a=1 b=2');
    });

    test('an absent command or notes decodes to the empty string', () {
      final decoded = ResultRow.fromJson({
        'check': 'size',
        'target': 'ios/arm64',
        'status': 'unmeasured',
      });
      expect(decoded.command, '');
      expect(decoded.notes, '');
      expect(decoded.values, isEmpty);
    });
  });

  group('ResultsFile', () {
    final sample = ResultRow(
      check: 'alignment',
      target: 'ndk/arm64-v8a',
      status: CheckStatus.pass,
      command: 'check_alignment.sh --binary x',
      values: {'load_segments': 4},
    );
    final other = ResultRow(
      check: 'size',
      target: 'ios/arm64',
      status: CheckStatus.unmeasured,
      command: 'wc -c x',
    );

    test('encodes one JSON object per line and decodes back', () {
      final encoded = ResultsFile.encode([sample, other]);
      expect(encoded.split('\n'), hasLength(2));
      final decoded = ResultsFile.decode(encoded);
      expect(decoded.map((r) => r.toJson()), [sample.toJson(), other.toJson()]);
    });

    test('decode skips blank lines and reports the line that is not JSON', () {
      expect(ResultsFile.decode('\n\n'), isEmpty);
      expect(
        () => ResultsFile.decode('${ResultsFile.encode([sample])}\nnot json'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('line 2'),
          ),
        ),
      );
      expect(
        () => ResultsFile.decode('[1, 2]'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('not a JSON object'),
          ),
        ),
      );
    });

    test('append adds to an existing file, write replaces it', () {
      final directory = Directory.systemTemp.createTempSync('wcf-results-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/nested/results.jsonl');

      ResultsFile.append(file, [sample]);
      ResultsFile.append(file, [other]);
      expect(ResultsFile.read(file), hasLength(2));

      ResultsFile.append(file, const []);
      expect(ResultsFile.read(file), hasLength(2), reason: 'no empty append');

      ResultsFile.write(file, [sample]);
      expect(ResultsFile.read(file).single.check, 'alignment');
    });

    test('readAll reads two files and a directory in sorted order', () {
      final directory = Directory.systemTemp.createTempSync('wcf-results-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final first = File('${directory.path}/a.jsonl');
      final second = File('${directory.path}/b.jsonl');
      ResultsFile.write(first, [sample]);
      ResultsFile.write(second, [other]);
      File('${directory.path}/table.md').writeAsStringSync('not results');

      expect(
        ResultsFile.readAll([first.path, second.path]).map((r) => r.check),
        ['alignment', 'size'],
      );
      expect(ResultsFile.readAll([directory.path]).map((r) => r.check), [
        'alignment',
        'size',
      ], reason: 'directory entries are read sorted, .md ignored');
      expect(
        () => ResultsFile.readAll(['${directory.path}/missing.jsonl']),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('reads the committed sample results file', () {
      final rows = ResultsFile.read(
        File('${fixturesDirectory().path}/results/sample.jsonl'),
      );
      expect(rows, hasLength(8));
      expect(
        rows.map((r) => r.check).toSet(),
        containsAll(<String>['size', 'symbols', 'alignment', 'consumer-gen']),
      );
      expect(
        rows.where((r) => r.status == CheckStatus.fail).single.target,
        'android/arm64-v8a',
      );
      for (final row in rows) {
        expect(row.command, isNotEmpty, reason: 'every row cites a command');
      }
    });
  });
}
