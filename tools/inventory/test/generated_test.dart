import 'dart:io';

import 'package:test/test.dart';
import 'package:wcf_tool_inventory/generated.dart';

/// ffigen output in miniature, including the multi-line type arguments
/// `dart format` produces for anything with more than one parameter.
const _generated = r'''
// GENERATED FILE — DO NOT EDIT.
import 'dart:ffi' as ffi;

class WalletCoreBindings {
  final ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName)
  _lookup;

  ffi.Pointer<TWAnyAddress> TWAnyAddressCreateWithString(
    ffi.Pointer<TWString> string,
    TWCoinType coin,
  ) {
    return _TWAnyAddressCreateWithString(string, coin.value);
  }

  late final _TWAnyAddressCreateWithStringPtr =
      _lookup<
        ffi.NativeFunction<
          ffi.Pointer<TWAnyAddress> Function(
            ffi.Pointer<TWString>,
            ffi.UnsignedInt,
          )
        >
      >('TWAnyAddressCreateWithString');

  late final _TWAnyAddressDeletePtr =
      _lookup<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<TWAnyAddress>)>>(
        'TWAnyAddressDelete',
      );

  late final _HRP_BITCOIN = _lookup<ffi.Pointer<ffi.Char>>('HRP_BITCOIN');
}

enum TWPurpose {
  TWPurposeBIP44(44);

  final int value;
  const TWPurpose(this.value);
}

enum TWCurve {
  TWCurveSECP256k1(0);

  final int value;
  const TWCurve(this.value);
}
''';

void main() {
  late File file;

  setUp(() {
    file = File(
      '${Directory.systemTemp.createTempSync('wcf-generated-').path}/b.dart',
    )..writeAsStringSync(_generated);
  });

  tearDown(() => file.parent.deleteSync(recursive: true));

  test('finds every symbol name, across line breaks in the type argument', () {
    expect(
      scanGenerated(file).functions,
      equals(['TWAnyAddressCreateWithString', 'TWAnyAddressDelete']),
    );
  });

  test('separates data lookups from function lookups', () {
    final bound = scanGenerated(file);
    expect(bound.nonFunctionLookups, equals(['HRP_BITCOIN']));
    expect(bound.functions, isNot(contains('HRP_BITCOIN')));
  });

  test('finds the enums, sorted', () {
    expect(scanGenerated(file).enums, equals(['TWCurve', 'TWPurpose']));
  });

  test('says what to run when the bindings are absent', () {
    expect(
      () => scanGenerated(File('${file.parent.path}/absent.dart')),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('gen:ffi'),
        ),
      ),
    );
  });

  test('refuses to guess at a malformed lookup', () {
    file.writeAsStringSync('final x = _lookup<ffi.Void>(notAStringLiteral);\n');
    expect(() => scanGenerated(file), throwsA(isA<FormatException>()));
  });
}
