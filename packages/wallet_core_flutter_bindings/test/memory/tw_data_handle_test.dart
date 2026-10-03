/// `TWDataHandle` against the real host library: bytes in, bytes out, and the
/// boundary checks of threat model TM-17, TM-19 and TM-20.
@Tags(['native'])
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart';

import '../support/host_library.dart';
import '../support/observers.dart';

void main() {
  final skip = hostLibrarySkipReason();

  group('TWDataHandle', skip: skip, () {
    late NativeContext context;

    setUp(() {
      context = NativeContext(openHostBindings());
    });

    test('round trip: the bytes copied in are the bytes that come back', () {
      final bytes = Uint8List.fromList(
        List<int>.generate(512, (index) => index % 256),
      );
      final handle = TWDataHandle.fromBytes(context, bytes);
      addTearDown(handle.dispose);

      expect(handle.length, bytes.length);
      expect(handle.copyBytes(), bytes);
      // Upstream's own comparison, so the assertion is on what the library
      // sees in its buffer rather than only on what we copied back.
      final same = TWDataHandle.fromBytes(context, bytes);
      addTearDown(same.dispose);
      expect(
        context.bindings.TWDataEqual(handle.pointer, same.pointer),
        isTrue,
      );
    });

    test('round trip: an empty TWData is empty, not null', () {
      final handle = TWDataHandle.fromBytes(context, Uint8List(0));
      addTearDown(handle.dispose);

      expect(handle.length, 0);
      expect(handle.copyBytes(), isEmpty);
    });

    test('copyBytes() returns a copy, not a view over native memory', () {
      final handle = TWDataHandle.fromBytes(
        context,
        Uint8List.fromList([1, 2, 3]),
      );
      final copy = handle.copyBytes();
      handle.dispose();

      // Reading the copy after the native buffer was freed is safe precisely
      // because it is a copy.
      expect(copy, [1, 2, 3]);
    });

    test('two copyBytes() calls return independent lists', () {
      final handle = TWDataHandle.fromBytes(
        context,
        Uint8List.fromList([9, 9]),
      );
      addTearDown(handle.dispose);

      final first = handle.copyBytes();
      final second = handle.copyBytes();
      first[0] = 0;

      expect(second, [9, 9]);
    });

    test('adopt() takes a pointer upstream returned to us', () {
      final source = TWDataHandle.fromBytes(
        context,
        Uint8List.fromList([4, 5, 6]),
      );
      addTearDown(source.dispose);

      // A genuine upstream allocation: TWDataCreateWithData hands back a new
      // TWData that somebody has to delete.
      final adopted = TWDataHandle.adopt(
        context,
        context.bindings.TWDataCreateWithData(source.pointer),
      );

      expect(adopted.copyBytes(), [4, 5, 6]);
      adopted.dispose();
      expect(adopted.isDisposed, isTrue);
    });

    test('adopt(nullptr) throws ArgumentError — a null is a failure signal, '
        'never a wrapper (TM-20)', () {
      expect(
        () => TWDataHandle.adopt(context, nullptr),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('copyBytes() after dispose() throws DisposedError', () {
      final handle = TWDataHandle.fromBytes(
        context,
        Uint8List.fromList([1, 2, 3]),
      );
      handle.dispose();

      expect(handle.copyBytes, throwsA(isA<DisposedError>()));
    });

    test('dispose() twice is fine', () {
      final handle = TWDataHandle.fromBytes(context, Uint8List.fromList([1]));

      handle.dispose();
      expect(handle.dispose, returnsNormally);
      expect(handle.isDisposed, isTrue);
    });

    test('a length over the documented maximum is rejected before anything is '
        'allocated (TM-17)', () {
      expect(
        () => checkNativeLength(
          maxNativeBufferBytes + 1,
          resourceType: 'TWDataHandle',
          what: 'a hostile size',
        ),
        throwsA(isA<RangeError>()),
      );
      expect(
        () => checkNativeLength(
          -1,
          resourceType: 'TWDataHandle',
          what: 'a size_t that arrived negative',
        ),
        throwsA(isA<RangeError>()),
      );
    });

    test('withTWData disposes the handle when the body returns', () {
      final observer = RecordingObserver();
      final scoped = NativeContext(context.bindings, observer: observer);

      final length = withTWData<int>(
        scoped,
        Uint8List.fromList([1, 2, 3, 4]),
        (data) => data.length,
      );

      expect(length, 4);
      expect(observer.created.single.isDisposed, isTrue);
    });

    test('withTWData disposes the handle when the body throws', () {
      final observer = RecordingObserver();
      final scoped = NativeContext(context.bindings, observer: observer);
      late TWDataHandle escaped;

      expect(
        () => withTWData<void>(scoped, Uint8List.fromList([1]), (data) {
          escaped = data;
          throw StateError('body failed');
        }),
        throwsStateError,
      );

      expect(escaped.isDisposed, isTrue);
      expect(observer.disposed, [escaped]);
    });
  });
}
