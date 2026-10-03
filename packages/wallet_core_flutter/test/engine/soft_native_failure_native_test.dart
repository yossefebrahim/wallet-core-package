/// DECISION-12 §3.10 against the real host library: a soft native failure —
/// an upstream function returning null, or a size out of range — during an
/// operation is a typed error of that one operation, and the session stays
/// `ready`. Driven by replacing single upstream functions with Dart callbacks
/// that fail on demand (`EngineRequestHandler(bindings: ...)`).
///
/// Skips when the library is absent; `WCF_NATIVE_REQUIRED=1` turns that into
/// a failure (see `../support/host_library.dart`).
@Tags(['native'])
library;

import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/advanced.dart' show WalletCoreBindings;
import 'package:wallet_core_flutter/src/session/testing.dart';
import 'package:wallet_core_flutter/src/worker/handler.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';

import '../signing/signing_support.dart';
import '../support/fixtures.dart';
import '../support/host_library.dart';

/// The real functions, for the callbacks to delegate to.
late WalletCoreBindings _real;

/// Which failure the callbacks produce right now.
bool _privateKeyDataNull = false;
bool _mnemonicNull = false;
bool _dataSizeCorrupt = false;

Pointer<Void> _privateKeyData(Pointer<Void> key) =>
    _privateKeyDataNull ? nullptr : _real.TWPrivateKeyData(key.cast());

Pointer<Void> _mnemonic(Pointer<Void> wallet) =>
    _mnemonicNull ? nullptr : _real.TWHDWalletMnemonic(wallet.cast()).cast();

/// Far beyond any bound the SDK accepts.
int _dataSize(Pointer<Void> data) =>
    _dataSizeCorrupt ? 1 << 40 : _real.TWDataSize(data);

WalletCoreBindings _faulty(DynamicLibrary library) {
  _real = WalletCoreBindings(library);
  final replaced = <String, Pointer<NativeType>>{
    'TWPrivateKeyData':
        Pointer.fromFunction<Pointer<Void> Function(Pointer<Void>)>(
          _privateKeyData,
        ),
    'TWHDWalletMnemonic':
        Pointer.fromFunction<Pointer<Void> Function(Pointer<Void>)>(_mnemonic),
    'TWDataSize': Pointer.fromFunction<Size Function(Pointer<Void>)>(
      _dataSize,
      0,
    ),
  };
  return WalletCoreBindings.fromLookup(
    <T extends NativeType>(String name) =>
        (replaced[name] ?? library.lookup<T>(name)).cast<T>(),
  );
}

void main() {
  final skip = hostLibrarySkipReason();

  group('a soft native failure during an operation', skip: skip, () {
    late String mnemonic;
    late String path;
    late String to;
    late WalletCore core;

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

    setUp(() async {
      _privateKeyDataNull = false;
      _mnemonicNull = false;
      _dataSizeCorrupt = false;
      core = await initializeForTesting(
        hostLibraryPath: findHostLibrary(),
        expectedIdentity: hostIdentity,
        handler: EngineRequestHandler(bindings: _faulty),
      );
    });

    tearDown(() async {
      _privateKeyDataNull = false;
      _mnemonicNull = false;
      _dataSizeCorrupt = false;
      await core.shutdown();
      final report = debugLeakReportOf(core)!;
      expect(report.live, 0, reason: '$report');
      expect(report.finalizedWithoutDispose, 0, reason: '$report');
    });

    Matcher unusable(Matcher type) => allOf(
      type,
      isA<WalletCoreException>().having(
        (e) => e.message,
        'message',
        contains('upstream returned an unusable result'),
      ),
    );

    test('TWPrivateKeyData returning null while signing is SigningError, the '
        'key is still released, and the session stays ready', () async {
      final wallet = await core.wallets.importMnemonic(mnemonic);
      final locator = KeyLocator.hdPath(wallet.ref, Coin.ethereum, path);
      _privateKeyDataNull = true;
      await expectLater(
        core.signer.sign(transferTo(to), {locator}),
        throwsA(
          unusable(
            isA<SigningError>().having(
              (e) => e.upstreamCode,
              'code',
              SigningError.malformedOutputCode,
            ),
          ),
        ),
      );
      _privateKeyDataNull = false;
      expect(core.state, SessionState.ready);
      expect(debugLeakReportOf(core)!.liveByType, {
        'HDWallet': 1,
      }, reason: 'the derived key was released on the failure path');
      expect(
        await core.signer.sign(transferTo(to), {locator}),
        isA<EvmSignResult>(),
      );
      await wallet.close();
    });

    test('a corrupt TWDataSize while deriving is InvalidInputError, and the '
        'session stays ready', () async {
      final wallet = await core.wallets.importMnemonic(mnemonic);
      _dataSizeCorrupt = true;
      await expectLater(
        wallet.account(Coin.ethereum, path: path),
        throwsA(
          unusable(
            isA<InvalidInputError>().having(
              (e) => e.inputName,
              'input',
              'derivationPath',
            ),
          ),
        ),
      );
      _dataSizeCorrupt = false;
      expect(core.state, SessionState.ready);
      expect(
        (await wallet.account(Coin.ethereum, path: path)).derivationPath,
        path,
      );
      await wallet.close();
    });

    test('TWHDWalletMnemonic returning null is InvalidInputError(wallet), '
        'and the session stays ready', () async {
      final wallet = await core.wallets.importMnemonic(mnemonic);
      _mnemonicNull = true;
      await expectLater(
        wallet.exportMnemonic(),
        throwsA(
          unusable(
            isA<InvalidInputError>().having(
              (e) => e.inputName,
              'input',
              'wallet',
            ),
          ),
        ),
      );
      _mnemonicNull = false;
      expect(core.state, SessionState.ready);
      expect(await wallet.exportMnemonic(), mnemonic);
      await wallet.close();
    });
  });
}
