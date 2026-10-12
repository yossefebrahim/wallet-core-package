import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart';
import 'package:wcf_tool_probes/compiler_probe.dart';

Uint8List _bytes(List<int> b) => Uint8List.fromList(b);

ChildOutcome _ok(Map<String, List<int>> calls) => ChildOutcome.ok({
  for (final e in calls.entries) e.key: CallObservation.bytes(_bytes(e.value)),
});

// PreSigningOutput { error = Error_not_supported (24) }: field 3, varint 24.
const _notSupportedBytes = [0x18, 0x18];
// PreSigningOutput { error = Error_input_parse (22) }: field 3, varint 22.
const _inputParseBytes = [0x18, 0x16];

void main() {
  group('topLevelVarints', () {
    test('reads varint fields and skips length-delimited ones', () {
      // field 3 = 24; field 4 = "ab"; field 5 = 300
      final fields = topLevelVarints(
        _bytes([0x18, 0x18, 0x22, 0x02, 0x61, 0x62, 0x28, 0xac, 0x02]),
      );
      expect(fields, [(3, 24), (5, 300)]);
    });

    test('returns null for malformed input', () {
      expect(topLevelVarints(garbageInput), isNull);
      expect(topLevelVarints(_bytes([0x22, 0x05, 0x61])), isNull);
    });
  });

  group('classifyCompilerRuntime', () {
    test('reached: a call returned a non-empty output', () {
      final r = classifyCompilerRuntime(
        _ok({'preimage_empty': _inputParseBytes, 'preimage_garbage': const []}),
      );
      expect((r.label, r.supported), ('reached', true));
    });

    test('empty: every call returned zero bytes', () {
      final r = classifyCompilerRuntime(_ok({'a': const [], 'b': const []}));
      expect((r.label, r.supported), ('empty', false));
    });

    test('not-supported: only Error_not_supported outputs', () {
      final r = classifyCompilerRuntime(
        _ok({
          'a': _notSupportedBytes,
          'b': const [0x10, 0x18],
        }),
      );
      expect((r.label, r.supported), ('not-supported', false));
    });

    test('a different non-empty output alongside not-supported is reached', () {
      final r = classifyCompilerRuntime(
        _ok({'a': _notSupportedBytes, 'b': _inputParseBytes}),
      );
      expect(r.label, 'reached');
    });

    test('crash carries the detail and no runtime verdict', () {
      final r = classifyCompilerRuntime(
        ChildOutcome.crash('signal 6 in compile_empty'),
      );
      expect(
        (r.label, r.supported, r.crash),
        ('crash', null, 'signal 6 in compile_empty'),
      );
    });
  });

  group('static rules', () {
    test('every blockchain is in at most one table', () {
      final all = [
        cppCompilerBlockchains,
        rustCompilerBlockchains,
        cppDefaultCompilerBlockchains,
        explicitStubCompilerBlockchains,
      ].expand((t) => t).toList();
      expect(all.toSet().length, all.length);
    });

    test('verdicts follow the tables', () {
      expect(compilerStatic('Bitcoin'), isTrue);
      expect(compilerStatic('Solana'), isTrue);
      expect(compilerStatic('Nimiq'), isFalse);
      expect(compilerStatic('InternetComputer'), isFalse);
      expect(compilerStatic('NoSuchChain'), isNull);
    });

    test('every registry coin is classified', () {
      final blockchains = registryBlockchains();
      expect(blockchains.length, 167);
      expect(
        blockchains.entries.where((e) => compilerStatic(e.value) == null),
        isEmpty,
      );
    });

    test('registry coin ids match the FFI TWCoinType ids', () {
      expect(
        registryBlockchains().keys.toSet(),
        TWCoinType.values.map((c) => c.value).toSet(),
      );
    });
  });

  group('compilerRow', () {
    test('static and runtime agree', () {
      final row = compilerRow(
        coinId: 0,
        coinName: 'TWCoinTypeBitcoin',
        blockchain: 'Bitcoin',
        outcome: _ok({'a': _inputParseBytes}),
      );
      expect(row.result.agreement, Agreement.agree);
      expect(row.result.runtimeCell, 'reached');
    });

    test('disagreement is a conflict carrying both values', () {
      final row = compilerRow(
        coinId: 1,
        coinName: 'TWCoinTypeX',
        blockchain: 'Nimiq',
        outcome: _ok({'a': _inputParseBytes}),
      );
      expect(row.result.agreement, Agreement.conflict);
      expect(
        row.result.runtimeCell,
        'conflict (static=unsupported, runtime=reached)',
      );
    });

    test('crash is not a conflict', () {
      final row = compilerRow(
        coinId: 194,
        coinName: 'TWCoinTypeEOS',
        blockchain: 'EOS',
        outcome: ChildOutcome.crash('signal 6 in preimage_empty'),
      );
      expect(row.result.agreement, Agreement.crash);
      expect(row.result.runtimeCell, 'crash (signal 6 in preimage_empty)');
    });

    test('unknown blockchain is unclassified', () {
      final row = compilerRow(
        coinId: 1,
        coinName: 'TWCoinTypeX',
        blockchain: 'unknown',
        outcome: _ok({'a': const []}),
      );
      expect(row.result.agreement, Agreement.unclassified);
      expect(row.result.staticCell, 'unclassified');
    });
  });

  group('renderQuestionTotals', () {
    test('counts static, runtime, agreement, conflict and crash', () {
      QuestionResult result(String chain, ChildOutcome outcome) => compilerRow(
        coinId: 0,
        coinName: 'x',
        blockchain: chain,
        outcome: outcome,
      ).result;
      final text = renderQuestionTotals('Transaction compiler', [
        result('Bitcoin', _ok({'a': _inputParseBytes})),
        result('Nimiq', _ok({'a': const []})),
        result('Nimiq', _ok({'a': _inputParseBytes})),
        result('EOS', ChildOutcome.crash('signal 6')),
      ]);
      expect(text, contains('- Coins: 4'));
      expect(
        text,
        contains('- Static: 2 supported, 2 unsupported, 0 unclassified'),
      );
      expect(text, contains('- Runtime: 1 crash, 1 empty, 2 reached'));
      expect(text, contains('- Static and runtime agree: 2'));
      expect(text, contains('- Conflict: 1'));
      expect(text, contains('- Crash (no runtime evidence): 1'));
    });
  });

  group('child process plumbing', () {
    test('parseChildLine reads one JSON line', () {
      final line = jsonEncode({
        'coin': 1,
        'calls': {
          'a': CallObservation.bytes(_bytes([1, 2])).toJson(),
          'b': CallObservation.nullPointer().toJson(),
          'c': CallObservation.boolean(false).toJson(),
        },
      });
      final outcome = parseChildLine('$line\n');
      expect(outcome.isCrash, isFalse);
      expect(outcome.calls!['a']!.bytes, [1, 2]);
      expect(outcome.calls!['b']!.isNull, isTrue);
      expect(outcome.calls!['c']!.boolValue, isFalse);
    });

    test('parseChildLine turns anything else into a crash', () {
      expect(parseChildLine('').isCrash, isTrue);
      expect(parseChildLine('not json\n').isCrash, isTrue);
      expect(parseChildLine('{}\n{}\n').isCrash, isTrue);
    });

    test('runChild records signal death as a crash, naming the call', () async {
      // The "script" is a shell script that announces a call and then kills
      // itself with SIGABRT; the parent must record it instead of throwing.
      final dir = Directory.systemTemp.createTempSync('wcf_probe_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final script = File('${dir.path}/crash.sh')
        ..writeAsStringSync('echo call:compile_empty >&2\nkill -ABRT \$\$\n');
      final outcome = await runChild(
        executable: '/bin/sh',
        script: script.path,
        libPath: 'unused',
        coinId: 1,
        part: 'compiler',
      );
      expect(outcome.isCrash, isTrue);
      expect(outcome.crashDetail, 'signal 6 in compile_empty');
    }, testOn: 'mac-os || linux');

    test('runChild records a non-zero exit as a crash', () async {
      final dir = Directory.systemTemp.createTempSync('wcf_probe_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final script = File('${dir.path}/exit.sh')..writeAsStringSync('exit 3\n');
      final outcome = await runChild(
        executable: '/bin/sh',
        script: script.path,
        libPath: 'unused',
        coinId: 1,
        part: 'compiler',
      );
      expect(outcome.crashDetail, 'exit 3');
    }, testOn: 'mac-os || linux');

    test('mapConcurrent keeps input order', () async {
      final out = await mapConcurrent<int, int>(
        [for (var i = 0; i < 20; i++) i],
        4,
        (i) async {
          await Future<void>.delayed(Duration(milliseconds: (20 - i) % 5));
          return i * 2;
        },
      );
      expect(out, [for (var i = 0; i < 20; i++) i * 2]);
    });
  });

  group('observeCompiler', () {
    test('runs four calls through the interface and reports them', () {
      final native = _FakeNative();
      final seen = <String>[];
      final calls = observeCompiler(native, 60, onCall: seen.add);
      expect(seen, [
        'preimage_empty',
        'preimage_garbage',
        'compile_empty',
        'compile_garbage',
      ]);
      expect(calls.keys, seen);
      expect(native.garbageCalls, 2);
    });
  });

  group('native', () {
    test(
      'probes every coin through child processes and returns 167 rows',
      () async {
        final libPath =
            Platform.environment['WCF_NATIVE_LIB'] ??
            '../../third_party/wcf-native/macos/arm64_x86_64/libTrustWalletCore.dylib';
        if (!File(libPath).existsSync()) {
          if (Platform.environment['WCF_NATIVE_REQUIRED'] == '1') {
            fail('Native library required but not found at $libPath');
          }
          markTestSkipped('Native library not found at $libPath');
          return;
        }
        final rows = await probeCompilerViaChildren(
          executable: Platform.resolvedExecutable,
          script: 'bin/coverage_probe.dart',
          libPath: libPath,
        );
        expect(rows.length, 167);
        expect(rows.map((r) => r.coinId).toSet().length, 167);
        expect(
          rows.where((r) => r.result.agreement == Agreement.unclassified),
          isEmpty,
        );
        final byChain = {for (final r in rows) r.blockchain: r.result};
        expect(byChain['Ethereum']!.runtimeClass, 'reached');
        expect(byChain['InternetComputer']!.runtimeClass, 'not-supported');
      },
      tags: ['native'],
      timeout: const Timeout(Duration(minutes: 10)),
    );
  });
}

class _FakeNative implements CompilerNative {
  int garbageCalls = 0;

  @override
  Uint8List preImageHashes(int coinId, Uint8List input) {
    if (input.isNotEmpty) garbageCalls++;
    return Uint8List(0);
  }

  @override
  Uint8List compile(
    int coinId,
    Uint8List input,
    List<Uint8List> signatures,
    List<Uint8List> publicKeys,
  ) {
    if (input.isNotEmpty) garbageCalls++;
    return Uint8List(0);
  }
}
