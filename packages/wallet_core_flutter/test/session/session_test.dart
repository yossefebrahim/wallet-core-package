// The session over a fake handler: the state machine, admission and the
// queue bound, control-message admission, deadlines, shutdown, proxies and
// their finalizer callback, cross-session references, and scopes
// (DECISION-12 §3; lifecycle.md §1–§5). No library needed.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/src/session/session.dart';
import 'package:wallet_core_flutter/src/session/testing.dart';
import 'package:wallet_core_flutter/src/wallet/wallet.dart';
import 'package:wallet_core_flutter/src/worker/protocol.dart';
import 'package:wallet_core_flutter/src/worker/transport.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';

import '../support/fake_handler.dart';
import '../support/fixtures.dart';
import '../support/recording_transport.dart';

const String _mnemonic =
    'zebra cabbage orbit velvet hammer quantum lantern meadow pistol saddle '
    'tunnel abandon';

Future<(WalletCoreSession, FakeHandler)> _start({
  int queueLimit = 32,
  OperationTimeouts timeouts = const OperationTimeouts(),
  FakeHandler? handler,
}) async {
  final fake = handler ?? FakeHandler();
  final core = await initializeForTesting(
    queueLimit: queueLimit,
    timeouts: timeouts,
    handler: fake,
  );
  return (core as WalletCoreSession, fake);
}

Matcher _stateError(SessionState actual) =>
    throwsA(isA<SessionStateError>().having((e) => e.actual, 'actual', actual));

void main() {
  group('state machine (§3.1)', () {
    test(
      'initialize → ready, shutdown → closing → closed, states broadcast',
      () async {
        final (core, _) = await _start();
        expect(core.state, SessionState.ready);
        // Two listeners at once; each stream ends after `closed`.
        final seen = core.states.toList();
        final other = core.states.toList();
        await core.shutdown();
        expect(core.state, SessionState.closed);
        expect(await seen, [SessionState.closing, SessionState.closed]);
        expect(await other, await seen);
      },
    );

    test(
      'baseline: normal shutdown, states list ends with closed synchronously',
      () async {
        final (core, _) = await _start();
        final seen = <SessionState>[];
        var done = false;
        core.states.listen(seen.add, onDone: () => done = true);
        await core.shutdown();
        expect(seen, [SessionState.closing, SessionState.closed]);
        expect(done, isTrue);
      },
    );

    test(
      'shutdown() bound: paused subscription completes within grace',
      () async {
        final (core, _) = await _start(
          timeouts: const OperationTimeouts(
            shutdownGrace: Duration(milliseconds: 50),
          ),
        );
        final seen = <SessionState>[];
        var done = false;
        final sub = core.states.listen(seen.add, onDone: () => done = true);
        sub.pause();

        final stopwatch = Stopwatch()..start();
        await core.shutdown();
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
        expect(core.state, SessionState.closed);
        expect(done, isFalse);

        sub.resume();
        await Future<void>.delayed(Duration.zero);
        expect(seen, contains(SessionState.closed));
        expect(done, isTrue);
      },
    );

    test('shutdown() bound: await for body awaiting indefinitely completes within grace', () async {
      final (core, _) = await _start(
        timeouts: const OperationTimeouts(
          shutdownGrace: Duration(milliseconds: 50),
        ),
      );
      final seen = <SessionState>[];

      final done = Completer<void>();
      Future<void> consume() async {
        await for (final state in core.states) {
          seen.add(state);
          if (state == SessionState.closing) {
            await Completer<void>().future;
          }
        }
        done.complete();
      }

      unawaited(consume());
      await Future<void>.delayed(Duration.zero);

      final stopwatch = Stopwatch()..start();
      await core.shutdown();
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
      expect(core.state, SessionState.closed);

      expect(done.isCompleted, isFalse);
    });

    test('a failed Init throws the typed error, hands out no session, and '
        'leaves nothing to close', () async {
      final fake = FakeHandler()
        ..initError = const ManifestMismatchError(
          check: ManifestCheck.artifactSetMismatch,
          expected: 'as_wrong',
          actual: 'as_4.8.0_000',
        );
      await expectLater(
        initializeForTesting(handler: fake),
        throwsA(
          isA<ManifestMismatchError>().having(
            (e) => e.check,
            'check',
            ManifestCheck.artifactSetMismatch,
          ),
        ),
      );
      expect(fake.operations, ['initialize']);
      expect(fake.liveRefCount, 0);
      expect(fake.releaseAllCalls, 1, reason: 'the executor was stopped');
    });

    test('Init past its deadline is OperationTimeoutError, and the executor '
        'is stopped', () async {
      final fake = FakeHandler()
        ..blockFor['initialize'] = const Duration(milliseconds: 60);
      await expectLater(
        initializeForTesting(
          timeouts: const OperationTimeouts(
            initialize: Duration(milliseconds: 20),
          ),
          handler: fake,
        ),
        throwsA(
          isA<OperationTimeoutError>().having(
            (e) => e.operation,
            'operation',
            'initialize',
          ),
        ),
      );
      expect(fake.releaseAllCalls, 1);
    });

    test('no request runs inside the public call that submitted it', () async {
      final (core, fake) = await _start();
      final before = fake.handled.length;
      final created = core.wallets.create();
      final valid = core.addresses.isValid('0xabc', coin: Coin.ethereum);
      expect(fake.handled, hasLength(before));
      await created;
      expect(await valid, isTrue);
      expect(fake.handled, hasLength(before + 2));
      await core.shutdown();
    });

    test('an unmapped error during Init is WorkerTerminatedError'
        '(initializationFailed)', () async {
      final fake = FakeHandler()..throwOn['initialize'] = StateError('x');
      await expectLater(
        initializeForTesting(handler: fake),
        throwsA(
          isA<WorkerTerminatedError>().having(
            (e) => e.kind,
            'kind',
            WorkerTerminationKind.initializationFailed,
          ),
        ),
      );
    });

    // A genuinely unexpected error — a broken invariant of the SDK's own
    // code. A soft native failure (a null or a corrupt size from upstream)
    // is not this: the engine-backed handler types it per operation and the
    // session stays ready (DECISION-12 §3.10;
    // ../engine/soft_native_failure_native_test.dart).
    test('an unmapped error in an operation moves ready → failed, fails it '
        'and everything pending, and every later call', () async {
      final (core, fake) = await _start();
      fake.throwOn['exportMnemonic'] = StateError('broken invariant');
      final failures = <SessionState>[];
      core.states.listen(failures.add);
      final wallet = await core.wallets.create();
      final export = wallet.exportMnemonic();
      final queued = wallet.account(Coin.ethereum);
      final terminated = isA<WorkerTerminatedError>().having(
        (e) => e.kind,
        'kind',
        WorkerTerminationKind.uncaughtDartError,
      );
      await expectLater(export, throwsA(terminated));
      await expectLater(queued, throwsA(terminated));
      expect(core.state, SessionState.failed);
      expect(failures, [SessionState.failed]);
      expect(fake.liveRefCount, 0, reason: 'the M0 executor released');
      await expectLater(core.wallets.create(), throwsA(terminated));
      await expectLater(wallet.close(), throwsA(terminated));
      expect(wallet.isClosed, isTrue);
      // failed → closed without a round trip.
      await core.shutdown();
      expect(core.state, SessionState.closed);
    });

    test('close() first called after failed → closed still completes with '
        'the termination error: nothing confirmed the release', () async {
      final (core, fake) = await _start();
      final first = await core.wallets.create();
      final second = await core.wallets.create();
      fake.throwOn['exportMnemonic'] = StateError('broken invariant');
      final terminated = isA<WorkerTerminatedError>().having(
        (e) => e.kind,
        'kind',
        WorkerTerminationKind.uncaughtDartError,
      );
      await expectLater(first.exportMnemonic(), throwsA(terminated));
      expect(core.state, SessionState.failed);
      await expectLater(first.close(), throwsA(terminated));
      await core.shutdown();
      expect(core.state, SessionState.closed);
      // Never closed before the session ended: the executor died first, so
      // this release was not confirmed either.
      await expectLater(second.close(), throwsA(terminated));
      expect(second.isClosed, isTrue);
      await expectLater(second.close(), throwsA(terminated));
    });

    test('closing rejects new operations with SessionStateError at once; '
        'closed rejects them with ClosedError', () async {
      final (core, _) = await _start();
      final wallet = await core.wallets.create();
      final shutdown = core.shutdown();
      expect(core.state, SessionState.closing);
      await expectLater(
        core.wallets.create(),
        _stateError(SessionState.closing),
      );
      await expectLater(
        core.addresses.isValid('0x', coin: Coin.ethereum),
        _stateError(SessionState.closing),
      );
      await shutdown;
      await expectLater(
        wallet.account(Coin.ethereum),
        throwsA(isA<ClosedError>()),
      );
      await expectLater(
        core.mnemonics.isValid(_mnemonic),
        throwsA(isA<ClosedError>()),
      );
      expect(wallet.isClosed, isTrue);
      await wallet.close();
    });
  });

  group('shutdown (§3.8)', () {
    test(
      'is idempotent: concurrent and repeated calls share one completion',
      () async {
        final (core, fake) = await _start();
        final a = core.shutdown();
        final b = core.shutdown();
        expect(identical(a, b), isTrue);
        await a;
        await core.shutdown();
        expect(fake.operations.where((o) => o == 'shutdown'), hasLength(1));
      },
    );

    test(
      'rejects queued work with SessionStateError, lets the running '
      'operation finish, releases every wallet and reports the count',
      () async {
        final (core, fake) = await _start();
        final w1 = await core.wallets.create();
        await core.wallets.create();
        final running = w1.exportMnemonic();
        final queued = w1.account(Coin.ethereum);
        // Both were submitted before shutdown, and neither has run yet: the
        // executor never runs a request inside the call that submitted it.
        final shutdown = core.shutdown();
        await expectLater(running, throwsA(isA<SessionStateError>()));
        await expectLater(queued, throwsA(isA<SessionStateError>()));
        await shutdown;
        expect(core.disposedAtShutdown, 2);
        expect(core.forcedTermination, isFalse);
        expect(fake.liveRefCount, 0);
      },
    );

    test('an operation already running when shutdown arrives completes '
        'normally', () async {
      final (core, fake) = await _start();
      final wallet = await core.wallets.create();
      fake.blockFor['exportMnemonic'] = const Duration(milliseconds: 50);
      final export = wallet.exportMnemonic();
      // Let the executor pick it up: it runs in a timer turn after arrival.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(fake.operations.last, 'exportMnemonic');
      await core.shutdown();
      expect(await export, startsWith('fake mnemonic'));
    });

    test('close() issued while closing completes with WorkerTerminatedError '
        'when shutdown had to force the executor down', () async {
      final (core, fake) = await _start(
        timeouts: const OperationTimeouts(
          shutdownGrace: Duration(milliseconds: 50),
        ),
      );
      final first = await core.wallets.create();
      final second = await core.wallets.create();
      // A release that outlasts the grace period.
      fake.blockFor['close'] = const Duration(milliseconds: 120);
      final firstClose = first.close();
      final shutdown = core.shutdown();
      expect(core.state, SessionState.closing);
      // The first close was acknowledged before the kill; the second never
      // was, and must not report a release nobody confirmed.
      final secondClose = expectLater(
        second.close(),
        throwsA(
          isA<WorkerTerminatedError>().having(
            (e) => e.kind,
            'kind',
            WorkerTerminationKind.isolateExited,
          ),
        ),
      );
      await shutdown;
      expect(core.forcedTermination, isTrue);
      expect(core.state, SessionState.closed);
      await firstClose;
      await secondClose;
      // After closed, the same answer.
      await expectLater(second.close(), throwsA(isA<WorkerTerminatedError>()));
    });

    test('shutdown with an open wallet stream completion', () async {
      final (core, fake) = await _start();
      final states = <SessionState>[];
      var done = false;
      core.states.listen(states.add, onDone: () => done = true);
      await core.wallets.create();
      await core.shutdown();
      expect(states.last, SessionState.closed);
      expect(done, isTrue);
      expect(core.disposedAtShutdown, 1);
      expect(fake.liveRefCount, 0);
    });

    test('a second subscriber added just before shutdown() also sees closed and done', () async {
      final (core, _) = await _start();
      final states1 = <SessionState>[];
      var done1 = false;
      core.states.listen(states1.add, onDone: () => done1 = true);
      final states2 = <SessionState>[];
      var done2 = false;
      core.states.listen(states2.add, onDone: () => done2 = true);
      await core.shutdown();
      expect(states1.last, SessionState.closed);
      expect(done1, isTrue);
      expect(states2.last, SessionState.closed);
      expect(done2, isTrue);
    });

    test('a listener that calls core.shutdown() from inside onData when it sees closing', () async {
      final (core, _) = await _start();
      final states = <SessionState>[];
      var done = false;
      late Future<void> innerShutdown;
      core.states.listen((s) {
        states.add(s);
        if (s == SessionState.closing) {
          innerShutdown = core.shutdown();
        }
      }, onDone: () => done = true);
      final outerShutdown = core.shutdown();
      await outerShutdown.timeout(const Duration(milliseconds: 100));
      expect(identical(innerShutdown, outerShutdown), isTrue);
      expect(states.last, SessionState.closed);
      expect(done, isTrue);
    });

    test(
      'a states subscription made after closed receives only done',
      () async {
        final (core, _) = await _start();
        await core.shutdown();
        expect(core.state, SessionState.closed);

        final states = <SessionState>[];
        var done = false;
        core.states.listen(states.add, onDone: () => done = true);

        // Wait a tick to let it process
        await Future<void>.delayed(Duration.zero);
        expect(states, isEmpty, reason: 'no events after closed');
        expect(done, isTrue, reason: 'onDone fires immediately');
      },
    );
  });

  group('secret buffers at the transport (A-7)', () {
    test("send overwrites the sender's entropy copy at once; the executor "
        'works on its own copy', () async {
      final fake = FakeHandler();
      final transport = InProcessTransport(
        fake,
        onReply: (_) {},
        onTerminated: (_) {},
      );
      transport.send(Init(1, queueLimit: 4));
      final request = ImportWallet.entropy(
        2,
        Uint8List.fromList(List<int>.filled(16, 7)),
      );
      transport.send(request);
      expect(request.entropy, everyElement(0));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fake.entropySeen.single, List<int>.filled(16, 7));
      final delivered = fake.handled.whereType<ImportWallet>().single;
      expect(delivered, isNot(same(request)));
      expect(delivered.entropy, everyElement(0), reason: 'executor side');
      transport.close();
    });

    test('a request sent after the transport closed is overwritten, not '
        'kept', () {
      final transport = InProcessTransport(
        FakeHandler(),
        onReply: (_) {},
        onTerminated: (_) {},
      )..close();
      final request = ImportWallet.entropy(
        1,
        Uint8List.fromList(List<int>.filled(16, 7)),
      );
      transport.send(request);
      expect(request.entropy, everyElement(0));
    });
  });

  group('the queue bound (§3.4)', () {
    test('submission beyond queueLimit throws QueueFullError and does not '
        'run; control messages are still admitted', () async {
      final (core, fake) = await _start(queueLimit: 3);
      final wallet = await core.wallets.create();
      final accepted = [
        for (var i = 0; i < 3; i++) wallet.account(Coin.ethereum),
      ];
      expect(core.outstandingOperations, 3);
      await expectLater(
        wallet.exportMnemonic(),
        throwsA(isA<QueueFullError>().having((e) => e.limit, 'limit', 3)),
      );
      await expectLater(
        core.addresses.isValid('0xabc', coin: Coin.ethereum),
        throwsA(isA<QueueFullError>()),
      );
      // close() is a control message: admitted with the queue full.
      final closed = wallet.close();
      await Future.wait(accepted);
      await closed;
      expect(fake.operations.where((o) => o == 'exportMnemonic'), isEmpty);
      expect(fake.operations.last, 'close');
      expect(core.outstandingOperations, 0);
      await core.shutdown();
    });

    test('shutdown is admitted with the queue full', () async {
      final (core, _) = await _start(queueLimit: 1);
      final wallet = core.wallets.create();
      final rejected = expectLater(wallet, throwsA(isA<SessionStateError>()));
      await core.shutdown();
      await rejected;
      expect(core.state, SessionState.closed);
    });

    test('queueLimit below 1 and non-positive timeouts are rejected', () async {
      await expectLater(
        initializeForTesting(queueLimit: 0, handler: FakeHandler()),
        throwsA(
          isA<InvalidInputError>().having(
            (e) => e.inputName,
            'n',
            'queueLimit',
          ),
        ),
      );
      await expectLater(
        initializeForTesting(
          timeouts: const OperationTimeouts(derivation: Duration.zero),
          handler: FakeHandler(),
        ),
        throwsA(isA<InvalidInputError>()),
      );
    });
  });

  group('deadlines (§3.5)', () {
    test('a deadline runs from submission; the work was not aborted, and its '
        'late result is dropped by the executor, never posted', () async {
      final fake = FakeHandler();
      final (core, posted) = await startRecordingSession(
        fake,
        timeouts: const OperationTimeouts(
          derivation: Duration(milliseconds: 40),
        ),
      );
      final wallet = await core.wallets.create();
      fake.blockFor['account'] = const Duration(milliseconds: 120);
      await expectLater(
        wallet.account(Coin.ethereum),
        throwsA(
          isA<OperationTimeoutError>()
              .having((e) => e.operation, 'operation', 'account')
              .having(
                (e) => e.timeout,
                'timeout',
                const Duration(milliseconds: 40),
              ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fake.operations.where((o) => o == 'account'), hasLength(1));
      // DECISION-12 §3.9: dropped without being posted, not posted and
      // ignored. A key-less Failed closes the session's accounting instead.
      expect(posted.whereType<AddressDerived>(), isEmpty);
      final accountId = fake.handled.whereType<DeriveAddress>().single.id;
      expect(
        posted.where((r) => r.id == accountId).single,
        isA<Failed>().having(
          (r) => r.error,
          'error',
          isA<OperationTimeoutError>(),
        ),
      );
      expect(fake.discarded, ['AddressDerived']);
      expect(core.outstandingOperations, 0);
      expect(core.state, SessionState.ready);
      await core.shutdown();
    });

    test('a mnemonic exported past its deadline never crosses', () async {
      final fake = FakeHandler();
      final (core, posted) = await startRecordingSession(
        fake,
        timeouts: const OperationTimeouts(
          walletOperation: Duration(milliseconds: 40),
        ),
      );
      final wallet = await core.wallets.create();
      fake.blockFor['exportMnemonic'] = const Duration(milliseconds: 100);
      await expectLater(
        wallet.exportMnemonic(),
        throwsA(isA<OperationTimeoutError>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(posted.whereType<MnemonicExported>(), isEmpty);
      expect(fake.discarded, ['MnemonicExported']);
      expect(core.outstandingOperations, 0);
      await core.shutdown();
    });

    test('time spent queued counts: an operation stuck behind a slow one '
        'times out, and is withdrawn if it has not started', () async {
      final (core, fake) = await _start(
        timeouts: const OperationTimeouts(
          derivation: Duration(milliseconds: 30),
        ),
      );
      final wallet = await core.wallets.create();
      fake.blockFor['exportMnemonic'] = const Duration(milliseconds: 100);
      final slow = wallet.exportMnemonic();
      final starved = wallet.account(Coin.ethereum);
      await expectLater(starved, throwsA(isA<OperationTimeoutError>()));
      expect(await slow, startsWith('fake mnemonic'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(core.outstandingOperations, 0);
      await core.shutdown();
    });

    test('a wallet created after its caller timed out is released by the '
        'executor, not posted and not left until shutdown', () async {
      final fake = FakeHandler();
      final (core, posted) = await startRecordingSession(
        fake,
        timeouts: const OperationTimeouts(
          walletOperation: Duration(milliseconds: 30),
        ),
      );
      fake.blockFor['createWallet'] = const Duration(milliseconds: 80);
      await expectLater(
        core.wallets.create(),
        throwsA(isA<OperationTimeoutError>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(posted.whereType<WalletCreated>(), isEmpty);
      expect(fake.discarded, ['WalletCreated']);
      expect(fake.liveRefCount, 0);
      await core.shutdown();
    });

    test('a timeout too long to add to the clock means never, not already '
        'passed: the operation runs and succeeds', () async {
      const never = Duration(microseconds: 0x7FFFFFFFFFFFFFFF);
      final fake = FakeHandler();
      final (core, posted) = await startRecordingSession(
        fake,
        timeouts: const OperationTimeouts(
          walletOperation: never,
          derivation: never,
        ),
      );
      final wallet = await core.wallets.create();
      final account = await wallet.account(Coin.ethereum);
      expect(account.coin, Coin.ethereum);
      expect(fake.operations, containsAllInOrder(['createWallet', 'account']));
      expect(posted.whereType<Failed>(), isEmpty);
      expect(fake.discarded, isEmpty);
      expect(core.outstandingOperations, 0);
      await wallet.close();
      await core.shutdown();
    });

    test('close() has no deadline: it waits behind a slow operation and '
        'completes normally', () async {
      final (core, fake) = await _start(
        timeouts: const OperationTimeouts(
          walletOperation: Duration(milliseconds: 500),
          derivation: Duration(milliseconds: 10),
        ),
      );
      final wallet = await core.wallets.create();
      fake.blockFor['exportMnemonic'] = const Duration(milliseconds: 60);
      final export = wallet.exportMnemonic();
      await wallet.close();
      expect(await export, startsWith('fake mnemonic'));
      await core.shutdown();
    });
  });

  group('Wallet proxies (lifecycle.md §2)', () {
    test('close() is idempotent, marks the proxy closed at once, and waits '
        'for work already submitted on the wallet', () async {
      final (core, fake) = await _start();
      final wallet = await core.wallets.create();
      final derive = wallet.account(Coin.ethereum);
      final order = <String>[];
      unawaited(derive.then((_) => order.add('account')));
      final first = wallet.close();
      final second = wallet.close();
      expect(identical(first, second), isTrue);
      expect(wallet.isClosed, isTrue);
      await expectLater(
        wallet.account(Coin.ethereum),
        throwsA(
          isA<ClosedError>().having((e) => e.resourceType, 't', 'Wallet'),
        ),
      );
      await expectLater(wallet.exportMnemonic(), throwsA(isA<ClosedError>()));
      await first.then((_) => order.add('close'));
      expect(order, ['account', 'close']);
      expect((await derive).address.value, '0xfake1');
      expect(fake.disposedRefs, [1], reason: 'one DisposeRef for two closes');
      await core.shutdown();
    });

    test('inputs are checked before anything crosses', () async {
      final (core, fake) = await _start();
      final before = fake.handled.length;
      await expectLater(
        core.wallets.create(strength: 100),
        throwsA(isA<InvalidInputError>()),
      );
      await expectLater(
        core.wallets.importMnemonic('a\u0000b c d e f g h i j k l'),
        throwsA(isA<InvalidInputError>()),
      );
      await expectLater(
        core.wallets.importEntropy(Uint8List(15)),
        throwsA(isA<InvalidInputError>()),
      );
      await expectLater(
        core.wallets.create(passphrase: 'x\uD800'),
        throwsA(isA<InvalidInputError>()),
      );
      final wallet = await core.wallets.create();
      await expectLater(
        wallet.account(Coin.ethereum, path: 'm/44/60/invalid'),
        throwsA(isA<InvalidInputError>()),
      );
      await expectLater(
        wallet.account(Coin.ethereum, network: Network.testnet),
        throwsA(isA<UnsupportedOperationError>()),
      );
      await expectLater(
        core.addresses.isValid(
          '0x',
          coin: Coin.ethereum,
          network: Network.testnet,
        ),
        throwsA(isA<UnsupportedOperationError>()),
      );
      expect(fake.handled.length, before + 1, reason: 'only the create');
      await core.shutdown();
    });

    test('importEntropy sends a copy taken at the call', () async {
      final (core, fake) = await _start();
      final entropy = Uint8List.fromList(List<int>.filled(16, 3));
      final wallet = core.wallets.importEntropy(entropy);
      entropy.fillRange(0, 16, 9);
      await wallet;
      final sent = fake.handled.whereType<ImportWallet>().single;
      expect(sent.entropy, isNot(same(entropy)));
      await core.shutdown();
    });

    test('a reference from one session is rejected by another', () async {
      final (a, _) = await _start();
      final (b, _) = await _start();
      final wallet = await a.wallets.create();
      expect(resolveWalletRef(a, wallet.ref), 1);
      expect(
        () => resolveWalletRef(b, wallet.ref),
        throwsA(
          isA<KeyResolutionError>().having(
            (e) => e.reason,
            'reason',
            KeyResolutionReason.foreignRef,
          ),
        ),
      );
      expect(wallet.ref.toString(), 'WalletRef(#1)');
      await wallet.close();
      expect(
        () => resolveWalletRef(a, wallet.ref),
        throwsA(
          isA<ClosedError>().having((e) => e.resourceType, 'type', 'Wallet'),
        ),
      );
      await a.shutdown();
      await b.shutdown();
    });
  });

  group('the proxy finalizer callback (§3.7)', () {
    test('posts DisposeRef only while ready, and never throws', () async {
      final (core, fake) = await _start();
      await core.wallets.create();
      core.postFinalizerDispose(1);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fake.disposedRefs, [1]);

      final shutdown = core.shutdown();
      expect(core.state, SessionState.closing);
      core.postFinalizerDispose(2);
      await shutdown;
      core.postFinalizerDispose(3);
      expect(fake.disposedRefs, [1], reason: 'nothing posted after ready');

      final (failed, failedFake) = await _start();
      failedFake.throwOn['createWallet'] = StateError('x');
      await expectLater(
        failed.wallets.create(),
        throwsA(isA<WorkerTerminatedError>()),
      );
      expect(failed.state, SessionState.failed);
      failed.postFinalizerDispose(1);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(failedFake.disposedRefs, isEmpty);
    });
  });

  group('cancel (§3.6)', () {
    test('a queued operation is withdrawn; one already answered is not '
        'cancellable and costs no message', () async {
      final (core, fake) = await _start();
      final wallet = await core.wallets.create();
      final id = core.nextRequestId;
      final queued = wallet.account(Coin.ethereum);
      expect(core.cancel(id), isTrue);
      expect(core.cancel(id), isFalse, reason: 'one Cancel per target');
      await expectLater(
        queued,
        throwsA(
          isA<OperationCancelledError>().having((e) => e.requestId, 'id', id),
        ),
      );
      expect(fake.operations.where((o) => o == 'account'), isEmpty);
      expect(core.cancel(id), isFalse);
      expect(core.cancel(9999), isFalse);
      await core.shutdown();
    });
  });

  group('scope (PRD §11.2 item 6)', () {
    test('closes everything it created in reverse order on return', () async {
      final (core, fake) = await _start();
      final result = await core.scope((s) async {
        final a = await s.createWallet();
        final b = await s.importMnemonic(_mnemonic);
        final c = await s.importEntropy(Uint8List(16));
        return [a, b, c];
      });
      expect(result.every((w) => w.isClosed), isTrue);
      expect(fake.disposedRefs, [3, 2, 1]);
      expect(fake.liveRefCount, 0);
      await core.shutdown();
    });

    test('closes everything on throw and rethrows the body error', () async {
      final (core, fake) = await _start();
      late SessionScope escaped;
      await expectLater(
        core.scope<void>((s) async {
          escaped = s;
          await s.createWallet();
          // Not awaited: the scope still waits for it and closes it.
          unawaited(s.createWallet());
          throw const FormatException('body failed');
        }),
        throwsA(isA<FormatException>()),
      );
      expect(fake.disposedRefs, [2, 1]);
      await expectLater(
        escaped.createWallet(),
        throwsA(
          isA<ClosedError>().having((e) => e.resourceType, 't', 'SessionScope'),
        ),
      );
      await core.shutdown();
    });

    test('a failed creation inside a scope has nothing to close', () async {
      final (core, fake) = await _start();
      await core.scope((s) async {
        await expectLater(
          s.createWallet(strength: 1),
          throwsA(isA<InvalidInputError>()),
        );
        await s.createWallet();
      });
      expect(fake.disposedRefs, [1]);
      await core.shutdown();
    });
  });

  group('the mnemonic helpers', () {
    test('answer locally when they can, so the text never crosses', () async {
      final (core, fake) = await _start();
      expect(await core.mnemonics.isValid('too few words'), isFalse);
      expect(await core.mnemonics.isValidWord(''), isFalse);
      expect(await core.mnemonics.isValidWord('ab\u0000c'), isFalse);
      expect(await core.mnemonics.suggest('AB'), isEmpty);
      expect(fake.handled, hasLength(1), reason: 'only Init');
      expect(await core.mnemonics.isValid(_mnemonic), isTrue);
      expect(await core.mnemonics.isValidWord('orbit'), isTrue);
      expect(await core.mnemonics.suggest('or'), ['orone', 'ortwo']);
      await core.shutdown();
    });
  });

  test('errors raised for a secret input never render it', () async {
    final (core, _) = await _start();
    const passphrase = 'correct-horse-battery\u0000staple';
    try {
      await core.wallets.importMnemonic(_mnemonic, passphrase: passphrase);
      fail('no error');
    } on InvalidInputError catch (error) {
      expectRedacted(error, [_mnemonic, passphrase]);
    }
    await core.shutdown();
  });
}
