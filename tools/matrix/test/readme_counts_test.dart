import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wcf_tool_matrix/checks.dart';
import 'package:wcf_tool_matrix/readme_counts.dart';
import 'package:wcf_tool_matrix/render.dart';

import 'support.dart';

const _forbidden = [
  'supported',
  'zeroization',
  'secret-free',
  'audited',
  'reproducible',
];

String _readme(FixtureRepo repo) =>
    File(repo.paths.readmeFile).readAsStringSync();

/// The generated region of [text], between the markers, markers excluded.
String _region(String text) => text.substring(
  text.indexOf(openMarker) + openMarker.length,
  text.indexOf(closeMarker),
);

void main() {
  late FixtureRepo repo;

  group('marker parsing', () {
    const body = 'BODY';

    test('replaces only the text between the markers', () {
      final out = replaceRegion('a\n$openMarker\nold\n$closeMarker\nb', body);
      expect(out, 'a\n$openMarker\n\nBODY\n\n$closeMarker\nb');
    });

    test('a missing opening marker is an error', () {
      expect(
        () => replaceRegion('a\n$closeMarker\n', body),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('no $openMarker'),
          ),
        ),
      );
    });

    test('a missing closing marker is an error', () {
      expect(
        () => replaceRegion('a\n$openMarker\n', body),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('no $closeMarker'),
          ),
        ),
      );
    });

    test('no markers at all is an error, not an append', () {
      expect(() => replaceRegion('# readme\n', body), throwsFormatException);
    });

    test('reversed markers are an error', () {
      expect(
        () => replaceRegion('$closeMarker\nx\n$openMarker\n', body),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('before'),
          ),
        ),
      );
    });

    test('a repeated marker is an error', () {
      expect(
        () => replaceRegion('$openMarker\n$openMarker\n$closeMarker\n', body),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('more than one $openMarker'),
          ),
        ),
      );
      expect(
        () => replaceRegion('$openMarker\n$closeMarker\n$closeMarker\n', body),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('more than one $closeMarker'),
          ),
        ),
      );
    });

    test('a missing README file is an error', () {
      repo = FixtureRepo.create();
      File(repo.paths.readmeFile).deleteSync();
      expect(
        () => regeneratedReadme(repo.paths, repo.build().matrix),
        throwsFormatException,
      );
    });
  });

  group('generated region', () {
    test('bytes outside the markers are preserved exactly', () {
      repo = FixtureRepo.create();
      final result = repo.build();
      expect(result.problems, isEmpty);
      final out = regeneratedReadme(repo.paths, result.matrix);
      final start = fixtureReadme.indexOf(openMarker) + openMarker.length;
      final end = fixtureReadme.indexOf(closeMarker);
      expect(
        out.substring(0, start),
        fixtureReadme.substring(0, start),
        reason: 'prefix incl. trailing spaces',
      );
      expect(
        out.substring(out.length - (fixtureReadme.length - end)),
        fixtureReadme.substring(end),
        reason: 'suffix incl. CRLF and missing final newline',
      );
    });

    test('regeneration is idempotent', () {
      repo = FixtureRepo.create();
      final matrix = repo.build().matrix;
      final once = regeneratedReadme(repo.paths, matrix);
      File(repo.paths.readmeFile).writeAsStringSync(once);
      expect(regeneratedReadme(repo.paths, matrix), once);
    });

    test('gen twice leaves byte-identical README bytes', () {
      repo = FixtureRepo.create();
      final args = ['bin/gen.dart', '--root', repo.root.path];
      expect(Process.runSync(Platform.resolvedExecutable, args).exitCode, 0);
      final first = File(repo.paths.readmeFile).readAsBytesSync();
      expect(Process.runSync(Platform.resolvedExecutable, args).exitCode, 0);
      expect(File(repo.paths.readmeFile).readAsBytesSync(), first);
    });

    test('counts equal the matrix JSON', () {
      repo = FixtureRepo.create();
      repo.writeVectors('ethereum', [
        VectorSpec(
          'ethereum',
          'sign',
          'eip1559',
          platforms: ['android', 'ios'],
        ),
      ]);
      final matrix = repo.build().matrix;
      final json = jsonDecode(renderJson(matrix)) as Map<String, Object?>;
      final region = renderReadmeCounts(matrix);

      // Headline: chains with any generated / exposed / tested cell, read from
      // the per-coin JSON.
      var generated = 0, exposed = 0, tested = 0;
      for (final coin in (json['coins']! as Map<String, Object?>).values) {
        final operations =
            ((coin! as Map<String, Object?>)['operations']!
                    as Map<String, Object?>)
                .values
                .cast<Map<String, Object?>>()
                .where((o) => o['generated'] == 'yes');
        final variants = [
          for (final o in operations)
            ...(o['variants']! as Map<String, Object?>).values
                .cast<Map<String, Object?>>(),
        ];
        if (operations.isEmpty) continue;
        generated++;
        if (variants.any((v) => v['exposed'] != null)) exposed++;
        if (variants.any((v) => v['tested'] == true)) tested++;
      }
      expect(tested, 1);
      expect(
        region,
        startsWith('**$generated chains generated, $exposed exposed, '),
      );
      expect(region, contains('$exposed exposed, $tested tested.**'));

      // Table: one row per totals.variants entry, in JSON order.
      final totals =
          ((json['totals']! as Map<String, Object?>)['variants']!
              as List<Object?>);
      final rows = region
          .split('\n')
          .where((l) => l.startsWith('| ') && !l.startsWith('| operation'))
          .toList();
      expect(rows, hasLength(totals.length));
      for (var i = 0; i < totals.length; i++) {
        final t = totals[i]! as Map<String, Object?>;
        expect(
          rows[i],
          '| ${t['operation']} | ${t['family']} | ${t['variant']} '
          '| ${t['generated']} | ${t['exposed']} | ${t['tested']} |',
        );
      }
    });

    test('K = 0 says plainly that nothing is verified', () {
      repo = FixtureRepo.create();
      final region = renderReadmeCounts(repo.build().matrix);
      expect(region, contains(' 0 tested.**'));
      expect(region, contains('No variant is verified on a device yet'));
      expect(region, contains('exposed, unverified'));
      expect(region, isNot(contains('have at least one variant tested')));
    });

    test('K > 0 states the per-variant caveat instead', () {
      repo = FixtureRepo.create();
      repo.writeVectors('ethereum', [
        VectorSpec(
          'ethereum',
          'sign',
          'eip1559',
          platforms: ['android', 'ios'],
        ),
      ]);
      final region = renderReadmeCounts(repo.build().matrix);
      expect(region, contains(' 1 tested.**'));
      expect(region, contains('1 of 9 chains have at least one variant'));
      expect(region, isNot(contains('No variant is verified')));
    });

    test('links the matrix, stays stable Markdown, avoids banned words', () {
      repo = FixtureRepo.create();
      final region = renderReadmeCounts(repo.build().matrix);
      expect(region, contains('(docs/capability_matrix.md)'));
      expect(region.split('\n').where((l) => l.endsWith(' ')), isEmpty);
      expect(region, isNot(contains('\r')));
      for (final word in _forbidden) {
        expect(region.toLowerCase(), isNot(contains(word)));
      }
    });
  });

  group('(d) README drift check', () {
    test('passes on a regenerated README', () {
      repo = FixtureRepo.create();
      final matrix = repo.build().matrix;
      File(
        repo.paths.readmeFile,
      ).writeAsStringSync(regeneratedReadme(repo.paths, matrix));
      expect(checkReadme(repo.paths, matrix), isEmpty);
    });

    test('fails on a hand-edited region, naming the line and the fix', () {
      repo = FixtureRepo.create();
      final matrix = repo.build().matrix;
      final text = regeneratedReadme(repo.paths, matrix);
      expect(_region(text), contains('chains generated'));
      File(
        repo.paths.readmeFile,
      ).writeAsStringSync(text.replaceFirst(' 0 tested.', ' 99 tested.'));
      final violations = checkReadme(repo.paths, matrix);
      expect(violations, hasLength(1));
      expect(violations.single, startsWith('(d) README.md differs'));
      expect(violations.single, contains('first at line'));
      expect(violations.single, contains('melos run gen:matrix'));
    });

    test('fails on an unregenerated (empty) region', () {
      repo = FixtureRepo.create();
      expect(checkReadme(repo.paths, repo.build().matrix), hasLength(1));
    });

    test('fails on broken markers', () {
      repo = FixtureRepo.create();
      File(repo.paths.readmeFile).writeAsStringSync('# no markers\n');
      final violations = checkReadme(repo.paths, repo.build().matrix);
      expect(violations.single, startsWith('(d) '));
      expect(violations.single, contains('no $openMarker'));
    });

    test('matrix:check exits 1 on a hand-edited region, 0 after gen', () {
      repo = FixtureRepo.create();
      final root = ['--root', repo.root.path];
      Process.runSync(Platform.resolvedExecutable, ['bin/gen.dart', ...root]);
      ProcessResult check() => Process.runSync(Platform.resolvedExecutable, [
        'bin/check.dart',
        ...root,
      ]);
      expect(check().exitCode, 0, reason: '${check().stderr}');

      final file = File(repo.paths.readmeFile);
      file.writeAsStringSync(
        file.readAsStringSync().replaceFirst('chains generated', 'chains'),
      );
      final failed = check();
      expect(failed.exitCode, 1);
      expect(failed.stderr, contains('matrix:check: (d) README.md differs'));
    });

    test('gen with a README missing a marker exits 1 and writes nothing', () {
      repo = FixtureRepo.create();
      File(repo.paths.readmeFile).writeAsStringSync('# no markers\n');
      final gen = Process.runSync(Platform.resolvedExecutable, [
        'bin/gen.dart',
        '--root',
        repo.root.path,
      ]);
      expect(gen.exitCode, 1);
      expect(gen.stderr, contains('nothing written'));
      expect(File(repo.paths.matrixMarkdown).existsSync(), isFalse);
      expect(_readme(repo), '# no markers\n');
    });
  });
}
