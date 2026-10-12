import 'dart:convert';

/// The token a device test prints before its JSON payload
/// (`example/integration_test/vector_results.dart`).
const String resultMarker = 'WCF_VECTOR_RESULT';

const _statuses = ['pass', 'skipped', 'fail'];

final _payload = RegExp('$resultMarker (\\{[^{}]*\\})');

/// Pulls every `WCF_VECTOR_RESULT {...}` line out of device-test [log] text.
///
/// The marker may follow a reporter prefix on the same line. A line with the
/// marker and no readable payload throws [FormatException]: a result that
/// cannot be read must not be silently dropped. [source] names the log in the
/// message.
List<({String id, String status})> parseResultLines(
  String log, {
  String source = 'log',
}) {
  final results = <({String id, String status})>[];
  final lines = const LineSplitter().convert(log);
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (!line.contains(resultMarker)) continue;
    final where = '$source:${i + 1}';
    final match = _payload.firstMatch(line);
    if (match == null) {
      throw FormatException('$where: $resultMarker line without a payload');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(match.group(1)!);
    } on FormatException {
      throw FormatException('$where: $resultMarker payload is not JSON');
    }
    if (decoded is! Map<String, Object?> ||
        decoded['id'] is! String ||
        (decoded['id']! as String).isEmpty ||
        !_statuses.contains(decoded['status'])) {
      throw FormatException(
        '$where: $resultMarker payload needs a string id and a status of '
        '${_statuses.join(', ')}',
      );
    }
    results.add((
      id: decoded['id']! as String,
      status: decoded['status']! as String,
    ));
  }
  return results;
}

/// The results file for [platform]: [results] reduced to one entry per id and
/// sorted by id. When one id was printed with different statuses (a debug and a
/// release run, a retry) the worst one wins (`fail`, then `skipped`, then
/// `pass`), so a vector counts as passed only if every run that reported it
/// passed.
///
/// Throws [FormatException] for an id not in [knownIds].
Map<String, Object?> buildResultsFile({
  required String platform,
  required String upstreamTag,
  required String upstreamCommit,
  required String repositorySha,
  required String runId,
  required Iterable<({String id, String status})> results,
  required Set<String> knownIds,
}) {
  final unknown = {
    for (final r in results)
      if (!knownIds.contains(r.id)) r.id,
  }.toList()..sort();
  if (unknown.isNotEmpty) {
    throw FormatException(
      'not in the vector inventory (test_vectors/*/vectors.yaml): '
      '${unknown.join(', ')}',
    );
  }
  final worst = <String, String>{};
  for (final r in results) {
    final seen = worst[r.id];
    if (seen == null || _statuses.indexOf(r.status) > _statuses.indexOf(seen)) {
      worst[r.id] = r.status;
    }
  }
  // `_statuses` runs from best to worst, so "the higher index wins" above is
  // "the worse status wins".
  final ids = worst.keys.toList()..sort();
  return {
    'schema': 1,
    'platform': platform,
    'upstream': {'tag': upstreamTag, 'commit': upstreamCommit},
    'repository_sha': repositorySha,
    'run_id': runId,
    'results': [
      for (final id in ids) {'id': id, 'status': worst[id]},
    ],
  };
}

/// [file] as the committed text: two-space JSON and a final newline.
String encodeResultsFile(Map<String, Object?> file) =>
    '${const JsonEncoder.withIndent('  ').convert(file)}\n';
