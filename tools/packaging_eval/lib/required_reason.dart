// The required-reason API scan (PRD §12.2 step 10).
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.
//
// Apple's privacy-manifest categories each name a list of APIs. A library that
// imports one of them makes the app that links it require a
// PrivacyInfo.xcprivacy declaring a reason. The list is data
// (lib/required_reason_apis.json) rather than code so it can be re-checked
// against Apple's page without reading Dart; the scan is `nm -u` — undefined
// symbols are the ones the library imports.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

/// One of Apple's categories and the names that identify it in a Mach-O.
class RequiredReasonCategory {
  const RequiredReasonCategory({
    required this.id,
    required this.name,
    required this.cSymbols,
    required this.objcClasses,
    required this.documentedApis,
  });

  final String id;
  final String name;
  final Set<String> cSymbols;
  final Set<String> objcClasses;
  final List<String> documentedApis;
}

/// The transcribed list, with its provenance.
class RequiredReasonApis {
  const RequiredReasonApis({
    required this.source,
    required this.transcribedOn,
    required this.categories,
  });

  /// The Apple documentation URL the list was transcribed from.
  final String source;

  /// The date of the transcription, ISO-8601.
  final String transcribedOn;

  final List<RequiredReasonCategory> categories;

  static RequiredReasonApis parse(String jsonText) {
    final json = jsonDecode(jsonText) as Map<String, Object?>;
    return RequiredReasonApis(
      source: json['source']! as String,
      transcribedOn: json['transcribed_on']! as String,
      categories: [
        for (final entry in (json['categories']! as List<Object?>))
          if (entry is Map<String, Object?>)
            RequiredReasonCategory(
              id: entry['id']! as String,
              name: entry['name']! as String,
              cSymbols: _stringSet(entry['c_symbols']),
              objcClasses: _stringSet(entry['objc_classes']),
              documentedApis: _stringSet(entry['documented_apis']).toList()
                ..sort(),
            ),
      ],
    );
  }

  /// Loads the committed list. Resolved through the package URI so it works
  /// from any working directory.
  static Future<RequiredReasonApis> load() async {
    final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:wcf_tool_packaging_eval/required_reason_apis.json'),
    );
    if (uri == null) {
      throw StateError(
        'could not resolve package:wcf_tool_packaging_eval/'
        'required_reason_apis.json; run through `dart run` inside the '
        'workspace',
      );
    }
    return parse(await File.fromUri(uri).readAsString());
  }

  static Set<String> _stringSet(Object? value) => {
    if (value is List<Object?>)
      for (final item in value)
        if (item is String) item,
  };
}

/// The names of one category found in a binary.
class CategoryHits {
  const CategoryHits({required this.category, required this.symbols});

  final RequiredReasonCategory category;

  /// The normalised names that matched, sorted.
  final List<String> symbols;

  bool get any => symbols.isNotEmpty;

  Map<String, Object?> toJson() => {
    'category': category.id,
    'name': category.name,
    'hits': symbols,
  };
}

/// Normalises one `nm -u` name to the API name Apple documents.
///
/// Mach-O C symbols carry a leading underscore, and libSystem exports several
/// spellings of the same call through `$`-suffixed variants
/// (`_stat$INODE64`); Objective-C class imports appear as
/// `_OBJC_CLASS_$_NSUserDefaults`.
String normaliseImportedSymbol(String raw) {
  var name = raw.trim();
  for (final prefix in const ['_OBJC_CLASS_\$_', '_OBJC_METACLASS_\$_']) {
    if (name.startsWith(prefix)) return name.substring(prefix.length);
  }
  if (name.startsWith('_')) name = name.substring(1);
  const variants = [
    '\$INODE64',
    '\$UNIX2003',
    '\$NOCANCEL',
    '\$DARWIN_EXTSN',
    '\$1050',
  ];
  for (final variant in variants) {
    if (name.endsWith(variant)) {
      name = name.substring(0, name.length - variant.length);
      break;
    }
  }
  return name;
}

/// Scans a set of `nm -u` names against every category.
List<CategoryHits> scanRequiredReasonApis(
  RequiredReasonApis apis,
  Iterable<String> undefinedSymbols,
) {
  final normalised = <String>{
    for (final symbol in undefinedSymbols) normaliseImportedSymbol(symbol),
  };
  return [
    for (final category in apis.categories)
      CategoryHits(
        category: category,
        symbols:
            normalised
                .where(
                  (n) =>
                      category.cSymbols.contains(n) ||
                      category.objcClasses.contains(n),
                )
                .toList()
              ..sort(),
      ),
  ];
}
