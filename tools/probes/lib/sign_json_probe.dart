import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart';

class ProbeRow {
  final String coinName;
  final int coinId;
  final bool? supportsJson;
  final String? error;

  ProbeRow({
    required this.coinName,
    required this.coinId,
    this.supportsJson,
    this.error,
  });
}

List<ProbeRow> probe(WalletCoreBindings bindings) {
  final rows = <ProbeRow>[];
  for (final coin in TWCoinType.values) {
    try {
      final supports = bindings.TWAnySignerSupportsJSON(coin);
      rows.add(
        ProbeRow(
          coinName: coin.name,
          coinId: coin.value,
          supportsJson: supports,
        ),
      );
    } catch (e) {
      rows.add(
        ProbeRow(
          coinName: coin.name,
          coinId: coin.value,
          error: e.runtimeType.toString(),
        ),
      );
    }
  }
  return rows;
}

String renderMarkdown(
  List<ProbeRow> rows, {
  required String upstreamTag,
  required String upstreamCommit,
  required String libraryCommit,
  required String artifactSetId,
  required String librarySha256,
}) {
  final sortedRows = List<ProbeRow>.from(rows)
    ..sort((a, b) => a.coinId.compareTo(b.coinId));

  int supported = 0;
  int notSupported = 0;
  int errors = 0;

  for (final row in sortedRows) {
    if (row.error != null) {
      errors++;
    } else if (row.supportsJson == true) {
      supported++;
    } else {
      notSupported++;
    }
  }

  final buffer = StringBuffer();
  buffer.writeln('# `TWAnySignerSupportsJSON` coverage probe');
  buffer.writeln();
  buffer.writeln(
    'Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.',
  );
  buffer.writeln();
  buffer.writeln(
    '**Upstream Pin:** Tag $upstreamTag, Commit `$upstreamCommit`',
  );
  buffer.writeln();
  buffer.writeln(
    '**Library Checked:** Artifact Set `$artifactSetId`, Commit `$libraryCommit`, SHA-256 `$librarySha256`',
  );
  buffer.writeln();
  buffer.writeln(
    '**Measured:** `TWAnySignerSupportsJSON` for all coins in `TWCoinType`',
  );
  buffer.writeln();
  buffer.writeln('**Command:** `melos run probe:sign-json`');
  buffer.writeln();
  buffer.writeln('## Totals');
  buffer.writeln();
  buffer.writeln('- Supported: $supported');
  buffer.writeln('- Not supported: $notSupported');
  buffer.writeln('- Error: $errors');
  buffer.writeln('- Total: ${rows.length}');
  buffer.writeln();
  buffer.writeln('## Coverage Table');
  buffer.writeln();
  buffer.writeln('| coin id | TWCoinType | supports JSON |');
  buffer.writeln('|---|---|---|');

  for (final row in sortedRows) {
    final supportText = row.error != null
        ? 'error: ${row.error}'
        : (row.supportsJson! ? 'true' : 'false');
    buffer.writeln('| ${row.coinId} | ${row.coinName} | $supportText |');
  }

  return buffer.toString();
}
