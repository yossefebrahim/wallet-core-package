import 'dart:io';

import 'package:test/test.dart';
import 'package:wcf_tool_inventory/headers.dart';
import 'package:wcf_tool_upstream/dist.dart';

/// `tools/native_build/generate_symbol_list.sh`, relative to this package.
const _script = '../native_build/generate_symbol_list.sh';

/// The release-asset headers, relative to this package. Present only after
/// `melos run upstream:fetch -- --dist-only --from-dist <asset>`; the
/// hermetic test below does not need them.
const _distHeaders = '../../$defaultDistDestination/$distHeadersSubdirectory';

/// Awkward cases on purpose: a name mentioned in prose, a `static const char *`
/// initialiser, a non-`TW` declaration, a multi-word return type, and a
/// pointer return with nullability annotations.
const _fixture = '''
// SPDX-License-Identifier: Apache-2.0
#pragma once
#include "TWBase.h"

TW_EXTERN_C_BEGIN

TW_EXPORT_ENUM(uint32_t)
enum TWCurve {
    TWCurveSECP256k1 = 0,
};

/// Prose that names TWStoredKeyLoad(path) must not be counted.
TW_EXPORT_STATIC_METHOD
struct TWStoredKey *_Nullable TWStoredKeyLoad(TWString *_Nonnull path);

TW_EXPORT_METHOD void TWStoredKeyDelete(struct TWStoredKey *_Nonnull key);

TW_EXPORT_STATIC_PROPERTY unsigned long long TWHDWalletSeedSize(void);

static const char *_Nonnull HRP_BITCOIN = "bc";

const char *_Nullable stringForHRP(enum TWHRP hrp);

TW_EXTERN_C_END
''';

List<String> _runScript(String headers) {
  final result = Process.runSync(_script, ['--headers', headers]);
  if (result.exitCode != 0) {
    fail('$_script failed (${result.exitCode}): ${result.stderr}');
  }
  return (result.stdout as String)
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}

void main() {
  // The bindings must bind what the artifact exports. Both facts come from a
  // symbol list extracted from the same headers — this tool's, and the shell
  // script that feeds the linker's `-u` list and the export gate. If the two
  // extractions disagreed, one of the two gates would be measuring a set that
  // does not exist.
  group('agrees with tools/native_build/generate_symbol_list.sh', () {
    test('on a fixture built for the awkward cases', () {
      final root = Directory.systemTemp.createTempSync('wcf-agreement-');
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/TWFixture.h').writeAsStringSync(_fixture);

      expect(
        scanHeaders(root).exportedTwFunctions,
        equals(_runScript(root.path)),
      );
      expect(
        scanHeaders(root).exportedTwFunctions,
        equals(['TWHDWalletSeedSize', 'TWStoredKeyDelete', 'TWStoredKeyLoad']),
      );
    });

    test(
      'on the pinned release-asset headers',
      () {
        final symbols = scanHeaders(Directory(_distHeaders));
        expect(symbols.fileCount, equals(143));
        expect(symbols.exportedTwFunctions, equals(_runScript(_distHeaders)));
        expect(symbols.exportedTwFunctions, hasLength(464));
        expect(symbols.enums, hasLength(19));
      },
      skip: Directory(_distHeaders).existsSync()
          ? false
          : 'needs `melos run upstream:fetch -- --dist-only --from-dist '
                '<TrustWalletCore-<tag>.tar.xz>`',
    );
  });
}
