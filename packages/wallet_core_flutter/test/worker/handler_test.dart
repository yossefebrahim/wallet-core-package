// The engine-backed handler without a library: the error rule and the
// answers it gives before Init and after a failed one. No library needed.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/src/worker/handler.dart';
import 'package:wallet_core_flutter/src/worker/protocol.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';

void main() {
  test('before Init every operation is a typed SessionStateError', () {
    final handler = EngineRequestHandler();
    final reply = handler.handle(const CreateWallet(1, strength: 128));
    expect(
      reply,
      isA<Failed>().having(
        (r) => r.error,
        'error',
        isA<SessionStateError>()
            .having((e) => e.actual, 'actual', SessionState.initializing)
            .having((e) => e.attempted, 'attempted', 'createWallet'),
      ),
    );
    expect(handler.liveRefCount, 0);
    expect(handler.observer, isNull);
  });

  test('a library that cannot be loaded is a mapped NativeLoadError reply, '
      'and leaves nothing to release', () {
    final handler = EngineRequestHandler();
    final reply = handler.handle(
      Init(1, queueLimit: 1, hostLibraryPath: '/nonexistent/libWcf.dylib'),
    );
    expect(
      reply,
      isA<Failed>().having(
        (r) => r.error,
        'error',
        isA<NativeLoadError>().having(
          (e) => e.attempts.first.location,
          'first attempt',
          contains('/nonexistent/libWcf.dylib'),
        ),
      ),
    );
    expect(handler.liveRefCount, 0);
    expect(handler.releaseAll(), 0);
  });

  test('ImportWallet.entropy is overwritten once handled, even on failure', () {
    final handler = EngineRequestHandler();
    final request = ImportWallet.entropy(1, Uint8List(16)..fillRange(0, 16, 7));
    handler.handle(request);
    expect(request.entropy, everyElement(0));
  });
}
