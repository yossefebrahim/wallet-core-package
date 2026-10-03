/// `TWStringHandle` against the real host library: UTF-8 in, UTF-8 out, and
/// the boundary checks of threat model TM-17 and TM-20.
@Tags(['native'])
library;

import 'dart:convert';
import 'dart:ffi';

import 'package:test/test.dart';
import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart';

import '../support/host_library.dart';
import '../support/observers.dart';

void main() {
  final skip = hostLibrarySkipReason();

  group('TWStringHandle', skip: skip, () {
    late NativeContext context;

    setUp(() {
      context = NativeContext(openHostBindings());
    });

    test('round trip: a UTF-8 string with non-ASCII comes back unchanged', () {
      const value = 'café — 日本語 — 🪙 — Ω';
      final handle = TWStringHandle.fromString(context, value);
      addTearDown(handle.dispose);

      expect(handle.toDartString(), value);
      expect(handle.length, utf8.encode(value).length);
      expect(
        handle.length,
        greaterThan(value.length),
        reason: 'the length is bytes, not code units',
      );

      final same = TWStringHandle.fromString(context, value);
      addTearDown(same.dispose);
      expect(
        context.bindings.TWStringEqual(handle.pointer, same.pointer),
        isTrue,
      );
    });

    test('round trip: the empty string', () {
      final handle = TWStringHandle.fromString(context, '');
      addTearDown(handle.dispose);

      expect(handle.length, 0);
      expect(handle.toDartString(), isEmpty);
    });

    test('the size comes from TWStringSize, not from a terminator search', () {
      // `TWStringCreateWithUTF8Bytes` reads a NUL-terminated buffer, so a
      // string containing a NUL is stored as its prefix. What is asserted is
      // that the size upstream reports and the text we decode agree: a
      // `strlen` over the returned buffer would be a second, independent
      // answer, and this wrapper never asks for one.
      final value = 'before${String.fromCharCode(0)}after';
      final handle = TWStringHandle.fromString(context, value);
      addTearDown(handle.dispose);

      expect(handle.toDartString(), 'before');
      expect(handle.length, 6);
      expect(handle.length, utf8.encode(handle.toDartString()).length);
    });

    test('adopt() takes a pointer upstream returned to us', () {
      // A real upstream allocation: TWCoinTypeConfigurationGetSymbol builds a
      // TWString out of the library's own registry, and the caller deletes it.
      final adopted = TWStringHandle.adopt(
        context,
        context.bindings.TWCoinTypeConfigurationGetSymbol(
          TWCoinType.TWCoinTypeEthereum,
        ),
      );

      expect(adopted.toDartString(), 'ETH');
      adopted.dispose();
      expect(adopted.isDisposed, isTrue);
    });

    test('adopt(nullptr) throws ArgumentError (TM-20)', () {
      expect(
        () => TWStringHandle.adopt(context, nullptr),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('toDartString() after dispose() throws DisposedError', () {
      final handle = TWStringHandle.fromString(context, 'value');
      handle.dispose();

      expect(handle.toDartString, throwsA(isA<DisposedError>()));
    });

    test('dispose() twice is fine', () {
      final handle = TWStringHandle.fromString(context, 'value');

      handle.dispose();
      expect(handle.dispose, returnsNormally);
      expect(handle.isDisposed, isTrue);
    });

    test('withTWString disposes the handle when the body returns', () {
      final observer = RecordingObserver();
      final scoped = NativeContext(context.bindings, observer: observer);

      final text = withTWString<String>(
        scoped,
        'hello',
        (string) => string.toDartString(),
      );

      expect(text, 'hello');
      expect(observer.created.single.isDisposed, isTrue);
    });

    test('withTWString disposes the handle when the body throws', () {
      final observer = RecordingObserver();
      final scoped = NativeContext(context.bindings, observer: observer);
      late TWStringHandle escaped;

      expect(
        () => withTWString<void>(scoped, 'hello', (string) {
          escaped = string;
          throw StateError('body failed');
        }),
        throwsStateError,
      );

      expect(escaped.isDisposed, isTrue);
      expect(observer.disposed, [escaped]);
    });
  });
}
