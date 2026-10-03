import 'package:test/test.dart';
import 'package:wcf_tool_lint/public_api_lint.dart';

/// Lints the fixture whose entry is `test/fixtures/<name>/lib/<name>.dart`.
Future<LintResult> lintFixture(String name, {String? entry}) => checkPublicApi(
  packageRoot: '.',
  entryPoint: 'test/fixtures/$name/lib/${entry ?? name}.dart',
);

/// Lints an entry of the deliberately broken `diagnostics` fixture, which has
/// its own analysis options so it is analyzed when used as the package root.
Future<LintResult> lintDiagnostics(String entry) => checkPublicApi(
  packageRoot: 'test/fixtures/diagnostics',
  entryPoint: 'lib/$entry.dart',
);

Matcher violation({
  required String rule,
  String? element,
  String? member,
  String? type,
}) => predicate<Violation>(
  (v) =>
      v.rule == rule &&
      (element == null || v.elementName == element) &&
      (member == null || v.memberName == member) &&
      (type == null || v.typeString == type),
  'violation $rule ${element ?? '*'}.${member ?? '*'} ${type ?? ''}',
);

Matcher throwsUnresolved(String fragment) => throwsA(
  isA<PublicApiLintException>().having(
    (e) => e.message,
    'message',
    contains(fragment),
  ),
);

void main() {
  test('clean surface', () async {
    final result = await lintFixture('clean');
    expect(result.violations, isEmpty);
    expect(result.checkedElements, 1);
  });

  test('Pointer return type', () async {
    final result = await lintFixture('pointer_return');
    expect(
      result.violations,
      contains(
        violation(rule: 'ffi', element: 'BadClass', member: 'getPointer'),
      ),
    );
  });

  test('ffi type as a type argument', () async {
    final result = await lintFixture('ffi_type_arg');
    expect(
      result.violations,
      contains(
        violation(rule: 'ffi', member: 'pointers', type: 'Pointer<Void>'),
      ),
    );
  });

  test('ffi type in a function-typed parameter', () async {
    final result = await lintFixture('ffi_function_param');
    expect(
      result.violations,
      contains(violation(rule: 'ffi', element: 'doSomething')),
    );
  });

  test('type from src/generated/ re-exported', () async {
    final result = await lintFixture('generated_export');
    expect(
      result.violations,
      contains(
        violation(rule: 'generated', element: 'GeneratedType', member: 'self'),
      ),
    );
  });

  test('type from src/generated/ used as a supertype', () async {
    final result = await lintFixture('generated_supertype');
    expect(
      result.violations,
      contains(
        violation(rule: 'generated', element: 'MyClass', member: 'supertype'),
      ),
    );
  });

  test('private Pointer field in an exported class', () async {
    final result = await lintFixture('private_pointer_field');
    expect(
      result.violations,
      contains(violation(rule: 'pointer-field', member: '_ptr')),
    );
    // A private member is not a public signature.
    expect(result.violations, isNot(contains(violation(rule: 'ffi'))));
  });

  test('private Pointer field inherited from a non-exported base', () async {
    final result = await lintFixture('private_inherited_pointer_field');
    expect(
      result.violations,
      containsAll([
        violation(
          rule: 'pointer-field',
          element: 'Exported',
          member: '_handle',
        ),
        // Field type known only after substituting `SlotBase<Pointer<Void>>`.
        violation(
          rule: 'pointer-field',
          element: 'ExportedSlot',
          member: '_slot',
          type: 'Pointer<Void>?',
        ),
      ]),
    );
    // A computed private getter stores no pointer.
    expect(
      result.violations,
      isNot(
        contains(violation(rule: 'pointer-field', element: 'ExportedComputed')),
      ),
    );
  });

  test('public dispose() method', () async {
    final result = await lintFixture('sync_dispose');
    expect(
      result.violations,
      contains(violation(rule: 'sync-dispose', member: 'dispose')),
    );
  });

  test('violation reached through a re-export chain', () async {
    final result = await lintFixture('reexport_chain');
    expect(result.violations, contains(violation(rule: 'generated')));
  });

  test('combinator that hides the offending element', () async {
    final result = await lintFixture('combinator_hide');
    expect(result.violations, isEmpty);
    expect(result.checkedElements, 1);
  });

  test('inherited public getter from a non-exported base', () async {
    final result = await lintFixture('inherited_getter');
    expect(
      result.violations,
      contains(violation(rule: 'ffi', element: 'Exported', member: 'raw')),
    );
    // A getter is not a stored field.
    expect(
      result.violations,
      isNot(contains(violation(rule: 'pointer-field'))),
    );
  });

  test('inherited members are read with type arguments substituted', () async {
    final result = await lintFixture('generic_base');
    expect(
      result.violations,
      contains(
        violation(
          rule: 'ffi',
          element: 'PointerBox',
          member: 'value',
          type: 'Pointer<Void>',
        ),
      ),
    );
    // Static members of a supertype are not reachable through `Made`.
    expect(
      result.violations,
      isNot(contains(violation(rule: 'ffi', element: 'Made'))),
    );
    // The exported element's own static members are.
    expect(
      result.violations,
      contains(violation(rule: 'ffi', element: 'OwnStatic', member: 'own')),
    );
  });

  test('inherited dispose method, from a superclass and a mixin', () async {
    final result = await lintFixture('inherited_dispose');
    expect(
      result.violations,
      containsAll([
        violation(rule: 'sync-dispose', element: 'Exported', member: 'dispose'),
        violation(
          rule: 'sync-dispose',
          element: 'WithMixin',
          member: 'dispose',
        ),
      ]),
    );
    // An override and the declaration it overrides are one finding.
    expect(
      result.violations.where((v) => v.elementName == 'Overriding'),
      hasLength(1),
    );
  });

  test('extensions and extension types', () async {
    final result = await lintFixture('extensions');
    expect(
      result.violations,
      containsAll([
        violation(rule: 'ffi', element: 'X', member: 'toNative'),
        violation(rule: 'pointer-field', element: 'Handle', member: '_p'),
      ]),
    );
  });

  test('Future, nullable, record, and function-typed positions', () async {
    final result = await lintFixture('complex_types');
    for (final member in [
      'futurePointer',
      'nullablePointer',
      'recordParam',
      'functionParam',
    ]) {
      expect(
        result.violations,
        contains(violation(rule: 'ffi', element: 'Complex', member: member)),
      );
    }
  });

  test('type aliases are expanded and their own library is checked', () async {
    final result = await lintFixture('type_alias');
    expect(
      result.violations,
      containsAll([
        violation(rule: 'ffi', member: 'handle', type: 'Pointer<Void>'),
        violation(rule: 'ffi', member: 'handles', type: 'Pointer<Uint8>'),
        violation(rule: 'generated', member: 'id', type: 'GeneratedId'),
      ]),
    );
  });

  test('every link of a typedef chain is checked (finding 7)', () async {
    // `PublicId` (not generated) = `GeneratedId` (generated) = `int`.
    final result = await lintFixture('type_alias');
    expect(
      result.violations,
      contains(
        violation(rule: 'generated', member: 'chained', type: 'GeneratedId'),
      ),
    );
  });

  test('type-parameter bounds', () async {
    final result = await lintFixture('type_param_bounds');
    expect(
      result.violations,
      containsAll([
        violation(rule: 'ffi', element: 'Bounded', type: 'Pointer<Void>'),
        violation(rule: 'ffi', element: 'Holder', member: 'take'),
        violation(rule: 'ffi', element: 'Callback', type: 'Pointer<Int8>'),
        violation(rule: 'ffi', element: 'run', type: 'Pointer<Int16>'),
      ]),
    );
  });

  test('dart:core and dart:async supertypes raise nothing', () async {
    final result = await lintFixture('sdk_supertypes');
    expect(result.violations, isEmpty);
    expect(result.checkedElements, 7);
  });

  test('results are de-duplicated and sorted', () async {
    final result = await lintFixture('type_alias');
    final sorted = [...result.violations]..sort();
    expect(result.violations, sorted);
    expect(result.violations.toSet(), hasLength(result.violations.length));
  });

  test(
    'a nested type under an already-reported rule is not repeated',
    () async {
      // `Pointer<Void>` is one `ffi` exposure, not one for `Pointer` and one
      // for its `Void` argument.
      final result = await lintFixture('pointer_return');
      expect(result.violations.map((v) => v.toString()), [
        'ffi\tBadClass.getPointer\tPointer<Void>\t(dart:ffi)',
      ]);
    },
  );

  group('non-exported types reachable from public signatures (finding 1)', () {
    late LintResult result;
    setUpAll(() async => result = await lintFixture('reachable'));

    List<String> under(String element) => [
      for (final v in result.violations)
        if (v.elementName == element) '${v.rule} ${v.memberName}',
    ];

    test('through a getter: members, generated types, and dispose', () {
      expect(under('Direct'), [
        'ffi inner→Inner.pointer',
        'generated inner→Inner.generated',
        'sync-dispose inner→Inner.dispose',
      ]);
    });

    test('through Future<Inner>', () {
      expect(under('later'), contains('ffi signature→Inner.pointer'));
    });

    test('through a type-parameter bound', () {
      expect(under('bounded'), contains('ffi signature→Inner.pointer'));
    });

    test('through a supertype type argument (Iterable<Inner>)', () {
      expect(under('Items'), contains('ffi supertype→Inner.pointer'));
    });

    test('through an exported typedef', () {
      expect(under('InnerAlias'), contains('ffi alias→Inner.pointer'));
    });

    test('two hops away, with the Inner → Holder → Inner cycle cut', () {
      expect(under('TwoHops'), [
        'ffi holder→Holder.inner→Inner.pointer',
        'generated holder→Holder.inner→Inner.generated',
        'sync-dispose holder→Holder.inner→Inner.dispose',
      ]);
    });

    test('a non-exported subclass of a generated class', () {
      expect(under('SubUser'), ['generated sub→Sub.supertype']);
    });

    test('a private class returned by a public member', () {
      expect(under('PrivateUser'), ['ffi private→_Private.raw']);
    });

    test('SDK types are not descended into; exported types are not '
        're-attributed', () {
      expect(under('SdkOnly'), isEmpty);
      expect(under('ExportedUser'), isEmpty);
    });
  });

  test('every callable public dispose is reported (finding 2)', () async {
    final result = await lintFixture('dispose_forms');
    final disposals = {
      for (final v in result.violations)
        if (v.rule == 'sync-dispose') v.elementName,
    };
    expect(disposals, {
      'SyncClose', // extension method
      'GetterDispose', // getter of a function type
      'FieldDispose', // field of a function type
      'CallableDispose', // getter of a class with call()
    });
  });

  test('pointer-field looks through extension types and covers package:ffi '
      '(finding 3)', () async {
    final result = await lintFixture('wrapped_pointer_field');
    expect(
      result.violations,
      containsAll([
        violation(
          rule: 'pointer-field',
          element: 'Wrapped',
          member: '_h',
          type: 'Pointer<Void>',
        ),
        violation(
          rule: 'pointer-field',
          element: 'DoublyWrapped',
          member: '_o',
          type: 'Pointer<Void>',
        ),
        violation(
          rule: 'pointer-field',
          element: 'WithArena',
          member: '_arena',
          type: 'Arena',
        ),
      ]),
    );
    expect(
      result.violations,
      isNot(contains(violation(rule: 'pointer-field', element: 'Plain'))),
    );
  });

  test('fields are inherited through extends and with, not implements '
      '(finding 6)', () async {
    final result = await lintFixture('implements_field');
    expect(
      result.violations,
      containsAll([
        violation(rule: 'pointer-field', element: 'Extending', member: '_p'),
        violation(rule: 'pointer-field', element: 'Mixing', member: '_m'),
      ]),
    );
    expect(
      result.violations,
      isNot(
        contains(violation(rule: 'pointer-field', element: 'Implementing')),
      ),
    );
  });

  group('entry libraries (finding 5)', () {
    const root = 'test/fixtures/multi_entry';

    test('default: every lib/*.dart except advanced.dart', () {
      expect(defaultEntryPoints(root), [
        'lib/multi_entry.dart',
        'lib/piece.dart',
        'lib/testing.dart',
      ]);
    });

    test('checks each default entry, skipping part files', () async {
      final results = await checkPublicApiEntries(packageRoot: root);
      expect(results.map((r) => r.entryPoint), [
        'lib/multi_entry.dart',
        'lib/testing.dart',
      ]);
      expect(results.first.violations, isEmpty);
      expect(
        results.last.violations,
        contains(violation(rule: 'generated', element: 'GeneratedThing')),
      );
    });

    test('an explicit part file is an error', () {
      expect(
        checkPublicApiEntries(
          packageRoot: root,
          entryPoints: ['lib/piece.dart'],
        ),
        throwsUnresolved('cannot resolve'),
      );
    });
  });

  group('no verdict without a clean analysis', () {
    test('error in a directly exported library', () {
      expect(
        lintDiagnostics('diagnostics'),
        throwsUnresolved('UnresolvedType'),
      );
    });

    test('error in a transitively exported library', () {
      expect(lintDiagnostics('chain'), throwsUnresolved('UnresolvedType'));
    });

    test('error in a part of the entry library', () {
      expect(lintDiagnostics('with_part'), throwsUnresolved('MissingInPart'));
    });

    test('unresolved type inherited from a non-exported library', () {
      expect(
        lintDiagnostics('broken_base_entry'),
        throwsUnresolved('Exported.raw'),
      );
    });

    test('missing entry point', () {
      expect(
        lintFixture('clean', entry: 'absent'),
        throwsUnresolved('entry point not found'),
      );
    });
  });

  group('command line', () {
    Future<(int, String, String)> run(List<String> args) async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runPublicApiLint(args, out: out, err: err);
      return (code, out.toString(), err.toString());
    }

    test('exit 0 and summary line when clean', () async {
      final (code, out, _) = await run([
        '--package',
        '.',
        '--entry',
        'test/fixtures/clean/lib/clean.dart',
      ]);
      expect(code, exitClean);
      expect(
        out,
        'public-api: test/fixtures/clean/lib/clean.dart: 1 exported elements '
        'checked, 0 violations\n'
        'public-api: 1 exported elements checked, 0 violations\n',
      );
    });

    test('repeatable --entry: a line per entry and a total', () async {
      final (code, out, _) = await run([
        '--package',
        '.',
        '--entry',
        'test/fixtures/clean/lib/clean.dart',
        '--entry',
        'test/fixtures/sync_dispose/lib/sync_dispose.dart',
      ]);
      expect(code, exitViolations);
      expect(out.trimRight().split('\n'), [
        'public-api: test/fixtures/clean/lib/clean.dart: 1 exported elements '
            'checked, 0 violations',
        startsWith('sync-dispose\tMyClass.dispose\tvoid\t('),
        'public-api: test/fixtures/sync_dispose/lib/sync_dispose.dart: 1 '
            'exported elements checked, 1 violations',
        'public-api: 2 exported elements checked, 1 violations',
      ]);
    });

    test('default entries of a package', () async {
      final (code, out, _) = await run([
        '--package',
        'test/fixtures/multi_entry',
      ]);
      expect(code, exitViolations);
      expect(
        out,
        allOf(
          contains('public-api: lib/multi_entry.dart: 2 exported elements'),
          contains('public-api: lib/testing.dart: 1 exported elements'),
          isNot(contains('advanced.dart')),
        ),
      );
    });

    test('exit 1 with one line per violation', () async {
      final (code, out, _) = await run([
        '--package',
        '.',
        '--entry',
        'test/fixtures/sync_dispose/lib/sync_dispose.dart',
      ]);
      expect(code, exitViolations);
      final lines = out.trimRight().split('\n');
      expect(lines, hasLength(3));
      expect(lines.first, startsWith('sync-dispose\tMyClass.dispose\tvoid\t('));
      expect(
        lines.last,
        'public-api: 1 exported elements checked, 1 violations',
      );
    });

    test('exit 2 on analysis errors', () async {
      final (code, out, err) = await run([
        '--package',
        'test/fixtures/diagnostics',
        '--entry',
        'lib/chain.dart',
      ]);
      expect(code, exitUnresolved);
      expect(out, isEmpty);
      expect(err, contains('UnresolvedType'));
    });

    test('exit 64 on usage errors', () async {
      expect((await run(['--entry'])).$1, exitUsage);
      expect((await run(['--bogus'])).$1, exitUsage);
    });
  });
}
