/// The library-backed half of the suite: everything here runs against the
/// real relinked host library, or skips.
///
/// See `host_library.dart` for how the path is found and how to make these run
/// (`melos run native:host-lib`, or `WCF_NATIVE_LIB`; `WCF_NATIVE_REQUIRED=1`
/// turns a skip into a failure).
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter_native/wallet_core_flutter_native.dart';

import 'host_library.dart';

/// The identity the relinked development library carries: DECISION-9 Option
/// C's Apple leg, built locally rather than by a workflow.
const String _expectedCommit = 'd692ac27749d0c615e17c751b70ab4f0aa75c59b';

DynamicLibrary _openHostLibrary() => WalletCoreNative.load(
  // The *test* reads WCF_NATIVE_LIB and passes the path in. Library code
  // never reads an environment variable (TM-13).
  platform: NativePlatform.macos,
  hostLibraryPath: requireHostLibrary(),
);

void main() {
  group('the real host library', () {
    test('opens through the documented locator', () {
      expect(_openHostLibrary(), isA<DynamicLibrary>());
    }, skip: hostLibrarySkip);

    test('reports the identity wcf_build_info() was linked with', () {
      final identity = BuildIdentity.read(_openHostLibrary());
      expect(identity.upstreamCommit, _expectedCommit);
      expect(identity.artifactSetId, startsWith('as_'));
      expect(identity.buildWorkflow, isNotEmpty);
    }, skip: hostLibrarySkip);

    test('passes comparisons 3 and 4 against its own identity', () {
      // The injected expectation is what T1.2's workflow will write into the
      // manifest for the set this library belongs to.
      final library = _openHostLibrary();
      final identity = BuildIdentity.read(library);
      expect(
        () => verifyIdentity(
          library,
          expected: ManifestIdentity(
            artifactSetId: identity.artifactSetId,
            upstreamCommit: identity.upstreamCommit,
          ),
        ),
        returnsNormally,
      );
    }, skip: hostLibrarySkip);

    test('fails comparison 3 against the shipped manifest, by design', () {
      // compat_manifest.json still says identity.artifact_set_id = TBD-T1.2:
      // the CI native build has not run, so no published set exists and this
      // locally relinked library is not a member of one.
      expect(
        () => verifyIdentity(_openHostLibrary()),
        throwsA(
          isA<ManifestMismatchError>()
              .having(
                (e) => e.check,
                'check',
                ManifestCheck.artifactSetMismatch,
              )
              .having((e) => e.expected, 'expected', identityArtifactSetId),
        ),
      );
    }, skip: hostLibrarySkip ?? _placeholderSkip);

    test('fails comparison 4 against a different commit', () {
      final library = _openHostLibrary();
      final identity = BuildIdentity.read(library);
      expect(
        () => verifyIdentity(
          library,
          expected: ManifestIdentity(
            artifactSetId: identity.artifactSetId,
            upstreamCommit: '0' * 40,
          ),
        ),
        throwsA(
          isA<ManifestMismatchError>().having(
            (e) => e.check,
            'check',
            ManifestCheck.upstreamCommitMismatch,
          ),
        ),
      );
    }, skip: hostLibrarySkip);

    test('resolves every exported TW* symbol plus the identity symbol', () {
      final names = _exportedSymbols()!;
      // 464 TW* functions at 4.8.0 (DECISION-9 §5) plus wcf_build_info.
      expect(names, hasLength(465));
      expect(names, contains(identitySymbol));
      expect(
        WalletCoreNative.symbolLookupAll(_openHostLibrary(), names),
        isEmpty,
      );
      expect(
        () => WalletCoreNative.requireSymbols(_openHostLibrary(), names),
        returnsNormally,
      );
    }, skip: hostLibrarySkip ?? _inventorySkip);

    test('a symbol it does not export is reported by name', () {
      expect(
        () => WalletCoreNative.requireSymbols(_openHostLibrary(), const [
          'TWAnyAddressIsValid',
          'TWNoSuchFunction',
        ]),
        throwsA(
          isA<NativeLoadError>().having(
            (e) => e.message,
            'message',
            contains('TWNoSuchFunction'),
          ),
        ),
      );
    }, skip: hostLibrarySkip);
  });

  group('a library without wcf_build_info', () {
    // DECISION-9 §5 requires this negative test: it is the case a
    // mirrored-without-relink artifact would hit. libSystem opens on every
    // macOS and exports no such symbol.
    const String libSystem = '/usr/lib/libSystem.B.dylib';

    test('is a NativeLoadError naming the missing symbol', () {
      final library = WalletCoreNative.load(
        locations: const [LibraryFile(libSystem)],
      );
      expect(library.providesSymbol(identitySymbol), isFalse);
      expect(
        () => BuildIdentity.read(library),
        throwsA(
          isA<NativeLoadError>().having(
            (e) => e.message,
            'message',
            allOf(contains(identitySymbol), contains('not an artifact')),
          ),
        ),
      );
    }, skip: _macOnlySkip);

    test('is never reported as a mismatch', () {
      // DECISION-14 §2.3: a missing identity symbol means the library is not
      // one of ours, which is a load failure, not a wrong-set failure.
      expect(
        () => verifyIdentity(
          WalletCoreNative.load(locations: const [LibraryFile(libSystem)]),
        ),
        throwsA(
          allOf(
            isA<NativeLoadError>().having(
              (e) => e.message,
              'message',
              contains('does not export "$identitySymbol"'),
            ),
            isNot(isA<ManifestMismatchError>()),
          ),
        ),
      );
    }, skip: _macOnlySkip);
  });
}

Object? get _macOnlySkip =>
    Platform.isMacOS ? null : 'needs macOS: /usr/lib/libSystem.B.dylib';

Object? get _placeholderSkip => isPlaceholder(identityArtifactSetId)
    ? null
    : 'compat_manifest.json now carries a real identity.artifact_set_id '
          '($identityArtifactSetId); T1.2 has run, so the development library '
          'is no longer expected to be a stranger to the manifest.';

Object? get _inventorySkip => _exportedSymbols() == null
    ? 'needs the bindings package\'s generated inventory.json '
          '(`melos run gen:ffi`).'
    : null;

/// The 464 exported `TW*` function names the bindings package's generated
/// inventory records, plus the identity symbol.
///
/// Read from the sibling package rather than depended on: the dependency runs
/// the other way (the bindings package depends on this one), so the symbol
/// list is the caller's to supply — which is exactly what
/// `WalletCoreNative.symbolLookupAll` is shaped for.
List<String>? _exportedSymbols() {
  final root = repoRoot;
  if (root == null) return null;
  final file = File(
    '${root.path}/packages/wallet_core_flutter_bindings/lib/src/generated/'
    'inventory.json',
  );
  if (!file.existsSync()) return null;
  final decoded = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final symbols = decoded['symbols']! as Map<String, Object?>;
  return <String>[
    for (final entry in symbols.entries)
      if (entry.key.startsWith('TW') &&
          (entry.value! as Map<String, Object?>)['kind'] == 'function')
        entry.key,
    identitySymbol,
  ];
}
