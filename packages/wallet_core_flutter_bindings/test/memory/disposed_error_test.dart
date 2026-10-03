/// The parts of the memory contract that need no native library: the error
/// vocabulary and the length ceiling.
///
/// Deliberately untagged, so it runs under `melos run test` on a machine that
/// has never built the host library.
library;

import 'package:test/test.dart';
import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart';

void main() {
  group('DisposedError', () {
    test('names the resource type', () {
      final error = DisposedError('TWDataHandle');

      expect(error.resourceType, 'TWDataHandle');
      expect(error.toString(), contains('TWDataHandle'));
      expect(error.toString(), startsWith('DisposedError'));
    });

    test('carries a message and never any content (TM-09, TM-31)', () {
      final error = DisposedError(
        'TWStringHandle',
        'copyBytes() after '
            'dispose()',
      );

      expect(error.message, contains('copyBytes()'));
      expect(
        error.toString(),
        'DisposedError: TWStringHandle copyBytes() '
        'after dispose()',
      );
    });

    test('is an Error, because using a disposed handle is a defect', () {
      expect(DisposedError('X'), isA<Error>());
    });
  });

  group('checkNativeLength (TM-17)', () {
    test('accepts 0 and the documented maximum', () {
      expect(
        checkNativeLength(0, resourceType: 'TWDataHandle', what: 'a size'),
        0,
      );
      expect(
        checkNativeLength(
          maxNativeBufferBytes,
          resourceType: 'TWDataHandle',
          what: 'a size',
        ),
        maxNativeBufferBytes,
      );
    });

    test('rejects a negative length — a size_t above 2^63 arrives here as a '
        'negative Dart int', () {
      expect(
        () => checkNativeLength(-1, resourceType: 'X', what: 'a size'),
        throwsA(isA<RangeError>()),
      );
    });

    test('rejects a length above the documented maximum', () {
      expect(
        () => checkNativeLength(
          maxNativeBufferBytes + 1,
          resourceType: 'X',
          what: 'a size',
        ),
        throwsA(isA<RangeError>()),
      );
    });

    test('the maximum is 64 MiB', () {
      expect(maxNativeBufferBytes, 64 * 1024 * 1024);
    });
  });
}
