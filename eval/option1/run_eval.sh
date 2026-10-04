#!/bin/sh
# DECISION-2 Option 1 (build hooks): PRD §12.2 steps 1–11, in order, for every
# target that has an input on the machine running it. EVALUATION ONLY.
#
# Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
# Not affiliated with or endorsed by Trust Wallet.
#
#   eval/option1/run_eval.sh            # from anywhere; resolves the repo root
#
# Writes eval/option1/results/results.jsonl (rewritten from empty on every run),
# eval/option1/results/table.md (rendered by tools/packaging_eval's
# report.dart), and re-embeds that table and the row counts into
# docs/decisions/DECISION-2-option1.md (§2.1, between its generated-block
# markers; nothing else in that document is touched).
#
# Every app is built in a fresh copy of eval/option1/consumer staged under
# $TMPDIR/o1 (deleted at the start of each run) by `eval_tool.dart stage`, which
# leaves out build/, .dart_tool/ and every CocoaPods/SwiftPM directory. So no
# build starts from an earlier run's outputs or caches, every measured binary
# is this run's, and the checked-in consumer stays as `flutter create` wrote it
# (the script refuses to start if it is not, and checks again at the end).
# Nothing runs inside eval/option1/consumer: it is only read (by `stage` and
# for its deployment targets). Any flutter command there — even
# `flutter test` — runs `flutter pub get`, whose plugin injection copies
# Flutter's Podfile template into ios/ and adds `#include? "Pods/…"` to the
# xcconfigs whenever the app has an iOS plugin (integration_test) and Swift
# Package Manager is off (T1.8a delta 5). The short-path host test needs
# /tmp/wcf-o1-<pid> (created and removed by this script, see step 1) because
# $TMPDIR is too deep on macOS.
# Flutter, Xcode and pub keep their own caches (pub cache, DerivedData) as for
# any Flutter build.
#
# Every measurement is a tools/packaging_eval command; tool/eval_tool.dart only
# writes the rows the harness leaves to the evaluations (a build, a run, the
# offline/wrong-digest checks) in the harness's schema, and decides the two
# verdicts that need the hook's own output (classify-negative,
# offline-evidence; tested in
# packages/wallet_core_flutter_native/test/eval_option1/eval_tool_test.dart).
#
# A row is `unmeasured` when its input does not exist here — no booted
# simulator or emulator, no physical device, a build that did not succeed in
# this run —
# or when the machine refuses the build (a sandbox denying Xcode,
# CoreSimulator or the network); the row then carries the exact command. A
# *required* target that fails for any other reason — iOS simulator debug, the
# iOS device release archive, the host `flutter test` rows — is recorded as
# `fail`, the table is rendered, and the script stops there. The macOS desktop
# app is not a PRD §12.2 target: its failure is recorded (`skip` for the known
# template/Xcode mismatch, `fail` otherwise) and the run continues.
set -eu

REPO=$(cd "$(dirname "$0")/../.." && pwd)
EVAL="$REPO/eval/option1"
APP="$EVAL/consumer"
MANIFEST="$EVAL/eval_manifest.json"
RESULTS="$EVAL/results/results.jsonl"
TABLE="$EVAL/results/table.md"
DOC="$REPO/docs/decisions/DECISION-2-option1.md"
SET="$REPO/third_party/wcf-native-all"
VENDORED="$SET/artifacts"
TMP="${TMPDIR:-/tmp}"
TMP="${TMP%/}"
# Short on purpose: Flutter's host `flutter test` rewrites the bundled dylib's
# install name to its absolute path, and the path has to fit the dylib's
# Mach-O header padding (step 1, host rows).
WORK="$TMP/o1"
LOGS="$WORK/logs"
# The staged consumer every app build runs in (see the header).
BUILD="$WORK/app"
TITLE='DECISION-2 Option 1 (build hooks) — PRD §12.2 measurement table'
# The manifest artifacts the hook picks for each target (hook/src/targets.dart).
SIM_NAME='ios-simulator/arm64_x86_64/libTrustWalletCore.dylib'
DEV_NAME='ios/arm64/libTrustWalletCore.dylib'
MAC_NAME='macos/arm64_x86_64/libTrustWalletCore.dylib'

cd "$REPO"

tool() { dart run "$EVAL/tool/eval_tool.dart" "$@"; }
# Rows this script writes name paths repo-relative, $TMPDIR-relative or
# ~-relative; `finish` applies the same rewrite to the harness's rows.
row() { tool row --out "$RESULTS" --repo "$REPO" --tmp "$TMP" --home "$HOME" "$@"; }
harness() {
  name=$1
  shift
  dart run "tools/packaging_eval/bin/$name.dart" "$@" --out "$RESULTS"
}
render() {
  tool relativize "$RESULTS" --repo "$REPO" --tmp "$TMP" --home "$HOME"
  # `--out=` and `--title=`, not `--out FILE`: report.dart counts every
  # argument that does not start with `-` as a results path, the value of a
  # spaced `--out` included (harness issue, reported; not patched here).
  dart run tools/packaging_eval/bin/report.dart "$RESULTS" --out="$TABLE" \
    --title="$TITLE" >/dev/null
  tool embed-table "$TABLE" "$RESULTS" "$DOC"
}
abort() {
  echo "run_eval: $1" >&2
  render
  echo "run_eval: table so far -> $TABLE (and $DOC §2.1)" >&2
  exit 1
}
say() { echo "== $*"; }

# The machine refused, as opposed to the build failing: a sandbox denying
# Xcode's DerivedData or SwiftPM, CoreSimulator, or the network.
refused() {
  grep -Eq "permissionDenied|You don.t have permission to save|CoreSimulatorService connection|not connected to CoreSimulatorService|Could not resolve package dependencies|Operation not permitted.*(DerivedData|xcodebuild)|Failed to connect to|Could not resolve host" "$1"
}

# attempt LOG DIR CMD...: 0 built, 10 refused by the machine, 1 failed.
# A failure the hook reported is always a failure, whatever else the log says.
attempt() {
  log=$1
  dir=$2
  shift 2
  say "$* (in $dir)"
  if (cd "$dir" && "$@") >"$log" 2>&1; then return 0; fi
  if grep -q "Building assets for package:wallet_core_flutter_native failed\|^wallet_core_flutter_native: " "$log"; then
    return 1
  fi
  if refused "$log"; then return 10; fi
  return 1
}

# ---------------------------------------------------------------------------
# 0. Inputs. third_party/ is untrusted: nothing under it is used before it
#    verifies against the committed eval manifest.
# ---------------------------------------------------------------------------
for t in flutter dart shasum; do
  command -v "$t" >/dev/null || { echo "run_eval: $t not on PATH" >&2; exit 1; }
done
[ -d "$VENDORED" ] || {
  echo "run_eval: no local artifact set at $SET (git-ignored; built by tools/native_build)" >&2
  exit 1
}
# pristine_check, not_built, packaged, offline_verdict (tested by
# packages/wallet_core_flutter_native/test/eval_option1/verdicts_test.dart).
. "$EVAL/tool/verdicts.sh"
pristine_check "$APP" 'before the run'
rm -rf "$WORK"
mkdir -p "$LOGS" "$EVAL/results"
: >"$RESULTS"

say "eval manifest is current, valid, and pins the files on disk"
dart run eval/option1/tool/make_eval_manifest.dart --check
dart run tools/manifest/bin/validate.dart "$MANIFEST"
tool verify-set "$MANIFEST" "$VENDORED"

SET_ID=$(tool value "$MANIFEST" identity.artifact_set_id)
COMMIT=$(tool value "$MANIFEST" identity.upstream_commit)
DEFINES="--dart-define=WCF_EXPECTED_ARTIFACT_SET_ID=$SET_ID --dart-define=WCF_EXPECTED_UPSTREAM_COMMIT=$COMMIT"
# The toolchain, read here and nowhere hard-coded: every row that states a
# version takes it from these.
flutter --version --machine 2>/dev/null | sed -n '/^{/,$p' >"$LOGS/flutter-version.json"
FLUTTER_VERSION=$(tool value "$LOGS/flutter-version.json" frameworkVersion)
DART_VERSION=$(tool value "$LOGS/flutter-version.json" dartSdkVersion)
FLUTTER_ROOT_DIR=$(tool value "$LOGS/flutter-version.json" flutterRoot)
XCODE_VERSION=$(xcodebuild -version 2>/dev/null | head -1 || true)
[ -n "$XCODE_VERSION" ] || XCODE_VERSION='Xcode (version unreadable)'
template_target() {
  grep -m1 -o "$1 = [0-9.]*" "$2" 2>/dev/null | sed 's/.*= //' || true
}
IOS_TEMPLATE=$(template_target IPHONEOS_DEPLOYMENT_TARGET "$APP/ios/Runner.xcodeproj/project.pbxproj")
MACOS_TEMPLATE=$(template_target MACOSX_DEPLOYMENT_TARGET "$APP/macos/Runner.xcodeproj/project.pbxproj")
TOOLCHAIN="Flutter $FLUTTER_VERSION / Dart $DART_VERSION / $XCODE_VERSION; consumer generated with iOS ${IOS_TEMPLATE:-?} / macOS ${MACOS_TEMPLATE:-?} deployment targets"
say "toolchain: $TOOLCHAIN"
# The native package's own environment, which pub enforces on every consumer.
PKG_PUBSPEC="$REPO/packages/wallet_core_flutter_native/pubspec.yaml"
PKG_SDK=$(sed -n 's/^  sdk: *//p' "$PKG_PUBSPEC" | head -1 | tr -d '"'"'")
PKG_FLUTTER=$(sed -n 's/^  flutter: *//p' "$PKG_PUBSPEC" | head -1 | tr -d '"'"'")

ORCH='orchestrator-run: the machine that ran this refused the build (see the log); rerun outside the sandbox'
# not_built's exit code 20 (tool/verdicts.sh); no target of the evaluated set
# uses it since as_4.8.0_001 ships Android libraries.
NOART='no artifact for this target in the evaluated set'

say "staging the consumer at $BUILD"
tool stage "$APP" "$BUILD"
[ ! -e "$BUILD/.dart_tool" ] || { echo "run_eval: $BUILD/.dart_tool exists after staging" >&2; exit 1; }
STAGE="dart run eval/option1/tool/eval_tool.dart stage eval/option1/consumer $BUILD && cd $BUILD"

MAC_APP="$BUILD/build/macos/Build/Products/Debug/wcf_eval_option1.app"
MAC_FW="$MAC_APP/Contents/Frameworks/TrustWalletCore.framework/TrustWalletCore"
# The simulator app is measured from a copy taken right after its step-1
# build: step 2's `flutter test -d <simulator>` rebuilds the same directory
# for the booted simulator's architecture only, so measuring it afterwards
# would compare a one-architecture SDK app with a two-architecture baseline.
SIM_BUILT="$BUILD/build/ios/iphonesimulator/Runner.app"
SIM_APP="$WORK/apps/sim/Runner.app"
SIM_FW="$SIM_APP/Frameworks/TrustWalletCore.framework/TrustWalletCore"
ARCHIVE="$BUILD/build/ios/archive/Runner.xcarchive"
DEV_APP="$ARCHIVE/Products/Applications/Runner.app"
DEV_FW="$DEV_APP/Frameworks/TrustWalletCore.framework/TrustWalletCore"
# Host `flutter test` from two staged copies (step 1): under the default
# temporary directory, and under a short one. The short one is
# /tmp/wcf-o1-<pid> — outside $TMPDIR on purpose, because with as_4.8.0_000
# the default macOS $TMPDIR (/var/folders/…/T/, resolved under /private/var)
# was itself too deep for the install name Flutter writes; it is created and
# removed here.
HOST_TMPDIR="$WORK/h"
SHORT_ROOT="/tmp/wcf-o1-$$"
SHORT_DIR="$SHORT_ROOT/h"
# The longest install name the macOS arm64 slice's header padding takes:
# 87 + (spare bytes - 56). as_4.8.0_000 had 56 spare bytes (87 characters);
# as_4.8.0_001 is linked with -headerpad_max_install_names (T1.2-d1) and has
# 6168 (otool -l: __text offset 8480 - 32 - sizeofcmds 2280).
HEADER_SPARE=6168
INSTALL_NAME_LIMIT=$((87 + HEADER_SPARE - 56))
# Android (T1.8b). The evaluated set ships arm64-v8a and x86_64 only — PRD
# §12.2 step 8 ships an ABI only if it is tested, and armeabi-v7a was never
# built — so every APK is built for exactly those two (--target-platform).
# This host is Apple Silicon: an x86_64 system image does not run here, so the
# emulator rows are measured on an arm64-v8a emulator that must already be
# running (the script never boots or stops one), and the x86_64 library is
# measured statically from the same APKs. No physical device is attached.
ANDROID_PLATFORMS='android-arm64,android-x64'
AND_ARM=android-emulator-arm64-v8a
AND_X64=android-emulator-x86_64
AND_DEV=android-device-arm64-v8a
AND_ARM_NAME='android/arm64-v8a/libTrustWalletCore.so'
AND_X64_NAME='android/x86_64/libTrustWalletCore.so'
AND_PACKAGE='dev.wcf.eval.wcf_eval_option1'
# The four TW* exports outside the symbol list that every Android build of
# upstream's module carries — its JNI glue (jni/cpp/TWJNIData.h,
# TWJNIString.h) — allowed exactly as tools/native_build/build_android.sh
# allows them; any other extra still fails.
JNI_ALLOW='--allow-extra TWDataCreateWithJByteArray --allow-extra TWDataJByteArray --allow-extra TWStringCreateWithJString --allow-extra TWStringJString'
APK_OUT="$BUILD/build/app/outputs/flutter-apk"
# Each APK is copied here right after its build: later steps rebuild the same
# outputs (step 2's `flutter test -d <emulator>` for one ABI only, the release
# probe with another entry point).
AND_APPS="$WORK/apps/android"
NO_DEVICE='no physical Android device is attached to this host. The APK is the one the emulator columns measure; what is unmeasured is installing and running it on arm64 hardware'
NO_X64='Apple-Silicon host: an x86_64 Android system image does not run here, so the emulator rows are measured on arm64-v8a; the x86_64 library is measured statically from the same APK (symbols, size, alignment, libc++_shared copy)'
ANDROID_SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
ADB=$(command -v adb || true)
[ -n "$ADB" ] || ADB="$ANDROID_SDK/platform-tools/adb"
APKSIGNER="$(ls -d "$ANDROID_SDK"/build-tools/*/ 2>/dev/null | sort -V | tail -1)apksigner"
# The NDK whose libc++_shared.so android_libcpp_shared 0.2.1 bundles: the one
# the Flutter build uses (read from the installed Flutter's Gradle plugin),
# else the newest installed. Its llvm-readelf reads ELF notes and DT_NEEDED.
NDK_ROOT="$ANDROID_SDK/ndk"
FLUTTER_NDK=$(grep -ho 'val ndkVersion: String = "[^"]*"' \
  "$FLUTTER_ROOT_DIR/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt" 2>/dev/null |
  sed 's/.*= "//; s/"$//' || true)
NDK=''
if [ -n "$FLUTTER_NDK" ] && [ -d "$NDK_ROOT/$FLUTTER_NDK" ]; then
  NDK="$NDK_ROOT/$FLUTTER_NDK/"
elif [ -d "$NDK_ROOT" ]; then
  NDK=$(ls -d "$NDK_ROOT"/*/ | sort -V | tail -1)
fi
[ -n "$NDK" ] || { echo "run_eval: no Android NDK under $NDK_ROOT" >&2; exit 1; }
READELF="${NDK}toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-readelf"
for t in "$ADB" "$APKSIGNER" "$READELF"; do
  [ -x "$t" ] || { echo "run_eval: $t not found" >&2; exit 1; }
done
command -v unzip >/dev/null || { echo "run_eval: unzip not on PATH" >&2; exit 1; }

# apk_libs APK: the APK's native libraries, `lib/<abi>/<name>.so <bytes>`,
# comma-separated.
apk_libs() {
  unzip -l "$1" | awk '$4 ~ /^lib\/[^\/]+\/[^\/]+\.so$/ { printf "%s%s %s", sep, $4, $1; sep = ", " }'
}
# build_id ELF: the GNU build ID, which tells two builds of one library apart
# after Gradle's strip (the bytes differ, the note survives).
build_id() {
  "$READELF" -n "$1" 2>/dev/null | sed -n 's/^ *Build ID: //p' | head -1
}
# android_probe DEVICE APK LOG: installs APK, cold-starts its activity, and
# waits up to 60 s for the probe's line in logcat. Sets PROBE_LINE (empty if
# none) and LAUNCH (am start -W's status, launch state and time).
android_probe() {
  {
    "$ADB" -s "$1" install -r "$2" &&
      "$ADB" -s "$1" shell am force-stop "$AND_PACKAGE" &&
      "$ADB" -s "$1" logcat -c &&
      "$ADB" -s "$1" shell am start -W -n "$AND_PACKAGE/.MainActivity"
  } >"$3" 2>&1 || true
  PROBE_LINE=''
  n=0
  while [ $n -lt 60 ]; do
    PROBE_LINE=$("$ADB" -s "$1" logcat -d -s flutter:I 2>/dev/null | tr -d '\r' | grep -o 'WCF_PROBE .*' | head -1 || true)
    [ -z "$PROBE_LINE" ] || break
    sleep 1
    n=$((n + 1))
  done
  "$ADB" -s "$1" logcat -d -s flutter:I >>"$3" 2>&1 || true
  LAUNCH=$(tr -d '\r' <"$3" | grep -E '^(Status|LaunchState|TotalTime):' | tr '\n' ' ' | sed 's/ *$//' || true)
}

# record_build CHECK TARGET RC LOG COMMAND [PASS_SUMMARY]
record_build() {
  check=$1
  target=$2
  rc=$3
  log=$4
  command=$5
  summary=${6:-built}
  case $rc in
    0) row --check "$check" --target "$target" --status pass --summary "$summary" \
         --command "$command" --notes "log: $log" ;;
    10) row --check "$check" --target "$target" --status unmeasured \
          --summary 'refused here' --command "$command" --notes "$ORCH; log: $log" ;;
    *) row --check "$check" --target "$target" --status fail --summary 'build failed' \
         --command "$command" --notes "log: $log"
       abort "$target: $command failed; see $log" ;;
  esac
}

# not_built, packaged and offline_verdict (tool/verdicts.sh, sourced in step
# 0) are the shell side of when a row may say `pass`.
evidence() { tool offline-evidence "$1" "$2"; }

# ---------------------------------------------------------------------------
# 1. Clean consumer build, no manual native edits (offline, vendored, verified
#    against the eval manifest by the hook), each in the staged copy.
# ---------------------------------------------------------------------------
say "step 1: consumer builds"
# The macOS desktop app: not a PRD §12.2 target (the macOS host matters for
# `flutter test`, below), so a failure is recorded and never stops the run.
# MAC_REASON, when set, is why every row that needs the macOS app is `skip`.
MAC_CMD="$STAGE && flutter build macos --debug $DEFINES"
MAC_REASON=''
rc=0; attempt "$LOGS/macos-debug.log" "$BUILD" flutter build macos --debug $DEFINES || rc=$?
MAC_RC=$rc
if [ $rc -ne 0 ]; then
  CLASS=$(tool classify-macos-build "$LOGS/macos-debug.log" "$BUILD")
else
  CLASS=''
fi
case $CLASS in
  template-deployment-target*)
    # tab-separated: kind, template value, Xcode minimum, Xcode maximum
    MAC_TEMPLATE=$(printf %s "$CLASS" | cut -f2)
    MAC_MIN=$(printf %s "$CLASS" | cut -f3)
    MAC_MAX=$(printf %s "$CLASS" | cut -f4)
    MAC_REASON="the flutter create macOS template sets MACOSX_DEPLOYMENT_TARGET $MAC_TEMPLATE and this Xcode supports $MAC_MIN to $MAC_MAX, so the generated project does not build; independent of the package (an empty flutter create app fails the same way), fixing it is a native edit the evaluation forbids, and macOS desktop is not a PRD §12.2 target ($TOOLCHAIN)"
    row --check consumer-build --target macos-host/debug --status skip \
      --summary "template target $MAC_TEMPLATE < Xcode minimum $MAC_MIN" \
      --command "$MAC_CMD" --notes "$MAC_REASON; log: $LOGS/macos-debug.log"
    ;;
  podfile-missing*)
    # tab-separated: kind, native plugins on other platforms, SPM for macOS
    MAC_PLUGINS=$(printf %s "$CLASS" | cut -f2)
    MAC_SPM=$(printf %s "$CLASS" | cut -f3)
    MAC_REASON="Flutter stopped with 'Podfile missing' before Xcode or the hook ran: the app has native plugins for other platforms ($MAC_PLUGINS — the iOS/Android-only integration_test dev dependency), so Flutter runs CocoaPods for macOS too, but no plugin supports macOS, so it never generates macos/Podfile, and Swift Package Manager is off for macOS on this host (swift_package_manager_enabled.macos: $MAC_SPM). A Flutter tooling gap independent of the package; writing the Podfile by hand is a native edit, and macOS desktop is not a PRD §12.2 target ($TOOLCHAIN)"
    row --check consumer-build --target macos-host/debug --status skip \
      --summary "Podfile missing (no macOS plugin, SPM $MAC_SPM)" \
      --command "$MAC_CMD" --notes "$MAC_REASON; log: $LOGS/macos-debug.log"
    ;;
  other)
    if [ $rc -eq 10 ]; then
      record_build consumer-build macos-host/debug $rc "$LOGS/macos-debug.log" "$MAC_CMD"
    else
      MAC_REASON="the macOS app build failed (consumer-build macos-host/debug); macOS desktop is not a PRD §12.2 target, so the run continued"
      row --check consumer-build --target macos-host/debug --status fail \
        --summary 'macOS app build failed' --command "$MAC_CMD" \
        --notes "not a required target; the run continued; log: $LOGS/macos-debug.log"
    fi
    ;;
  *)
    record_build consumer-build macos-host/debug $rc "$LOGS/macos-debug.log" "$MAC_CMD"
    ;;
esac

# The first build of each iOS artifact in the staged copy is also its clean
# offline install (step 7): the hook evidence is read right before and right
# after it, before any later build can touch that artifact's cache entry.
SIM_PRE=$(evidence "$BUILD" "$SIM_NAME")
rc=0; attempt "$LOGS/ios-sim-debug.log" "$BUILD" flutter build ios --simulator --debug $DEFINES || rc=$?
SIM_RC=$rc
SIM_POST=$(evidence "$BUILD" "$SIM_NAME")
record_build consumer-build ios-simulator-arm64/debug $rc "$LOGS/ios-sim-debug.log" \
  "$STAGE && flutter build ios --simulator --debug $DEFINES"
if [ $SIM_RC -eq 0 ]; then
  mkdir -p "$(dirname "$SIM_APP")"
  cp -R "$SIM_BUILT" "$(dirname "$SIM_APP")/"
fi

rc=0; attempt "$LOGS/ios-sim-release.log" "$BUILD" flutter build ios --simulator --release $DEFINES || rc=$?
if [ $rc -ne 0 ] && grep -q 'mode is not supported for simulators' "$LOGS/ios-sim-release.log"; then
  row --check consumer-build --target ios-simulator-arm64/release --status skip \
    --summary 'Flutter refuses' \
    --command "$STAGE && flutter build ios --simulator --release" \
    --notes "Flutter: \"Release mode is not supported for simulators.\" Not an Option 1 property; release is measured on the device archive."
else
  record_build consumer-build ios-simulator-arm64/release $rc "$LOGS/ios-sim-release.log" \
    "$STAGE && flutter build ios --simulator --release $DEFINES"
fi

# The archive before the device debug build, so the archive is the first
# build of the device artifact (its offline row, step 7).
DEV_PRE=$(evidence "$BUILD" "$DEV_NAME")
rc=0; attempt "$LOGS/ios-device-archive.log" "$BUILD" flutter build ipa --release --no-codesign $DEFINES || rc=$?
DEV_RC=$rc
DEV_POST=$(evidence "$BUILD" "$DEV_NAME")
record_build consumer-build ios-device-arm64/release $rc "$LOGS/ios-device-archive.log" \
  "$STAGE && flutter build ipa --release --no-codesign $DEFINES" 'archived, unsigned'

rc=0; attempt "$LOGS/ios-device-debug.log" "$BUILD" flutter build ios --debug --no-codesign $DEFINES || rc=$?
record_build consumer-build ios-device-arm64/debug $rc "$LOGS/ios-device-debug.log" \
  "$STAGE && flutter build ios --debug --no-codesign $DEFINES" 'built, unsigned'

# Android: the debug APK first, so it is the clean offline build of both ABIs
# (step 7: the hook evidence is read right before and right after it), then
# release. Each APK is copied away right after its build.
AND_ARM_PRE=$(evidence "$BUILD" "$AND_ARM_NAME")
AND_X64_PRE=$(evidence "$BUILD" "$AND_X64_NAME")
AND_DEBUG_RC=0
attempt "$LOGS/android-debug.log" "$BUILD" flutter build apk --debug --target-platform $ANDROID_PLATFORMS $DEFINES || AND_DEBUG_RC=$?
AND_ARM_POST=$(evidence "$BUILD" "$AND_ARM_NAME")
AND_X64_POST=$(evidence "$BUILD" "$AND_X64_NAME")
mkdir -p "$AND_APPS"
[ $AND_DEBUG_RC -ne 0 ] || cp "$APK_OUT/app-debug.apk" "$AND_APPS/app-debug.apk"
AND_RELEASE_RC=0
attempt "$LOGS/android-release.log" "$BUILD" flutter build apk --release --target-platform $ANDROID_PLATFORMS $DEFINES || AND_RELEASE_RC=$?
[ $AND_RELEASE_RC -ne 0 ] || cp "$APK_OUT/app-release.apk" "$AND_APPS/app-release.apk"

# android_build_rows MODE RC LOG: the consumer-build rows of one APK. `pass`
# only if the APK holds our library for both shipped ABIs.
android_build_rows() {
  b_mode=$1
  b_rc=$2
  b_log=$3
  b_cmd="$STAGE && flutter build apk --$b_mode --target-platform $ANDROID_PLATFORMS $DEFINES"
  if [ "$b_rc" -eq 0 ]; then
    b_libs=$(apk_libs "$AND_APPS/app-$b_mode.apk")
    for abi in arm64-v8a x86_64; do
      case "$b_libs, " in
        *"lib/$abi/libTrustWalletCore.so "*) ;;
        *)
          row --check consumer-build --target "$AND_ARM/$b_mode" --status fail \
            --summary "no $abi library in the APK" \
            --command "$b_cmd && unzip -l build/app/outputs/flutter-apk/app-$b_mode.apk" \
            --notes "APK native libraries (bytes): $b_libs; log: $b_log"
          abort "$AND_ARM/$b_mode: the APK has no lib/$abi/libTrustWalletCore.so"
          ;;
      esac
    done
    row --check consumer-build --target "$AND_ARM/$b_mode" --status pass \
      --summary 'built; arm64-v8a and x86_64 .so in the APK' \
      --command "$b_cmd && unzip -l build/app/outputs/flutter-apk/app-$b_mode.apk" \
      --notes "APK native libraries (bytes): $b_libs. Bundled by the hook from vendored_dir, offline, verified against the eval manifest; log: $b_log"
    row --check consumer-build --target "$AND_X64/$b_mode" --status pass \
      --summary 'built; x86_64 .so in the APK' \
      --command "$b_cmd && unzip -l build/app/outputs/flutter-apk/app-$b_mode.apk" \
      --notes "the same APK as $AND_ARM/$b_mode (one APK carries both ABIs). $NO_X64; log: $b_log"
  else
    record_build consumer-build "$AND_ARM/$b_mode" "$b_rc" "$b_log" "$b_cmd"
    record_build consumer-build "$AND_X64/$b_mode" "$b_rc" "$b_log" "$b_cmd"
  fi
  row --check consumer-build --target "$AND_DEV/$b_mode" --status unmeasured \
    --summary 'no physical device' \
    --command "$b_cmd && flutter install --$b_mode -d <arm64-device-id>" --notes "$NO_DEVICE"
}
android_build_rows debug "$AND_DEBUG_RC" "$LOGS/android-debug.log"
android_build_rows release "$AND_RELEASE_RC" "$LOGS/android-release.log"

# armeabi-v7a is not shipped. What a consumer meets: a default
# `flutter build apk` also targets android-arm, and the hook refuses that
# build with the remedy. Measured once, in its own staged copy.
ABI_APP="$WORK/abi"
tool stage "$APP" "$ABI_APP" >/dev/null
rc=0; attempt "$LOGS/android-default-abis.log" "$ABI_APP" flutter build apk --debug $DEFINES || rc=$?
ABI_CMD="dart run eval/option1/tool/eval_tool.dart stage eval/option1/consumer $ABI_APP && cd $ABI_APP && flutter build apk --debug $DEFINES   # no --target-platform: android-arm, android-arm64 and android-x64"
REFUSAL=$(grep -m1 'Android arm is not shipped' "$LOGS/android-default-abis.log" | sed 's/^ *//' || true)
if [ $rc -eq 10 ]; then
  row --check default-abi-build --target android-emulator-arm64-v8a/debug --status unmeasured --summary 'refused here' \
    --command "$ABI_CMD" --notes "$ORCH; log: $LOGS/android-default-abis.log"
elif [ $rc -ne 0 ] && [ -n "$REFUSAL" ]; then
  row --check default-abi-build --target android-emulator-arm64-v8a/debug --status pass \
    --summary 'refused at the hook with the remedy --target-platform android-arm64,android-x64' --command "$ABI_CMD" \
    --notes "as_4.8.0_001 builds no armeabi-v7a library. A default-ABI build stops at the hook with: $REFUSAL log: $LOGS/android-default-abis.log"
else
  row --check default-abi-build --target android-emulator-arm64-v8a/debug --status fail \
    --summary 'default-ABI build not refused by the hook' --command "$ABI_CMD" \
    --notes "exit $rc and no refusal line: an APK for android-arm must not build without an armeabi-v7a library; log: $LOGS/android-default-abis.log"
fi

# Host `flutter test` runs the hook too, and Flutter rewrites the bundled
# dylib's install name to its absolute path, which must fit the dylib's
# Mach-O header padding. Two staged copies, one above and one below the
# limit, neither of which stops the run: the result is the finding, whichever
# way it goes. (Until T1.8a delta 5 a third run was made in the checkout
# itself, at its 133-character path; it was dropped because it measured
# nothing the two staged rows do not — another path over the limit — and any
# flutter command in the checkout writes a Podfile into it, see the header.)
# host_test TARGET DIR LOG: 0 ran, 1 failed, 10 refused.
host_test() {
  target=$1
  dir=$2
  log=$3
  rc=0; attempt "$log" "$dir" flutter test test/bundled_library_test.dart $DEFINES || rc=$?
  # The install name Flutter writes is the resolved path (/tmp -> /private/tmp,
  # /var/folders -> /private/var/folders).
  real="$(cd "$dir" && pwd -P)/build/native_assets/macos/libTrustWalletCore.dylib"
  length=$(printf %s "$real" | wc -c | tr -d ' ')
  command="cd $dir && flutter test test/bundled_library_test.dart $DEFINES"
  if [ $rc -eq 0 ]; then
    row --check consumer-build --target "$target" --status pass --summary "built and ran ($length-char path)" \
      --command "$command" --value "install_name_chars=$length" --value "limit_chars=$INSTALL_NAME_LIMIT" \
      --notes "install name $length characters, within the $INSTALL_NAME_LIMIT-character limit of the macOS arm64 slice's header padding; log: $log"
    return 0
  fi
  if grep -q 'larger updated load commands do not fit' "$log"; then
    row --check consumer-build --target "$target" --status fail \
      --summary "install_name_tool: header too small for a $length-char path" \
      --command "$command" --value "install_name_chars=$length" --value "limit_chars=$INSTALL_NAME_LIMIT" \
      --notes "Flutter's host test runner sets the dylib's install name to its absolute path; our Mach-O header has $HEADER_SPARE spare bytes in the macOS arm64 slice (otool -l), so any path over $INSTALL_NAME_LIMIT characters fails, and this one is $length. The artifact build must link with -Wl,-headerpad_max_install_names (T1.2). log: $log"
    return 1
  fi
  if [ $rc -eq 10 ]; then
    row --check consumer-build --target "$target" --status unmeasured --summary 'refused here' \
      --command "$command" --notes "$ORCH; log: $log"
    return 10
  fi
  row --check consumer-build --target "$target" --status fail --summary 'host flutter test failed' \
    --command "$command" --notes "not the install-name limit; recorded, and the run continued; log: $log"
  return 1
}
say "step 1: host flutter test, under the default temporary directory"
tool stage "$APP" "$HOST_TMPDIR"
TMPDIR_PRE=$(evidence "$HOST_TMPDIR" "$MAC_NAME")
TMPDIR_RC=0
host_test macos-host/flutter-test-tmpdir "$HOST_TMPDIR" "$LOGS/host-test-tmpdir.log" || TMPDIR_RC=$?
TMPDIR_POST=$(evidence "$HOST_TMPDIR" "$MAC_NAME")
say "step 1: host flutter test, from a short path ($SHORT_ROOT)"
SHORT_RC=1
if mkdir "$SHORT_ROOT" 2>/dev/null; then
  trap 'rm -rf "$SHORT_ROOT"' EXIT
  tool stage "$APP" "$SHORT_DIR"
  SHORT_PRE=$(evidence "$SHORT_DIR" "$MAC_NAME")
  SHORT_RC=0
  host_test macos-host/flutter-test-short-path "$SHORT_DIR" "$LOGS/host-test-short.log" || SHORT_RC=$?
  SHORT_POST=$(evidence "$SHORT_DIR" "$MAC_NAME")
else
  row --check consumer-build --target macos-host/flutter-test-short-path --status unmeasured \
    --summary "cannot create $SHORT_ROOT here" \
    --command "mkdir /tmp/wcf-o1-<pid> && dart run eval/option1/tool/eval_tool.dart stage eval/option1/consumer /tmp/wcf-o1-<pid>/h && cd /tmp/wcf-o1-<pid>/h && flutter test test/bundled_library_test.dart $DEFINES" \
    --notes "this machine does not allow writing under /tmp outside its temporary directory; $ORCH"
fi
# The host run every later host row uses: the short path if it ran, else the
# default temporary directory if that ran.
if [ $SHORT_RC -eq 0 ]; then
  HOST_RC=0; HOST="$SHORT_DIR"; HOST_TARGET=macos-host/flutter-test-short-path
  HOST_LOG="$LOGS/host-test-short.log"; HOST_PRE=$SHORT_PRE; HOST_POST=$SHORT_POST
elif [ $TMPDIR_RC -eq 0 ]; then
  HOST_RC=0; HOST="$HOST_TMPDIR"; HOST_TARGET=macos-host/flutter-test-tmpdir
  HOST_LOG="$LOGS/host-test-tmpdir.log"; HOST_PRE=$TMPDIR_PRE; HOST_POST=$TMPDIR_POST
else
  HOST_RC=1; HOST="$HOST_TMPDIR"; HOST_TARGET=macos-host/flutter-test-short-path
  HOST_LOG="$LOGS/host-test-short.log"; HOST_PRE=''; HOST_POST=''
fi
HOST_LIB="$HOST/build/native_assets/macos/libTrustWalletCore.dylib"

# ---------------------------------------------------------------------------
# 2. Runs on the targets that are running here. Nothing is booted or started.
# ---------------------------------------------------------------------------
say "step 2: run on targets"
flutter devices --machine --device-timeout 15 >"$LOGS/devices.json" 2>/dev/null || true

run_integration() {
  target=$1
  device=$2
  log=$3
  command="$STAGE && flutter test integration_test/wallet_core_test.dart -d $device $DEFINES"
  rc=0; attempt "$log" "$BUILD" flutter test integration_test/wallet_core_test.dart -d "$device" $DEFINES || rc=$?
  record_build run-on-target "$target" $rc "$log" "$command" 'ran'
  if [ $rc -eq 0 ]; then
    probe=$(grep -o 'WCF_PROBE PASS.*' "$log" | head -1)
    row --check symbols-runtime-lookup --target "$target" --status pass \
      --summary 'all resolved' --command "$command" --notes "$probe"
  else
    row --check symbols-runtime-lookup --target "$target" --status unmeasured \
      --summary 'refused here' --command "$command" --notes "$ORCH; log: $log"
  fi
}

if [ $MAC_RC -eq 0 ]; then
  run_integration macos-host/debug macos "$LOGS/run-macos.log"
elif [ -n "$MAC_REASON" ]; then
  for c in run-on-target symbols-runtime-lookup; do
    row --check $c --target macos-host/debug --status skip --summary 'no macOS app' \
      --command "$STAGE && flutter test integration_test/wallet_core_test.dart -d macos $DEFINES" \
      --notes "$MAC_REASON"
  done
else
  for c in run-on-target symbols-runtime-lookup; do
    row --check $c --target macos-host/debug --status unmeasured --summary 'not built here' \
      --command "$STAGE && flutter test integration_test/wallet_core_test.dart -d macos $DEFINES" \
      --notes "$ORCH"
  done
fi

SIM_ID=$(tool pick-device "$LOGS/devices.json" ios-simulator)
if [ -n "$SIM_ID" ] && [ $SIM_RC -eq 0 ]; then
  run_integration ios-simulator-arm64/debug "$SIM_ID" "$LOGS/run-ios-sim.log"
else
  for c in run-on-target symbols-runtime-lookup; do
    row --check $c --target ios-simulator-arm64/debug --status unmeasured \
      --summary 'no booted simulator' \
      --command "$STAGE && flutter test integration_test/wallet_core_test.dart -d <booted-simulator-id> $DEFINES" \
      --notes "$ORCH (needs a booted iOS simulator; this script never boots one)"
  done
fi

for t in ios-device-arm64/debug ios-device-arm64/release; do
  mode=${t#*/}
  for c in run-on-target symbols-runtime-lookup; do
    row --check $c --target "$t" --status unmeasured --summary 'needs a device' \
      --command "$STAGE && flutter run --$mode -d <device-id> -t lib/probe_main.dart $DEFINES  (look for WCF_PROBE PASS)" \
      --notes 'T1.8b: physical iPhone with a signing team set by the person running it'
  done
done
# Android: the arm64-v8a emulator that is already running (never booted
# here). Debug runs the integration test; release installs the probe build and
# reads its line from logcat (integration tests do not run in release).
EMU_ID=$(tool pick-device "$LOGS/devices.json" android-emulator)
EMU_ABI=''
EMU_API=''
if [ -n "$EMU_ID" ]; then
  EMU_ABI=$("$ADB" -s "$EMU_ID" shell getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r' || true)
  EMU_API=$("$ADB" -s "$EMU_ID" shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r' || true)
fi
EMU_OK=0
if [ -n "$EMU_ID" ] && [ "$EMU_ABI" = arm64-v8a ]; then EMU_OK=1; fi
EMU_NOTE="emulator ${EMU_ID:-none} ($EMU_ABI, API $EMU_API)"
say "Android emulator: $EMU_NOTE"
if [ $EMU_OK -eq 1 ] && [ $AND_DEBUG_RC -eq 0 ]; then
  run_integration "$AND_ARM/debug" "$EMU_ID" "$LOGS/run-android-emulator-debug.log"
else
  for c in run-on-target symbols-runtime-lookup; do
    row --check $c --target "$AND_ARM/debug" --status unmeasured \
      --summary 'no arm64-v8a emulator running' \
      --command "$STAGE && flutter test integration_test/wallet_core_test.dart -d <arm64-emulator-id> $DEFINES" \
      --notes "needs a booted arm64-v8a emulator (this script never boots one) and this run's debug APK; found: $EMU_NOTE, debug build exit $AND_DEBUG_RC"
  done
fi

PROBE_APK="$AND_APPS/app-release-probe.apk"
PROBE_BUILD="$STAGE && flutter build apk --release --target-platform $ANDROID_PLATFORMS -t lib/probe_main.dart $DEFINES"
probe_cmd() {
  echo "$PROBE_BUILD && adb -s $1 install -r build/app/outputs/flutter-apk/app-release.apk && adb -s $1 logcat -c && adb -s $1 shell am start -W -n $AND_PACKAGE/.MainActivity && adb -s $1 logcat -d -s flutter:I   (look for WCF_PROBE PASS)"
}
PROBE_CMD=$(probe_cmd '<arm64-emulator-id>')
PROBE_PASS=0
if [ $EMU_OK -eq 1 ] && [ $AND_RELEASE_RC -eq 0 ]; then
  PROBE_CMD=$(probe_cmd "$EMU_ID")
  rc=0; attempt "$LOGS/android-release-probe-build.log" "$BUILD" flutter build apk --release --target-platform $ANDROID_PLATFORMS -t lib/probe_main.dart $DEFINES || rc=$?
  if [ $rc -eq 0 ]; then
    cp "$APK_OUT/app-release.apk" "$PROBE_APK"
    android_probe "$EMU_ID" "$PROBE_APK" "$LOGS/run-android-emulator-release.log"
    case $PROBE_LINE in
      'WCF_PROBE PASS'*)
        PROBE_PASS=1
        AND_PROBE_LINE=$PROBE_LINE
        AND_LAUNCH=$LAUNCH
        row --check run-on-target --target "$AND_ARM/release" --status pass --summary 'ran' \
          --command "$PROBE_CMD" \
          --notes "$EMU_NOTE; am start -W: $LAUNCH; $PROBE_LINE; log: $LOGS/run-android-emulator-release.log"
        row --check symbols-runtime-lookup --target "$AND_ARM/release" --status pass \
          --summary 'all resolved' --command "$PROBE_CMD" --notes "$PROBE_LINE"
        ;;
      *)
        for c in run-on-target symbols-runtime-lookup; do
          row --check $c --target "$AND_ARM/release" --status fail --summary 'probe did not pass' \
            --command "$PROBE_CMD" \
            --notes "${PROBE_LINE:-no WCF_PROBE line in logcat within 60 s}; am start -W: ${LAUNCH:-none}; log: $LOGS/run-android-emulator-release.log"
        done
        abort "$AND_ARM/release: ${PROBE_LINE:-no WCF_PROBE line}"
        ;;
    esac
  else
    record_build run-on-target "$AND_ARM/release" $rc "$LOGS/android-release-probe-build.log" "$PROBE_CMD"
    row --check symbols-runtime-lookup --target "$AND_ARM/release" --status unmeasured \
      --summary 'refused here' --command "$PROBE_CMD" --notes "$ORCH"
  fi
else
  for c in run-on-target symbols-runtime-lookup; do
    row --check $c --target "$AND_ARM/release" --status unmeasured \
      --summary 'no arm64-v8a emulator running' --command "$PROBE_CMD" \
      --notes "needs a booted arm64-v8a emulator (this script never boots one) and this run's release APK; found: $EMU_NOTE, release build exit $AND_RELEASE_RC"
  done
fi

for mode in debug release; do
  for c in run-on-target symbols-runtime-lookup; do
    if [ $mode = debug ]; then
      x64_cmd="$STAGE && flutter test integration_test/wallet_core_test.dart -d <x86_64-emulator-id> $DEFINES"
      dev_cmd="$STAGE && flutter test integration_test/wallet_core_test.dart -d <arm64-device-id> $DEFINES"
    else
      x64_cmd=$(probe_cmd '<x86_64-emulator-id>')
      dev_cmd=$(probe_cmd '<arm64-device-id>')
    fi
    row --check $c --target "$AND_X64/$mode" --status unmeasured --summary 'no x86_64 emulator here' \
      --command "$x64_cmd" --notes "$NO_X64"
    row --check $c --target "$AND_DEV/$mode" --status unmeasured --summary 'no physical device' \
      --command "$dev_cmd" --notes "$NO_DEVICE"
  done
done

# The host test is the runtime lookup this machine can run.
if [ $HOST_RC -eq 0 ]; then
  probe=$(grep -o 'WCF_PROBE PASS.*' "$HOST_LOG" | head -1)
  row --check symbols-runtime-lookup --target "$HOST_TARGET" --status pass \
    --summary 'all resolved' \
    --command "cd $HOST && flutter test test/bundled_library_test.dart $DEFINES" --notes "$probe"
fi

# ---------------------------------------------------------------------------
# 3. Release launches and signs.
# ---------------------------------------------------------------------------
say "step 3: release launch"
row --check release-launch-and-sign --target ios-simulator-arm64/release --status skip \
  --summary 'no simulator release' --command 'flutter run --release -d <simulator>' \
  --notes 'Flutter builds no release mode for the iOS simulator'
row --check release-launch-and-sign --target ios-device-arm64/release --status unmeasured \
  --summary 'needs a device' \
  --command "$STAGE && flutter run --release -d <device-id> -t lib/probe_main.dart $DEFINES" \
  --notes 'T1.8b; the probe makes a real call, transaction signing needs the SDK signer (later tasks)'
# Android: the release probe APK of step 2 — the same release configuration as
# step 1's, with the probe's entry point — launched on the emulator, and its
# signature verified.
if [ $PROBE_PASS -eq 1 ]; then
  SIGN=$("$APKSIGNER" verify --print-certs "$PROBE_APK" 2>&1 || true)
  SIGNER=$(printf '%s\n' "$SIGN" | sed -n 's/^Signer #1 certificate DN: //p' | head -1)
  SIGN_RC=0
  "$APKSIGNER" verify "$PROBE_APK" >/dev/null 2>&1 || SIGN_RC=$?
  case "$SIGN_RC:$AND_LAUNCH" in
    0:*'Status: ok'*)
      row --check release-launch-and-sign --target "$AND_ARM/release" --status pass \
        --summary 'launched, probe PASS; signed with the debug keystore' \
        --command "$PROBE_CMD && apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk" \
        --notes "$EMU_NOTE; am start -W: $AND_LAUNCH; apksigner verify: OK, signer $SIGNER. The flutter create template signs release with signingConfigs.debug; an upload key is the app author's, not a property of the packaging option. $AND_PROBE_LINE"
      ;;
    *)
      row --check release-launch-and-sign --target "$AND_ARM/release" --status fail \
        --summary 'release did not launch or verify' \
        --command "$PROBE_CMD && apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk" \
        --notes "am start -W: ${AND_LAUNCH:-none}; apksigner verify exit $SIGN_RC: $SIGN"
      ;;
  esac
else
  row --check release-launch-and-sign --target "$AND_ARM/release" --status unmeasured \
    --summary 'release probe did not run' \
    --command "$PROBE_CMD && apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk" \
    --notes "needs step 2's release probe run on an arm64-v8a emulator; $EMU_NOTE"
fi
row --check release-launch-and-sign --target "$AND_X64/release" --status unmeasured \
  --summary 'no x86_64 emulator here' --command "$(probe_cmd '<x86_64-emulator-id>')" --notes "$NO_X64"
row --check release-launch-and-sign --target "$AND_DEV/release" --status unmeasured \
  --summary 'no physical device' --command "$(probe_cmd '<arm64-device-id>')" --notes "$NO_DEVICE"

# ---------------------------------------------------------------------------
# 4 and 5. Exported symbols and size: the verified artifacts, and the binary
#    Flutter actually packaged from them (after its lipo, strip, install-name
#    rewrite and re-sign) — only from a build that succeeded in this run.
# ---------------------------------------------------------------------------
say "steps 4-5: symbols and size"
# The verified artifacts, in the library columns.
for slice in ios/arm64 ios-simulator/arm64_x86_64 macos/arm64_x86_64; do
  lib="$VENDORED/$slice/libTrustWalletCore.dylib"
  harness symbols --artifact "$lib" --format macho --target "$slice"
  harness size --artifact "$lib" --target "$slice"
done
for check in symbols size; do
  fmt=''
  [ $check != symbols ] || fmt=' --format elf'
  row --check $check --target android/armeabi-v7a --status skip \
    --summary 'not shipped (PRD §12.2 step 8)' \
    --command "dart run tools/packaging_eval/bin/$check.dart --artifact third_party/wcf-native-all/artifacts/android/armeabi-v7a/libTrustWalletCore.so$fmt --target android/armeabi-v7a" \
    --notes 'as_4.8.0_001 builds no armeabi-v7a library: PRD §12.2 step 8 ships an ABI only if it is tested, and the hook refuses android-arm (consumer-build / android/armeabi-v7a)'
done
for abi in arm64-v8a x86_64; do
  so="$VENDORED/android/$abi/libTrustWalletCore.so"
  harness symbols --artifact "$so" --format elf --target "android/$abi" $JNI_ALLOW
  harness size --artifact "$so" --target "android/$abi"
done
# The binary inside each built app (`packaged`, tool/verdicts.sh), in that
# app's column — only from a build that succeeded in this run.
packaged "$DEV_RC" "$DEV_FW" ios-device-arm64/release macho
packaged "$SIM_RC" "$SIM_FW" ios-simulator-arm64/debug macho
if [ -n "$MAC_REASON" ]; then
  row --check symbols --target macos-host/debug --status skip --summary 'no macOS app' \
    --command "dart run tools/packaging_eval/bin/symbols.dart --artifact $MAC_FW --format macho --target macos-host/debug" \
    --notes "$MAC_REASON"
  row --check size --target macos-host/debug --status skip --summary 'no macOS app' \
    --command "dart run tools/packaging_eval/bin/size.dart --artifact $MAC_FW --target macos-host/debug" \
    --notes "$MAC_REASON"
else
  packaged "$MAC_RC" "$MAC_FW" macos-host/debug macho
fi
[ $HOST_RC -eq 0 ] && packaged 0 "$HOST_LIB" "$HOST_TARGET" macho
# The Android libraries as Gradle packaged them, out of step 1's release APK.
if [ $AND_DEBUG_RC -eq 0 ]; then
  mkdir -p "$AND_APPS/debug"
  unzip -o -q "$AND_APPS/app-debug.apk" 'lib/*' -d "$AND_APPS/debug"
fi
if [ $AND_RELEASE_RC -eq 0 ]; then
  mkdir -p "$AND_APPS/release"
  unzip -o -q "$AND_APPS/app-release.apk" 'lib/*' -d "$AND_APPS/release"
fi
packaged "$AND_RELEASE_RC" "$AND_APPS/release/lib/arm64-v8a/libTrustWalletCore.so" "$AND_ARM/release" elf $JNI_ALLOW
packaged "$AND_RELEASE_RC" "$AND_APPS/release/lib/x86_64/libTrustWalletCore.so" "$AND_X64/release" elf $JNI_ALLOW

for abi in arm64-v8a x86_64; do
  manifest_sha="$(jq -r ".artifacts[\"android/$abi/libTrustWalletCore.so\"].sha256" compat_manifest.json)"
  for mode in release debug; do
    if [ "$mode" = release ] && [ $AND_RELEASE_RC -ne 0 ]; then continue; fi
    if [ "$mode" = debug ] && [ $AND_DEBUG_RC -ne 0 ]; then continue; fi
    apk_sha="$(shasum -a 256 "$AND_APPS/$mode/lib/$abi/libTrustWalletCore.so" | cut -d' ' -f1)"
    apk_size="$(wc -c < "$AND_APPS/$mode/lib/$abi/libTrustWalletCore.so" | tr -d ' ')"
    short_apk="$(printf %s "$apk_sha" | cut -c 1-8)"
    short_man="$(printf %s "$manifest_sha" | cut -c 1-8)"
    if [ "$apk_sha" = "$manifest_sha" ]; then
      status=pass; summary="$mode APK: $short_apk = manifest $short_man"
    else
      status=fail; summary="$mode APK: $short_apk != manifest $short_man"
    fi
    row --check packaged-digest --target "android/$abi" --status "$status" \
      --command "unzip -p \"\$AND_APPS/app-$mode.apk\" lib/$abi/libTrustWalletCore.so | shasum -a 256" \
      --value "apk_sha256=$apk_sha" --value "apk_size=$apk_size" --value "manifest_sha256=$manifest_sha" \
      --summary "$summary" \
      --notes "lib/$abi/libTrustWalletCore.so in the $mode APK: sha256 $apk_sha, $apk_size B; the manifest pins android/$abi/libTrustWalletCore.so at $manifest_sha"
  done
done

# App-size delta: the same template app without the SDK, built the same way:
# the same Flutter, the same commands and modes, and the same plugin set — the
# consumer's integration_test dev dependency is a native plugin that a debug
# build embeds, so the baseline gets it too and the delta is the SDK alone.
# The SDK simulator app is the copy taken right after its step-1 build.
BASE="$WORK/baseline"
say "step 5: baseline app"
HOME_SAVE=$HOME
mkdir -p "$WORK/home"
HOME="$WORK/home" flutter create --project-name wcf_eval_option1 --org dev.wcf.eval \
  --platforms ios,android,macos --no-pub "$BASE" >"$LOGS/baseline-create.log" 2>&1
HOME=$HOME_SAVE
(cd "$BASE" && flutter pub add 'dev:integration_test:{"sdk":"flutter"}') >>"$LOGS/baseline-create.log" 2>&1 ||
  abort "could not add integration_test to the baseline app; see $LOGS/baseline-create.log"
BASE_DEV_RC=$DEV_RC
if [ $DEV_RC -eq 0 ]; then
  BASE_DEV_RC=0; attempt "$LOGS/baseline-archive.log" "$BASE" flutter build ipa --release --no-codesign || BASE_DEV_RC=$?
  [ $BASE_DEV_RC -eq 1 ] && abort "baseline archive failed; see $LOGS/baseline-archive.log"
fi
BASE_SIM_RC=$SIM_RC
if [ $SIM_RC -eq 0 ]; then
  BASE_SIM_RC=0; attempt "$LOGS/baseline-sim.log" "$BASE" flutter build ios --simulator --debug || BASE_SIM_RC=$?
  [ $BASE_SIM_RC -eq 1 ] && abort "baseline simulator build failed; see $LOGS/baseline-sim.log"
fi
if [ $BASE_DEV_RC -eq 0 ]; then
  harness size --baseline-app "$BASE/build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app" \
    --sdk-app "$DEV_APP" --target ios-device-arm64/release
else
  not_built app-size-delta ios-device-arm64/release "$BASE_DEV_RC" \
    "dart run tools/packaging_eval/bin/size.dart --baseline-app $BASE/build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app --sdk-app $DEV_APP --target ios-device-arm64/release"
fi
if [ $BASE_SIM_RC -eq 0 ]; then
  harness size --baseline-app "$BASE/build/ios/iphonesimulator/Runner.app" \
    --sdk-app "$SIM_APP" --target ios-simulator-arm64/debug
else
  not_built app-size-delta ios-simulator-arm64/debug "$BASE_SIM_RC" \
    "dart run tools/packaging_eval/bin/size.dart --baseline-app $BASE/build/ios/iphonesimulator/Runner.app --sdk-app $SIM_APP --target ios-simulator-arm64/debug"
fi

# The Android APKs of the same baseline app, with the same commands and ABIs.
# One APK carries both ABIs, so the delta lands in the arm64-v8a emulator
# column and the x86_64 column points at it.
for mode in debug release; do
  if [ $mode = debug ]; then sdk_rc=$AND_DEBUG_RC; else sdk_rc=$AND_RELEASE_RC; fi
  base_apk="$BASE/build/app/outputs/flutter-apk/app-$mode.apk"
  delta_cmd="dart run tools/packaging_eval/bin/size.dart --baseline-app $base_apk --sdk-app $AND_APPS/app-$mode.apk --target $AND_ARM/$mode"
  base_rc=$sdk_rc
  if [ $sdk_rc -eq 0 ]; then
    base_rc=0
    attempt "$LOGS/baseline-android-$mode.log" "$BASE" flutter build apk --$mode --target-platform $ANDROID_PLATFORMS || base_rc=$?
    [ $base_rc -ne 1 ] || abort "baseline APK ($mode) failed; see $LOGS/baseline-android-$mode.log"
  fi
  if [ $base_rc -eq 0 ]; then
    harness size --baseline-app "$base_apk" --sdk-app "$AND_APPS/app-$mode.apk" --target "$AND_ARM/$mode"
  else
    not_built app-size-delta "$AND_ARM/$mode" "$base_rc" "$delta_cmd"
  fi
  row --check app-size-delta --target "$AND_X64/$mode" --status skip \
    --summary "one APK for both ABIs (see $AND_ARM/$mode)" --command "$delta_cmd" \
    --notes "the APK measured in the $AND_ARM/$mode column carries the x86_64 library too; per-ABI library sizes are the size rows"
  row --check app-size-delta --target "$AND_DEV/$mode" --status unmeasured --summary 'no physical device' \
    --command "$delta_cmd" --notes "$NO_DEVICE"
done
# ---------------------------------------------------------------------------
# 6. Minimum Flutter/Dart.
# ---------------------------------------------------------------------------
say "step 6: minimum versions"
harness min_version --target host/toolchain
# The oldest Flutter tried is the one installed, so a target that built in
# step 1 has a measured "builds on" value and nothing below it. The floor a
# consumer can reach is the package's own `environment:` — pub refuses to
# resolve it on an older SDK — read from its pubspec here, not restated.
# Below that, the hooks dependencies alone would allow Dart 3.10 (hooks 2.0.2,
# required by android_libcpp_shared 0.2.1, and code_assets 1.2.1 both declare
# sdk >=3.10.0), reachable only if DECISION-6 lowers the package's own floor.
FLOOR_NOTE="oldest Flutter tried here: $FLUTTER_VERSION, the only one installed ($TOOLCHAIN). Declared floor, enforced by pub: the native package's environment (sdk: $PKG_SDK, flutter: $PKG_FLUTTER), so no older Flutter can resolve it. The hooks dependencies alone would allow Dart 3.10 (hooks 2.0.2 — required by android_libcpp_shared 0.2.1 — and code_assets 1.2.1 declare sdk >=3.10.0); that is reachable only if DECISION-6 lowers the package's own environment"
FLOOR_CMD="on each Flutter release from the declared floor (flutter: $PKG_FLUTTER) up to $FLUTTER_VERSION, oldest first, on a host Xcode that accepts that release's flutter create deployment targets: flutter --version && $STAGE && flutter build <target> (as step 1)"
floor_row() {
  target=$1
  state=$2
  case $state in
    pass) row --check min-version-floor --target "$target" --status unmeasured \
            --summary "only Flutter $FLUTTER_VERSION tried" \
            --command "$FLOOR_CMD" --notes "$FLOOR_NOTE" ;;
    skip) row --check min-version-floor --target "$target" --status skip \
            --summary 'no macOS app' --command "$FLOOR_CMD" --notes "$MAC_REASON" ;;
    *) row --check min-version-floor --target "$target" --status unmeasured \
         --summary "$state" --command "$FLOOR_CMD" --notes "$FLOOR_NOTE" ;;
  esac
}
state_of() {
  case $1 in
    0) echo pass ;;
    10) echo 'refused here' ;;
    *) echo 'not built' ;;
  esac
}
if [ -n "$MAC_REASON" ]; then
  floor_row macos-host/debug skip
else
  floor_row macos-host/debug "$(state_of "$MAC_RC")"
fi
floor_row ios-simulator-arm64/debug "$(state_of "$SIM_RC")"
floor_row ios-device-arm64/release "$(state_of "$DEV_RC")"
for mode in debug release; do
  if [ $mode = debug ]; then f_rc=$AND_DEBUG_RC; else f_rc=$AND_RELEASE_RC; fi
  floor_row "$AND_ARM/$mode" "$(state_of "$f_rc")"
  floor_row "$AND_X64/$mode" "$(state_of "$f_rc")"
  row --check min-version-floor --target "$AND_DEV/$mode" --status unmeasured \
    --summary 'no physical device' --command "$FLOOR_CMD" --notes "$NO_DEVICE"
done

# ---------------------------------------------------------------------------
# 7. Offline install from a clean state, and a wrong checksum fails the build
#    loudly — on the digest.
# ---------------------------------------------------------------------------
say "step 7: offline, and a flipped digest"
OFFLINE_CMD="$STAGE && flutter build … (the target's first build in a fresh staged copy; hooks.user_defines.wallet_core_flutter_native: {offline: true, vendored_dir: …, manifest: …}; eval_tool.dart offline-evidence before and after)"
# offline_row TARGET RC PRE POST: the target's offline row on its own.
offline_row() {
  offline_verdict "$2" "$3" "$4"
  row --check offline-install --target "$1" --status "$OFF_STATUS" --summary "$OFF_SUMMARY" \
    --command "$OFFLINE_CMD" --notes "$OFF_NOTES"
  [ "$OFF_STATUS" != fail ] || abort "$1: $OFF_SUMMARY"
}
offline_row ios-device-arm64/release "$DEV_RC" "$DEV_PRE" "$DEV_POST"
offline_row "$HOST_TARGET" "$HOST_RC" "$HOST_PRE" "$HOST_POST"

FLIP1="$WORK/flip-1.json"
FLIPPED="$WORK/eval_manifest.flipped.json"
tool flip "$MANIFEST" "$MAC_NAME" "$FLIP1"
tool flip "$FLIP1" "$SIM_NAME" "$WORK/flip-2.json"
tool flip "$WORK/flip-2.json" "$AND_ARM_NAME" "$FLIPPED"
NEG="$WORK/n"
tool stage "$APP" "$NEG" --manifest "$FLIPPED"

# negative LOG NAME CMD...: runs CMD in the flipped-digest copy and sets
# NEG_STATUS, NEG_SUMMARY, NEG_NOTES and NEG_CMD. `pass` only when the build
# failed *and* its output carries the hook's one-line verdict for NAME against
# the flipped digest (`eval_tool.dart classify-negative`): a build that failed
# for another reason — a vendored file missing, an offline cache miss — shows
# the same generic "could not be verified" headline and is not this check.
negative() {
  log=$1
  name=$2
  shift 2
  NEG_CMD="tool flip … && eval_tool.dart stage eval/option1/consumer $NEG --manifest $FLIPPED && cd $NEG && $* ($name's digest flipped in one hex character)"
  rc=0; attempt "$log" "$NEG" "$@" || rc=$?
  if [ $rc -eq 10 ]; then
    NEG_STATUS=unmeasured; NEG_SUMMARY='wrong-digest build refused here'; NEG_NOTES="$ORCH; log: $log"
    return
  fi
  if [ $rc -eq 0 ]; then
    NEG_STATUS=fail; NEG_SUMMARY='built with a wrong digest'; NEG_NOTES="log: $log"
    return
  fi
  verdict=$(tool classify-negative "$log" "$FLIPPED" "$name")
  kind=$(printf %s "$verdict" | cut -f1)
  evidence=$(printf %s "$verdict" | cut -f2-)
  if [ "$kind" = digest-mismatch ]; then
    NEG_STATUS=pass; NEG_SUMMARY='wrong digest: build failed on it, both digests shown'
    NEG_NOTES="the build output carries: $evidence; log: $log"
  else
    NEG_STATUS=fail; NEG_SUMMARY='wrong digest: build failed, but not on the digest'
    NEG_NOTES="no '$name: sha256 mismatch: expected <flipped digest>' line in the output; most telling line: ${evidence:-none}. log: $log"
  fi
}
negative "$LOGS/neg-host.log" "$MAC_NAME" flutter test test/bundled_library_test.dart $DEFINES
row --check offline-install --target macos-host/flutter-test-flipped-digest --status "$NEG_STATUS" \
  --summary "$NEG_SUMMARY" --command "$NEG_CMD" --notes "$NEG_NOTES"
[ "$NEG_STATUS" != fail ] || abort "macos-host/flutter-test-flipped-digest: $NEG_SUMMARY; see $LOGS/neg-host.log"

# The simulator's offline build and its wrong-digest build share one row:
# pass only if both pass.
offline_verdict "$SIM_RC" "$SIM_PRE" "$SIM_POST"
negative "$LOGS/neg-ios-sim.log" "$SIM_NAME" flutter build ios --simulator --debug $DEFINES
if [ "$OFF_STATUS" = fail ] || [ "$NEG_STATUS" = fail ]; then
  SIM_STATUS=fail
elif [ "$OFF_STATUS" = pass ] && [ "$NEG_STATUS" = pass ]; then
  SIM_STATUS=pass
else
  SIM_STATUS=unmeasured
fi
row --check offline-install --target ios-simulator-arm64/debug --status "$SIM_STATUS" \
  --summary "$OFF_SUMMARY; $NEG_SUMMARY" --command "$OFFLINE_CMD; then $NEG_CMD" \
  --notes "offline: $OFF_NOTES. wrong digest: $NEG_NOTES"
[ "$SIM_STATUS" != fail ] || abort "ios-simulator-arm64/debug: $OFF_SUMMARY; $NEG_SUMMARY"
# Android: the debug APK was the staged copy's first Android build, so it is
# the clean offline install of both ABIs (one hook run per ABI); the wrong
# digest is flipped on the arm64-v8a library. Release follows debug in the
# same copy, so its cache is warm by construction and it has no offline row.
offline_verdict "$AND_DEBUG_RC" "$AND_ARM_PRE" "$AND_ARM_POST"
A_OFF_STATUS=$OFF_STATUS
A_OFF_SUMMARY=$OFF_SUMMARY
A_OFF_NOTES=$OFF_NOTES
negative "$LOGS/neg-android.log" "$AND_ARM_NAME" flutter build apk --debug --target-platform $ANDROID_PLATFORMS $DEFINES
if [ "$A_OFF_STATUS" = fail ] || [ "$NEG_STATUS" = fail ]; then
  AND_STATUS=fail
elif [ "$A_OFF_STATUS" = pass ] && [ "$NEG_STATUS" = pass ]; then
  AND_STATUS=pass
else
  AND_STATUS=unmeasured
fi
row --check offline-install --target "$AND_ARM/debug" --status "$AND_STATUS" \
  --summary "$A_OFF_SUMMARY; $NEG_SUMMARY" --command "$OFFLINE_CMD; then $NEG_CMD" \
  --notes "offline: $A_OFF_NOTES. wrong digest: $NEG_NOTES"
[ "$AND_STATUS" != fail ] || abort "$AND_ARM/debug: $A_OFF_SUMMARY; $NEG_SUMMARY"
offline_row "$AND_X64/debug" "$AND_DEBUG_RC" "$AND_X64_PRE" "$AND_X64_POST"
for t in "$AND_ARM/release" "$AND_X64/release"; do
  row --check offline-install --target "$t" --status skip --summary 'warm cache by construction' \
    --command "$OFFLINE_CMD" \
    --notes "the clean offline install is each staged copy's first build of an artifact: the debug APK (${t%/release}/debug); the release APK follows it in the same copy"
done
for mode in debug release; do
  row --check offline-install --target "$AND_DEV/$mode" --status unmeasured --summary 'no physical device' \
    --command "$OFFLINE_CMD" --notes "$NO_DEVICE"
done

# ---------------------------------------------------------------------------
# 8. 16 KB alignment: our libraries as shipped and as packaged, each APK's
#    zip alignment, and the NDK's libc++_shared.so — the file
#    android_libcpp_shared 0.2.1 bundles, from the NDK the Flutter build uses
#    ($NDK, step 0).
# ---------------------------------------------------------------------------
say "step 8: alignment"
row --check alignment --target android/armeabi-v7a --status skip --summary 'not shipped (PRD §12.2 step 8)' \
  --command "dart run tools/packaging_eval/bin/alignment.dart --binary third_party/wcf-native-all/artifacts/android/armeabi-v7a/libTrustWalletCore.so --target android/armeabi-v7a" \
  --notes 'as_4.8.0_001 builds no armeabi-v7a library (16 KB alignment applies to the 64-bit ABIs)'
for abi in arm64-v8a x86_64; do
  harness alignment --binary "$VENDORED/android/$abi/libTrustWalletCore.so" --target "android/$abi"
done
say "NDK for libc++_shared.so: $NDK (Flutter $FLUTTER_VERSION default: ${FLUTTER_NDK:-unknown})"
for pair in arm64-v8a:aarch64-linux-android x86_64:x86_64-linux-android; do
  abi=${pair%%:*}
  triple=${pair#*:}
  harness alignment --binary "${NDK}toolchains/llvm/prebuilt/darwin-x86_64/sysroot/usr/lib/$triple/libc++_shared.so" \
    --target "ndk/$abi"
done
if [ $AND_RELEASE_RC -eq 0 ]; then
  harness alignment --binary "$AND_APPS/release/lib/arm64-v8a/libTrustWalletCore.so" --target "$AND_ARM/release"
  harness alignment --binary "$AND_APPS/release/lib/x86_64/libTrustWalletCore.so" --target "$AND_X64/release"
fi
for mode in debug release; do
  if [ $mode = debug ]; then a_rc=$AND_DEBUG_RC; else a_rc=$AND_RELEASE_RC; fi
  apk="$AND_APPS/app-$mode.apk"
  for t in "$AND_ARM/$mode" "$AND_X64/$mode"; do
    if [ $a_rc -eq 0 ]; then
      harness alignment --apk "$apk" --target "$t"
    else
      not_built alignment-apk "$t" "$a_rc" "dart run tools/packaging_eval/bin/alignment.dart --apk $apk --target $t"
    fi
  done
  row --check alignment-apk --target "$AND_DEV/$mode" --status unmeasured --summary 'no physical device' \
    --command "dart run tools/packaging_eval/bin/alignment.dart --apk $apk --target $AND_DEV/$mode" --notes "$NO_DEVICE"
done

# ---------------------------------------------------------------------------
# 9. A second plugin bundling libc++_shared.so.
# ---------------------------------------------------------------------------
say "step 9: libc++_shared conflict"
# What our library needs: the DT_NEEDED entries of the shipped .so (§5.1).
dt_needed() {
  "$READELF" -d "$1" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' | tr '\n' ' ' | sed 's/ $//'
}
DT_ARM=$(dt_needed "$VENDORED/android/arm64-v8a/libTrustWalletCore.so")
DT_X64=$(dt_needed "$VENDORED/android/x86_64/libTrustWalletCore.so")
# The second plugin: the harness fixture, copied out of the checkout and given
# the libc++_shared.so of an NDK other than the build's, so the two
# contributors differ by GNU build ID and the APK shows which one Gradle kept.
LIBCXX_NDK=''
for d in $(ls -d "$NDK_ROOT"/*/ | sort -V -r); do
  [ "$d" != "$NDK" ] || continue
  [ -f "${d}toolchains/llvm/prebuilt/darwin-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so" ] || continue
  LIBCXX_NDK=$d
  break
done
[ -n "$LIBCXX_NDK" ] || LIBCXX_NDK=$NDK
PLUGIN="$WORK/libcxx_plugin"
LX="$WORK/libcxx"
mkdir -p "$PLUGIN"
(cd tools/packaging_eval/fixtures/libcxx_plugin && tar cf - --exclude '*.so' .) | (cd "$PLUGIN" && tar xf -)
bash tools/packaging_eval/fixtures/libcxx_plugin/tool/materialize_libcxx.sh --ndk "${LIBCXX_NDK%/}" \
  --dest "$PLUGIN/android/src/main/jniLibs" --abis 'arm64-v8a x86_64' >"$LOGS/libcxx-materialize.log" 2>&1 ||
  abort "could not materialize the fixture's libc++_shared.so; see $LOGS/libcxx-materialize.log"
tool stage "$APP" "$LX" >/dev/null
(cd "$LX" && flutter pub add "libcxx_plugin:{\"path\":\"$PLUGIN\"}") >"$LOGS/libcxx-pub-add.log" 2>&1 ||
  abort "could not add the fixture plugin; see $LOGS/libcxx-pub-add.log"
LX_STAGE="dart run eval/option1/tool/eval_tool.dart stage eval/option1/consumer $LX && (copy tools/packaging_eval/fixtures/libcxx_plugin to $PLUGIN without .so) && tools/packaging_eval/fixtures/libcxx_plugin/tool/materialize_libcxx.sh --ndk ${LIBCXX_NDK%/} --dest $PLUGIN/android/src/main/jniLibs --abis 'arm64-v8a x86_64' && cd $LX && flutter pub add 'libcxx_plugin:{\"path\":\"$PLUGIN\"}'"
NDK_NAME=$(basename "$NDK")
LIBCXX_NDK_NAME=$(basename "$LIBCXX_NDK")

# libcxx_mode MODE: builds the consumer with the fixture plugin, reads which
# libc++_shared.so the APK holds per ABI, and (release, arm64-v8a) runs the
# probe on the emulator with both plugins present. Gradle's log names neither
# copy when the app's copy overrides a library module's — nothing for
# tools/packaging_eval's libcxx_conflict.dart (a log classifier) to read — so
# the row is the evaluation's, from the APK and the build's intermediates.
libcxx_mode() {
  l_mode=$1
  l_log="$LOGS/libcxx-$l_mode.log"
  l_entry=''
  [ "$l_mode" != release ] || l_entry='-t lib/probe_main.dart'
  l_cmd="$LX_STAGE && flutter build apk --$l_mode --target-platform $ANDROID_PLATFORMS $l_entry $DEFINES && unzip -l build/app/outputs/flutter-apk/app-$l_mode.apk && llvm-readelf -n lib/<abi>/libc++_shared.so"
  l_rc=0
  attempt "$l_log" "$LX" flutter build apk --$l_mode --target-platform $ANDROID_PLATFORMS $l_entry $DEFINES || l_rc=$?
  if [ $l_rc -ne 0 ]; then
    if [ $l_rc -eq 10 ]; then
      l_status=unmeasured; l_summary='refused here'; l_notes="$ORCH; log: $l_log"
    elif grep -q 'More than one file was found' "$l_log"; then
      l_status=fail; l_summary='duplicate-file failure'
      l_notes="$(grep -m1 'More than one file was found' "$l_log" | sed 's/^ *//'); log: $l_log"
    else
      l_status=fail; l_summary='build failed'; l_notes="log: $l_log"
    fi
    for t in "$AND_ARM/$l_mode" "$AND_X64/$l_mode"; do
      row --check libcxx-conflict --target "$t" --status "$l_status" --summary "$l_summary" \
        --command "$l_cmd" --notes "$l_notes"
    done
    return 0
  fi
  l_apk="$AND_APPS/libcxx-$l_mode.apk"
  l_dir="$AND_APPS/libcxx-$l_mode"
  cp "$LX/build/app/outputs/flutter-apk/app-$l_mode.apk" "$l_apk"
  rm -rf "$l_dir"
  mkdir -p "$l_dir"
  unzip -o -q "$l_apk" 'lib/*' -d "$l_dir"
  for abi in arm64-v8a x86_64; do
    if [ $abi = arm64-v8a ]; then
      triple=aarch64-linux-android; t="$AND_ARM/$l_mode"; dt=$DT_ARM
    else
      triple=x86_64-linux-android; t="$AND_X64/$l_mode"; dt=$DT_X64
    fi
    copies=$(unzip -l "$l_apk" | awk -v p="lib/$abi/libc++_shared.so" '$4 == p' | wc -l | tr -d ' ')
    packaged_id=''
    [ ! -f "$l_dir/lib/$abi/libc++_shared.so" ] || packaged_id=$(build_id "$l_dir/lib/$abi/libc++_shared.so")
    asset_id=$(build_id "${NDK}toolchains/llvm/prebuilt/darwin-x86_64/sysroot/usr/lib/$triple/libc++_shared.so")
    plugin_id=$(build_id "$PLUGIN/android/src/main/jniLibs/$abi/libc++_shared.so")
    from_plugin=$(find "$LX/build/libcxx_plugin" -path "*/library_jni/*/$abi/libc++_shared.so" 2>/dev/null | head -1)
    from_asset=$(find "$LX/build/app/intermediates/flutter" -path "*/native_assets/*/$abi/libc++_shared.so" 2>/dev/null | head -1)
    if [ -n "$asset_id" ] && [ "$asset_id" = "$plugin_id" ]; then
      kept="unidentified (both NDKs ship build ID $asset_id)"
    elif [ "$packaged_id" = "$asset_id" ]; then
      kept="android_libcpp_shared's copy (NDK $NDK_NAME)"
    elif [ "$packaged_id" = "$plugin_id" ]; then
      kept="the fixture plugin's copy (NDK $LIBCXX_NDK_NAME)"
    else
      kept="unidentified (build ID ${packaged_id:-none})"
    fi
    l_notes="APK lib/$abi/libc++_shared.so: $copies entr$( [ "$copies" = 1 ] && echo y || echo ies), build ID ${packaged_id:-none} = $kept. Contributors that reached the build: android_libcpp_shared's code asset (NDK $NDK_NAME, build ID $asset_id) at ${from_asset:-NOT FOUND}; the fixture plugin's jniLibs (NDK $LIBCXX_NDK_NAME, build ID $plugin_id) at ${from_plugin:-NOT FOUND}. The Gradle log names neither (no duplicate error, no pickFirst). Our libTrustWalletCore.so DT_NEEDED: $dt (no libc++_shared.so). log: $l_log"
    if [ -z "$from_plugin" ] || [ -z "$from_asset" ]; then
      row --check libcxx-conflict --target "$t" --status unmeasured --summary 'two copies did not reach the build' \
        --command "$l_cmd" --notes "$l_notes"
      continue
    fi
    if [ "$copies" != 1 ]; then
      row --check libcxx-conflict --target "$t" --status fail --summary "$copies copies in the APK" \
        --command "$l_cmd" --notes "$l_notes"
      continue
    fi
    l_summary="one copy, no Gradle message: $kept kept"
    if [ $abi = x86_64 ]; then
      row --check libcxx-conflict --target "$t" --status pass --summary "$l_summary" \
        --command "$l_cmd" --notes "$l_notes. Not run: $NO_X64"
    elif [ "$l_mode" = debug ]; then
      row --check libcxx-conflict --target "$t" --status pass --summary "$l_summary" \
        --command "$l_cmd" --notes "$l_notes. Run on the emulator in the release column"
    elif [ $EMU_OK -ne 1 ]; then
      row --check libcxx-conflict --target "$t" --status unmeasured --summary "$l_summary; not run" \
        --command "$l_cmd" --notes "$l_notes. No arm64-v8a emulator running: $EMU_NOTE"
    else
      android_probe "$EMU_ID" "$l_apk" "$LOGS/run-libcxx-release.log"
      l_cmd="$l_cmd && adb -s $EMU_ID install -r … && adb -s $EMU_ID shell am start -W -n $AND_PACKAGE/.MainActivity && adb -s $EMU_ID logcat -d -s flutter:I"
      case $PROBE_LINE in
        'WCF_PROBE PASS'*)
          row --check libcxx-conflict --target "$t" --status pass --summary "$l_summary; probe PASS" \
            --command "$l_cmd" --notes "$l_notes. Run with both plugins: $PROBE_LINE; am start -W: $LAUNCH"
          ;;
        *)
          row --check libcxx-conflict --target "$t" --status fail --summary "$l_summary; probe failed" \
            --command "$l_cmd" --notes "$l_notes. Run with both plugins: ${PROBE_LINE:-no WCF_PROBE line within 60 s}; am start -W: ${LAUNCH:-none}; log: $LOGS/run-libcxx-release.log"
          ;;
      esac
    fi
  done
}
libcxx_mode debug
libcxx_mode release
for mode in debug release; do
  row --check libcxx-conflict --target "$AND_DEV/$mode" --status unmeasured --summary 'no physical device' \
    --command "$LX_STAGE && flutter build apk --$mode --target-platform $ANDROID_PLATFORMS $DEFINES" --notes "$NO_DEVICE"
done


# ---------------------------------------------------------------------------
# 10. iOS: deployment target, visibility, signing, privacy APIs, duplicates,
#     archive link.
# ---------------------------------------------------------------------------
say "step 10: iOS archive"
for slice in ios/arm64 ios-simulator/arm64_x86_64 macos/arm64_x86_64; do
  harness ios_archive --binary "$VENDORED/$slice/libTrustWalletCore.dylib" --target "$slice"
done
if [ $DEV_RC -eq 0 ]; then
  harness ios_archive --binary "$DEV_FW" --target ios-device-arm64/release
else
  not_built ios-archive ios-device-arm64/release "$DEV_RC" \
    "dart run tools/packaging_eval/bin/ios_archive.dart --binary $DEV_FW --target ios-device-arm64/release"
fi
if [ $SIM_RC -eq 0 ]; then
  harness ios_archive --binary "$SIM_FW" --target ios-simulator-arm64/debug
else
  not_built ios-archive ios-simulator-arm64/debug "$SIM_RC" \
    "dart run tools/packaging_eval/bin/ios_archive.dart --binary $SIM_FW --target ios-simulator-arm64/debug"
fi
[ $HOST_RC -eq 0 ] && harness ios_archive --binary "$HOST_LIB" --target "$HOST_TARGET"
# Duplicate symbols across every framework the archived app embeds (the same
# scope as Option 2's scan), not TrustWalletCore and Flutter only.
if [ $DEV_RC -eq 0 ]; then
  set --
  while IFS= read -r binary; do
    [ -n "$binary" ] && set -- "$@" --duplicate-scan "$binary"
  done <<EOF
$(tool embedded-binaries "$DEV_APP")
EOF
  [ $# -ge 4 ] || abort "the archived app embeds fewer than two libraries: $*"
  say "duplicate scan over $(($# / 2)) embedded libraries"
  harness ios_archive "$@" --target ios-device-arm64/release
else
  not_built ios-duplicate-symbols ios-device-arm64/release "$DEV_RC" \
    "dart run tools/packaging_eval/bin/ios_archive.dart --duplicate-scan <each Frameworks/*.framework binary of $DEV_APP> --target ios-device-arm64/release"
fi
if [ $DEV_RC -eq 0 ] && [ -d "$ARCHIVE" ]; then
  contents=$(cd "$(dirname "$DEV_FW")" && ls -A | tr '\n' ' ')
  privacy='no PrivacyInfo.xcprivacy in the framework'
  [ -e "$(dirname "$DEV_FW")/PrivacyInfo.xcprivacy" ] && privacy='PrivacyInfo.xcprivacy present in the framework'
  row --check ios-archive-link --target ios-device-arm64/release --status pass --summary 'archive links' \
    --command "$STAGE && flutter build ipa --release --no-codesign $DEFINES" \
    --notes "TrustWalletCore.framework holds: $contents; $privacy"
else
  not_built ios-archive-link ios-device-arm64/release "$DEV_RC" \
    "$STAGE && flutter build ipa --release --no-codesign $DEFINES"
fi

# ---------------------------------------------------------------------------
# 11. Consumed as hosted packages, never by path.
# ---------------------------------------------------------------------------
say "step 11: hosted consumption"
harness consumer_gen --out-dir "$WORK/consumer-gen"

render
pristine_check "$APP" 'after the run'
echo
cat "$TABLE"
echo
echo "results -> $RESULTS"
echo "table   -> $TABLE (embedded in $DOC §2.1)"
echo "logs    -> $LOGS"
