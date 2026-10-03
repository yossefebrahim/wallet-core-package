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
    -h|--help) sed -n '2,48p' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 64 ;;
  esac
done

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
NDK_HINT='$ANDROID_NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin'
WAITING_ANDROID="waiting-for-artifacts: no Android artifact exists (the eval manifest's android rows are TBD-T1.2; T1.2's Android build produces them, T1.9b runs this)"
ORCHESTRATOR="orchestrator-run: --no-xcode (this session's sandbox refuses Xcode's DerivedData); run eval/option2/run_eval.sh without it"
IOS_APP_TARGETS=(ios-simulator-arm64/debug ios-simulator-arm64/release ios-device-arm64/debug ios-device-arm64/release)
ANDROID_APP_TARGETS=(android-emulator-x86_64/debug android-emulator-x86_64/release android-device-arm64-v8a/debug android-device-arm64-v8a/release)

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

# third_party/ is untrusted: every file used below is verified against the
# evaluation manifest by the package's own fetch tool before anything reads it.
# Into a cache of its own: the builds' $CACHE must start absent, or the
# measured pod install would read a cache this script warmed instead of the
# vendored set.
dart run packages/wallet_core_flutter_native/tool/fetch_artifacts.dart \
  --manifest "$MANIFEST" --cache-dir "$PREFLIGHT_CACHE" --vendored "$VENDORED" --offline \
  --only "$DEVICE_ROW" --only "$SIM_ROW"

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
# option named --release"); an integration test runs in release mode only
# through `flutter drive` with the integration_test driver.
DRIVE_CMD="flutter drive --driver=test_driver/integration_test.dart --target=integration_test/symbol_lookup_test.dart ${IDENTITY_DEFINES[*]}"

# Builds recorded `skip`, one "<target> TAB <summary> TAB <notes>" line each.
# Every row that needs the build's output inherits the skip and its reason
# instead of being attempted (inherit_skip).
TAB="$(printf '\t')"
SKIPPED="$OUT/skipped-builds.tsv"
: > "$SKIPPED"
skipped_build() { grep -q "^$1$TAB" "$SKIPPED"; }
# The on-target command for a "<device>/<debug|release>" target, as text.
on_target_cmd() { # target device-id
  if [ "${1##*/}" = release ]; then echo "$DRIVE_CMD -d $2 --release"; else echo "$TEST_CMD -d $2"; fi
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
# The first pod install above started without $CACHE; with --offline and the
# eval manifest's never-resolving retention URL, --vendored is the only
# source it had (step 7).
CACHE_FILLED="$(cache_files "$CACHE")"
for t in "${ANDROID_APP_TARGETS[@]}"; do
  unmeasured consumer-build "$t" \
    "cd \"\$APP\" && WCF_MANIFEST=<manifest with android rows> flutter build apk --${t##*/}" \
    "$WAITING_ANDROID"
done

# ---------------------------------------------------------------------------
# step 2 — run on target; step 4 (runtime half) — full symbol lookup
# ---------------------------------------------------------------------------

run_test() { # target slug device debug|release
  local target="$1" slug="$2" device="$3" mode="$4"
  local log="$LOGS/test-$slug.log"
  local cmd
  if [ "$mode" = release ]; then
    cmd=(flutter drive --driver=test_driver/integration_test.dart
      --target=integration_test/symbol_lookup_test.dart "${IDENTITY_DEFINES[@]}"
      -d "$device" --release)
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
  say "step 2: integration test on $device ($target)"
  local status=pass
  (cd "$APP" && "${cmd[@]}") > "$log" 2>&1 || status=fail
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
for t in "${ANDROID_APP_TARGETS[@]}"; do
  unmeasured run-on-target "$t" "$(on_target_cmd "$t" '<emulator or device id>')" "$WAITING_ANDROID"
  unmeasured symbols-runtime-lookup "$t" "$(on_target_cmd "$t" '<emulator or device id>')" "$WAITING_ANDROID"
done

# ---------------------------------------------------------------------------
# step 3 — release build launches and signs
# ---------------------------------------------------------------------------

unmeasured release-launch-and-sign ios-device-arm64/release \
  "flutter build ipa (signed) && WCF_IOS_DEVICE=<id> eval/option2/run_eval.sh" \
  "device: needs a signing identity and a physical iPhone; the release archive is built --no-codesign here (T1.9b)"
for t in android-emulator-x86_64/release android-device-arm64-v8a/release; do
  unmeasured release-launch-and-sign "$t" "flutter run --release -d <id> in \"\$APP\"" "$WAITING_ANDROID"
done

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
for abi in arm64-v8a armeabi-v7a x86_64; do
  unmeasured symbols "android/$abi" \
    "unzip -o \"\$APP/build/app/outputs/flutter-apk/app-release.apk\" 'lib/*' -d \"\$OUT/apk\" && dart run tools/packaging_eval/bin/symbols.dart --artifact \"\$OUT/apk/lib/$abi/libTrustWalletCore.so\" --format elf --nm \"$NDK_HINT/llvm-nm\" --target android/$abi" \
    "$WAITING_ANDROID"
done

# ---------------------------------------------------------------------------
# step 5 — sizes, and the app-size delta against a baseline app
# ---------------------------------------------------------------------------

say "step 5: sizes"
harness size --artifact "$XCF_ROOT/$XCF_DEVICE_BIN" --target ios/arm64
harness size --artifact "$XCF_ROOT/$XCF_SIM_BIN" --target ios-simulator/arm64_x86_64
if [ "$NO_XCODE" = 0 ]; then
  say "step 5: baseline app (no SDK) for the app-size delta"
  (cd "$OUT" && flutter create --no-pub --platforms=ios --org dev.wcf.eval \
      --project-name wcf_eval_baseline baseline) > "$LOGS/baseline-create.log" 2>&1
  # The consumer has integration_test as a dev dependency, and dev-dependency
  # plugins are built into debug apps; the baseline gets the same.
  (cd "$BASELINE" && flutter pub add 'dev:integration_test:{"sdk":"flutter"}') \
    > "$LOGS/baseline-pub.log" 2>&1
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
for abi in arm64-v8a armeabi-v7a x86_64; do
  unmeasured size "android/$abi" \
    "dart run tools/packaging_eval/bin/size.dart --artifact \"\$OUT/apk/lib/$abi/libTrustWalletCore.so\" --target android/$abi" \
    "$WAITING_ANDROID"
done
for t in android-emulator-x86_64/release android-device-arm64-v8a/release; do
  unmeasured app-size-delta "$t" \
    "dart run tools/packaging_eval/bin/size.dart --baseline-app \"\$OUT/baseline/build/app/outputs/flutter-apk/app-release.apk\" --sdk-app \"\$APP/build/app/outputs/flutter-apk/app-release.apk\" --target $t" \
    "$WAITING_ANDROID"
done

# ---------------------------------------------------------------------------
# step 6 — minimum Flutter/Dart
# ---------------------------------------------------------------------------

say "step 6: toolchain and declared constraints"
harness min_version --target host/toolchain
FLOOR_NOTE="one SDK per run: this run used Flutter $FLUTTER_VERSION / Dart $DART_VERSION with $XCODE_VERSION (iOS deployment ${IOS_SDK_MIN}–$IOS_SDK_MAX). With this Xcode, a Flutter whose app template targets below iOS $IOS_SDK_MIN builds no iOS app at all, with or without this package (recorded in DECISION-2-option2.md §4). Documentation: the ffiPlugin platform key exists since Flutter 3.0 (plugin_ffi template); the package's declared floor is the Dart code's, not the packaging's."
for t in ios-simulator-arm64/debug ios-device-arm64/release android-emulator-x86_64/release; do
  unmeasured min-version-floor "$t" \
    "for each candidate SDK, oldest first: <sdk>/bin/flutter build ios --simulator --debug (and apk --release) in \"\$APP\"; record the oldest that builds" \
    "$FLOOR_NOTE"
done

# ---------------------------------------------------------------------------
# step 7 — offline install; a wrong checksum fails loudly
# ---------------------------------------------------------------------------

offline_target=ios-simulator-arm64/debug
# The measured builds' install: pass only when pub get needed no network and
# the first pod install filled the absent $CACHE from --vendored. Whether a
# socket was opened is observed separately below, not inferred from --offline.
offline_status=pass
offline_notes="pub get --offline succeeded; the first pod install started without an artifact cache and, with --offline and a retention URL under .invalid, filled it from --vendored ($CACHE_FILLED of 2 libraries). No socket was observed here; see the outbound-network-denied pod install in this cell"
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
say "step 7: the package's own shipped manifest (all TBD-) must fail pod install"
log="$LOGS/negative-root-manifest.log"
if (unset WCF_MANIFEST; cd "$APP/ios" && pod install) > "$log" 2>&1; then
  row --check offline-install --target "$offline_target" --status fail \
    --command "cd \"\$APP/ios\" && pod install (no WCF_MANIFEST: the shipped assets/compat_manifest.json)" \
    --value "log=$log" --notes "pod install SUCCEEDED against a placeholder manifest"
  finish 1
fi
if grep -q 'cannot be fetched from' "$log"; then
  row --check offline-install --target "$offline_target" --status pass \
    --command "cd \"\$APP/ios\" && pod install (no WCF_MANIFEST: the shipped assets/compat_manifest.json)" \
    --value "log=$log" \
    --summary "shipped manifest: pod install fails, fetch tool exit 2, blockers named" \
    --notes "$(grep -m1 'blockers' "$log" | sed 's|.*/assets/|assets/|')"
else
  row --check offline-install --target "$offline_target" --status fail \
    --command "cd \"\$APP/ios\" && pod install (shipped manifest)" --value "log=$log" \
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

for t in android-emulator-x86_64/debug android-device-arm64-v8a/release; do
  unmeasured offline-install "$t" \
    "WCF_OFFLINE=1 WCF_VENDORED_DIR=<dir> flutter build apk; then WCF_MANIFEST=<flipped> flutter build apk must fail in wcfPrepare<Variant>JniLibs" \
    "$WAITING_ANDROID"
done

# ---------------------------------------------------------------------------
# step 8 — 16 KB alignment (Android only)
# ---------------------------------------------------------------------------

for abi in arm64-v8a armeabi-v7a x86_64; do
  unmeasured alignment "android/$abi" \
    "dart run tools/packaging_eval/bin/alignment.dart --binary \"\$OUT/apk/lib/$abi/libTrustWalletCore.so\" --target android/$abi" \
    "$WAITING_ANDROID"
done
for t in android-emulator-x86_64/release android-device-arm64-v8a/release; do
  unmeasured alignment-apk "$t" \
    "dart run tools/packaging_eval/bin/alignment.dart --apk \"\$APP/build/app/outputs/flutter-apk/app-release.apk\" --target $t" \
    "$WAITING_ANDROID"
done

# ---------------------------------------------------------------------------
# step 9 — a second plugin bundling libc++_shared.so (Android only)
# ---------------------------------------------------------------------------

for t in "${ANDROID_APP_TARGETS[@]}"; do
  harness libcxx_conflict --target "$t" \
    --build-command "add tools/packaging_eval/fixtures/libcxx_plugin by path to \"\$APP\", then flutter build apk --${t##*/} 2>&1 | tee \"\$OUT/gradle.log\""
done

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
