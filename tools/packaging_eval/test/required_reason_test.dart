// Apple's required-reason API scan (PRD §12.2 step 10).
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.

import 'dart:io';

import 'package:test/test.dart';
import 'package:wcf_tool_packaging_eval/host.dart';
import 'package:wcf_tool_packaging_eval/macho.dart';
import 'package:wcf_tool_packaging_eval/proc.dart';
import 'package:wcf_tool_packaging_eval/required_reason.dart';

import 'fixtures.dart';

/// The five categories PRD §12.2 step 10 names.
const _expectedCategories = [
  'NSPrivacyAccessedAPICategoryFileTimestamp',
  'NSPrivacyAccessedAPICategorySystemBootTime',
  'NSPrivacyAccessedAPICategoryDiskSpace',
  'NSPrivacyAccessedAPICategoryActiveKeyboards',
  'NSPrivacyAccessedAPICategoryUserDefaults',
];

Map<String, List<String>> hitsById(List<CategoryHits> hits) => {
  for (final hit in hits) hit.category.id: hit.symbols,
};

void main() {
  group('required_reason_apis.json', () {
    late RequiredReasonApis apis;

    setUpAll(() async => apis = await RequiredReasonApis.load());

    test('carries its provenance: Apple URL and transcription date', () {
      expect(apis.source, startsWith('https://developer.apple.com/'));
      expect(apis.source, contains('required-reason-api'));
      expect(
        apis.transcribedOn,
        matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
        reason: 'ISO-8601, so a re-check knows how old the list is',
      );
    });

    test('has the five categories, each with names and documented APIs', () {
      expect(apis.categories.map((c) => c.id), _expectedCategories);
      for (final category in apis.categories) {
        expect(category.name, isNotEmpty, reason: category.id);
        expect(category.documentedApis, isNotEmpty, reason: category.id);
        expect(
          category.cSymbols.length + category.objcClasses.length,
          greaterThan(0),
          reason: '${category.id} matches nothing in a Mach-O',
        );
        expect(
          category.documentedApis,
          orderedEquals(category.documentedApis.toList()..sort()),
        );
      }
    });

    test(
      'the names it looks for are unprefixed, the way the scan sees them',
      () {
        for (final category in apis.categories) {
          for (final symbol in {
            ...category.cSymbols,
            ...category.objcClasses,
          }) {
            expect(
              symbol,
              isNot(startsWith('_')),
              reason: '${category.id}: the scan normalises before comparing',
            );
          }
        }
      },
    );

    test('parse rejects a listing without provenance', () {
      expect(
        () => RequiredReasonApis.parse('{"categories": []}'),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('normaliseImportedSymbol', () {
    test('strips the leading underscore of a Mach-O C symbol', () {
      expect(normaliseImportedSymbol('_stat'), 'stat');
      expect(normaliseImportedSymbol('  _fstatat  '), 'fstatat');
      expect(
        normaliseImportedSymbol('mach_absolute_time'),
        'mach_absolute_time',
      );
    });

    test('strips the libSystem variant suffixes it claims to', () {
      expect(normaliseImportedSymbol('_stat\$INODE64'), 'stat');
      expect(normaliseImportedSymbol('_open\$UNIX2003'), 'open');
      expect(normaliseImportedSymbol('_close\$NOCANCEL'), 'close');
      expect(
        normaliseImportedSymbol('_fgetattrlist\$DARWIN_EXTSN'),
        'fgetattrlist',
      );
      expect(normaliseImportedSymbol('_statfs\$1050'), 'statfs');
    });

    test('unwraps an Objective-C class or metaclass import', () {
      expect(
        normaliseImportedSymbol(r'_OBJC_CLASS_$_NSUserDefaults'),
        'NSUserDefaults',
      );
      expect(
        normaliseImportedSymbol(r'_OBJC_METACLASS_$_NSFileManager'),
        'NSFileManager',
      );
    });

    test('leaves a C++ mangled name alone apart from the underscore', () {
      expect(
        normaliseImportedSymbol('__ZNSt13runtime_errorD1Ev'),
        '_ZNSt13runtime_errorD1Ev',
      );
    });
  });

  group('scanRequiredReasonApis', () {
    late RequiredReasonApis apis;

    setUpAll(() async => apis = await RequiredReasonApis.load());

    test('the saved nm -u head of our dylib has no hit in it', () {
      // The fixture is the *first 60 lines* of `nm -u`, and nm sorts: the head
      // stops in the C++ mangled names, well before `_stat`. Zero hits here is
      // the correct answer for this input, not the answer for the library —
      // the whole-library scan below is the one that finds them.
      final names = parseNmNames(
        toolOutput('nm_u_relinked_ios_arm64_head.txt'),
      );
      expect(names, hasLength(60));
      final hits = scanRequiredReasonApis(apis, names);
      expect(hits.map((h) => h.category.id), _expectedCategories);
      for (final hit in hits) {
        expect(hit.symbols, isEmpty, reason: hit.category.id);
        expect(hit.any, isFalse);
      }
    });

    test('finds the file-timestamp and boot-time APIs in a name list', () {
      // The names the whole relinked iOS device dylib imports, in `nm -u`
      // spelling; the real-binary test below re-derives them from the file.
      const names = [
        '_fopen',
        '_fstat',
        '_fstatat',
        '_lstat',
        '_stat',
        '_mach_absolute_time',
        '_malloc',
      ];
      final hits = hitsById(scanRequiredReasonApis(apis, names));
      expect(hits['NSPrivacyAccessedAPICategoryFileTimestamp'], [
        'fstat',
        'fstatat',
        'lstat',
        'stat',
      ]);
      expect(hits['NSPrivacyAccessedAPICategorySystemBootTime'], [
        'mach_absolute_time',
      ]);
      expect(hits['NSPrivacyAccessedAPICategoryDiskSpace'], isEmpty);
      expect(hits['NSPrivacyAccessedAPICategoryActiveKeyboards'], isEmpty);
      expect(hits['NSPrivacyAccessedAPICategoryUserDefaults'], isEmpty);
    });

    test(
      'matches an Objective-C class import for the user-defaults category',
      () {
        final hits = hitsById(
          scanRequiredReasonApis(apis, [r'_OBJC_CLASS_$_NSUserDefaults']),
        );
        expect(hits['NSPrivacyAccessedAPICategoryUserDefaults'], [
          'NSUserDefaults',
        ]);
      },
    );

    test('a hit is reported once however many spellings imported it', () {
      final hits = hitsById(
        scanRequiredReasonApis(apis, ['_stat', '_stat\$INODE64', 'stat']),
      );
      expect(hits['NSPrivacyAccessedAPICategoryFileTimestamp'], ['stat']);
    });

    test('toJson names the category and its hits', () {
      final hit = scanRequiredReasonApis(apis, ['_stat']).first;
      expect(hit.toJson(), {
        'category': 'NSPrivacyAccessedAPICategoryFileTimestamp',
        'name': hit.category.name,
        'hits': ['stat'],
      });
    });

    test('scans the real relinked iOS device dylib when it is present', () {
      const artifact =
          'third_party/wcf-native-all/artifacts/ios/arm64/'
          'libTrustWalletCore.dylib';
      final path = '${repoRoot().path}/$artifact';
      if (!File(path).existsSync()) {
        markTestSkipped('no artifact set at $artifact');
        return;
      }
      final nm = run('nm', ['-u', '-arch', 'arm64', path]);
      if (!nm.ok) {
        markTestSkipped('nm is not available: ${nm.stderr.trim()}');
        return;
      }
      final hits = hitsById(
        scanRequiredReasonApis(apis, parseNmNames(nm.stdout)),
      );
      expect(hits['NSPrivacyAccessedAPICategoryFileTimestamp'], [
        'fstat',
        'fstatat',
        'lstat',
        'stat',
      ], reason: 'PrivacyInfo.xcprivacy is required for this library');
      expect(hits['NSPrivacyAccessedAPICategorySystemBootTime'], [
        'mach_absolute_time',
      ]);
      expect(hits['NSPrivacyAccessedAPICategoryUserDefaults'], isEmpty);
    });
  });
}
