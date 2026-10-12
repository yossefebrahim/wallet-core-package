/// The M1 Solana vectors asserted on a device, debug and release:
/// `solana-sign-legacy-1` byte for byte through the signing core (the vector's
/// key is a raw upstream test key), `solana-address-n/a-1` through the public
/// surface, the HD-derived key signing as that address, typed errors, and a
/// zero leak report. Every expected value comes from `m1_solana_vectors.dart`,
/// which a host test holds equal to `test_vectors/solana/vectors.yaml`.
///
/// The library is always the one the build hook bundled into the app: no test
/// here passes a host library path.
library;

import 'dart:ffi' show nullptr;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kProfileMode, kReleaseMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
// The public surface has no raw-key import yet (PRD §10.2: signers take
// `KeyLocator`s), and the byte-for-byte vector is signed by a raw upstream
// test key. So this one file imports the SDK's internals, the way the SDK's
// own host tests do (`test/families/solana/solana_native_test.dart`) and the
// M0 exit-clause test does.
// ignore_for_file: implementation_imports
import 'package:wallet_core_flutter/advanced.dart'
    show
        LeakTracker,
        NativeContext,
        NoopResourceObserver,
        TWDataHandle,
        TWStringHandle,
        WalletCoreBindings;
import 'package:wallet_core_flutter/src/engine/handles.dart'
    show PrivateKeyHandle;
import 'package:wallet_core_flutter/src/families/solana/solana_family.dart';
import 'package:wallet_core_flutter/src/session/testing.dart'
    show debugLeakReportOf, initializeForTesting;
import 'package:wallet_core_flutter/src/signing/key_locator.dart';
import 'package:wallet_core_flutter/src/signing/signing_core.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:wallet_core_flutter_native/wallet_core_flutter_native.dart'
    show WalletCoreNative;

import 'm1_solana_vectors.dart' as v;
import 'vector_results.dart';

const Timeout _timeout = Timeout(Duration(minutes: 5));

/// [text] decoded by upstream's `TWBase58DecodeNoCheck`, the decoder the
/// upstream test uses for the vector's key. Tests only.
Uint8List _base58Decode(NativeContext context, String text) {
  final string = TWStringHandle.fromString(context, text);
  try {
    final pointer = context.bindings.TWBase58DecodeNoCheck(string.pointer);
    if (pointer == nullptr) {
      throw StateError('upstream could not decode the base58 text');
    }
    final data = TWDataHandle.adopt(context, pointer);
    try {
      return data.copyBytes();
    } finally {
      data.dispose();
    }
  } finally {
    string.dispose();
  }
}

SolanaTransactionRequest _vectorRequest() => SolanaTransactionRequest.transfer(
  to: v.signToAddress,
  lamports: int.parse(v.signLamports),
  recentBlockhash: v.signRecentBlockhash,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the legacy transfer vector is signed byte for byte '
      '(solana-sign-legacy-1)', (WidgetTester tester) async {
    // The bundled library, opened as the session's executor opens it:
    // default locations for this platform, no host path.
    final bindings = WalletCoreBindings(WalletCoreNative.load());
    final tracker = LeakTracker.maybeCreate();
    final context = NativeContext(
      bindings,
      observer: tracker ?? const NoopResourceObserver(),
    );
    final core = SyncSigningCore(context);
    final request = _vectorRequest();
    final usedKeys = {KeyLocator.imported(issueKeyRef(1))};

    // The signing core borrows a native key handle per role: the vector's
    // base58 key becomes one through upstream (`TWBase58DecodeNoCheck`, then
    // `TWPrivateKeyCreateWithData`), in this test and never in `lib/`.
    final raw = _base58Decode(context, v.signPrivateKeyBase58);
    final keyData = TWDataHandle.fromBytes(context, raw);
    raw.fillRange(0, raw.length, 0);
    final PrivateKeyHandle key;
    try {
      key = PrivateKeyHandle.adopt(
        context,
        bindings.TWPrivateKeyCreateWithData(keyData.pointer),
      );
    } finally {
      keyData.dispose();
    }
    final disposedBeforeSign = tracker?.report.disposed;
    final SolanaSignResult result;
    try {
      result = core.sign(
        solanaFamily.encodeKeylessInput(request),
        family: solanaFamily,
        coin: Coin.solana,
        requiredRoles: const [KeyRole.primary],
        keys: {KeyRole.primary: key},
        usedKeys: usedKeys,
      );
    } finally {
      key.dispose();
    }

    expect(result.encoded, v.signExpectedEncoded);
    expect(result.unsignedTransaction, v.signExpectedUnsignedTx);
    expect(result.encoding, SolanaEncoding.base58);
    expect(result.coin, Coin.solana);
    expect(result.usedKeys, usedKeys);
    if (tracker != null) {
      // Four disposals since the snapshot: inside the call, the key's TWData
      // copy, the keyed input and the output; after it, the test's own key
      // handle (the core only borrows it, so the `finally` above disposes it).
      expect(tracker.report.live, 0, reason: '${tracker.report}');
      expect(
        tracker.report.disposed - disposedBeforeSign!,
        4,
        reason: '${tracker.report}',
      );
      tracker.stop();
    }
    recordVectorPass('solana-sign-legacy-1');
  }, timeout: _timeout);

  testWidgets(
    'the vector mnemonic derives solana-address-n/a-1 through the public '
    'surface, and its key signs as that address',
    (WidgetTester tester) async {
      final core = await initializeForTesting();
      try {
        final wallet = await core.wallets.importMnemonic(v.addressMnemonic);
        final account = await wallet.account(Coin.solana, path: v.addressPath);
        expect(account.address.value, v.addressExpected);
        expect(
          await core.addresses.isValid(
            account.address.value,
            coin: Coin.solana,
          ),
          isTrue,
        );
        // The default derivation is the same path.
        expect(
          (await wallet.account(Coin.solana)).address.value,
          v.addressExpected,
        );

        final locator = KeyLocator.hdPath(
          wallet.ref,
          account.coin,
          account.derivationPath,
        );
        final signed = await core.signer.sign(_vectorRequest(), {locator});
        expect(signed, isA<SolanaSignResult>());
        final result = signed as SolanaSignResult;
        expect(result.coin, Coin.solana);
        expect(result.usedKeys, {locator});
        expect(result.encoding, SolanaEncoding.base58);

        // A one-signer legacy transaction is the signature count (1), the
        // 64-byte signature, the 3-byte message header, the account count and
        // the 32-byte account keys, the fee payer first: the first key is the
        // signer's public key, which is the address of the vector.
        final context = NativeContext(
          WalletCoreBindings(WalletCoreNative.load()),
        );
        final tx = _base58Decode(context, result.encoded);
        expect(tx[0], 1);
        expect(tx.sublist(65, 68), [1, 0, 1]);
        expect(tx.sublist(69, 101), _base58Decode(context, v.addressExpected));
        await wallet.close();
        recordVectorPass('solana-address-n/a-1');
      } finally {
        await core.shutdown();
      }
    },
    timeout: _timeout,
  );

  testWidgets(
    'a request that is not valid is a typed error: at construction, and at '
    'sign time before any key is derived',
    (WidgetTester tester) async {
      expect(
        () => SolanaTransactionRequest.transfer(
          to: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
          lamports: 1,
          recentBlockhash: v.signRecentBlockhash,
        ),
        throwsA(
          isA<InvalidInputError>().having((e) => e.inputName, 'input', 'to'),
        ),
      );
      expect(
        () => SolanaTransactionRequest.transfer(
          to: v.signToAddress,
          lamports: -1,
          recentBlockhash: v.signRecentBlockhash,
        ),
        throwsA(
          isA<InvalidInputError>().having(
            (e) => e.inputName,
            'input',
            'lamports',
          ),
        ),
      );

      final core = await initializeForTesting();
      try {
        final wallet = await core.wallets.importMnemonic(v.addressMnemonic);
        await expectLater(
          core.signer.sign(
            SolanaTransactionRequest.transfer(
              to: v.notAnAddress,
              lamports: 1,
              recentBlockhash: v.signRecentBlockhash,
            ),
            {KeyLocator.hdPath(wallet.ref, Coin.solana, v.addressPath)},
          ),
          throwsA(
            isA<InvalidInputError>().having((e) => e.inputName, 'input', 'to'),
          ),
        );
        // No request names a fee payer, so a key in that role is unused.
        await expectLater(
          core.signer.sign(_vectorRequest(), {
            KeyLocator.hdPath(
              wallet.ref,
              Coin.solana,
              v.addressPath,
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
        await wallet.close();
      } finally {
        await core.shutdown();
      }
    },
    timeout: _timeout,
  );

  testWidgets(
    'the leak tracker reports nothing live and nothing finalized without '
    'dispose after import, derive, sign, close and shutdown',
    (WidgetTester tester) async {
      final core = await initializeForTesting();
      final wallet = await core.wallets.importMnemonic(v.addressMnemonic);
      final account = await wallet.account(Coin.solana, path: v.addressPath);
      final signed = await core.signer.sign(_vectorRequest(), {
        KeyLocator.hdPath(wallet.ref, account.coin, account.derivationPath),
      });
      expect(signed, isA<SolanaSignResult>());
      await wallet.close();

      if (kReleaseMode || kProfileMode) {
        // The tracker is constructed only inside an `assert`, so a release or
        // profile build has none: there is nothing to report.
        expect(debugLeakReportOf(core), isNull);
        await core.shutdown();
        expect(debugLeakReportOf(core), isNull);
        return;
      }

      final beforeShutdown = debugLeakReportOf(core);
      expect(beforeShutdown, isNotNull, reason: 'a debug build has a tracker');
      expect(beforeShutdown!.live, 0, reason: '$beforeShutdown');
      expect(beforeShutdown.finalizedWithoutDispose, 0);
      expect(beforeShutdown.disposed, greaterThan(0), reason: 'not vacuous');

      await core.shutdown();
      final afterShutdown = debugLeakReportOf(core)!;
      expect(afterShutdown.stopped, isTrue);
      expect(afterShutdown.live, 0, reason: '$afterShutdown');
      expect(afterShutdown.finalizedWithoutDispose, 0);
    },
    timeout: _timeout,
  );
}
