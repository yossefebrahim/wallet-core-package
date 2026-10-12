/// The disposal contract (PRD §11.2 items 1–3) on each engine handle type,
/// directly: `dispose()` releases the native object once, a second `dispose()`
/// is a no-op, and any use afterwards is `DisposedError`. Against the real host
/// library, with a counting observer so "once" is observed.
///
/// Skips when the library is absent; `WCF_NATIVE_REQUIRED=1` turns that into
/// a failure (see `../support/host_library.dart`).
@Tags(['native'])
library;

import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/advanced.dart';
import 'package:wallet_core_flutter/src/engine/handles.dart';
import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart'
    as wcfb
    show DisposedError;

import '../support/host_library.dart';

/// Records creations and disposals; never reads a handle's contents.
final class _Counting implements ResourceObserver {
  final List<NativeResource> created = <NativeResource>[];
  final List<NativeResource> disposed = <NativeResource>[];

  @override
  void onResourceCreated(NativeResource resource) => created.add(resource);

  @override
  void onResourceDisposed(NativeResource resource) => disposed.add(resource);
}

void main() {
  final skip = hostLibrarySkipReason();

  group('engine handles, direct disposal', skip: skip, () {
    late WalletCoreBindings bindings;
    late _Counting observer;
    late NativeContext context;

    setUpAll(() => bindings = openHostBindings());

    setUp(() {
      observer = _Counting();
      context = NativeContext(bindings, observer: observer);
    });

    /// A fresh upstream key, owned by the caller of this function.
    PrivateKeyHandle newPrivateKey() =>
        PrivateKeyHandle.adopt(context, bindings.TWPrivateKeyCreate());

    PublicKeyHandle newPublicKey() {
      final key = newPrivateKey();
      try {
        return PublicKeyHandle.adopt(
          context,
          bindings.TWPrivateKeyGetPublicKeySecp256k1(key.pointer, true),
        );
      } finally {
        key.dispose();
      }
    }

    AnyAddressHandle newAnyAddress() => withTWString(
      context,
      '0xB9F5771C27664bF2282D98E09D7F50cEc7cB01a7',
      (string) => AnyAddressHandle.adopt(
        context,
        bindings.TWAnyAddressCreateWithString(
          string.pointer,
          TWCoinType.TWCoinTypeEthereum,
        ),
      ),
    );

    // The closures read `context` when a test calls them, not now.
    final cases = <String, NativeResource Function()>{
      'PrivateKeyHandle': newPrivateKey,
      'PublicKeyHandle': newPublicKey,
      'AnyAddressHandle': newAnyAddress,
    };

    for (final name in [
      'PrivateKeyHandle',
      'PublicKeyHandle',
      'AnyAddressHandle',
    ]) {
      test('$name: dispose() releases once, a second dispose() is a no-op, '
          'and use afterwards is DisposedError', () {
        final handle = cases[name]!();
        final before = observer.disposed.length;
        expect(handle.isDisposed, isFalse);
        expect(handle.isFinalizerAttached, isTrue);
        expect(handle.rawPointer, isNot(nullptr), reason: 'usable while live');

        handle.dispose();

        expect(handle.isDisposed, isTrue);
        expect(handle.isFinalizerAttached, isFalse);
        expect(observer.disposed.length, before + 1);
        expect(observer.disposed.last, same(handle));

        handle.dispose();
        handle.dispose();
        expect(
          observer.disposed.length,
          before + 1,
          reason: 'a second dispose() is not notified or released again',
        );

        expect(() => handle.rawPointer, throwsA(isA<wcfb.DisposedError>()));
        expect(handle.checkNotDisposed, throwsA(isA<wcfb.DisposedError>()));
        expect(
          () => switch (handle) {
            final PrivateKeyHandle h => h.pointer,
            final PublicKeyHandle h => h.pointer,
            final AnyAddressHandle h => h.pointer,
            _ => throw StateError('unexpected handle type'),
          },
          throwsA(isA<wcfb.DisposedError>()),
        );
        expect(handle.toString(), '$name(disposed: true)');
      });

      test('$name: adopt(nullptr) is an ArgumentError, never a wrapped '
          'null', () {
        expect(
          () => switch (name) {
            'PrivateKeyHandle' => PrivateKeyHandle.adopt(context, nullptr),
            'PublicKeyHandle' => PublicKeyHandle.adopt(context, nullptr),
            _ => AnyAddressHandle.adopt(context, nullptr),
          },
          throwsArgumentError,
        );
      });
    }
  });
}
