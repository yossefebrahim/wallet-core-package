// The loopback package repository: the two routes the pub client needs, and
// the two edits staging makes to a workspace member's pubspec.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.
//
// Two tiny fake packages stand in for the three real ones so the test costs a
// tarball rather than a `flutter pub get`; the acceptance test in
// consumer_gen_test.dart serves the real packages to the real client.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wcf_tool_packaging_eval/host.dart';
import 'package:wcf_tool_packaging_eval/local_pub_repository.dart';
import 'package:wcf_tool_packaging_eval/mini_yaml.dart';
import 'package:wcf_tool_packaging_eval/proc.dart';

void main() {
  late Directory scratch;
  late Directory staging;
  late String leafDirectory;
  late String rootDirectory;

  setUp(() {
    scratch = scratchDirectory('wcf-pubrepo-test-');
    staging = Directory('${scratch.path}/staging')..createSync(recursive: true);

    // A leaf package…
    leafDirectory = '${scratch.path}/src/wcf_fake_leaf';
    Directory('$leafDirectory/lib').createSync(recursive: true);
    File('$leafDirectory/pubspec.yaml').writeAsStringSync('''
name: wcf_fake_leaf
description: >-
  A leaf package staged by the local repository test.
version: 0.0.1
publish_to: none
resolution: workspace

environment:
  sdk: ^3.12.0

dev_dependencies:
  test: ^1.25.0
''');
    File(
      '$leafDirectory/lib/leaf.dart',
    ).writeAsStringSync('int leaf() => 1;\n');
    File('$leafDirectory/pubspec.lock').writeAsStringSync('# not shipped\n');
    Directory('$leafDirectory/.dart_tool').createSync(recursive: true);
    File(
      '$leafDirectory/.dart_tool/package_config.json',
    ).writeAsStringSync('{}');

    // …and a root package that depends on it at an exact pin.
    rootDirectory = '${scratch.path}/src/wcf_fake_root';
    Directory('$rootDirectory/lib').createSync(recursive: true);
    File('$rootDirectory/pubspec.yaml').writeAsStringSync('''
name: wcf_fake_root
description: >-
  A root package staged by the local repository test.
version: 0.0.1
publish_to: none
resolution: workspace

environment:
  sdk: ^3.12.0

dependencies:
  wcf_fake_leaf: 0.0.1
''');
    File(
      '$rootDirectory/lib/root.dart',
    ).writeAsStringSync('int root() => 2;\n');
  });

  tearDown(() {
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  group('stagePackage', () {
    test(
      'drops `resolution: workspace` and `publish_to` and hosts siblings',
      () {
        final staged = stagePackage(
          packageDirectory: rootDirectory,
          baseUrl: 'http://127.0.0.1:1234',
          siblingNames: {'wcf_fake_root', 'wcf_fake_leaf'},
          stagingRoot: staging,
        );

        expect(staged.name, 'wcf_fake_root');
        expect(staged.version, '0.0.1');
        expect(staged.pubspec.containsKey('resolution'), isFalse);
        expect(staged.pubspec.containsKey('publish_to'), isFalse);
        expect(staged.pubspec['dependencies'], {
          'wcf_fake_leaf': {
            'hosted': 'http://127.0.0.1:1234',
            'version': '0.0.1',
          },
        });
        expect(staged.archive.existsSync(), isTrue);
        expect(staged.archiveSha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      },
    );

    test('drops dev_dependencies, which a consumer never resolves', () {
      final staged = stagePackage(
        packageDirectory: leafDirectory,
        baseUrl: 'http://127.0.0.1:1234',
        siblingNames: {'wcf_fake_leaf'},
        stagingRoot: staging,
      );
      expect(staged.pubspec.containsKey('dev_dependencies'), isFalse);
      expect(staged.pubspec['environment'], {'sdk': '^3.12.0'});
    });

    test('a package directory that does not exist raises', () {
      expect(
        () => stagePackage(
          packageDirectory: '${scratch.path}/absent',
          baseUrl: 'http://127.0.0.1:1234',
          siblingNames: const {},
          stagingRoot: staging,
        ),
        throwsArgumentError,
      );
    });
  });

  group('LocalPubRepository over loopback', () {
    late LocalPubRepository repository;
    late HttpClient client;

    setUp(() async {
      repository = await LocalPubRepository.serve(
        packageDirectories: [rootDirectory, leafDirectory],
        stagingRoot: staging,
      );
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await repository.close();
    });

    Future<HttpClientResponse> get(String path) async {
      final request = await client.getUrl(
        Uri.parse('${repository.baseUrl}$path'),
      );
      return request.close();
    }

    test('binds 127.0.0.1 on an ephemeral port', () {
      expect(repository.baseUrl, startsWith('http://127.0.0.1:'));
      expect(Uri.parse(repository.baseUrl).port, greaterThan(0));
      expect(repository.packages.keys.toSet(), {
        'wcf_fake_root',
        'wcf_fake_leaf',
      });
    });

    test(
      'GET /api/packages/<name> answers the shape pub resolves against',
      () async {
        final response = await get('/api/packages/wcf_fake_root');
        expect(response.statusCode, HttpStatus.ok);
        expect(
          response.headers.contentType?.mimeType,
          'application/vnd.pub.v2+json',
        );

        final body =
            jsonDecode(await response.transform(utf8.decoder).join())
                as Map<String, Object?>;
        expect(body['name'], 'wcf_fake_root');

        final versions = body['versions']! as List<Object?>;
        expect(versions, hasLength(1));
        expect(body['latest'], versions.single);

        final version = versions.single! as Map<String, Object?>;
        expect(version['version'], '0.0.1');
        expect(
          version['archive_url'],
          '${repository.baseUrl}/packages/wcf_fake_root/versions/0.0.1.tar.gz',
        );
        expect(
          version['archive_sha256'],
          repository.packages['wcf_fake_root']!.archiveSha256,
        );
        // The embedded pubspec is what pub resolves against — it never downloads
        // an archive to answer a version query — so the sibling must already be
        // rewritten to `hosted:` here.
        final pubspec = version['pubspec']! as Map<String, Object?>;
        expect(pubspec['name'], 'wcf_fake_root');
        expect(pubspec['dependencies'], {
          'wcf_fake_leaf': {'hosted': repository.baseUrl, 'version': '0.0.1'},
        });
        expect(pubspec.containsKey('resolution'), isFalse);
      },
    );

    test(
      'GET the archive returns a tarball whose pubspec is the staged one',
      () async {
        final response = await get(
          '/packages/wcf_fake_leaf/versions/0.0.1.tar.gz',
        );
        expect(response.statusCode, HttpStatus.ok);
        expect(
          response.headers.contentType?.mimeType,
          'application/octet-stream',
        );

        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
        }
        expect(bytes, isNotEmpty);

        final downloaded = File('${scratch.path}/downloaded.tar.gz')
          ..writeAsBytesSync(bytes);
        expect(
          sha256OfFile(downloaded.path),
          repository.packages['wcf_fake_leaf']!.archiveSha256,
        );

        final unpacked = Directory('${scratch.path}/unpacked')
          ..createSync(recursive: true);
        final untar = run('tar', [
          '-xzf',
          downloaded.path,
          '-C',
          unpacked.path,
        ]);
        expect(untar.ok, isTrue, reason: untar.stderr);

        final pubspec = File('${unpacked.path}/pubspec.yaml');
        expect(pubspec.existsSync(), isTrue);
        final text = pubspec.readAsStringSync();
        expect(text, isNot(contains('resolution: workspace')));
        expect(text, isNot(contains('publish_to')));
        expect(parseMiniYaml(text)['name'], 'wcf_fake_leaf');

        // The library source travels with it; pub's own bookkeeping does not.
        expect(File('${unpacked.path}/lib/leaf.dart').existsSync(), isTrue);
        expect(File('${unpacked.path}/pubspec.lock').existsSync(), isFalse);
        expect(Directory('${unpacked.path}/.dart_tool').existsSync(), isFalse);
      },
    );

    test('an unknown package and an unknown route are 404, not 500', () async {
      expect(
        (await get('/api/packages/not_a_package')).statusCode,
        HttpStatus.notFound,
      );
      expect(
        (await get('/packages/wcf_fake_leaf/versions/9.9.9.tar.gz')).statusCode,
        HttpStatus.notFound,
      );
      expect((await get('/anything/else')).statusCode, HttpStatus.notFound);
    });

    test('the request log records every path served', () async {
      await (await get('/api/packages/wcf_fake_leaf')).drain<void>();
      await (await get(
        '/packages/wcf_fake_leaf/versions/0.0.1.tar.gz',
      )).drain<void>();
      expect(repository.requestLog, contains('/api/packages/wcf_fake_leaf'));
      expect(
        repository.requestLog,
        contains('/packages/wcf_fake_leaf/versions/0.0.1.tar.gz'),
      );
    });
  });
}
