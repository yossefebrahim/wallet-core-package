/// The URL and file-name grammar of DECISION-14 §3.1, exhaustively, with no
/// filesystem and no server.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
library;

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/asset_names.dart';

void main() {
  group('flatName', () {
    test('replaces every separator', () {
      expect(
        flatName('android/arm64-v8a/libTrustWalletCore.so'),
        'android-arm64-v8a-libTrustWalletCore.so',
      );
    });

    test('leaves a single-segment name alone', () {
      expect(flatName('libTrustWalletCore.so'), 'libTrustWalletCore.so');
    });

    test('matches the longest name DECISION-14 §3.1 measures', () {
      expect(
        flatName(
          'ios-simulator/arm64_x86_64/libTrustWalletCore.dylib.dSYM.zip',
        ).length,
        lessThan(80),
      );
    });
  });

  group('primaryUrl', () {
    const base =
        'https://github.com/yossefebrahim/wallet-core-package/releases/download/'
        'native-4.8.0-001';
    const assetName =
        'as_4.8.0_001__'
        '9f2c1ab34de5f70e8a3b1c4d6e2079bd85fa1c3e97d024b658ea7c319f40db26'
        '__android-arm64-v8a-libTrustWalletCore.so';

    test('is one segment under the base', () {
      expect(primaryUrl(base, assetName), '$base/$assetName');
    });

    test('tolerates a trailing slash on the base', () {
      expect(primaryUrl('$base/', assetName), '$base/$assetName');
    });
  });

  group('mirrorUrl', () {
    const base = 'https://bucket.example/wcf-artifacts';
    const sha =
        '9f2c1ab34de5f70e8a3b1c4d6e2079bd85fa1c3e97d024b658ea7c319f40db26';

    test('is set id, digest, then the logical name as a path', () {
      expect(
        mirrorUrl(
          base,
          'as_4.8.0_001',
          sha,
          'android/arm64-v8a/libTrustWalletCore.so',
        ),
        '$base/as_4.8.0_001/$sha/android/arm64-v8a/libTrustWalletCore.so',
      );
    });

    test('keeps the logical name unflattened, unlike the primary', () {
      final url = mirrorUrl(base, 'as_4.8.0_001', sha, 'ios/Frame.zip');
      expect(url, endsWith('/ios/Frame.zip'));
      expect(url, isNot(contains('ios-Frame.zip')));
    });
  });

  group('parseAssetName', () {
    const sha =
        '9f2c1ab34de5f70e8a3b1c4d6e2079bd85fa1c3e97d024b658ea7c319f40db26';

    test('splits the three fields', () {
      final parsed = parseAssetName(
        'as_4.8.0_001__${sha}__android-arm64-v8a-libTrustWalletCore.so',
      );
      expect(parsed.artifactSetId, 'as_4.8.0_001');
      expect(parsed.sha256, sha);
      expect(parsed.flatName, 'android-arm64-v8a-libTrustWalletCore.so');
    });

    test('round-trips through toString', () {
      const name = 'as_4.8.0_001__${sha}__libTrustWalletCore.so';
      expect(parseAssetName(name).toString(), name);
    });

    test('rejects two fields', () {
      expect(
        () => parseAssetName('as_4.8.0_001__$sha'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('three "__"-separated fields, got 2'),
          ),
        ),
      );
    });

    test('rejects four fields', () {
      expect(
        () => parseAssetName('as_4.8.0_001__${sha}__a__b'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a 12-hex prefix — D0 finding F7', () {
      expect(
        () => parseAssetName('as_4.8.0_001__9f2c1ab34de5__android-lib.so'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('64 lowercase hex characters'),
          ),
        ),
      );
    });

    test('rejects an uppercase digest', () {
      expect(
        () => parseAssetName('as_4.8.0_001__${sha.toUpperCase()}__lib.so'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects an empty field', () {
      expect(
        () => parseAssetName('__${sha}__lib.so'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('artifact_set_id is empty'),
          ),
        ),
      );
    });

    test('tryParseAssetName returns null instead of throwing', () {
      expect(tryParseAssetName('nope'), isNull);
      expect(tryParseAssetName('as_4.8.0_001__${sha}__lib.so'), isNotNull);
    });
  });

  group('isSha256', () {
    test('accepts exactly 64 lowercase hex', () {
      expect(isSha256('a' * 64), isTrue);
      expect(
        isSha256(
          '30b0532d9f143b6409aa405f3ba124625fb01e70f13d8e52b3904334c617ff60',
        ),
        isTrue,
      );
    });

    test('rejects everything else', () {
      expect(isSha256('a' * 63), isFalse);
      expect(isSha256('a' * 65), isFalse);
      expect(isSha256('A' * 64), isFalse);
      expect(isSha256('TBD-T1.2'), isFalse);
      expect(isSha256(''), isFalse);
    });
  });

  group('isLogicalName', () {
    test('accepts the path grammar of D0 finding F14', () {
      expect(isLogicalName('android/arm64-v8a/libTrustWalletCore.so'), isTrue);
      expect(isLogicalName('ios/TrustWalletCore.xcframework.zip'), isTrue);
      expect(isLogicalName('a+b/c.d_e-f'), isTrue);
      expect(isLogicalName('single'), isTrue);
    });

    test('rejects the asset name separator', () {
      expect(isLogicalName('android/lib__thing.so'), isFalse);
    });

    test('rejects traversal and empty segments', () {
      expect(isLogicalName('../etc/passwd'), isFalse);
      expect(isLogicalName('a/./b'), isFalse);
      expect(isLogicalName('/absolute'), isFalse);
      expect(isLogicalName('a//b'), isFalse);
      expect(isLogicalName(''), isFalse);
    });

    test('rejects characters outside the grammar', () {
      expect(isLogicalName(r'android\arm64\lib.so'), isFalse);
      expect(isLogicalName('a b/c'), isFalse);
    });
  });

  group('cachePathFor', () {
    test('joins the cache root and the logical path', () {
      expect(
        cachePathFor('/cache/4.8.0', 'android/arm64-v8a/lib.so'),
        '/cache/4.8.0/android/arm64-v8a/lib.so',
      );
    });

    test('does not double a trailing separator', () {
      expect(cachePathFor('/cache/', 'a/b'), '/cache/a/b');
      expect(cachePathFor('/', 'a/b'), '/a/b');
    });

    test('rewrites separators when asked', () {
      expect(
        cachePathFor(r'C:\cache', 'android/lib.so', separator: r'\'),
        r'C:\cache\android\lib.so',
      );
    });

    test('refuses a name that would escape the cache directory', () {
      expect(
        () => cachePathFor('/cache', '../../etc/passwd'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => cachePathFor('/cache', '/etc/passwd'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
