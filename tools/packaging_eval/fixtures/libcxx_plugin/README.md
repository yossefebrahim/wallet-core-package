# `libcxx_plugin` — the second `libc++_shared.so`

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not
affiliated with or endorsed by Trust Wallet.

PRD §12.2 step 9 asks for the consumer app to be built "together with another
Flutter plugin that bundles `libc++_shared.so`" and for the packaging option's
resolution of the collision to be recorded. This is that plugin, and nothing
else: no method channel, no example app, no iOS, no Dart API. Nine committed
files, one of them a `.gitignore`.

`libc++_shared.so` is not a system library on Android, so every app using the
C++ standard library bundles its own copy; two bundlers means two
`lib/<abi>/libc++_shared.so` entries arriving at Gradle's merge, and what
happens then is the measurement.

## Use

```
tools/packaging_eval/fixtures/libcxx_plugin/tool/materialize_libcxx.sh
```

copies the NDK's own `libc++_shared.so` into `android/src/main/jniLibs/<abi>/`
for `arm64-v8a`, `armeabi-v7a` and `x86_64`. **The `.so` is never committed** —
it is 1 MB per ABI and it is the NDK's file; the directory is git-ignored.
`--clean` removes it again. Both NDK layouts are handled: r27 and earlier keep
the library under `sources/cxx-stl/llvm-libc++/libs/<abi>/`, r28 removed that
tree and ships it in the sysroot under the target triple.

Then, in the evaluation's consumer app:

```yaml
dependencies:
  wallet_core_flutter: { hosted: <local repository>, version: 0.0.1 }
  libcxx_plugin:
    path: <this directory>
```

and

```
flutter build apk --debug 2>&1 | tee "$OUT/gradle.log"
dart run tools/packaging_eval/bin/libcxx_conflict.dart \
    --gradle-output "$OUT/gradle.log" --target android-emulator-x86_64/debug
```

The fixture is referenced by `path:` from a throwaway consumer app only. It is
never published and no shipped package depends on it.

## What the classifier looks for

| Outcome | What the log shows |
|---|---|
| `duplicateFailure` | `More than one file was found with OS independent path 'lib/<abi>/libc++_shared.so'` and no successful build |
| `pickFirstResolved` | a `pickFirst` rule naming the file, or the duplicate reported and the build finishing anyway |
| `singleCopy` | the file mentioned, no duplicate reported, build successful |
| `versionConflict` | the build called out different versions of the library |
| `unknown` | the log says nothing about the file — not a pass |
