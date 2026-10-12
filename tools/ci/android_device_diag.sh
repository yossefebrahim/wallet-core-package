#!/usr/bin/env bash
#
# android_device_diag.sh — run the Android integration tests
# (tools/device_test.sh android) under diagnostics, one test file at a time, so
# that a failing or hanging run leaves evidence behind and one flaky launch
# costs one file, not the rest of the run.
#
# Usage: WCF_ANDROID_DEVICE=<adb serial> DIAG_DIR=<directory> \
#          [WCF_TEST_EXTRA="<extra flutter test arguments>"] \
#          bash tools/ci/android_device_diag.sh
#
# It is one command on purpose: reactivecircus/android-emulator-runner runs each
# line of its `script` input as a separate `sh -c`, so background jobs and the
# tests' exit codes only survive inside a single script.
#
# Each file under example/integration_test/*_test.dart (in C-locale sorted
# order) is its own `flutter test` run: its own app launch and VM-service
# attach. Before this, all files shared one run, and in CI run 38292237498 two
# of five files failed at load with "Failed to start Dart Development Service"
# (the app launched, the VM-service URL was found and forwarded, DDS failed to
# start, no test of the file ran) and lost every result they would have
# recorded; a rerun of the job was green.
#
# Time limits. Each attempt runs under `timeout -s KILL` (GNU coreutils;
# `gtimeout` is used when only that exists; without either there is no
# per-attempt limit, and a warning). The limit is min(600 s, budget left). In
# that run the cold first file (Gradle build, NDK download, install, launch)
# took ~250 s and every later file ~20 s, so 600 s is more than twice the cold
# case and 30x a warm one. The whole script stays inside WCF_TOTAL_BUDGET_S
# (default 1200 s, 20 min); the CI step's limit is 30 min, which leaves 10 min
# for the post-run collection below (its adb calls are bounded to ~7 min in the
# worst case), so the summary always prints. An attempt that would start with
# under 30 s of budget left is not run; a retry needs 120 s left.
#
# One retry, for one known tooling failure: the flutter tool could not attach
# to the freshly launched app. A file is run a second time only when its first
# attempt's output has "Failed to start Dart Development Service" (the Android
# case, run 38292237498) or "Error waiting for a debug connection" (the iOS
# lane's case, kept for parity) AND no test result line (`+N: <name>`, other
# than `loading` and the closing "Some tests failed." line). A test failure, a
# timeout, or a run in which tests started is never retried.
#
# Before the retry the script force-stops the app and removes the device's adb
# forwards. KNOWN: in the failing runs DDS died 0.2-0.5 s after it was asked to
# start, with no reason in the output, and the app, the VM-service URL and the
# forward were already in place. GUESS: a leftover forward or DDS port from the
# previous launch, or an app instance still shutting down, is the likeliest
# cause; the cleanup targets that. A retry that succeeds shows the failure was
# transient, not that this was the cause.
#
# What it writes to $DIAG_DIR:
#   device.txt                     ABI list, page size, kernel, CPU flags of the device
#   logcat.txt                     logcat (main, system, crash) for the whole run
#   heartbeat.txt                  every 20 s: UTC time, adb state, app pid, qemu count
#   flutter_test_<name>.txt        the verbose `flutter test` output of one file
#   flutter_test_<name>.retry.txt  the same, for the retry (only when retried)
#   activity.txt                   resumed / focused activity after the run
#   screen.png                     screenshot after the run
#   native_stacks.txt              `debuggerd -b` of the app, if it is still running
#   {activity,screen,native_stacks}_hang_<tag>.*
#                                  the same three, taken right after an attempt was
#                                  killed by its timeout (<tag> is the file name,
#                                  with `.retry` appended for the retry)
#   tombstones/ anr/               pulled from the device when readable (needs adb root)
#
# The script exits 1 when any file failed or timed out. A missing variable,
# adb or device, or no test files, exits 2.
#
# Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
# Not affiliated with or endorsed by Trust Wallet.

set -uo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
file_timeout_s="${WCF_FILE_TIMEOUT_S:-600}" # the overrides exist to test the limits
budget_s="${WCF_TOTAL_BUDGET_S:-1200}"
started=$SECONDS

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
  echo "  the tests and the adb calls below run with no time limit." >&2
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

# Post-run state of the device: resumed activity, a screenshot and the app's
# native stacks. $1 is the tag; empty for the end of the run.
collect_state() {
  local suffix="${1:+_$1}" app_pid
  bounded 60s adb -s "$serial" shell dumpsys activity activities 2>&1 \
    | grep -E 'ResumedActivity|mFocusedApp' >"$diag/activity$suffix.txt"
  bounded 60s adb -s "$serial" exec-out screencap -p >"$diag/screen$suffix.png" 2>/dev/null \
    || echo "android_device_diag: screencap failed" >&2
  if [ -n "$app_id" ]; then
    app_pid="$(bounded 10s adb -s "$serial" shell pidof "$app_id" 2>/dev/null | tr -d '[:space:]')"
    if [ -n "$app_pid" ]; then
      bounded 120s adb -s "$serial" shell debuggerd -b "$app_pid" >"$diag/native_stacks$suffix.txt" 2>&1 || true
    fi
  fi
}

# Returns 0 and sets attach_reason when $1 (a flutter test log) shows an attach
# failure and no test ever ran: the error text is there and no `+N: <name>`
# result line is, other than `loading` and the closing "Some tests failed."
# (which flutter prints for a load error too).
is_attach_failure() {
  local started_tests
  attach_reason=""
  if grep -q 'Failed to start Dart Development Service' "$1"; then
    attach_reason="Failed to start Dart Development Service"
  elif grep -q 'Error waiting for a debug connection' "$1"; then
    attach_reason="Error waiting for a debug connection"
  else
    return 1
  fi
  started_tests="$(grep -E '[0-9]{2}:[0-9]{2} \+[0-9]+( [-~][0-9]+)*: ' "$1" \
    | grep -Evc ': loading |: Some tests failed\.' || true)"
  [ "${started_tests:-0}" -eq 0 ]
}

# Between attempts: the app and the adb forwards of the failed launch.
clean_before_retry() {
  bounded 30s adb -s "$serial" shell am force-stop "${app_id:-dev.wcf.example.wallet_core_flutter_example}" || true
  bounded 30s adb -s "$serial" forward --remove-all || true
  sleep 2
}

# run_attempt <test file name> <log> <tag>: one `flutter test` run of one file.
# Sets attempt_rc: the exit code (124 or 137 when the timeout fired), 125 when
# the time budget left no room to start.
run_attempt() {
  local base="$1" log="$2" tag="$3" limit left
  left=$((budget_s - (SECONDS - started)))
  limit=$file_timeout_s
  [ "$left" -lt "$limit" ] && limit=$left
  if [ "$left" -lt 30 ]; then
    echo "android_device_diag: $tag not started: ${left}s of the ${budget_s}s budget left" >&2
    attempt_rc=125
    return
  fi
  echo "android_device_diag: ===== $tag ($(date -u +%H:%M:%SZ), limit ${limit}s) ====="
  # WCF_TEST_EXTRA is split into words on purpose: it carries flags.
  # shellcheck disable=SC2086
  bounded "${limit}s" \
    bash "$root/tools/device_test.sh" android "integration_test/$base" \
    --verbose --reporter expanded ${WCF_TEST_EXTRA:-} 2>&1 | tee "$log"
  attempt_rc=${PIPESTATUS[0]}
  case "$attempt_rc" in
    124 | 137)
      echo "android_device_diag: $tag was killed after ${limit}s (exit $attempt_rc); collecting evidence" >&2
      collect_state "hang_$tag"
      ;;
  esac
}

failed=0
summary=""
reason=""
while IFS= read -r f; do
  [ -e "$f" ] || continue
  base="$(basename "$f")"
  name="$(basename "$f" .dart)"
  out="$diag/flutter_test_$name.txt"
  retried=0

  run_attempt "$base" "$out" "$name"
  rc=$attempt_rc

  if [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ] && [ "$rc" -ne 125 ] && [ "$rc" -ne 137 ] && is_attach_failure "$out"; then
    reason="$attach_reason"
    left=$((budget_s - (SECONDS - started)))
    if [ "$left" -ge 120 ]; then
      echo "android_device_diag: $name: '$reason' on attempt 1 (exit $rc, no test ran); cleaning up and retrying once" >&2
      clean_before_retry
      out="$diag/flutter_test_$name.retry.txt"
      retried=1
      run_attempt "$base" "$out" "$name.retry"
      rc=$attempt_rc
    else
      echo "android_device_diag: $name: '$reason', but only ${left}s of budget is left; not retrying" >&2
    fi
  fi

  case "$rc" in
    0)
      if [ "$retried" -eq 1 ]; then
        summary="$summary$name: ok after retry ($reason on attempt 1)"$'\n'
      else
        summary="$summary$name: ok"$'\n'
      fi
      ;;
    124 | 137)
      summary="$summary$name: TIMEOUT$([ "$retried" -eq 1 ] && echo ' (on the retry)') (exit $rc)"$'\n'
      failed=1
      ;;
    125)
      summary="$summary$name: NOT RUN (time budget exhausted)"$'\n'
      failed=1
      ;;
    *)
      echo "android_device_diag: $name failed (exit $rc)" >&2
      summary="$summary$name: FAILED$([ "$retried" -eq 1 ] && echo ' after retry') (exit $rc)"$'\n'
      failed=1
      ;;
  esac
done < <(printf '%s\n' "$root"/example/integration_test/*_test.dart | LC_ALL=C sort)

if [ -z "$summary" ]; then
  echo "android_device_diag: no example/integration_test/*_test.dart files found." >&2
  exit 2
fi

echo "android_device_diag: all files done; collecting the post-run state"
collect_state ""

bounded 120s adb -s "$serial" pull /data/tombstones "$diag/" >/dev/null 2>&1 \
  || echo "android_device_diag: could not pull /data/tombstones" >&2
bounded 120s adb -s "$serial" pull /data/anr "$diag/" >/dev/null 2>&1 \
  || echo "android_device_diag: could not pull /data/anr" >&2

cleanup

echo "===== logcat (filtered, last 100 matching lines) ====="
grep -E 'AndroidRuntime|FATAL|F DEBUG|signal [0-9]+ \(SIG|dlopen failed|cannot locate symbol|Impeller|VM service is listening|[IEW] flutter|ANR in' \
  "$diag/logcat.txt" | tail -n 100
for out in "$diag"/flutter_test_*.txt; do
  [ -e "$out" ] || continue
  echo "===== $(basename "$out") (last 40 lines) ====="
  tail -n 40 "$out"
done
echo "===== summary ====="
printf '%s' "$summary"
echo "android_device_diag: diagnostics in $diag"
exit "$failed"
