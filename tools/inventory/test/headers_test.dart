import 'dart:io';

import 'package:test/test.dart';
import 'package:wcf_tool_inventory/headers.dart';

/// A header in upstream's own shape: the `TW_EXPORT_*` markers expand to
/// nothing or to `extern`, so what the scanner sees is a return type and a
/// name on one line.
const _header = '''
// SPDX-License-Identifier: Apache-2.0

#pragma once

#include "TWBase.h"

TW_EXTERN_C_BEGIN

TW_EXPORT_ENUM(uint32_t)
enum TWPurpose {
    TWPurposeBIP44 = 44,
};

struct TWAnyAddress;

/// Creates an address. Callers write TWAnyAddressCreateWithString(x) in prose
/// like this, and in \\code blocks, and it must not be counted.
TW_EXPORT_STATIC_METHOD
struct TWAnyAddress *_Nullable TWAnyAddressCreateWithString(TWString *s);

TW_EXPORT_METHOD void TWAnyAddressDelete(struct TWAnyAddress *address);

static const char *_Nonnull HRP_BITCOIN = "bc";

const char *_Nullable stringForHRP(enum TWHRP hrp);

TW_EXTERN_C_END
''';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('wcf-headers-');
    File('${root.path}/TWExample.h').writeAsStringSync(_header);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('takes declarations, in sorted order', () {
    final symbols = scanHeaders(root);
    expect(
      symbols.functions,
      equals([
        'TWAnyAddressCreateWithString',
        'TWAnyAddressDelete',
        'stringForHRP',
      ]),
    );
    expect(symbols.enums, equals(['TWPurpose']));
    expect(symbols.fileCount, equals(1));
  });

  test('does not take a name out of a comment or a macro body', () {
    // The prose line mentions TWAnyAddressCreateWithString mid-sentence; it is
    // counted once, from its declaration, not twice.
    expect(
      scanHeaders(
        root,
      ).functions.where((f) => f == 'TWAnyAddressCreateWithString'),
      hasLength(1),
    );
  });

  test('does not take a `static const char *` initialiser', () {
    expect(scanHeaders(root).functions, isNot(contains('HRP_BITCOIN')));
  });

  test('exportedTwFunctions is the TW-prefixed subset', () {
    final symbols = scanHeaders(root);
    expect(
      symbols.exportedTwFunctions,
      equals(['TWAnyAddressCreateWithString', 'TWAnyAddressDelete']),
    );
    expect(symbols.functions, contains('stringForHRP'));
    expect(symbols.exportedTwFunctions, isNot(contains('stringForHRP')));
  });

  test('reads only .h files', () {
    File(
      '${root.path}/notes.md',
    ).writeAsStringSync('void TWNotAFunction(void);\n');
    final symbols = scanHeaders(root);
    expect(symbols.fileCount, equals(1));
    expect(symbols.functions, isNot(contains('TWNotAFunction')));
  });

  test('explains how to place the headers when they are absent', () {
    expect(
      () => scanHeaders(Directory('${root.path}/absent')),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('upstream:fetch'),
        ),
      ),
    );
  });
}
