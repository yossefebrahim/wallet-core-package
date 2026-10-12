/// The M0 exit clauses (PRD §18) asserted on a device, debug and release:
/// a byte-for-byte EIP-1559 vector, typed errors for an invalid address and
/// derivation path (and mnemonic), a zero leak report, and a mismatched
/// identity refused. One test per clause; every expected value comes from
/// `m0_vectors.dart`, which a host test holds equal to
/// `test_vectors/ethereum/vectors.yaml`.
///
/// The library is always the one the build hook bundled into the app: no test
/// here passes a host library path.
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kProfileMode, kReleaseMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
// The public surface has no raw-key import yet (PRD §10.2: signers take
// `KeyLocator`s), and the byte-for-byte vector is signed by a raw upstream
// test key. So this one file imports the SDK's internals, the way the SDK's
// own host tests do (`test/signing/signing_core_native_test.dart`,
// `test/session/session_native_test.dart`).
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
import 'package:wallet_core_flutter/src/families/evm/evm_family.dart';
import 'package:wallet_core_flutter/src/session/testing.dart'
    show debugLeakReportOf, initializeForTesting;
import 'package:wallet_core_flutter/src/signing/key_locator.dart';
import 'package:wallet_core_flutter/src/signing/signing_core.dart';
import 'package:wallet_core_flutter/src/worker/handler.dart'
    show EngineRequestHandler;
import 'package:wallet_core_flutter/wallet_core_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:wallet_core_flutter_native/wallet_core_flutter_native.dart'
    show ManifestIdentity, WalletCoreNative;

import 'm0_vectors.dart' as v;

const Timeout _timeout = Timeout(Duration(minutes: 5));

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _unhex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('clause 1: the EIP-1559 vector is signed byte for byte '
      '(ethereum-sign-eip1559-1)', (WidgetTester tester) async {
    // The bundled library, opened as the session's executor opens it:
    // default locations for this platform, no host path.
    final bindings = WalletCoreBindings(WalletCoreNative.load());
    final tracker = LeakTracker.maybeCreate();
    final context = NativeContext(
      bindings,
      observer: tracker ?? const NoopResourceObserver(),
    );
    final core = SyncSigningCore(context);

    final request = EvmTransactionRequest.transfer(
      coin: Coin.ethereum,
      chainId: int.parse(v.signChainId),
      nonce: BigInt.parse(v.signNonce),
      to: v.signToAddress,
      valueWei: BigInt.parse(v.signValue),
      maxFeePerGas: BigInt.parse(v.signMaxFeePerGas),
      maxPriorityFeePerGas: BigInt.parse(v.signMaxPriorityFeePerGas),
      gasLimit: BigInt.parse(v.signGasLimit),
    );
    final usedKeys = {KeyLocator.imported(issueKeyRef(1))};
    // The signing core borrows a native key handle per role (T2.0): the
    // vector's raw key becomes one with `TWPrivateKeyCreateWithData`.
    final keyData = TWDataHandle.fromBytes(context, _unhex(v.signPrivateKey));
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
    final EvmSignResult result;
    try {
      result = core.sign(
        evmFamily.encodeKeylessInput(request),
        family: evmFamily,
        coin: Coin.ethereum,
        requiredRoles: const [KeyRole.primary],
        keys: {KeyRole.primary: key},
        usedKeys: usedKeys,
      );
    } finally {
      key.dispose();
    }

    expect(_hex(result.encoded), v.signExpectedEncoded);
    expect(_hex(result.v), v.signExpectedV);
    expect(_hex(result.r), v.signExpectedR);
    expect(_hex(result.s), v.signExpectedS);
    expect(result.coin, Coin.ethereum);
    expect(result.usedKeys, usedKeys);
    if (tracker != null) {
      // The key's TWData copy, the keyed input and the output: all created
      // and disposed inside the call (the borrowed key handle is the test's).
      expect(tracker.report.live, 0, reason: '${tracker.report}');
      expect(
        tracker.report.disposed - disposedBeforeSign!,
        3,
        reason: '${tracker.report}',
      );
      tracker.stop();
    }
  }, timeout: _timeout);

  testWidgets(
    'clause 2: an invalid mnemonic, address and derivation path raise '
    'InvalidInputError (ethereum-invalid_input-n/a-1, -2, -3)',
    (WidgetTester tester) async {
      final core = await initializeForTesting();
      try {
        await expectLater(
          core.wallets.importMnemonic(v.invalidMnemonic),
          throwsA(
            isA<InvalidInputError>().having(
              (e) => e.inputName,
              'inputName',
              'mnemonic',
            ),
          ),
        );

        expect(
          await core.addresses.isValid(v.invalidAddress, coin: Coin.ethereum),
          isFalse,
        );
        await expectLater(
          core.addresses.parse(v.invalidAddress, coin: Coin.ethereum),
          throwsA(
            isA<InvalidInputError>().having(
              (e) => e.inputName,
              'inputName',
              'address',
            ),
          ),
        );

        final wallet = await core.wallets.importMnemonic(v.addressMnemonic);
        await expectLater(
          wallet.account(Coin.ethereum, path: v.invalidDerivationPath),
          throwsA(
            isA<InvalidInputError>().having(
              (e) => e.inputName,
              'inputName',
              'derivationPath',
            ),
          ),
        );
        // The wallet is still usable: the rejection did not close it.
        final account = await wallet.account(
          Coin.ethereum,
          path: v.addressPath,
        );
        expect(account.address.value, v.addressExpected);
        await wallet.close();
      } finally {
        await core.shutdown();
      }
    },
    timeout: _timeout,
  );

  testWidgets(
    'clause 3: the leak tracker reports nothing live and nothing finalized '
    'without dispose after create, import, derive, sign, close and shutdown',
    (WidgetTester tester) async {
      final core = await initializeForTesting();
      final created = await core.wallets.create();
      final imported = await core.wallets.importMnemonic(v.addressMnemonic);
      final account = await imported.account(
        Coin.ethereum,
        path: v.addressPath,
      );
      expect(account.address.value, v.addressExpected);
      final signed = await core.signer.sign(
        EvmTransactionRequest.transfer(
          coin: Coin.ethereum,
          chainId: int.parse(v.signChainId),
          nonce: BigInt.parse(v.signNonce),
          to: v.signToAddress,
          valueWei: BigInt.parse(v.signValue),
          maxFeePerGas: BigInt.parse(v.signMaxFeePerGas),
          maxPriorityFeePerGas: BigInt.parse(v.signMaxPriorityFeePerGas),
          gasLimit: BigInt.parse(v.signGasLimit),
        ),
        {KeyLocator.hdPath(imported.ref, account.coin, account.derivationPath)},
      );
      expect(signed, isA<EvmSignResult>());
      await created.close();
      await imported.close();

      if (kReleaseMode || kProfileMode) {
        // The tracker is constructed only inside an `assert`, so a release or
        // profile build has none: there is nothing to report. This is the
        // release-mode meaning of the clause, pending the owner's wording.
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

  testWidgets(
    'clause 4: the shipped identity initializes; another artifact-set id is '
    'ManifestMismatchError(artifactSetMismatch) and leaves nothing to close',
    (WidgetTester tester) async {
      // Positive half: the manifest's own identity, against the bundled
      // library, with no host path.
      final core = await initializeForTesting();
      expect(core.state, SessionState.ready);
      await core.shutdown();
      expect(core.state, SessionState.closed);

      // Negative half: same library, a different expected artifact-set id.
      final handler = EngineRequestHandler();
      await expectLater(
        initializeForTesting(
          expectedIdentity: const ManifestIdentity(
            artifactSetId: v.wrongArtifactSetId,
            upstreamCommit: v.upstreamCommit,
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
              .having((e) => e.expected, 'expected', v.wrongArtifactSetId)
              .having(
                (e) => e.actual,
                'actual',
                ManifestIdentity.embedded.artifactSetId,
              ),
        ),
      );
      expect(handler.liveRefCount, 0);
      expect(handler.observer, isNull, reason: 'no engine was built');
    },
    timeout: _timeout,
  );
}
