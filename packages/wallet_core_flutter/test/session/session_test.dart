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
import 'package:wallet_core_flutter/wallet_core_flutter.dart';

import '../support/fake_handler.dart';
import '../support/fixtures.dart';

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

    test('an unmapped error in an operation moves ready → failed, fails it '
        'and everything pending, and every later call', () async {
      final (core, fake) = await _start();
      fake.throwOn['exportMnemonic'] = RangeError('corrupt size');
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
    test('a deadline runs from submission; a late result is discarded and '
        'the work was not aborted', () async {
      final (core, fake) = await _start(
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
      expect(core.outstandingOperations, 0);
      expect(core.state, SessionState.ready);
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

    test('a wallet created after its caller timed out is released, not '
        'left until shutdown', () async {
      final (core, fake) = await _start(
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
      expect(fake.disposedRefs, [1]);
      expect(fake.liveRefCount, 0);
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
        throwsA(isA<KeyResolutionError>()),
      );
      expect(wallet.ref.toString(), 'WalletRef(#1)');
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
