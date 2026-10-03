// A minimal local package repository, so a consumer app can depend on the
// three packages the way a real app will — hosted, never by path
// (PRD §12.2 step 11).
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.
//
// The pub client needs exactly two routes to resolve and download a hosted
// package, and this serves both and nothing else:
//
//   GET /api/packages/<name>
//       {"name": …, "latest": {…}, "versions": [{"version": …,
//        "archive_url": …, "archive_sha256": …, "pubspec": {…}}]}
//       The embedded pubspec is what pub resolves against; it never downloads
//       an archive to answer a version query.
//
//   GET /packages/<name>/versions/<version>.tar.gz
//       The archive bytes, exactly as `pub` would fetch them from pub.dev.
//
// The server binds 127.0.0.1 on an ephemeral port. It is build-time tooling on
// loopback: nothing in the three packages reaches it, or any network, at
// runtime (AGENTS.md rule 3, PRD §16 S4).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'host.dart';
import 'mini_yaml.dart';
import 'proc.dart';

/// One package staged for serving: its rewritten pubspec and its tarball.
class StagedPackage {
  StagedPackage({
    required this.name,
    required this.version,
    required this.pubspec,
    required this.archive,
    required this.archiveSha256,
  });

  final String name;
  final String version;

  /// The rewritten pubspec, as the JSON the version listing embeds.
  final Map<String, Object?> pubspec;

  final File archive;
  final String archiveSha256;
}

/// Builds a servable copy of a workspace package.
///
/// Two edits, and only these two: `resolution: workspace` and `publish_to` are
/// dropped (a workspace member is not a publishable unit), and every
/// dependency on a sibling package becomes `hosted: <baseUrl>` at its exact
/// pinned version. The exact cross-pins are preserved, so the consumer
/// resolves the same one-version-per-package set PRD §15.4 requires.
StagedPackage stagePackage({
  required String packageDirectory,
  required String baseUrl,
  required Set<String> siblingNames,
  required Directory stagingRoot,
}) {
  final source = Directory(packageDirectory);
  if (!source.existsSync()) {
    throw ArgumentError('no such package directory: $packageDirectory');
  }
  final pubspecFile = File('${source.path}/pubspec.yaml');
  final pubspec = parseMiniYaml(pubspecFile.readAsStringSync());
  final name = pubspec['name']! as String;
  final version = '${pubspec['version'] ?? '0.0.0'}';

  final staged = Directory('${stagingRoot.path}/$name')
    ..createSync(recursive: true);
  _copyPackageContents(source, staged);

  final rewritten = Map<String, Object?>.from(pubspec)
    ..remove('resolution')
    ..remove('publish_to');
  for (final section in const ['dependencies', 'dev_dependencies']) {
    final block = rewritten[section];
    if (block is! Map<String, Object?>) continue;
    final updated = Map<String, Object?>.from(block);
    for (final dependency in block.keys) {
      if (!siblingNames.contains(dependency)) continue;
      final pinned = block[dependency];
      updated[dependency] = {
        'hosted': baseUrl,
        'version': pinned is String ? pinned : version,
      };
    }
    rewritten[section] = updated;
  }
  // dev_dependencies are irrelevant to a consumer and are the most likely
  // thing to be unresolvable from a local server; pub ignores them for a
  // hosted dependency, and dropping them keeps the served pubspec honest
  // about what a consumer actually needs.
  rewritten.remove('dev_dependencies');
  rewritten.remove('dependency_overrides');

  File('${staged.path}/pubspec.yaml').writeAsStringSync(_writeYaml(rewritten));

  final archive = File('${stagingRoot.path}/$name-$version.tar.gz');
  final tar = run('tar', ['-czf', archive.path, '-C', staged.path, '.']);
  if (!tar.ok) {
    throw StateError('could not build $name-$version.tar.gz: ${tar.stderr}');
  }
  final digest = sha256OfFile(archive.path);
  if (digest == null) {
    throw StateError('could not hash ${archive.path}');
  }

  return StagedPackage(
    name: name,
    version: version,
    pubspec: rewritten,
    archive: archive,
    archiveSha256: digest,
  );
}

void _copyPackageContents(Directory source, Directory destination) {
  const skip = {
    '.dart_tool',
    'build',
    '.git',
    '.symlinks',
    'pubspec.lock',
    '.flutter-plugins-dependencies',
  };
  for (final entity in source.listSync()) {
    final name = entity.path.split(Platform.pathSeparator).last;
    if (skip.contains(name)) continue;
    final target = '${destination.path}/$name';
    if (entity is Directory) {
      Directory(target).createSync(recursive: true);
      _copyPackageContents(entity, Directory(target));
    } else if (entity is File) {
      entity.copySync(target);
    }
  }
}

/// Writes the subset of YAML a pubspec needs. Round-trips what
/// [parseMiniYaml] produced.
String _writeYaml(Map<String, Object?> map, [int indent = 0]) {
  final buffer = StringBuffer();
  final pad = ' ' * indent;
  for (final entry in map.entries) {
    final value = entry.value;
    if (value is Map<String, Object?>) {
      buffer.writeln('$pad${entry.key}:');
      buffer.write(_writeYaml(value, indent + 2));
    } else if (value is List<Object?>) {
      buffer.writeln('$pad${entry.key}:');
      for (final item in value) {
        buffer.writeln('$pad  - ${_scalarToYaml(item)}');
      }
    } else {
      buffer.writeln('$pad${entry.key}: ${_scalarToYaml(value)}');
    }
  }
  return buffer.toString();
}

String _scalarToYaml(Object? value) {
  if (value == null) return 'null';
  if (value is bool || value is num) return '$value';
  final text = '$value';
  if (text.isEmpty) return "''";
  // Bare only when the scalar cannot be mistaken for anything else; a version
  // constraint (`^3.12.0`, `>=3.44.0`) and any prose get quoted.
  if (RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_.-]*$').hasMatch(text)) return text;
  return '"${text.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}

/// The running repository.
class LocalPubRepository {
  LocalPubRepository._(this._server, this.baseUrl, this.packages);

  final HttpServer _server;

  /// `http://127.0.0.1:<port>` — what a consumer puts under `hosted:`.
  final String baseUrl;

  final Map<String, StagedPackage> packages;

  /// Requests served, for the test to assert both routes were exercised.
  final List<String> requestLog = [];

  static Future<LocalPubRepository> serve({
    required List<String> packageDirectories,
    required Directory stagingRoot,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final baseUrl = 'http://127.0.0.1:${server.port}';

    final names = <String>{
      for (final directory in packageDirectories)
        parseMiniYaml(
              File('$directory/pubspec.yaml').readAsStringSync(),
            )['name']!
            as String,
    };
    final packages = <String, StagedPackage>{};
    for (final directory in packageDirectories) {
      final staged = stagePackage(
        packageDirectory: directory,
        baseUrl: baseUrl,
        siblingNames: names,
        stagingRoot: stagingRoot,
      );
      packages[staged.name] = staged;
    }

    final repository = LocalPubRepository._(server, baseUrl, packages);
    unawaited(repository._listen());
    return repository;
  }

  Future<void> _listen() async {
    await for (final request in _server) {
      requestLog.add(request.uri.path);
      try {
        await _handle(request);
      } on Object catch (e) {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('$e');
        await request.response.close();
      }
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;

    final listing = RegExp(r'^/api/packages/([A-Za-z0-9_]+)$').firstMatch(path);
    if (listing != null) {
      final package = packages[listing.group(1)];
      if (package == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final version = {
        'version': package.version,
        'archive_url':
            '$baseUrl/packages/${package.name}/versions/'
            '${package.version}.tar.gz',
        'archive_sha256': package.archiveSha256,
        'pubspec': package.pubspec,
      };
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType(
          'application',
          'vnd.pub.v2+json',
          charset: 'utf-8',
        )
        ..write(
          jsonEncode({
            'name': package.name,
            'latest': version,
            'versions': [version],
          }),
        );
      await request.response.close();
      return;
    }

    final download = RegExp(
      r'^/packages/([A-Za-z0-9_]+)/versions/(.+)\.tar\.gz$',
    ).firstMatch(path);
    if (download != null) {
      final package = packages[download.group(1)];
      if (package == null || package.version != download.group(2)) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType('application', 'octet-stream');
      await request.response.addStream(package.archive.openRead());
      await request.response.close();
      return;
    }

    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }

  Future<void> close() => _server.close(force: true);
}
