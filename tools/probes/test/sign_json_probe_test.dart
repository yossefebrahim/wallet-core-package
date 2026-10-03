import 'dart:io';
import 'dart:ffi';
import 'package:test/test.dart';
import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart';
import 'package:wallet_core_flutter_bindings/src/generated/registry/coin_type.dart';
import 'package:wcf_tool_probes/sign_json_probe.dart';

void main() {
  group('renderMarkdown', () {
    test('renders deterministic markdown correctly', () {
      final rows = [
        ProbeRow(coinName: 'TWCoinTypeBitcoin', coinId: 0, supportsJson: false),
        ProbeRow(
          coinName: 'TWCoinTypeEthereum',
          coinId: 60,
          supportsJson: true,
        ),
        ProbeRow(
          coinName: 'TWCoinTypeMissing',
          coinId: 999,
          error: 'StateError',
        ),
      ];

      final md = renderMarkdown(
        rows,
        upstreamTag: '1.0.0',
        upstreamCommit: 'abcdef',
        libraryCommit: 'abcdef',
        artifactSetId: 'as_1.0.0',
        librarySha256: 'deadbeef',
      );

      expect(md, contains('# `TWAnySignerSupportsJSON` coverage probe'));
      expect(
        md,
        contains(
          'Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.',
        ),
      );
      expect(md, contains('- Supported: 1'));
      expect(md, contains('- Not supported: 1'));
      expect(md, contains('- Error: 1'));
      expect(md, contains('- Total: 3'));

      final btcIdx = md.indexOf('| 0 | TWCoinTypeBitcoin | false |');
      final ethIdx = md.indexOf('| 60 | TWCoinTypeEthereum | true |');
      final errIdx = md.indexOf(
        '| 999 | TWCoinTypeMissing | error: StateError |',
      );
      expect(btcIdx, lessThan(ethIdx));
      expect(ethIdx, lessThan(errIdx));
    });
  });

  group('probe', () {
    test('runs against native library and returns 167 rows', () {
      final libPath =
          Platform.environment['WCF_NATIVE_LIB'] ??
          '../../third_party/wcf-native/macos/arm64_x86_64/libTrustWalletCore.dylib';
      final file = File(libPath);
      if (!file.existsSync()) {
        if (Platform.environment['WCF_NATIVE_REQUIRED'] == '1') {
          fail('Native library required but not found at $libPath');
        } else {
          markTestSkipped('Native library not found at $libPath');
          return;
        }
      }

      final dylib = DynamicLibrary.open(file.absolute.path);
      final bindings = WalletCoreBindings(dylib);

      final rows = probe(bindings);
      expect(rows.length, 167);
      expect(rows.where((r) => r.error != null), isEmpty);
    }, tags: ['native']);

    test('renders golden deterministic output', () {
      final libPath =
          Platform.environment['WCF_NATIVE_LIB'] ??
          '../../third_party/wcf-native/macos/arm64_x86_64/libTrustWalletCore.dylib';
      final file = File(libPath);
      if (!file.existsSync()) {
        if (Platform.environment['WCF_NATIVE_REQUIRED'] == '1') {
          fail('Native library required but not found at $libPath');
        } else {
          markTestSkipped('Native library not found at $libPath');
          return;
        }
      }

      final tempOut = '${Directory.systemTemp.path}/test_evidence.md';
      final result = Process.runSync('dart', [
        'run',
        'bin/sign_json_probe.dart',
        '--lib',
        libPath,
        '--out',
        tempOut,
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());

      final generated = File(tempOut).readAsBytesSync();
      final golden = File(
        '../../docs/decisions/evidence/sign_json_coverage.md',
      ).readAsBytesSync();
      expect(generated, equals(golden));
    }, tags: ['native']);
  });

  group('drift', () {
    test('FFI coin ids match registry coin ids', () {
      final ffiIds = TWCoinType.values.map((c) => c.value).toSet();
      final registryIds = CoinType.values.map((c) => c.coinId).toSet();

      expect(ffiIds, equals(registryIds));
    });
  });
}
