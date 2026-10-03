// `WalletCore.signer` over a fake handler: what crosses in `Sign`, what comes
// back, the checks made before submission, and the queue bound and deadline
// applied to signing like any other operation (DECISION-12 §3.4, §3.5). No
// library needed.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/src/session/session.dart';
import 'package:wallet_core_flutter/src/session/testing.dart';
import 'package:wallet_core_flutter/src/signing/key_locator.dart'
    show issueKeyRef;
import 'package:wallet_core_flutter/src/worker/protocol.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';

import '../support/fake_handler.dart';
import 'signing_support.dart';

const String _to = '0xB9F5771C27664bF2282D98E09D7F50cEc7cB01a7';
const String _path = "m/44'/60'/0'/0/0";

Future<(WalletCoreSession, FakeHandler)> _start({
  int queueLimit = 32,
  OperationTimeouts timeouts = const OperationTimeouts(),
}) async {
  final fake = FakeHandler();
  final core = await initializeForTesting(
    queueLimit: queueLimit,
    timeouts: timeouts,
    handler: fake,
  );
  return (core as WalletCoreSession, fake);
}

void main() {
  test('sign sends the request and the locator names, never a WalletRef, and '
      'returns the caller\'s locators as usedKeys', () async {
    final (core, fake) = await _start();
    final wallet = await core.wallets.create();
    final locator = KeyLocator.hdPath(wallet.ref, Coin.ethereum, _path);
    final request = transferTo(_to);

    final result = await core.signer.sign(request, {locator});

    final sent = fake.handled.whereType<Sign>().single;
    expect(sent.request, same(request));
    expect(sent.keys, {
      HdLocatorSpec(
        sessionToken: core.sessionToken,
        walletRef: 1,
        coin: Coin.ethereum,
        derivationPath: _path,
      ),
    });
    expect(result, isA<EvmSignResult>());
    expect(result.coin, Coin.ethereum);
    expect(result.usedKeys, {locator});
    await core.shutdown();
  });

  test('every session has its own token, and Init carries it', () async {
    final (a, fakeA) = await _start();
    final (b, _) = await _start();
    expect(a.sessionToken, isPositive);
    expect(b.sessionToken, isNot(a.sessionToken));
    expect(fakeA.handled.whereType<Init>().single.sessionToken, a.sessionToken);
    await a.shutdown();
    await b.shutdown();
  });

  test('signWithKey is sign over a one-element set', () async {
    final (core, fake) = await _start();
    final wallet = await core.wallets.create();
    final locator = KeyLocator.hdPath(wallet.ref, Coin.ethereum, _path);
    final result = await core.signer.signWithKey(transferTo(_to), locator);
    expect(result.usedKeys, {locator});
    expect(fake.handled.whereType<Sign>().single.keys, hasLength(1));
    await core.shutdown();
  });

  test('a duplicate-equal locator is folded before it crosses', () async {
    final (core, fake) = await _start();
    final wallet = await core.wallets.create();
    final result = await core.signer.sign(transferTo(_to), {
      KeyLocator.hdPath(wallet.ref, Coin.ethereum, _path),
      KeyLocator.hdPath(wallet.ref, Coin.ethereum, _path),
    });
    expect(result.usedKeys, hasLength(1));
    expect(fake.handled.whereType<Sign>().single.keys, hasLength(1));
    await core.shutdown();
  });

  test('a reference of another session is KeyResolutionError(foreignRef), '
      'and nothing is sent', () async {
    final (a, _) = await _start();
    final (b, fakeB) = await _start();
    final wallet = await a.wallets.create();
    await expectLater(
      b.signer.sign(transferTo(_to), {
        KeyLocator.hdPath(wallet.ref, Coin.ethereum, _path),
      }),
      throwsA(
        isA<KeyResolutionError>().having(
          (e) => e.reason,
          'reason',
          KeyResolutionReason.foreignRef,
        ),
      ),
    );
    expect(fakeB.handled.whereType<Sign>(), isEmpty);
    expect(b.outstandingOperations, 0);
    await a.shutdown();
    await b.shutdown();
  });

  test('a closed wallet is ClosedError, and nothing is sent', () async {
    final (core, fake) = await _start();
    final wallet = await core.wallets.create();
    final locator = KeyLocator.hdPath(wallet.ref, Coin.ethereum, _path);
    final closing = wallet.close();
    await expectLater(
      core.signer.sign(transferTo(_to), {locator}),
      throwsA(
        isA<ClosedError>().having((e) => e.resourceType, 'type', 'Wallet'),
      ),
    );
    await closing;
    expect(fake.handled.whereType<Sign>(), isEmpty);
    await core.shutdown();
  });

  test('imported and external locators cross as their names; the executor '
      'decides', () async {
    final (core, fake) = await _start();
    await core.signer.sign(transferTo(_to), {
      KeyLocator.imported(issueKeyRef(5), role: KeyRole.feePayer),
      KeyLocator.external('ledger-1', Uint8List(33)),
    });
    expect(fake.handled.whereType<Sign>().single.keys, {
      const ImportedLocatorSpec(keyRef: 5, role: KeyRole.feePayer),
      const ExternalLocatorSpec(deviceId: 'ledger-1'),
    });
    await core.shutdown();
  });

  test('after shutdown, sign is ClosedError', () async {
    final (core, _) = await _start();
    final wallet = await core.wallets.create();
    await core.shutdown();
    await expectLater(
      core.signer.sign(transferTo(_to), {
        KeyLocator.hdPath(wallet.ref, Coin.ethereum, _path),
      }),
      throwsA(isA<ClosedError>()),
    );
  });

  test('sign counts against the queue bound', () async {
    final (core, fake) = await _start(queueLimit: 2);
    final wallet = await core.wallets.create();
    fake.blockFor['sign'] = const Duration(milliseconds: 30);
    final locator = KeyLocator.hdPath(wallet.ref, Coin.ethereum, _path);
    final first = core.signer.sign(transferTo(_to), {locator});
    final second = core.signer.sign(transferTo(_to, nonce: 7), {locator});
    await expectLater(
      core.signer.sign(transferTo(_to, nonce: 8), {locator}),
      throwsA(isA<QueueFullError>().having((e) => e.limit, 'limit', 2)),
    );
    await Future.wait([first, second]);
    expect(fake.handled.whereType<Sign>(), hasLength(2));
    await core.shutdown();
  });

  test('sign has the signing deadline: a late result is discarded', () async {
    final (core, fake) = await _start(
      timeouts: const OperationTimeouts(signing: Duration(milliseconds: 40)),
    );
    final wallet = await core.wallets.create();
    fake.blockFor['sign'] = const Duration(milliseconds: 80);
    await expectLater(
      core.signer.sign(transferTo(_to), {
        KeyLocator.hdPath(wallet.ref, Coin.ethereum, _path),
      }),
      throwsA(
        isA<OperationTimeoutError>()
            .having((e) => e.operation, 'operation', 'sign')
            .having(
              (e) => e.timeout,
              'timeout',
              const Duration(milliseconds: 40),
            ),
      ),
    );
    expect(core.outstandingOperations, 0);
    await core.shutdown();
  });

  test(
    'a sign still queued is withdrawn by its deadline and never runs',
    () async {
      final (core, fake) = await _start(
        timeouts: const OperationTimeouts(
          derivation: Duration(seconds: 5),
          signing: Duration(milliseconds: 20),
        ),
      );
      final wallet = await core.wallets.create();
      fake.blockFor['account'] = const Duration(milliseconds: 60);
      final slow = wallet.account(Coin.ethereum);
      final starved = core.signer.sign(transferTo(_to), {
        KeyLocator.hdPath(wallet.ref, Coin.ethereum, _path),
      });
      await expectLater(starved, throwsA(isA<OperationTimeoutError>()));
      await slow;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fake.operations, isNot(contains('sign')));
      await core.shutdown();
    },
  );
}
