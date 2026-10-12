/// The SDK's `isNativeSafeString` and the bindings' `TWStringHandle.fromString`
/// apply the same predicate (a private copy in the bindings, since their barrel
/// does not export it). This holds the two to one table of inputs: whatever the
/// SDK calls unsafe, the bindings refuse with `ArgumentError`, and whatever it
/// calls safe, the bindings carry to upstream and back unchanged.
///
/// The bindings' own table, in `tw_string_handle_test.dart` there, is the same
/// list of strings.
///
/// Skips when the library is absent; `WCF_NATIVE_REQUIRED=1` turns that into
/// a failure (see `../support/host_library.dart`).
@Tags(['native'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/advanced.dart';
import 'package:wallet_core_flutter/src/core/input_checks.dart';

import '../support/host_library.dart';

const Map<String, String> _unsafe = <String, String>{
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

const Map<String, String> _safe = <String, String>{
  'the empty string': '',
  'plain ASCII': 'abandon abandon about',
  'a paired surrogate (U+1F512)': 'wallet \u{1F512} ok',
  'the lowest and highest pair': '\u{10000}\u{10FFFF}',
  'BMP text next to the surrogate range': '퟿',
  'non-ASCII': 'café — 日本語 — Ω',
};

void main() {
  final skip = hostLibrarySkipReason();

  group(
    'isNativeSafeString and TWStringHandle.fromString agree',
    skip: skip,
    () {
      late NativeContext context;

      setUpAll(() => context = NativeContext(openHostBindings()));

      for (final entry in _unsafe.entries) {
        test('both refuse ${entry.key}', () {
          expect(isNativeSafeString(entry.value), isFalse);
          expect(
            () => TWStringHandle.fromString(context, entry.value),
            throwsArgumentError,
          );
        });
      }

      for (final entry in _safe.entries) {
        test('both accept ${entry.key}', () {
          expect(isNativeSafeString(entry.value), isTrue);
          final handle = TWStringHandle.fromString(context, entry.value);
          addTearDown(handle.dispose);
          expect(handle.toDartString(), entry.value);
        });
      }
    },
  );
}
