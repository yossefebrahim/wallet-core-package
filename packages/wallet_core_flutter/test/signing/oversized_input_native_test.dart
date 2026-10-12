/// An oversized signing input is the input's fault, never the session's
/// (D1-B C1, PRD §16 S5, TM-21): a key-less input that slips past a family's
/// request validation and makes the keyed input longer than one native buffer
/// may be fails with `InvalidInputError(signingInput)`; the session stays
/// `ready`, and every wallet in it stays usable.
///
/// The constructor's own cap on EVM calldata is tested in `requests_test.dart`.
/// These tests build the over-long key-less bytes directly, at the signing-core
/// seam, so they hold for any future family whose validation misses a length.
///
/// Skips when the library is absent; `WCF_NATIVE_REQUIRED=1` turns that into
/// a failure (see `../support/host_library.dart`).
@Tags(['native'])
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/advanced.dart';
import 'package:wallet_core_flutter/src/errors/errors.dart';
import 'package:wallet_core_flutter/src/families/evm/evm_family.dart';
import 'package:wallet_core_flutter/src/families/family.dart';
import 'package:wallet_core_flutter/src/requests/requests.dart';
import 'package:wallet_core_flutter/src/session/testing.dart';
import 'package:wallet_core_flutter/src/signing/key_locator.dart';
import 'package:wallet_core_flutter/src/signing/sign_result.dart';
import 'package:wallet_core_flutter/src/signing/signing_core.dart';
import 'package:wallet_core_flutter/src/worker/handler.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart'
    show Coin, SessionState;
// ignore: implementation_imports
import 'package:wallet_core_flutter_bindings/src/generated/proto/Ethereum.pb.dart'
    as eth;

import '../support/fixtures.dart';
import '../support/host_library.dart';
import 'signing_support.dart';

/// A well-formed, key-less `Ethereum.SigningInput` whose calldata is [data]
/// bytes long: what a family that forgot to bound a length would hand over.
Uint8List _keylessWithCalldata(String to, int data) => eth.SigningInput(
  chainId: <int>[1],
  nonce: <int>[0],
  gasLimit: <int>[0x52, 0x08],
  toAddress: to,
  txMode: eth.TransactionMode.Enveloped,
  maxInclusionFeePerGas: <int>[1],
  maxFeePerGas: <int>[2],
  transaction: eth.Transaction(
    contractGeneric: eth.Transaction_ContractGeneric(data: Uint8List(data)),
  ),
).writeToBuffer();

/// Key-less bytes within the native buffer ceiling by a few bytes, so that the
/// key field the signer puts in front of them — 34 bytes — is what tips the
/// keyed input over it.
Uint8List _nearCeilingKeyless(String to) {
  final base = _keylessWithCalldata(to, 0).length;
  final keyless = _keylessWithCalldata(to, maxNativeBufferBytes - base - 16);
  expect(keyless.length, lessThanOrEqualTo(maxNativeBufferBytes));
  expect(keyless.length + 34, greaterThan(maxNativeBufferBytes));
  return keyless;
}

/// Signs through [delegate], except that while [oversize] is set it replaces
/// the key-less input with [oversized] — as if the family had encoded it.
final class _OversizingCore implements SigningCore {
  _OversizingCore(this.delegate, this.oversized);

  final SigningCore delegate;
  final Uint8List oversized;
  bool oversize = false;

  @override
  S sign<S extends SignResult>(
    Uint8List keylessInput, {
    required TransactionFamily<TransactionRequest, S> family,
    required Coin coin,
    required Uint8List privateKey,
    required Set<KeyLocator> usedKeys,
  }) => delegate.sign(
    oversize ? oversized : keylessInput,
    family: family,
    coin: coin,
    privateKey: privateKey,
    usedKeys: usedKeys,
  );
}

void main() {
  final skip = hostLibrarySkipReason();

  group('an oversized signing input', skip: skip, () {
    late String mnemonic;
    late String path;
    late String to;

    setUpAll(() {
      final inventory = loadInventory();
      final account = vectorById(inventory, 'ethereum-address-n/a-1');
      mnemonic = (account.input as Map)['mnemonic'] as String;
      path = (account.input as Map)['derivation_path'] as String;
      to =
          (vectorById(inventory, 'ethereum-sign-eip1559-1').input
                  as Map)['to_address']
              as String;
    });

    test('is InvalidInputError(signingInput) at the signing core, before any '
        'native signing, with nothing left undisposed', () {
      final tracker = LeakTracker.maybeCreate()!;
      var nativeSignCalls = 0;
      final bindings = openHostBindings();
      final core = SyncSigningCore(
        NativeContext(bindings, observer: tracker),
        anySignerSign: (Pointer<Void> data, TWCoinType coin) {
          nativeSignCalls++;
          return bindings.TWAnySignerSign(data, coin);
        },
      );
      final keyless = _nearCeilingKeyless(to);
      final key = Uint8List(32)..fillRange(0, 32, 0x55);

      expect(
        () => core.sign(
          keyless,
          family: evmFamily,
          coin: Coin.ethereum,
          privateKey: key,
          usedKeys: const <KeyLocator>{},
        ),
        throwsA(
          isA<InvalidInputError>()
              .having((e) => e.inputName, 'inputName', 'signingInput')
              .having((e) => '$e', 'message', isNot(contains('55'))),
        ),
      );

      expect(nativeSignCalls, 0);
      expect(tracker.report.live, 0, reason: '${tracker.report}');
      expect(tracker.report.finalizedWithoutDispose, 0);
      expect(
        key.every((b) => b == 0x55),
        isTrue,
        reason: "the caller's key is untouched",
      );
      tracker.stop();
    });

    test('through the session: InvalidInputError(signingInput), the session '
        'stays ready, and a second wallet still signs', () async {
      late _OversizingCore oversizing;
      final core = await initializeForTesting(
        hostLibraryPath: findHostLibrary(),
        expectedIdentity: hostIdentity,
        handler: EngineRequestHandler(
          signingCore: (context) => oversizing = _OversizingCore(
            SyncSigningCore(context),
            _nearCeilingKeyless(to),
          ),
        ),
      );
      try {
        final first = await core.wallets.importMnemonic(mnemonic);
        final account = await first.account(Coin.ethereum, path: path);
        final firstLocator = KeyLocator.hdPath(
          first.ref,
          Coin.ethereum,
          account.derivationPath,
        );

        oversizing.oversize = true;
        await expectLater(
          core.signer.signWithKey(transferTo(to), firstLocator),
          throwsA(
            isA<InvalidInputError>().having(
              (e) => e.inputName,
              'inputName',
              'signingInput',
            ),
          ),
        );
        oversizing.oversize = false;

        expect(core.state, SessionState.ready);
        expect(first.isClosed, isFalse, reason: 'no wallet was released');

        // The first wallet and a second one are both still usable.
        expect((await first.account(Coin.ethereum)).address.value, isNotEmpty);
        final second = await core.wallets.importMnemonic(mnemonic);
        final secondAccount = await second.account(Coin.ethereum, path: path);
        final request = transferTo(to);
        final firstResult = await core.signer.signWithKey(
          request,
          firstLocator,
        );
        final secondResult = await core.signer.signWithKey(
          request,
          KeyLocator.hdPath(
            second.ref,
            Coin.ethereum,
            secondAccount.derivationPath,
          ),
        );
        expect(
          listEquals(
            (firstResult as EvmSignResult).encoded,
            (secondResult as EvmSignResult).encoded,
          ),
          isTrue,
          reason: 'same mnemonic and path, same request, same signature',
        );
        expect(core.state, SessionState.ready);

        final report = debugLeakReportOf(core)!;
        expect(report.finalizedWithoutDispose, 0, reason: '$report');
      } finally {
        await core.shutdown();
      }
      final after = debugLeakReportOf(core)!;
      expect(after.live, 0, reason: '$after');
    });
  });
}
