import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wcf_tool_manifest/embed.dart';

/// A minimal manifest carrying only what the generator reads.
const Map<String, Object?> _manifest = <String, Object?>{
  'upstream': <String, Object?>{
    'repo': 'trustwallet/wallet-core',
    'tag': '4.8.0',
    'commit': 'd692ac27749d0c615e17c751b70ab4f0aa75c59b',
  },
  'release_set': 'rs_4.8.0_001',
  'identity': <String, Object?>{
    'symbol': 'wcf_build_info',
    'artifact_set_id': 'as_4.8.0_001',
    'upstream_commit': 'd692ac27749d0c615e17c751b70ab4f0aa75c59b',
  },
};

String _render(Map<String, Object?> manifest) =>
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n';

Uint8List _bytes(Map<String, Object?> manifest) =>
    Uint8List.fromList(utf8.encode(_render(manifest)));

Directory _tempDir() {
  final dir = Directory.systemTemp.createTempSync('wcf-embed-');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

/// Writes [manifest] into a temp file and returns its path.
String _tempManifest(Map<String, Object?> manifest) {
  final file = File('${_tempDir().path}/compat_manifest.json')
    ..writeAsBytesSync(_bytes(manifest));
  return file.path;
}

void main() {
  group('manifestSha256Of', () {
    test('is the sha256 of the bytes it is given', () {
      // sha256("abc"), the published NIST vector: the digest is checked
      // against a value from outside this repository.
      expect(
        manifestSha256Of(utf8.encode('abc')),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('covers the file exactly as committed, trailing newline included', () {
      final withNewline = manifestSha256Of(utf8.encode('{}\n'));
      final without = manifestSha256Of(utf8.encode('{}'));
      expect(withNewline, isNot(without));
      expect(withNewline, hasLength(64));
    });

    test('is not the digest of a re-serialisation', () {
      // Two byte sequences that decode to the same JSON must hash
      // differently, which is the whole point of hashing the file.
      const compact = '{"a":1}';
      const spaced = '{ "a": 1 }';
      expect(jsonDecode(compact), jsonDecode(spaced));
      expect(
        manifestSha256Of(utf8.encode(compact)),
        isNot(manifestSha256Of(utf8.encode(spaced))),
      );
    });
  });

  group('EmbeddedManifest.fromBytes', () {
    test('reads the eight values the native package needs', () {
      final values = EmbeddedManifest.fromBytes(_bytes(_manifest));
      expect(values.upstreamRepo, 'trustwallet/wallet-core');
      expect(values.upstreamTag, '4.8.0');
      expect(values.upstreamCommit, 'd692ac27749d0c615e17c751b70ab4f0aa75c59b');
      expect(values.identitySymbol, 'wcf_build_info');
      expect(values.identityArtifactSetId, 'as_4.8.0_001');
      expect(
        values.identityUpstreamCommit,
        'd692ac27749d0c615e17c751b70ab4f0aa75c59b',
      );
      expect(values.releaseSetId, 'rs_4.8.0_001');
      expect(values.manifestSha256, manifestSha256Of(_bytes(_manifest)));
      expect(values.constants, hasLength(8));
    });

    test('hashes the same bytes it parsed', () {
      final bytes = _bytes(_manifest);
      expect(
        EmbeddedManifest.fromBytes(bytes).manifestSha256,
        manifestSha256Of(bytes),
      );
    });

    test('copies a TBD- placeholder through unchanged', () {
      // The generator never substitutes for a placeholder: the native package
      // is what decides that "unknown" never matches, and it can only do that
      // if it can see the placeholder.
      final manifest = <String, Object?>{
        ..._manifest,
        'release_set': 'TBD-T3.11',
        'identity': <String, Object?>{
          ..._manifest['identity']! as Map<String, Object?>,
          'artifact_set_id': 'TBD-T1.2',
        },
      };
      final values = EmbeddedManifest.fromBytes(_bytes(manifest));
      expect(values.releaseSetId, 'TBD-T3.11');
      expect(values.identityArtifactSetId, 'TBD-T1.2');
    });

    test('rejects a manifest that is not JSON', () {
      expect(
        () => EmbeddedManifest.fromBytes(
          Uint8List.fromList(utf8.encode('not json')),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a missing block, naming it', () {
      final manifest = Map<String, Object?>.from(_manifest)..remove('identity');
      expect(
        () => EmbeddedManifest.fromBytes(_bytes(manifest)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('`identity` must be an object'),
          ),
        ),
      );
    });

    test('rejects a missing field, naming its path', () {
      final manifest = <String, Object?>{
        ..._manifest,
        'identity': <String, Object?>{
          'symbol': 'wcf_build_info',
          'upstream_commit': 'd692ac27749d0c615e17c751b70ab4f0aa75c59b',
        },
      };
      expect(
        () => EmbeddedManifest.fromBytes(_bytes(manifest)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('`identity.artifact_set_id`'),
          ),
        ),
      );
    });

    test('rejects an empty field', () {
      final manifest = <String, Object?>{..._manifest, 'release_set': ''};
      expect(
        () => EmbeddedManifest.fromBytes(_bytes(manifest)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('`release_set`'),
          ),
        ),
      );
    });
  });

  group('renderManifestLibrary', () {
    final source = renderManifestLibrary(
      EmbeddedManifest.fromBytes(_bytes(_manifest)),
    );

    test('is deterministic', () {
      for (var i = 0; i < 3; i++) {
        expect(
          renderManifestLibrary(EmbeddedManifest.fromBytes(_bytes(_manifest))),
          source,
        );
      }
    });

    test('emits the constants in sorted name order', () {
      final order = RegExp(
        r'^const String (\w+) =',
        multiLine: true,
      ).allMatches(source).map((m) => m.group(1)!).toList();
      expect(order, hasLength(8));
      expect(order, orderedEquals(List<String>.from(order)..sort()));
      expect(order.first, 'identityArtifactSetId');
      expect(order.last, 'upstreamTag');
    });

    test('carries the generated header and the disclaimer', () {
      expect(source, startsWith('// GENERATED CODE - DO NOT MODIFY BY HAND'));
      expect(source, contains('melos run gen:manifest'));
      expect(
        source,
        contains(
          'Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core',
        ),
      );
      expect(source, contains('Not affiliated with or endorsed by Trust '));
    });

    test('states what manifestSha256 is', () {
      expect(source, contains('exactly as committed'));
      expect(source, contains('re-serialisation'));
    });

    test('says why the check reads constants and not the asset', () {
      expect(source, contains('rootBundle'));
      expect(source, contains('DECISION-12 §5'));
      expect(source, contains('pure-Dart CLI'));
    });

    test('every constant carries a doc comment', () {
      final lines = const LineSplitter().convert(source);
      var seen = 0;
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].startsWith('const String')) continue;
        seen++;
        expect(
          lines[i - 1],
          startsWith('///'),
          reason: '${lines[i]} has no doc comment',
        );
      }
      expect(seen, 8);
    });

    test('formatDartSource makes it format-clean, and is idempotent', () {
      // `generate` writes the formatted text, so this is what lands in the
      // repository and what `melos run format:check` sees.
      final formatted = formatDartSource(source);
      expect(formatDartSource(formatted), formatted);
      final file = File('${_tempDir().path}/manifest.dart')
        ..writeAsStringSync(formatted);
      final result = Process.runSync('dart', <String>[
        'format',
        '--output=none',
        '--set-exit-if-changed',
        file.path,
      ]);
      expect(
        result.exitCode,
        0,
        reason:
            'dart format would rewrite the generated source:\n'
            '${result.stdout}${result.stderr}',
      );
    });

    test('is valid Dart that analyzes clean', () {
      final dir = _tempDir();
      File('${dir.path}/manifest.dart').writeAsStringSync(source);
      File('${dir.path}/pubspec.yaml').writeAsStringSync(
        'name: wcf_embed_probe\n'
        'publish_to: none\n'
        'environment:\n  sdk: ^3.12.0\n',
      );
      final result = Process.runSync('dart', <String>[
        'analyze',
        '--fatal-infos',
        dir.path,
      ]);
      expect(
        result.exitCode,
        0,
        reason:
            'the generated source does not analyze:\n'
            '${result.stdout}${result.stderr}',
      );
    });

    test('escapes a value that would break the literal', () {
      final manifest = <String, Object?>{
        ..._manifest,
        'release_set': r"rs_'4.8.0'_\001_$x",
      };
      final rendered = renderManifestLibrary(
        EmbeddedManifest.fromBytes(_bytes(manifest)),
      );
      expect(
        rendered,
        contains(r"const String releaseSetId = 'rs_\'4.8.0\'_\\001_\$x';"),
      );
    });

    test('refuses a value containing a control character', () {
      final manifest = <String, Object?>{
        ..._manifest,
        'release_set': 'rs_4.8.0_001\nconst String evil = 1;',
      };
      expect(
        () =>
            renderManifestLibrary(EmbeddedManifest.fromBytes(_bytes(manifest))),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('control character'),
          ),
        ),
      );
    });
  });

  group('generate', () {
    test('writes both outputs and reports them as changed', () {
      final manifestPath = _tempManifest(_manifest);
      final packageDir = _tempDir().path;

      final first = generate(
        manifestPath: manifestPath,
        nativePackageDir: packageDir,
      );
      expect(first.dartChanged, isTrue);
      expect(first.assetChanged, isTrue);
      expect(first.dartPath, endsWith(generatedDartRelativePath));
      expect(first.assetPath, endsWith(assetRelativePath));
      expect(File(first.dartPath).readAsStringSync(), first.dartSource);
    });

    test('the asset copy is byte-identical to the manifest', () {
      final manifestPath = _tempManifest(_manifest);
      final result = generate(
        manifestPath: manifestPath,
        nativePackageDir: _tempDir().path,
      );
      expect(
        File(result.assetPath).readAsBytesSync(),
        File(manifestPath).readAsBytesSync(),
      );
      expect(
        manifestSha256Of(File(result.assetPath).readAsBytesSync()),
        result.values.manifestSha256,
      );
    });

    test('a second run over an unchanged manifest writes nothing', () {
      // What makes `melos run gen:check` a real gate: regeneration is a no-op
      // unless the manifest moved.
      final manifestPath = _tempManifest(_manifest);
      final packageDir = _tempDir().path;
      generate(manifestPath: manifestPath, nativePackageDir: packageDir);
      final second = generate(
        manifestPath: manifestPath,
        nativePackageDir: packageDir,
      );
      expect(second.dartChanged, isFalse);
      expect(second.assetChanged, isFalse);
    });

    test('a changed manifest changes both outputs', () {
      final packageDir = _tempDir().path;
      generate(
        manifestPath: _tempManifest(_manifest),
        nativePackageDir: packageDir,
      );
      final changed = generate(
        manifestPath: _tempManifest(<String, Object?>{
          ..._manifest,
          'release_set': 'rs_4.8.0_002',
        }),
        nativePackageDir: packageDir,
      );
      expect(changed.dartChanged, isTrue);
      expect(changed.assetChanged, isTrue);
      expect(changed.dartSource, contains('rs_4.8.0_002'));
    });

    test('a missing manifest is a clear failure', () {
      expect(
        () => generate(
          manifestPath: '${_tempDir().path}/absent.json',
          nativePackageDir: _tempDir().path,
        ),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('against the repository\'s own manifest', () {
    final root = _repoRoot();

    test('the committed constants match a fresh render', () {
      final values = EmbeddedManifest.fromFile('$root/compat_manifest.json');
      final generated = File(
        '$root/packages/wallet_core_flutter_native/'
        '$generatedDartRelativePath',
      ).readAsStringSync();
      expect(generated, formatDartSource(renderManifestLibrary(values)));
    }, skip: root == null ? 'not run from a repository checkout' : null);

    test('the shipped asset is a byte copy of the root manifest', () {
      expect(
        File(
          '$root/packages/wallet_core_flutter_native/$assetRelativePath',
        ).readAsBytesSync(),
        File('$root/compat_manifest.json').readAsBytesSync(),
      );
    }, skip: root == null ? 'not run from a repository checkout' : null);
  });
}

/// The repository root, or null when the tool is run from outside a checkout.
String? _repoRoot() {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 8; i++) {
    if (File('${dir.path}/compat_manifest.json').existsSync() &&
        Directory('${dir.path}/packages').existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}
