import 'package:wcf_tool_vectors/validator.dart';

import 'inputs.dart';
import 'registry.dart';
import 'variants.dart';

/// Whether an operation is generated for a coin (PRD §13.1).
enum Generated {
  /// The coin's proto defines the operation's input (or the probe evidence
  /// shows the entry point answers) and the registry lists the coin.
  yes,

  /// Neither source says the operation exists for this coin.
  no,

  /// The two evidence sources disagree, or one of them is missing or
  /// indeterminate. Reported, never resolved.
  conflict,
}

/// One (coin, operation, variant) cell.
class VariantCell {
  VariantCell(this.variant);

  final String variant;

  /// `typed` or `generic`; `null` when the SDK offers no path.
  String? exposure;

  /// Ids of the vectors for exactly this cell.
  final List<String> vectorIds = [];

  /// Platforms ([platforms]) some vector of this cell claims in
  /// `platforms_verified`.
  final Set<String> verifiedOn = {};

  /// A single vector for this cell claims every platform in [platforms]
  /// (PRD §13.1 *Tested*).
  bool tested = false;

  /// 1 generated, 2 exposed, 3 verified on [platform]. Check (c) (PRD §13.2)
  /// fails when one of these goes down.
  int levelOn(String platform) {
    if (verifiedOn.contains(platform)) return 3;
    return exposure != null ? 2 : 1;
  }
}

/// One (coin, operation): the generated verdict, the evidence behind it, and
/// the variant cells that exist when it is generated.
class OperationCell {
  OperationCell({
    required this.operation,
    required this.generated,
    required this.evidence,
    this.note,
    this.conflict,
  });

  final String operation;
  final Generated generated;
  final Map<String, Object?> evidence;

  /// Qualifies a `yes`: `aborts on malformed input` for a compiler entry whose
  /// probe child process died.
  final String? note;

  /// Why the sources disagree, for a `conflict`.
  final String? conflict;

  /// By variant, in catalogue order. Empty unless [generated] is `yes`.
  final Map<String, VariantCell> variants = {};

  bool get anyExposed => variants.values.any((v) => v.exposure != null);
  bool get anyTested => variants.values.any((v) => v.tested);
}

class CoinRow {
  CoinRow({
    required this.coin,
    required this.family,
    required this.proto,
    required this.operations,
  });

  final RegistryCoin coin;
  final String family;
  final String proto;
  final Map<String, OperationCell> operations;
}

/// Every vector of the inventory, matrix operation or not, so that a removed
/// `invalid_input` vector is caught by check (c) too.
class VectorRecord {
  const VectorRecord({
    required this.id,
    required this.coin,
    required this.operation,
    required this.variant,
    required this.platforms,
  });

  final String id;
  final String coin;
  final String operation;
  final String variant;
  final List<String> platforms;
}

class Counts {
  const Counts(this.generated, this.exposed, this.tested);
  final int generated;
  final int exposed;
  final int tested;
}

class VariantTotals {
  const VariantTotals(this.operation, this.family, this.variant, this.counts);
  final String operation;
  final String family;
  final String variant;
  final Counts counts;
}

class Conflict {
  const Conflict(this.coin, this.operation, this.detail);
  final String coin;
  final String operation;
  final String detail;
}

class Matrix {
  Matrix({required this.upstream, required this.coins, required this.vectors});

  final Upstream upstream;
  final List<CoinRow> coins;
  final List<VectorRecord> vectors;

  /// Coins, per operation, that are generated / have an exposed variant / have
  /// a tested variant.
  Counts operationTotals(String operation) {
    var generated = 0, exposed = 0, tested = 0;
    for (final row in coins) {
      final cell = row.operations[operation]!;
      if (cell.generated != Generated.yes) continue;
      generated++;
      if (cell.anyExposed) exposed++;
      if (cell.anyTested) tested++;
    }
    return Counts(generated, exposed, tested);
  }

  /// Coins, per (operation, family, variant). A family with no variants for an
  /// operation (the single cell [anyVariant]) appears only when some coin of it
  /// has the operation generated.
  List<VariantTotals> variantTotals() {
    final totals = <VariantTotals>[];
    for (final operation in operations) {
      for (final family in families) {
        for (final variant in variantsOf(family, operation)) {
          var generated = 0, exposed = 0, tested = 0;
          for (final row in coins.where((r) => r.family == family)) {
            final cell = row.operations[operation]!.variants[variant];
            if (cell == null) continue;
            generated++;
            if (cell.exposure != null) exposed++;
            if (cell.tested) tested++;
          }
          if (variant == anyVariant && generated == 0) continue;
          totals.add(
            VariantTotals(
              operation,
              family,
              variant,
              Counts(generated, exposed, tested),
            ),
          );
        }
      }
    }
    return totals;
  }

  List<Conflict> get conflicts => [
    for (final row in coins)
      for (final operation in operations)
        if (row.operations[operation]!.generated == Generated.conflict)
          Conflict(
            row.coin.id,
            operation,
            row.operations[operation]!.conflict!,
          ),
  ];
}

class BuildResult {
  const BuildResult(this.matrix, this.problems);
  final Matrix matrix;

  /// Inconsistencies between the inputs. A matrix built with problems is not
  /// written (`gen:matrix`) and fails `matrix:check`.
  final List<String> problems;
}

/// The probe's verdict as a boolean, or `null` when it is indeterminate: the
/// static and runtime evidence disagree, the child process died, or the
/// blockchain is in no static table.
bool? _probeVerdict(ProbeRow row) =>
    row.agreement == 'agree' ? row.staticVerdict == 'supported' : null;

String _probeSummary(ProbeRow row) =>
    'static=${row.staticVerdict}, runtime=${row.runtime}'
    '${row.crashDetail == null ? '' : ' (${row.crashDetail})'}';

Map<String, Object?> _probeEvidence(ProbeRow row) => {
  'static': row.staticVerdict,
  'runtime': row.runtime,
  'agreement': row.agreement,
  'crash_detail': ?row.crashDetail,
};

/// Computes the matrix from [inputs]: the generated verdicts per coin and
/// operation, then the Exposed and Tested columns laid over them.
BuildResult buildMatrix(MatrixInputs inputs) {
  final problems = <String>[
    for (final error in validateInventory(inputs.inventory))
      'inventory: $error',
  ];
  final evidence = inputs.evidence;
  if (evidence.commit != inputs.upstream.commit) {
    problems.add(
      'coverage evidence is for upstream ${evidence.commit}, compat_manifest.json '
      'pins ${inputs.upstream.commit}; rerun `melos run probe:coverage`',
    );
  }

  final rows = <CoinRow>[];
  for (final coin in inputs.coins) {
    final family = familyOfBlockchain(coin.blockchain);
    final protoName = protoOfBlockchain(coin.blockchain);
    final messages = inputs.protoMessages[protoName] ?? const <String>{};
    bool defines(String message) => messages.contains(message);
    Map<String, Object?> protoEvidence(String message) => {
      'package': protoName,
      'message': message,
      'defined': defines(message),
    };

    ProbeRow? probe(Map<int, ProbeRow> rows, String question) {
      final row = rows[coin.coinId];
      if (row == null) {
        problems.add(
          '${coin.id}: no $question row in the coverage evidence; '
          'rerun `melos run probe:coverage`',
        );
      }
      return row;
    }

    final operationsOfCoin = <String, OperationCell>{};

    operationsOfCoin['address'] = OperationCell(
      operation: 'address',
      generated: coin.derivationCount > 0 ? Generated.yes : Generated.no,
      evidence: {'derivations': coin.derivationCount},
    );

    operationsOfCoin['sign'] = OperationCell(
      operation: 'sign',
      generated: defines('SigningInput') ? Generated.yes : Generated.no,
      evidence: {'proto': protoEvidence('SigningInput')},
    );

    final messageRow = probe(evidence.message, 'message-signing');
    final protoMessage = defines('MessageSigningInput');
    final messageVerdict = messageRow == null
        ? null
        : _probeVerdict(messageRow);
    final messageEvidence = <String, Object?>{
      'proto': protoEvidence('MessageSigningInput'),
      'probe': ?(messageRow == null ? null : _probeEvidence(messageRow)),
      'specific_signer': ?messageRow?.specificSigner,
    };
    operationsOfCoin['sign_message'] = messageVerdict == null
        ? OperationCell(
            operation: 'sign_message',
            generated: Generated.conflict,
            evidence: messageEvidence,
            conflict: messageRow == null
                ? 'no generic message-signer evidence row'
                : 'proto ${protoMessage ? 'defines' : 'defines no'} '
                      'MessageSigningInput; the generic message-signer probe '
                      'is indeterminate (${_probeSummary(messageRow)})',
          )
        : messageVerdict == protoMessage
        ? OperationCell(
            operation: 'sign_message',
            generated: protoMessage ? Generated.yes : Generated.no,
            evidence: messageEvidence,
          )
        : OperationCell(
            operation: 'sign_message',
            generated: Generated.conflict,
            evidence: messageEvidence,
            conflict:
                'proto ${protoMessage ? 'defines' : 'defines no'} '
                'MessageSigningInput but the generic message-signer probe says '
                '${messageVerdict ? 'supported' : 'unsupported'} '
                '(${_probeSummary(messageRow!)})',
          );

    operationsOfCoin['plan'] = OperationCell(
      operation: 'plan',
      generated: defines('TransactionPlan') ? Generated.yes : Generated.no,
      evidence: {'proto': protoEvidence('TransactionPlan')},
    );

    final compileRow = probe(evidence.compiler, 'compiler');
    final compileVerdict = compileRow == null
        ? null
        : _probeVerdict(compileRow);
    final compileEvidence = <String, Object?>{
      'probe': ?(compileRow == null ? null : _probeEvidence(compileRow)),
    };
    if (compileVerdict != null) {
      operationsOfCoin['compile'] = OperationCell(
        operation: 'compile',
        generated: compileVerdict ? Generated.yes : Generated.no,
        evidence: compileEvidence,
      );
    } else if (compileRow != null &&
        compileRow.agreement == 'crash' &&
        compileRow.staticVerdict == 'supported') {
      // The static rules say the entry exists and the probe child died on a
      // malformed input: generated, with a distinct note, never plain support.
      operationsOfCoin['compile'] = OperationCell(
        operation: 'compile',
        generated: Generated.yes,
        evidence: compileEvidence,
        note: 'aborts on malformed input',
      );
    } else {
      operationsOfCoin['compile'] = OperationCell(
        operation: 'compile',
        generated: Generated.conflict,
        evidence: compileEvidence,
        conflict: compileRow == null
            ? 'no compiler evidence row'
            : 'the compiler probe is indeterminate '
                  '(${_probeSummary(compileRow)}, agreement=${compileRow.agreement})',
      );
    }

    for (final cell in operationsOfCoin.values) {
      if (cell.generated != Generated.yes) continue;
      for (final variant in variantsOf(family, cell.operation)) {
        cell.variants[variant] = VariantCell(variant);
      }
    }
    rows.add(
      CoinRow(
        coin: coin,
        family: family,
        proto: protoName,
        operations: {for (final op in operations) op: operationsOfCoin[op]!},
      ),
    );
  }

  final byId = {for (final row in rows) row.coin.id: row};

  // The Exposed column: the SDK's own registry, validated against the cells it
  // lands on.
  for (final group in inputs.exposed) {
    final label = '${group.operation}/${group.variant}';
    if (!operations.contains(group.operation)) {
      problems.add('exposed $label: unknown operation');
      continue;
    }
    if (group.exposure != 'typed' && group.exposure != 'generic') {
      problems.add('exposed $label: exposure must be typed or generic');
      continue;
    }
    for (final id in group.coins ?? [for (final row in rows) row.coin.id]) {
      final row = byId[id];
      if (row == null) {
        problems.add('exposed $label: $id is not in the pinned registry');
        continue;
      }
      final cell = row.operations[group.operation]!;
      if (cell.generated != Generated.yes) {
        problems.add(
          'exposed $label: $id is exposed but ${group.operation} is not '
          'generated for it (${cell.generated.name})',
        );
        continue;
      }
      final variant = cell.variants[group.variant];
      if (variant == null) {
        problems.add(
          'exposed $label: variant ${group.variant} is not defined for '
          '${row.family} ${group.operation} (defined: '
          '${cell.variants.keys.join(', ')}); coin $id',
        );
        continue;
      }
      if (variant.exposure != null) {
        problems.add('exposed $label: $id is listed twice');
        continue;
      }
      variant.exposure = group.exposure;
    }
  }

  // The Tested column: vectors, bound to the family of their coin.
  final records = <VectorRecord>[];
  for (final vector in inputs.inventory.vectors) {
    records.add(
      VectorRecord(
        id: vector.id,
        coin: vector.coin,
        operation: vector.operation,
        variant: vector.variant,
        platforms: [...vector.platformsVerified]..sort(),
      ),
    );
    if (vector.operation == 'invalid_input') continue;
    final row = byId[vector.coin];
    if (row == null) {
      problems.add(
        'vector ${vector.id}: coin ${vector.coin} is not in the pinned registry',
      );
      continue;
    }
    final cell = row.operations[vector.operation];
    if (cell == null) {
      problems.add(
        'vector ${vector.id}: ${vector.operation} is not a matrix operation',
      );
      continue;
    }
    if (cell.generated != Generated.yes) {
      problems.add(
        'vector ${vector.id}: ${vector.operation} is not generated for '
        '${vector.coin} (${cell.generated.name})',
      );
      continue;
    }
    final variant = cell.variants[vector.variant];
    if (variant == null) {
      problems.add(
        'vector ${vector.id}: variant ${vector.variant} is not defined for '
        '${row.family} ${vector.operation} (defined: '
        '${cell.variants.keys.join(', ')})',
      );
      continue;
    }
    variant.vectorIds.add(vector.id);
    for (final platform in platforms) {
      if (vector.platformsVerified.contains(platform)) {
        variant.verifiedOn.add(platform);
      }
    }
    if (platforms.every(vector.platformsVerified.contains)) {
      variant.tested = true;
    }
  }
  records.sort((a, b) => a.id.compareTo(b.id));
  for (final row in rows) {
    for (final cell in row.operations.values) {
      for (final variant in cell.variants.values) {
        variant.vectorIds.sort();
      }
    }
  }

  return BuildResult(
    Matrix(upstream: inputs.upstream, coins: rows, vectors: records),
    problems,
  );
}
