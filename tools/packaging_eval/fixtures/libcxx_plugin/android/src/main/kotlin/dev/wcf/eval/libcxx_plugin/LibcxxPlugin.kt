package dev.wcf.eval.libcxx_plugin

import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * The registered plugin class. It does nothing: the fixture exists to put
 * `libc++_shared.so` into the consumer's APK through
 * `android/src/main/jniLibs/`, and Flutter needs a plugin class for the module
 * to be an Android library the app builds.
 */
class LibcxxPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) = Unit

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) = Unit
}
