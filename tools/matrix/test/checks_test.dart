import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wcf_tool_matrix/checks.dart';
import 'package:wcf_tool_matrix/load.dart';
import 'package:wcf_tool_matrix/render.dart';
import 'package:wcf_tool_vectors/inventory.dart';

import 'support.dart';

/// Generates the committed outputs into the fixture's `docs/`.
void generate(FixtureRepo repo) {
  final result = repo.build();
  expect(result.problems, isEmpty);
  writeOutputs(result.matrix, Directory(repo.paths.docsDir));
}

/// The decoded matrix JSON of the fixture as it is now, for use as a baseline.
Map<String, Object?> snapshotOf(FixtureRepo repo) =>
    jsonDecode(renderJson(repo.build().matrix)) as Map<String, Object?>;

const exampleResults = 'test/fixtures/results_example_android.json';

void main() {
  late FixtureRepo repo;

  group('(b) the matrix is regenerated, never edited', () {
    test('passes when the committed outputs equal a regeneration', () {
      repo = FixtureRepo.create();
      generate(repo);
      expect(checkRegeneration(repo.paths, repo.build().matrix), isEmpty);
    });

    test('a hand edit to the markdown fails, naming the file and line', () {
      repo = FixtureRepo.create();
      generate(repo);
      final file = File(repo.paths.matrixMarkdown);
      file.writeAsStringSync(
        file.readAsStringSync().replaceFirst('exposed, unverified', 'tested'),
      );
      final violations = checkRegeneration(repo.paths, repo.build().matrix);
      expect(violations, hasLength(1));
      expect(violations.single, contains('docs/capability_matrix.md'));
      expect(violations.single, contains('first at line'));
    });

    test('a hand edit to the JSON fails', () {
      repo = FixtureRepo.create();
      generate(repo);
      final file = File(repo.paths.matrixJson);
      file.writeAsStringSync(
        file.readAsStringSync().replaceFirst(
          '"tested": false',
          '"tested": true',
        ),
      );
      expect(
        checkRegeneration(repo.paths, repo.build().matrix).single,
        contains('capability_matrix.json'),
      );
    });

    test('a missing output fails', () {
      repo = FixtureRepo.create();
      expect(checkRegeneration(repo.paths, repo.build().matrix), hasLength(2));
    });

    test('an input change without regeneration fails', () {
      repo = FixtureRepo.create();
      generate(repo);
      repo.writeVectors('ethereum', [VectorSpec('ethereum', 'address', 'n/a')]);
      expect(checkRegeneration(repo.paths, repo.build().matrix), isNotEmpty);
    });
  });

  group('(c) no level goes down, no vector disappears', () {
    List<String> against(FixtureRepo r, Map<String, Object?> baseline) =>
        checkAgainstBaseline(
          r.build().matrix,
          baseline,
          loadInputs(r.paths).inventory.exclusions,
        );

    test('passes when nothing changed or a level went up', () {
      repo = FixtureRepo.create();
      repo.writeVectors('ethereum', [
        VectorSpec('ethereum', 'sign', 'eip1559'),
      ]);
      final baseline = snapshotOf(repo);
      expect(against(repo, baseline), isEmpty);
      repo.writeVectors('ethereum', [
        VectorSpec(
          'ethereum',
          'sign',
          'eip1559',
          platforms: ['android', 'ios'],
        ),
        VectorSpec('ethereum', 'address', 'n/a'),
      ]);
      expect(against(repo, baseline), isEmpty);
    });

    test('a vector that disappears fails, naming it', () {
      repo = FixtureRepo.create();
      repo.writeVectors('ethereum', [
        VectorSpec('ethereum', 'sign', 'eip1559'),
        VectorSpec('ethereum', 'address', 'n/a'),
      ]);
      final baseline = snapshotOf(repo);
      repo.writeVectors('ethereum', [VectorSpec('ethereum', 'address', 'n/a')]);
      final violations = against(repo, baseline);
      expect(violations, hasLength(1));
      expect(
        violations.single,
        contains('vector ethereum-sign-eip1559-1 was removed'),
      );
    });

    test('an exclusions entry with a reason clears it; a variant-less entry '
        'covers every variant', () {
      repo = FixtureRepo.create();
      repo.writeVectors('ethereum', [
        VectorSpec('ethereum', 'sign', 'eip1559'),
        VectorSpec('ethereum', 'sign', 'legacy'),
      ]);
      final baseline = snapshotOf(repo);
      repo.writeVectors('ethereum', []);
      expect(against(repo, baseline), hasLength(2));

      repo.writeExclusions(
        'exclusions:\n'
        '  - coin: ethereum\n'
        '    operation: sign\n'
        '    variant: eip1559\n'
        '    reason: fixture\n',
      );
      expect(
        against(repo, baseline).single,
        contains('ethereum-sign-legacy-1'),
      );

      repo.writeExclusions(
        'exclusions:\n'
        '  - coin: ethereum\n'
        '    operation: sign\n'
        '    reason: fixture\n',
      );
      expect(against(repo, baseline), isEmpty);
    });

    test(
      'a platform level that goes down fails, and so does losing Tested',
      () {
        repo = FixtureRepo.create();
        repo.writeVectors('ethereum', [
          VectorSpec(
            'ethereum',
            'sign',
            'eip1559',
            platforms: ['android', 'ios'],
          ),
        ]);
        final baseline = snapshotOf(repo);
        repo.writeVectors('ethereum', [
          VectorSpec('ethereum', 'sign', 'eip1559', platforms: ['android']),
        ]);
        final violations = against(repo, baseline);
        expect(
          violations,
          contains(
            contains('level of ethereum/sign/eip1559 on ios went down, 3 -> 2'),
          ),
        );
        expect(
          violations,
          contains(contains('ethereum/sign/eip1559 is no longer tested')),
        );
        expect(violations.any((v) => v.contains('on android')), isFalse);
      },
    );

    test('a cell that is no longer generated fails; a level lost from '
        'exposed fails', () {
      repo = FixtureRepo.create();
      final baseline = snapshotOf(repo);
      // The exposed snapshot loses ethereum's eip1559 path.
      repo.writeJson('docs/capability_exposed.json', {
        'schema': 1,
        'groups': [
          {
            'operation': 'address',
            'variant': 'n/a',
            'exposure': 'typed',
            'coins': 'all',
          },
        ],
      });
      final violations = against(repo, baseline);
      expect(
        violations,
        contains(
          contains(
            'level of ethereum/sign/eip1559 on android went down, 2 -> 1',
          ),
        ),
      );

      // A coin leaves the registry: its cells disappear.
      final fewer = FixtureRepo.create(
        coins: defaultCoins.where((c) => c.enumName != 'solana').toList(),
      );
      expect(
        checkAgainstBaseline(fewer.build().matrix, baseline, const []),
        contains(contains('solana/sign/legacy is no longer generated')),
      );
    });

    test('a baseline of another schema is refused', () {
      repo = FixtureRepo.create();
      expect(
        checkAgainstBaseline(repo.build().matrix, {'schema': 2}, const []),
        [contains('schema 2')],
      );
    });

    test('exclusions need a coin, an operation and a reason', () {
      final violations = checkExclusions([
        Exclusion(coin: '', operation: 'sign', reason: 'r'),
        Exclusion(coin: 'ethereum', operation: '', reason: 'r'),
        Exclusion(coin: 'ethereum', operation: 'sign', reason: '  '),
        Exclusion(coin: 'ethereum', operation: 'sign', reason: 'fine'),
      ]);
      expect(violations, [
        contains('entry 1 has no coin'),
        contains('entry 2 has no operation'),
        contains('entry 3 has no reason'),
      ]);
    });

    test('with no committed matrix at the ref there is no baseline', () {
      repo = FixtureRepo.create();
      expect(readBaselineFromGit(repo.root.path, 'HEAD'), isNull);
      expect(readBaselineFromGit('/nonexistent/dir', 'HEAD'), isNull);
    });
  });

  group('(a) every claim has a passing vector', () {
    ResultsReport run(FixtureRepo r) => checkResults(
      inventory: loadInputs(r.paths).inventory,
      resultsDir: r.paths.resultsDir,
      upstream: loadInputs(r.paths).upstream,
    );

    void claimsAndExample(FixtureRepo r) {
      r.writeVectors('ethereum', [
        VectorSpec(
          'ethereum',
          'sign',
          'eip1559',
          platforms: ['android', 'ios'],
        ),
        VectorSpec('ethereum', 'address', 'n/a', platforms: ['android']),
        VectorSpec('ethereum', 'sign', 'legacy', platforms: ['host']),
      ]);
      r.writeText(
        'test_vectors/results/android.json',
        File(exampleResults).readAsStringSync(),
      );
    }

    test('a claim the results file records as pass is confirmed; the '
        'missing ios file leaves its claim unconfirmed', () {
      repo = FixtureRepo.create();
      claimsAndExample(repo);
      final report = run(repo);
      expect(report.violations, isEmpty);
      expect(report.unconfirmed, [
        contains('vector ethereum-sign-eip1559-1 claims ios'),
      ]);
    });

    test('no results files and no claims: nothing to report', () {
      repo = FixtureRepo.create();
      repo.writeVectors('ethereum', [VectorSpec('ethereum', 'address', 'n/a')]);
      final report = run(repo);
      expect(report.violations, isEmpty);
      expect(report.unconfirmed, isEmpty);
    });

    test('with no results files every device claim is unconfirmed', () {
      repo = FixtureRepo.create();
      claimsAndExample(repo);
      File('${repo.paths.resultsDir}/android.json').deleteSync();
      expect(run(repo).unconfirmed, hasLength(3));
      expect(run(repo).violations, isEmpty);
    });

    test('a claim the results file records as fail, or omits, is a '
        'violation', () {
      repo = FixtureRepo.create();
      claimsAndExample(repo);
      repo.writeVectors('ethereum', [
        VectorSpec('ethereum', 'sign', 'legacy', platforms: ['android']),
        VectorSpec('ethereum', 'sign', 'contract_call', platforms: ['android']),
      ]);
      final violations = run(repo).violations;
      expect(violations, hasLength(2));
      expect(
        violations,
        contains(
          allOf(
            contains('vector ethereum-sign-legacy-1 claims android'),
            contains('records fail'),
          ),
        ),
      );
      expect(
        violations,
        contains(
          allOf(
            contains('ethereum-sign-contract_call-1 claims android'),
            contains('records no entry'),
          ),
        ),
      );
    });

    test('a results file for another upstream, platform or shape is a '
        'violation', () {
      repo = FixtureRepo.create();
      claimsAndExample(repo);
      final stale =
          jsonDecode(File(exampleResults).readAsStringSync())
                as Map<String, Object?>
            ..['upstream'] = {'tag': '1.0.0', 'commit': 'deadbeef'}
            ..['platform'] = 'ios'
            ..['run_id'] = ''
            ..['results'] = [
              {'id': 'x', 'status': 'maybe'},
            ];
      repo.writeJson('test_vectors/results/android.json', stale);
      final violations = run(repo).violations;
      expect(violations, hasLength(1));
      expect(violations.single, contains('platform must be android'));
      expect(violations.single, contains('stale results'));
      expect(violations.single, contains('run_id must be a non-empty string'));
      expect(violations.single, contains('status of pass, fail or skipped'));
    });

    test('an unreadable results file is a violation', () {
      repo = FixtureRepo.create();
      claimsAndExample(repo);
      repo.writeText('test_vectors/results/android.json', '{not json');
      expect(run(repo).violations.single, contains('not readable JSON'));
    });
  });
}
