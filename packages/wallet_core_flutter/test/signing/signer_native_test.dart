/// The M0 signing flow against the real host library, through the public API
/// only — `initialize` (by the internal test entry point, for the library
/// path and the host identity, as in `../session/session_native_test.dart`),
/// import, derive, build a request, `signer.sign` — and its result checked
/// for consistency with the signing core driven directly at engine level.
///
/// The byte-for-byte vector `ethereum-sign-eip1559-1` is covered at core
/// level by `signing_core_native_test.dart`; this file adds no vector.
///
/// Skips when the library is absent; `WCF_NATIVE_REQUIRED=1` turns that into
/// a failure (see `../support/host_library.dart`).
@Tags(['native'])
library;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/advanced.dart'
    show HDWallet, LeakTracker, NativeContext;
import 'package:wallet_core_flutter/src/engine/hd_wallet.dart'
    show withDerivedKey;
import 'package:wallet_core_flutter/src/families/evm/evm_family.dart';
import 'package:wallet_core_flutter/src/session/testing.dart';
import 'package:wallet_core_flutter/src/signing/signing_core.dart';
import 'package:wallet_core_flutter/src/worker/handler.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';

import '../support/fixtures.dart';
import '../support/host_library.dart';
import 'signing_support.dart';

void main() {
  final skip = hostLibrarySkipReason();

  group('WalletCore.signer against the host library', skip: skip, () {
    late String mnemonic;
    late String path;
    late String address;
    late String to;

    setUpAll(() {
      final inventory = loadInventory();
      final account = vectorById(inventory, 'ethereum-address-n/a-1');
      mnemonic = (account.input as Map)['mnemonic'] as String;
      path = (account.input as Map)['derivation_path'] as String;
      address = (account.expected as Map)['address'] as String;
      to =
          (vectorById(inventory, 'ethereum-sign-eip1559-1').input
                  as Map)['to_address']
              as String;
    });

    late WalletCore core;

    setUp(() async {
      core = await initializeForTesting(
        hostLibraryPath: findHostLibrary(),
        expectedIdentity: hostIdentity,
      );
    });

    /// Zero undisposed after the test, with every wallet it opened closed,
    /// and again after shutdown.
    tearDown(() async {
      final before = debugLeakReportOf(core)!;
      expect(before.finalizedWithoutDispose, 0, reason: '$before');
      await core.shutdown();
      final after = debugLeakReportOf(core)!;
      expect(after.live, 0, reason: '$after');
      expect(after.finalizedWithoutDispose, 0, reason: '$after');
    });

    void expectNothingLive() {
      final report = debugLeakReportOf(core)!;
      expect(report.live, 0, reason: '$report');
      expect(report.finalizedWithoutDispose, 0, reason: '$report');
    }

    int keysDerived() =>
        (debugHandlerOf(core) as EngineRequestHandler).keysDerived;

    /// The same request signed by the core directly, with the key derived at
    /// engine level for the same path, in a context of its own.
    EvmSignResult engineLevelSign(EvmTransactionRequest request) {
      final tracker = LeakTracker.maybeCreate()!;
      final context = NativeContext(openHostBindings(), observer: tracker);
      final wallet = HDWallet.fromMnemonic(context, mnemonic);
      try {
        return withDerivedKey(
          wallet,
          Coin.ethereum,
          path,
          (key) => SyncSigningCore(context).sign(
            evmFamily.encodeKeylessInput(request),
            family: evmFamily,
            coin: Coin.ethereum,
            privateKey: key,
            usedKeys: const <KeyLocator>{},
          ),
        );
      } finally {
        wallet.dispose();
        expect(tracker.report.live, 0, reason: '${tracker.report}');
        tracker.stop();
      }
    }

    test('import → derive → request → sign gives an EvmSignResult equal to '
        "the engine-level core's, with usedKeys the locator set", () async {
      final wallet = await core.wallets.importMnemonic(mnemonic);
      final account = await wallet.account(Coin.ethereum, path: path);
      expect(account.address.value, address);

      final request = transferTo(to);
      final locator = KeyLocator.hdPath(
        wallet.ref,
        Coin.ethereum,
        account.derivationPath,
      );
      final result = await core.signer.sign(request, {locator});

      expect(result, isA<EvmSignResult>());
      final evm = result as EvmSignResult;
      final reference = engineLevelSign(request);
      expect(listEquals(evm.encoded, reference.encoded), isTrue);
      expect(listEquals(evm.v, reference.v), isTrue);
      expect(listEquals(evm.r, reference.r), isTrue);
      expect(listEquals(evm.s, reference.s), isTrue);
      expect(evm.coin, Coin.ethereum);
      expect(evm.usedKeys, {locator});
      expect(evm.toString(), isNot(contains(mnemonic.split(' ').first)));

      final again = await core.signer.signWithKey(request, locator);
      expect(listEquals((again as EvmSignResult).encoded, evm.encoded), isTrue);

      await wallet.close();
      expectNothingLive();
    });

    test(
      'sign after wallet.close() is ClosedError, and derives nothing',
      () async {
        final wallet = await core.wallets.importMnemonic(mnemonic);
        final locator = KeyLocator.hdPath(wallet.ref, Coin.ethereum, path);
        await wallet.close();
        await expectLater(
          core.signer.sign(transferTo(to), {locator}),
          throwsA(
            isA<ClosedError>().having((e) => e.resourceType, 'type', 'Wallet'),
          ),
        );
        expect(keysDerived(), 0);
        expectNothingLive();
      },
    );

    test('a reference from a second session is foreignRef', () async {
      final other = await initializeForTesting(
        hostLibraryPath: findHostLibrary(),
        expectedIdentity: hostIdentity,
      );
      final foreign = await other.wallets.importMnemonic(mnemonic);
      await expectLater(
        core.signer.sign(transferTo(to), {
          KeyLocator.hdPath(foreign.ref, Coin.ethereum, path),
        }),
        throwsA(
          isA<KeyResolutionError>().having(
            (e) => e.reason,
            'reason',
            KeyResolutionReason.foreignRef,
          ),
        ),
      );
      expect(keysDerived(), 0);
      await other.shutdown();
      expect(debugLeakReportOf(other)!.live, 0);
    });

    test('a wrong-family coin and a bad checksum are typed errors before any '
        'key is derived', () async {
      final wallet = await core.wallets.importMnemonic(mnemonic);
      await expectLater(
        core.signer.sign(transferTo(to), {
          KeyLocator.hdPath(wallet.ref, Coin.bitcoin, "m/84'/0'/0'/0/0"),
        }),
        throwsA(
          isA<InvalidInputError>().having((e) => e.inputName, 'input', 'keys'),
        ),
      );
      await expectLater(
        core.signer.sign(transferTo(breakChecksum(to)), {
          KeyLocator.hdPath(wallet.ref, Coin.ethereum, path),
        }),
        throwsA(
          isA<InvalidInputError>().having((e) => e.inputName, 'input', 'to'),
        ),
      );
      expect(
        () => EvmTransactionRequest.transfer(
          coin: Coin.bitcoin,
          chainId: 1,
          nonce: BigInt.zero,
          to: to,
          valueWei: BigInt.zero,
          maxFeePerGas: BigInt.one,
          maxPriorityFeePerGas: BigInt.one,
          gasLimit: BigInt.one,
        ),
        throwsA(
          isA<InvalidInputError>().having((e) => e.inputName, 'input', 'coin'),
        ),
      );
      expect(keysDerived(), 0);
      await wallet.close();
      expectNothingLive();
    });

    test('20 signs in a loop leave zero undisposed', () async {
      final wallet = await core.wallets.importMnemonic(mnemonic);
      final locator = KeyLocator.hdPath(wallet.ref, Coin.ethereum, path);
      final encodings = <String>{};
      for (var nonce = 0; nonce < 20; nonce++) {
        final result = await core.signer.sign(transferTo(to, nonce: nonce), {
          locator,
        }) as EvmSignResult;
        encodings.add(result.encoded.join(','));
        final report = debugLeakReportOf(core)!;
        expect(report.live, 1, reason: 'the wallet only: $report');
      }
      expect(encodings, hasLength(20));
      expect(keysDerived(), 20);
      await wallet.close();
      expectNothingLive();
    });
  });
}
