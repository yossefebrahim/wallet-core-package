// The executor's loop over a fake handler: ordering, asynchrony, cancel,
// shutdown, the control-path bounds, and the fault rule (DECISION-12 §3.4,
// §3.6–§3.10). No library needed.
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/src/worker/protocol.dart';
import 'package:wallet_core_flutter/src/worker/worker_loop.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';

import '../support/fake_handler.dart';

/// Lets the loop drain: each request takes a timer turn.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late FakeHandler handler;
  late List<WorkerReply> replies;
  late List<WorkerTerminatedError> faults;
  late WorkerLoop loop;

  setUp(() {
    handler = FakeHandler();
    replies = <WorkerReply>[];
    faults = <WorkerTerminatedError>[];
    loop = WorkerLoop(handler, post: replies.add, onFault: faults.add);
    loop.receive(Init(1, queueLimit: 4));
  });

  test('nothing is handled inside receive; each request in a later turn, '
      'in arrival order, one reply each', () async {
    loop.receive(const CreateWallet(2, strength: 128));
    loop.receive(const ExportMnemonic(3, walletRef: 1));
    expect(handler.handled, isEmpty);
    expect(replies, isEmpty);
    await _settle();
    expect(handler.operations, [
      'initialize',
      'createWallet',
      'exportMnemonic',
    ]);
    expect([for (final r in replies) r.id], [1, 2, 3]);
    expect(replies[0], isA<InitOk>());
    expect(replies[1], isA<WalletCreated>());
    expect(replies[2], isA<MnemonicExported>());
  });

  test('DisposeRef queues behind work already queued on the wallet', () async {
    loop.receive(const CreateWallet(2, strength: 128));
    await _settle();
    loop.receive(
      DeriveAddress(
        3,
        walletRef: 1,
        coin: Coin.ethereum,
        network: Network.mainnet,
        style: AddressStyle.standard,
      ),
    );
    loop.receive(const DisposeRef(4, walletRef: 1));
    await _settle();
    expect(replies.skip(2).map((r) => r.runtimeType), [
      AddressDerived,
      Disposed,
    ]);
  });

  group('Cancel (§3.6)', () {
    test('a queued target is withdrawn and never runs', () async {
      await _settle();
      loop.receive(const CreateWallet(2, strength: 128));
      loop.receive(const Cancel(3, target: 2));
      await _settle();
      expect(handler.operations, ['initialize']);
      final target = replies.whereType<Failed>().single;
      expect(target.id, 2);
      expect(
        target.error,
        isA<OperationCancelledError>().having((e) => e.requestId, 'id', 2),
      );
      expect(
        replies.whereType<Cancelled>().single,
        isA<Cancelled>().having((r) => r.target, 'target', 2),
      );
    });

    test('an unknown or finished target is NotCancellable and nothing is '
        'queued', () async {
      await _settle();
      loop.receive(const Cancel(2, target: 99));
      loop.receive(const Cancel(3, target: 1));
      expect(loop.queuedCount, 0);
      expect(replies.whereType<NotCancellable>().map((r) => r.target), [99, 1]);
    });
  });

  group('DisposeRef (§3.4 rule 1, §3.7)', () {
    test('a repeat for the same reference is folded into the pending one and '
        'answered with it', () async {
      loop.receive(const CreateWallet(2, strength: 128));
      await _settle();
      loop.receive(const DisposeRef(3, walletRef: 1));
      loop.receive(const DisposeRef(4, walletRef: 1));
      loop.receive(const DisposeRef(5, walletRef: 1));
      expect(loop.queuedCount, 1);
      await _settle();
      expect(handler.disposedRefs, [1]);
      expect(replies.whereType<Disposed>().map((r) => (r.id, r.walletRef)), [
        (3, 1),
        (4, 1),
        (5, 1),
      ]);
    });

    test('an unknown reference still answers Disposed', () async {
      loop.receive(const DisposeRef(2, walletRef: 42));
      await _settle();
      expect(replies.last, isA<Disposed>().having((r) => r.id, 'id', 2));
    });

    test('pending disposals beyond queueLimit + live refs + reserve fail '
        'the executor rather than grow', () async {
      await _settle();
      // No live wallets: capacity is 4 + 0 + controlReserve.
      for (var i = 0; i <= 4 + controlReserve; i++) {
        loop.receive(DisposeRef(10 + i, walletRef: 100 + i));
      }
      await _settle();
      expect(faults, hasLength(1));
      expect(faults.single.kind, WorkerTerminationKind.uncaughtDartError);
      expect(loop.isFinished, isTrue);
    });
  });

  group('Shutdown (§3.8)', () {
    test('rejects queued operations, keeps queued disposals, runs last, and '
        'answers nothing afterwards', () async {
      loop.receive(const CreateWallet(2, strength: 128));
      await _settle();
      loop.receive(const ExportMnemonic(3, walletRef: 1));
      loop.receive(const DisposeRef(4, walletRef: 1));
      loop.receive(const Shutdown(5, grace: Duration(seconds: 1)));
      loop.receive(const Shutdown(6, grace: Duration(seconds: 1)));
      loop.receive(const CreateWallet(7, strength: 128));
      await _settle();
      final byId = {for (final r in replies) r.id: r};
      expect(
        byId[3],
        isA<Failed>().having(
          (r) => r.error,
          'error',
          isA<SessionStateError>()
              .having((e) => e.actual, 'actual', SessionState.closing)
              .having((e) => e.attempted, 'attempted', 'exportMnemonic'),
        ),
      );
      expect(byId[4], isA<Disposed>());
      expect(byId[5], isA<ShutdownComplete>());
      expect(byId[6], isA<ShutdownComplete>(), reason: 'coalesced');
      expect(byId[7], isA<Failed>());
      expect(handler.operations, [
        'initialize',
        'createWallet',
        'close',
        'shutdown',
      ]);
      expect(loop.isFinished, isTrue);

      final before = replies.length;
      loop.receive(const DisposeRef(8, walletRef: 1));
      loop.receive(const CreateWallet(9, strength: 128));
      await _settle();
      expect(replies, hasLength(before), reason: 'dropped after shutdown');
    });
  });

  group('the fault rule (§3.10)', () {
    test('an unmapped error stops the loop, releases everything, answers '
        'nothing more, and reports uncaughtDartError', () async {
      handler.throwOn['exportMnemonic'] = RangeError('corrupt size');
      loop.receive(const CreateWallet(2, strength: 128));
      loop.receive(const ExportMnemonic(3, walletRef: 1));
      loop.receive(const CreateWallet(4, strength: 128));
      await _settle();
      expect(replies.map((r) => r.id), [1, 2]);
      expect(handler.releaseAllCalls, 1);
      expect(handler.liveRefCount, 0);
      expect(faults.single.kind, WorkerTerminationKind.uncaughtDartError);
      expect(
        faults.single.cause,
        isA<WorkerFault>().having((f) => f.errorType, 'type', 'RangeError'),
      );
      expect(faults.single.toString(), isNot(contains('corrupt size')));
      expect(handler.operations, [
        'initialize',
        'createWallet',
        'exportMnemonic',
      ]);
    });

    test('during Init it reports initializationFailed', () async {
      final handler = FakeHandler()..throwOn['initialize'] = StateError('x');
      final faults = <WorkerTerminatedError>[];
      WorkerLoop(
        handler,
        post: (_) {},
        onFault: faults.add,
      ).receive(Init(1, queueLimit: 1));
      await _settle();
      expect(faults.single.kind, WorkerTerminationKind.initializationFailed);
    });
  });

  test('kill releases what the handler owns and stops the loop', () async {
    loop.receive(const CreateWallet(2, strength: 128));
    await _settle();
    loop.receive(const ExportMnemonic(3, walletRef: 1));
    loop.kill();
    await _settle();
    expect(handler.liveRefCount, 0);
    expect(replies.map((r) => r.id), [1, 2]);
    expect(loop.isFinished, isTrue);
  });

  test('the default schedule is a timer turn, not a microtask', () async {
    loop.receive(const CreateWallet(2, strength: 128));
    await Future<void>.microtask(() {});
    await Future<void>.microtask(() {});
    expect(handler.handled, isEmpty);
    await _settle();
    expect(handler.handled, isNotEmpty);
  });
}
