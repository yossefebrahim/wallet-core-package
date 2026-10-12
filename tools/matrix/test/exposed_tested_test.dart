import 'dart:io';

import 'package:test/test.dart';
import 'package:wcf_tool_matrix/inputs.dart';
import 'package:wcf_tool_matrix/matrix.dart';
import 'package:wcf_tool_matrix/render.dart';

import 'support.dart';

VariantCell cellOf(Matrix m, String coin, String op, String variant) =>
    opOf(m, coin, op).variants[variant]!;

void main() {
  late FixtureRepo repo;

  group('exposed column', () {
    test('reads the snapshot: a list of coins, and "all"', () {
      repo = FixtureRepo.create();
      final groups = readExposed(File(repo.paths.exposedFile));
      expect(groups, hasLength(2));
      expect(groups.first.coins, isNull);
      expect(groups.last.coins, ['classic', 'ethereum']);
      expect(groups.last.exposure, 'typed');
    });

    test('lands on the cells it names and nowhere else', () {
      repo = FixtureRepo.create();
      final result = repo.build();
      expect(result.problems, isEmpty);
      final m = result.matrix;
      expect(cellOf(m, 'ethereum', 'sign', 'eip1559').exposure, 'typed');
      expect(cellOf(m, 'classic', 'sign', 'eip1559').exposure, 'typed');
      expect(cellOf(m, 'ethereum', 'sign', 'legacy').exposure, isNull);
      expect(cellOf(m, 'bitcoin', 'address', 'n/a').exposure, 'typed');
      expect(cellOf(m, 'solana', 'sign', 'legacy').exposure, isNull);
    });

    test('an entry for a coin outside the registry, an ungenerated '
        'operation or an undefined variant is a problem', () {
      repo = FixtureRepo.create(
        exposedGroups: [
          {
            'operation': 'sign',
            'variant': 'eip1559',
            'exposure': 'typed',
            'coins': ['ethereum', 'nosuchcoin'],
          },
          {
            'operation': 'plan',
            'variant': 'p2wpkh',
            'exposure': 'typed',
            'coins': ['ethereum'],
          },
          {
            'operation': 'sign',
            'variant': 'taproot',
            'exposure': 'typed',
            'coins': ['ethereum'],
          },
          {
            'operation': 'sign_message',
            'variant': 'personal',
            'exposure': 'bogus',
            'coins': ['ethereum'],
          },
        ],
      );
      final problems = repo.build().problems;
      expect(
        problems,
        contains(contains('nosuchcoin is not in the pinned registry')),
      );
      expect(
        problems,
        contains(contains('ethereum is exposed but plan is not generated')),
      );
      expect(
        problems,
        contains(contains('variant taproot is not defined for evm sign')),
      );
      expect(problems, contains(contains('exposure must be typed or generic')));
    });
  });

  group('tested column', () {
    test('tested needs one vector listing android and ios', () {
      repo = FixtureRepo.create();
      repo.writeVectors('ethereum', [
        VectorSpec(
          'ethereum',
          'sign',
          'eip1559',
          platforms: ['android', 'ios'],
        ),
        VectorSpec('ethereum', 'sign', 'legacy', platforms: ['android']),
        VectorSpec('ethereum', 'address', 'n/a', platforms: ['host']),
      ]);
      final result = repo.build();
      expect(result.problems, isEmpty);
      final m = result.matrix;

      final both = cellOf(m, 'ethereum', 'sign', 'eip1559');
      expect(both.tested, isTrue);
      expect(both.verifiedOn, {'android', 'ios'});
      expect(both.levelOn('android'), 3);
      expect(both.levelOn('ios'), 3);
      expect(both.vectorIds, ['ethereum-sign-eip1559-1']);

      final one = cellOf(m, 'ethereum', 'sign', 'legacy');
      expect(one.tested, isFalse);
      expect(one.verifiedOn, {'android'});
      expect(one.levelOn('android'), 3);
      expect(one.levelOn('ios'), isNot(3));

      // `host` is no device run: the cell stays exposed, unverified.
      final host = cellOf(m, 'ethereum', 'address', 'n/a');
      expect(host.tested, isFalse);
      expect(host.verifiedOn, isEmpty);
      expect(host.levelOn('android'), 2);

      // An exposed variant nobody tested, and a variant that is not exposed.
      expect(cellOf(m, 'ethereum', 'sign', 'contract_call').levelOn('ios'), 1);
      expect(cellOf(m, 'classic', 'sign', 'eip1559').levelOn('android'), 2);
    });

    test('two vectors, one per platform, verify both platforms but do not '
        'make the variant tested', () {
      repo = FixtureRepo.create();
      repo.writeVectors('ethereum', [
        VectorSpec('ethereum', 'sign', 'eip1559', platforms: ['android']),
        VectorSpec('ethereum', 'sign', 'eip1559', n: 2, platforms: ['ios']),
      ]);
      final cell = cellOf(repo.build().matrix, 'ethereum', 'sign', 'eip1559');
      expect(cell.verifiedOn, {'android', 'ios'});
      expect(cell.tested, isFalse);
    });

    test('totals count a coin as tested only for a tested variant', () {
      repo = FixtureRepo.create();
      repo.writeVectors('ethereum', [
        VectorSpec(
          'ethereum',
          'sign',
          'eip1559',
          platforms: ['android', 'ios'],
        ),
      ]);
      final m = repo.build().matrix;
      expect(m.operationTotals('sign').tested, 1);
      expect(m.operationTotals('address').tested, 0);
    });

    test('a vector binds to its coin\'s family: an Ethereum taproot vector '
        'fails', () {
      repo = FixtureRepo.create();
      repo.writeVectors('ethereum', [
        VectorSpec('ethereum', 'sign', 'taproot'),
        VectorSpec('ethereum', 'plan', 'p2wpkh'),
        VectorSpec('ethereum', 'sign', 'versioned', n: 2),
      ]);
      final problems = repo.build().problems;
      expect(
        problems,
        contains(
          contains(
            'vector ethereum-sign-taproot-1: variant taproot is not defined '
            'for evm sign',
          ),
        ),
      );
      expect(
        problems,
        contains(
          contains('vector ethereum-plan-p2wpkh-1: plan is not generated'),
        ),
      );
      expect(
        problems,
        contains(
          contains('vector ethereum-sign-versioned-2: variant versioned'),
        ),
      );
    });

    test('a vector for a coin outside the registry is a problem; an '
        'invalid_input vector is recorded but is no cell', () {
      repo = FixtureRepo.create();
      repo.writeVectors('ethereum', [
        VectorSpec('ethereum', 'invalid_input', 'n/a'),
      ]);
      repo.writeVectors('ghost', [VectorSpec('ghost', 'address', 'n/a')]);
      final result = repo.build();
      expect(
        result.problems,
        contains(contains('coin ghost is not in the pinned registry')),
      );
      expect(
        result.matrix.vectors.map((v) => v.id),
        containsAll(['ethereum-invalid_input-n/a-1', 'ghost-address-n/a-1']),
      );
      expect(
        opOf(
          result.matrix,
          'ethereum',
          'sign',
        ).variants.values.expand((v) => v.vectorIds),
        isEmpty,
      );
    });

    test('an inventory the validator rejects is a problem', () {
      repo = FixtureRepo.create();
      repo.writeText(
        'test_vectors/ethereum/vectors.yaml',
        'vectors:\n  - id: x\n',
      );
      expect(repo.build().problems, contains(startsWith('inventory: ')));
    });
  });

  group('rendering', () {
    test('non-tested exposed cells read "exposed, unverified"; markdown '
        'carries the disclaimer, the pin and the totals', () {
      repo = FixtureRepo.create();
      repo.writeVectors('ethereum', [
        VectorSpec('ethereum', 'sign', 'eip1559', platforms: ['android']),
        VectorSpec('ethereum', 'sign', 'legacy', platforms: ['ios']),
      ]);
      final matrix = repo.build().matrix;
      final md = renderMarkdown(matrix);
      expect(md, contains(disclaimer));
      expect(md, contains('generated by `melos run gen:matrix` — do not edit'));
      expect(md, contains('Tag $pinnedTag, Commit `$pinnedCommit`'));
      expect(md, contains('| sign | 9 | 2 | 0 |'));
      expect(md, contains('exposed, unverified'));
      expect(md, contains('exposed, unverified (verified on android only)'));
      expect(md, contains('generated (verified on ios only)'));
      expect(md, contains('generated, aborts on malformed input'));
      for (final banned in [
        'zeroization',
        'secret-free',
        'audited',
        'reproducible',
      ]) {
        expect(md.toLowerCase(), isNot(contains(banned)), reason: banned);
      }
      expect(md, isNot(contains('supported')));
    });

    test('coins with the same cells share a row', () {
      repo = FixtureRepo.create();
      final md = renderMarkdown(repo.build().matrix);
      expect(md, contains('| evm | 2: classic, ethereum |'));
    });

    test('two runs are byte-identical, whatever the input order', () {
      repo = FixtureRepo.create();
      repo.writeVectors('ethereum', [
        VectorSpec(
          'ethereum',
          'sign',
          'eip1559',
          platforms: ['android', 'ios'],
        ),
        VectorSpec('ethereum', 'address', 'n/a'),
      ]);
      final a = repo.build().matrix;
      final b = repo.build().matrix;
      expect(renderJson(a), renderJson(b));
      expect(renderMarkdown(a), renderMarkdown(b));

      final reversed = FixtureRepo.create(
        coins: defaultCoins.reversed.toList(),
      );
      reversed.writeVectors('ethereum', [
        VectorSpec('ethereum', 'address', 'n/a'),
        VectorSpec(
          'ethereum',
          'sign',
          'eip1559',
          platforms: ['android', 'ios'],
        ),
      ]);
      expect(renderJson(reversed.build().matrix), renderJson(a));
      expect(renderMarkdown(reversed.build().matrix), renderMarkdown(a));
    });
  });
}
