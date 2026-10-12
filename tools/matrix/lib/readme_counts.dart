import 'dart:io';

import 'inputs.dart';
import 'matrix.dart';
import 'render.dart';

/// The README region owned by the generator (PRD §13.2, T2.11).
const String openMarker = '<!-- matrix-counts -->';
const String closeMarker = '<!-- /matrix-counts -->';

/// The body of the region: the headline counts, what each level means, and the
/// per-variant table. Every number comes from [matrix]; nothing is typed here.
/// No trailing spaces, no timestamps, no paths: two runs are byte-identical.
String renderReadmeCounts(Matrix matrix) {
  final chains = matrix.chainTotals();
  final out = StringBuffer()
    ..writeln(
      '**${chains.generated} chains generated, ${chains.exposed} exposed, '
      '${chains.tested} tested.** '
      'Per-coin detail is in the '
      '[capability matrix](docs/capability_matrix.md), which names the exact '
      'variants verified.',
    )
    ..writeln();
  if (chains.tested == 0) {
    out
      ..writeln(
        'No variant is verified on a device yet: every exposed chain is '
        'exposed, unverified.',
      )
      ..writeln();
  } else {
    out
      ..writeln(
        '${chains.tested} of ${chains.generated} chains have at least one '
        'variant tested on both Android and iOS. Testing is per variant; the '
        'table below lists which.',
      )
      ..writeln();
  }
  out
    ..writeln(
      'A chain counts at a level when at least one of its operations has a '
      'variant at that level. The levels, as the matrix defines them:',
    )
    ..writeln()
    ..writeln('- **generated** — $generatedMeaning')
    ..writeln('- **exposed** — $exposedMeaning')
    ..writeln('- **tested** — $testedMeaning')
    ..writeln()
    ..writeln(
      'Per variant, in chains (upstream ${matrix.upstream.tag}, commit '
      '`${matrix.upstream.commit}`):',
    )
    ..writeln()
    ..writeln('| operation | family | variant | generated | exposed | tested |')
    ..writeln('|---|---|---|---|---|---|');
  for (final t in matrix.variantTotals()) {
    out.writeln(
      '| ${t.operation} | ${t.family} | ${t.variant} | ${t.counts.generated} '
      '| ${t.counts.exposed} | ${t.counts.tested} |',
    );
  }
  return out.toString().trimRight();
}

/// Replaces what lies between the markers in [readme] with [body]; every byte
/// outside the markers is kept. Throws [FormatException] unless each marker
/// occurs exactly once and the opening one comes first.
String replaceRegion(String readme, String body) {
  final open = _single(readme, openMarker);
  final close = _single(readme, closeMarker);
  if (close < open) {
    throw FormatException('README.md has $closeMarker before $openMarker');
  }
  return '${readme.substring(0, open + openMarker.length)}\n\n$body\n\n'
      '${readme.substring(close)}';
}

int _single(String text, String marker) {
  final first = text.indexOf(marker);
  if (first < 0) {
    throw FormatException('README.md has no $marker marker');
  }
  if (text.indexOf(marker, first + marker.length) >= 0) {
    throw FormatException('README.md has more than one $marker marker');
  }
  return first;
}

/// The README text [paths] points at, with the region regenerated from
/// [matrix]. Throws [FormatException] when the file or a marker is missing.
String regeneratedReadme(MatrixPaths paths, Matrix matrix) {
  final file = File(paths.readmeFile);
  if (!file.existsSync()) {
    throw FormatException('${paths.readmeFile} does not exist');
  }
  return replaceRegion(file.readAsStringSync(), renderReadmeCounts(matrix));
}
