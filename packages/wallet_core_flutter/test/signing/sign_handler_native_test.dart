/// The executor's signing path against the real host library, driven at the
/// handler with a recording signing core: every resolution and validation
/// failure is typed, and none of them derives a key or reaches the core; a
/// valid request derives exactly one key, hands the core its live handle,
/// disposes it before the reply, and leaves nothing undisposed.
///
/// Skips when the library is absent; `WCF_NATIVE_REQUIRED=1` turns that into
/// a failure (see `../support/host_library.dart`).
@Tags(['native'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/advanced.dart' show LeakTracker;
import 'package:wallet_core_flutter/src/signing/signing_core.dart';
import 'package:wallet_core_flutter/src/worker/handler.dart';
import 'package:wallet_core_flutter/src/worker/protocol.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';

import '../support/fixtures.dart';
import '../support/host_library.dart';
import 'signing_support.dart';

const int _token = 7;

void main() {
  final skip = hostLibrarySkipReason();

  group('EngineRequestHandler signing', skip: skip, () {
    late Map<dynamic, dynamic> account;
    late String to;

    late EngineRequestHandler handler;
    late RecordingCore core;
    late int walletRef;
    var nextId = 1;

    setUpAll(() {
      final inventory = loadInventory();
      account = vectorById(inventory, 'ethereum-address-n/a-1').input as Map;
      to =
          (vectorById(inventory, 'ethereum-sign-eip1559-1').input
                  as Map)['to_address']
              as String;
    });

    WorkerReply handle(WorkerRequest Function(int id) build) =>
        handler.handle(build(nextId++));

    setUp(() {
      handler = EngineRequestHandler(
        signingCore: (context, _) =>
            core = RecordingCore(SyncSigningCore(context)),
      );
      expect(
        handle(
          (id) => Init(
            id,
            queueLimit: 4,
            hostLibraryPath: findHostLibrary(),
            expectedIdentity: hostIdentity,
            sessionToken: _token,
          ),
        ),
        isA<InitOk>(),
      );
      final created = handle(
        (id) => ImportWallet.mnemonic(id, account['mnemonic'] as String),
      );
      walletRef = (created as WalletCreated).walletRef;
    });

    tearDown(() {
      handle((id) => Shutdown(id, grace: const Duration(seconds: 1)));
      final tracker = handler.observer! as LeakTracker;
      final report = tracker.report;
      expect(report.live, 0, reason: '$report');
      expect(report.finalizedWithoutDispose, 0, reason: '$report');
    });

    HdLocatorSpec hd({
      int? token,
      int? ref,
      Coin? coin,
      String? path,
      KeyRole? role,
    }) => HdLocatorSpec(
      sessionToken: token ?? _token,
      walletRef: ref ?? walletRef,
      coin: coin ?? Coin.ethereum,
      derivationPath: path ?? account['derivation_path'] as String,
      role: role,
    );

    WorkerReply sign(Set<LocatorSpec> keys, {String? recipient}) => handle(
      (id) => Sign(id, request: transferTo(recipient ?? to), keys: keys),
    );

    /// Asserts [reply] failed with an error [matcher] accepts, that no key
    /// was derived, and that the core was never called.
    void expectRejectedBeforeDerivation(WorkerReply reply, Matcher matcher) {
      expect(reply, isA<Failed>().having((r) => r.error, 'error', matcher));
      expect(handler.keysDerived, 0, reason: 'no key may be derived');
      expect(core.calls, 0, reason: 'the core may not be called');
    }

    Matcher resolution(KeyResolutionReason reason) =>
        isA<KeyResolutionError>().having((e) => e.reason, 'reason', reason);

    Matcher invalid(String inputName) =>
        isA<InvalidInputError>().having((e) => e.inputName, 'input', inputName);

    test('a valid request derives one key, hands the core its live handle, '
        'and returns the parsed result with no locators on the wire', () {
      final reply = sign({hd()});
      expect(reply, isA<Signed>());
      final result = (reply as Signed).result as EvmSignResult;
      expect(result.coin, Coin.ethereum);
      expect(result.encoded.first, 0x02, reason: 'an EIP-1559 envelope');
      expect(result.usedKeys, isEmpty);
      expect(handler.keysDerived, 1);
      expect(core.calls, 1);
      expect(core.lastKeyWasLive, isTrue);
      expect(core.lastKey!.isDisposed, isTrue, reason: 'released before reply');
      expect(core.lastCoin, Coin.ethereum);
      // Only the wallet is left: the key, its bytes, the keyed input, the
      // output and every string were released before the reply was made.
      final report = (handler.observer! as LeakTracker).report;
      expect(report.live, 1, reason: '$report');
      expect(report.liveByType, {'HDWallet': 1});
    });

    test('duplicate-equal locators are one locator', () {
      expect(sign({hd(), hd()}), isA<Signed>());
      expect(handler.keysDerived, 1);
    });

    test('an explicit primary role is the same slot', () {
      expect(sign({hd(role: KeyRole.primary)}), isA<Signed>());
    });

    test('an empty set is missingRole', () {
      expectRejectedBeforeDerivation(
        sign(const <LocatorSpec>{}),
        resolution(KeyResolutionReason.missingRole),
      );
    });

    test('a role the family does not use is unusedLocator', () {
      expectRejectedBeforeDerivation(
        sign({hd(role: KeyRole.feePayer)}),
        resolution(KeyResolutionReason.unusedLocator),
      );
    });

    test('two locators for one slot are unusedLocator', () {
      expectRejectedBeforeDerivation(
        sign({hd(), hd(path: "m/44'/60'/0'/0/2")}),
        resolution(KeyResolutionReason.unusedLocator),
      );
    });

    test('a locator from another session is foreignRef, even when its number '
        'names a wallet here', () {
      expectRejectedBeforeDerivation(
        sign({hd(token: _token + 1)}),
        resolution(KeyResolutionReason.foreignRef),
      );
    });

    test('an imported-key locator is noKeyForAccount: no import exists', () {
      expectRejectedBeforeDerivation(
        sign({const ImportedLocatorSpec(keyRef: 1)}),
        resolution(KeyResolutionReason.noKeyForAccount),
      );
    });

    test('an external locator is UnsupportedOperationError(external-signer), '
        'whatever else is in the set', () {
      expectRejectedBeforeDerivation(
        sign({hd(), const ExternalLocatorSpec(deviceId: 'ledger-1')}),
        isA<UnsupportedOperationError>()
            .having((e) => e.capability, 'capability', 'external-signer')
            .having((e) => e.coin, 'coin', Coin.ethereum),
      );
    });

    test('a locator for another coin is InvalidInputError(keys)', () {
      expectRejectedBeforeDerivation(
        sign({hd(coin: Coin.bitcoin)}),
        invalid('keys'),
      );
      expectRejectedBeforeDerivation(
        sign({hd(coin: Coin.byId('polygon'))}),
        invalid('keys'),
      );
    });

    test('a wallet reference never issued is InvalidInputError(wallet); a '
        'released one is ClosedError', () {
      expectRejectedBeforeDerivation(sign({hd(ref: 99)}), invalid('wallet'));
      handle((id) => DisposeRef(id, walletRef: walletRef));
      expectRejectedBeforeDerivation(
        sign({hd()}),
        isA<ClosedError>().having((e) => e.resourceType, 'type', 'Wallet'),
      );
    });

    test('a malformed path is InvalidInputError(derivationPath)', () {
      for (final path in ['m/44h/60', "m/44'/60'/x", '', "44'/60'/0'"]) {
        expectRejectedBeforeDerivation(
          sign({hd(path: path)}),
          invalid('derivationPath'),
        );
      }
    });

    test(
      'a recipient whose EIP-55 checksum fails is InvalidInputError(to)',
      () {
        final broken = breakChecksum(to);
        final reply = sign({hd()}, recipient: broken);
        // Upstream's own validity check accepts it; the checksum comparison
        // is what rejects it.
        expectRejectedBeforeDerivation(
          reply,
          allOf(
            invalid('to'),
            isA<InvalidInputError>().having(
              (e) => e.message,
              'message',
              contains('EIP-55'),
            ),
          ),
        );
        expectRedacted((reply as Failed).error, [broken]);
      },
    );

    test('a recipient in one case asserts no checksum and is accepted', () {
      expect(sign({hd()}, recipient: to.toLowerCase()), isA<Signed>());
      expect(
        sign({hd()}, recipient: '0x${to.substring(2).toUpperCase()}'),
        isA<Signed>(),
      );
      expect(handler.keysDerived, 2);
    });

    test('Sign after Shutdown is ClosedError, and derives nothing', () {
      handle((id) => Shutdown(id, grace: const Duration(seconds: 1)));
      expectRejectedBeforeDerivation(sign({hd()}), isA<ClosedError>());
    });
  });
}
