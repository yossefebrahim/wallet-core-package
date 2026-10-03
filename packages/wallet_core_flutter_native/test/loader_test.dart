import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter_native/wallet_core_flutter_native.dart';

/// A location that always fails, so the locator's ordering and its failure
/// report can be tested without a library on disk.
final class _FailingLocation extends LibraryLocation {
  const _FailingLocation(this.label);

  final String label;

  @override
  String get description => 'fake location $label';

  @override
  DynamicLibrary open() => throw ArgumentError('cannot open $label');
}

/// A location that succeeds, standing in for whatever the winning packaging
/// option turns out to provide. Adding it changes nothing in the loader —
/// which is the property under test.
final class _ProcessLocation extends LibraryLocation {
  const _ProcessLocation();

  @override
  String get description => 'a packaging option that resolved the library';

  @override
  DynamicLibrary open() => DynamicLibrary.process();
}

void main() {
  group('default locations', () {
    test('Android asks the loader search path for the packaged .so', () {
      final locations = defaultLocations(platform: NativePlatform.android);
      expect(locations, hasLength(1));
      expect(locations.single, isA<NamedLibrary>());
      expect((locations.single as NamedLibrary).name, 'libTrustWalletCore.so');
      expect(androidLibraryName, 'libTrustWalletCore.so');
    });

    test('iOS tries the process first, then the embedded framework', () {
      final locations = defaultLocations(platform: NativePlatform.ios);
      expect(locations, hasLength(2));
      expect(locations[0], isA<ProcessLibrary>());
      expect(locations[1], isA<NamedLibrary>());
      expect(
        (locations[1] as NamedLibrary).name,
        'TrustWalletCore.framework/TrustWalletCore',
      );
      expect(iosFrameworkLibraryPath, endsWith('TrustWalletCore'));
    });

    test('macOS and Linux ask for the bare host library name', () {
      expect(
        (defaultLocations(platform: NativePlatform.macos).single
                as NamedLibrary)
            .name,
        'libTrustWalletCore.dylib',
      );
      expect(
        (defaultLocations(platform: NativePlatform.linux).single
                as NamedLibrary)
            .name,
        'libTrustWalletCore.so',
      );
    });

    test('a host path goes first on a development host', () {
      final locations = defaultLocations(
        platform: NativePlatform.macos,
        hostLibraryPath: '/build/libTrustWalletCore.dylib',
      );
      expect(locations, hasLength(2));
      expect(locations[0], isA<LibraryFile>());
      expect(
        (locations[0] as LibraryFile).path,
        '/build/libTrustWalletCore.dylib',
      );
      expect(locations[1], isA<NamedLibrary>());
    });

    test('an unknown platform has no default but honours a host path', () {
      expect(defaultLocations(platform: NativePlatform.other), isEmpty);
      expect(
        defaultLocations(
          platform: NativePlatform.other,
          hostLibraryPath: '/build/lib.so',
        ),
        hasLength(1),
      );
    });

    test('every description reads as a place, for the failure report', () {
      for (final platform in NativePlatform.values) {
        for (final location in defaultLocations(platform: platform)) {
          expect(location.description, isNotEmpty);
          expect(location.toString(), location.description);
        }
      }
    });
  });

  group('hostLibraryPath is a development-host parameter only (TM-13)', () {
    for (final platform in const [NativePlatform.android, NativePlatform.ios]) {
      test('rejected on ${platform.name}', () {
        expect(
          () => defaultLocations(
            platform: platform,
            hostLibraryPath: '/data/local/tmp/evil.so',
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('TM-13'),
            ),
          ),
        );
        expect(
          () => WalletCoreNative.load(
            platform: platform,
            hostLibraryPath: '/data/local/tmp/evil.so',
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    }

    test('accepted on macOS and Linux', () {
      expect(NativePlatform.macos.allowsHostLibraryPath, isTrue);
      expect(NativePlatform.linux.allowsHostLibraryPath, isTrue);
      expect(NativePlatform.android.allowsHostLibraryPath, isFalse);
      expect(NativePlatform.ios.allowsHostLibraryPath, isFalse);
    });
  });

  group('load', () {
    test('records every location it tried, in order', () {
      NativeLoadError? caught;
      try {
        WalletCoreNative.load(
          locations: const [
            _FailingLocation('one'),
            _FailingLocation('two'),
            _FailingLocation('three'),
          ],
          platform: NativePlatform.macos,
        );
      } on NativeLoadError catch (e) {
        caught = e;
      }
      final error = caught!;
      expect(error.attempts, hasLength(3));
      expect(error.attempts.map((a) => a.location), <String>[
        'fake location one',
        'fake location two',
        'fake location three',
      ]);
      expect(error.attempts.first.error, isA<ArgumentError>());
      expect(error.message, contains('3 attempts'));
      final text = error.toString();
      for (final label in const ['one', 'two', 'three']) {
        expect(text, contains('fake location $label'));
      }
    });

    test('stops at the first location that opens', () {
      final library = WalletCoreNative.load(
        locations: const [_FailingLocation('one'), _ProcessLocation()],
        platform: NativePlatform.macos,
      );
      expect(library, isA<DynamicLibrary>());
    });

    test('a packaging option adds a location without touching the loader', () {
      // _ProcessLocation is defined in this test file and the loader knows
      // nothing about it: that is the extension point T1.8 and T1.9 use.
      final locations = <LibraryLocation>[
        const _ProcessLocation(),
        ...defaultLocations(platform: NativePlatform.macos),
      ];
      expect(
        WalletCoreNative.load(locations: locations),
        isA<DynamicLibrary>(),
      );
    });

    test('the attempt list is unmodifiable', () {
      final error = NativeLoadError(
        'x',
        attempts: const [LibraryLoadAttempt(location: 'a', error: 'b')],
      );
      expect(
        () => error.attempts.add(
          const LibraryLoadAttempt(location: 'c', error: 'd'),
        ),
        throwsUnsupportedError,
      );
    });

    test('a platform with no location to try says so', () {
      expect(
        () => WalletCoreNative.load(platform: NativePlatform.other),
        throwsA(
          isA<NativeLoadError>().having(
            (e) => e.message,
            'message',
            contains('no location to try'),
          ),
        ),
      );
    });

    test('a missing host library file names the path', () {
      expect(
        () => WalletCoreNative.load(
          platform: NativePlatform.other,
          hostLibraryPath: '/nonexistent/libTrustWalletCore.dylib',
        ),
        throwsA(
          isA<NativeLoadError>().having(
            (e) => e.toString(),
            'toString',
            contains('/nonexistent/libTrustWalletCore.dylib'),
          ),
        ),
      );
    });
  });

  group('symbolLookupAll', () {
    test('returns the names that did not resolve, in order', () {
      final process = DynamicLibrary.process();
      expect(
        WalletCoreNative.symbolLookupAll(process, const [
          'wcf_definitely_absent_b',
          'malloc',
          'wcf_definitely_absent_a',
        ]),
        <String>['wcf_definitely_absent_b', 'wcf_definitely_absent_a'],
      );
    });

    test('an empty list means healthy', () {
      expect(
        WalletCoreNative.symbolLookupAll(DynamicLibrary.process(), const [
          'malloc',
          'free',
        ]),
        isEmpty,
      );
      expect(
        WalletCoreNative.symbolLookupAll(
          DynamicLibrary.process(),
          const <String>[],
        ),
        isEmpty,
      );
    });

    test('requireSymbols throws NativeLoadError naming what is missing', () {
      expect(
        () => WalletCoreNative.requireSymbols(DynamicLibrary.process(), const [
          'malloc',
          'wcf_definitely_absent',
        ]),
        throwsA(
          isA<NativeLoadError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('wcf_definitely_absent'),
              contains('1 of the 2 symbols'),
            ),
          ),
        ),
      );
    });

    test('requireSymbols is silent when everything resolves', () {
      expect(
        () => WalletCoreNative.requireSymbols(DynamicLibrary.process(), const [
          'malloc',
        ]),
        returnsNormally,
      );
    });

    test('a long missing list is summarised rather than dumped', () {
      final many = List<String>.generate(30, (i) => 'wcf_absent_$i');
      expect(
        () => WalletCoreNative.requireSymbols(
          DynamicLibrary.process(),
          many,
          maxNamed: 3,
        ),
        throwsA(
          isA<NativeLoadError>().having(
            (e) => e.message,
            'message',
            allOf(contains('wcf_absent_0'), contains('and 27 more')),
          ),
        ),
      );
    });
  });
}
