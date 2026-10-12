import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wcf_tool_matrix/collect.dart';

import 'support.dart';

String line(String id, [String status = 'pass']) =>
    'WCF_VECTOR_RESULT {"id":"$id","status":"$status"}';

ProcessResult collect(
  FixtureRepo repo,
  String platform,
  List<String> logs, {
  Map<String, String> extra = const {},
  String out = 'results_out',
}) => Process.runSync(Platform.resolvedExecutable, [
  'bin/collect_results.dart',
  '--root',
  repo.root.path,
  '--platform',
  platform,
  '--out',
  '${repo.root.path}/$out',
  for (final e in extra.entries) ...[e.key, e.value],
  ...logs,
]);

void main() {
  group('parseResultLines', () {
    test(
      'finds the marker after a reporter prefix and ignores other lines',
      () {
        final results = parseResultLines(
          '00:12 +3: loading\n'
          '00:13 +3: ${line('a-1')}\n'
          'flutter: ${line('b-1', 'fail')}  \n'
          'WCF_VECTOR is not the marker\n',
        );
        expect(results, [
          (id: 'a-1', status: 'pass'),
          (id: 'b-1', status: 'fail'),
        ]);
      },
    );

    test(
      'a marker line without a readable payload throws, naming the line',
      () {
        for (final bad in [
          'WCF_VECTOR_RESULT',
          'WCF_VECTOR_RESULT not json',
          'WCF_VECTOR_RESULT {"id":"a-1"}',
          'WCF_VECTOR_RESULT {"id":"a-1","status":"maybe"}',
          'WCF_VECTOR_RESULT {"id":"","status":"pass"}',
          'WCF_VECTOR_RESULT {"id":1,"status":"pass"}',
          'WCF_VECTOR_RESULT {"id":"a-1",',
        ]) {
          expect(
            () => parseResultLines('ok\n$bad\n', source: 'x.txt'),
            throwsA(
              isA<FormatException>().having(
                (e) => e.message,
                'message',
                startsWith('x.txt:2:'),
              ),
            ),
            reason: bad,
          );
        }
      },
    );
  });

  group('buildResultsFile', () {
    Map<String, Object?> build(
      List<({String id, String status})> results, {
      Set<String> known = const {'a-1', 'b-1', 'c-1'},
    }) => buildResultsFile(
      platform: 'ios',
      upstreamTag: '4.8.0',
      upstreamCommit: 'abc',
      repositorySha: 'sha',
      runId: '7',
      results: results,
      knownIds: known,
    );

    test('sorts by id, de-duplicates, and the worst status wins', () {
      final file = build([
        (id: 'c-1', status: 'pass'),
        (id: 'a-1', status: 'pass'),
        (id: 'a-1', status: 'pass'),
        (id: 'b-1', status: 'pass'),
        (id: 'b-1', status: 'fail'),
        (id: 'b-1', status: 'pass'),
      ]);
      expect(file['results'], [
        {'id': 'a-1', 'status': 'pass'},
        {'id': 'b-1', 'status': 'fail'},
        {'id': 'c-1', 'status': 'pass'},
      ]);
      expect(file['upstream'], {'tag': '4.8.0', 'commit': 'abc'});
    });

    test('is the same for any order of the same lines', () {
      final a = [(id: 'a-1', status: 'pass'), (id: 'c-1', status: 'pass')];
      expect(
        encodeResultsFile(build(a)),
        encodeResultsFile(build(a.reversed.toList())),
      );
    });

    test('an id outside the inventory throws and names it', () {
      expect(
        () => build([(id: 'z-9', status: 'pass'), (id: 'y-9', status: 'pass')]),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('y-9, z-9'),
          ),
        ),
      );
    });
  });

  group('bin/collect_results.dart', () {
    late FixtureRepo repo;

    FixtureRepo create() {
      repo = FixtureRepo.create();
      repo.writeVectors('ethereum', [
        VectorSpec('ethereum', 'sign', 'eip1559'),
        VectorSpec('ethereum', 'sign', 'legacy'),
      ]);
      return repo;
    }

    test('writes <out>/<platform>.json in the RESULTS.md schema', () {
      create();
      repo.writeText(
        'logs/flutter_test_a.txt',
        '00:01 +0: x\n${line('ethereum-sign-legacy-1')}\n'
            '${line('ethereum-sign-eip1559-1')}\n',
      );
      repo.writeText(
        'logs/flutter_test_b.txt',
        '${line('ethereum-sign-eip1559-1')}\n',
      );
      final run = collect(
        repo,
        'android',
        [
          '${repo.root.path}/logs/flutter_test_a.txt',
          '${repo.root.path}/logs/flutter_test_b.txt',
        ],
        extra: {'--repository-sha': 'deadbeef', '--run-id': '42'},
      );
      expect(run.exitCode, 0, reason: '${run.stderr}');
      final text = File(
        '${repo.root.path}/results_out/android.json',
      ).readAsStringSync();
      expect(text, endsWith('}\n'));
      expect(jsonDecode(text), {
        'schema': 1,
        'platform': 'android',
        'upstream': {'tag': pinnedTag, 'commit': pinnedCommit},
        'repository_sha': 'deadbeef',
        'run_id': '42',
        'results': [
          {'id': 'ethereum-sign-eip1559-1', 'status': 'pass'},
          {'id': 'ethereum-sign-legacy-1', 'status': 'pass'},
        ],
      });
    });

    test('an id that is not in the inventory exits 1 and writes nothing', () {
      create();
      repo.writeText('log.txt', '${line('ethereum-sign-taproot-9')}\n');
      final run = collect(
        repo,
        'ios',
        ['${repo.root.path}/log.txt'],
        extra: {'--repository-sha': 's', '--run-id': '1'},
      );
      expect(run.exitCode, 1);
      expect(run.stderr, contains('ethereum-sign-taproot-9'));
      expect(
        File('${repo.root.path}/results_out/ios.json').existsSync(),
        isFalse,
      );
    });

    test('a log with no result lines writes an empty results list', () {
      create();
      repo.writeText('log.txt', '00:01 +0: nothing\n');
      final run = collect(
        repo,
        'ios',
        ['${repo.root.path}/log.txt'],
        extra: {'--repository-sha': 's', '--run-id': '1'},
      );
      expect(run.exitCode, 0, reason: '${run.stderr}');
      expect(run.stdout, contains('warning: no WCF_VECTOR_RESULT'));
      final json =
          jsonDecode(
                File(
                  '${repo.root.path}/results_out/ios.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      expect(json['results'], isEmpty);
    });

    test('usage errors exit 64', () {
      create();
      repo.writeText('log.txt', '');
      final log = '${repo.root.path}/log.txt';
      // no platform, bad platform, no logs, no sha/run id
      expect(
        Process.runSync(Platform.resolvedExecutable, [
          'bin/collect_results.dart',
          '--out',
          '${repo.root.path}/o',
          log,
        ]).exitCode,
        64,
      );
      expect(
        collect(
          repo,
          'windows',
          [log],
          extra: {'--repository-sha': 's', '--run-id': '1'},
        ).exitCode,
        64,
      );
      expect(
        collect(
          repo,
          'ios',
          [],
          extra: {'--repository-sha': 's', '--run-id': '1'},
        ).exitCode,
        64,
      );
      final noIds = Process.runSync(
        Platform.resolvedExecutable,
        [
          'bin/collect_results.dart',
          '--root',
          repo.root.path,
          '--platform',
          'ios',
          '--out',
          '${repo.root.path}/o',
          log,
        ],
        environment: {'GITHUB_SHA': '', 'GITHUB_RUN_ID': ''},
      );
      expect(noIds.exitCode, 64);
    });

    test('GITHUB_SHA and GITHUB_RUN_ID are the defaults', () {
      create();
      repo.writeText('log.txt', '${line('ethereum-sign-legacy-1')}\n');
      final run = Process.runSync(
        Platform.resolvedExecutable,
        [
          'bin/collect_results.dart',
          '--root',
          repo.root.path,
          '--platform',
          'ios',
          '--out',
          '${repo.root.path}/o',
          '${repo.root.path}/log.txt',
        ],
        environment: {'GITHUB_SHA': 'envsha', 'GITHUB_RUN_ID': '99'},
      );
      expect(run.exitCode, 0, reason: '${run.stderr}');
      final json =
          jsonDecode(File('${repo.root.path}/o/ios.json').readAsStringSync())
              as Map<String, Object?>;
      expect(json['repository_sha'], 'envsha');
      expect(json['run_id'], '99');
    });

    test('the file it writes passes check (a), strictly, for its claims', () {
      create();
      repo.writeVectors('ethereum', [
        VectorSpec('ethereum', 'sign', 'eip1559', platforms: ['android']),
      ]);
      Process.runSync(Platform.resolvedExecutable, [
        'bin/gen.dart',
        '--root',
        repo.root.path,
      ]);
      repo.writeText('log.txt', '${line('ethereum-sign-eip1559-1')}\n');
      final run = collect(
        repo,
        'android',
        ['${repo.root.path}/log.txt'],
        extra: {'--repository-sha': 's', '--run-id': '1'},
        out: 'test_vectors/results',
      );
      expect(run.exitCode, 0, reason: '${run.stderr}');
      repo.writeJson('test_vectors/results/ios.json', {
        'schema': 1,
        'platform': 'ios',
        'upstream': {'tag': pinnedTag, 'commit': pinnedCommit},
        'repository_sha': 's',
        'run_id': '1',
        'results': <Object?>[],
      });
      final check = Process.runSync(Platform.resolvedExecutable, [
        'bin/check.dart',
        '--strict',
        '--root',
        repo.root.path,
      ]);
      expect(check.exitCode, 0, reason: '${check.stderr}');
    });
  });
}
