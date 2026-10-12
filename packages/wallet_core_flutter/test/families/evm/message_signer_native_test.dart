/// EVM message signing through the public API against the real host library:
/// `initialize` (by the internal test entry point), import, derive,
/// `EvmMessageRequest`, `signer.signMessage` — its result checked for
/// consistency with the signing core driven directly at engine level for the
/// same derived key, and every refusal checked for being typed, raised before
/// a key is derived, and leak-free.
///
/// The byte-for-byte vectors are signed with a raw upstream test key, which
/// no session can hold, so they are covered at core level by
/// `message_signing_core_native_test.dart`; the session test signs with an
/// HD-derived key, whose expected bytes are the engine-level core's own.
///
/// Skips when the library is absent; `WCF_NATIVE_REQUIRED=1` turns that into
/// a failure (see `../../support/host_library.dart`).
@Tags(['native'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/advanced.dart'
    show HDWallet, LeakTracker, NativeContext;
import 'package:wallet_core_flutter/src/engine/hd_wallet.dart'
    show KeyDerivation, withDerivedKeys;
import 'package:wallet_core_flutter/src/families/evm/message_family.dart';
import 'package:wallet_core_flutter/src/session/testing.dart';
import 'package:wallet_core_flutter/src/signing/signing_core.dart';
import 'package:wallet_core_flutter/src/worker/handler.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';

import '../../signing/signing_support.dart';
import '../../support/fixtures.dart';
import '../../support/host_library.dart';
import 'message_vector.dart';

void main() {
  final skip = hostLibrarySkipReason();

  group(
    'WalletCore.signer.signMessage against the host library',
    skip: skip,
    () {
      late String mnemonic;
      late String path;
      late MessageVector typedVector;

      setUpAll(() {
        final account = vectorById(loadInventory(), 'ethereum-address-n/a-1');
        mnemonic = (account.input as Map)['mnemonic'] as String;
        path = (account.input as Map)['derivation_path'] as String;
        typedVector = MessageVector.load(typedDataVectorId);
      });

      late WalletCore core;

      setUp(() async {
        core = await initializeForTesting(
          hostLibraryPath: findHostLibrary(),
          expectedIdentity: hostIdentity,
        );
      });

      tearDown(() async {
        final before = debugLeakReportOf(core)!;
        expect(before.finalizedWithoutDispose, 0, reason: '$before');
        await core.shutdown();
        final after = debugLeakReportOf(core)!;
        expect(after.live, 0, reason: '$after');
        expect(after.finalizedWithoutDispose, 0, reason: '$after');
      });

      void expectOnlyWalletLive() {
        final report = debugLeakReportOf(core)!;
        expect(report.live, 1, reason: 'the wallet only: $report');
        expect(report.finalizedWithoutDispose, 0, reason: '$report');
      }

      int keysDerived() =>
          (debugHandlerOf(core) as EngineRequestHandler).keysDerived;

      EvmMessageRequest personal(String text, {int? chainId}) =>
          EvmMessageRequest.personal(
            Uint8List.fromList(utf8.encode(text)),
            coin: Coin.ethereum,
            chainId: chainId,
          );

      /// The same message signed by the core directly, with the key derived at
      /// engine level for the same path, in a context of its own.
      EvmMessageSignResult engineLevelSign(EvmMessageRequest request) {
        final tracker = LeakTracker.maybeCreate()!;
        final context = NativeContext(openHostBindings(), observer: tracker);
        final wallet = HDWallet.fromMnemonic(context, mnemonic);
        final family = switch (request.type) {
          EvmMessageType.personal => evmPersonalMessageFamily,
          EvmMessageType.typedData => evmTypedDataMessageFamily,
        };
        try {
          return withDerivedKeys(
            {KeyRole.primary: KeyDerivation(wallet, Coin.ethereum, path)},
            (keys) => SyncSigningCore(context).signMessage(
              family.encodeKeylessInput(request),
              family: family,
              coin: Coin.ethereum,
              requiredRoles: const [KeyRole.primary],
              keys: keys,
              usedKeys: const <KeyLocator>{},
            ),
          );
        } finally {
          wallet.dispose();
          expect(tracker.report.live, 0, reason: '${tracker.report}');
          tracker.stop();
        }
      }

      test('import → derive → request → signMessage gives a result equal to '
          "the engine-level core's, for both kinds, with usedKeys the locator "
          'set', () async {
        final wallet = await core.wallets.importMnemonic(mnemonic);
        final locator = KeyLocator.hdPath(wallet.ref, Coin.ethereum, path);

        for (final request in [
          personal('Foo'),
          EvmMessageRequest.typedData(
            typedVector.input['typed_data'] as String,
            coin: Coin.ethereum,
          ),
        ]) {
          final result = await core.signer.signMessage(request, {locator});
          expect(result, isA<EvmMessageSignResult>());
          final message = result as EvmMessageSignResult;
          final reference = engineLevelSign(request);
          expect(listEquals(message.signature, reference.signature), isTrue);
          expect(message.signature, hasLength(65));
          expect(message.messageType, request.type);
          expect(message.coin, Coin.ethereum);
          expect(message.usedKeys, {locator});
          expect(
            message.toString(),
            isNot(contains(mnemonic.split(' ').first)),
          );
          expectOnlyWalletLive();
        }

        // Different messages sign differently; the same one signs the same.
        final a = await core.signer.signMessage(personal('a'), {locator});
        final b = await core.signer.signMessage(personal('b'), {locator});
        final aAgain = await core.signer.signMessage(personal('a'), {locator});
        expect(
          (a as EvmMessageSignResult).signatureHex,
          isNot((b as EvmMessageSignResult).signatureHex),
        );
        expect(a.signatureHex, (aAgain as EvmMessageSignResult).signatureHex);

        await wallet.close();
      });

      test('an EIP-155 variant is UnsupportedOperationError before any key is '
          'derived, whatever the key set', () async {
        final wallet = await core.wallets.importMnemonic(mnemonic);
        final locator = KeyLocator.hdPath(wallet.ref, Coin.ethereum, path);
        for (final (request, capability) in [
          (personal('Foo', chainId: 1), 'messageType:eip155'),
          (
            EvmMessageRequest.typedData(
              typedVector.input['typed_data'] as String,
              coin: Coin.ethereum,
              chainId: 1,
            ),
            'messageType:typed_eip155',
          ),
        ]) {
          for (final keys in [
            <KeyLocator>{locator},
            <KeyLocator>{},
          ]) {
            await expectLater(
              core.signer.signMessage(request, keys),
              throwsA(
                isA<UnsupportedOperationError>().having(
                  (e) => e.capability,
                  'capability',
                  capability,
                ),
              ),
            );
          }
        }
        expect(keysDerived(), 0);
        await wallet.close();
      });

      test('key resolution refusals are typed and derive nothing', () async {
        final wallet = await core.wallets.importMnemonic(mnemonic);
        final locator = KeyLocator.hdPath(wallet.ref, Coin.ethereum, path);
        final request = personal('Foo');

        await expectLater(
          core.signer.signMessage(request, <KeyLocator>{}),
          throwsA(
            isA<KeyResolutionError>().having(
              (e) => e.reason,
              'reason',
              KeyResolutionReason.missingRole,
            ),
          ),
        );
        await expectLater(
          core.signer.signMessage(request, {
            locator,
            KeyLocator.hdPath(
              wallet.ref,
              Coin.ethereum,
              path,
              role: KeyRole.feePayer,
            ),
          }),
          throwsA(
            isA<KeyResolutionError>().having(
              (e) => e.reason,
              'reason',
              KeyResolutionReason.unusedLocator,
            ),
          ),
        );
        await expectLater(
          core.signer.signMessage(request, {
            KeyLocator.external('ledger-1', _noKey),
          }),
          throwsA(
            isA<UnsupportedOperationError>().having(
              (e) => e.capability,
              'capability',
              'external-signer',
            ),
          ),
        );
        await expectLater(
          core.signer.signMessage(request, {
            KeyLocator.hdPath(wallet.ref, Coin.bitcoin, "m/84'/0'/0'/0/0"),
          }),
          throwsA(
            isA<InvalidInputError>().having(
              (e) => e.inputName,
              'input',
              'keys',
            ),
          ),
        );
        expect(keysDerived(), 0);
        expectOnlyWalletLive();
        await wallet.close();
      });

      test('a closed wallet is ClosedError and a second session\'s reference '
          'is foreignRef, both before any derivation', () async {
        final wallet = await core.wallets.importMnemonic(mnemonic);
        final closed = KeyLocator.hdPath(wallet.ref, Coin.ethereum, path);
        await wallet.close();
        await expectLater(
          core.signer.signMessage(personal('Foo'), {closed}),
          throwsA(
            isA<ClosedError>().having((e) => e.resourceType, 'type', 'Wallet'),
          ),
        );

        final other = await initializeForTesting(
          hostLibraryPath: findHostLibrary(),
          expectedIdentity: hostIdentity,
        );
        final foreign = await other.wallets.importMnemonic(mnemonic);
        await expectLater(
          core.signer.signMessage(personal('Foo'), {
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

      test("upstream's refusal of a document that is not EIP-712 is a "
          'SigningError, leaves nothing undisposed, and the session signs '
          'again', () async {
        final wallet = await core.wallets.importMnemonic(mnemonic);
        final locator = KeyLocator.hdPath(wallet.ref, Coin.ethereum, path);
        await expectLater(
          core.signer.signMessage(
            EvmMessageRequest.typedData('{}', coin: Coin.ethereum),
            {locator},
          ),
          throwsA(
            isA<SigningError>().having(
              (e) => e.upstreamCode,
              'upstreamCode',
              greaterThan(0),
            ),
          ),
        );
        expect(keysDerived(), 1, reason: 'the key was derived, then released');
        expectOnlyWalletLive();
        final result = await core.signer.signMessage(personal('Foo'), {
          locator,
        });
        expect(result, isA<EvmMessageSignResult>());
        expectOnlyWalletLive();
        await wallet.close();
      });

      test('20 messages in a loop leave zero undisposed', () async {
        final wallet = await core.wallets.importMnemonic(mnemonic);
        final locator = KeyLocator.hdPath(wallet.ref, Coin.ethereum, path);
        final signatures = <String>{};
        for (var i = 0; i < 20; i++) {
          final result = await core.signer.signMessage(personal('message $i'), {
            locator,
          }) as EvmMessageSignResult;
          signatures.add(result.signatureHex);
          expectOnlyWalletLive();
        }
        expect(signatures, hasLength(20));
        expect(keysDerived(), 20);
        await wallet.close();
      });
    },
  );
}

final Uint8List _noKey = Uint8List.fromList(const [2, 3]);
