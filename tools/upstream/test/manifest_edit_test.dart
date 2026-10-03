import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wcf_tool_upstream/manifest_edit.dart';

const _pinned = 'd692ac27749d0c615e17c751b70ab4f0aa75c59b';

void main() {
  group('resolveCommit', () {
    test('adopts --commit while the manifest holds a placeholder', () {
      expect(
        resolveCommit(recorded: 'TBD-T1.1', provided: _pinned),
        equals(_pinned),
      );
    });

    test('requires --commit while the manifest holds a placeholder', () {
      expect(
        () => resolveCommit(recorded: 'TBD-T1.1'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('verifies --commit against an already-resolved pin', () {
      expect(
        resolveCommit(recorded: _pinned, provided: _pinned),
        equals(_pinned),
      );
    });

    test('keeps the pin when --commit is omitted', () {
      expect(resolveCommit(recorded: _pinned), equals(_pinned));
    });

    test('refuses to repin on a mismatch', () {
      expect(
        () => resolveCommit(
          recorded: _pinned,
          provided: '0000000000000000000000000000000000000000',
        ),
        throwsA(isA<CommitPinMismatch>()),
      );
    });

    test('rejects a malformed --commit', () {
      for (final bad in ['deadbeef', '${_pinned}0', _pinned.toUpperCase()]) {
        expect(
          () => resolveCommit(recorded: 'TBD-T1.1', provided: bad),
          throwsA(isA<ArgumentError>()),
          reason: bad,
        );
      }
    });
  });

  group('encodeManifest', () {
    test('reproduces the checked-in formatting byte for byte', () {
      final file = File('../../compat_manifest.json');
      final original = file.readAsStringSync();
      final decoded = jsonDecode(original) as Map<String, Object?>;
      expect(encodeManifest(decoded), equals(original));
    });

    test('preserves key order', () {
      final encoded = encodeManifest({'z': 1, 'a': 2});
      expect(encoded.indexOf('"z"'), lessThan(encoded.indexOf('"a"')));
    });
  });

  group('writeManifestIfChanged', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('wcf-manifest-'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('reports a change on first write and none on the second', () {
      final file = File('${dir.path}/compat_manifest.json');
      final manifest = <String, Object?>{
        'upstream': {'tag': '4.8.0'},
      };
      expect(writeManifestIfChanged(file, manifest), isTrue);
      final firstBytes = file.readAsBytesSync();
      expect(writeManifestIfChanged(file, manifest), isFalse);
      expect(file.readAsBytesSync(), equals(firstBytes));
    });
  });

  group('readManifest', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('wcf-manifest-'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('rejects a non-object root', () {
      final file = File('${dir.path}/m.json')..writeAsStringSync('[1,2]');
      expect(() => readManifest(file), throwsA(isA<FormatException>()));
    });
  });
}
