/// The M0 signing flow through the public API with the Approach B core
/// injected (T1.13, DECISION-1 evaluation): `initialize` by the internal test
/// entry point with an `EngineRequestHandler` whose factory is
/// `AdapterSigningCore.new`, then import, derive, build a request,
/// `signer.sign`. The result must equal Approach A's — a second session over
/// the same library with the default handler — for the same request; 50 signs
/// in a loop must leave nothing but the wallet live; and nothing may be left
/// undisposed after shutdown.
///
/// Skips when the shim library is absent (see `shim_library.dart`);
/// `WCF_NATIVE_SHIM_REQUIRED=1` turns that into a failure.
@Tags(['native', 'shim'])
library;

import 'dart:ffi';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/advanced.dart' show WalletCoreBindings;
import 'package:wallet_core_flutter/src/session/testing.dart';
import 'package:wallet_core_flutter/src/signing/adapter/adapter_signing_core.dart';
import 'package:wallet_core_flutter/src/worker/handler.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';

import '../../support/fixtures.dart';
import '../../support/host_library.dart' show findHostLibrary;
import '../signing_support.dart';
import 'shim_library.dart';

/// The real functions, for [_createWithBytes] to delegate to.
late WalletCoreBindings _real;

/// Whether the next `TWDataCreateWithBytes` made through the bindings returns
/// null. One-shot: the callback clears it.
bool _createWithBytesFailsNext = false;

Pointer<Void> _createWithBytes(Pointer<Uint8> bytes, int size) {
  if (_createWithBytesFailsNext) {
    _createWithBytesFailsNext = false;
    return nullptr;
  }
  return _real.TWDataCreateWithBytes(bytes, size);
}

/// The library's bindings with `TWDataCreateWithBytes` replaced by
/// [_createWithBytes]; every other symbol — `TWDataDelete`, which the
/// adapter's same-image check compares, included — is the library's own.
WalletCoreBindings _faulty(DynamicLibrary library) {
  _real = WalletCoreBindings(library);
  final replaced = <String, Pointer<NativeType>>{
    'TWDataCreateWithBytes':
        Pointer.fromFunction<Pointer<Void> Function(Pointer<Uint8>, Size)>(
          _createWithBytes,
        ),
  };
  return WalletCoreBindings.fromLookup(
    <T extends NativeType>(String name) =>
        (replaced[name] ?? library.lookup<T>(name)).cast<T>(),
  );
}

void main() {
  final skip = shimLibrarySkipReason();

  group('WalletCore.signer with the adapter core', skip: skip, () {
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

    late EngineRequestHandler handler;
    late WalletCore core;

    setUp(() async {
      handler = EngineRequestHandler(signingCore: AdapterSigningCore.new);
      core = await initializeForTesting(
        hostLibraryPath: findShimLibrary(),
        expectedIdentity: shimIdentity,
        handler: handler,
      );
    });

    tearDown(() async {
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

    /// [request] signed by a second session with the default handler —
    /// Approach A — and the same wallet and path: over the **standard**
    /// library when it is present (the artifact Approach A ships in), else
    /// over the shim library, which contains every upstream symbol too.
    Future<EvmSignResult> signWithApproachA(
      EvmTransactionRequest request,
    ) async {
      final standard = findHostLibrary();
      final reference = await initializeForTesting(
        hostLibraryPath: standard ?? findShimLibrary(),
        expectedIdentity: standard != null ? hostIdentity : shimIdentity,
      );
      try {
        final wallet = await reference.wallets.importMnemonic(mnemonic);
        final result = await reference.signer.sign(request, {
          KeyLocator.hdPath(wallet.ref, Coin.ethereum, path),
        });
        await wallet.close();
        return result as EvmSignResult;
      } finally {
        await reference.shutdown();
        expect(debugLeakReportOf(reference)!.live, 0);
      }
    }

    test('import → derive → request → sign equals Approach A for the same '
        'request', () async {
      final wallet = await core.wallets.importMnemonic(mnemonic);
      final account = await wallet.account(Coin.ethereum, path: path);
      final locator = KeyLocator.hdPath(
        wallet.ref,
        Coin.ethereum,
        account.derivationPath,
      );
      final request = transferTo(to);
      final result = await core.signer.sign(request, {locator});

      expect(result, isA<EvmSignResult>());
      final viaB = result as EvmSignResult;
      final viaA = await signWithApproachA(request);
      expect(listEquals(viaB.encoded, viaA.encoded), isTrue);
      expect(listEquals(viaB.v, viaA.v), isTrue);
      expect(listEquals(viaB.r, viaA.r), isTrue);
      expect(listEquals(viaB.s, viaA.s), isTrue);
      expect(viaB.coin, Coin.ethereum);
      expect(viaB.usedKeys, {locator});
      expect(handler.keysDerived, 1);

      await wallet.close();
      expectNothingLive();
    });

    test('50 signs in a loop leave zero undisposed', () async {
      final wallet = await core.wallets.importMnemonic(mnemonic);
      final locator = KeyLocator.hdPath(wallet.ref, Coin.ethereum, path);
      final encodings = <String>{};
      for (var nonce = 0; nonce < 50; nonce++) {
        final result =
            await core.signer.sign(transferTo(to, nonce: nonce), {locator})
                as EvmSignResult;
        encodings.add(result.encoded.join(','));
        final report = debugLeakReportOf(core)!;
        expect(report.live, 1, reason: 'the wallet only: $report');
        expect(report.finalizedWithoutDispose, 0, reason: '$report');
      }
      expect(encodings, hasLength(50));
      expect(handler.keysDerived, 50);
      await wallet.close();
      expectNothingLive();
    });
  });

  group('the shim library and the session', skip: skip, () {
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

    test('is refused where the standard identity is expected', () async {
      await expectLater(
        initializeForTesting(
          hostLibraryPath: findShimLibrary(),
          expectedIdentity: hostIdentity,
          handler: EngineRequestHandler(signingCore: AdapterSigningCore.new),
        ),
        throwsA(
          isA<ManifestMismatchError>()
              .having(
                (e) => e.check,
                'check',
                ManifestCheck.artifactSetMismatch,
              )
              .having((e) => e.expected, 'expected', 'as_4.8.0_000')
              .having((e) => e.actual, 'actual', 'as_4.8.0-shim_000'),
        ),
      );
    });

    test('an adapter returning NULL is the one operation\'s SigningError: '
        'the key is released and the session stays ready', () async {
      var failNext = true;
      late EngineRequestHandler handler;
      handler = EngineRequestHandler(
        signingCore: (context, library) {
          final real = AdapterSigningCore.bindAdapter(context, library);
          return AdapterSigningCore(
            context,
            library,
            adapterSign: (keyless, key, coin) {
              if (failNext) {
                failNext = false;
                return nullptr;
              }
              return real(keyless, key, coin);
            },
          );
        },
      );
      final core = await initializeForTesting(
        hostLibraryPath: findShimLibrary(),
        expectedIdentity: shimIdentity,
        handler: handler,
      );
      try {
        final wallet = await core.wallets.importMnemonic(mnemonic);
        final locator = KeyLocator.hdPath(wallet.ref, Coin.ethereum, path);
        await expectLater(
          core.signer.sign(transferTo(to), {locator}),
          throwsA(
            isA<SigningError>().having(
              (e) => e.upstreamCode,
              'upstreamCode',
              SigningError.malformedOutputCode,
            ),
          ),
        );
        final report = debugLeakReportOf(core)!;
        expect(report.live, 1, reason: 'the wallet only: $report');
        // Still ready: the next sign goes through the real adapter.
        final result = await core.signer.sign(transferTo(to), {locator});
        expect(result, isA<EvmSignResult>());
        expect(handler.keysDerived, 2);
        await wallet.close();
      } finally {
        await core.shutdown();
      }
      final after = debugLeakReportOf(core)!;
      expect(after.live, 0, reason: '$after');
      expect(after.finalizedWithoutDispose, 0, reason: '$after');
    });

    test('TWDataCreateWithBytes returning null while signing is the one '
        'operation\'s SigningError, as under Approach A: the key is released '
        'and the session stays ready', () async {
      _createWithBytesFailsNext = false;
      final handler = EngineRequestHandler(
        signingCore: AdapterSigningCore.new,
        bindings: _faulty,
      );
      final core = await initializeForTesting(
        hostLibraryPath: findShimLibrary(),
        expectedIdentity: shimIdentity,
        handler: handler,
      );
      try {
        final wallet = await core.wallets.importMnemonic(mnemonic);
        final locator = KeyLocator.hdPath(wallet.ref, Coin.ethereum, path);
        _createWithBytesFailsNext = true;
        await expectLater(
          core.signer.sign(transferTo(to), {locator}),
          throwsA(
            isA<SigningError>()
                .having(
                  (e) => e.upstreamCode,
                  'upstreamCode',
                  SigningError.malformedOutputCode,
                )
                .having(
                  (e) => e.message,
                  'message',
                  contains('TWDataCreateWithBytes returned nullptr'),
                ),
          ),
        );
        expect(
          _createWithBytesFailsNext,
          isFalse,
          reason: 'the failure was injected during the sign',
        );
        expect(core.state, SessionState.ready);
        final report = debugLeakReportOf(core)!;
        expect(report.live, 1, reason: 'the wallet only: $report');
        // Still ready: the next sign goes through.
        final result = await core.signer.sign(transferTo(to), {locator});
        expect(result, isA<EvmSignResult>());
        expect(handler.keysDerived, 2);
        await wallet.close();
      } finally {
        _createWithBytesFailsNext = false;
        await core.shutdown();
      }
      final after = debugLeakReportOf(core)!;
      expect(after.live, 0, reason: '$after');
      expect(after.finalizedWithoutDispose, 0, reason: '$after');
    });
  });
}
