#!/usr/bin/env bash
#
# android_device_diag.sh — run the Android M0 flow (tools/device_test.sh android)
# under diagnostics, so that a failing or hanging run leaves evidence behind.
#
# Usage: WCF_ANDROID_DEVICE=<adb serial> DIAG_DIR=<directory> \
#          [WCF_TEST_EXTRA="<extra flutter test arguments>"] \
#          bash tools/ci/android_device_diag.sh
#
# It is one command on purpose: reactivecircus/android-emulator-runner runs each
# line of its `script` input as a separate `sh -c`, so background jobs and the
# test's exit code only survive inside a single script.
#
# What it writes to $DIAG_DIR:
#   device.txt          ABI list, page size, kernel, CPU flags of the device
#   logcat.txt          logcat (main, system, crash) for the whole run
#   heartbeat.txt       every 20 s: UTC time, adb state, app pid, qemu count
#   flutter_test.txt    the verbose `flutter test` output
#   activity.txt        resumed / focused activity after the run
#   screen.png          screenshot after the run
#   native_stacks.txt   `debuggerd -b` of the app, if it is still running
#   tombstones/ anr/    pulled from the device when readable (needs adb root)
#
# The test runs under `timeout -s KILL 15m` (GNU coreutils; `gtimeout` is used
# when only that exists). Without either, as on a stock macOS, it runs with no
# time limit and a warning. The script exits with the test's exit code; a
# timeout (124 or 137) is a failure. A missing variable, adb or device exits 2.
#
# Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
# Not affiliated with or endorsed by Trust Wallet.

set -uo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
test_timeout=15m

serial="${WCF_ANDROID_DEVICE:-}"
diag="${DIAG_DIR:-}"
if [ -z "$serial" ]; then
  echo "android_device_diag: WCF_ANDROID_DEVICE is not set (an adb serial, for example emulator-5554)." >&2
  exit 2
fi
if [ -z "$diag" ]; then
  echo "android_device_diag: DIAG_DIR is not set (the directory the diagnostics are written to)." >&2
  exit 2
fi
if ! command -v adb >/dev/null 2>&1; then
  echo "android_device_diag: adb is not on PATH (Android SDK platform-tools)." >&2
  exit 2
fi
mkdir -p "$diag" || exit 2

timeout_bin=""
if command -v timeout >/dev/null 2>&1; then
  timeout_bin=timeout
elif command -v gtimeout >/dev/null 2>&1; then
  timeout_bin=gtimeout
else
  echo "android_device_diag: WARNING: neither timeout nor gtimeout is on PATH;" >&2
  echo "  the test and the adb calls below run with no time limit." >&2
fi

# Runs "$@" killed after $1 when a timeout binary exists, unbounded otherwise.
# A stalled emulator can hang any adb call; this keeps the script finishing.
bounded() {
  local limit="$1"
  shift
  if [ -n "$timeout_bin" ]; then
    "$timeout_bin" -s KILL "$limit" "$@"
  else
    "$@"
  fi
}

state="$(bounded 30s adb -s "$serial" get-state 2>/dev/null || true)"
if [ "$state" != "device" ]; then
  echo "android_device_diag: Android device '$serial' is not online (adb get-state: '${state:-none}')." >&2
  exit 2
fi

app_id=""
for gradle in "$root"/example/android/app/build.gradle.kts "$root"/example/android/app/build.gradle; do
  [ -f "$gradle" ] || continue
  app_id="$(sed -nE 's/^[[:space:]]*applicationId[[:space:]]*=?[[:space:]]*"([^"]+)".*/\1/p' "$gradle" | head -n 1)"
  [ -n "$app_id" ] && break
done
if [ -z "$app_id" ]; then
  echo "android_device_diag: WARNING: no applicationId in example/android/app/build.gradle*;" >&2
  echo "  the app pid is not tracked." >&2
fi

echo "android_device_diag: device $serial, app ${app_id:-unknown}, diagnostics in $diag"

# Root lets debuggerd and the tombstone/ANR pulls work; images without it
# (user builds) refuse, and the run goes on without those.
root_out="$(bounded 30s adb -s "$serial" root 2>&1)"
echo "adb root: $root_out"
case "$root_out" in
  *restarting*) sleep 3 ;; # adbd restarts; let the old one go away first
esac
bounded 120s adb -s "$serial" wait-for-device || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
  bounded 10s adb -s "$serial" shell true >/dev/null 2>&1 && break
  sleep 2
done

{
  echo "serial: $serial"
  echo "ro.product.cpu.abilist: $(bounded 30s adb -s "$serial" shell getprop ro.product.cpu.abilist 2>&1)"
  echo "PAGE_SIZE: $(bounded 30s adb -s "$serial" shell getconf PAGE_SIZE 2>&1)"
  echo "uname -a: $(bounded 30s adb -s "$serial" shell uname -a 2>&1)"
  echo "cpuinfo flags: $(bounded 30s adb -s "$serial" shell 'cat /proc/cpuinfo | grep -m1 flags' 2>&1)"
} >"$diag/device.txt"

bounded 30s adb -s "$serial" logcat -c || true

logcat_pid=""
heartbeat_pid=""
cleanup() {
  local pid
  for pid in $heartbeat_pid $logcat_pid; do
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null # reaps it without a "Terminated" job notice
  done
  heartbeat_pid=""
  logcat_pid=""
}
trap cleanup EXIT

adb -s "$serial" logcat -v threadtime -b main,system,crash >"$diag/logcat.txt" 2>&1 &
logcat_pid=$!

# stdout/stderr go to /dev/null so a leftover `sleep` holds no pipe of the
# caller open after the loop is killed.
(
  while :; do
    beat_state="$(bounded 10s adb -s "$serial" get-state 2>/dev/null)"
    beat_pid=""
    if [ -n "$app_id" ]; then
      beat_pid="$(bounded 10s adb -s "$serial" shell pidof "$app_id" 2>/dev/null)"
    fi
    qemu="$(pgrep -f qemu-system 2>/dev/null | wc -l | tr -d '[:space:]')"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) state=${beat_state:-none} pid=${beat_pid:--} qemu=$qemu" >>"$diag/heartbeat.txt"
    sleep 20
  done
) >/dev/null 2>&1 &
heartbeat_pid=$!

run_test() {
  # WCF_TEST_EXTRA is split into words on purpose: it carries flags.
  # shellcheck disable=SC2086
  if [ -n "$timeout_bin" ]; then
    "$timeout_bin" -s KILL "$test_timeout" \
      bash "$root/tools/device_test.sh" android --verbose --reporter expanded ${WCF_TEST_EXTRA:-}
  else
    bash "$root/tools/device_test.sh" android --verbose --reporter expanded ${WCF_TEST_EXTRA:-}
  fi
}

run_test 2>&1 | tee "$diag/flutter_test.txt"
rc=${PIPESTATUS[0]}

echo "android_device_diag: flutter test exited $rc; collecting the post-run state"

bounded 60s adb -s "$serial" shell dumpsys activity activities 2>&1 \
  | grep -E 'ResumedActivity|mFocusedApp' >"$diag/activity.txt"
bounded 60s adb -s "$serial" exec-out screencap -p >"$diag/screen.png" 2>/dev/null \
  || echo "android_device_diag: screencap failed" >&2

if [ -n "$app_id" ]; then
  app_pid="$(bounded 10s adb -s "$serial" shell pidof "$app_id" 2>/dev/null | tr -d '[:space:]')"
  if [ -n "$app_pid" ]; then
    bounded 120s adb -s "$serial" shell debuggerd -b "$app_pid" >"$diag/native_stacks.txt" 2>&1 || true
  fi
fi

bounded 120s adb -s "$serial" pull /data/tombstones "$diag/" >/dev/null 2>&1 \
  || echo "android_device_diag: could not pull /data/tombstones" >&2
bounded 120s adb -s "$serial" pull /data/anr "$diag/" >/dev/null 2>&1 \
  || echo "android_device_diag: could not pull /data/anr" >&2

cleanup

echo "===== logcat (filtered, last 100 matching lines) ====="
grep -E 'AndroidRuntime|FATAL|F DEBUG|signal [0-9]+ \(SIG|dlopen failed|cannot locate symbol|Impeller|VM service is listening|[IEW] flutter|ANR in' \
  "$diag/logcat.txt" | tail -n 100
echo "===== flutter_test.txt (last 40 lines) ====="
tail -n 40 "$diag/flutter_test.txt"

case "$rc" in
  0) ;;
  124 | 137) echo "android_device_diag: flutter test was killed after $test_timeout (exit $rc)." >&2 ;;
  *) echo "android_device_diag: flutter test failed (exit $rc)." >&2 ;;
esac
echo "android_device_diag: diagnostics in $diag"
exit "$rc"
