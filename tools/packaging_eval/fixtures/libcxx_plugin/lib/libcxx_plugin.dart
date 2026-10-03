/// A Flutter Android plugin whose only purpose is to bundle
/// `libc++_shared.so`, so that a consumer app has two contributors of that
/// file and PRD §12.2 step 9 has something to measure.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// There is no Dart API here on purpose: the collision happens at the Gradle
/// merge, and a method channel would only add a moving part that has nothing
/// to do with the measurement.
library;

/// Marker class, so the plugin has a Dart entry point to import.
class LibcxxPlugin {
  const LibcxxPlugin._();

  /// The ABIs the fixture materialises `libc++_shared.so` for.
  static const List<String> abis = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];
}
