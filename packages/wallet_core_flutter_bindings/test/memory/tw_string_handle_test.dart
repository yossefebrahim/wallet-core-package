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
      // What is asserted is that the size upstream reports and the text we
      // decode agree: a `strlen` over the returned buffer would be a second,
      // independent answer, and this wrapper never asks for one.
      const value = 'before\u{1F512}after';
      final handle = TWStringHandle.fromString(context, value);
      addTearDown(handle.dispose);

      expect(handle.toDartString(), value);
      expect(handle.length, utf8.encode(value).length);
    });

    group('fromString refuses a string that would reach native code '
        'changed', () {
      // The same table the SDK's `isNativeSafeString` is held to in
      // `wallet_core_flutter/test/core/native_safe_string_agreement_native_test.dart`.
      const rejected = <String, String>{
        'an embedded NUL': 'ab\u0000cd',
        'a leading NUL': '\u0000abc',
        'a trailing NUL': 'abc\u0000',
        'only a NUL': '\u0000',
        'a lone high surrogate': 'a\uD800b',
        'a high surrogate at the end': 'abc\uD83D',
        'a lone low surrogate': 'a\uDC00b',
        'a low surrogate at the start': '\uDE00abc',
        'two high surrogates in a row': '\uD83D😀',
        'a reversed pair': '\uDE00\uD83D',
      };
      const accepted = <String, String>{
        'the empty string': '',
        'plain ASCII': 'abandon abandon about',
        'a paired surrogate (U+1F512)': 'wallet \u{1F512} ok',
        'the lowest and highest pair': '\u{10000}\u{10FFFF}',
        'BMP text next to the surrogate range': '퟿',
        'non-ASCII': 'café — 日本語 — Ω',
      };

      for (final entry in rejected.entries) {
        test('rejects ${entry.key}, quoting nothing, creating nothing', () {
          final observer = RecordingObserver();
          final scoped = NativeContext(context.bindings, observer: observer);

          expect(
            () => TWStringHandle.fromString(scoped, entry.value),
            throwsA(
              isA<ArgumentError>()
                  .having((e) => e.name, 'name', 'value')
                  .having((e) => '$e', 'message', isNot(contains('abc'))),
            ),
          );
          expect(observer.created, isEmpty, reason: 'no handle was made');
        });
      }

      for (final entry in accepted.entries) {
        test('accepts ${entry.key}, and it reads back unchanged', () {
          final handle = TWStringHandle.fromString(context, entry.value);
          addTearDown(handle.dispose);

          expect(handle.toDartString(), entry.value);
        });
      }

      test('withTWString refuses before running its body', () {
        var ran = false;
        expect(
          () => withTWString<void>(context, 'a\u0000b', (_) => ran = true),
          throwsArgumentError,
        );
        expect(ran, isFalse);
      });
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
