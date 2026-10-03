/// The manifest → jniLibs mapping the Android Gradle task consumes.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
library;

import 'package:flutter_test/flutter_test.dart';

import '../../tool/option2/src/jni_libs_plan.dart';

Map<String, Object?> _manifest(List<String> keys) => {
  'artifacts': {
    for (final key in keys) key: {'sha256': 'TBD-T1.2', 'size': 0},
    'ios/TrustWalletCore.xcframework.zip': {'sha256': 'TBD-T1.2', 'size': 0},
  },
};

void main() {
  test('every android/<abi>/<file>.so row maps to <abi>/<file>.so, sorted', () {
    final plan = jniLibsPlan(
      _manifest([
        'android/x86_64/libTrustWalletCore.so',
        'android/arm64-v8a/libc++_shared.so',
        'android/arm64-v8a/libTrustWalletCore.so',
      ]),
    );
    expect(plan.map((e) => e.jniLibsPath), [
      'arm64-v8a/libTrustWalletCore.so',
      'arm64-v8a/libc++_shared.so',
      'x86_64/libTrustWalletCore.so',
    ]);
    expect(plan.first.logicalName, 'android/arm64-v8a/libTrustWalletCore.so');
  });

  test('the root manifest shape ships armeabi-v7a because it lists it', () {
    final plan = jniLibsPlan(
      _manifest([
        'android/arm64-v8a/libTrustWalletCore.so',
        'android/armeabi-v7a/libTrustWalletCore.so',
        'android/x86_64/libTrustWalletCore.so',
      ]),
    );
    expect(plan.map((e) => e.abi), ['arm64-v8a', 'armeabi-v7a', 'x86_64']);
  });

  test('dropping a row from the manifest drops the ABI', () {
    final plan = jniLibsPlan(
      _manifest(['android/arm64-v8a/libTrustWalletCore.so']),
    );
    expect(plan.map((e) => e.abi), ['arm64-v8a']);
  });

  test('non-Android and non-.so rows are ignored', () {
    final plan = jniLibsPlan({
      'artifacts': <String, Object?>{
        'android/arm64-v8a/libTrustWalletCore.so': <String, Object?>{},
        'android/arm64-v8a/libTrustWalletCore.so.sym.zip': <String, Object?>{},
        'ios/arm64/libTrustWalletCore.dylib': <String, Object?>{},
      },
    });
    expect(plan, hasLength(1));
  });

  test('an unknown ABI directory is refused', () {
    expect(
      () => jniLibsPlan(_manifest(['android/mips/libTrustWalletCore.so'])),
      throwsA(isA<JniLibsPlanException>()),
    );
  });

  test('an ABI without libTrustWalletCore.so is refused', () {
    expect(
      () => jniLibsPlan(
        _manifest([
          'android/arm64-v8a/libTrustWalletCore.so',
          'android/x86_64/libc++_shared.so',
        ]),
      ),
      throwsA(
        isA<JniLibsPlanException>().having(
          (e) => e.message,
          'message',
          contains('android/x86_64/libTrustWalletCore.so'),
        ),
      ),
    );
  });

  test('no Android row at all is refused, not an empty APK', () {
    expect(
      () => jniLibsPlan(_manifest(const [])),
      throwsA(isA<JniLibsPlanException>()),
    );
    expect(() => jniLibsPlan(const {}), throwsA(isA<JniLibsPlanException>()));
  });

  test('abisWithoutLibcxx names the ABIs with no runtime row', () {
    final plan = jniLibsPlan(
      _manifest([
        'android/arm64-v8a/libTrustWalletCore.so',
        'android/arm64-v8a/libc++_shared.so',
        'android/x86_64/libTrustWalletCore.so',
      ]),
    );
    expect(abisWithoutLibcxx(plan), ['x86_64']);
  });
}
