/// The Approach B core against the **standard** host library, which has no
/// adapter (T1.13, DECISION-1 evaluation): constructing the core is a typed
/// [NativeLoadError], and so is `Init` of a handler whose factory builds it —
/// nothing is signed and nothing is left to release.
///
/// Tagged `native` only: it runs in `melos run test:native`. Skips when the
/// host library is absent (`../../support/host_library.dart`), and when
/// `WCF_NATIVE_LIB` names a library that does export the adapter.
@Tags(['native'])
library;

import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/advanced.dart';
import 'package:wallet_core_flutter/src/errors/errors.dart';
import 'package:wallet_core_flutter/src/signing/adapter/adapter_signing_core.dart';
import 'package:wallet_core_flutter/src/worker/handler.dart';
import 'package:wallet_core_flutter/src/worker/protocol.dart';

import '../../support/host_library.dart';
import '../signing_support.dart';

void main() {
  String? skip = hostLibrarySkipReason();
  if (skip == null &&
      DynamicLibrary.open(findHostLibrary()!).providesSymbol(adapterSymbol)) {
    skip = 'WCF_NATIVE_LIB names a library that exports $adapterSymbol';
  }

  group('AdapterSigningCore over the standard library', skip: skip, () {
    test('construction is a NativeLoadError naming the symbol', () {
      final library = DynamicLibrary.open(findHostLibrary()!);
      final context = NativeContext(WalletCoreBindings(library));
      expect(
        () => AdapterSigningCore(context, library),
        throwsA(
          isA<NativeLoadError>().having(
            (e) => e.message,
            'message',
            contains(adapterSymbol),
          ),
        ),
      );
    });

    test('Init with the adapter factory fails with NativeLoadError and '
        'leaves no engine', () {
      final handler = EngineRequestHandler(signingCore: AdapterSigningCore.new);
      final reply = handler.handle(
        Init(
          1,
          queueLimit: 4,
          hostLibraryPath: findHostLibrary(),
          expectedIdentity: hostIdentity,
          sessionToken: 1,
        ),
      );
      expect(
        reply,
        isA<Failed>().having((r) => r.error, 'error', isA<NativeLoadError>()),
      );
      expect(handler.liveRefCount, 0);
      expect(handler.observer, isNull, reason: 'no engine was created');
    });
  });
}
