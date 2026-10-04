# `eval/option2` — DECISION-2 Option 2 evaluation

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not
affiliated with or endorsed by Trust Wallet.

**Evaluation branch only** (T1.9). Nothing here merges unless Option 2 wins
DECISION-2 at the D1a debate. The findings are in
[`docs/decisions/DECISION-2-option2.md`](../../docs/decisions/DECISION-2-option2.md).

Option 2 is conventional platform packaging: `wallet_core_flutter_native` is an
FFI plugin whose `android/build.gradle` packages each ABI's library from a
checksum-verified cache, and whose `ios/wallet_core_flutter_native.podspec`
vendors a `TrustWalletCore.xcframework` produced, at `pod install`, from
checksum-verified artifacts.

## What is here

| Path | What |
|---|---|
| `run_eval.sh` | Runs PRD §12.2 steps 1–11 for every target with an input on the machine, through `tools/packaging_eval`, and renders the table. `--help` for flags. |
| `eval_manifest.json` | **Evaluation-only.** The root `compat_manifest.json` with its artifact rows taken from the DECISION-14 §5.1 records of the set under `third_party/wcf-native-all/records/` — since T1.9b the published set `as_4.8.0_001` (Android `arm64-v8a` and `x86_64`, iOS device, iOS simulator, macOS), so it holds the root's values. |
| `consumer/` | A `flutter create` app plus two dependencies, one integration test and one release probe entry point. See below for exactly what changed after `flutter create`. |
| `tool/eval.dart` | Helpers `run_eval.sh` needs that are not measurements: build the eval manifest, read its identity and fields, write the wrong-digest fixtures and step 9's counterfactual manifest, append an evaluation-owned result row. |
| `results/` | `results.jsonl` (the rows) and `table.md` (the rendered table), rewritten by every run and never edited by hand. Machine-specific path prefixes are rewritten to `$OUT`, `<repo>` and `~` before rendering. The same run rewrites the generated results block of `DECISION-2-option2.md` §2. |

## The evaluation manifest

Generated once, by hand, and reviewed:

```
dart eval/option2/tool/eval.dart make-manifest --root compat_manifest.json \
    --records third_party/wcf-native-all/records --out eval/option2/eval_manifest.json
```

It is the integrity root of the evaluation: `run_eval.sh` never regenerates it
from `third_party/`, which is untrusted input; the preflight verifies every
file it uses against it with the package's own fetch tool, and the podspec and
the Gradle task verify again before packaging.

**No value is substituted any more.** For the locally built `as_4.8.0_000`
(T1.9a) the tool wrote `.invalid` stand-ins for the records' `"local"`
`build_workflow` and for `retention.primary`, left the Android rows `TBD-T1.2`
and dropped the root's `ios/TrustWalletCore.xcframework.zip` row. The
published set `as_4.8.0_001` (`main` f9f3d58) carries the real `build_workflow`
(`…/actions/runs/37211800874`) in every record, and the root manifest carries
its identity, `retention.primary` (the `native-4.8.0-001` release), the
Android rows and no xcframework-zip row, so `make-manifest` writes the records
as they are and refuses a record whose `build_workflow` is not an https URL or
whose set is not the root manifest's identity. For this set the result equals
the root `compat_manifest.json` as JSON. The release is a draft whose assets
are not anonymously downloadable (HTTP 404); every fetch in the evaluation is
`--offline` from the vendored copy, so none is attempted.

`dart run tools/manifest/bin/validate.dart eval/option2/eval_manifest.json`
passes.

## The consumer app

Created with Flutter **3.47.5** (Dart 3.13.4), from an empty `HOME` so that
`flutter create` finds no keychain identity and writes no `DEVELOPMENT_TEAM`
into `ios/Runner.xcodeproj/project.pbxproj`:

```
HOME=<empty dir> flutter create --no-pub --platforms=android,ios --org dev.wcf.eval \
    --project-name wcf_eval_option2 consumer
```

in `$TMPDIR` and copied here without the IDE files (`.idea/`, `*.iml`) that the
repository ignores anyway, because this session's sandbox refused `flutter
create`'s `.idea/` writes inside the repository. The 3.47.5 template sets iOS
15.0, `sdk: ^3.13.4`, AGP 9.1.0, Kotlin 2.4.0 and Gradle 9.3.1.

**Why 3.47.5.** Flutter 3.44.1 could not build any iOS app on this machine's
Xcode 27.0, an empty one included: its template set iOS 13.0 (macOS 10.15),
and Xcode 27.0 accepts deployment targets 15.0–27.0 (macOS 12.0–27.0). The
evaluation was regenerated and re-run on 3.47.5. `run_eval.sh` reads the
toolchain at run time (rows `min-version` / `host/toolchain` and `host/xcode`).

Changed after `flutter create`:

| File | Change |
|---|---|
| `pubspec.yaml` | added `wallet_core_flutter_bindings: 0.0.1`, `wallet_core_flutter_native: 0.0.1`, and the `integration_test` and `flutter_driver` SDK dev dependencies |
| `integration_test/symbol_lookup_test.dart` | new (carried over unchanged from the 3.44.1 consumer) |
| `lib/probe_main.dart` | new (T1.9b): the release-mode entry point — the integration test's checks, printed as one `WCF_PROBE PASS\|FAIL …` line |
| `test_driver/integration_test.dart` | new: the `integration_test` package's standard driver. It was meant for release-mode runs, but Flutter 3.47.5 refuses them: `flutter drive --release` on the Android emulator printed "Flutter Driver (non-web) does not support running in release mode" (T1.9b, 2026-10-04). Release runs use `lib/probe_main.dart` instead; the driver remains usable in profile mode |
| `.gitignore` | added `pubspec.lock` and `pubspec_overrides.yaml` |
| `pubspec.lock` | not copied in (it would describe the pre-edit dependencies) |

No native file was edited: no Podfile (Flutter generates it at the first iOS
build, in the working copy), no Gradle file, no Xcode project. `run_eval.sh`
checks the Gradle half on every run: the `gradle-integration` row compares the
working copy's four Gradle files with these and fails on any difference. The
two measurements that need a Gradle edit (`abiFilters` in step 1, `pickFirsts`
in step 9) make it in their own working copies under `$TMPDIR`, never here.

`run_eval.sh` never builds this directory in place. It copies it to
`$TMPDIR/wcf-eval-option2/consumer`, writes a `pubspec_overrides.yaml` there
pointing at staged copies of the two packages, and builds the copy — so `pod
install` writes the xcframework under `$TMPDIR`, never into `packages/`.
Hosted consumption (step 11) is measured separately by
`tools/packaging_eval/bin/consumer_gen.dart`.

The integration test loads the library through the loader's default
locations, records which one provides `wcf_build_info`, runs `verifyIdentity`
against the identity injected from `eval_manifest.json`
(`--dart-define=WCF_EXPECT_ARTIFACT_SET_ID/WCF_EXPECT_UPSTREAM_COMMIT`),
resolves every name in `boundFunctionNames` and `exportedTwFunctionNames` plus
`wcf_build_info`, and calls `TWAnyAddressIsValid` on EIP-55's checksummed test
address.

## Android (T1.9b)

Needs the Android SDK (`$ANDROID_HOME`, default `~/Library/Android/sdk`) with
`adb`, a build-tools `apksigner`, the NDK the installed Flutter defaults to
(its `llvm-nm` and `llvm-readelf`; its `libc++_shared.so` is the step 9
fixture's), the set's own NDK (`toolchain.ndk`, for step 9's counterfactual
row), and an **arm64-v8a emulator already running** — the script never boots,
stops or configures one (`WCF_ANDROID_EMULATOR`, default the first `emulator-*`
serial `adb devices` lists; on the T1.9b host AVD `wcf_api35`, API 35,
`emulator-5554`). It differs from PRD §12.2 step 2 in three ways:

- **ABIs.** `as_4.8.0_001` ships `arm64-v8a` and `x86_64`; `armeabi-v7a` was
  never built (PRD §12.2 step 8). Every measured APK is built with
  `--target-platform android-arm64,android-x64`; the `armeabi-v7a` rows are
  `skip not shipped (PRD §12.2 step 8)`. What a default `flutter build apk`
  does, and what `abiFilters` changes, is measured once in a working copy of
  its own (`consumer-build` / `android/armeabi-v7a`).
- **Emulator ABI.** Apple Silicon runs no x86_64 system image, so the run and
  launch rows are measured on the arm64-v8a emulator (`android-emulator-arm64-v8a/*`
  columns); the `android-emulator-x86_64/*` columns carry what needs no run —
  the build, the x86_64 library as packaged in the same APK, its offline
  evidence and its `libc++_shared.so` copy — and their run rows are
  `unmeasured no x86_64 emulator here`. No x86_64 emulator ran. The Android app-size delta is for a two-ABI APK (per-ABI ≈ library size).
- **No physical device.** `android-device-arm64-v8a/*` rows are
  `unmeasured no physical device`, with the command.

Each APK is copied to `$TMPDIR/wcf-eval-option2/apps/android/` right after its
build, and every packaged-library measurement (symbols, size, alignment, the
`packaged-digest` comparison with the manifest) reads those copies: step 2's
`flutter test -d <emulator>` rebuilds the debug APK for one ABI, and the release
probe rebuilds the release APK with another entry point. Debug runs
`integration_test/symbol_lookup_test.dart` on the emulator; release builds
`-t lib/probe_main.dart` with step 1's release configuration, installs it with
`adb`, cold-starts it with `am start -W`, reads the `WCF_PROBE` line from
`logcat`, and checks the signature with `apksigner verify --print-certs` (the
template signs release with the debug keystore). Both builds run `flutter
build apk -v`, so the logs carry Gradle's task graph and the
`wcfPrepare<Variant>JniLibs` task's own output; the `gradle-integration` row
records where the task sits and what it handed AGP.

Step 7 on Android: the debug APK is the app's first Gradle build, and the
`android/` libraries are absent from the artifact cache before it (the pod
installs fetch the iOS rows only), so it is the clean offline install; the
release build after it is warm by construction (`skip`). The no-socket half
runs the exact command the Gradle task runs — `tool/option2/prepare_jni_libs.dart`
through the Flutter SDK's `dart` and the app's package configuration — from a
clean state under the same `sandbox-exec` profile and probe as the iOS
`pod install`. Gradle itself does not run under the profile: its client talks
to the daemon over a loopback socket the profile also denies, and a daemon
started outside the sandbox would run the task outside it anyway. A flipped
`arm64-v8a` digest and the placeholder manifest must each fail the Gradle
build in `wcfPrepareDebugJniLibs` with the fetch tool's report.

Step 9 copies `tools/packaging_eval/fixtures/libcxx_plugin` to
`$TMPDIR/wcf-eval-option2/libcxx_plugin`, materializes the Flutter default
NDK's `libc++_shared.so` there (never in the checkout), adds it to a working
copy of the consumer, and reads from the APK how many copies ship and whose
(GNU build ID). It then measures the counterfactual DECISION-2-option2.md §5.2
is about — a `c++_shared` set, whose manifest lists `android/<abi>/libc++_shared.so`
(here the set's own NDK's file, in a manifest written under `$TMPDIR` only) —
once as the consumer left it and once with the consumer's `pickFirsts` edit.

## The wrong-digest fixtures (step 7)

`run_eval.sh` writes `$TMPDIR/wcf-eval-option2/eval_manifest.flipped.json`: the
evaluation manifest with the simulator dylib's `sha256` changed in its last hex
digit, and its `asset_name` changed to match, so the manifest still validates
and only the bytes disagree. With it, `pod install` must fail with the fetch
tool's mismatch report, and an Xcode build after a good `pod install` must fail
in the pod's `[CP-User] Verify TrustWalletCore.xcframework against the manifest`
phase. With the placeholder manifest — since `main` f9f3d58 the package ships
the filled `as_4.8.0_001` manifest, so the all-`TBD-` case is the fixture
`packages/wallet_core_flutter_native/test/fixtures/compat_manifest.placeholder.json`
copied from `main` — `pod install` must fail with the manifest gate's blockers.
The Gradle build gets the same two, each of which must fail it in
`wcfPrepareDebugJniLibs`: `eval_manifest.flipped-android.json` (the
`arm64-v8a` library's digest flipped) and the placeholder fixture. Its
network-denied half is described under Android above.

The offline half of step 7 is measured, not assumed. The builds' artifact
cache does not exist until their first `pod install` fills it, so that install
obtains the set from the vendored directory (the preflight verifies
`third_party/` into a cache of its own). A separate clean `pod install` runs
under `sandbox-exec` with every outbound connection denied, once a probe shows
the profile applies on the host. The probe is `tool/no_net_probe.sh`: the same
`nc -v -z` connect to a closed loopback port must say "Connection refused" run
plainly and "Operation not permitted" under the profile. Where it does not (a
nested sandbox, no `sandbox-exec`), that row is `unmeasured` with both outputs.
`tool/no_net_probe_test.sh` checks the classification and runs in the
preflight. An online `pub get` makes the
offline rows `unmeasured`.

## Running it

```
eval/option2/run_eval.sh                 # everything this machine can run
eval/option2/run_eval.sh --no-xcode      # stop the iOS side at pod install
```

On the T1.9b host the whole run took under six minutes (2026-10-04, with
Gradle's daemon, its dependency cache and Xcode's DerivedData already warm
from earlier builds; a cold host takes longer). It writes only
`eval/option2/results/`, the block between
`<!-- BEGIN run_eval.sh results -->` and `<!-- END run_eval.sh results -->` in
`docs/decisions/DECISION-2-option2.md`, and `$TMPDIR/wcf-eval-option2/`, plus
the per-user caches the tools it drives always use.
