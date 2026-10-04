// The hook's user-defines.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.

import 'package:flutter_test/flutter_test.dart';

import '../../hook/src/hook_options.dart';

HookOptions _parse(Map<String, Object?> defines) => HookOptions.parse(
  read: (k) => defines[k],
  path: (k) => '/app/${defines[k]}',
  definedKeys: defines.keys,
  shippedManifestPath: '/pkg/assets/compat_manifest.json',
  defaultCacheDir: '/shared/artifacts/',
);

void main() {
  test('nothing set: shipped manifest, own cache, network allowed', () {
    final o = _parse(const {});
    expect(o.manifestPath, '/pkg/assets/compat_manifest.json');
    expect(o.manifestOverridden, isFalse);
    expect(o.cacheDir, '/shared/artifacts/');
    expect(o.vendoredDir, isNull);
    expect(o.offline, isFalse);
  });

  test('every key, resolved against the pubspec', () {
    final o = _parse(const {
      'offline': true,
      'vendored_dir': 'v',
      'cache_dir': 'c',
      'manifest': 'm.json',
    });
    expect(o.offline, isTrue);
    expect(o.vendoredDir, '/app/v');
    expect(o.cacheDir, '/app/c');
    expect(o.manifestPath, '/app/m.json');
    expect(o.manifestOverridden, isTrue);
  });

  test('an unknown key fails rather than being ignored', () {
    expect(
      () => _parse(const {'ofline': true}),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          allOf(contains('ofline'), contains('offline')),
        ),
      ),
    );
  });

  test('wrong types fail', () {
    expect(() => _parse(const {'offline': 'yes'}), throwsFormatException);
    expect(() => _parse(const {'vendored_dir': 3}), throwsFormatException);
    expect(() => _parse(const {'manifest': ''}), throwsFormatException);
  });

  test('there is no key that accepts a mismatch', () {
    expect(
      HookOptions.keys,
      everyElement(isNot(anyOf(contains('skip'), contains('insecure')))),
    );
    expect(HookOptions.keys, {
      'offline',
      'vendored_dir',
      'cache_dir',
      'manifest',
    });
  });
}
