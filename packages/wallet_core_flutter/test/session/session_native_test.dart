/// The session against the real host library, through the public API only —
/// plus the internal test entry point for the library path and the expected
/// identity, which the public `initialize()` deliberately cannot take.
///
/// Skips when the library is absent; `WCF_NATIVE_REQUIRED=1` turns that into
/// a failure (see `../support/host_library.dart`).
@Tags(['native'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/src/session/testing.dart';
import 'package:wallet_core_flutter/src/worker/handler.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';
import 'package:wallet_core_flutter_native/wallet_core_flutter_native.dart'
    show ManifestIdentity;
import 'package:wcf_tool_vectors/inventory.dart';

import '../support/fixtures.dart';
import '../support/host_library.dart';

/// The host library's identity: `tools/native_build/build_apple.sh` at the
/// pinned commit, artifact set `as_4.8.0_000`, built locally.
const ManifestIdentity _hostIdentity = ManifestIdentity(
  artifactSetId: 'as_4.8.0_000',
  upstreamCommit: 'd692ac27749d0c615e17c751b70ab4f0aa75c59b',
);

String _hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Matcher _invalid(String inputName) => throwsA(
  isA<InvalidInputError>().having((e) => e.inputName, 'inputName', inputName),
);

/// Creates a wallet and drops every reference to it. A separate function so
/// that nothing in the caller's frame keeps the proxy reachable.
Future<void> _createAndDrop(WalletCore core) async {
  await core.wallets.create();
}

Object? _garbageSink;

/// Allocates a few megabytes nobody keeps, to give the collector a reason to
/// run.
void _makeGarbage() {
  for (var i = 0; i < 32; i++) {
    _garbageSink = Uint8List(1 << 16)..[0] = i;
  }
  if (_garbageSink != null) _garbageSink = null;
}

void main() {
  final skip = hostLibrarySkipReason();

  test('the public initialize() takes no path and reads no environment '
      'variable: it fails typed, with nothing handed out', () async {
    // Whatever WCF_NATIVE_LIB says, the public entry point does not look.
    // Either the platform location has no library (NativeLoadError) or the
    // one it finds cannot match the manifest's placeholder identity
    // (ManifestMismatchError).
    await expectLater(
      WalletCore.initialize(),
      throwsA(anyOf(isA<NativeLoadError>(), isA<ManifestMismatchError>())),
    );
  });

  test('a missing library is the public NativeLoadError', () async {
    final handler = EngineRequestHandler();
    await expectLater(
      initializeForTesting(
        hostLibraryPath: '/nonexistent/libTrustWalletCore.dylib',
        expectedIdentity: _hostIdentity,
        handler: handler,
      ),
      throwsA(
        isA<NativeLoadError>().having(
          (e) => e.attempts.map((a) => a.location).join(),
          'attempts',
          contains('/nonexistent/libTrustWalletCore.dylib'),
        ),
      ),
    );
    expect(handler.liveRefCount, 0);
    expect(handler.observer, isNull, reason: 'no engine was built');
  });

  group('WalletCore against the host library', skip: skip, () {
    late String libraryPath;
    late Inventory inventory;

    setUpAll(() {
      libraryPath = findHostLibrary()!;
      inventory = loadInventory();
    });

    Future<WalletCore> start({
      ManifestIdentity identity = _hostIdentity,
      Uint8List? manifestBytes,
      RequestHandler? handler,
    }) => initializeForTesting(
      hostLibraryPath: libraryPath,
      expectedIdentity: identity,
      manifestBytes: manifestBytes,
      handler: handler,
    );

    group('initialize', () {
      test('reaches ready', () async {
        final core = await start();
        expect(core.state, SessionState.ready);
        await core.shutdown();
        expect(core.state, SessionState.closed);
      });

      test('an identity mismatch is ManifestMismatchError(artifactSetMismatch) '
          'and leaves nothing to close', () async {
        final handler = EngineRequestHandler();
        await expectLater(
          start(
            identity: const ManifestIdentity(
              artifactSetId: 'as_wrong',
              upstreamCommit: 'd692ac27749d0c615e17c751b70ab4f0aa75c59b',
            ),
            handler: handler,
          ),
          throwsA(
            isA<ManifestMismatchError>()
                .having(
                  (e) => e.check,
                  'check',
                  ManifestCheck.artifactSetMismatch,
                )
                .having((e) => e.expected, 'expected', 'as_wrong')
                .having((e) => e.actual, 'actual', 'as_4.8.0_000'),
          ),
        );
        expect(handler.liveRefCount, 0);
        expect(handler.observer, isNull, reason: 'no engine was built');
      });

      test('the shipped manifest copy passes comparison 2; other bytes fail '
          'it', () async {
        final asset = File(
          '${repositoryRoot()!.path}/packages/wallet_core_flutter_native/'
          'assets/compat_manifest.json',
        ).readAsBytesSync();
        final core = await start(manifestBytes: asset);
        expect(core.state, SessionState.ready);
        await core.shutdown();

        await expectLater(
          start(manifestBytes: Uint8List.fromList([...asset, 0x0A])),
          throwsA(
            isA<ManifestMismatchError>().having(
              (e) => e.check,
              'check',
              ManifestCheck.manifestHashMismatch,
            ),
          ),
        );
      });
    });

    group('wallets', () {
      late WalletCore core;
      setUp(() async => core = await start());
      tearDown(() => core.shutdown());

      test('create with strength 128 and 256', () async {
        for (final (strength, words) in [(128, 12), (256, 24)]) {
          final wallet = await core.wallets.create(strength: strength);
          final mnemonic = await wallet.exportMnemonic();
          expect(mnemonic.split(' '), hasLength(words));
          expect(await core.mnemonics.isValid(mnemonic), isTrue);
          await wallet.close();
        }
      });

      test('the vector mnemonic derives ethereum-address-n/a-1 through the '
          'public API', () async {
        final vector = vectorById(inventory, 'ethereum-address-n/a-1');
        final input = vector.input as Map;
        final expected = vector.expected as Map;
        final wallet = await core.wallets.importMnemonic(
          input['mnemonic'] as String,
        );
        final account = await wallet.account(
          Coin.byId(vector.coin),
          path: input['derivation_path'] as String,
        );
        expect(account.address.value, expected['address']);
        expect(_hex(account.publicKey), expected['public_key']);
        expect(account.derivationPath, input['derivation_path']);
        expect(await wallet.exportMnemonic(), input['mnemonic']);
        expect(
          await core.addresses.isValid(
            account.address.value,
            coin: Coin.ethereum,
          ),
          isTrue,
        );
        final parsed = await core.addresses.parse(
          account.address.value,
          coin: Coin.ethereum,
        );
        expect(parsed, account.address);
        await wallet.close();
      });

      test('importEntropy reproduces the BIP-39 reference mnemonic', () async {
        final wallet = await core.wallets.importEntropy(Uint8List(16));
        expect(await wallet.exportMnemonic(), '${'abandon ' * 11}about');
        await wallet.close();
      });

      test('mnemonic words and suggestions come from upstream', () async {
        expect(await core.mnemonics.isValidWord('abandon'), isTrue);
        expect(await core.mnemonics.isValidWord('abandonx'), isFalse);
        expect(await core.mnemonics.suggest('aban'), contains('abandon'));
      });

      for (final id in [
        'ethereum-invalid_input-n/a-1',
        'ethereum-invalid_input-n/a-2',
        'ethereum-invalid_input-n/a-3',
      ]) {
        test('$id raises its typed error through the public API', () async {
          final vector = vectorById(inventory, id);
          final input = vector.input as Map;
          final coin = Coin.byId(vector.coin);
          switch ((vector.expected as Map)['error']) {
            case 'invalid_mnemonic':
              final mnemonic = input['mnemonic'] as String;
              await expectLater(
                core.wallets.importMnemonic(mnemonic),
                _invalid('mnemonic'),
              );
              expect(await core.mnemonics.isValid(mnemonic), isFalse);
              try {
                await core.wallets.importMnemonic(mnemonic);
              } on InvalidInputError catch (error) {
                expectRedacted(error, [mnemonic]);
              }
            case 'invalid_address':
              final address = input['address'] as String;
              expect(
                await core.addresses.isValid(address, coin: coin),
                isFalse,
              );
              await expectLater(
                core.addresses.parse(address, coin: coin),
                _invalid('address'),
              );
            case 'invalid_derivation_path':
              final wallet = await core.wallets.create();
              await expectLater(
                wallet.account(coin, path: input['derivation_path'] as String),
                _invalid('derivationPath'),
              );
              await wallet.close();
            case final other:
              fail('unmapped vector error $other');
          }
        });
      }
    });

    group('close (lifecycle.md §2, DECISION-12 §3.8)', () {
      test(
        'close() during an in-flight derive waits for it, then disposes',
        () async {
          final core = await start();
          final wallet = await core.wallets.create();
          final order = <String>[];
          final derive = wallet.account(Coin.ethereum).then((account) {
            order.add('account');
            return account;
          });
          final close = wallet.close().then((_) => order.add('close'));
          expect(wallet.isClosed, isTrue);
          await Future.wait([derive, close]);
          expect(order, ['account', 'close']);
          expect((await derive).address.value, startsWith('0x'));
          expect(debugHandlerOf(core).liveRefCount, 0);
          expect(debugLeakReportOf(core)!.live, 0);
          await core.shutdown();
        },
      );

      test('double close() and use after close', () async {
        final core = await start();
        final wallet = await core.wallets.create();
        final a = wallet.close();
        final b = wallet.close();
        expect(identical(a, b), isTrue);
        await a;
        await wallet.close();
        await expectLater(
          wallet.account(Coin.ethereum),
          throwsA(
            isA<ClosedError>().having((e) => e.resourceType, 'type', 'Wallet'),
          ),
        );
        await expectLater(wallet.exportMnemonic(), throwsA(isA<ClosedError>()));
        await core.shutdown();
      });
    });

    group('scope and shutdown leave nothing undisposed', () {
      test('scope closes everything in reverse order on return, and the leak '
          'tracker reports zero undisposed', () async {
        final core = await start();
        final wallets = await core.scope((s) async {
          final a = await s.createWallet(strength: 256);
          final b = await s.importEntropy(Uint8List(16));
          await a.account(Coin.ethereum);
          await b.account(Coin.bitcoin, network: Network.testnet);
          await a.exportMnemonic();
          expect(debugLeakReportOf(core)!.live, 2, reason: 'two wallets');
          return [a, b];
        });
        expect(wallets.every((w) => w.isClosed), isTrue);
        final report = debugLeakReportOf(core)!;
        expect(report.live, 0, reason: '$report');
        expect(report.finalizedWithoutDispose, 0, reason: '$report');
        expect(report.disposed, greaterThan(10));
        await core.shutdown();
      });

      test('scope closes everything on throw', () async {
        final core = await start();
        late Wallet escaped;
        await expectLater(
          core.scope<void>((s) async {
            escaped = await s.createWallet();
            await escaped.account(Coin.ethereum);
            throw StateError('body failed');
          }),
          throwsStateError,
        );
        expect(escaped.isClosed, isTrue);
        expect(debugLeakReportOf(core)!.live, 0);
        await core.shutdown();
      });

      test('shutdown releases every wallet left open, reports the count, and '
          'the leak tracker reports zero undisposed', () async {
        final core = await start();
        final open = [
          await core.wallets.create(),
          await core.wallets.importEntropy(Uint8List(32)),
          await core.wallets.create(strength: 192),
        ];
        await open.first.account(Coin.solana);
        expect(debugLeakReportOf(core)!.live, 3);
        await core.shutdown();
        await core.shutdown();
        final report = debugLeakReportOf(core)!;
        expect(report.stopped, isTrue);
        expect(report.live, 0, reason: '$report');
        expect(report.finalizedWithoutDispose, 0, reason: '$report');
        expect(debugHandlerOf(core).liveRefCount, 0);
        for (final wallet in open) {
          expect(wallet.isClosed, isTrue);
          await wallet.close();
          await expectLater(
            wallet.account(Coin.ethereum),
            throwsA(isA<ClosedError>()),
          );
        }
      });
    });

    test(
      'a dropped proxy is released by its finalizer while the session is '
      'ready (best effort: skips when the collector does not run in time)',
      () async {
        final core = await start();
        await _createAndDrop(core);
        expect(debugHandlerOf(core).liveRefCount, 1);
        const budget = Duration(seconds: 5);
        final deadline = DateTime.now().add(budget);
        while (debugHandlerOf(core).liveRefCount > 0 &&
            DateTime.now().isBefore(deadline)) {
          _makeGarbage();
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        final released = debugHandlerOf(core).liveRefCount == 0;
        if (released) {
          final report = debugLeakReportOf(core)!;
          expect(report.live, 0, reason: '$report');
          expect(
            report.finalizedWithoutDispose,
            0,
            reason: 'the proxy finalizer disposed it; nothing was leaked',
          );
        }
        await core.shutdown();
        if (!released) {
          // Never a failure: a managed Finalizer runs "as early as possible"
          // after unreachability and nothing in Dart can force a collection
          // (PRD §11.1 [VERIFIED]); shutdown released the wallet instead.
          markTestSkipped(
            'the collector did not run within ${budget.inSeconds}s; the '
            'finalizer path could not be observed.',
          );
        }
      },
    );
  });
}
