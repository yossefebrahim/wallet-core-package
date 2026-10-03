// PRD §12.2 step 11: consume the packages the way a real app will.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.
//
// A fresh Flutter app, a `hosted:` dependency pointing at the loopback
// repository in local_pub_repository.dart, `flutter pub get`, and one
// assertion: the resulting pubspec.lock shows all three packages with source
// `hosted` from that URL and carries no `path` entry at all. A path dependency
// resolves differently from a published one — different transitive set,
// different asset and native-hook wiring — so an evaluation that only ever
// tested `path:` has not tested what a consumer gets.
//
// Building the generated app is the evaluations' job (T1.8, T1.9), not this
// harness's.

import 'dart:io';

import 'host.dart';
import 'local_pub_repository.dart';
import 'mini_yaml.dart';
import 'proc.dart';
import 'results.dart';

class ConsumerGenOutcome {
  const ConsumerGenOutcome({
    required this.rows,
    required this.consumerDirectory,
    this.lockExcerpt = '',
  });

  final List<ResultRow> rows;
  final Directory? consumerDirectory;

  /// The pubspec.lock stanzas for the three packages, for the report.
  final String lockExcerpt;
}

/// Generates the consumer app and asserts the lock.
///
/// Everything is written under [outDirectory], which must be outside the
/// repository.
Future<ConsumerGenOutcome> generateHostedConsumer({
  required Directory outDirectory,
  List<String>? packageDirectories,
  String projectName = 'wcf_eval_consumer',
  String rootPackage = 'wallet_core_flutter',
  bool keepPubCacheEntry = false,
}) async {
  final root = repoRoot().path;
  final packages =
      packageDirectories ??
      [
        '$root/packages/wallet_core_flutter',
        '$root/packages/wallet_core_flutter_bindings',
        '$root/packages/wallet_core_flutter_native',
      ];

  final flutter = flutterPath();
  final documentedCommand =
      'dart run tools/packaging_eval/bin/consumer_gen.dart --out-dir <dir>   '
      '# flutter create + a hosted: dependency on the loopback repository, '
      'then flutter pub get';
  if (flutter == null) {
    return ConsumerGenOutcome(
      rows: [
        ResultRow(
          check: 'consumer-gen',
          target: 'consumer/pub',
          status: CheckStatus.unmeasured,
          command: documentedCommand,
          notes: 'flutter is not on PATH',
        ),
      ],
      consumerDirectory: null,
    );
  }

  outDirectory.createSync(recursive: true);
  final staging = Directory('${outDirectory.path}/pub-repository')
    ..createSync(recursive: true);
  final consumer = Directory('${outDirectory.path}/$projectName');
  if (consumer.existsSync()) consumer.deleteSync(recursive: true);

  final repository = await LocalPubRepository.serve(
    packageDirectories: packages,
    stagingRoot: staging,
  );

  final commands = <String>[];
  try {
    // Asynchronous, not `runSync`: the loopback repository is serving on this
    // isolate's event loop, and a synchronous child process would block it and
    // deadlock the pub client's first request.
    final create = await runAsync(flutter, [
      'create',
      '--project-name',
      projectName,
      '--platforms',
      'android,ios',
      consumer.path,
    ]);
    commands.add(create.command);
    if (!create.ok) {
      return ConsumerGenOutcome(
        rows: [
          ResultRow(
            check: 'consumer-gen',
            target: 'consumer/pub',
            status: CheckStatus.fail,
            command: commands.join(' ; '),
            values: {'summary': 'flutter create failed'},
            notes: create.combined.trim().split('\n').take(3).join(' / '),
          ),
        ],
        consumerDirectory: consumer,
      );
    }

    final pubspecFile = File('${consumer.path}/pubspec.yaml');
    _addHostedDependency(
      pubspecFile,
      package: rootPackage,
      version: repository.packages[rootPackage]!.version,
      hostedUrl: repository.baseUrl,
    );
    commands.add(
      'append to ${_relative(pubspecFile.path, outDirectory.path)}: '
      '"$rootPackage: {hosted: ${repository.baseUrl}, version: '
      '${repository.packages[rootPackage]!.version}}"',
    );

    final get = await runAsync(flutter, [
      'pub',
      'get',
    ], workingDirectory: consumer.path);
    commands.add('(cd ${shellQuote(consumer.path)} && ${get.command})');

    final lockFile = File('${consumer.path}/pubspec.lock');
    if (!get.ok || !lockFile.existsSync()) {
      return ConsumerGenOutcome(
        rows: [
          ResultRow(
            check: 'consumer-gen',
            target: 'consumer/pub',
            status: CheckStatus.fail,
            command: commands.join(' ; '),
            values: {
              'summary': 'flutter pub get failed',
              'routes_served': repository.requestLog,
            },
            notes: get.combined.trim().split('\n').take(6).join(' / '),
          ),
        ],
        consumerDirectory: consumer,
      );
    }

    final assertion = assertHostedLock(
      lockFile.readAsStringSync(),
      expectedPackages: repository.packages.keys.toSet(),
      hostedUrl: repository.baseUrl,
    );

    return ConsumerGenOutcome(
      rows: [
        ResultRow(
          check: 'consumer-gen',
          target: 'consumer/pub',
          status: assertion.ok ? CheckStatus.pass : CheckStatus.fail,
          command: commands.join(' ; '),
          values: {
            ...assertion.toJson(),
            'consumer': consumer.path,
            'hosted_url': repository.baseUrl,
            'routes_served': repository.requestLog.toSet().toList()..sort(),
            'summary': assertion.ok
                ? '${assertion.hostedPackages.length} packages hosted from the '
                      'local repository, 0 path entries'
                : assertion.problems.join('; '),
          },
          notes: assertion.problems.join('; '),
        ),
      ],
      consumerDirectory: consumer,
      lockExcerpt: excerptLock(
        lockFile.readAsStringSync(),
        repository.packages.keys.toSet(),
      ),
    );
  } finally {
    await repository.close();
    if (!keepPubCacheEntry) _removePubCacheEntry(repository.baseUrl);
  }
}

/// The result of the one assertion this step exists for.
class LockAssertion {
  const LockAssertion({
    required this.hostedPackages,
    required this.pathPackages,
    required this.problems,
  });

  final List<String> hostedPackages;
  final List<String> pathPackages;
  final List<String> problems;

  bool get ok => problems.isEmpty;

  Map<String, Object?> toJson() => {
    'hosted_packages': hostedPackages,
    'path_packages': pathPackages,
  };
}

/// Every expected package must be `source: hosted` with `description.url`
/// equal to the local repository, and the whole lock must contain no `path`
/// source at all.
LockAssertion assertHostedLock(
  String lockContents, {
  required Set<String> expectedPackages,
  required String hostedUrl,
}) {
  final lock = parseMiniYaml(lockContents);
  final packages = lock['packages'];
  if (packages is! Map<String, Object?>) {
    return const LockAssertion(
      hostedPackages: [],
      pathPackages: [],
      problems: ['pubspec.lock has no `packages` map'],
    );
  }

  final hosted = <String>[];
  final byPath = <String>[];
  final problems = <String>[];

  for (final entry in packages.entries) {
    final value = entry.value;
    if (value is! Map<String, Object?>) continue;
    final source = value['source'];
    if (source == 'path') byPath.add(entry.key);
    if (!expectedPackages.contains(entry.key)) continue;

    if (source != 'hosted') {
      problems.add('${entry.key} resolved from source `$source`, not `hosted`');
      continue;
    }
    final description = value['description'];
    final url = description is Map<String, Object?>
        ? '${description['url']}'
        : '';
    if (url != hostedUrl) {
      problems.add('${entry.key} resolved from `$url`, not `$hostedUrl`');
      continue;
    }
    hosted.add(entry.key);
  }

  for (final expected in expectedPackages) {
    if (!packages.containsKey(expected)) {
      problems.add('$expected is not in the lock at all');
    }
  }
  if (byPath.isNotEmpty) {
    problems.add('path dependencies in the lock: ${byPath.join(', ')}');
  }

  hosted.sort();
  byPath.sort();
  return LockAssertion(
    hostedPackages: hosted,
    pathPackages: byPath,
    problems: problems,
  );
}

/// The lock stanzas for [packages], verbatim, for the report.
String excerptLock(String lockContents, Set<String> packages) {
  final lines = lockContents.split('\n');
  final buffer = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    final match = RegExp(r'^  ([A-Za-z0-9_]+):$').firstMatch(lines[i]);
    if (match == null || !packages.contains(match.group(1))) continue;
    buffer.writeln(lines[i]);
    for (var j = i + 1; j < lines.length; j++) {
      // The next package stanza, or the next top-level key (`sdks:`).
      if (RegExp(r'^ {0,3}\S').hasMatch(lines[j])) break;
      buffer.writeln(lines[j]);
    }
  }
  return buffer.toString();
}

void _addHostedDependency(
  File pubspec, {
  required String package,
  required String version,
  required String hostedUrl,
}) {
  final lines = pubspec.readAsStringSync().split('\n');
  final index = lines.indexWhere((l) => l.trimRight() == 'dependencies:');
  if (index < 0) {
    throw StateError('generated pubspec has no `dependencies:` block');
  }
  lines.insertAll(index + 1, [
    '  $package:',
    '    hosted: $hostedUrl',
    '    version: $version',
  ]);
  pubspec.writeAsStringSync(lines.join('\n'));
}

/// Drops the cache entry the run created, so a loopback port number does not
/// accumulate directories under the developer's pub cache.
void _removePubCacheEntry(String baseUrl) {
  final home = Platform.environment['HOME'];
  final cache = Platform.environment['PUB_CACHE'] ?? '$home/.pub-cache';
  final host = Uri.parse(baseUrl).host;
  final port = Uri.parse(baseUrl).port;
  for (final encoded in ['$host%58$port', '$host:$port']) {
    final directory = Directory('$cache/hosted/$encoded');
    if (directory.existsSync()) {
      try {
        directory.deleteSync(recursive: true);
      } on FileSystemException {
        // Leaving one stale directory behind is not worth failing a run over.
      }
    }
  }
}

String _relative(String path, String base) =>
    path.startsWith(base) ? path.substring(base.length + 1) : path;
