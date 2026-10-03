/// A [RequestHandler] with no native library behind it, for the protocol,
/// loop, and session tests: it answers every request with a plausible reply,
/// records what it handled, and can be told to block or to fail.
library;

import 'dart:io' show sleep;
import 'dart:typed_data';

import 'package:wallet_core_flutter/src/address/address.dart';
import 'package:wallet_core_flutter/src/worker/handler.dart';
import 'package:wallet_core_flutter/src/worker/protocol.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';

/// A stand-in for the engine-backed handler.
final class FakeHandler implements RequestHandler {
  /// Every request handled, in order.
  final List<WorkerRequest> handled = <WorkerRequest>[];

  /// Blocks the isolate this long while handling a request of the given
  /// operation name — what a slow native call does to the M0 executor.
  final Map<String, Duration> blockFor = <String, Duration>{};

  /// Throws this, unmapped, while handling a request of the given operation.
  final Map<String, Object> throwOn = <String, Object>{};

  /// Answers `Init` with this error instead of `InitOk`.
  WalletCoreException? initError;

  final Set<int> _live = <int>{};
  int _nextRef = 1;

  /// How many times [releaseAll] ran.
  int releaseAllCalls = 0;

  /// Every reply the loop dropped past its deadline, by type name.
  final List<String> discarded = <String>[];

  /// A copy of each `ImportWallet.entropy` as it was when handled — before
  /// the executor overwrote its copy.
  final List<Uint8List> entropySeen = <Uint8List>[];

  /// The operation names of [handled], in order.
  List<String> get operations => [for (final r in handled) r.operation];

  /// The `DisposeRef`s handled, by wallet reference.
  List<int> get disposedRefs => [
    for (final r in handled)
      if (r is DisposeRef) r.walletRef,
  ];

  @override
  int get liveRefCount => _live.length;

  @override
  WorkerReply handle(WorkerRequest request) {
    handled.add(request);
    if (request case ImportWallet(:final entropy?)) {
      entropySeen.add(Uint8List.fromList(entropy));
    }
    final block = blockFor[request.operation];
    if (block != null) sleep(block);
    final failure = throwOn[request.operation];
    if (failure != null) throw failure;
    return switch (request) {
      Init(:final id) =>
        initError == null ? InitOk(id, symbolCount: 1) : Failed(id, initError!),
      CreateWallet(:final id) || ImportWallet(:final id) => _create(id),
      ExportMnemonic(:final id, :final walletRef) =>
        _live.contains(walletRef)
            ? MnemonicExported(id, 'fake mnemonic for $walletRef')
            : Failed(id, const ClosedError('Wallet')),
      DeriveAddress(:final id, :final walletRef, :final coin, :final network) =>
        _live.contains(walletRef)
            ? AddressDerived(
                id,
                Account(
                  coin: coin,
                  network: network,
                  addressStyle: request.style,
                  derivationPath: request.path ?? "m/44'/60'/0'/0/0",
                  address: validatedAddress('0xfake$walletRef', coin, network),
                  publicKey: Uint8List(33),
                ),
              )
            : Failed(id, const ClosedError('Wallet')),
      ValidateAddress(:final id, :final value) => AddressValidated(
        id,
        isValid: value.startsWith('0x'),
      ),
      ValidateMnemonic(:final id) => MnemonicValidated(id, isValid: true),
      ValidateMnemonicWord(:final id) => MnemonicWordValidated(
        id,
        isValid: true,
      ),
      SuggestMnemonicWords(:final id, :final prefix) => MnemonicWordsSuggested(
        id,
        ['${prefix}one', '${prefix}two'],
      ),
      Sign(:final id, :final request) => Signed(
        id,
        EvmSignResult(
          coin: request.coin,
          encoded: Uint8List.fromList([0x02, id]),
          v: Uint8List(1),
          r: Uint8List(32),
          s: Uint8List(32),
          usedKeys: const <KeyLocator>{},
        ),
      ),
      DisposeRef(:final id, :final walletRef) => _dispose(id, walletRef),
      Cancel(:final id, :final target) => NotCancellable(id, target: target),
      Shutdown(:final id) => _shutdown(id),
    };
  }

  @override
  void discard(WorkerReply reply) {
    discarded.add(reply.runtimeType.toString());
    if (reply is WalletCreated) _live.remove(reply.walletRef);
  }

  WorkerReply _create(int id) {
    final ref = _nextRef++;
    _live.add(ref);
    return WalletCreated(id, walletRef: ref);
  }

  WorkerReply _dispose(int id, int ref) {
    _live.remove(ref);
    return Disposed(id, walletRef: ref);
  }

  WorkerReply _shutdown(int id) {
    final count = _live.length;
    _live.clear();
    return ShutdownComplete(id, disposedCount: count);
  }

  @override
  int releaseAll() {
    releaseAllCalls++;
    final count = _live.length;
    _live.clear();
    return count;
  }
}
