// The DECISION-14 §5.1 per-artifact record reader.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.
//
// The tests build a synthetic output set — `<set>/artifacts/<logical name>` and
// `<set>/records/<flat name>.json` — under TMPDIR, because the shape of the set
// is what `forArtifact` walks, and a temp copy lets a record be made to
// disagree with its bytes on purpose.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wcf_tool_packaging_eval/artifact_record.dart';
import 'package:wcf_tool_packaging_eval/host.dart';
import 'package:wcf_tool_packaging_eval/measurements.dart';
import 'package:wcf_tool_packaging_eval/results.dart';

void main() {
  late Directory scratch;

  setUp(() => scratch = scratchDirectory('wcf-record-test-'));
  tearDown(() {
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  /// Writes `<scratch>/artifacts/<logicalName>` with [bytes] and a record
  /// beside it carrying [fields], and returns the artifact path.
  String stageSet({
    required String logicalName,
    required List<int> bytes,
    required Map<String, Object?> fields,
  }) {
    final artifact = File('${scratch.path}/artifacts/$logicalName');
    artifact.parent.createSync(recursive: true);
    artifact.writeAsBytesSync(bytes);
    final flat = logicalName.replaceAll('/', '-');
    final record = File('${scratch.path}/records/$flat.json')
      ..parent.createSync(recursive: true);
    record.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({logicalName: fields}),
    );
    return artifact.path;
  }

  group('ArtifactRecord.forArtifact', () {
    test('finds the record beside a staged artifact and reads its fields', () {
      final bytes = List<int>.filled(64, 7);
      final artifact = stageSet(
        logicalName: 'ios/arm64/libTrustWalletCore.dylib',
        bytes: bytes,
        fields: {
          'sha256': 'a' * 64,
          'size': bytes.length,
          'target_os': 'ios',
          'abi': 'arm64',
          'min_os': '13.0',
          'provenance': 'relinked_from_upstream_release_asset',
          'asset_name': 'as_4.8.0_000__${'a' * 64}__ios-arm64-lib.dylib',
        },
      );

      final record = ArtifactRecord.forArtifact(artifact);
      expect(record, isNotNull);
      expect(record!.logicalName, 'ios/arm64/libTrustWalletCore.dylib');
      expect(record.size, bytes.length);
      expect(record.sha256, 'a' * 64);
      expect(record.targetOs, 'ios');
      expect(record.abi, 'arm64');
      expect(record.minOs, '13.0');
      expect(record.provenance, 'relinked_from_upstream_release_asset');
      expect(record.assetName, startsWith('as_4.8.0_000__'));
      expect(
        record.recordPath,
        endsWith('records/ios-arm64-libTrustWalletCore.dylib.json'),
      );
    });

    test('returns null for a file that is not inside an output set', () {
      final loose = File('${scratch.path}/loose.dylib')..writeAsStringSync('x');
      expect(ArtifactRecord.forArtifact(loose.path), isNull);
    });

    test('returns null when the set has no record for the artifact', () {
      final artifact = File('${scratch.path}/artifacts/android/x86_64/lib.so')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('x');
      Directory('${scratch.path}/records').createSync(recursive: true);
      expect(ArtifactRecord.forArtifact(artifact.path), isNull);
    });

    test('reads the real relinked iOS device record when it is present', () {
      final artifact =
          '${repoRoot().path}/third_party/wcf-native-all/artifacts/'
          'ios/arm64/libTrustWalletCore.dylib';
      if (!File(artifact).existsSync()) {
        markTestSkipped('no third_party/wcf-native-all artifact set here');
        return;
      }
      final record = ArtifactRecord.forArtifact(artifact)!;
      expect(record.logicalName, 'ios/arm64/libTrustWalletCore.dylib');
      expect(record.size, File(artifact).lengthSync());
      expect(record.provenance, 'relinked_from_upstream_release_asset');
    });
  });

  group('measureSize cross-checks the record', () {
    test('a record that agrees with the bytes passes', () {
      final bytes = List<int>.filled(1024, 3);
      final artifact = stageSet(
        logicalName: 'macos/arm64/libTrustWalletCore.dylib',
        bytes: bytes,
        fields: {'size': bytes.length, 'provenance': 'test_fixture'},
      );
      final rows = measureSize(artifact: artifact, target: 'macos/arm64');
      expect(rows, hasLength(1));
      expect(rows.single.status, CheckStatus.pass);
      expect(rows.single.values['size_bytes'], bytes.length);
      expect(rows.single.values['record_size'], bytes.length);
      expect(rows.single.notes, isEmpty);
    });

    test('a record whose size disagrees is flagged as a failure', () {
      final bytes = List<int>.filled(1024, 3);
      final artifact = stageSet(
        logicalName: 'macos/arm64/libTrustWalletCore.dylib',
        bytes: bytes,
        fields: {'size': bytes.length + 1, 'provenance': 'test_fixture'},
      );
      final rows = measureSize(artifact: artifact, target: 'macos/arm64');
      expect(rows.single.status, CheckStatus.fail);
      expect(rows.single.notes, contains('record says 1025 bytes'));
    });

    test('a record whose sha256 disagrees is flagged as a failure', () {
      final bytes = List<int>.filled(1024, 3);
      final artifact = stageSet(
        logicalName: 'macos/arm64/libTrustWalletCore.dylib',
        bytes: bytes,
        fields: {
          'size': bytes.length,
          'sha256': 'f' * 64,
          'provenance': 'test_fixture',
        },
      );
      final rows = measureSize(artifact: artifact, target: 'macos/arm64');
      final digest = sha256OfFile(artifact);
      if (digest == null) {
        markTestSkipped('neither shasum nor sha256sum is on PATH');
        return;
      }
      expect(rows.single.status, CheckStatus.fail);
      expect(rows.single.notes, contains('does not match the file'));
      expect(rows.single.values['sha256'], digest);
    });

    test('a missing artifact is unmeasured, never pass', () {
      final rows = measureSize(
        artifact: '${scratch.path}/artifacts/nowhere/lib.so',
        target: 'android/x86_64',
      );
      expect(rows.single.status, CheckStatus.unmeasured);
      expect(rows.single.command, contains('wc -c'));
    });
  });
}
