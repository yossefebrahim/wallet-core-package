#!/usr/bin/env bash
# eval/option2/run_eval.sh — PRD §12.2 steps 1–11 for DECISION-2 Option 2
# (conventional platform packaging: Gradle on Android, podspec + xcframework on
# iOS). Evaluation branch only (T1.9).
#
# Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
# Not affiliated with or endorsed by Trust Wallet.
#
# Usage, from anywhere (paths are resolved from this file):
#
#   eval/option2/run_eval.sh [--no-xcode] [--skip-consumer-gen]
#
#   --no-xcode           stop the iOS side at `pod install` (run through
#                        `flutter build ios --config-only`): the podspec's
#                        verification and xcframework assembly, the CocoaPods
#                        integration and the wrong-digest fixture are measured;
#                        every row that needs an Xcode build or a device run is
#                        written `unmeasured` with its exact command. For a
#                        session whose sandbox refuses Xcode's DerivedData.
#   --skip-consumer-gen  skip step 11 (flutter create + pub get, ~1 min)
#
# Environment:
#   WCF_IOS_SIMULATOR    id of an already-booted simulator to run the
#                        integration test on. Default: the first booted one
#                        `xcrun simctl list devices booted` reports. This
#                        script never boots, erases or configures a simulator.
#   WCF_IOS_DEVICE       id of a connected physical device (optional).
#   WCF_ANDROID_EMULATOR adb serial of an already-running arm64-v8a emulator.
#                        Default: the first `emulator-*` serial `adb devices`
#                        lists. This script never boots, stops or configures
#                        an emulator. Android also needs $ANDROID_HOME
#                        (default ~/Library/Android/sdk) with adb, a
#                        build-tools apksigner and the NDK Flutter defaults to.
#
# Android (T1.9b). The evaluated set (as_4.8.0_001) ships arm64-v8a and x86_64
# only: armeabi-v7a was never built (PRD §12.2 step 8), so every measured APK
# is built with --target-platform android-arm64,android-x64 and the
# armeabi-v7a rows are `skip`. On an Apple-Silicon host no x86_64 system image
# runs, so the run rows are measured on the arm64-v8a emulator and the x86_64
# library statically from the same APK. The release run is a probe entry point
# (consumer/lib/probe_main.dart) installed with adb and read from logcat:
# `flutter test` has no release mode and Flutter Driver refuses one.
#
# Every measurement is a tools/packaging_eval command appending to
# eval/option2/results/results.jsonl; rows the harness has no command for
# (a build, an on-target run, the wrong-checksum fixture) are written by
# eval/option2/tool/eval.dart with the same schema. The table is rendered by
# tools/packaging_eval/bin/report.dart into eval/option2/results/table.md.
#
# Writes: eval/option2/results/, the generated results block of
# docs/decisions/DECISION-2-option2.md §2 (between `<!-- BEGIN run_eval.sh
# results -->` and `<!-- END run_eval.sh results -->`), and
# $TMPDIR/wcf-eval-option2/ (staged packages, the working copy of the
# consumer app and every build, logs, the artifact caches). Nothing else in
# the repository. Before rendering, machine-specific path prefixes in
# results.jsonl are rewritten to `$OUT`, `<repo>` and `~`; the run fails if
# the home directory still appears. The tools it drives keep their usual
# per-user caches (pub cache, CocoaPods cache, Xcode's DerivedData), as any
# Flutter build does.
#
# Idempotent: both output locations are reset at the start of a run.
# Fails on the first unexpected error (set -Eeuo pipefail); the expected
# failures — the wrong-checksum fixtures — are checked explicitly.

set -Eeuo pipefail

NO_XCODE=0
SKIP_CONSUMER_GEN=0
for arg in "$@"; do
  case "$arg" in
    --no-xcode) NO_XCODE=1 ;;
    --skip-consumer-gen) SKIP_CONSUMER_GEN=1 ;;
    -h|--help) awk 'NR > 1 && /^#/ { print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 64 ;;
  esac
done

# CocoaPods (1.16.2 on Ruby 4.0) aborts with "Unicode Normalization not
# appropriate for ASCII-8BIT" when the locale is not UTF-8 — the case for a
# script started without LANG (measured, T1.9b). Flutter sets it for the pod
# installs it runs itself; the direct `pod install`s below need it too.
case "${LC_ALL:-${LANG:-}}" in
  *UTF-8*|*utf8*|*UTF8*|*utf-8*) ;;
  *) export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 ;;
esac

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EVAL="$REPO/eval/option2"
TMP_ROOT="${TMPDIR:-/tmp}"
OUT="${TMP_ROOT%/}/wcf-eval-option2"
RESULTS_DIR="$EVAL/results"
RESULTS="$RESULTS_DIR/results.jsonl"
TABLE="$RESULTS_DIR/table.md"
DOC="$REPO/docs/decisions/DECISION-2-option2.md"
MANIFEST="$EVAL/eval_manifest.json"
FLIPPED="$OUT/eval_manifest.flipped.json"
VENDORED="$REPO/third_party/wcf-native-all/artifacts"
# The builds' artifact cache. It does not exist until the first pod install
# fills it, so that install obtains the set from --vendored (step 7).
CACHE="$OUT/artifact-cache"
PREFLIGHT_CACHE="$OUT/preflight-cache"
OFFLINE_CACHE="$OUT/offline-cache"
STAGE="$OUT/stage"
APP="$OUT/consumer"
BASELINE="$OUT/baseline"
APPS="$OUT/apps"
LOGS="$OUT/logs"
XCF_ROOT="$STAGE/wallet_core_flutter_native/ios/Frameworks"
PODS_SUPPORT="$APP/ios/Pods/Target Support Files"

DEVICE_ROW="ios/arm64/libTrustWalletCore.dylib"
SIM_ROW="ios-simulator/arm64_x86_64/libTrustWalletCore.dylib"
XCF_DEVICE_BIN="TrustWalletCore.xcframework/ios-arm64/TrustWalletCore.framework/TrustWalletCore"
XCF_SIM_BIN="TrustWalletCore.xcframework/ios-arm64_x86_64-simulator/TrustWalletCore.framework/TrustWalletCore"
EMBEDDED_BIN="Frameworks/TrustWalletCore.framework/TrustWalletCore"
ORCHESTRATOR="orchestrator-run: --no-xcode (this session's sandbox refuses Xcode's DerivedData); run eval/option2/run_eval.sh without it"
IOS_APP_TARGETS=(ios-simulator-arm64/debug ios-simulator-arm64/release ios-device-arm64/debug ios-device-arm64/release)

# Android (T1.9b): see the header. One APK carries both shipped ABIs, so the
# x86_64 emulator columns measure the same APK statically.
ANDROID_PLATFORMS='android-arm64,android-x64'
AND_ARM=android-emulator-arm64-v8a
AND_X64=android-emulator-x86_64
AND_DEV=android-device-arm64-v8a
AND_ARM_ROW='android/arm64-v8a/libTrustWalletCore.so'
AND_X64_ROW='android/x86_64/libTrustWalletCore.so'
AND_PACKAGE='dev.wcf.eval.wcf_eval_option2'
AND_APPS="$APPS/android"
# The four TW* exports outside the symbol list that every Android build of
# upstream's module carries — its JNI glue (jni/cpp/TWJNIData.h,
# TWJNIString.h) — allowed exactly as tools/native_build/build_android.sh
# allows them; any other extra still fails.
JNI_ALLOW=(--allow-extra TWDataCreateWithJByteArray --allow-extra TWDataJByteArray
  --allow-extra TWStringCreateWithJString --allow-extra TWStringJString)
NOT_SHIPPED='not shipped (PRD §12.2 step 8)'
NOT_SHIPPED_NOTE='as_4.8.0_001 builds no armeabi-v7a library: PRD §12.2 step 8 ships an ABI only if it is tested; the manifest has no android/armeabi-v7a row, so the Gradle task packages none (what a default-ABI build does: consumer-build / android/armeabi-v7a)'
NO_DEVICE='no physical Android device is attached to this host; the APK is the one the emulator columns measure, what is unmeasured is installing and running it on arm64 hardware'
NO_X64='Apple-Silicon host: an x86_64 Android system image does not run here, so the run rows are measured on the arm64-v8a emulator; the x86_64 library is measured statically from the same APK (symbols, size, alignment, packaged digest, libc++_shared copy)'
# The fixture manifest every placeholder check uses (main f9f3d58): the root
# manifest as it was before as_4.8.0_001, every digest `TBD-`.
PLACEHOLDER="$REPO/packages/wallet_core_flutter_native/test/fixtures/compat_manifest.placeholder.json"

cd "$REPO"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

say() { printf '\n== %s\n' "$*"; }

row() { dart "$EVAL/tool/eval.dart" row --out "$RESULTS" "$@"; }

harness() {
  local command="$1"
  shift
  dart run "tools/packaging_eval/bin/$command.dart" "$@" --out "$RESULTS"
}

unmeasured() { # check target command notes
  row --check "$1" --target "$2" --status unmeasured --command "$3" --notes "$4"
}

render() {
  # Machine-specific prefixes out of what gets committed, longest first: the
  # build directory and the temporary directory the harness uses (each also
  # as macOS's /private realpath), the repository, the home directory.
  dart "$EVAL/tool/eval.dart" scrub --file "$RESULTS" \
    --replace "/private$OUT=\$OUT" --replace "$OUT=\$OUT" \
    --replace "/private${TMP_ROOT%/}=\$TMPDIR" --replace "${TMP_ROOT%/}=\$TMPDIR" \
    --replace "$REPO=<repo>" --replace "$HOME=~"
  # `=` forms only: report.dart counts every argument that does not start with
  # `-` as a results path, including the value of a space-separated option.
  dart run tools/packaging_eval/bin/report.dart "--results=$RESULTS" "--out=$TABLE" \
    '--title=DECISION-2 Option 2 (Gradle / podspec + xcframework) — PRD §12.2 results' \
    > /dev/null
  # The decision document's §2 block is this table, never a hand copy.
  dart "$EVAL/tool/eval.dart" embed --table "$TABLE" --results "$RESULTS" --doc "$DOC"
  if [ "${#HOME}" -gt 1 ] && grep -qF "$HOME/" "$RESULTS" "$TABLE" "$DOC"; then
    echo "run_eval.sh: $HOME still appears in $RESULTS, $TABLE or $DOC" >&2
    exit 1
  fi
  echo "table: $TABLE"
}

finish() {
  render
  exit "$1"
}

trap 'echo "run_eval.sh: unexpected failure at line $LINENO" >&2' ERR

log_tail() { tail -n 25 "$1" | tr '\n' ' ' | cut -c1-900; }

# "<slug>" -> "<target>": ios-simulator-arm64-debug -> ios-simulator-arm64/debug
target_of() { echo "${1%-*}/${1##*-}"; }

# How many libraries an artifact cache holds (0 when it does not exist).
cache_files() {
  { find "$1" -type f -name 'libTrustWalletCore.dylib' 2>/dev/null || true; } | wc -l | tr -d ' '
}
# The same for the Android libraries.
so_cache_files() {
  { find "$1" -type f -name 'libTrustWalletCore.so' 2>/dev/null || true; } | wc -l | tr -d ' '
}

# A working copy of the consumer app at $1, resolving the two packages from
# the staged copies (the same pubspec_overrides.yaml as $APP).
stage_app() {
  rm -rf "$1"
  rsync -a --exclude .dart_tool --exclude build \
    --exclude ios/Pods --exclude ios/.symlinks "$EVAL/consumer/" "$1/"
  cp "$APP/pubspec_overrides.yaml" "$1/pubspec_overrides.yaml"
  (cd "$1" && flutter pub get --offline) > "$LOGS/pub-get-$(basename "$1").log" 2>&1
}

# apk_libs APK: the APK's native libraries, `lib/<abi>/<name>.so <bytes>`,
# comma-separated.
apk_libs() {
  unzip -l "$1" | awk '$4 ~ /^lib\/[^\/]+\/[^\/]+\.so$/ { printf "%s%s %s", sep, $4, $1; sep = ", " }'
}
# apk_abi_libs APK ABI: the file names under lib/<ABI>/, space-separated.
apk_abi_libs() {
  unzip -l "$1" | awk -v p="lib/$2/" 'index($4, p) == 1 { n = $4; sub(".*/", "", n); printf "%s%s", sep, n; sep = " " }'
}
# build_id ELF: the GNU build ID, which tells two builds of one file apart.
build_id() {
  "$READELF" -n "$1" 2>/dev/null | sed -n 's/^ *Build ID: //p' | head -1
}
# dt_needed ELF: the DT_NEEDED entries, space-separated.
dt_needed() {
  "$READELF" -d "$1" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' | tr '\n' ' ' | sed 's/ $//'
}
# The fetch tool's count line(s) for the Gradle task, out of a verbose
# `flutter build apk -v` log: what the task obtained and from where.
prepare_lines() { # log task
  sed -n "/> Task :wallet_core_flutter_native:$2/,/verified libraries in/p" "$1" \
    | grep -E ' requested: |verified libraries in' | sed 's/^\[[^]]*\] *//' | tr '\n' ' ' | tr -s ' ' || true
}
# android_probe APK LOG: installs APK on $EMU_ID, cold-starts its activity and
# waits up to 60 s for the probe's line in logcat. Sets PROBE_LINE (empty if
# none) and LAUNCH (am start -W's status, launch state and time).
android_probe() {
  {
    "$ADB" -s "$EMU_ID" install -r "$1" &&
      "$ADB" -s "$EMU_ID" shell am force-stop "$AND_PACKAGE" &&
      "$ADB" -s "$EMU_ID" logcat -c &&
      "$ADB" -s "$EMU_ID" shell am start -W -n "$AND_PACKAGE/.MainActivity"
  } > "$2" 2>&1 || true
  PROBE_LINE=''
  local n=0
  while [ $n -lt 60 ]; do
    PROBE_LINE=$("$ADB" -s "$EMU_ID" logcat -d -s flutter:I 2>/dev/null | tr -d '\r' | grep -o 'WCF_PROBE .*' | head -1 || true)
    [ -z "$PROBE_LINE" ] || break
    sleep 1
    n=$((n + 1))
  done
  "$ADB" -s "$EMU_ID" logcat -d -s flutter:I >> "$2" 2>&1 || true
  LAUNCH=$(tr -d '\r' < "$2" | grep -E '^(Status|LaunchState|TotalTime):' | tr '\n' ' ' | sed 's/ *$//' || true)
}

# ---------------------------------------------------------------------------
# step 0 — preflight: the evaluation manifest, the untrusted inputs, staging
# ---------------------------------------------------------------------------

say "preflight"
rm -rf "$OUT"
mkdir -p "$OUT" "$LOGS" "$APPS" "$RESULTS_DIR"
: > "$RESULTS"

dart run tools/manifest/bin/validate.dart "$MANIFEST"
# The network-denial probe of step 7 decides a row's status; check its
# classification before anything is measured.
# shellcheck source=tool/no_net_probe.sh
. "$EVAL/tool/no_net_probe.sh"
bash "$EVAL/tool/no_net_probe_test.sh"
IDENTITY="$(dart "$EVAL/tool/eval.dart" identity --manifest "$MANIFEST")"
SET_ID="${IDENTITY%% *}"
COMMIT="${IDENTITY##* }"
[ -n "$SET_ID" ] && [ "$SET_ID" != "$COMMIT" ] || { echo "no identity in $MANIFEST" >&2; exit 1; }
echo "evaluation identity: $SET_ID $COMMIT"

# The toolchain, read here rather than written into this script: every fact
# below is a property of the machine that runs it.
say "toolchain"
flutter --version --machine > "$OUT/flutter-version.json" 2> "$LOGS/flutter-version.log"
json_get() { dart "$EVAL/tool/eval.dart" json-get --file "$OUT/flutter-version.json" --key "$1"; }
FLUTTER_VERSION="$(json_get frameworkVersion)"
DART_VERSION="$(json_get dartSdkVersion)"
FLUTTER_ROOT_DIR="$(json_get flutterRoot)"
XCODE_VERSION="$(xcodebuild -version 2>/dev/null | tr '\n' ' ' | sed 's/ *$//' || true)"
[ -n "$XCODE_VERSION" ] || XCODE_VERSION=unknown
IOS_SDK_SETTINGS="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)/SDKSettings.plist"
plist_get() { plutil -extract "$1" raw "$2" 2>/dev/null || echo unknown; }
IOS_SDK_MIN="$(plist_get SupportedTargets.iphoneos.MinimumDeploymentTarget "$IOS_SDK_SETTINGS")"
IOS_SDK_MAX="$(plist_get SupportedTargets.iphoneos.MaximumDeploymentTarget "$IOS_SDK_SETTINGS")"
FLUTTER_IOS_MIN="$(plist_get MinimumOSVersion \
  "$FLUTTER_ROOT_DIR/bin/cache/artifacts/engine/ios/Flutter.xcframework/ios-arm64/Flutter.framework/Info.plist")"
POD_TARGET="$(sed -n "s/^wcf_deployment_target = '\([0-9.]*\)'$/\1/p" \
  packages/wallet_core_flutter_native/ios/wallet_core_flutter_native.podspec)"
APP_IOS_TARGET="$(grep -o 'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]*' \
  "$EVAL/consumer/ios/Runner.xcodeproj/project.pbxproj" | head -1 | sed 's/.* //')"
echo "Flutter $FLUTTER_VERSION / Dart $DART_VERSION; $XCODE_VERSION; iphoneos deployment ${IOS_SDK_MIN}–$IOS_SDK_MAX; Flutter.framework min $FLUTTER_IOS_MIN; pod $POD_TARGET; consumer app $APP_IOS_TARGET"

# `a <= b` for dotted versions.
version_le() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)" = "$1" ]; }
deployment_status=pass
for declared in "$POD_TARGET" "$APP_IOS_TARGET"; do
  if [ "$IOS_SDK_MIN" = unknown ] || ! version_le "$IOS_SDK_MIN" "$declared"; then
    deployment_status=fail
  fi
done
row --check min-version --target host/xcode --status "$deployment_status" \
  --command "xcodebuild -version ; plutil -extract SupportedTargets.iphoneos.{Minimum,Maximum}DeploymentTarget raw \$(xcrun --sdk iphoneos --show-sdk-path)/SDKSettings.plist ; plutil -extract MinimumOSVersion raw <flutterRoot>/bin/cache/artifacts/engine/ios/Flutter.xcframework/ios-arm64/Flutter.framework/Info.plist" \
  --value "flutter=$FLUTTER_VERSION" --value "dart=$DART_VERSION" --value "xcode=$XCODE_VERSION" \
  --value "iphoneos_deployment_min=$IOS_SDK_MIN" --value "iphoneos_deployment_max=$IOS_SDK_MAX" \
  --value "flutter_framework_min_ios=$FLUTTER_IOS_MIN" --value "pod_deployment_target=$POD_TARGET" \
  --value "consumer_app_deployment_target=$APP_IOS_TARGET" \
  --summary "$XCODE_VERSION accepts iOS ${IOS_SDK_MIN}–$IOS_SDK_MAX; Flutter.framework $FLUTTER_IOS_MIN; pod $POD_TARGET; app $APP_IOS_TARGET" \
  --notes "pass means both the pod's and the consumer app's deployment targets are ones this Xcode accepts. An app whose template target is below $IOS_SDK_MIN does not build for iOS on this Xcode at all."

# Android tooling (T1.9b), read from the machine. The NDK is the one the
# installed Flutter's Gradle plugin defaults to (else the newest installed):
# its llvm-nm and llvm-readelf read the packaged libraries, and its
# sysroot's libc++_shared.so is the fixture plugin's copy in step 9.
ANDROID_SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
ADB="$(command -v adb || true)"
[ -n "$ADB" ] || ADB="$ANDROID_SDK/platform-tools/adb"
APKSIGNER="$(ls -d "$ANDROID_SDK"/build-tools/*/ 2>/dev/null | sort -V | tail -1)apksigner"
NDK_ROOT="$ANDROID_SDK/ndk"
FLUTTER_NDK="$(grep -ho 'val ndkVersion: String = "[^"]*"' \
  "$FLUTTER_ROOT_DIR/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt" 2>/dev/null \
  | sed 's/.*= "//; s/"$//' || true)"
if [ -n "$FLUTTER_NDK" ] && [ -d "$NDK_ROOT/$FLUTTER_NDK" ]; then
  NDK="$NDK_ROOT/$FLUTTER_NDK"
else
  NDK="$(ls -d "$NDK_ROOT"/*/ 2>/dev/null | sort -V | tail -1)"
  NDK="${NDK%/}"
fi
[ -n "$NDK" ] && [ -d "$NDK" ] || { echo "run_eval.sh: no Android NDK under $NDK_ROOT" >&2; exit 1; }
NDK_BIN="$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin"
READELF="$NDK_BIN/llvm-readelf"
LLVM_NM="$NDK_BIN/llvm-nm"
for t in "$ADB" "$APKSIGNER" "$READELF" "$LLVM_NM"; do
  [ -x "$t" ] || { echo "run_eval.sh: $t not found" >&2; exit 1; }
done
# The set's own NDK (manifest toolchain.ndk): the libc++_shared.so a
# c++_shared build of the set would have shipped (step 9's counterfactual).
SET_NDK_VERSION="$(dart "$EVAL/tool/eval.dart" json-get --file "$MANIFEST" --key toolchain.ndk)"
SET_NDK="$NDK_ROOT/$SET_NDK_VERSION"
# The emulator that is already running (never booted here).
EMU_ID="${WCF_ANDROID_EMULATOR:-}"
if [ -z "$EMU_ID" ]; then
  EMU_ID="$("$ADB" devices 2>/dev/null | awk '$1 ~ /^emulator-/ && $2 == "device" { print $1; exit }' || true)"
fi
EMU_ABI=''
EMU_API=''
if [ -n "$EMU_ID" ]; then
  EMU_ABI="$("$ADB" -s "$EMU_ID" shell getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r' || true)"
  EMU_API="$("$ADB" -s "$EMU_ID" shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r' || true)"
fi
EMU_OK=0
[ -n "$EMU_ID" ] && [ "$EMU_ABI" = arm64-v8a ] && EMU_OK=1
EMU_NOTE="emulator ${EMU_ID:-none} (${EMU_ABI:-?}, API ${EMU_API:-?})"
echo "Android: NDK $(basename "$NDK") (Flutter default ${FLUTTER_NDK:-unknown}); set NDK $SET_NDK_VERSION; $EMU_NOTE"

# third_party/ is untrusted: every file used below is verified against the
# evaluation manifest by the package's own fetch tool before anything reads it.
# Into a cache of its own: the builds' $CACHE must start absent, or the
# measured pod install would read a cache this script warmed instead of the
# vendored set.
dart run packages/wallet_core_flutter_native/tool/fetch_artifacts.dart \
  --manifest "$MANIFEST" --cache-dir "$PREFLIGHT_CACHE" --vendored "$VENDORED" --offline \
  --only "$DEVICE_ROW" --only "$SIM_ROW" --only "$AND_ARM_ROW" --only "$AND_X64_ROW"

# The consumer resolves the two packages by path from staged copies, so that
# `pod install` writes the xcframework into $TMPDIR and never into packages/.
# The one edit is dropping `resolution: workspace`, which only a workspace
# member may carry.
mkdir -p "$STAGE"
for package in wallet_core_flutter_native wallet_core_flutter_bindings; do
  rsync -a --delete \
    --exclude .dart_tool --exclude build --exclude pubspec.lock \
    --exclude ios/Frameworks --exclude ios/.wcf_work --exclude android/.gradle \
    "packages/$package/" "$STAGE/$package/"
  grep -v '^resolution: workspace$' "packages/$package/pubspec.yaml" \
    > "$STAGE/$package/pubspec.yaml"
done

rsync -a --delete --exclude .dart_tool --exclude build \
  --exclude ios/Pods --exclude ios/.symlinks "$EVAL/consumer/" "$APP/"
cat > "$APP/pubspec_overrides.yaml" <<EOF
# Written by eval/option2/run_eval.sh into its working copy only.
dependency_overrides:
  wallet_core_flutter_native:
    path: $STAGE/wallet_core_flutter_native
  wallet_core_flutter_bindings:
    path: $STAGE/wallet_core_flutter_bindings
EOF

dart "$EVAL/tool/eval.dart" flip --manifest "$MANIFEST" --artifact "$SIM_ROW" --out "$FLIPPED"
# Self-consistent on purpose: the gate passes, and only the bytes disagree.
dart run tools/manifest/bin/validate.dart "$FLIPPED"
# The same for the Gradle task, on the arm64-v8a library.
FLIPPED_ANDROID="$OUT/eval_manifest.flipped-android.json"
dart "$EVAL/tool/eval.dart" flip --manifest "$MANIFEST" --artifact "$AND_ARM_ROW" --out "$FLIPPED_ANDROID"
dart run tools/manifest/bin/validate.dart "$FLIPPED_ANDROID"

# Build-time inputs of the podspec (and of the Gradle task, which reads the
# same names). The fetch makes no request: --offline, from the vendored set.
export WCF_MANIFEST="$MANIFEST"
export WCF_VENDORED_DIR="$VENDORED"
export WCF_OFFLINE=1
export WCF_ARTIFACT_DIR="$CACHE"

IDENTITY_DEFINES=(
  "--dart-define=WCF_EXPECT_ARTIFACT_SET_ID=$SET_ID"
  "--dart-define=WCF_EXPECT_UPSTREAM_COMMIT=$COMMIT"
)
TEST_CMD="flutter test integration_test/symbol_lookup_test.dart ${IDENTITY_DEFINES[*]}"
# `flutter test` has no --release option (Flutter 3.47.5: "Could not find an
# option named --release"), and `flutter drive --release` with the
# integration_test driver is refused too ("Flutter Driver (non-web) does not
# support running in release mode", measured on the Android emulator,
# 2026-10-04). A release build therefore runs lib/probe_main.dart, the same
# checks with one `WCF_PROBE PASS|FAIL` line in the device log.
PROBE_CMD="-t lib/probe_main.dart ${IDENTITY_DEFINES[*]}"

# Builds recorded `skip`, one "<target> TAB <summary> TAB <notes>" line each.
# Every row that needs the build's output inherits the skip and its reason
# instead of being attempted (inherit_skip).
TAB="$(printf '\t')"
SKIPPED="$OUT/skipped-builds.tsv"
: > "$SKIPPED"
skipped_build() { grep -q "^$1$TAB" "$SKIPPED"; }
# The on-target command for a "<device>/<debug|release>" target, as text.
on_target_cmd() { # target device-id
  if [ "${1##*/}" = release ]; then
    echo "flutter run --release -d $2 $PROBE_CMD (look for WCF_PROBE PASS in the device log)"
  else
    echo "$TEST_CMD -d $2"
  fi
}
inherit_skip() { # check target command
  local line
  line="$(grep -m1 "^$2$TAB" "$SKIPPED")"
  row --check "$1" --target "$2" --status skip --command "$3" \
    --summary "$(printf '%s\n' "$line" | cut -f2)" \
    --notes "not run: consumer-build $2 was skipped ($(printf '%s\n' "$line" | cut -f3))"
}

# ---------------------------------------------------------------------------
# step 1 — clean consumer build, no manual native edits
# ---------------------------------------------------------------------------

say "step 1: pub get"
PUB_MODE=offline
if ! (cd "$APP" && flutter pub get --offline) > "$LOGS/pub-get.log" 2>&1; then
  PUB_MODE=online
  (cd "$APP" && flutter pub get) > "$LOGS/pub-get.log" 2>&1
fi
echo "pub get: $PUB_MODE"
BUILD_NOTE="pub get $PUB_MODE; artifact fetch --offline --vendored from the verified local set; WCF_MANIFEST=eval/option2/eval_manifest.json"
[ ! -e "$CACHE" ] || { echo "run_eval.sh: $CACHE exists before the first pod install" >&2; exit 1; }

# What `pod install` made of the podspec, read from the files CocoaPods wrote.
pod_integration_row() { # log of the flutter command that ran pod install
  local links=no slices=no embed=no privacy=no phase=no loadall=none
  # Flutter's SwiftPM notice, verbatim as this Flutter prints it.
  local spm
  spm="$(grep -m1 -A2 'Swift Package Manager' "$1" | tr '\n' ' ' | tr -s ' ' || true)"
  [ -n "$spm" ] || spm="none printed"
  grep -q -- '-framework "TrustWalletCore"' "$PODS_SUPPORT/Pods-Runner/Pods-Runner.debug.xcconfig" && links=yes
  grep -q 'install_xcframework .*TrustWalletCore.xcframework.*"ios-arm64" "ios-arm64_x86_64-simulator"' \
    "$PODS_SUPPORT/wallet_core_flutter_native/wallet_core_flutter_native-xcframeworks.sh" && slices=yes
  grep -q 'install_framework .*TrustWalletCore.framework' "$PODS_SUPPORT/Pods-Runner/Pods-Runner-frameworks.sh" && embed=yes
  grep -q 'wallet_core_flutter_native_privacy' "$APP/ios/Pods/Pods.xcodeproj/project.pbxproj" && privacy=yes
  grep -q 'Verify TrustWalletCore.xcframework against the manifest' "$APP/ios/Pods/Pods.xcodeproj/project.pbxproj" && phase=yes
  if grep -rqE -- '-all_load|-force_load' "$PODS_SUPPORT"; then loadall=present; fi
  local status=pass
  [ "$links$slices$embed$privacy$phase" = yesyesyesyesyes ] && [ "$loadall" = none ] || status=fail
  row --check pod-integration --target ios/pod --status "$status" \
    --command "cd \"\$APP/ios\" && pod install (via flutter build ios); grep the Pods support files" \
    --value "app_links_framework=$links" --value "xcframework_slices_copied=$slices" \
    --value "embedded=$embed" --value "privacy_bundle_target=$privacy" \
    --value "verify_script_phase=$phase" --value "load_all_flags=$loadall" \
    --value "swiftpm_notice=$spm" \
    --summary "-framework TrustWalletCore: $links; both slices: $slices; embed: $embed; privacy bundle: $privacy; script phase: $phase; -all_load/-force_load: $loadall" \
    --notes "$BUILD_NOTE"
  [ "$status" = pass ] || finish 1
}

build_ios() { # target slug app-path flutter-args...
  local target="$1" slug="$2" built="$3"
  shift 3
  local log="$LOGS/build-$slug.log" start=$SECONDS
  say "step 1: flutter $* ($target)"
  if (cd "$APP" && flutter "$@") > "$log" 2>&1; then
    local seconds=$((SECONDS - start))
    mkdir -p "$APPS/$slug"
    ditto "$APP/$built" "$APPS/$slug/Runner.app"
    # Debug builds put the app's code, and so its load commands, in
    # Runner.debug.dylib; Runner itself is a stub. Look in both.
    local links=no image
    for image in Runner Runner.debug.dylib; do
      [ -f "$APPS/$slug/Runner.app/$image" ] || continue
      if otool -L "$APPS/$slug/Runner.app/$image" 2>/dev/null \
          | grep -q '@rpath/TrustWalletCore.framework/TrustWalletCore'; then
        links="yes ($image)"
      fi
    done
    row --check consumer-build --target "$target" --status pass \
      --command "cd \"\$APP\" && flutter $*" \
      --value "seconds=$seconds" --value "log=$log" \
      --value "load_command_trustwalletcore=$links" \
      --summary "built in ${seconds} s; TrustWalletCore load command: $links" \
      --notes "$BUILD_NOTE"
    return 0
  fi
  if grep -q 'not supported for simulators' "$log"; then
    local summary="Flutter: release not supported on simulators"
    local notes
    notes="$(grep -m1 'not supported for simulators' "$log")"
    row --check consumer-build --target "$target" --status skip \
      --command "cd \"\$APP\" && flutter $*" --value "log=$log" \
      --summary "$summary" --notes "$notes"
    printf '%s\t%s\t%s\n' "$target" "$summary" "$notes" >> "$SKIPPED"
    return 1
  fi
  row --check consumer-build --target "$target" --status fail \
    --command "cd \"\$APP\" && flutter $*" --value "log=$log" \
    --notes "$(log_tail "$log")"
  echo "build failed: $log" >&2
  finish 1
}

if [ "$NO_XCODE" = 1 ]; then
  say "step 1: flutter build ios --config-only (pod install, no Xcode build)"
  POD_LOG="$LOGS/config-only.log"
  if ! (cd "$APP" && flutter build ios --config-only --debug --no-codesign) > "$POD_LOG" 2>&1; then
    # Since Flutter 3.47, --config-only asks `xcodebuild -list` for project
    # information before it runs pod install, and a host that refuses
    # Xcode's DerivedData/CoreSimulator fails there. By then Flutter has
    # written the Podfile and Flutter/Generated.xcconfig, which is all
    # `pod install` needs (Flutter's podhelper creates .symlinks/ itself), so
    # run the step Flutter would have run next. Any other failure is real.
    if grep -q 'Unable to get Xcode project information' "$POD_LOG" \
        && [ -f "$APP/ios/Podfile" ] && [ -f "$APP/ios/Flutter/Generated.xcconfig" ]; then
      echo "flutter build ios --config-only stopped at xcodebuild -list; running pod install directly"
      cp "$POD_LOG" "$LOGS/config-only-xcodebuild-list.log"
      POD_LOG="$LOGS/pod-install-direct.log"
      # The SwiftPM notice is Flutter's, so keep its lines with pod's output.
      grep -A2 'Swift Package Manager' "$LOGS/config-only-xcodebuild-list.log" > "$POD_LOG" || true
      (cd "$APP/ios" && pod install) >> "$POD_LOG" 2>&1
      BUILD_NOTE="$BUILD_NOTE; pod install run directly: flutter build ios --config-only stopped at xcodebuild -list (Unable to get Xcode project information) on this host"
    else
      echo "flutter build ios --config-only failed: $POD_LOG" >&2
      finish 1
    fi
  fi
  pod_integration_row "$POD_LOG"
  for t in "${IOS_APP_TARGETS[@]}"; do
    unmeasured consumer-build "$t" "eval/option2/run_eval.sh (flutter build ios … in \$APP)" "$ORCHESTRATOR"
  done
else
  build_ios ios-simulator-arm64/debug ios-simulator-arm64-debug \
    build/ios/iphonesimulator/Runner.app build ios --simulator --debug
  pod_integration_row "$LOGS/build-ios-simulator-arm64-debug.log"
  # A skip here is recorded in $SKIPPED and inherited by the rows that need it.
  build_ios ios-simulator-arm64/release ios-simulator-arm64-release \
    build/ios/iphonesimulator/Runner.app build ios --simulator --release || true
  build_ios ios-device-arm64/debug ios-device-arm64-debug \
    build/ios/iphoneos/Runner.app build ios --debug --no-codesign
  # `flutter build ipa` archives (step 10's release-archive link) as well as
  # building; with --no-codesign it stops at the .xcarchive.
  build_ios ios-device-arm64/release ios-device-arm64-release \
    build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app \
    build ipa --no-codesign
fi
# The first pod install above started without $CACHE; with --offline, the
# vendored directory is the only source it had (step 7).
CACHE_FILLED="$(cache_files "$CACHE")"

# Android (T1.9b). The debug APK first, so it is the app's first Gradle build
# and its wcfPrepareDebugJniLibs task the first fetch of the Android rows into
# $CACHE (step 7 counts them before and after), then release. `-v` so the log
# carries Gradle's task graph and the task's own output (where the libraries
# came from). Each APK is copied away right after its build: later steps
# rebuild the same outputs (step 2's `flutter test -d <emulator>` for one ABI
# only, the release probe with another entry point).
mkdir -p "$AND_APPS"
APK_OUT="$APP/build/app/outputs/flutter-apk"
AND_CACHE_BEFORE="$(so_cache_files "$CACHE")"
android_build() { # mode -> BUILD_RC, BUILD_SECONDS
  local mode="$1" log="$LOGS/build-android-$1.log" start=$SECONDS
  say "step 1: flutter build apk --$mode --target-platform $ANDROID_PLATFORMS"
  BUILD_RC=0
  (cd "$APP" && flutter build apk "--$mode" --target-platform "$ANDROID_PLATFORMS" \
    "${IDENTITY_DEFINES[@]}" -v) > "$log" 2>&1 || BUILD_RC=$?
  BUILD_SECONDS=$((SECONDS - start))
  if [ "$BUILD_RC" = 0 ]; then cp "$APK_OUT/app-$mode.apk" "$AND_APPS/app-$mode.apk"; fi
}
android_build debug
AND_DEBUG_RC=$BUILD_RC
AND_DEBUG_SECONDS=$BUILD_SECONDS
AND_CACHE_AFTER="$(so_cache_files "$CACHE")"
android_build release
AND_RELEASE_RC=$BUILD_RC
AND_RELEASE_SECONDS=$BUILD_SECONDS

# android_build_rows MODE: the consumer-build rows of one APK. `pass` only if
# the APK holds our library for both shipped ABIs.
android_build_rows() {
  local mode="$1" rc seconds log="$LOGS/build-android-$1.log" libs abi task
  if [ "$mode" = debug ]; then
    rc=$AND_DEBUG_RC; seconds=$AND_DEBUG_SECONDS; task=wcfPrepareDebugJniLibs
  else
    rc=$AND_RELEASE_RC; seconds=$AND_RELEASE_SECONDS; task=wcfPrepareReleaseJniLibs
  fi
  local cmd="cd \"\$APP\" && flutter build apk --$mode --target-platform $ANDROID_PLATFORMS ${IDENTITY_DEFINES[*]} -v && unzip -l build/app/outputs/flutter-apk/app-$mode.apk"
  if [ "$rc" != 0 ]; then
    for t in "$AND_ARM/$mode" "$AND_X64/$mode"; do
      row --check consumer-build --target "$t" --status fail --command "$cmd" \
        --value "log=$log" --notes "$(log_tail "$log")"
    done
    echo "Android $mode build failed: $log" >&2
    finish 1
  fi
  libs="$(apk_libs "$AND_APPS/app-$mode.apk")"
  for abi in arm64-v8a x86_64; do
    case "$libs, " in
      *"lib/$abi/libTrustWalletCore.so "*) ;;
      *)
        row --check consumer-build --target "$AND_ARM/$mode" --status fail --command "$cmd" \
          --summary "no $abi library in the APK" --notes "APK native libraries (bytes): $libs; log: $log"
        finish 1
        ;;
    esac
  done
  local prepared
  prepared="$(prepare_lines "$log" "$task")"
  row --check consumer-build --target "$AND_ARM/$mode" --status pass --command "$cmd" \
    --value "seconds=$seconds" --value "log=$log" --value "apk_native_libraries=$libs" \
    --value "gradle_task=$task: ${prepared:-no output (UP-TO-DATE?)}" \
    --summary "built in ${seconds} s; arm64-v8a and x86_64 .so in the APK" \
    --notes "APK native libraries (bytes): $libs. $task: ${prepared:-no fetch-tool output in the log}. $BUILD_NOTE"
  row --check consumer-build --target "$AND_X64/$mode" --status pass --command "$cmd" \
    --value "log=$log" \
    --summary "built in ${seconds} s; x86_64 .so in the APK" \
    --notes "the same APK as $AND_ARM/$mode (one APK carries both ABIs). $NO_X64"
  row --check consumer-build --target "$AND_DEV/$mode" --status unmeasured \
    --command "$cmd && adb -s <arm64-device-id> install build/app/outputs/flutter-apk/app-$mode.apk" \
    --summary 'no physical device' --notes "$NO_DEVICE"
}
android_build_rows debug
android_build_rows release

# What the Gradle integration is, read from the debug build: the task in the
# graph and where it sits, the generated jniLibs directory it hands to AGP,
# and that the consumer's Gradle files are still as `flutter create` wrote
# them (no manual native edit).
GRADLE_LOG="$LOGS/build-android-debug.log"
GEN_DIR="$APP/build/wallet_core_flutter_native/generated/jniLibs/wcfPrepareDebugJniLibs"
task_graph="$(grep -m1 'Tasks to be executed:' "$GRADLE_LOG" | tr ',' '\n' \
  | grep -E "wcfPrepareDebugJniLibs|:wallet_core_flutter_native:mergeDebugJniLibFolders|:app:mergeDebugNativeLibs|:app:stripDebugDebugSymbols|:app:packageDebug'" \
  | sed "s/.*task '//; s/'.*//" | tr '\n' ' ' | sed 's/ $//' | sed 's/ / -> /g' || true)"
gen_libs="$(cd "$GEN_DIR" 2>/dev/null && find . -name '*.so' | sed 's|^\./||' | sort | tr '\n' ' ' | sed 's/ $//' || true)"
gradle_edits=none
for f in android/build.gradle.kts android/settings.gradle.kts android/app/build.gradle.kts android/gradle.properties; do
  cmp -s "$EVAL/consumer/$f" "$APP/$f" || gradle_edits="$gradle_edits $f"
done
gradle_edits="${gradle_edits#none }"
dart_line="$(grep -m1 "Starting process 'command '.*/bin/dart''" "$GRADLE_LOG" | sed 's/^\[[^]]*\] *//; s/Command: .*//' || true)"
status=pass
{ [ -n "$task_graph" ] && [ "$gen_libs" = 'arm64-v8a/libTrustWalletCore.so x86_64/libTrustWalletCore.so' ] \
  && [ "$gradle_edits" = none ]; } || status=fail
row --check gradle-integration --target android/gradle --status "$status" \
  --command "cd \"\$APP\" && flutter build apk --debug --target-platform $ANDROID_PLATFORMS -v; read the task graph, \$APP/build/wallet_core_flutter_native/generated/jniLibs/, cmp the consumer's Gradle files with eval/option2/consumer" \
  --value "task_chain=$task_graph" --value "generated_jnilibs=$GEN_DIR" \
  --value "generated_files=$gen_libs" --value "consumer_gradle_edits=$gradle_edits" \
  --value "tool_process=$dart_line" \
  --summary "wcfPrepareDebugJniLibs in the graph before AGP's merge; generated jniLibs: $gen_libs; consumer Gradle edits: $gradle_edits" \
  --notes "task chain: $task_graph. The task runs the package's tool/option2/prepare_jni_libs.dart with the Flutter SDK's dart ($dart_line) and hands AGP build/wallet_core_flutter_native/generated/jniLibs/wcfPrepareDebugJniLibs through variant.sources.jniLibs.addGeneratedSourceDirectory; nothing is written under the package's or the app's src/"
[ "$status" = pass ] || finish 1

# armeabi-v7a is not shipped. What a consumer meets, measured once in copies
# of their own: a default `flutter build apk` (no --target-platform: Flutter
# targets android-arm, android-arm64 and android-x64), and the same with
# `ndk { abiFilters += listOf("arm64-v8a", "x86_64") }` added to the app's
# build.gradle.kts — the remedy an Android developer reaches for first.
ABI_APP="$OUT/abi"
stage_app "$ABI_APP"
ABI_CMD="(working copy of eval/option2/consumer) && flutter build apk --release ${IDENTITY_DEFINES[*]}   # no --target-platform"
rc=0
(cd "$ABI_APP" && flutter build apk --release "${IDENTITY_DEFINES[@]}") > "$LOGS/build-android-default-abis.log" 2>&1 || rc=$?
default_v7a="build exit $rc"
if [ "$rc" = 0 ]; then
  cp "$ABI_APP/build/app/outputs/flutter-apk/app-release.apk" "$AND_APPS/app-release-default-abis.apk"
  default_v7a="build exit 0; APK lib/armeabi-v7a/: $(apk_abi_libs "$AND_APPS/app-release-default-abis.apk" armeabi-v7a)"
fi
default_msg="$(grep -i -m1 -E 'armeabi|wallet_core_flutter_native.*(warn|abi)' "$LOGS/build-android-default-abis.log" || true)"
sed -i '' 's|^        versionName = flutter.versionName$|        versionName = flutter.versionName\
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }|' "$ABI_APP/android/app/build.gradle.kts"
grep -q 'abiFilters' "$ABI_APP/android/app/build.gradle.kts" || { echo "run_eval.sh: could not add abiFilters" >&2; exit 1; }
rm -rf "$ABI_APP/build"
rc=0
(cd "$ABI_APP" && flutter build apk --release "${IDENTITY_DEFINES[@]}") > "$LOGS/build-android-abifilters.log" 2>&1 || rc=$?
filters_v7a="build exit $rc"
if [ "$rc" = 0 ]; then
  cp "$ABI_APP/build/app/outputs/flutter-apk/app-release.apk" "$AND_APPS/app-release-abifilters.apk"
  filters_v7a="build exit 0; APK lib/armeabi-v7a/: $(apk_abi_libs "$AND_APPS/app-release-abifilters.apk" armeabi-v7a)"
fi
target_platform_arg="$(grep -m1 -o -- '-Ptarget-platform=[^ ]*' "$LOGS/build-android-release.log" || true)"
row --check consumer-build --target android/armeabi-v7a --status skip --summary "$NOT_SHIPPED" \
  --command "$ABI_CMD; then the same with ndk { abiFilters += listOf(\"arm64-v8a\", \"x86_64\") } in android/app/build.gradle.kts" \
  --value "default_build=$default_v7a" --value "default_build_message=${default_msg:-none}" \
  --value "abifilters_build=$filters_v7a" \
  --notes "as_4.8.0_001 builds no armeabi-v7a library, and the Gradle task packages exactly the manifest's ABIs. A default-ABI build is NOT refused: $default_v7a (no libTrustWalletCore.so), Gradle message: ${default_msg:-none}. With abiFilters arm64-v8a,x86_64 in the app's defaultConfig.ndk: $filters_v7a. Only --target-platform $ANDROID_PLATFORMS keeps android-arm out of the APK (Flutter passes it to Gradle as ${target_platform_arg:--Ptarget-platform}). logs: $LOGS/build-android-default-abis.log, $LOGS/build-android-abifilters.log"

# ---------------------------------------------------------------------------
# step 2 — run on target; step 4 (runtime half) — full symbol lookup
# ---------------------------------------------------------------------------

run_test() { # target slug device debug|release
  local target="$1" slug="$2" device="$3" mode="$4"
  local log="$LOGS/test-$slug.log"
  local cmd
  if [ "$mode" = release ]; then
    cmd=(flutter run --release -d "$device" -t lib/probe_main.dart "${IDENTITY_DEFINES[@]}")
  else
    cmd=(flutter test integration_test/symbol_lookup_test.dart "${IDENTITY_DEFINES[@]}"
      -d "$device")
  fi
  # Nothing to run on when the build this run needs was skipped.
  if skipped_build "$target"; then
    say "step 2: $target not run (its build was skipped)"
    inherit_skip run-on-target "$target" "${cmd[*]}"
    inherit_skip symbols-runtime-lookup "$target" "${cmd[*]}"
    return 0
  fi
  # A release run on an iOS device is the probe under `flutter run --release`
  # (Flutter Driver refuses release mode), which stays attached to the app;
  # this script does not drive it.
  if [ "$mode" = release ]; then
    for check in run-on-target symbols-runtime-lookup; do
      unmeasured "$check" "$target" "${cmd[*]} (look for WCF_PROBE PASS)" \
        "release on an iOS device: run the probe by hand and read its WCF_PROBE line; Flutter Driver refuses release mode (measured on Android, 2026-10-04)"
    done
    return 0
  fi
  say "step 2: integration test on $device ($target)"
  local status=pass retry_note=''
  (cd "$APP" && "${cmd[@]}") > "$log" 2>&1 || status=fail
  # Flutter's tooling, not the app: observed once on the Android emulator
  # right after the simulator run (T1.9b, 2026-10-04), and passing when rerun.
  # One retry, recorded in the row.
  if [ "$status" = fail ] && grep -q 'Failed to start Dart Development Service' "$log"; then
    cp "$log" "$log.first-attempt"
    retry_note="first attempt failed to load the test: 'Failed to start Dart Development Service' ($log.first-attempt); rerun once"
    status=pass
    (cd "$APP" && "${cmd[@]}") > "$log" 2>&1 || status=fail
  fi
  if [ "$status" = fail ] && grep -q 'not supported' "$log"; then
    local notes
    notes="$(grep -m1 'not supported' "$log")"
    for check in run-on-target symbols-runtime-lookup; do
      row --check "$check" --target "$target" --status skip \
        --command "${cmd[*]}" --value "log=$log" \
        --summary "Flutter: $mode not supported on this target" --notes "$notes"
    done
    return 0
  fi
  local notes=""
  [ "$status" = fail ] && notes="$(log_tail "$log")"
  [ -z "$retry_note" ] || notes="${notes:+$notes; }$retry_note"
  local resolved via set_id summary
  resolved="$(grep -o 'WCF-EVAL symbols_resolved=[^ ]*' "$log" | head -1 | cut -d= -f2 || true)"
  via="$(grep -o 'WCF-EVAL resolved_by=.*' "$log" | head -1 | cut -d= -f2- || true)"
  set_id="$(grep -o 'WCF-EVAL identity_artifact_set_id=[^ ]*' "$log" | head -1 | cut -d= -f2 || true)"
  # A summary, so the table cell is one line and not every value (log path
  # included).
  row --check run-on-target --target "$target" --status "$status" \
    --command "${cmd[*]}" --value "log=$log" --log-values "$log" \
    --summary "$([ "$status" = pass ] && echo "ran; identity ${set_id:-?} verified; library via ${via:-?}" || echo "test failed (see notes)")" \
    --notes "$notes"
  if [ -n "$resolved" ]; then
    summary="$resolved resolved; via $via"
  else
    summary="no lookup result in the test output (see run-on-target notes)"
  fi
  row --check symbols-runtime-lookup --target "$target" --status "$status" \
    --command "${cmd[*]}" --log-values "$log" --summary "$summary"
}

SIM="${WCF_IOS_SIMULATOR:-}"
if [ -z "$SIM" ] && [ "$NO_XCODE" = 0 ]; then
  SIM="$(xcrun simctl list devices booted 2>/dev/null \
    | sed -n 's/.*(\([0-9A-F-]\{36\}\)) (Booted).*/\1/p' | head -1 || true)"
fi
if [ "$NO_XCODE" = 0 ] && [ -n "$SIM" ]; then
  run_test ios-simulator-arm64/debug ios-simulator-arm64-debug "$SIM" debug
  run_test ios-simulator-arm64/release ios-simulator-arm64-release "$SIM" release
else
  why="$ORCHESTRATOR"
  [ "$NO_XCODE" = 0 ] && why="orchestrator-run: no booted simulator"
  for t in ios-simulator-arm64/debug ios-simulator-arm64/release; do
    if skipped_build "$t"; then
      inherit_skip run-on-target "$t" "$(on_target_cmd "$t" '<booted simulator id>')"
      inherit_skip symbols-runtime-lookup "$t" "$(on_target_cmd "$t" '<booted simulator id>')"
      continue
    fi
    unmeasured run-on-target "$t" "$(on_target_cmd "$t" '<booted simulator id>')" "$why"
    unmeasured symbols-runtime-lookup "$t" "$(on_target_cmd "$t" '<booted simulator id>')" "$why"
  done
fi
if [ "$NO_XCODE" = 0 ] && [ -n "${WCF_IOS_DEVICE:-}" ]; then
  run_test ios-device-arm64/debug ios-device-arm64-debug "$WCF_IOS_DEVICE" debug
  run_test ios-device-arm64/release ios-device-arm64-release "$WCF_IOS_DEVICE" release
else
  for t in ios-device-arm64/debug ios-device-arm64/release; do
    unmeasured run-on-target "$t" "WCF_IOS_DEVICE=<id> eval/option2/run_eval.sh ($(on_target_cmd "$t" '<id>'))" "device: physical iPhone (T1.9b)"
    unmeasured symbols-runtime-lookup "$t" "WCF_IOS_DEVICE=<id> eval/option2/run_eval.sh ($(on_target_cmd "$t" '<id>'))" "device: physical iPhone (T1.9b)"
  done
fi

# Android: the arm64-v8a emulator that is already running. Debug runs the
# integration test (`flutter test -d`, which rebuilds the debug APK for that
# one ABI — step 1's copies are what later steps measure); release builds the
# probe entry point with step 1's release configuration, installs it with adb,
# cold-starts it and reads its WCF_PROBE line from logcat.
PROBE_APK="$AND_APPS/app-release-probe.apk"
PROBE_BUILD="cd \"\$APP\" && flutter build apk --release --target-platform $ANDROID_PLATFORMS $PROBE_CMD"
probe_cmd() {
  echo "$PROBE_BUILD && adb -s $1 install -r build/app/outputs/flutter-apk/app-release.apk && adb -s $1 shell am start -W -n $AND_PACKAGE/.MainActivity && adb -s $1 logcat -d -s flutter:I   (look for WCF_PROBE PASS)"
}
PROBE_PASS=0
AND_PROBE_LINE=''
AND_LAUNCH=''
if [ "$EMU_OK" = 1 ]; then
  run_test "$AND_ARM/debug" android-emulator-debug "$EMU_ID" debug
  say "step 2: release probe on $EMU_ID ($AND_ARM/release)"
  rc=0
  (cd "$APP" && flutter build apk --release --target-platform "$ANDROID_PLATFORMS" \
    -t lib/probe_main.dart "${IDENTITY_DEFINES[@]}") > "$LOGS/build-android-release-probe.log" 2>&1 || rc=$?
  if [ "$rc" != 0 ]; then
    for check in run-on-target symbols-runtime-lookup; do
      row --check "$check" --target "$AND_ARM/release" --status fail --command "$(probe_cmd "$EMU_ID")" \
        --summary 'probe build failed' --notes "$(log_tail "$LOGS/build-android-release-probe.log")"
    done
    finish 1
  fi
  cp "$APK_OUT/app-release.apk" "$PROBE_APK"
  android_probe "$PROBE_APK" "$LOGS/run-android-emulator-release.log"
  case "$PROBE_LINE" in
    'WCF_PROBE PASS'*)
      PROBE_PASS=1
      AND_PROBE_LINE="$PROBE_LINE"
      AND_LAUNCH="$LAUNCH"
      row --check run-on-target --target "$AND_ARM/release" --status pass --command "$(probe_cmd "$EMU_ID")" \
        --value "log=$LOGS/run-android-emulator-release.log" --value "probe=$PROBE_LINE" \
        --summary "ran; identity $(printf '%s' "$PROBE_LINE" | sed -n 's/.*identity=\([^@ ]*\).*/\1/p') verified; library via $(printf '%s' "$PROBE_LINE" | sed -n 's/.*resolved_by=\(.*\) TWAnyAddressIsValid.*/\1/p')" \
        --notes "$EMU_NOTE; am start -W: $LAUNCH; $PROBE_LINE"
      row --check symbols-runtime-lookup --target "$AND_ARM/release" --status pass --command "$(probe_cmd "$EMU_ID")" \
        --value "probe=$PROBE_LINE" \
        --summary "$(printf '%s' "$PROBE_LINE" | sed -n 's/.*symbols=\([^ ]*\).*/\1/p') resolved; via $(printf '%s' "$PROBE_LINE" | sed -n 's/.*resolved_by=\(.*\) TWAnyAddressIsValid.*/\1/p')"
      ;;
    *)
      for check in run-on-target symbols-runtime-lookup; do
        row --check "$check" --target "$AND_ARM/release" --status fail --command "$(probe_cmd "$EMU_ID")" \
          --summary 'probe did not pass' \
          --notes "${PROBE_LINE:-no WCF_PROBE line in logcat within 60 s}; am start -W: ${LAUNCH:-none}; log: $LOGS/run-android-emulator-release.log"
      done
      finish 1
      ;;
  esac
else
  for check in run-on-target symbols-runtime-lookup; do
    unmeasured "$check" "$AND_ARM/debug" "$(on_target_cmd "$AND_ARM/debug" '<arm64-emulator-id>')" \
      "needs a running arm64-v8a emulator (this script never boots one); found: $EMU_NOTE"
    unmeasured "$check" "$AND_ARM/release" "$(probe_cmd '<arm64-emulator-id>')" \
      "needs a running arm64-v8a emulator (this script never boots one); found: $EMU_NOTE"
  done
fi
for mode in debug release; do
  if [ "$mode" = debug ]; then
    x64_cmd="$(on_target_cmd "$AND_X64/debug" '<x86_64-emulator-id>')"
    dev_cmd="$(on_target_cmd "$AND_DEV/debug" '<arm64-device-id>')"
  else
    x64_cmd="$(probe_cmd '<x86_64-emulator-id>')"
    dev_cmd="$(probe_cmd '<arm64-device-id>')"
  fi
  for check in run-on-target symbols-runtime-lookup; do
    row --check "$check" --target "$AND_X64/$mode" --status unmeasured --summary 'no x86_64 emulator here' \
      --command "$x64_cmd" --notes "$NO_X64"
    row --check "$check" --target "$AND_DEV/$mode" --status unmeasured --summary 'no physical device' \
      --command "$dev_cmd" --notes "$NO_DEVICE"
  done
done

# ---------------------------------------------------------------------------
# step 3 — release build launches and signs
# ---------------------------------------------------------------------------

unmeasured release-launch-and-sign ios-device-arm64/release \
  "flutter build ipa (signed) && WCF_IOS_DEVICE=<id> eval/option2/run_eval.sh" \
  "device: needs a signing identity and a physical iPhone; the release archive is built --no-codesign here (T1.9b)"
# Android: step 2's release probe APK — step 1's release configuration with
# the probe's entry point — launched on the emulator, and its signature
# verified.
SIGN_CMD="$(probe_cmd "${EMU_ID:-<arm64-emulator-id>}") && apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk"
if [ "$PROBE_PASS" = 1 ]; then
  sign="$("$APKSIGNER" verify --print-certs "$PROBE_APK" 2>&1 || true)"
  signer="$(printf '%s\n' "$sign" | sed -n 's/^Signer #1 certificate DN: //p' | head -1)"
  sign_rc=0
  "$APKSIGNER" verify "$PROBE_APK" > /dev/null 2>&1 || sign_rc=$?
  case "$sign_rc:$AND_LAUNCH" in
    0:*'Status: ok'*)
      row --check release-launch-and-sign --target "$AND_ARM/release" --status pass --command "$SIGN_CMD" \
        --value "launch=$AND_LAUNCH" --value "signer=$signer" \
        --summary 'launched, probe PASS; signed with the debug keystore' \
        --notes "$EMU_NOTE; am start -W: $AND_LAUNCH; apksigner verify: OK, signer $signer. The flutter create template signs release with signingConfigs.debug; an upload key is the app author's, not a property of the packaging option. $AND_PROBE_LINE"
      ;;
    *)
      row --check release-launch-and-sign --target "$AND_ARM/release" --status fail --command "$SIGN_CMD" \
        --summary 'release did not launch or verify' \
        --notes "am start -W: ${AND_LAUNCH:-none}; apksigner verify exit $sign_rc: $sign"
      ;;
  esac
else
  unmeasured release-launch-and-sign "$AND_ARM/release" "$SIGN_CMD" \
    "needs step 2's release probe on an arm64-v8a emulator; $EMU_NOTE"
fi
row --check release-launch-and-sign --target "$AND_X64/release" --status unmeasured \
  --summary 'no x86_64 emulator here' --command "$(probe_cmd '<x86_64-emulator-id>')" --notes "$NO_X64"
row --check release-launch-and-sign --target "$AND_DEV/release" --status unmeasured \
  --summary 'no physical device' --command "$(probe_cmd '<arm64-device-id>')" --notes "$NO_DEVICE"

# ---------------------------------------------------------------------------
# The xcframework `pod install` produced, measured by steps 4, 5 and 10.
# ---------------------------------------------------------------------------

plutil -lint "$XCF_ROOT/TrustWalletCore.xcframework/Info.plist" \
  "$XCF_ROOT/TrustWalletCore.xcframework/ios-arm64/TrustWalletCore.framework/Info.plist" \
  "$XCF_ROOT/TrustWalletCore.xcframework/ios-arm64_x86_64-simulator/TrustWalletCore.framework/Info.plist" \
  "$XCF_ROOT/TrustWalletCore.xcframework/ios-arm64/TrustWalletCore.framework/PrivacyInfo.xcprivacy"
(cd "$XCF_ROOT" && shasum -a 256 -c wcf_binaries.sha256)

# ---------------------------------------------------------------------------
# step 4 — exported symbols of the shipped library
# ---------------------------------------------------------------------------

say "step 4: exported symbols"
harness symbols --artifact "$XCF_ROOT/$XCF_DEVICE_BIN" --format macho --target ios/arm64
harness symbols --artifact "$XCF_ROOT/$XCF_SIM_BIN" --format macho --target ios-simulator/arm64_x86_64
if [ "$NO_XCODE" = 0 ]; then
  for slug in ios-simulator-arm64-debug ios-device-arm64-release; do
    harness symbols --artifact "$APPS/$slug/Runner.app/$EMBEDDED_BIN" --format macho \
      --target "$(target_of "$slug")"
  done
fi
# Android: the libraries as Gradle packaged them, out of step 1's release APK
# (the copy taken right after its build) — the library columns, as the
# xcframework's binaries are for iOS — and whether those bytes are still the
# pinned ones (risk 7 of DECISION-2-option2.md: AGP strips packaged .so files).
mkdir -p "$AND_APPS/release" "$AND_APPS/debug"
unzip -o -q "$AND_APPS/app-release.apk" 'lib/*' -d "$AND_APPS/release"
unzip -o -q "$AND_APPS/app-debug.apk" 'lib/*' -d "$AND_APPS/debug"
APK_SO_CMD="unzip -o \"\$OUT/apps/android/app-release.apk\" 'lib/*' -d \"\$OUT/apps/android/release\""
for abi in arm64-v8a x86_64; do
  harness symbols --artifact "$AND_APPS/release/lib/$abi/libTrustWalletCore.so" --format elf \
    --nm "$LLVM_NM" --target "android/$abi" "${JNI_ALLOW[@]}"
done
row --check symbols --target android/armeabi-v7a --status skip --summary "$NOT_SHIPPED" \
  --command "$APK_SO_CMD && dart run tools/packaging_eval/bin/symbols.dart --artifact \"\$OUT/apps/android/release/lib/armeabi-v7a/libTrustWalletCore.so\" --format elf --target android/armeabi-v7a" \
  --notes "$NOT_SHIPPED_NOTE"
for abi in arm64-v8a x86_64; do
  manifest_sha="$(dart "$EVAL/tool/eval.dart" json-get --file "$MANIFEST" --key "artifacts.android/$abi/libTrustWalletCore.so.sha256" 2>/dev/null || true)"
  for mode in release debug; do
    apk_sha="$(shasum -a 256 "$AND_APPS/$mode/lib/$abi/libTrustWalletCore.so" | cut -d' ' -f1)"
    apk_size="$(wc -c < "$AND_APPS/$mode/lib/$abi/libTrustWalletCore.so" | tr -d ' ')"
    if [ "$apk_sha" = "$manifest_sha" ]; then
      status=pass; summary="$mode APK: the pinned bytes (sha256 = manifest)"
    else
      status=fail; summary="$mode APK: NOT the pinned bytes"
    fi
    row --check packaged-digest --target "android/$abi" --status "$status" \
      --command "unzip -p \"\$OUT/apps/android/app-$mode.apk\" lib/$abi/libTrustWalletCore.so | shasum -a 256" \
      --value "apk_sha256=$apk_sha" --value "apk_size=$apk_size" --value "manifest_sha256=$manifest_sha" \
      --summary "$summary" \
      --notes "lib/$abi/libTrustWalletCore.so in the $mode APK: sha256 $apk_sha, $apk_size B; the manifest pins android/$abi/libTrustWalletCore.so at $manifest_sha"
  done
done

# ---------------------------------------------------------------------------
# step 5 — sizes, and the app-size delta against a baseline app
# ---------------------------------------------------------------------------

say "step 5: sizes"
harness size --artifact "$XCF_ROOT/$XCF_DEVICE_BIN" --target ios/arm64
harness size --artifact "$XCF_ROOT/$XCF_SIM_BIN" --target ios-simulator/arm64_x86_64
say "step 5: baseline app (no SDK) for the app-size delta"
(cd "$OUT" && flutter create --no-pub --platforms=android,ios --org dev.wcf.eval \
    --project-name wcf_eval_baseline baseline) > "$LOGS/baseline-create.log" 2>&1
# The consumer has integration_test as a dev dependency, and dev-dependency
# plugins are built into debug apps; the baseline gets the same.
(cd "$BASELINE" && flutter pub add 'dev:integration_test:{"sdk":"flutter"}') \
  > "$LOGS/baseline-pub.log" 2>&1
if [ "$NO_XCODE" = 0 ]; then
  (cd "$BASELINE" && flutter build ios --simulator --debug) > "$LOGS/baseline-sim.log" 2>&1
  mkdir -p "$APPS/baseline-sim" "$APPS/baseline-device"
  ditto "$BASELINE/build/ios/iphonesimulator/Runner.app" "$APPS/baseline-sim/Runner.app"
  (cd "$BASELINE" && flutter build ipa --no-codesign) > "$LOGS/baseline-ipa.log" 2>&1
  ditto "$BASELINE/build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app" \
    "$APPS/baseline-device/Runner.app"
  harness size --baseline-app "$APPS/baseline-sim/Runner.app" \
    --sdk-app "$APPS/ios-simulator-arm64-debug/Runner.app" --target ios-simulator-arm64/debug
  harness size --baseline-app "$APPS/baseline-device/Runner.app" \
    --sdk-app "$APPS/ios-device-arm64-release/Runner.app" --target ios-device-arm64/release
else
  for t in ios-simulator-arm64/debug ios-device-arm64/release; do
    unmeasured app-size-delta "$t" "eval/option2/run_eval.sh (size.dart --baseline-app <flutter create app> --sdk-app <consumer app> --target $t)" "$ORCHESTRATOR"
  done
fi
for abi in arm64-v8a x86_64; do
  harness size --artifact "$AND_APPS/release/lib/$abi/libTrustWalletCore.so" --target "android/$abi"
done
row --check size --target android/armeabi-v7a --status skip --summary "$NOT_SHIPPED" \
  --command "$APK_SO_CMD && dart run tools/packaging_eval/bin/size.dart --artifact \"\$OUT/apps/android/release/lib/armeabi-v7a/libTrustWalletCore.so\" --target android/armeabi-v7a" \
  --notes "$NOT_SHIPPED_NOTE"
# The baseline's APKs: the same Flutter, commands, modes and ABIs. One APK
# carries both ABIs, so the delta lands in the arm64-v8a emulator column and
# the x86_64 column points at it.
for mode in debug release; do
  base_apk="$BASELINE/build/app/outputs/flutter-apk/app-$mode.apk"
  (cd "$BASELINE" && flutter build apk "--$mode" --target-platform "$ANDROID_PLATFORMS") \
    > "$LOGS/baseline-android-$mode.log" 2>&1
  mkdir -p "$APPS/baseline-android"
  cp "$base_apk" "$APPS/baseline-android/app-$mode.apk"
  delta_cmd="cd \"\$OUT/baseline\" && flutter build apk --$mode --target-platform $ANDROID_PLATFORMS && dart run tools/packaging_eval/bin/size.dart --baseline-app \"\$OUT/apps/baseline-android/app-$mode.apk\" --sdk-app \"\$OUT/apps/android/app-$mode.apk\" --target $AND_ARM/$mode"
  harness size --baseline-app "$APPS/baseline-android/app-$mode.apk" \
    --sdk-app "$AND_APPS/app-$mode.apk" --target "$AND_ARM/$mode"
  row --check app-size-delta --target "$AND_X64/$mode" --status skip \
    --summary "one APK for both ABIs (see $AND_ARM/$mode)" --command "$delta_cmd" \
    --notes "the APK measured in the $AND_ARM/$mode column carries the x86_64 library too; per-ABI library sizes are the size rows"
  row --check app-size-delta --target "$AND_DEV/$mode" --status unmeasured --summary 'no physical device' \
    --command "$delta_cmd" --notes "$NO_DEVICE"
done

# ---------------------------------------------------------------------------
# step 6 — minimum Flutter/Dart
# ---------------------------------------------------------------------------

say "step 6: toolchain and declared constraints"
harness min_version --target host/toolchain
FLOOR_NOTE="one SDK per run: this run used Flutter $FLUTTER_VERSION / Dart $DART_VERSION with $XCODE_VERSION (iOS deployment ${IOS_SDK_MIN}–$IOS_SDK_MAX). With this Xcode, a Flutter whose app template targets below iOS $IOS_SDK_MIN builds no iOS app at all, with or without this package (recorded in DECISION-2-option2.md §4). Documentation: the ffiPlugin platform key exists since Flutter 3.0 (plugin_ffi template); the package's declared floor is the Dart code's, not the packaging's."
FLOOR_CMD="for each candidate SDK, oldest first: <sdk>/bin/flutter build ios --simulator --debug (and apk --release --target-platform $ANDROID_PLATFORMS) in \"\$APP\"; record the oldest that builds"
for t in ios-simulator-arm64/debug ios-device-arm64/release; do
  unmeasured min-version-floor "$t" "$FLOOR_CMD" "$FLOOR_NOTE"
done
for t in "$AND_ARM/debug" "$AND_ARM/release" "$AND_X64/debug" "$AND_X64/release"; do
  row --check min-version-floor --target "$t" --status unmeasured \
    --summary "only Flutter $FLUTTER_VERSION tried" --command "$FLOOR_CMD" \
    --notes "one SDK per run: built on Flutter $FLUTTER_VERSION / Dart $DART_VERSION (consumer-build rows), the only Flutter installed. The Gradle task needs the app's AGP to provide variant.sources.jniLibs.addGeneratedSourceDirectory (AGP 8 Variant API; built here with the $FLUTTER_VERSION app template's AGP and Gradle); the package's declared floor is the Dart code's, not the packaging's."
done
for mode in debug release; do
  row --check min-version-floor --target "$AND_DEV/$mode" --status unmeasured \
    --summary 'no physical device' --command "$FLOOR_CMD" --notes "$NO_DEVICE"
done

# ---------------------------------------------------------------------------
# step 7 — offline install; a wrong checksum fails loudly
# ---------------------------------------------------------------------------

offline_target=ios-simulator-arm64/debug
# The measured builds' install: pass only when pub get needed no network and
# the first pod install filled the absent $CACHE from --vendored. Whether a
# socket was opened is observed separately below, not inferred from --offline.
offline_status=pass
offline_notes="pub get --offline succeeded; the first pod install started without an artifact cache and, with --offline, filled it from --vendored ($CACHE_FILLED of 2 libraries): no request to the retention URL (the draft release native-4.8.0-001, whose assets are not anonymously downloadable) was possible. No socket was observed here; see the outbound-network-denied pod install in this cell"
if [ "$PUB_MODE" != offline ]; then
  offline_status=unmeasured
  offline_notes="not an offline install: pub get --offline failed and pub get ran online ($LOGS/pub-get.log)"
elif [ "$CACHE_FILLED" != 2 ]; then
  offline_status=fail
  offline_notes="the artifact cache holds $CACHE_FILLED of 2 libraries after the first pod install"
fi
if [ "$NO_XCODE" = 1 ]; then
  offline_targets=("$offline_target")
  offline_how="flutter build ios --config-only (pod install only, --no-xcode)"
else
  offline_targets=(ios-simulator-arm64/debug ios-device-arm64/release)
  offline_how="flutter build …"
fi
for t in "${offline_targets[@]}"; do
  row --check offline-install --target "$t" --status "$offline_status" \
    --command "pub get --offline; WCF_OFFLINE=1 WCF_VENDORED_DIR=third_party/wcf-native-all/artifacts WCF_ARTIFACT_DIR=<absent> $offline_how" \
    --value "pub_get=$PUB_MODE" --value "artifact_cache_before=absent" \
    --value "artifact_cache_after=$CACHE_FILLED" \
    --summary "pub get $PUB_MODE; first pod install filled an absent artifact cache from --vendored ($CACHE_FILLED/2)" \
    --notes "$offline_notes"
done

say "step 7: a wrong digest in the manifest must fail pod install"
log="$LOGS/negative-pod-install.log"
if (cd "$APP/ios" && WCF_MANIFEST="$FLIPPED" pod install) > "$log" 2>&1; then
  row --check offline-install --target "$offline_target" --status fail \
    --command "cd \"\$APP/ios\" && WCF_MANIFEST=<flipped> pod install" --value "log=$log" \
    --notes "pod install SUCCEEDED with a flipped digest"
  finish 1
fi
if grep -q 'expected sha256' "$log" && grep -q 'verification FAILED' "$log"; then
  row --check offline-install --target "$offline_target" --status pass \
    --command "cd \"\$APP/ios\" && WCF_MANIFEST=<flipped: one sha256 + asset_name> pod install" --value "log=$log" \
    --summary "pod install fails loudly: digest mismatch, both digests printed" \
    --notes "$(grep -m1 'expected sha256' "$log" | tr -s ' ') / $(grep -m1 'found    sha256' "$log" | tr -s ' ')"
else
  row --check offline-install --target "$offline_target" --status fail \
    --command "cd \"\$APP/ios\" && WCF_MANIFEST=<flipped> pod install" --value "log=$log" \
    --notes "pod install failed, but not with the fetch tool's mismatch report: $(log_tail "$log")"
  finish 1
fi
# Since as_4.8.0_001 the package ships a filled manifest (main f9f3d58), so the
# placeholder case is the fixture copy of the manifest as it was before.
say "step 7: a placeholder manifest (all TBD-) must fail pod install"
log="$LOGS/negative-placeholder-manifest.log"
PLACEHOLDER_CMD="cd \"\$APP/ios\" && WCF_MANIFEST=packages/wallet_core_flutter_native/test/fixtures/compat_manifest.placeholder.json pod install"
if (cd "$APP/ios" && WCF_MANIFEST="$PLACEHOLDER" pod install) > "$log" 2>&1; then
  row --check offline-install --target "$offline_target" --status fail \
    --command "$PLACEHOLDER_CMD" --value "log=$log" --notes "pod install SUCCEEDED against a placeholder manifest"
  finish 1
fi
if grep -q 'cannot be fetched from' "$log"; then
  row --check offline-install --target "$offline_target" --status pass \
    --command "$PLACEHOLDER_CMD" --value "log=$log" \
    --summary "placeholder manifest: pod install fails, fetch tool exit 2, blockers named" \
    --notes "$(grep -m1 'blockers' "$log" | sed 's|.*/test/fixtures/|test/fixtures/|')"
else
  row --check offline-install --target "$offline_target" --status fail \
    --command "$PLACEHOLDER_CMD" --value "log=$log" \
    --notes "failed, but not with the manifest gate: $(log_tail "$log")"
  finish 1
fi

say "step 7: restore with the right manifest"
(cd "$APP/ios" && pod install) > "$LOGS/restore-pod-install.log" 2>&1

if [ "$NO_XCODE" = 0 ]; then
  say "step 7: a manifest changed after pod install must fail the Xcode build"
  log="$LOGS/negative-build.log"
  if (cd "$APP" && WCF_MANIFEST="$FLIPPED" flutter build ios --simulator --debug) > "$log" 2>&1; then
    row --check offline-install --target "$offline_target" --status fail \
      --command "WCF_MANIFEST=<flipped> flutter build ios --simulator --debug" --value "log=$log" \
      --notes "the build SUCCEEDED against a manifest it was not verified against"
    finish 1
  fi
  if grep -q 'is not the manifest TrustWalletCore.xcframework was verified against' "$log" \
      || grep -q 'verification FAILED' "$log"; then
    row --check offline-install --target "$offline_target" --status pass \
      --command "WCF_MANIFEST=<flipped> flutter build ios --simulator --debug" --value "log=$log" \
      --summary "build fails: the script phase (or a re-run pod install) reports the mismatch"
  else
    row --check offline-install --target "$offline_target" --status fail \
      --command "WCF_MANIFEST=<flipped> flutter build ios --simulator --debug" --value "log=$log" \
      --notes "the build failed, but not with the manifest check: $(log_tail "$log")"
    finish 1
  fi
  (cd "$APP/ios" && pod install) > "$LOGS/restore-pod-install-2.log" 2>&1
else
  unmeasured offline-install ios-device-arm64/release \
    "WCF_MANIFEST=<flipped> flutter build ios --simulator --debug (must fail in the [CP-User] Verify TrustWalletCore.xcframework script phase)" \
    "$ORCHESTRATOR"
fi

say "step 7: a clean pod install with outbound network denied"
# Observed, not inferred from --offline: macOS's sandbox-exec with a profile
# that refuses every outbound connection, applied to pod install only (the
# artifact step). The profile is probed first (tool/no_net_probe.sh): the same
# `nc -v` connect to a closed loopback port, once plainly and once under the
# profile, must say "Connection refused" and then "Operation not permitted".
# Any other pair — no sandbox-exec, a nested sandbox, a host that already
# denies loopback — leaves the row `unmeasured` with both outputs. Clean: no
# Frameworks/, no .wcf_work/, an absent cache.
no_net_control="$("${NO_NET_PROBE[@]}" 2>&1 || true)"
no_net_denied="sandbox-exec not found"
if command -v sandbox-exec > /dev/null 2>&1; then
  no_net_denied="$(sandbox-exec -p "$NO_NET_PROFILE" "${NO_NET_PROBE[@]}" 2>&1 || true)"
fi
no_net_control="$(printf '%s' "$no_net_control" | tr '\n' ' ' | cut -c1-200)"
no_net_denied="$(printf '%s' "$no_net_denied" | tr '\n' ' ' | cut -c1-200)"
log="$LOGS/offline-pod-install.log"
no_net_cmd="cd \"\$APP/ios\" && rm -rf <pod>/Frameworks <pod>/.wcf_work && WCF_ARTIFACT_DIR=<absent> sandbox-exec -p '$NO_NET_PROFILE' pod install"
no_net_applies=yes
no_net_verdict="$(no_net_classify "$no_net_control" "$no_net_denied")" || no_net_applies=no
case "$no_net_applies" in
  yes)
    rm -rf "$XCF_ROOT" "$STAGE/wallet_core_flutter_native/ios/.wcf_work" "$OFFLINE_CACHE"
    status=fail
    if (cd "$APP/ios" && WCF_ARTIFACT_DIR="$OFFLINE_CACHE" \
          sandbox-exec -p "$NO_NET_PROFILE" pod install) > "$log" 2>&1 \
        && (cd "$XCF_ROOT" && shasum -a 256 -c wcf_binaries.sha256) >> "$log" 2>&1 \
        && [ "$(cache_files "$OFFLINE_CACHE")" = 2 ]; then
      status=pass
    fi
    # The acquire pass's own count line, as the podspec printed it.
    acquired="$(grep -m1 ' requested: ' "$log" | tr -s ' ' || true)"
    notes="${acquired:-no fetch-tool count line in the pod install output}"
    [ "$status" = pass ] || notes="$notes; $(log_tail "$log")"
    row --check offline-install --target "$offline_target" --status "$status" \
      --command "$no_net_cmd" --value "log=$log" \
      --value "network_probe_control=$no_net_control" --value "network_probe_denied=$no_net_denied" \
      --value "artifact_cache_after=$(cache_files "$OFFLINE_CACHE")" \
      --summary "$([ "$status" = pass ] && echo "clean pod install with outbound network denied: verified and assembled" || echo "clean pod install with outbound network denied: FAILED")" \
      --notes "$notes"
    if [ "$status" != pass ]; then
      # Put back what the remaining steps measure.
      rm -rf "$XCF_ROOT"
      (cd "$APP/ios" && pod install) > "$LOGS/restore-pod-install-3.log" 2>&1
    fi
    ;;
  *)
    unmeasured offline-install "$offline_target" "$no_net_cmd" \
      "no socket not observed: $no_net_verdict"
    ;;
esac

# Android. The debug APK was the app's first Gradle build: its
# wcfPrepareDebugJniLibs task found no Android library in $CACHE (the pod
# installs fetch the iOS rows only) and, with --offline, filled it from
# --vendored. The release build that followed found the cache warm by
# construction, so it has no offline row of its own.
say "step 7: Android offline install, wrong digest, placeholder manifest"
AND_OFF_CMD="pub get --offline; cd \"\$APP\" && WCF_OFFLINE=1 WCF_VENDORED_DIR=third_party/wcf-native-all/artifacts WCF_ARTIFACT_DIR=<no Android library yet> flutter build apk --debug --target-platform $ANDROID_PLATFORMS -v"
AND_PREPARED="$(prepare_lines "$LOGS/build-android-debug.log" wcfPrepareDebugJniLibs)"
and_off_status=pass
and_off_notes="pub get --offline succeeded; before the app's first Gradle build the artifact cache held $AND_CACHE_BEFORE Android libraries and after it $AND_CACHE_AFTER; wcfPrepareDebugJniLibs: $AND_PREPARED. With --offline no request to the retention URL (the draft release, not anonymously downloadable) was possible. No socket was observed here; see the network-denied prepare step in this cell"
if [ "$PUB_MODE" != offline ]; then
  and_off_status=unmeasured
  and_off_notes="not an offline install: pub get --offline failed and pub get ran online ($LOGS/pub-get.log)"
elif [ "$AND_CACHE_BEFORE" != 0 ]; then
  and_off_status=unmeasured
  and_off_notes="the artifact cache already held $AND_CACHE_BEFORE Android libraries before the first Gradle build (warm), so this build is not a clean install; wcfPrepareDebugJniLibs: $AND_PREPARED"
elif [ "$AND_CACHE_AFTER" != 2 ] || ! printf '%s' "$AND_PREPARED" | grep -q '2 from --vendored'; then
  and_off_status=fail
  and_off_notes="after the first Gradle build the cache holds $AND_CACHE_AFTER of 2 Android libraries; wcfPrepareDebugJniLibs: ${AND_PREPARED:-no output}"
fi
for t in "$AND_ARM/debug" "$AND_X64/debug"; do
  row --check offline-install --target "$t" --status "$and_off_status" --command "$AND_OFF_CMD" \
    --value "pub_get=$PUB_MODE" --value "android_cache_before=$AND_CACHE_BEFORE" \
    --value "android_cache_after=$AND_CACHE_AFTER" --value "prepare=$AND_PREPARED" \
    --summary "first Gradle build filled the cache from --vendored ($AND_CACHE_BEFORE -> $AND_CACHE_AFTER/2 Android libraries)" \
    --notes "$and_off_notes"
done
[ "$and_off_status" != fail ] || finish 1

# The artifact step with outbound network denied: the exact command the
# Gradle task runs (tool/option2/prepare_jni_libs.dart through the Flutter
# SDK's dart and the app's package configuration), from a clean state, under
# the same sandbox-exec profile and probe as the iOS pod install above.
# Gradle itself is not run under the profile: the Gradle client talks to its
# daemon over a loopback socket, which the profile denies too, and a daemon
# started outside the sandbox would run the task outside it anyway.
log="$LOGS/offline-prepare-jni-libs.log"
AND_OFFLINE_CACHE="$OUT/offline-cache-android"
AND_OFFLINE_OUT="$OUT/offline-jnilibs"
FLUTTER_DART="$FLUTTER_ROOT_DIR/bin/dart"
and_no_net_cmd="sandbox-exec -p '$NO_NET_PROFILE' <flutter>/bin/dart --packages=\"\$APP/.dart_tool/package_config.json\" <package>/tool/option2/prepare_jni_libs.dart --manifest eval/option2/eval_manifest.json --out <absent> --work <absent> --vendored third_party/wcf-native-all/artifacts --cache-dir <absent> --offline"
case "$no_net_applies" in
  yes)
    rm -rf "$AND_OFFLINE_CACHE" "$AND_OFFLINE_OUT" "$OUT/offline-jni-work"
    status=fail
    if sandbox-exec -p "$NO_NET_PROFILE" "$FLUTTER_DART" \
          "--packages=$APP/.dart_tool/package_config.json" \
          "$STAGE/wallet_core_flutter_native/tool/option2/prepare_jni_libs.dart" \
          --manifest "$MANIFEST" --out "$AND_OFFLINE_OUT" --work "$OUT/offline-jni-work" \
          --vendored "$VENDORED" --cache-dir "$AND_OFFLINE_CACHE" --offline > "$log" 2>&1 \
        && [ "$(so_cache_files "$AND_OFFLINE_CACHE")" = 2 ] \
        && [ "$(so_cache_files "$AND_OFFLINE_OUT")" = 2 ]; then
      status=pass
    fi
    acquired="$(grep -m1 ' requested: ' "$log" | tr -s ' ' || true)"
    notes="${acquired:-no fetch-tool count line in the output}; jniLibs: $(cd "$AND_OFFLINE_OUT" 2>/dev/null && find . -name '*.so' | sed 's|^\./||' | sort | tr '\n' ' ')"
    [ "$status" = pass ] || notes="$notes; $(log_tail "$log")"
    row --check offline-install --target "$AND_ARM/debug" --status "$status" \
      --command "$and_no_net_cmd" --value "log=$log" \
      --value "network_probe_control=$no_net_control" --value "network_probe_denied=$no_net_denied" \
      --value "artifact_cache_after=$(so_cache_files "$AND_OFFLINE_CACHE")" \
      --summary "$([ "$status" = pass ] && echo "clean prepare step with outbound network denied: verified, 2 libraries laid out" || echo "clean prepare step with outbound network denied: FAILED")" \
      --notes "$notes"
    [ "$status" = pass ] || finish 1
    ;;
  *)
    unmeasured offline-install "$AND_ARM/debug" "$and_no_net_cmd" "no socket not observed: $no_net_verdict"
    ;;
esac

# A flipped digest must fail the Gradle build in wcfPrepareDebugJniLibs with
# the fetch tool's report (both digests); so must the placeholder manifest,
# with the manifest gate's blockers. Gradle reruns the task because the
# manifest is one of its inputs.
negative_gradle() { # label manifest manifest-shown -> NEG_LOG, NEG_RC
  NEG_LOG="$LOGS/negative-gradle-$1.log"
  NEG_RC=0
  (cd "$APP" && WCF_MANIFEST="$2" flutter build apk --debug --target-platform "$ANDROID_PLATFORMS" \
    "${IDENTITY_DEFINES[@]}") > "$NEG_LOG" 2>&1 || NEG_RC=$?
}
negative_gradle flipped "$FLIPPED_ANDROID"
NEG_CMD="cd \"\$APP\" && WCF_MANIFEST=<eval manifest with android/arm64-v8a's sha256 + asset_name flipped> flutter build apk --debug --target-platform $ANDROID_PLATFORMS"
if [ "$NEG_RC" = 0 ]; then
  row --check offline-install --target "$AND_ARM/debug" --status fail --command "$NEG_CMD" \
    --value "log=$NEG_LOG" --notes "the Gradle build SUCCEEDED with a flipped digest"
  finish 1
fi
if grep -q 'native artifact verification FAILED' "$NEG_LOG" && grep -q 'expected sha256' "$NEG_LOG" \
    && grep -q 'wcfPrepareDebugJniLibs' "$NEG_LOG"; then
  row --check offline-install --target "$AND_ARM/debug" --status pass --command "$NEG_CMD" \
    --value "log=$NEG_LOG" \
    --summary "Gradle build fails in wcfPrepareDebugJniLibs: digest mismatch, both digests printed" \
    --notes "$(grep -m1 "Execution failed for task" "$NEG_LOG" | tr -s ' ') / $(grep -m1 'native artifact verification FAILED' "$NEG_LOG" | tr -s ' ') / $(grep -m1 'expected sha256' "$NEG_LOG" | tr -s ' ') / $(grep -m1 'found    sha256' "$NEG_LOG" | tr -s ' ')"
else
  row --check offline-install --target "$AND_ARM/debug" --status fail --command "$NEG_CMD" \
    --value "log=$NEG_LOG" --notes "the build failed, but not with the fetch tool's mismatch report in wcfPrepareDebugJniLibs: $(log_tail "$NEG_LOG")"
  finish 1
fi
negative_gradle placeholder "$PLACEHOLDER"
NEG_CMD="cd \"\$APP\" && WCF_MANIFEST=packages/wallet_core_flutter_native/test/fixtures/compat_manifest.placeholder.json flutter build apk --debug --target-platform $ANDROID_PLATFORMS"
if [ "$NEG_RC" = 0 ]; then
  row --check offline-install --target "$AND_ARM/debug" --status fail --command "$NEG_CMD" \
    --value "log=$NEG_LOG" --notes "the Gradle build SUCCEEDED against a placeholder manifest"
  finish 1
fi
if grep -q 'cannot be fetched from' "$NEG_LOG" && grep -q 'exit 2' "$NEG_LOG"; then
  row --check offline-install --target "$AND_ARM/debug" --status pass --command "$NEG_CMD" \
    --value "log=$NEG_LOG" \
    --summary "placeholder manifest: Gradle build fails, fetch tool exit 2, blockers named" \
    --notes "$(grep -m1 'native artifact verification FAILED' "$NEG_LOG" | tr -s ' ') / $(grep -m1 'blockers' "$NEG_LOG" | sed 's|.*/test/fixtures/|test/fixtures/|' | tr -s ' ')"
else
  row --check offline-install --target "$AND_ARM/debug" --status fail --command "$NEG_CMD" \
    --value "log=$NEG_LOG" --notes "failed, but not with the manifest gate: $(log_tail "$NEG_LOG")"
  finish 1
fi
for t in "$AND_ARM/release" "$AND_X64/release"; do
  row --check offline-install --target "$t" --status skip --summary 'warm cache by construction' \
    --command "cd \"\$APP\" && flutter build apk --release --target-platform $ANDROID_PLATFORMS -v" \
    --notes "the clean offline install is the app's first Gradle build, the debug APK (${t%/release}/debug); the release APK follows it with the same cache: wcfPrepareReleaseJniLibs: $(prepare_lines "$LOGS/build-android-release.log" wcfPrepareReleaseJniLibs)"
done
for mode in debug release; do
  row --check offline-install --target "$AND_DEV/$mode" --status unmeasured --summary 'no physical device' \
    --command "$AND_OFF_CMD" --notes "$NO_DEVICE"
done

# ---------------------------------------------------------------------------
# step 8 — 16 KB alignment (Android only)
# ---------------------------------------------------------------------------

say "step 8: 16 KB alignment"
# The libraries as packaged (step 4's copies out of the release APK), and the
# zip alignment of every .so entry in both APKs, as copied right after their
# builds.
for abi in arm64-v8a x86_64; do
  harness alignment --binary "$AND_APPS/release/lib/$abi/libTrustWalletCore.so" --target "android/$abi"
done
row --check alignment --target android/armeabi-v7a --status skip --summary "$NOT_SHIPPED" \
  --command "$APK_SO_CMD && dart run tools/packaging_eval/bin/alignment.dart --binary \"\$OUT/apps/android/release/lib/armeabi-v7a/libTrustWalletCore.so\" --target android/armeabi-v7a" \
  --notes "$NOT_SHIPPED_NOTE (16 KB pages concern the 64-bit ABIs)"
for mode in debug release; do
  for t in "$AND_ARM/$mode" "$AND_X64/$mode"; do
    harness alignment --apk "$AND_APPS/app-$mode.apk" --target "$t"
  done
  row --check alignment-apk --target "$AND_DEV/$mode" --status unmeasured --summary 'no physical device' \
    --command "dart run tools/packaging_eval/bin/alignment.dart --apk \"\$OUT/apps/android/app-$mode.apk\" --target $AND_DEV/$mode" \
    --notes "$NO_DEVICE"
done

# ---------------------------------------------------------------------------
# step 9 — a second plugin bundling libc++_shared.so (Android only)
# ---------------------------------------------------------------------------

say "step 9: a second plugin bundling libc++_shared.so"
# What our library needs: the DT_NEEDED entries of the packaged .so (§5.1).
DT_ARM="$(dt_needed "$AND_APPS/release/lib/arm64-v8a/libTrustWalletCore.so")"
DT_X64="$(dt_needed "$AND_APPS/release/lib/x86_64/libTrustWalletCore.so")"
# The second plugin: the harness fixture, copied out of the checkout, given
# the libc++_shared.so of the NDK the Flutter build uses, and added by path to
# a working copy of the consumer. tools/packaging_eval's libcxx_conflict.dart
# classifies a Gradle log, and a build in which only one contributor bundles
# the file names it nowhere (nothing to classify), while AGP 9's duplicate
# error reads "2 files found with path", not the "More than one file was
# found with OS independent path" it matches; so the rows are this
# evaluation's, read from the APK (copies, GNU build IDs) and the build log.
PLUGIN="$OUT/libcxx_plugin"
LX="$OUT/libcxx"
NDK_NAME="$(basename "$NDK")"
rm -rf "$PLUGIN"
mkdir -p "$PLUGIN"
(cd tools/packaging_eval/fixtures/libcxx_plugin && tar cf - --exclude '*.so' .) | (cd "$PLUGIN" && tar xf -)
bash tools/packaging_eval/fixtures/libcxx_plugin/tool/materialize_libcxx.sh --ndk "$NDK" \
  --dest "$PLUGIN/android/src/main/jniLibs" --abis 'arm64-v8a x86_64' > "$LOGS/libcxx-materialize.log" 2>&1
stage_app "$LX"
(cd "$LX" && { flutter pub add --offline "libcxx_plugin:{\"path\":\"$PLUGIN\"}" \
  || flutter pub add "libcxx_plugin:{\"path\":\"$PLUGIN\"}"; }) > "$LOGS/libcxx-pub-add.log" 2>&1
LX_STAGE="(working copy of eval/option2/consumer at \$OUT/libcxx) && (tools/packaging_eval/fixtures/libcxx_plugin copied to \$OUT/libcxx_plugin without .so) && tools/packaging_eval/fixtures/libcxx_plugin/tool/materialize_libcxx.sh --ndk <NDK $NDK_NAME> --dest \$OUT/libcxx_plugin/android/src/main/jniLibs --abis 'arm64-v8a x86_64' && flutter pub add 'libcxx_plugin:{\"path\":\"\$OUT/libcxx_plugin\"}'"

libcxx_mode() { # debug|release
  local mode="$1" log="$LOGS/libcxx-$1.log" entry=() rc=0
  [ "$mode" != release ] || entry=(-t lib/probe_main.dart)
  local cmd="$LX_STAGE && flutter build apk --$mode --target-platform $ANDROID_PLATFORMS ${entry[*]:-} ${IDENTITY_DEFINES[*]} && unzip -l build/app/outputs/flutter-apk/app-$mode.apk && llvm-readelf -n lib/<abi>/libc++_shared.so"
  (cd "$LX" && flutter build apk "--$mode" --target-platform "$ANDROID_PLATFORMS" ${entry[@]+"${entry[@]}"} \
    "${IDENTITY_DEFINES[@]}") > "$log" 2>&1 || rc=$?
  if [ "$rc" != 0 ]; then
    local summary='build failed' notes
    notes="$(grep -m1 'files found with path' "$log" | sed 's/^ *//' || true)"
    [ -z "$notes" ] || summary='duplicate-file failure'
    for t in "$AND_ARM/$mode" "$AND_X64/$mode"; do
      row --check libcxx-conflict --target "$t" --status fail --summary "$summary" \
        --command "$cmd" --value "log=$log" --notes "${notes:-$(log_tail "$log")}"
    done
    return 0
  fi
  local apk="$AND_APPS/libcxx-$mode.apk" dir="$AND_APPS/libcxx-$mode"
  cp "$LX/build/app/outputs/flutter-apk/app-$mode.apk" "$apk"
  rm -rf "$dir"
  mkdir -p "$dir"
  unzip -o -q "$apk" 'lib/*' -d "$dir"
  local abi t dt copies packaged_id plugin_id kept notes summary
  for abi in arm64-v8a x86_64; do
    if [ "$abi" = arm64-v8a ]; then t="$AND_ARM/$mode"; dt="$DT_ARM"; else t="$AND_X64/$mode"; dt="$DT_X64"; fi
    copies="$(unzip -l "$apk" | awk -v p="lib/$abi/libc++_shared.so" '$4 == p' | wc -l | tr -d ' ')"
    packaged_id=''
    [ ! -f "$dir/lib/$abi/libc++_shared.so" ] || packaged_id="$(build_id "$dir/lib/$abi/libc++_shared.so")"
    plugin_id="$(build_id "$PLUGIN/android/src/main/jniLibs/$abi/libc++_shared.so")"
    if [ -n "$packaged_id" ] && [ "$packaged_id" = "$plugin_id" ]; then
      kept="the fixture plugin's copy (NDK $NDK_NAME)"
    else
      kept="unidentified (build ID ${packaged_id:-none})"
    fi
    notes="APK lib/$abi/libc++_shared.so: $copies entr$([ "$copies" = 1 ] && echo y || echo ies), build ID ${packaged_id:-none} = $kept. Our libTrustWalletCore.so DT_NEEDED: $dt — no libc++_shared.so (a c++_static build), and the manifest lists no android/$abi/libc++_shared.so row, so the Gradle task packages none: the fixture's copy is the only contributor and Gradle says nothing about the file. log: $log"
    if [ "$copies" != 1 ] || [ "$packaged_id" != "$plugin_id" ]; then
      row --check libcxx-conflict --target "$t" --status fail --summary "$copies copies; $kept" \
        --command "$cmd" --notes "$notes"
      continue
    fi
    case "$dt" in *libc++_shared.so*)
      row --check libcxx-conflict --target "$t" --status fail --summary 'our library needs libc++_shared.so' \
        --command "$cmd" --notes "$notes"
      continue ;;
    esac
    summary="one copy, the fixture's; ours needs none (c++_static)"
    if [ "$abi" = x86_64 ]; then
      row --check libcxx-conflict --target "$t" --status pass --summary "$summary" \
        --command "$cmd" --notes "$notes. Not run: $NO_X64"
    elif [ "$mode" = debug ]; then
      row --check libcxx-conflict --target "$t" --status pass --summary "$summary" \
        --command "$cmd" --notes "$notes. Run on the emulator in the release column"
    elif [ "$EMU_OK" != 1 ]; then
      row --check libcxx-conflict --target "$t" --status unmeasured --summary "$summary; not run" \
        --command "$cmd" --notes "$notes. No arm64-v8a emulator running: $EMU_NOTE"
    else
      android_probe "$apk" "$LOGS/run-libcxx-release.log"
      cmd="$cmd && adb -s $EMU_ID install -r … && adb -s $EMU_ID shell am start -W -n $AND_PACKAGE/.MainActivity && adb -s $EMU_ID logcat -d -s flutter:I"
      case "$PROBE_LINE" in
        'WCF_PROBE PASS'*)
          row --check libcxx-conflict --target "$t" --status pass --summary "$summary; probe PASS" \
            --command "$cmd" --notes "$notes. Run with both plugins: $PROBE_LINE; am start -W: $LAUNCH"
          ;;
        *)
          row --check libcxx-conflict --target "$t" --status fail --summary "$summary; probe failed" \
            --command "$cmd" --notes "$notes. Run with both plugins: ${PROBE_LINE:-no WCF_PROBE line within 60 s}; am start -W: ${LAUNCH:-none}; log: $LOGS/run-libcxx-release.log"
          ;;
      esac
    fi
  done
}
libcxx_mode debug
libcxx_mode release
for mode in debug release; do
  row --check libcxx-conflict --target "$AND_DEV/$mode" --status unmeasured --summary 'no physical device' \
    --command "$LX_STAGE && flutter build apk --$mode --target-platform $ANDROID_PLATFORMS" --notes "$NO_DEVICE"
done

# The counterfactual §5.2 is about: the set built against c++_shared, so the
# manifest lists android/<abi>/libc++_shared.so beside each library and the
# Gradle task packages it. The rows are the set's own NDK's file
# (toolchain.ndk), added to a copy of the evaluation manifest under $OUT and
# vendored there; never committed. Measured in the same working copy, after
# the rows above: first as `flutter create` left it, then with the
# resolution only the consumer can write (pickFirsts in the app's
# build.gradle.kts).
CXX_CHECK=libcxx-if-cxx-shared
CXX_MANIFEST="$OUT/eval_manifest.cxx-shared.json"
CXX_VENDORED="$OUT/vendored-cxx-shared"
CXX_CMD="eval.dart add-artifact (android/<abi>/libc++_shared.so from NDK $SET_NDK_VERSION, the set's toolchain.ndk) && $LX_STAGE && WCF_MANIFEST=<that manifest> WCF_VENDORED_DIR=<vendored + those files> flutter build apk --debug --target-platform $ANDROID_PLATFORMS"
SET_LIBCXX_ARM="$SET_NDK/toolchains/llvm/prebuilt/darwin-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"
SET_LIBCXX_X64="$SET_NDK/toolchains/llvm/prebuilt/darwin-x86_64/sysroot/usr/lib/x86_64-linux-android/libc++_shared.so"
if [ -f "$SET_LIBCXX_ARM" ] && [ -f "$SET_LIBCXX_X64" ]; then
  rm -rf "$CXX_VENDORED"
  mkdir -p "$CXX_VENDORED"
  cp -R "$VENDORED/android" "$CXX_VENDORED/android"
  cp "$SET_LIBCXX_ARM" "$CXX_VENDORED/android/arm64-v8a/libc++_shared.so"
  cp "$SET_LIBCXX_X64" "$CXX_VENDORED/android/x86_64/libc++_shared.so"
  dart "$EVAL/tool/eval.dart" add-artifact --manifest "$MANIFEST" --name android/arm64-v8a/libc++_shared.so \
    --like "$AND_ARM_ROW" --file "$CXX_VENDORED/android/arm64-v8a/libc++_shared.so" --out "$CXX_MANIFEST.tmp"
  dart "$EVAL/tool/eval.dart" add-artifact --manifest "$CXX_MANIFEST.tmp" --name android/x86_64/libc++_shared.so \
    --like "$AND_X64_ROW" --file "$CXX_VENDORED/android/x86_64/libc++_shared.so" --out "$CXX_MANIFEST"
  rm -f "$CXX_MANIFEST.tmp"
  dart run tools/manifest/bin/validate.dart "$CXX_MANIFEST"
  ours_id="$(build_id "$CXX_VENDORED/android/arm64-v8a/libc++_shared.so")"
  plugin_id="$(build_id "$PLUGIN/android/src/main/jniLibs/arm64-v8a/libc++_shared.so")"
  ids="ours (NDK $SET_NDK_VERSION) build ID $ours_id; the fixture's (NDK $NDK_NAME) $plugin_id"
  cxx_build() { # log
    local rc=0
    (cd "$LX" && WCF_MANIFEST="$CXX_MANIFEST" WCF_VENDORED_DIR="$CXX_VENDORED" WCF_ARTIFACT_DIR="$OUT/cache-cxx-shared" \
      flutter build apk --debug --target-platform "$ANDROID_PLATFORMS" "${IDENTITY_DEFINES[@]}") > "$1" 2>&1 || rc=$?
    return $rc
  }
  log="$LOGS/libcxx-cxx-shared-row.log"
  if cxx_build "$log"; then
    copies="$(unzip -l "$LX/build/app/outputs/flutter-apk/app-debug.apk" | awk '$4 == "lib/arm64-v8a/libc++_shared.so"' | wc -l | tr -d ' ')"
    row --check "$CXX_CHECK" --target "$AND_ARM/debug" --status pass --command "$CXX_CMD" \
      --summary "counterfactual c++_shared row: builds ($copies copy in lib/arm64-v8a)" --notes "$ids; log: $log"
  elif grep -q "files found with path 'lib/[^']*/libc++_shared.so'" "$log"; then
    row --check "$CXX_CHECK" --target "$AND_ARM/debug" --status fail --command "$CXX_CMD" \
      --value "log=$log" \
      --summary "counterfactual c++_shared row: the app build fails, duplicate lib/<abi>/libc++_shared.so" \
      --notes "$(grep -m1 'Execution failed for task' "$log" | tr -s ' ') / $(grep -m1 'files found with path' "$log" | sed 's/^ *//') / $(grep -A2 'files found with path' "$log" | tail -2 | sed 's|.*/build/\([^/]*\)/.*|\1|' | tr '\n' ' ')contribute it. $ids"
  else
    row --check "$CXX_CHECK" --target "$AND_ARM/debug" --status unmeasured --command "$CXX_CMD" \
      --value "log=$log" --summary 'counterfactual build failed for another reason' --notes "$(log_tail "$log")"
  fi
  # The consumer's resolution (a manual native edit, which step 1 forbids).
  printf '\nandroid { packaging { jniLibs { pickFirsts += "**/libc++_shared.so" } } }\n' \
    >> "$LX/android/app/build.gradle.kts"
  log="$LOGS/libcxx-cxx-shared-row-pickfirst.log"
  if cxx_build "$log"; then
    pk="$OUT/libcxx-pickfirst"
    rm -rf "$pk"
    mkdir -p "$pk"
    unzip -o -q "$LX/build/app/outputs/flutter-apk/app-debug.apk" 'lib/*' -d "$pk"
    kept_id="$(build_id "$pk/lib/arm64-v8a/libc++_shared.so")"
    if [ "$kept_id" = "$ours_id" ]; then kept="ours (NDK $SET_NDK_VERSION)"
    elif [ "$kept_id" = "$plugin_id" ]; then kept="the fixture's (NDK $NDK_NAME)"
    else kept="unidentified ($kept_id)"; fi
    row --check "$CXX_CHECK" --target "$AND_ARM/debug" --status pass \
      --command "$CXX_CMD, with android { packaging { jniLibs { pickFirsts += \"**/libc++_shared.so\" } } } appended to android/app/build.gradle.kts" \
      --value "log=$log" \
      --summary "counterfactual + consumer pickFirsts edit: builds; keeps $kept" \
      --notes "lib/arm64-v8a/libc++_shared.so in the APK: build ID $kept_id = $kept; $ids. pickFirst takes the first contributor in merge order, not the newer NDK"
  else
    row --check "$CXX_CHECK" --target "$AND_ARM/debug" --status fail \
      --command "$CXX_CMD, with pickFirsts in android/app/build.gradle.kts" --value "log=$log" \
      --summary 'counterfactual + consumer pickFirsts edit: still fails' --notes "$(log_tail "$log")"
  fi
else
  unmeasured "$CXX_CHECK" "$AND_ARM/debug" "$CXX_CMD" \
    "the set's NDK $SET_NDK_VERSION (manifest toolchain.ndk) is not installed under $NDK_ROOT"
fi

# ---------------------------------------------------------------------------
# step 10 — iOS deployment target, visibility, signing, privacy, archive link
# ---------------------------------------------------------------------------

say "step 10: iOS archive checks"
harness ios_archive --binary "$XCF_ROOT/$XCF_DEVICE_BIN" --target ios/arm64
harness ios_archive --binary "$XCF_ROOT/$XCF_SIM_BIN" --target ios-simulator/arm64_x86_64
if [ "$NO_XCODE" = 0 ]; then
  for slug in ios-simulator-arm64-debug ios-device-arm64-release; do
    scan=()
    for fw in "$APPS/$slug/Runner.app/Frameworks/"*.framework; do
      scan+=(--duplicate-scan "$fw/$(basename "$fw" .framework)")
    done
    if [ "$slug" = ios-simulator-arm64-debug ]; then dup_target=ios-simulator/arm64_x86_64; else dup_target=ios/arm64; fi
    harness ios_archive "${scan[@]}" --target "$dup_target"
    harness ios_archive --binary "$APPS/$slug/Runner.app/$EMBEDDED_BIN" --target "$(target_of "$slug")"
  done
  archive="$APP/build/ios/archive/Runner.xcarchive"
  bundle="$archive/Products/Applications/Runner.app"
  fw_privacy=absent
  pod_privacy=absent
  [ -f "$bundle/Frameworks/TrustWalletCore.framework/PrivacyInfo.xcprivacy" ] && fw_privacy=present
  if find "$bundle" -path '*wallet_core_flutter_native_privacy.bundle/PrivacyInfo.xcprivacy' | grep -q .; then
    pod_privacy=present
  fi
  status=pass
  { [ -d "$archive" ] && [ -f "$bundle/$EMBEDDED_BIN" ]; } || status=fail
  row --check ios-archive-link --target ios-device-arm64/release --status "$status" \
    --command "cd \"\$APP\" && flutter build ipa --no-codesign (xcodebuild archive, Release, generic/platform=iOS)" \
    --value "archive=$archive" --value "framework_privacy_manifest=$fw_privacy" \
    --value "pod_privacy_bundle=$pod_privacy" \
    --summary "archive links; PrivacyInfo: framework $fw_privacy, pod bundle $pod_privacy" \
    --notes "unsigned (--no-codesign); signing the archive needs an identity (step 3, T1.9b)"
else
  for t in ios/arm64 ios-simulator/arm64_x86_64; do
    unmeasured ios-duplicate-symbols "$t" \
      "dart run tools/packaging_eval/bin/ios_archive.dart --duplicate-scan <Runner.app>/Frameworks/<each>.framework/<each> … --target $t" \
      "$ORCHESTRATOR"
  done
  unmeasured ios-archive-link ios-device-arm64/release \
    "cd \"\$APP\" && flutter build ipa --no-codesign" "$ORCHESTRATOR"
fi

# ---------------------------------------------------------------------------
# step 11 — consumed as hosted packages, never by path
# ---------------------------------------------------------------------------

if [ "$SKIP_CONSUMER_GEN" = 0 ]; then
  say "step 11: hosted consumption through a loopback package repository"
  harness consumer_gen --out-dir "$OUT/consumer-gen"
else
  unmeasured consumer-gen consumer/pub \
    "dart run tools/packaging_eval/bin/consumer_gen.dart --out-dir \"\$OUT/consumer-gen\"" \
    "skipped: --skip-consumer-gen"
fi

say "report"
finish 0
