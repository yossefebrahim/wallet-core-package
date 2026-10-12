/// `withDerivedKeys` against the host library: one borrowed `PrivateKeyHandle`
/// per requested derivation, every handle disposed on the way out — on
/// success, on a throw from the callback, and when a later derivation fails —
/// and no key bytes anywhere in what it does.
///
/// Skips when the library is absent; `WCF_NATIVE_REQUIRED=1` turns that into
/// a failure (see `../support/host_library.dart`).
@Tags(['native'])
library;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/advanced.dart'
    show HDWallet, LeakTracker, NativeContext, TWDataHandle, TWCoinType;
import 'package:wallet_core_flutter/src/engine/handles.dart';
import 'package:wallet_core_flutter/src/engine/hd_wallet.dart'
    show KeyDerivation, withDerivedKeys;
import 'package:wallet_core_flutter/src/errors/errors.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart' show Coin;

import '../support/fixtures.dart';
import '../support/host_library.dart';

void main() {
  final skip = hostLibrarySkipReason();

  group('withDerivedKeys against the host library', skip: skip, () {
    late String mnemonic;
    late LeakTracker tracker;
    late NativeContext context;
    late HDWallet wallet;

    const path0 = "m/44'/60'/0'/0/0";
    const path1 = "m/44'/60'/0'/0/1";

    setUpAll(() {
      mnemonic =
          (vectorById(loadInventory(), 'ethereum-address-n/a-1').input
                  as Map)['mnemonic']
              as String;
    });

    setUp(() {
      tracker = LeakTracker.maybeCreate()!;
      context = NativeContext(openHostBindings(), observer: tracker);
      wallet = HDWallet.fromMnemonic(context, mnemonic);
    });

    tearDown(() {
      wallet.dispose();
      final report = tracker.report;
      expect(report.live, 0, reason: '$report');
      expect(report.finalizedWithoutDispose, 0, reason: '$report');
      tracker.stop();
    });

    /// The public key bytes of [key], read through the bindings.
    List<int> publicKeyOf(PrivateKeyHandle key) {
      final bindings = context.bindings;
      final publicKey = bindings.TWPrivateKeyGetPublicKey(
        key.pointer,
        TWCoinType.TWCoinTypeEthereum,
      );
      final data = TWDataHandle.adopt(
        context,
        bindings.TWPublicKeyData(publicKey),
      );
      try {
        return data.copyBytes();
      } finally {
        data.dispose();
        bindings.TWPublicKeyDelete(publicKey);
      }
    }

    test('lends one handle per entry, in order, for the right path; every '
        'handle is disposed when it returns', () {
      late List<PrivateKeyHandle> lent;
      late List<List<int>> publicKeys;
      final result = withDerivedKeys(
        {
          'a': KeyDerivation(wallet, Coin.ethereum, path0),
          'b': KeyDerivation(wallet, Coin.ethereum, path1),
          'c': KeyDerivation(wallet, Coin.ethereum, path0),
        },
        (keys) {
          expect(keys.keys, ['a', 'b', 'c']);
          lent = keys.values.toList();
          publicKeys = [for (final key in lent) publicKeyOf(key)];
          for (final key in lent) {
            expect(key.isDisposed, isFalse);
          }
          return 42;
        },
      );
      expect(result, 42);
      expect(listEquals(publicKeys[0], publicKeys[2]), isTrue);
      expect(listEquals(publicKeys[0], publicKeys[1]), isFalse);
      for (final key in lent) {
        expect(key.isDisposed, isTrue);
      }
    });

    test('the map handed to the callback is unmodifiable', () {
      withDerivedKeys({'a': KeyDerivation(wallet, Coin.ethereum, path0)}, (
        keys,
      ) {
        expect(() => keys.remove('a'), throwsUnsupportedError);
      });
    });

    test('a throw from the callback disposes every handle and propagates', () {
      late List<PrivateKeyHandle> lent;
      expect(
        () => withDerivedKeys(
          {
            'a': KeyDerivation(wallet, Coin.ethereum, path0),
            'b': KeyDerivation(wallet, Coin.ethereum, path1),
          },
          (keys) {
            lent = keys.values.toList();
            throw StateError('the callback fails');
          },
        ),
        throwsStateError,
      );
      for (final key in lent) {
        expect(key.isDisposed, isTrue);
      }
    });

    test('a derivation that fails after others succeeded disposes those, and '
        'never calls the callback', () {
      var called = false;
      final before = tracker.report;
      expect(
        () => withDerivedKeys(
          {
            'a': KeyDerivation(wallet, Coin.ethereum, path0),
            'b': KeyDerivation(wallet, Coin.ethereum, 'm/not/a/path'),
          },
          (keys) {
            called = true;
          },
        ),
        throwsA(
          isA<InvalidInputError>().having(
            (e) => e.inputName,
            'inputName',
            'derivationPath',
          ),
        ),
      );
      expect(called, isFalse);
      final after = tracker.report;
      expect(after.live, before.live, reason: '$after');
      expect(
        after.disposed - before.disposed,
        greaterThanOrEqualTo(2),
        reason: 'the first key and the path strings were released',
      );
    });

    test('a disposed wallet is DisposedError, before any key is derived', () {
      final other = HDWallet.fromMnemonic(context, mnemonic);
      other.dispose();
      final before = tracker.report.disposed;
      expect(
        () => withDerivedKeys({
          'a': KeyDerivation(wallet, Coin.ethereum, path0),
          'b': KeyDerivation(other, Coin.ethereum, path1),
        }, (keys) => fail('the callback must not run')),
        throwsA(isA<DisposedError>()),
      );
      expect(tracker.report.disposed, before, reason: 'nothing was derived');
    });

    test('an empty request is an ArgumentError; wallets of different contexts '
        'are a StateError', () {
      expect(
        () => withDerivedKeys(
          <String, KeyDerivation>{},
          (keys) => fail('the callback must not run'),
        ),
        throwsArgumentError,
      );
      final otherContext = NativeContext(openHostBindings());
      final foreign = HDWallet.fromMnemonic(otherContext, mnemonic);
      try {
        expect(
          () => withDerivedKeys({
            'a': KeyDerivation(wallet, Coin.ethereum, path0),
            'b': KeyDerivation(foreign, Coin.ethereum, path0),
          }, (keys) => fail('the callback must not run')),
          throwsStateError,
        );
      } finally {
        foreign.dispose();
      }
    });

    test('no key bytes are read: no TWData is created for a key', () {
      final before = tracker.report.disposed;
      withDerivedKeys({'a': KeyDerivation(wallet, Coin.ethereum, path0)}, (
        keys,
      ) {
        // Only the path string exists besides the key itself.
        expect(tracker.report.disposed, before);
      });
      // The path string and the key: two disposals, no TWData for key bytes.
      expect(tracker.report.disposed - before, 2);
      expect(
        tracker.report.liveByType.keys.toSet().difference({'HDWallet'}),
        isEmpty,
      );
    });
  });
}
