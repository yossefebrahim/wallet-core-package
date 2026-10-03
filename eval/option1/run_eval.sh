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
# simulator, no Android artifact, a build that did not succeed in this run —
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
NOART='waiting-for-artifacts: no Android artifact exists (compat_manifest.json TBD-T1.2; DECISION-9 §4 CI build); T1.8b'

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
# /tmp/wcf-o1-<pid> — outside $TMPDIR on purpose, because the default macOS
# $TMPDIR (/var/folders/…/T/, resolved under /private/var) is itself too deep
# for the install name Flutter writes; it is created and removed here.
HOST_TMPDIR="$WORK/h"
SHORT_ROOT="/tmp/wcf-o1-$$"
SHORT_DIR="$SHORT_ROOT/h"
INSTALL_NAME_LIMIT=87 # macOS arm64 slice: 56 spare header bytes (otool -l)
ANDROID_TARGETS="android-emulator-x86_64/debug android-emulator-x86_64/release android-device-arm64-v8a/debug android-device-arm64-v8a/release"
# No Android build is attempted (no artifact): every Android measurement is
# `unmeasured`, never read from a file an earlier run left behind.
ANDROID_RC=20

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

for t in $ANDROID_TARGETS; do
  mode=${t#*/}
  row --check consumer-build --target "$t" --status unmeasured --summary 'no artifact' \
    --command "$STAGE && flutter build apk --$mode $DEFINES" --notes "$NOART"
done

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
      --notes "Flutter's host test runner sets the dylib's install name to its absolute path; our Mach-O header has 56 spare bytes in the macOS arm64 slice (otool -l), so any path over $INSTALL_NAME_LIMIT characters fails, and this one is $length. The artifact build must link with -Wl,-headerpad_max_install_names (T1.2). log: $log"
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
for t in $ANDROID_TARGETS; do
  mode=${t#*/}
  for c in run-on-target symbols-runtime-lookup; do
    row --check $c --target "$t" --status unmeasured --summary 'no artifact' \
      --command "$STAGE && flutter run --$mode -d <device-id> -t lib/probe_main.dart $DEFINES  (look for WCF_PROBE PASS)" \
      --notes "$NOART"
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
for t in android-emulator-x86_64/release android-device-arm64-v8a/release; do
  row --check release-launch-and-sign --target "$t" --status unmeasured --summary 'no artifact' \
    --command "$STAGE && flutter run --release -d <device-id> -t lib/probe_main.dart $DEFINES" \
    --notes "$NOART"
done

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
for abi in arm64-v8a armeabi-v7a x86_64; do
  so="$VENDORED/android/$abi/libTrustWalletCore.so"
  harness symbols --artifact "$so" --format elf --target "android/$abi"
  harness size --artifact "$so" --target "android/$abi"
done
# The binary inside each built app (`packaged`, tool/verdicts.sh), in that
# app's column — only from a build that succeeded in this run.
APK_LIBS="$BUILD/build/app/intermediates/merged_native_libs/release/mergeReleaseNativeLibs/out/lib"
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
packaged "$ANDROID_RC" "$APK_LIBS/x86_64/libTrustWalletCore.so" android-emulator-x86_64/release elf
packaged "$ANDROID_RC" "$APK_LIBS/arm64-v8a/libTrustWalletCore.so" android-device-arm64-v8a/release elf

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
    pass) row --check min-version-floor --target "$target" --status pass \
            --summary "builds on $FLUTTER_VERSION (only version tried)" \
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
for t in $ANDROID_TARGETS; do
  floor_row "$t" 'no artifact'
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
tool flip "$FLIP1" "$SIM_NAME" "$FLIPPED"
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
for t in $ANDROID_TARGETS; do
  row --check offline-install --target "$t" --status unmeasured --summary 'no artifact' \
    --command 'as for iOS: flutter build apk with offline: true, then with a flipped digest' \
    --notes "$NOART"
done

# ---------------------------------------------------------------------------
# 8. 16 KB alignment. Our .so does not exist. The NDK's libc++_shared.so is
#    the file android_libcpp_shared bundles: 0.2.1 takes it from the NDK the
#    Flutter build uses, falling back to other installs. Measured here on the
#    installed Flutter's default NDK (read from its Gradle plugin), else on the
#    newest NDK installed.
# ---------------------------------------------------------------------------
say "step 8: alignment"
for abi in arm64-v8a armeabi-v7a x86_64; do
  harness alignment --binary "$VENDORED/android/$abi/libTrustWalletCore.so" --target "android/$abi"
done
NDK_ROOT="${ANDROID_HOME:-$HOME/Library/Android/sdk}/ndk"
if [ -d "$NDK_ROOT" ]; then
  FLUTTER_NDK=$(grep -ho 'val ndkVersion: String = "[^"]*"' \
    "$FLUTTER_ROOT_DIR/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt" 2>/dev/null |
    sed 's/.*= "//; s/"$//' || true)
  if [ -n "$FLUTTER_NDK" ] && [ -d "$NDK_ROOT/$FLUTTER_NDK" ]; then
    NDK="$NDK_ROOT/$FLUTTER_NDK/"
  else
    NDK=$(ls -d "$NDK_ROOT"/*/ | sort -V | tail -1)
  fi
  say "NDK for libc++_shared.so: $NDK (Flutter $FLUTTER_VERSION default: ${FLUTTER_NDK:-unknown})"
  for pair in arm64-v8a:aarch64-linux-android x86_64:x86_64-linux-android; do
    abi=${pair%%:*}
    triple=${pair#*:}
    harness alignment --binary "${NDK}toolchains/llvm/prebuilt/darwin-x86_64/sysroot/usr/lib/$triple/libc++_shared.so" \
      --target "ndk/$abi"
  done
fi
for t in $ANDROID_TARGETS; do
  mode=${t#*/}
  not_built alignment-apk "$t" "$ANDROID_RC" \
    "dart run tools/packaging_eval/bin/alignment.dart --apk $BUILD/build/app/outputs/flutter-apk/app-$mode.apk --target $t"
done

# ---------------------------------------------------------------------------
# 9. A second plugin bundling libc++_shared.so.
# ---------------------------------------------------------------------------
say "step 9: libc++_shared conflict"
for t in $ANDROID_TARGETS; do
  harness libcxx_conflict --target "$t" --gradle-output "$WORK/gradle-$(echo "$t" | tr / -).log"
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
