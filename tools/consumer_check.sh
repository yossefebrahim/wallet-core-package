#!/usr/bin/env bash
#
# consumer_check.sh — PRD §12.2 step 11, T1.16: consume the three packages the
# way a real app will. A fresh `flutter create` app; the packages published to
# a local package repository; the SDK added as a hosted dependency, never by
# path; debug and release builds for Android and iOS; the M0 flow run on a
# device. No manual native edits.
#
# Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
# Not affiliated with or endorsed by Trust Wallet.
#
# STATUS (T1.16b). All stages work today. The native library is downloaded by
# a build hook from the published GitHub release and its sha256 is verified.
#
# Everything is written under the work directory, outside the repository:
# $WCF_CONSUMER_CHECK_DIR, default $TMPDIR/wcf-consumer-check. The package repository
# listens on 127.0.0.1 only. The build needs network for the build hook's first fetch of
# the native library from the published release native-4.8.0-001 (sha256-verified), for
# pub.dev transitive dependencies, and for CocoaPods. Stage results are kept in
# <work dir>/status/ for `report`.
#
# Bash 3.2 (macOS /bin/bash): no associative arrays, no mapfile, no ${x,,}.
set -euo pipefail

STAGES="create_consumer publish_locally add_dependency build_debug_android \
build_release_android build_debug_ios build_release_ios run_m0_flow report"

usage() {
  cat <<USAGE
Usage: tools/consumer_check.sh [--stage NAME] [--android-device DEVICE_ID] [--ios-device UDID]

Runs PRD §12.2 step 11 against a fresh consumer app. With no --stage, runs
every stage in order (each in its own process), stops at the first failure,
and prints the report. With --stage, runs that one stage alone.

Stages, in order:
  create_consumer        flutter create, under an empty HOME (no team id)
  publish_locally        publish the three packages to a loopback package
                         repository and fetch them back over HTTP
  add_dependency         add wallet_core_flutter as a hosted dependency
  build_debug_android    flutter build apk --debug --target-platform android-arm64,android-x64
  build_release_android  flutter build apk --release --target-platform android-arm64,android-x64
  build_debug_ios        flutter build ios --simulator --debug
  build_release_ios      flutter build ios --release --no-codesign
  run_m0_flow            run the M0 flow on devices (needs booted emulator + simulator, and adb)
  report                 summarize the recorded stage results

Exit status: 0 passed; 1 failed;
64 usage error.

Arguments:
  --android-device ID    Device ID for Android (default: emulator-5554)
  --ios-device UDID      UDID for iOS (default: first booted simulator)

Work directory: \$WCF_CONSUMER_CHECK_DIR, default \$TMPDIR/wcf-consumer-check
(must be outside the repository).
USAGE
}

usage_error() {
  echo "consumer_check: $*" >&2
  usage >&2
  exit 64
}

STAGE=""
ANDROID_DEVICE="emulator-5554"
IOS_DEVICE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --stage)
      [ $# -ge 2 ] || usage_error "--stage needs a stage name"
      STAGE="$2"
      shift 2
      ;;
    --android-device)
      [ $# -ge 2 ] || usage_error "--android-device needs a device id"
      ANDROID_DEVICE="$2"
      shift 2
      ;;
    --ios-device)
      [ $# -ge 2 ] || usage_error "--ios-device needs a device id"
      IOS_DEVICE="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage_error "unknown argument: $1"
      ;;
  esac
done

if [ -n "$STAGE" ]; then
  case " $STAGES " in
    *" $STAGE "*) ;;
    *) usage_error "unknown stage: $STAGE" ;;
  esac
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
SCRIPT_PATH="$REPO_ROOT/tools/consumer_check.sh"
tmp_base="${TMPDIR:-/tmp}"
WORK_DIR="${WCF_CONSUMER_CHECK_DIR:-${tmp_base%/}/wcf-consumer-check}"

# The work directory must not be inside the checkout: a consumer app or a
# staged package there would be picked up by the workspace and by git.
mkdir -p "$(dirname "$WORK_DIR")"
work_parent="$(cd "$(dirname "$WORK_DIR")" && pwd -P)"
WORK_DIR="$work_parent/$(basename "$WORK_DIR")"
case "$WORK_DIR/" in
  "$REPO_ROOT"/*) usage_error "the work directory must be outside the repository: $WORK_DIR" ;;
esac

CONSUMER_DIR="$WORK_DIR/consumer"
PUB_REPOSITORY_DIR="$WORK_DIR/pub-repository"
STATUS_DIR="$WORK_DIR/status"

# --- Stage bookkeeping. Every stage runs as the only stage of its process, so
# --- these may exit.

with_timeout() {
  local timeout="$1"
  shift
  set -m
  "$@" &
  local pid=$!
  set +m
  trap "kill -TERM -- -$pid 2>/dev/null; sleep 1; kill -9 -- -$pid 2>/dev/null; exit 130" INT TERM HUP
  local elapsed=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$elapsed" -ge "$timeout" ]; then
      kill -9 -- "-$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      trap - INT TERM HUP
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  wait "$pid"
  local rc=$?
  trap - INT TERM HUP
  return $rc
}

record() {
  mkdir -p "$STATUS_DIR"
  printf '%s\n' "$2" >"$STATUS_DIR/$1"
}

pass() {
  echo "$1: OK — $2"
  record "$1" "ok — $2"
}

fail() {
  local stage="$1"
  shift
  echo "$stage: FAILED — $*" >&2
  record "$stage" "failed — $*"
  exit 1
}


require() {
  command -v "$2" >/dev/null 2>&1 || fail "$1" "$2 is not on PATH"
}

# --- Stages ------------------------------------------------------------------

# A fresh app, exactly as `flutter create` writes it. HOME points at an empty
# directory for the call, so flutter finds no Apple signing identity and writes
# no DEVELOPMENT_TEAM — a personal identifier (same reason as
# eval/option1/tool/create_consumer.sh). --no-pub: dependencies are
# add_dependency's business.
create_consumer() {
  require create_consumer flutter
  mkdir -p "$WORK_DIR"
  rm -rf "$CONSUMER_DIR"
  local empty_home
  empty_home="$(mktemp -d "${tmp_base%/}/wcf-consumer-home.XXXXXX")"
  if ! HOME="$empty_home" flutter create \
    --project-name wcf_consumer_check \
    --org dev.wcf.consumer \
    --platforms android,ios \
    --no-pub \
    "$CONSUMER_DIR"; then
    rm -rf "$empty_home"
    fail create_consumer "flutter create failed"
  fi
  rm -rf "$empty_home"
  if grep -rq 'DEVELOPMENT_TEAM' "$CONSUMER_DIR/ios"; then
    fail create_consumer "a DEVELOPMENT_TEAM was written despite the empty HOME"
  fi
  if grep -q 'wallet_core_flutter' "$CONSUMER_DIR/pubspec.yaml"; then
    fail create_consumer "the fresh app already names wallet_core_flutter"
  fi
  pass create_consumer "$CONSUMER_DIR (android, ios; no DEVELOPMENT_TEAM)"
}

# The three packages, staged and served by the T1.19 loopback repository
# (tools/consumer_check/publish_locally.dart). The keep-alive server writes its
# port to pub-repository/port and its pid to $WORK_DIR/pub_server.pid. If these
# files exist and the process matches publish_locally.dart, the server is reused.
# The server is stopped by run_all's EXIT trap, or manually after a standalone
# stage with: kill "$(cat <work-dir>/pub_server.pid)"
publish_locally() {
  require publish_locally dart
  mkdir -p "$WORK_DIR"
  if [ ! -f "$REPO_ROOT/.dart_tool/package_config.json" ]; then
    fail publish_locally "no workspace package config; run \`melos bootstrap\` first"
  fi
  
  local launcher=""
  if [ -f "$WORK_DIR/pub_server.pid" ] && kill -0 "$(cat "$WORK_DIR/pub_server.pid")" 2>/dev/null; then
    local pid
    pid="$(cat "$WORK_DIR/pub_server.pid")"
    if ps -p "$pid" -o command= | grep -q publish_locally.dart; then
      echo "publish_locally: reusing existing server at $(cat "$PUB_REPOSITORY_DIR/port")"
    else
      rm -f "$PUB_REPOSITORY_DIR/port" "$WORK_DIR/pub_server.pid"
      ( cd "$REPO_ROOT/tools/consumer_check" && exec nohup dart run publish_locally.dart --staging-dir "$PUB_REPOSITORY_DIR" --keep-alive --pid-file "$WORK_DIR/pub_server.pid" ) </dev/null >"$WORK_DIR/publish_locally.log" 2>&1 &
      launcher=$!
    fi
  else
    rm -f "$PUB_REPOSITORY_DIR/port" "$WORK_DIR/pub_server.pid"
    ( cd "$REPO_ROOT/tools/consumer_check" && exec nohup dart run publish_locally.dart --staging-dir "$PUB_REPOSITORY_DIR" --keep-alive --pid-file "$WORK_DIR/pub_server.pid" ) </dev/null >"$WORK_DIR/publish_locally.log" 2>&1 &
    launcher=$!
  fi
  
  local attempts=0
  while [ ! -f "$WORK_DIR/pub_server.pid" ] || [ ! -f "$PUB_REPOSITORY_DIR/port" ]; do
    if [ -n "$launcher" ]; then
      if grep -q 'publish_locally: FAIL' "$WORK_DIR/publish_locally.log" 2>/dev/null || ! kill -0 "$launcher" 2>/dev/null; then
        cat "$WORK_DIR/publish_locally.log" || true
        fail publish_locally "$(grep 'publish_locally: FAIL' "$WORK_DIR/publish_locally.log" | head -3 | tr '\n' ' ' || echo 'publish_locally exited before serving')"
      fi
    fi
    sleep 1
    attempts=$((attempts + 1))
    if [ "$attempts" -gt 30 ]; then
      cat "$WORK_DIR/publish_locally.log" || true
      fail publish_locally "server failed to start"
    fi
  done

  local pid
  pid="$(cat "$WORK_DIR/pub_server.pid")"

  if ! kill -0 "$pid" 2>/dev/null; then
    cat "$WORK_DIR/publish_locally.log" || true
    fail publish_locally "server died"
  fi

  if [ -z "$launcher" ]; then
    pass publish_locally "reused existing server on 127.0.0.1:$(cat "$PUB_REPOSITORY_DIR/port") (not re-verified)"
  else
    pass publish_locally "3 packages served on loopback and fetched back intact; staged under $PUB_REPOSITORY_DIR"
  fi
}

add_dependency() {
  if [ ! -f "$PUB_REPOSITORY_DIR/port" ]; then
    fail add_dependency "no server port found; run publish_locally first"
  fi
  local port
  port="$(cat "$PUB_REPOSITORY_DIR/port")"
  local url="http://127.0.0.1:$port"
  
  if ! (cd "$CONSUMER_DIR" && flutter pub add wallet_core_flutter --hosted-url "$url"); then
    fail add_dependency "flutter pub add failed"
  fi
  
  
  if grep -q "source: path" "$CONSUMER_DIR/pubspec.lock"; then
    fail add_dependency "pubspec.lock contains path dependencies"
  fi
  
  for pkg in wallet_core_flutter wallet_core_flutter_bindings wallet_core_flutter_native; do
    if ! grep -A 10 "^  $pkg:" "$CONSUMER_DIR/pubspec.lock" | grep -q 'source: hosted'; then
      fail add_dependency "$pkg is not hosted in pubspec.lock"
    fi
  done
  
  pass add_dependency "added wallet_core_flutter from $url; pubspec.lock verified"
}

build_debug_android() {
  require build_debug_android python3
  require build_debug_android unzip

  if ! (cd "$CONSUMER_DIR" && flutter build apk --debug --target-platform android-arm64,android-x64); then
    fail build_debug_android "flutter build apk --debug failed"
  fi
  
  local apk="$CONSUMER_DIR/build/app/outputs/flutter-apk/app-debug.apk"
  if [ ! -f "$apk" ]; then
    fail build_debug_android "APK not found at $apk"
  fi
  
  # Check for the .so files
  if ! unzip -l "$apk" | grep 'lib/arm64-v8a/libTrustWalletCore.so' > /dev/null; then
    fail build_debug_android "lib/arm64-v8a/libTrustWalletCore.so missing in APK"
  fi
  if ! unzip -l "$apk" | grep 'lib/x86_64/libTrustWalletCore.so' > /dev/null; then
    fail build_debug_android "lib/x86_64/libTrustWalletCore.so missing in APK"
  fi
  
  # Extract and hash them
  unzip -o -q -j "$apk" 'lib/arm64-v8a/libTrustWalletCore.so' -d "$WORK_DIR/extracted_arm64" || fail build_debug_android "unzip arm64-v8a failed"
  unzip -o -q -j "$apk" 'lib/x86_64/libTrustWalletCore.so' -d "$WORK_DIR/extracted_x86_64" || fail build_debug_android "unzip x86_64 failed"
  
  local arm64_hash x86_64_hash
  if command -v shasum >/dev/null 2>&1; then
    arm64_hash=$(shasum -a 256 "$WORK_DIR/extracted_arm64/libTrustWalletCore.so" | awk '{print $1}')
    x86_64_hash=$(shasum -a 256 "$WORK_DIR/extracted_x86_64/libTrustWalletCore.so" | awk '{print $1}')
  else
    arm64_hash=$(sha256sum "$WORK_DIR/extracted_arm64/libTrustWalletCore.so" | awk '{print $1}')
    x86_64_hash=$(sha256sum "$WORK_DIR/extracted_x86_64/libTrustWalletCore.so" | awk '{print $1}')
  fi
  
  local expected_arm64 expected_x86_64
  expected_arm64=$(python3 -c "import json; d=json.load(open('$REPO_ROOT/compat_manifest.json')); print(d['artifacts']['android/arm64-v8a/libTrustWalletCore.so']['sha256'])" || fail build_debug_android "python3 manifest read failed")
  expected_x86_64=$(python3 -c "import json; d=json.load(open('$REPO_ROOT/compat_manifest.json')); print(d['artifacts']['android/x86_64/libTrustWalletCore.so']['sha256'])" || fail build_debug_android "python3 manifest read failed")
  
  if [ "$arm64_hash" != "$expected_arm64" ]; then
    fail build_debug_android "arm64-v8a hash mismatch: got $arm64_hash expected $expected_arm64"
  fi
  if [ "$x86_64_hash" != "$expected_x86_64" ]; then
    fail build_debug_android "x86_64 hash mismatch: got $x86_64_hash expected $expected_x86_64"
  fi
  
  pass build_debug_android "APK built; arm64-v8a $arm64_hash, x86_64 $x86_64_hash (both matched manifest)"
}

build_release_android() {
  require build_release_android python3
  require build_release_android unzip

  if ! (cd "$CONSUMER_DIR" && flutter build apk --release --target-platform android-arm64,android-x64); then
    fail build_release_android "flutter build apk --release failed"
  fi
  
  local apk="$CONSUMER_DIR/build/app/outputs/flutter-apk/app-release.apk"
  if [ ! -f "$apk" ]; then
    fail build_release_android "APK not found at $apk"
  fi
  
  # Check for the .so files
  if ! unzip -l "$apk" | grep 'lib/arm64-v8a/libTrustWalletCore.so' > /dev/null; then
    fail build_release_android "lib/arm64-v8a/libTrustWalletCore.so missing in APK"
  fi
  if ! unzip -l "$apk" | grep 'lib/x86_64/libTrustWalletCore.so' > /dev/null; then
    fail build_release_android "lib/x86_64/libTrustWalletCore.so missing in APK"
  fi
  
  # Extract and hash them
  unzip -o -q -j "$apk" 'lib/arm64-v8a/libTrustWalletCore.so' -d "$WORK_DIR/extracted_arm64_rel" || fail build_release_android "unzip arm64-v8a failed"
  unzip -o -q -j "$apk" 'lib/x86_64/libTrustWalletCore.so' -d "$WORK_DIR/extracted_x86_64_rel" || fail build_release_android "unzip x86_64 failed"
  
  local arm64_hash x86_64_hash
  if command -v shasum >/dev/null 2>&1; then
    arm64_hash=$(shasum -a 256 "$WORK_DIR/extracted_arm64_rel/libTrustWalletCore.so" | awk '{print $1}')
    x86_64_hash=$(shasum -a 256 "$WORK_DIR/extracted_x86_64_rel/libTrustWalletCore.so" | awk '{print $1}')
  else
    arm64_hash=$(sha256sum "$WORK_DIR/extracted_arm64_rel/libTrustWalletCore.so" | awk '{print $1}')
    x86_64_hash=$(sha256sum "$WORK_DIR/extracted_x86_64_rel/libTrustWalletCore.so" | awk '{print $1}')
  fi
  
  local expected_arm64 expected_x86_64
  expected_arm64=$(python3 -c "import json; d=json.load(open('$REPO_ROOT/compat_manifest.json')); print(d['artifacts']['android/arm64-v8a/libTrustWalletCore.so']['sha256'])" || fail build_release_android "python3 manifest read failed")
  expected_x86_64=$(python3 -c "import json; d=json.load(open('$REPO_ROOT/compat_manifest.json')); print(d['artifacts']['android/x86_64/libTrustWalletCore.so']['sha256'])" || fail build_release_android "python3 manifest read failed")
  
  if [ "$arm64_hash" != "$expected_arm64" ]; then
    fail build_release_android "arm64-v8a hash mismatch: got $arm64_hash expected $expected_arm64"
  fi
  if [ "$x86_64_hash" != "$expected_x86_64" ]; then
    fail build_release_android "x86_64 hash mismatch: got $x86_64_hash expected $expected_x86_64"
  fi
  
  pass build_release_android "APK built; arm64-v8a $arm64_hash, x86_64 $x86_64_hash (both matched manifest)"
}

build_debug_ios() {
  if ! (cd "$CONSUMER_DIR" && flutter build ios --simulator --debug); then
    fail build_debug_ios "flutter build ios --simulator --debug failed"
  fi
  pass build_debug_ios "iOS simulator debug build succeeded"
}

build_release_ios() {
  if ! (cd "$CONSUMER_DIR" && flutter build ios --release --no-codesign); then
    fail build_release_ios "flutter build ios --release --no-codesign failed"
  fi
  pass build_release_ios "iOS release build succeeded (unsigned; no signing identity)"
}

run_m0_flow() {
  require run_m0_flow adb
  
  if [ -z "$IOS_DEVICE" ]; then
    IOS_DEVICE=$(xcrun simctl list devices booted -j | grep -Eo '"udid" : "[^"]+"' | head -1 | awk -F'"' '{print $4}' || true)
    if [ -z "$IOS_DEVICE" ]; then
      fail run_m0_flow "no booted iOS simulator found; start one or use --ios-device"
    fi
  fi

  cat > "$CONSUMER_DIR/lib/m0.dart" << 'EOF_M0'
import 'package:wallet_core_flutter/wallet_core_flutter.dart';

Future<String> runM0() async {
  final core = await WalletCore.initialize();
  final created = await core.wallets.create(strength: 128);
  await created.close();
  
  final wallet = await core.wallets.importMnemonic('broom ramp luggage this language sketch door allow elbow wife moon impulse');
  final account = await wallet.account(Coin.ethereum, path: "m/44'/60'/0'/0/1");
  if (account.address.value != '0x996891c410FB76C19DBA72C6f6cEFF2d9DD069b1') {
    throw Exception('Address mismatch: ${account.address.value}');
  }
  
  try {
    await core.wallets.importMnemonic('abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon');
    throw Exception('Expected InvalidInputError');
  } on InvalidInputError {
    // Expected
  }
  
  final request = EvmTransactionRequest.transfer(
    coin: Coin.ethereum,
    chainId: 3,
    nonce: BigInt.from(6),
    maxPriorityFeePerGas: BigInt.parse('2000000000'),
    maxFeePerGas: BigInt.parse('3000000000'),
    gasLimit: BigInt.parse('21100'),
    to: '0xB9F5771C27664bF2282D98E09D7F50cEc7cB01a7',
    valueWei: BigInt.parse('543210987654321'),
  );
  
  final key = KeyLocator.hdPath(wallet.ref, Coin.ethereum, "m/44'/60'/0'/0/1");
  final result = await core.signer.sign(request, {key});
  
  if (result is! EvmSignResult || result.encoded.isEmpty) {
    throw Exception('sign returned unexpected result or empty bytes: $result');
  }
  
  await wallet.close();
  await core.shutdown();
  
  return 'signed ${result.encoded.length} bytes; gap: no public KeyRef';
}
EOF_M0

  cat > "$CONSUMER_DIR/lib/main.dart" << 'EOF_MAIN'
import 'package:flutter/material.dart';
import 'm0.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final summary = await runM0();
    print('WCF_M0 PASS $summary');
  } catch (e) {
    print('WCF_M0 FAIL $e');
  }
  runApp(const MaterialApp(home: Scaffold(body: Text('M0 Flow Test'))));
}
EOF_MAIN

  mkdir -p "$CONSUMER_DIR/integration_test"
  cat > "$CONSUMER_DIR/integration_test/app_test.dart" << 'EOF_APP_TEST'
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wcf_consumer_check/m0.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('M0 Flow', (WidgetTester tester) async {
    try {
      final summary = await runM0();
      print('WCF_M0 PASS $summary');
    } catch (e) {
      print('WCF_M0 FAIL $e');
      rethrow;
    }
  });
}
EOF_APP_TEST

  if ! grep -q "integration_test:" "$CONSUMER_DIR/pubspec.yaml"; then
    (cd "$CONSUMER_DIR" && flutter pub add --dev integration_test --sdk=flutter) || fail run_m0_flow "flutter pub add integration_test failed"
  fi

  local emulator_log="$WORK_DIR/emulator_debug.log"
  local simulator_log="$WORK_DIR/simulator_debug.log"

  # Debug on Android emulator
  local status=0
  (cd "$CONSUMER_DIR" && with_timeout 900 flutter test integration_test/app_test.dart -d "$ANDROID_DEVICE" | tee "$emulator_log") || status=$?
  if [ "$status" -ne 0 ]; then
    if [ "$status" -eq 124 ]; then
      fail run_m0_flow "timed out after 900 s on $ANDROID_DEVICE"
    else
      fail run_m0_flow "M0 flow debug failed on $ANDROID_DEVICE"
    fi
  fi
  if ! grep -q "WCF_M0 PASS" "$emulator_log"; then
    fail run_m0_flow "WCF_M0 PASS not found in $ANDROID_DEVICE debug output"
  fi
  local emulator_pass
  emulator_pass=$(grep "WCF_M0 PASS" "$emulator_log" | tail -1 | sed 's/.*WCF_M0 PASS //')

  # Debug on iOS simulator
  status=0
  (cd "$CONSUMER_DIR" && with_timeout 900 flutter test integration_test/app_test.dart -d "$IOS_DEVICE" | tee "$simulator_log") || status=$?
  if [ "$status" -ne 0 ]; then
    if [ "$status" -eq 124 ]; then
      fail run_m0_flow "timed out after 900 s on $IOS_DEVICE"
    else
      fail run_m0_flow "M0 flow debug failed on $IOS_DEVICE"
    fi
  fi
  if ! grep -q "WCF_M0 PASS" "$simulator_log"; then
    fail run_m0_flow "WCF_M0 PASS not found in $IOS_DEVICE debug output"
  fi
  local simulator_pass
  simulator_pass=$(grep "WCF_M0 PASS" "$simulator_log" | tail -1 | sed 's/.*WCF_M0 PASS //')

  # Release on Android emulator
  if ! (cd "$CONSUMER_DIR" && flutter build apk --release --target-platform android-arm64,android-x64); then
    fail run_m0_flow "flutter build apk --release failed inside run_m0_flow"
  fi

  local apk="$CONSUMER_DIR/build/app/outputs/flutter-apk/app-release.apk"
  if [ ! -f "$apk" ]; then
    fail run_m0_flow "Release APK not found at $apk"
  fi
  
  adb -s "$ANDROID_DEVICE" logcat -c || fail run_m0_flow "adb logcat -c failed on $ANDROID_DEVICE"
  adb -s "$ANDROID_DEVICE" install -r "$apk" || fail run_m0_flow "adb install -r failed on $ANDROID_DEVICE"
  
  local app_id
  app_id="$(grep -Eo 'applicationId( *| *= *)"[^"]+"' "$CONSUMER_DIR/android/app/build.gradle"* | head -1 | grep -Eo '"[^"]+"' | tr -d '"' || app_id="")"
  if [ -z "$app_id" ]; then
    app_id="dev.wcf.consumer.wcf_consumer_check"
  fi

  adb -s "$ANDROID_DEVICE" shell am start -W -n "$app_id/.MainActivity" || fail run_m0_flow "adb shell am start failed on $ANDROID_DEVICE"
  
  # Wait for PASS line in logcat
  local timeout=60
  local elapsed=0
  local passed=0
  local release_pass=""
  while [ $elapsed -lt $timeout ]; do
    local log_line
    if log_line="$(adb -s "$ANDROID_DEVICE" logcat -d -s flutter | grep -E "WCF_M0 (PASS|FAIL)")"; then
      if echo "$log_line" | grep -q "WCF_M0 PASS"; then
        passed=1
        release_pass=$(echo "$log_line" | grep "WCF_M0 PASS" | tail -1 | sed 's/.*WCF_M0 PASS //')
      else
        fail run_m0_flow "M0 flow release failed: $log_line"
      fi
      break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
  
  if [ $passed -eq 0 ]; then
    fail run_m0_flow "M0 flow release failed on $ANDROID_DEVICE (timeout waiting for PASS)"
  fi
  
  pass run_m0_flow "[$ANDROID_DEVICE debug] $emulator_pass | [$IOS_DEVICE debug] $simulator_pass | [$ANDROID_DEVICE release] $release_pass"
}
report() {
  echo "consumer_check report — $WORK_DIR"
  local stage line
  for stage in $STAGES; do
    [ "$stage" = report ] && continue
    if [ -f "$STATUS_DIR/$stage" ]; then
      line="$(cat "$STATUS_DIR/$stage")"
    else
      line="not run"
    fi
    printf '  %-22s %s\n' "$stage" "$line"
  done
}

cleanup() {
  if [ -f "$WORK_DIR/pub_server.pid" ]; then
    local pid
    pid="$(cat "$WORK_DIR/pub_server.pid")"
    if kill -0 "$pid" 2>/dev/null; then
      if ps -p "$pid" -o command= | grep -q publish_locally.dart; then
        kill "$pid" 2>/dev/null || true
      fi
    fi
    rm -f "$WORK_DIR/pub_server.pid"
  fi
}

run_all() {
  trap cleanup EXIT
  rm -rf "$STATUS_DIR"
  if [ -f "$WORK_DIR/pub_server.pid" ]; then
    local pid
    pid="$(cat "$WORK_DIR/pub_server.pid")"
    if kill -0 "$pid" 2>/dev/null && ps -p "$pid" -o command= | grep -q publish_locally.dart; then
      kill "$pid" 2>/dev/null || true
    fi
  fi
  rm -f "$PUB_REPOSITORY_DIR/port" "$WORK_DIR/pub_server.pid"
  local stage status worst=0
  for stage in $STAGES; do
    [ "$stage" = report ] && continue
    status=0
    local args=("--stage" "$stage")
    if [ -n "$ANDROID_DEVICE" ]; then
      args+=("--android-device" "$ANDROID_DEVICE")
    fi
    if [ -n "$IOS_DEVICE" ]; then
      args+=("--ios-device" "$IOS_DEVICE")
    fi
    "$BASH" "$SCRIPT_PATH" "${args[@]}" || status=$?
    if [ "$status" -ne 0 ]; then
      worst=1
      break
    fi
  done
  report
  return "$worst"
}

if [ -n "$STAGE" ]; then
  if [ "$STAGE" != report ]; then
    rm -f "$STATUS_DIR/$STAGE"
    trap '[ -f "$STATUS_DIR/$STAGE" ] || record "$STAGE" "failed — exited without a result (see output)"' EXIT
  fi
  "$STAGE"
else
  run_all
fi

