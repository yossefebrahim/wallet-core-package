import 'package:test/test.dart';
import 'package:wcf_tool_matrix/matrix.dart';
import 'package:wcf_tool_matrix/registry.dart';
import 'package:wcf_tool_matrix/variants.dart';

import 'support.dart';

void main() {
  late FixtureRepo repo;

  group('registry ids', () {
    test('snake-case the enum member, with the Nebl exception', () {
      expect(registryIdOfEnumName('internetComputer'), 'internet_computer');
      expect(registryIdOfEnumName('bitcoin'), 'bitcoin');
      expect(registryIdOfEnumName('nebl'), 'Nebl');
    });
  });

  group('generated column', () {
    test('sign: the coin\'s proto package defines SigningInput', () {
      repo = FixtureRepo.create();
      final matrix = repo.build().matrix;
      for (final coin in ['bitcoin', 'ethereum', 'eos', 'solana']) {
        final cell = opOf(matrix, coin, 'sign');
        expect(cell.generated, Generated.yes, reason: coin);
        expect(
          (cell.evidence['proto']! as Map)['defined'],
          isTrue,
          reason: coin,
        );
      }
    });

    test('sign: aliased blockchains use their proto package; a blockchain '
        'with no proto is not generated', () {
      repo = FixtureRepo.create(
        coins: [
          ...defaultCoins,
          const FixtureCoin('orphan', 999, 'NoSuchChain'),
        ],
      );
      final matrix = repo.build().matrix;
      final cash = opOf(matrix, 'bitcoincash', 'sign');
      expect(cash.generated, Generated.yes);
      expect((cash.evidence['proto']! as Map)['package'], 'Bitcoin');
      expect(opOf(matrix, 'ronin', 'sign').generated, Generated.yes);
      final orphan = opOf(matrix, 'orphan', 'sign');
      expect(orphan.generated, Generated.no);
      expect((orphan.evidence['proto']! as Map)['defined'], isFalse);
    });

    test('sign_message: proto and the generic probe agree', () {
      repo = FixtureRepo.create();
      final matrix = repo.build().matrix;
      expect(opOf(matrix, 'ethereum', 'sign_message').generated, Generated.yes);
      expect(opOf(matrix, 'ronin', 'sign_message').generated, Generated.yes);
      expect(opOf(matrix, 'solana', 'sign_message').generated, Generated.yes);
      expect(opOf(matrix, 'bitcoin', 'sign_message').generated, Generated.no);
      final cell = opOf(matrix, 'ethereum', 'sign_message');
      expect(cell.evidence.keys, containsAll(['proto', 'probe']));
      expect(matrix.conflicts, isEmpty);
    });

    test('sign_message: a disagreement is a reported conflict cell', () {
      final coins = defaultCoins;
      final classic = coins.singleWhere((c) => c.enumName == 'classic');
      final messageRows = [
        for (final row in defaultMessageRows(coins))
          if (row['coin_id'] == classic.coinId)
            // The proto defines MessageSigningInput; the probe says no.
            probeRow(classic, message: true)
          else
            row,
      ];
      repo = FixtureRepo.create(messageRows: messageRows);
      final result = repo.build();
      final cell = opOf(result.matrix, 'classic', 'sign_message');
      expect(cell.generated, Generated.conflict);
      expect(cell.variants, isEmpty);
      expect(cell.conflict, contains('defines MessageSigningInput'));
      expect(cell.conflict, contains('unsupported'));
      expect(result.matrix.conflicts.map((c) => '${c.coin}/${c.operation}'), [
        'classic/sign_message',
      ]);
      expect(result.problems, isEmpty);
    });

    test(
      'sign_message: the opposite disagreement, and an indeterminate probe',
      () {
        final coins = defaultCoins;
        final bitcoin = coins.singleWhere((c) => c.enumName == 'bitcoin');
        final solana = coins.singleWhere((c) => c.enumName == 'solana');
        final messageRows = [
          for (final row in defaultMessageRows(coins))
            if (row['coin_id'] == bitcoin.coinId)
              probeRow(
                bitcoin,
                static: 'supported',
                runtime: 'supported',
                message: true,
              )
            else if (row['coin_id'] == solana.coinId)
              probeRow(
                solana,
                static: 'supported',
                runtime: 'unsupported',
                agreement: 'conflict',
                message: true,
              )
            else
              row,
        ];
        repo = FixtureRepo.create(messageRows: messageRows);
        final matrix = repo.build().matrix;
        final bitcoinCell = opOf(matrix, 'bitcoin', 'sign_message');
        expect(bitcoinCell.generated, Generated.conflict);
        expect(
          bitcoinCell.conflict,
          contains('defines no MessageSigningInput'),
        );
        expect(
          opOf(matrix, 'solana', 'sign_message').generated,
          Generated.conflict,
        );
        expect(
          opOf(matrix, 'solana', 'sign_message').conflict,
          contains('indeterminate'),
        );
      },
    );

    test('plan: the proto defines TransactionPlan', () {
      repo = FixtureRepo.create();
      final matrix = repo.build().matrix;
      expect(opOf(matrix, 'bitcoin', 'plan').generated, Generated.yes);
      expect(opOf(matrix, 'bitcoincash', 'plan').generated, Generated.yes);
      expect(opOf(matrix, 'ethereum', 'plan').generated, Generated.no);
      expect(opOf(matrix, 'solana', 'plan').generated, Generated.no);
    });

    test('compile: probe agreement, an aborting entry, a refusing one', () {
      repo = FixtureRepo.create();
      final matrix = repo.build().matrix;
      expect(opOf(matrix, 'ethereum', 'compile').generated, Generated.yes);
      expect(opOf(matrix, 'ethereum', 'compile').note, isNull);
      final eos = opOf(matrix, 'eos', 'compile');
      expect(eos.generated, Generated.yes);
      expect(eos.note, 'aborts on malformed input');
      expect(eos.evidence['probe'], containsPair('agreement', 'crash'));
      expect(
        opOf(matrix, 'internet_computer', 'compile').generated,
        Generated.no,
      );
    });

    test('compile: static and runtime disagreeing is a conflict, never '
        'resolved', () {
      final coins = defaultCoins;
      final ethereum = coins.singleWhere((c) => c.enumName == 'ethereum');
      final rows = [
        for (final row in defaultCompilerRows(coins))
          if (row['coin_id'] == ethereum.coinId)
            probeRow(
              ethereum,
              static: 'supported',
              runtime: 'empty',
              agreement: 'conflict',
            )
          else
            row,
      ];
      repo = FixtureRepo.create(compilerRows: rows);
      final matrix = repo.build().matrix;
      final cell = opOf(matrix, 'ethereum', 'compile');
      expect(cell.generated, Generated.conflict);
      expect(cell.conflict, contains('static=supported, runtime=empty'));
      expect(matrix.conflicts.single.coin, 'ethereum');
    });

    test('address: the registry lists a derivation', () {
      repo = FixtureRepo.create(
        coins: [
          ...defaultCoins,
          const FixtureCoin('bare', 998, 'Bitcoin', derivations: 0),
        ],
        exposedGroups: const [],
      );
      final matrix = repo.build().matrix;
      expect(opOf(matrix, 'bitcoin', 'address').generated, Generated.yes);
      expect(opOf(matrix, 'Nebl', 'address').generated, Generated.yes);
      expect(opOf(matrix, 'bare', 'address').generated, Generated.no);
      expect(opOf(matrix, 'bare', 'address').variants, isEmpty);
    });

    test('a coin with no evidence row is a conflict and a problem', () {
      final coins = defaultCoins;
      repo = FixtureRepo.create(
        compilerRows: [
          for (final r in defaultCompilerRows(coins))
            if (r['coin_id'] != 0) r,
        ],
      );
      final result = repo.build();
      expect(
        opOf(result.matrix, 'bitcoin', 'compile').generated,
        Generated.conflict,
      );
      expect(result.problems, contains(contains('bitcoin: no compiler row')));
    });

    test('evidence for another upstream commit is a problem', () {
      repo = FixtureRepo.create(
        evidenceCommit: '0000000000000000000000000000000000000000',
      );
      expect(
        repo.build().problems,
        contains(contains('coverage evidence is for upstream')),
      );
    });

    test('variant cells follow the family catalogue', () {
      repo = FixtureRepo.create();
      final matrix = repo.build().matrix;
      List<String> variants(String coin, String op) =>
          opOf(matrix, coin, op).variants.keys.toList();
      expect(variants('ethereum', 'sign'), [
        'legacy',
        'eip1559',
        'contract_call',
      ]);
      expect(variants('ethereum', 'sign_message'), ['personal', 'eip712']);
      expect(variants('bitcoin', 'plan'), [
        'p2pkh',
        'p2wpkh',
        'taproot',
        'multi_input',
      ]);
      expect(variants('solana', 'sign'), ['legacy', 'versioned']);
      expect(variants('ronin', 'sign_message'), [anyVariant]);
      expect(variants('eos', 'sign'), [anyVariant]);
      expect(variants('bitcoin', 'address'), ['n/a']);
      expect(variants('ethereum', 'plan'), isEmpty);
    });

    test('totals count coins per operation and per variant', () {
      repo = FixtureRepo.create();
      final matrix = repo.build().matrix;
      final sign = matrix.operationTotals('sign');
      expect((sign.generated, sign.exposed, sign.tested), (9, 2, 0));
      final eip1559 = matrix.variantTotals().singleWhere(
        (t) =>
            t.operation == 'sign' &&
            t.family == 'evm' &&
            t.variant == 'eip1559',
      );
      // ethereum, classic (evm family); ronin is family other.
      expect(
        (
          eip1559.counts.generated,
          eip1559.counts.exposed,
          eip1559.counts.tested,
        ),
        (2, 2, 0),
      );
    });
  });
}
