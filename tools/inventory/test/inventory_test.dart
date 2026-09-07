import 'dart:convert';

import 'package:test/test.dart';
import 'package:wcf_tool_inventory/generated.dart';
import 'package:wcf_tool_inventory/headers.dart';
import 'package:wcf_tool_inventory/inventory.dart';
import 'package:wcf_tool_upstream/dist.dart';

final _headers = DistHeaders(
  archiveName: 'TrustWalletCore-4.8.0.tar.xz',
  archiveSha256: 'a' * 64,
  tag: '4.8.0',
  commit: 'd692ac27749d0c615e17c751b70ab4f0aa75c59b',
  fileCount: 143,
  dirSha256: 'b' * 64,
);

Inventory _build({
  List<String> declaredFunctions = const ['TWA', 'TWB', 'stringForHRP'],
  List<String> declaredEnums = const ['TWCurve'],
  List<String> boundFunctions = const ['TWA', 'TWB', 'stringForHRP'],
  List<String> boundEnums = const ['TWCurve'],
}) => buildInventory(
  headers: _headers,
  declared: HeaderSymbols(
    functions: declaredFunctions,
    enums: declaredEnums,
    fileCount: 143,
  ),
  bound: GeneratedSymbols(
    functions: boundFunctions,
    nonFunctionLookups: const [],
    enums: boundEnums,
  ),
  generatedPath: 'lib/src/generated/ffi/wallet_core_bindings.dart',
);

void main() {
  test('records where the headers came from', () {
    final json = _build().toJson();
    expect(json['headers'], equals(_headers.toJson()));
    expect(
      (json['headers']! as Map<String, Object?>)['archive'],
      equals('TrustWalletCore-4.8.0.tar.xz'),
    );
  });

  test('joins the two sets on name', () {
    final symbols = _build().toJson()['symbols']! as Map<String, Object?>;
    expect(
      symbols['TWA'],
      equals({'kind': 'function', 'in_headers': true, 'in_generated': true}),
    );
    expect(
      symbols['TWCurve'],
      equals({'kind': 'enum', 'in_headers': true, 'in_generated': true}),
    );
  });

  test('a declared symbol that is not bound is missing', () {
    final inventory = _build(boundFunctions: const ['TWA', 'stringForHRP']);
    expect(inventory.missing, equals(['TWB']));
    expect(
      (inventory.toJson()['counts']! as Map<String, Object?>)['functions'],
      equals({'in_headers': 3, 'in_generated': 2, 'missing': 1}),
    );
    expect(
      (inventory.toJson()['symbols']! as Map<String, Object?>)['TWB'],
      equals({'kind': 'function', 'in_headers': true, 'in_generated': false}),
    );
  });

  test('a bound symbol the headers do not declare is extra', () {
    final inventory = _build(
      boundFunctions: const ['TWA', 'TWB', 'stringForHRP', 'TWGhost'],
    );
    expect(inventory.extra, equals(['TWGhost']));
    expect(inventory.missing, isEmpty);
  });

  test('counts the TW-prefixed subset the export gate uses', () {
    expect(
      (_build().toJson()['counts']! as Map<String, Object?>)['exported_tw_'
          'functions'],
      equals(2),
    );
  });

  test('renders deterministically: two-space indent, trailing newline', () {
    final rendered = _build().render();
    expect(rendered, endsWith('}\n'));
    expect(rendered, equals(_build().render()));
    expect(jsonDecode(rendered), equals(_build().toJson()));
    // Order must not depend on the order the sets were built in.
    final reversed = _build(
      declaredFunctions: const ['stringForHRP', 'TWB', 'TWA'],
      boundFunctions: const ['stringForHRP', 'TWB', 'TWA'],
    );
    expect(reversed.render(), equals(rendered));
  });

  test('symbols are sorted, enums before functions', () {
    final keys = ((_build().toJson()['symbols']! as Map<String, Object?>).keys)
        .toList();
    expect(keys, equals(['TWCurve', 'TWA', 'TWB', 'stringForHRP']));
  });
}
