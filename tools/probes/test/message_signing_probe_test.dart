import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wcf_tool_probes/compiler_probe.dart';
import 'package:wcf_tool_probes/message_signing_probe.dart';

ChildOutcome _signed({bool sign = true, bool preimage = true}) =>
    ChildOutcome.ok({
      'sign_empty': sign
          ? CallObservation.bytes(Uint8List.fromList([0x10, 0x01]))
          : CallObservation.nullPointer(),
      'preimage_empty': preimage
          ? CallObservation.bytes(Uint8List.fromList([0x18, 0x16]))
          : CallObservation.nullPointer(),
      'verify_empty': CallObservation.boolean(false),
    });

CompilerRow _compiler(
  int id,
  String name,
  String chain,
  ChildOutcome outcome,
) => compilerRow(
  coinId: id,
  coinName: name,
  blockchain: chain,
  outcome: outcome,
);

ChildOutcome _compilerReached() => ChildOutcome.ok({
  'preimage_empty': CallObservation.bytes(Uint8List.fromList([0x18, 0x16])),
});

String _render(List<CompilerRow> compiler, List<MessageRow> messages) =>
    renderCoverageMarkdown(
      compiler,
      messages,
      upstreamTag: '1.0.0',
      upstreamCommit: 'abcdef',
      libraryCommit: 'abcdef',
      artifactSetId: 'as_1.0.0',
      librarySha256: 'deadbeef',
    );

void main() {
  group('classifyMessageRuntime', () {
    test('supported when sign or preimage returned data', () {
      expect(classifyMessageRuntime(_signed()).label, 'supported');
      expect(classifyMessageRuntime(_signed(sign: false)).supported, isTrue);
      expect(
        classifyMessageRuntime(_signed(preimage: false)).supported,
        isTrue,
      );
    });

    test('unsupported when both returned null; verify never decides', () {
      final r = classifyMessageRuntime(_signed(sign: false, preimage: false));
      expect((r.label, r.supported), ('unsupported', false));
    });

    test('crash has no runtime verdict', () {
      final r = classifyMessageRuntime(
        ChildOutcome.crash('signal 11 in sign_empty'),
      );
      expect(
        (r.label, r.supported, r.crash),
        ('crash', null, 'signal 11 in sign_empty'),
      );
    });
  });

  group('static rules', () {
    test('generic signer is supported only for the four Rust entries', () {
      for (final chain in ['Ethereum', 'Ronin', 'Solana', 'Sui']) {
        expect(genericMessageStatic(chain), isTrue, reason: chain);
      }
      for (final chain in ['Aptos', 'Bitcoin', 'Cosmos', 'Tron', 'unknown']) {
        expect(genericMessageStatic(chain), isFalse, reason: chain);
      }
    });

    test('coin-specific signer maps by blockchain family name only', () {
      expect(coinSpecificSigner('Ethereum'), 'TWEthereumMessageSigner');
      expect(coinSpecificSigner('Bitcoin'), 'TWBitcoinMessageSigner');
      expect(coinSpecificSigner('Tezos'), 'TWTezosMessageSigner');
      expect(coinSpecificSigner('Tron'), 'TWTronMessageSigner');
      expect(coinSpecificSigner('TheOpenNetwork'), 'TWTONMessageSigner');
      expect(coinSpecificSigner('Ronin'), isNull);
      expect(coinSpecificSigner('BitcoinCash'), isNull);
    });
  });

  group('messageRow', () {
    test('agreement, conflict and crash', () {
      final agree = messageRow(
        coinId: 60,
        coinName: 'TWCoinTypeEthereum',
        blockchain: 'Ethereum',
        outcome: _signed(),
      );
      expect(agree.result.agreement, Agreement.agree);
      expect(agree.specificSigner, 'TWEthereumMessageSigner');

      final conflict = messageRow(
        coinId: 501,
        coinName: 'TWCoinTypeSolana',
        blockchain: 'Solana',
        outcome: _signed(sign: false, preimage: false),
      );
      expect(conflict.result.agreement, Agreement.conflict);
      expect(
        conflict.result.runtimeCell,
        'conflict (static=supported, runtime=unsupported)',
      );

      final crash = messageRow(
        coinId: 1,
        coinName: 'TWCoinTypeX',
        blockchain: 'Cosmos',
        outcome: ChildOutcome.crash('signal 6 in sign_empty'),
      );
      expect(crash.result.agreement, Agreement.crash);
      expect(crash.result.runtimeCell, 'crash (signal 6 in sign_empty)');
    });
  });

  group('observeMessageSigner', () {
    test('runs sign, preimage and verify through the interface', () {
      final seen = <String>[];
      final calls = observeMessageSigner(_FakeNative(), 60, onCall: seen.add);
      expect(seen, ['sign_empty', 'preimage_empty', 'verify_empty']);
      expect(calls['sign_empty']!.isNull, isTrue);
      expect(calls['preimage_empty']!.bytes, [1]);
      expect(calls['verify_empty']!.boolValue, isFalse);
    });
  });

  group('renderCoverageMarkdown', () {
    final compiler = [
      _compiler(501, 'TWCoinTypeSolana', 'Solana', _compilerReached()),
      _compiler(0, 'TWCoinTypeBitcoin', 'Bitcoin', _compilerReached()),
      _compiler(
        60,
        'TWCoinTypeEthereum',
        'Ethereum',
        ChildOutcome.crash('signal 6 in compile_empty'),
      ),
      _compiler(
        223,
        'TWCoinTypeInternetComputer',
        'InternetComputer',
        _compilerReached(),
      ),
    ];
    final messages = [
      messageRow(
        coinId: 501,
        coinName: 'TWCoinTypeSolana',
        blockchain: 'Solana',
        outcome: _signed(),
      ),
      messageRow(
        coinId: 0,
        coinName: 'TWCoinTypeBitcoin',
        blockchain: 'Bitcoin',
        outcome: _signed(sign: false, preimage: false),
      ),
      messageRow(
        coinId: 60,
        coinName: 'TWCoinTypeEthereum',
        blockchain: 'Ethereum',
        outcome: _signed(),
      ),
      messageRow(
        coinId: 223,
        coinName: 'TWCoinTypeInternetComputer',
        blockchain: 'InternetComputer',
        outcome: _signed(sign: false, preimage: false),
      ),
    ];

    test('sorts rows by coin id and renders conflict and crash rows', () {
      final md = _render(compiler, messages);
      final order = [
        '| 0 | TWCoinTypeBitcoin |',
        '| 60 | TWCoinTypeEthereum |',
        '| 223 | TWCoinTypeInternetComputer |',
        '| 501 | TWCoinTypeSolana |',
      ].map(md.indexOf).toList();
      expect(order.every((i) => i >= 0), isTrue);
      expect(order, [...order]..sort());

      expect(
        md,
        contains(
          '| 0 | TWCoinTypeBitcoin | supported | reached | unsupported | unsupported | TWBitcoinMessageSigner |',
        ),
      );
      expect(
        md,
        contains(
          '| 60 | TWCoinTypeEthereum | supported | crash (signal 6 in compile_empty) | supported | supported | TWEthereumMessageSigner |',
        ),
      );
      expect(
        md,
        contains(
          '| 223 | TWCoinTypeInternetComputer | unsupported | conflict (static=unsupported, runtime=reached) | unsupported | unsupported | — |',
        ),
      );
    });

    test('totals per question', () {
      final md = _render(compiler, messages);
      expect(md, contains('### Transaction compiler'));
      expect(md, contains('### Generic message signer (`TWMessageSigner*`)'));
      expect(md, contains('- Coins with a coin-specific message signer: 2'));
      expect(md, contains('- Conflict: 1'));
      expect(md, contains('- Crash (no runtime evidence): 1'));
    });

    test(
      'carries the disclaimer, command and method; no timestamps or paths',
      () {
        final md = _render(compiler, messages);
        expect(
          md,
          contains(
            'Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.',
          ),
        );
        expect(md, contains('**Command:** `melos run probe:coverage`'));
        expect(md, contains('## Method'));
        expect(md, contains('src/CoinEntry.h:68,70'));
        expect(md, isNot(contains(RegExp(r'/Users/|/tmp/|/private/'))));
        expect(md, isNot(contains(RegExp(r'\d{4}-\d{2}-\d{2}'))));
        for (final banned in [
          'zeroization',
          'secret-free',
          'audited',
          'reproducible',
        ]) {
          expect(md.toLowerCase(), isNot(contains(banned)), reason: banned);
        }
      },
    );

    test('is deterministic regardless of row order', () {
      final a = _render(compiler, messages);
      final b = _render(compiler.reversed.toList(), messages.reversed.toList());
      expect(a, b);
    });
  });

  group('renderCoverageJson', () {
    final compiler = [
      _compiler(60, 'TWCoinTypeEthereum', 'Ethereum', _compilerReached()),
      _compiler(
        194,
        'TWCoinTypeEOS',
        'EOS',
        ChildOutcome.crash('signal 6 in preimage_empty'),
      ),
      _compiler(0, 'TWCoinTypeBitcoin', 'Bitcoin', _compilerReached()),
    ];
    final messages = [
      for (final c in compiler)
        messageRow(
          coinId: c.coinId,
          coinName: c.coinName,
          blockchain: c.blockchain,
          outcome: _signed(sign: c.blockchain == 'Ethereum'),
        ),
    ];
    String render(List<CompilerRow> c, List<MessageRow> m) =>
        renderCoverageJson(
          c,
          m,
          upstreamTag: '1.0.0',
          upstreamCommit: 'abcdef',
          libraryCommit: 'abcdef',
          artifactSetId: 'as_1.0.0',
          librarySha256: 'deadbeef',
        );

    test('carries the markdown rows, sorted by coin id, with verdicts', () {
      final json =
          jsonDecode(render(compiler, messages)) as Map<String, Object?>;
      expect(json['schema'], 1);
      expect((json['upstream']! as Map)['tag'], '1.0.0');
      final rows = (json['compiler']! as List).cast<Map<String, Object?>>();
      expect(rows.map((r) => r['coin_id']), [0, 60, 194]);
      expect(rows.last['agreement'], 'crash');
      expect(rows.last['crash_detail'], 'signal 6 in preimage_empty');
      expect(rows.first.containsKey('crash_detail'), isFalse);
      expect(rows.first['static'], 'supported');
      expect(rows.first['runtime'], 'reached');
      final msgs = (json['message']! as List).cast<Map<String, Object?>>();
      expect(msgs.map((r) => r['coin_id']), [0, 60, 194]);
      expect(msgs.first['specific_signer'], 'TWBitcoinMessageSigner');
      expect(msgs.last['specific_signer'], isNull);
    });

    test('is deterministic regardless of row order and ends in a newline', () {
      final a = render(compiler, messages);
      final b = render(compiler.reversed.toList(), messages.reversed.toList());
      expect(a, b);
      expect(a.endsWith('}\n'), isTrue);
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
        final rows = await probeMessageSignerViaChildren(
          executable: Platform.resolvedExecutable,
          script: 'bin/coverage_probe.dart',
          libPath: libPath,
        );
        expect(rows.length, 167);
        expect(rows.map((r) => r.coinId).toSet().length, 167);
        final byChain = {for (final r in rows) r.blockchain: r.result};
        expect(byChain['Ethereum']!.runtimeClass, 'supported');
        expect(byChain['Bitcoin']!.runtimeClass, 'unsupported');
      },
      tags: ['native'],
      timeout: const Timeout(Duration(minutes: 10)),
    );
  });
}

class _FakeNative implements MessageSignerNative {
  @override
  Uint8List? sign(int coinId, Uint8List input) => null;

  @override
  Uint8List? preImageHashes(int coinId, Uint8List input) =>
      Uint8List.fromList([1]);

  @override
  bool verify(int coinId, Uint8List input) => false;
}
