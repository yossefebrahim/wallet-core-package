// The catalogue is the evaluation protocol: eleven steps, every one of them a
// row, measured or not.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.

import 'package:test/test.dart';
import 'package:wcf_tool_packaging_eval/steps.dart';

void main() {
  group('stepCatalogue', () {
    test('covers exactly the eleven PRD §12.2 steps, 1 through 11', () {
      final steps = stepCatalogue.map((r) => r.step).toSet().toList()..sort();
      expect(steps, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
      expect(steps, hasLength(11));
    });

    test('rows are in step order, so the table reads as the protocol does', () {
      final numbers = stepCatalogue.map((r) => r.step).toList();
      for (var i = 1; i < numbers.length; i++) {
        expect(
          numbers[i],
          greaterThanOrEqualTo(numbers[i - 1]),
          reason: 'row $i (${stepCatalogue[i].check}) is out of order',
        );
      }
    });

    test('every row cites its step, a command, and at least one target', () {
      for (final row in stepCatalogue) {
        expect(row.step, inInclusiveRange(1, 11), reason: row.check);
        expect(row.check, isNotEmpty);
        expect(row.label, isNotEmpty);
        expect(row.command.trim(), isNotEmpty, reason: row.check);
        expect(row.targets, isNotEmpty, reason: row.check);
      }
    });

    test('no two rows share a check name', () {
      final checks = stepCatalogue.map((r) => r.check).toList();
      expect(checks.toSet(), hasLength(checks.length));
    });

    test('ownership is one of harness, evaluation, device', () {
      for (final row in stepCatalogue) {
        expect(
          row.ownedBy,
          anyOf('harness', 'evaluation', 'device'),
          reason: row.check,
        );
      }
      expect(
        stepCatalogue.where((r) => r.ownedBy == 'harness').map((r) => r.check),
        containsAll(<String>[
          'symbols',
          'size',
          'alignment',
          'libcxx-conflict',
          'ios-archive',
          'consumer-gen',
        ]),
      );
    });

    test('a harness row runs a command in this package', () {
      for (final row in stepCatalogue.where((r) => r.ownedBy == 'harness')) {
        expect(
          row.command,
          anyOf(
            contains('tools/packaging_eval/bin/'),
            contains('tools/packaging_eval/fixtures/'),
          ),
          reason: row.check,
        );
      }
    });

    test('every target named by a row is a declared column', () {
      const known = {...artifactTargets, ...appTargets, ...otherTargets};
      for (final row in stepCatalogue) {
        for (final target in row.targets) {
          expect(known, contains(target), reason: '${row.check} -> $target');
        }
      }
    });

    test('the column lists are disjoint and the subsets are subsets', () {
      expect(artifactTargets.toSet().intersection(appTargets.toSet()), isEmpty);
      expect(appTargets.toSet().intersection(otherTargets.toSet()), isEmpty);
      expect(appTargets.toSet(), containsAll(androidAppTargets));
      expect(appTargets.toSet(), containsAll(iosAppTargets));
      expect(appTargets.toSet(), containsAll(releaseAppTargets));
      expect(releaseAppTargets.every((t) => t.endsWith('/release')), isTrue);
    });
  });
}
