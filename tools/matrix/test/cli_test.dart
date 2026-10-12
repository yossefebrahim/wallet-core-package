import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support.dart';

/// Runs one of the package's scripts against a fixture repository.
ProcessResult run(String script, List<String> args) =>
    Process.runSync(Platform.resolvedExecutable, ['bin/$script.dart', ...args]);

void main() {
  late FixtureRepo repo;

  test('gen writes both outputs; check then passes with exit 0', () {
    repo = FixtureRepo.create();
    final gen = run('gen', ['--root', repo.root.path]);
    expect(gen.exitCode, 0, reason: '${gen.stderr}');
    expect(File(repo.paths.matrixMarkdown).existsSync(), isTrue);
    expect(File(repo.paths.matrixJson).existsSync(), isTrue);

    final check = run('check', ['--root', repo.root.path]);
    expect(check.exitCode, 0, reason: '${check.stderr}');
    expect(check.stdout, contains('matrix:check: ok'));
    expect(check.stdout, contains('(c) skipped'));
  });

  test('two gen runs write byte-identical files', () {
    repo = FixtureRepo.create();
    run('gen', ['--root', repo.root.path]);
    final first = [
      File(repo.paths.matrixMarkdown).readAsBytesSync(),
      File(repo.paths.matrixJson).readAsBytesSync(),
    ];
    run('gen', ['--root', repo.root.path]);
    expect(File(repo.paths.matrixMarkdown).readAsBytesSync(), first[0]);
    expect(File(repo.paths.matrixJson).readAsBytesSync(), first[1]);
  });

  test('gen with inconsistent inputs exits 1 and writes nothing', () {
    repo = FixtureRepo.create();
    repo.writeVectors('ethereum', [VectorSpec('ethereum', 'sign', 'taproot')]);
    final gen = run('gen', ['--root', repo.root.path]);
    expect(gen.exitCode, 1);
    expect(gen.stderr, contains('variant taproot is not defined for evm sign'));
    expect(File(repo.paths.matrixMarkdown).existsSync(), isFalse);
  });

  test('check: a hand edit exits 1 with one line per violation', () {
    repo = FixtureRepo.create();
    run('gen', ['--root', repo.root.path]);
    final file = File(repo.paths.matrixMarkdown);
    file.writeAsStringSync('${file.readAsStringSync()}hand edit\n');
    final check = run('check', ['--root', repo.root.path]);
    expect(check.exitCode, 1);
    final lines = const LineSplitter().convert(check.stderr as String);
    expect(
      lines.where((l) => l.contains('docs/capability_matrix.md')),
      hasLength(1),
    );
    expect(lines.last, contains('FAILED, 1 violations'));
  });

  test('check: an unconfirmed claim passes, and fails under --strict', () {
    repo = FixtureRepo.create();
    repo.writeVectors('ethereum', [
      VectorSpec('ethereum', 'sign', 'eip1559', platforms: ['android', 'ios']),
    ]);
    run('gen', ['--root', repo.root.path]);
    final lenient = run('check', ['--root', repo.root.path]);
    expect(lenient.exitCode, 0, reason: '${lenient.stderr}');
    expect(
      lenient.stdout,
      contains('unconfirmed: vector ethereum-sign-eip1559-1 claims android'),
    );
    final strict = run('check', ['--root', repo.root.path, '--strict']);
    expect(strict.exitCode, 1);
    expect(strict.stderr, contains('(--strict)'));
  });

  test('check: a removed vector exits 1 naming it; an exclusion clears it', () {
    repo = FixtureRepo.create();
    repo.writeVectors('ethereum', [
      VectorSpec('ethereum', 'sign', 'eip1559'),
      VectorSpec('ethereum', 'address', 'n/a'),
    ]);
    run('gen', ['--root', repo.root.path]);
    final baseline = '${repo.root.path}/baseline.json';
    File(repo.paths.matrixJson).copySync(baseline);

    repo.writeVectors('ethereum', [VectorSpec('ethereum', 'address', 'n/a')]);
    run('gen', ['--root', repo.root.path]);
    final removed = run('check', [
      '--root',
      repo.root.path,
      '--baseline',
      baseline,
    ]);
    expect(removed.exitCode, 1);
    expect(
      removed.stderr,
      contains('vector ethereum-sign-eip1559-1 was removed'),
    );

    repo.writeExclusions(
      'exclusions:\n'
      '  - coin: ethereum\n'
      '    operation: sign\n'
      '    variant: eip1559\n'
      '    reason: fixture\n',
    );
    final excluded = run('check', [
      '--root',
      repo.root.path,
      '--baseline',
      baseline,
    ]);
    expect(excluded.exitCode, 0, reason: '${excluded.stderr}');
  });

  test('usage errors exit 64', () {
    repo = FixtureRepo.create();
    expect(run('check', ['--bogus']).exitCode, 64);
    expect(run('gen', ['--strict']).exitCode, 64);
    expect(run('check', ['--root']).exitCode, 64);
    expect(
      run('check', [
        '--root',
        repo.root.path,
        '--baseline',
        '${repo.root.path}/missing.json',
      ]).exitCode,
      64,
    );
  });

  test('a missing input exits 1 with the remedy', () {
    repo = FixtureRepo.create();
    File(repo.paths.exposedFile).deleteSync();
    final gen = run('gen', ['--root', repo.root.path]);
    expect(gen.exitCode, 1);
    expect(gen.stderr, contains('exposed snapshot not found'));
  });
}
