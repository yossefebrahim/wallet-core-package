// The protocol types: what they carry, what their toString() shows, and the
// one buffer a request owns. No library needed.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/src/address/address.dart';
import 'package:wallet_core_flutter/src/worker/protocol.dart';
import 'package:wallet_core_flutter/src/worker/worker_loop.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';

import '../support/fixtures.dart';

const String _mnemonic =
    'zebra cabbage orbit velvet hammer quantum lantern meadow pistol saddle '
    'tunnel abandon';
const String _passphrase = 'correct-horse-battery-staple';

/// Asserts [value]'s toString() contains none of [secrets], without ever
/// printing a secret into the test log.
void _expectNoSecret(Object value, Iterable<String> secrets) {
  final rendered = value.toString();
  for (final secret in secrets) {
    final fragments = <String>{
      secret,
      ...secret.split(RegExp(r'\s+')).where((part) => part.length >= 4),
    };
    for (final fragment in fragments) {
      if (rendered.contains(fragment)) {
        fail(
          '${value.runtimeType}.toString() rendered a secret fragment of '
          'length ${fragment.length}',
        );
      }
    }
  }
}

String _hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('secret-bearing payloads never render their secret', () {
    final entropy = Uint8List.fromList(List<int>.generate(16, (i) => 0xA0 + i));

    final cases = <(Object, List<String>)>[
      (CreateWallet(1, strength: 128, passphrase: _passphrase), [_passphrase]),
      (
        const ImportWallet.mnemonic(2, _mnemonic, passphrase: _passphrase),
        [_mnemonic, _passphrase],
      ),
      (
        ImportWallet.entropy(3, entropy, passphrase: _passphrase),
        [_hex(entropy), _passphrase, entropy.toString()],
      ),
      (const MnemonicExported(4, _mnemonic), [_mnemonic]),
      (const ValidateMnemonic(5, _mnemonic), [_mnemonic]),
      (const ValidateMnemonicWord(6, 'orbit'), ['orbit']),
      (const SuggestMnemonicWords(7, 'orbi'), ['orbi']),
      (MnemonicWordsSuggested(8, ['orbit']), ['orbit']),
    ];

    for (final (value, secrets) in cases) {
      test('${value.runtimeType}', () {
        _expectNoSecret(value, secrets);
        expect(value.toString(), contains(redacted));
      });
    }

    test('a Failed reply renders only the typed error, which is redacted', () {
      const error = InvalidInputError(
        'not a valid BIP-39 mnemonic',
        inputName: 'mnemonic',
      );
      const reply = Failed(9, error);
      _expectNoSecret(reply, [_mnemonic]);
      expectRedacted(error, [_mnemonic]);
      expect(reply.toString(), contains('InvalidInputError'));
    });

    test('a WorkerFault names the error type and nothing it carried', () {
      final fault = WorkerFault(
        FormatException('bad', _mnemonic).runtimeType.toString(),
      );
      _expectNoSecret(fault, [_mnemonic]);
      final error = WorkerTerminatedError(
        WorkerTerminationKind.uncaughtDartError,
        cause: fault,
      );
      _expectNoSecret(error, [_mnemonic]);
      expect(fault.toString(), contains('FormatException'));
    });
  });

  group('payload shape', () {
    test('WalletCreated carries a reference and nothing else', () {
      const reply = WalletCreated(1, walletRef: 7);
      expect(reply.walletRef, 7);
      expect(reply.toString(), 'WalletCreated(#1, wallet: 7)');
    });

    test('ImportWallet.entropy owns a copy, which overwriteOwnedSecrets '
        'zeroes', () {
      final callers = Uint8List.fromList(List<int>.filled(16, 0x5A));
      final request = ImportWallet.entropy(1, callers);
      expect(identical(request.entropy, callers), isFalse);
      callers[0] = 0;
      expect(request.entropy![0], 0x5A, reason: 'a copy, not a view');
      overwriteOwnedSecrets(request);
      expect(request.entropy, everyElement(0));
      expect(callers.skip(1), everyElement(0x5A), reason: 'caller untouched');
    });

    test('Init keeps an unmodifiable copy of the manifest bytes', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final init = Init(1, queueLimit: 4, manifestBytes: bytes);
      bytes[0] = 9;
      expect(init.manifestBytes, [1, 2, 3]);
      expect(() => init.manifestBytes![0] = 0, throwsUnsupportedError);
    });

    test('control messages are exactly DisposeRef, Cancel and Shutdown', () {
      final requests = <WorkerRequest>[
        Init(1, queueLimit: 1),
        const CreateWallet(2, strength: 128),
        const ImportWallet.mnemonic(3, _mnemonic),
        const ExportMnemonic(4, walletRef: 1),
        DeriveAddress(
          5,
          walletRef: 1,
          coin: Coin.ethereum,
          network: Network.mainnet,
          style: AddressStyle.standard,
        ),
        ValidateAddress(
          6,
          value: '0x',
          coin: Coin.ethereum,
          network: Network.mainnet,
        ),
        const ValidateMnemonic(7, _mnemonic),
        const ValidateMnemonicWord(8, 'word'),
        const SuggestMnemonicWords(9, 'wo'),
        const DisposeRef(10, walletRef: 1),
        const Cancel(11, target: 2),
        const Shutdown(12, grace: Duration(seconds: 1)),
      ];
      expect(
        [
          for (final r in requests)
            if (r.isControl) r.runtimeType,
        ],
        [DisposeRef, Cancel, Shutdown],
      );
      expect(
        [for (final r in requests) r.id],
        [for (var i = 1; i <= 12; i++) i],
      );
    });

    test('AddressDerived carries a descriptor with no key', () {
      final account = Account(
        coin: Coin.ethereum,
        network: Network.mainnet,
        addressStyle: AddressStyle.standard,
        derivationPath: "m/44'/60'/0'/0/0",
        address: validatedAddress(
          '0x9858EfFD232B4033E47d90003D41EC34EcaEda94',
          Coin.ethereum,
          Network.mainnet,
        ),
        publicKey: Uint8List(33),
      );
      final reply = AddressDerived(1, account);
      expect(reply.account, same(account));
      expect(
        reply.toString(),
        contains('0x9858EfFD232B4033E47d90003D41EC34EcaEda94'),
      );
    });
  });
}
