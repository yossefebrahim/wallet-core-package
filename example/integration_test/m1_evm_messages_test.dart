/// EVM message signing (T2.7) on a device, debug and release: both upstream
/// message vectors byte for byte through the signing core's message path
/// (`TWMessageSignerSign`), and the public surface — import, derive,
/// `signer.signMessage` — for an HD-derived key, with its typed refusals and a
/// zero leak report. One test per claim; every expected value comes from
/// `m1_evm_messages_vectors.dart`, which a host test holds equal to
/// `test_vectors/ethereum/vectors.yaml`.
///
/// The library is always the one the build hook bundled into the app: no test
/// here passes a host library path.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kProfileMode, kReleaseMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
// The public surface has no raw-key import (PRD §10.2: signers take
// `KeyLocator`s), and the byte-for-byte vectors are signed by a raw upstream
// test key. So this file imports the SDK's internals for those two tests, the
// way `m0_exit_clauses_test.dart` does for its vector.
// ignore_for_file: implementation_imports
import 'package:wallet_core_flutter/advanced.dart'
    show
        LeakTracker,
        NativeContext,
        NoopResourceObserver,
        TWDataHandle,
        WalletCoreBindings;
import 'package:wallet_core_flutter/src/engine/handles.dart'
    show PrivateKeyHandle;
import 'package:wallet_core_flutter/src/families/evm/message_family.dart';
import 'package:wallet_core_flutter/src/session/testing.dart'
    show debugLeakReportOf, initializeForTesting;
import 'package:wallet_core_flutter/src/signing/key_locator.dart';
import 'package:wallet_core_flutter/src/signing/signing_core.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:wallet_core_flutter_native/wallet_core_flutter_native.dart'
    show WalletCoreNative;

import 'm1_evm_messages_vectors.dart' as v;

const Timeout _timeout = Timeout(Duration(minutes: 5));

Uint8List _unhex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

/// Signs [request] with the raw vector key through the core's message path,
/// in a context over the bundled library, and checks that nothing is left
/// undisposed.
EvmMessageSignResult _signWithVectorKey(
  EvmMessageRequest request,
  EvmMessageFamily family,
) {
  final bindings = WalletCoreBindings(WalletCoreNative.load());
  final tracker = LeakTracker.maybeCreate();
  final context = NativeContext(
    bindings,
    observer: tracker ?? const NoopResourceObserver(),
  );
  final core = SyncSigningCore(context);
  final usedKeys = {KeyLocator.imported(issueKeyRef(1))};
  // The signing core borrows a native key handle per role: the vector's raw
  // key becomes one with `TWPrivateKeyCreateWithData`.
  final keyData = TWDataHandle.fromBytes(context, _unhex(v.messagePrivateKey));
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
  final EvmMessageSignResult result;
  try {
    result = core.signMessage(
      family.encodeKeylessInput(request),
      family: family,
      coin: Coin.ethereum,
      requiredRoles: const [KeyRole.primary],
      keys: {KeyRole.primary: key},
      usedKeys: usedKeys,
    );
  } finally {
    key.dispose();
  }
  expect(result.coin, Coin.ethereum);
  expect(result.usedKeys, usedKeys);
  if (tracker != null) {
    // Four disposals since the snapshot: inside the call, the key's TWData
    // copy, the keyed input and the output; after it, the test's own key
    // handle (the core only borrows it).
    expect(tracker.report.live, 0, reason: '${tracker.report}');
    expect(
      tracker.report.disposed - disposedBeforeSign!,
      4,
      reason: '${tracker.report}',
    );
    tracker.stop();
  }
  return result;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the personal-message vector is signed byte for byte '
      '(ethereum-sign_message-personal-1)', (WidgetTester tester) async {
    final result = _signWithVectorKey(
      EvmMessageRequest.personal(
        Uint8List.fromList(utf8.encode(v.personalMessage)),
        coin: Coin.ethereum,
      ),
      evmPersonalMessageFamily,
    );
    expect(result.signatureHex, v.personalExpectedSignature);
    expect(result.signature, hasLength(65));
    expect(result.messageType, EvmMessageType.personal);
  }, timeout: _timeout);

  testWidgets('the typed-data vector is signed byte for byte '
      '(ethereum-sign_message-eip712-1)', (WidgetTester tester) async {
    final result = _signWithVectorKey(
      EvmMessageRequest.typedData(v.typedDataDocument, coin: Coin.ethereum),
      evmTypedDataMessageFamily,
    );
    expect(result.signatureHex, v.typedDataExpectedSignature);
    expect(result.signature, hasLength(65));
    expect(result.messageType, EvmMessageType.typedData);
  }, timeout: _timeout);

  testWidgets(
    'the public surface signs a message with an HD-derived key, refuses an '
    'EIP-155 variant and a missing key with typed errors, and leaks nothing',
    (WidgetTester tester) async {
      final core = await initializeForTesting();
      final wallet = await core.wallets.importMnemonic(v.addressMnemonic);
      final account = await wallet.account(Coin.ethereum, path: v.addressPath);
      final locator = KeyLocator.hdPath(
        wallet.ref,
        account.coin,
        account.derivationPath,
      );
      final personal = EvmMessageRequest.personal(
        Uint8List.fromList(utf8.encode(v.personalMessage)),
        coin: Coin.ethereum,
      );

      final first = await core.signer.signMessage(personal, {
        locator,
      }) as EvmMessageSignResult;
      final again = await core.signer.signMessage(personal, {
        locator,
      }) as EvmMessageSignResult;
      expect(first.signature, hasLength(65));
      expect(first.signatureHex, again.signatureHex, reason: 'deterministic');
      expect(first.usedKeys, {locator});
      // A different key than the vector's: a different signature.
      expect(first.signatureHex, isNot(v.personalExpectedSignature));

      final typed = await core.signer.signMessage(
        EvmMessageRequest.typedData(v.typedDataDocument, coin: Coin.ethereum),
        {locator},
      ) as EvmMessageSignResult;
      expect(typed.signature, hasLength(65));
      expect(typed.messageType, EvmMessageType.typedData);

      await expectLater(
        core.signer.signMessage(
          EvmMessageRequest.personal(
            Uint8List.fromList(utf8.encode(v.personalMessage)),
            coin: Coin.ethereum,
            chainId: 1,
          ),
          {locator},
        ),
        throwsA(isA<UnsupportedOperationError>()),
      );
      await expectLater(
        core.signer.signMessage(personal, <KeyLocator>{}),
        throwsA(
          isA<KeyResolutionError>().having(
            (e) => e.reason,
            'reason',
            KeyResolutionReason.missingRole,
          ),
        ),
      );
      await wallet.close();

      if (kReleaseMode || kProfileMode) {
        // The tracker is constructed only inside an `assert`: a release or
        // profile build has none, so there is nothing to report.
        expect(debugLeakReportOf(core), isNull);
        await core.shutdown();
        return;
      }
      final beforeShutdown = debugLeakReportOf(core)!;
      expect(beforeShutdown.live, 0, reason: '$beforeShutdown');
      expect(beforeShutdown.finalizedWithoutDispose, 0);
      expect(beforeShutdown.disposed, greaterThan(0), reason: 'not vacuous');
      await core.shutdown();
      final afterShutdown = debugLeakReportOf(core)!;
      expect(afterShutdown.live, 0, reason: '$afterShutdown');
      expect(afterShutdown.finalizedWithoutDispose, 0);
    },
    timeout: _timeout,
  );
}
