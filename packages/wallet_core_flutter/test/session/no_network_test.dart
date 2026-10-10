@Tags(['native'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/src/session/testing.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';
import 'package:wallet_core_flutter_native/wallet_core_flutter_native.dart'
    show ManifestIdentity;

import '../support/host_library.dart';

const ManifestIdentity _hostIdentity = ManifestIdentity(
  artifactSetId: 'as_4.8.0_000',
  upstreamCommit: 'd692ac27749d0c615e17c751b70ab4f0aa75c59b',
);

void main() {
  final skip = hostLibrarySkipReason();

  group('No-network runtime test (In-process Layer A)', skip: skip, () {
    test('negative control: socket is blocked by IOOverrides', () async {
      final attempts = <String>[];
      bool blocked = false;
      await IOOverrides.runZoned(
        () async {
          try {
            await Socket.connect('8.8.8.8', 53);
          } catch (e) {
            blocked = true;
            expect(e, isA<StateError>());
          }
        },
        socketConnect: (host, port, {sourceAddress, int? sourcePort, timeout}) {
          attempts.add('connect $host:$port');
          throw StateError('Network access blocked: connect to $host:$port');
        },
        socketStartConnect: (host, port, {sourceAddress, int? sourcePort}) {
          attempts.add('startConnect $host:$port');
          throw StateError(
            'Network access blocked: startConnect to $host:$port',
          );
        },
      );
      expect(blocked, isTrue);
      expect(attempts, isNotEmpty);
    });

    test('M0 flow runs without network access', () async {
      // Layer A records attempts in this isolate. It does NOT see:
      // RawSocket, SecureSocket, RawDatagramSocket, InternetAddress.lookup, or native code.
      // Layer B (the OS sandbox) covers those. Also note that in the M0 flow there
      // is no worker isolate: `initializeForTesting` and `WalletCore.initialize` use
      // `InProcessTransport` (session.dart / transport.dart), so the zone covers the executor today.
      // When T2.1 adds a worker isolate, overrides must be installed inside the isolate.
      final attempts = <String>[];

      await HttpOverrides.runZoned(
        () async {
          await IOOverrides.runZoned(
            () async {
              // Initialize
              final core = await initializeForTesting(
                hostLibraryPath: findHostLibrary(),
                expectedIdentity: _hostIdentity,
              );
              // Create wallet
              final created = await core.wallets.create(strength: 128);
              await created.close();
              // Import vector mnemonic
              final wallet = await core.wallets.importMnemonic(
                'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
              );
              // Derive address
              final account = await wallet.account(Coin.ethereum);
              expect(account.address.value, isNotEmpty);
              // Sign EIP-1559 request
              final request = EvmTransactionRequest.transfer(
                coin: Coin.ethereum,
                chainId: 1,
                nonce: BigInt.zero,
                to: '0x0000000000000000000000000000000000000000',
                valueWei: BigInt.zero,
                maxFeePerGas: BigInt.zero,
                maxPriorityFeePerGas: BigInt.zero,
                gasLimit: BigInt.from(21000),
              );
              final key = KeyLocator.hdPath(
                wallet.ref,
                account.coin,
                account.derivationPath,
              );
              final result =
                  await core.signer.sign(request, {key}) as EvmSignResult;
              expect(result.encoded, isNotEmpty);
              // Shutdown
              await core.shutdown();
            },
            socketConnect:
                (host, port, {sourceAddress, int? sourcePort, timeout}) {
                  attempts.add('connect $host:$port');
                  throw StateError(
                    'Network access blocked: connect to $host:$port',
                  );
                },
            socketStartConnect: (host, port, {sourceAddress, int? sourcePort}) {
              attempts.add('startConnect $host:$port');
              throw StateError(
                'Network access blocked: startConnect to $host:$port',
              );
            },
            serverSocketBind:
                (address, port, {backlog = 0, v6Only = false, shared = false}) {
                  attempts.add('bind $address:$port');
                  throw StateError(
                    'Network access blocked: bind to $address:$port',
                  );
                },
          );
        },
        createHttpClient: (context) {
          attempts.add('createHttpClient');
          throw StateError('Network access blocked: createHttpClient');
        },
      );

      expect(attempts, isEmpty);
    });
  });
}
