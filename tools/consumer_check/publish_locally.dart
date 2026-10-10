// `tools/consumer_check.sh --stage publish_locally` — PRD §12.2 step 11.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.
//
// Publishes the three packages to the T1.19 loopback package repository
// (tools/packaging_eval/lib/local_pub_repository.dart) and proves the
// publication over HTTP, as the pub client will see it:
//
//   1. stage each of packages/* (pubspec rewritten: workspace fields dropped,
//      every sibling dependency `hosted:` at its exact pinned version), tar it,
//      hash it, and serve it on 127.0.0.1;
//   2. GET /api/packages/<name> for each: one version, the staged version,
//      a pubspec with no `path:` dependency, no workspace field, and every
//      sibling hosted at this repository;
//   3. GET the archive_url it lists: its sha256 is the listed archive_sha256
//      and the archive has a pubspec.yaml and a lib/ at its root;
//   4. stop the server (unless --keep-alive).
//
// With --keep-alive the process does not exit after a successful check — it
// writes <staging-dir>/port, writes its own pid to --pid-file if given,
// and serves until killed; on a failed check it closes the server and exits 1;
// --pid-file is ignored without --keep-alive.
//
// Build-time tooling on loopback only: nothing in the three packages reaches
// this server, or any network, at runtime (AGENTS.md rule 3). Everything is
// written under --staging-dir, which must be outside the repository.
//
// Not a package of its own: it runs under the workspace root's package config
// (`melos bootstrap`), which resolves every workspace member,
// wcf_tool_packaging_eval included. The root pubspec does not list that member
// as a dependency, hence the one lint suppressed below.
//
//   dart run tools/consumer_check/publish_locally.dart --staging-dir DIR

// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:wcf_tool_packaging_eval/host.dart' show sha256OfFile;
import 'package:wcf_tool_packaging_eval/local_pub_repository.dart';

const List<String> _packageNames = [
  'wallet_core_flutter',
  'wallet_core_flutter_bindings',
  'wallet_core_flutter_native',
];

const String _usage = '''
Usage: dart run tools/consumer_check/publish_locally.dart --staging-dir DIR [--keep-alive] [--pid-file PATH]

Stages the three packages, serves them from a loopback package repository,
fetches every listing and archive back over HTTP and checks them.
With --keep-alive the process does not exit after a successful check — it writes
<staging-dir>/port, writes its own pid to --pid-file if given, and serves until
killed; on a failed check it closes the server and exits 1; --pid-file is
ignored without --keep-alive. DIR is emptied first and must be outside the repository.
''';

Future<void> main(List<String> arguments) async {
  String? stagingPath;
  String? pidFile;
  bool keepAlive = false;

  for (var i = 0; i < arguments.length; i++) {
    final arg = arguments[i];
    if (arg == '--staging-dir' && i + 1 < arguments.length) {
      stagingPath = arguments[++i];
    } else if (arg == '--pid-file' && i + 1 < arguments.length) {
      pidFile = arguments[++i];
    } else if (arg == '--keep-alive') {
      keepAlive = true;
    }
  }

  if (stagingPath == null) {
    stderr.write(_usage);
    exitCode = 64;
    return;
  }
  // This file is tools/consumer_check/publish_locally.dart.
  final root = Directory.fromUri(Platform.script.resolve('../../'));
  if (!File('${root.path}compat_manifest.json').existsSync()) {
    stderr.writeln('publish_locally: no repository root at ${root.path}');
    exitCode = 70;
    return;
  }
  final staging = Directory(stagingPath).absolute;
  if (_isInside(staging, root)) {
    stderr.writeln(
      'publish_locally: --staging-dir must be outside the repository',
    );
    exitCode = 64;
    return;
  }
  if (staging.existsSync()) staging.deleteSync(recursive: true);
  staging.createSync(recursive: true);

  final repository = await LocalPubRepository.serve(
    packageDirectories: [
      for (final name in _packageNames) '${root.path}packages/$name',
    ],
    stagingRoot: Directory('${staging.path}/staged')..createSync(),
  );
  final problems = <String>[];
  final client = HttpClient();
  try {
    stdout.writeln('publish_locally: serving at ${repository.baseUrl}');
    for (final name in _packageNames) {
      problems.addAll(
        await _check(client, repository, name, Directory(staging.path)),
      );
    }
  } finally {
    client.close(force: true);
  }

  if (!keepAlive) {
    await repository.close();
  }
  final routes = repository.requestLog.toSet().toList()..sort();
  stdout.writeln('publish_locally: routes served: ${routes.join(' ')}');
  if (!keepAlive) {
    stdout.writeln(
      'publish_locally: server stopped; staged under ${staging.path}',
    );
  }
  if (problems.isNotEmpty) {
    if (keepAlive) {
      await repository.close();
    }
    for (final problem in problems) {
      stderr.writeln('publish_locally: FAIL $problem');
    }
    exitCode = 1;
    return;
  }
  if (keepAlive) {
    stdout.writeln(
      'publish_locally: server kept alive; staged under ${staging.path}',
    );
  }
  stdout.writeln(
    'publish_locally: OK — ${_packageNames.length} packages published to '
    'the loopback repository and fetched back intact',
  );
  if (keepAlive) {
    if (pidFile != null) {
      File(pidFile).writeAsStringSync('$pid');
    }
    File(
      '${staging.path}/port',
    ).writeAsStringSync('${Uri.parse(repository.baseUrl).port}');
    await Completer<void>().future;
  }
}

/// Fetches [name]'s listing and archive from [repository]; returns what is
/// wrong with them.
Future<List<String>> _check(
  HttpClient client,
  LocalPubRepository repository,
  String name,
  Directory staging,
) async {
  final staged = repository.packages[name];
  if (staged == null) return ['$name was not staged'];
  final base = repository.baseUrl;

  final listing = await _get(client, Uri.parse('$base/api/packages/$name'));
  if (listing.status != HttpStatus.ok) {
    return ['$name: listing answered HTTP ${listing.status}'];
  }
  if (!listing.contentType.contains('application/vnd.pub.v2+json')) {
    return ['$name: listing content type is "${listing.contentType}"'];
  }
  final json = jsonDecode(utf8.decode(listing.body)) as Map<String, Object?>;
  final versions = json['versions'] as List<Object?>? ?? const [];
  final latest = json['latest'] as Map<String, Object?>? ?? const {};
  final problems = <String>[
    if (json['name'] != name) '$name: listing names "${json['name']}"',
    if (versions.length != 1) '$name: ${versions.length} versions listed',
    if (latest['version'] != staged.version)
      '$name: lists ${latest['version']}, staged ${staged.version}',
    ..._pubspecProblems(name, latest['pubspec'], repository),
  ];

  final archiveUrl = '${latest['archive_url']}';
  final archive = await _get(client, Uri.parse(archiveUrl));
  if (archive.status != HttpStatus.ok) {
    return [...problems, '$name: archive answered HTTP ${archive.status}'];
  }
  final downloaded = File(
    '${staging.path}/downloaded/$name-${staged.version}.tar.gz',
  )..createSync(recursive: true);
  downloaded.writeAsBytesSync(archive.body);
  final digest = sha256OfFile(downloaded.path);
  if (digest == null || digest != latest['archive_sha256']) {
    problems.add(
      '$name: archive sha256 $digest, listed ${latest['archive_sha256']}',
    );
  }
  if (digest != staged.archiveSha256) {
    problems.add('$name: served archive differs from the staged one');
  }
  final entries = Process.runSync('tar', ['-tzf', downloaded.path]);
  final names = '${entries.stdout}'.split('\n').map(_stripDot).toSet();
  if (entries.exitCode != 0 || !names.contains('pubspec.yaml')) {
    problems.add('$name: archive has no pubspec.yaml at its root');
  }
  if (!names.any((entry) => entry.startsWith('lib/'))) {
    problems.add('$name: archive has no lib/');
  }

  final siblings = [
    for (final sibling in _packageNames)
      if (sibling != name && _dependsOn(latest['pubspec'], sibling)) sibling,
  ];
  stdout.writeln(
    '  $name ${staged.version}  ${archive.body.length} bytes  '
    'sha256 $digest'
    '${siblings.isEmpty ? '' : '  hosted siblings: ${siblings.join(', ')}'}',
  );
  return problems;
}

/// What is wrong with a served pubspec: a `path:` dependency anywhere, a
/// workspace-only field, or a sibling not hosted here at its exact version.
List<String> _pubspecProblems(
  String name,
  Object? pubspec,
  LocalPubRepository repository,
) {
  if (pubspec is! Map<String, Object?>) {
    return ['$name: listing has no pubspec'];
  }
  final problems = <String>[
    for (final field in const [
      'resolution',
      'publish_to',
      'dev_dependencies',
      'dependency_overrides',
    ])
      if (pubspec.containsKey(field)) '$name: served pubspec keeps `$field`',
  ];
  final dependencies = pubspec['dependencies'];
  if (dependencies is! Map<String, Object?>) return problems;
  for (final MapEntry(key: dependency, value: spec) in dependencies.entries) {
    if (spec is Map<String, Object?> && spec.containsKey('path')) {
      problems.add('$name: `$dependency` is a path dependency');
    }
    final sibling = repository.packages[dependency];
    if (sibling == null) continue;
    final hostedHere =
        spec is Map<String, Object?> &&
        spec['hosted'] == repository.baseUrl &&
        spec['version'] == sibling.version;
    if (!hostedHere) {
      problems.add(
        '$name: `$dependency` is not hosted at ${repository.baseUrl} '
        'at ${sibling.version}',
      );
    }
  }
  return problems;
}

bool _dependsOn(Object? pubspec, String dependency) =>
    pubspec is Map<String, Object?> &&
    (pubspec['dependencies'] as Map<String, Object?>? ?? const {}).containsKey(
      dependency,
    );

Future<({int status, String contentType, List<int> body})> _get(
  HttpClient client,
  Uri uri,
) async {
  final request = await client.getUrl(uri);
  request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.pub.v2+json');
  final response = await request.close();
  final body = <int>[];
  await response.forEach(body.addAll);
  return (
    status: response.statusCode,
    contentType: response.headers.contentType?.toString() ?? '',
    body: body,
  );
}

String _stripDot(String entry) =>
    entry.startsWith('./') ? entry.substring(2) : entry;

/// Whether [directory] is [root] or below it, by normalized absolute path.
bool _isInside(Directory directory, Directory root) {
  String normalized(Directory d) =>
      Uri.directory(d.absolute.path).normalizePath().path;
  return normalized(directory).startsWith(normalized(root));
}
