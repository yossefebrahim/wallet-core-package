/// THE TESTING SEAM. Every import of a `package:wallet_core_flutter/src/`
/// path in this example is in this one file, and only tests import it.
///
/// The app under `lib/` uses the public surface only (AGENTS.md rule 4). A
/// test has no public door to what it needs: `WalletCore.initialize()` takes
/// no library path and no request handler (threat model TM-13), and the
/// identity it checks is a placeholder until the first native release. So,
/// exactly as the SDK package's own tests do
/// (`packages/wallet_core_flutter/test/session/session_test.dart` with
/// `test/support/fake_handler.dart`, and `session_native_test.dart`), the
/// tests here start sessions through the SDK's internal entry point
/// `src/session/testing.dart` — over a fake request handler when there is no
/// native library, or over the host library a developer built.
///
/// Nothing here is an API a consumer should copy.
// ignore_for_file: implementation_imports
library;

import 'dart:typed_data';

import 'package:wallet_core_flutter/src/address/address.dart'
    show validatedAddress;
import 'package:wallet_core_flutter/src/session/testing.dart'
    show debugHandlerOf, debugLeakReportOf, initializeForTesting;
import 'package:wallet_core_flutter/src/worker/handler.dart'
    show RequestHandler;
import 'package:wallet_core_flutter/src/worker/protocol.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';
import 'package:wallet_core_flutter_native/wallet_core_flutter_native.dart'
    show ManifestIdentity;

/// The mnemonic [FakeHandler] exports, and the only text it calls a valid
/// mnemonic: the BIP-39 English reference mnemonic for 128 bits of zero
/// entropy (BIP-39 test vectors, trezor/python-mnemonic `vectors.json`, first
/// `english` entry). A fake's answer, not a vector this repository asserts.
const String fakeMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon about';

/// A session over a [FakeHandler]: the SDK's real session, queue, deadlines,
/// proxies, and in-process executor — no native library.
Future<WalletCore> startFakeSession() =>
    initializeForTesting(handler: FakeHandler());

/// The identity of the host library `tools/native_build/build_apple.sh`
/// builds at the pinned upstream commit, artifact set `as_4.8.0_000` — the
/// same value the SDK's `test/session/session_native_test.dart` uses.
const ManifestIdentity hostLibraryIdentity = ManifestIdentity(
  artifactSetId: 'as_4.8.0_000',
  upstreamCommit: 'd692ac27749d0c615e17c751b70ab4f0aa75c59b',
);

/// A session over the real host library at [libraryPath].
Future<WalletCore> startHostSession(String libraryPath) => initializeForTesting(
  hostLibraryPath: libraryPath,
  expectedIdentity: hostLibraryIdentity,
);

/// How many wallets the executor behind [core] still holds.
int liveWalletCount(WalletCore core) => debugHandlerOf(core).liveRefCount;

/// The leak tracker's counts for [core]'s native handles, or `null` when
/// there is no tracker (a fake handler, or a release build). The report the
/// app cannot show: it is not on the public surface.
({int live, int finalizedWithoutDispose})? leakCounts(WalletCore core) {
  final report = debugLeakReportOf(core);
  if (report == null) return null;
  return (
    live: report.live,
    finalizedWithoutDispose: report.finalizedWithoutDispose,
  );
}

/// A [RequestHandler] with no native library behind it: plausible, fixed
/// answers for every request the M0 flow sends.
final class FakeHandler implements RequestHandler {
  static const Set<String> _words = {'abandon', 'about'};

  final Set<int> _live = <int>{};
  int _nextRef = 1;

  @override
  int get liveRefCount => _live.length;

  @override
  WorkerReply handle(WorkerRequest request) => switch (request) {
    Init(:final id) => InitOk(id, symbolCount: 1),
    CreateWallet(:final id) || ImportWallet(:final id) => _create(id),
    ExportMnemonic(:final id, :final walletRef) =>
      _live.contains(walletRef)
          ? MnemonicExported(id, fakeMnemonic)
          : Failed(id, const ClosedError('Wallet')),
    DeriveAddress(:final id, :final walletRef) =>
      _live.contains(walletRef)
          ? AddressDerived(id, _account(request, walletRef))
          : Failed(id, const ClosedError('Wallet')),
    ValidateAddress(:final id, :final value) => AddressValidated(
      id,
      isValid: RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(value),
    ),
    ValidateMnemonic(:final id, :final mnemonic) => MnemonicValidated(
      id,
      isValid: mnemonic.trim().split(RegExp(r'\s+')).join(' ') == fakeMnemonic,
    ),
    ValidateMnemonicWord(:final id, :final word) => MnemonicWordValidated(
      id,
      isValid: _words.contains(word),
    ),
    SuggestMnemonicWords(:final id, :final prefix) => MnemonicWordsSuggested(
      id,
      [
        for (final word in _words)
          if (word.startsWith(prefix)) word,
      ],
    ),
    Sign(:final id, :final request) => Signed(
      id,
      EvmSignResult(
        coin: request.coin,
        encoded: Uint8List.fromList([0x02, 0xf8, 0x01, 0x02]),
        v: Uint8List.fromList([0x01]),
        r: Uint8List(32)..fillRange(0, 32, 0x11),
        s: Uint8List(32)..fillRange(0, 32, 0x22),
        usedKeys: const <KeyLocator>{},
      ),
    ),
    DisposeRef(:final id, :final walletRef) => _dispose(id, walletRef),
    Cancel(:final id, :final target) => NotCancellable(id, target: target),
    Shutdown(:final id) => _shutdown(id),
  };

  @override
  void discard(WorkerReply reply) {
    if (reply is WalletCreated) _live.remove(reply.walletRef);
  }

  @override
  int releaseAll() {
    final count = _live.length;
    _live.clear();
    return count;
  }

  WorkerReply _create(int id) {
    final ref = _nextRef++;
    _live.add(ref);
    return WalletCreated(id, walletRef: ref);
  }

  /// `0xabab…ab` and the wallet reference, as 40 hex digits.
  Account _account(DeriveAddress request, int walletRef) => Account(
    coin: request.coin,
    network: request.network,
    addressStyle: request.style,
    derivationPath: request.path ?? "m/44'/60'/0'/0/0",
    address: validatedAddress(
      '0x${'ab' * 19}${walletRef.toRadixString(16).padLeft(2, '0')}',
      request.coin,
      request.network,
    ),
    publicKey: Uint8List(65)..[0] = 0x04,
  );

  WorkerReply _dispose(int id, int walletRef) {
    _live.remove(walletRef);
    return Disposed(id, walletRef: walletRef);
  }

  WorkerReply _shutdown(int id) {
    final count = _live.length;
    _live.clear();
    return ShutdownComplete(id, disposedCount: count);
  }
}
