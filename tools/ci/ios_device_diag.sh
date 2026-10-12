#!/usr/bin/env bash
#
# ios_device_diag.sh — run the iOS integration tests (tools/device_test.sh ios)
# under diagnostics, one test file at a time, so that a failing or hanging run
# leaves evidence behind instead of a silent job timeout.
#
# Usage: WCF_IOS_DEVICE=<simulator udid> DIAG_DIR=<directory> \
#          [WCF_TEST_EXTRA="<extra flutter test arguments>"] \
#          bash tools/ci/ios_device_diag.sh
#
# The simulator must already be booted; this script never boots, shuts down or
# erases one. It is one command on purpose, so that the background jobs and the
# per-file exit codes live in a single shell.
#
# Each file under example/integration_test/*_test.dart is its own
# `flutter test` run (its own app launch and VM-service attach) under a
# 12-minute watchdog: a background `sleep` that, when it fires, first collects
# evidence from the still-running Runner and then kills the run's process
# group. (macOS runners have no GNU `timeout`/`gtimeout`, so none is used.)
#
# One retry, for one known tooling failure: on a cold first launch on the iOS
# 26.5 simulator flutter_tools' log reader can miss the app's "Dart VM service
# is listening" line, waits ~340 s and fails with "Error waiting for a debug
# connection" before any test ran (CI run 38283052160). A file is run a second
# time only when its first run's output has that error AND no test result line
# (`+N: <name>`, other than `loading` and the closing "Some tests failed." line,
# which flutter prints for a load error too and which would otherwise make every
# attach failure that ends without the watchdog look like a started run). A test
# failure, or a run in which tests started, is never retried.
#
# Time budget: the whole script stays inside WCF_TOTAL_BUDGET_S (default 1920 s,
# 32 min, so the summary is printed before the CI step's 35-minute limit). Each
# attempt's watchdog is min(720 s, budget left); a retry needs 120 s of budget.
# Expected worst case that still retries: cold build ~7 min + failed VM-service
# wait ~6 min + warm retry ~1-2 min + second file ~1-2 min = ~17 min.
#
# What it writes to $DIAG_DIR:
#   device.txt                   booted simulators, sw_vers, Xcode, host CPU
#   simlog.txt                   `log stream` of the simulator for the whole run
#   heartbeat.txt                every 20 s: UTC time, host Runner.app processes,
#                                UIKit applications known to the simulator
#   flutter_test_<name>.txt      the verbose `flutter test` output of one file
#   flutter_test_<name>.retry.txt  the same, for the retry (only when retried)
#   watchdog_<tag>.txt           what the watchdog did when it fired
#   sample_<tag>_<pid>.txt       host `sample` of the Runner, taken BEFORE the kill
#   screen_<tag>.png             simulator screenshot, taken BEFORE the kill
#   Runner_crash_<file>          Runner crash reports from DiagnosticReports
# (<tag> is the file name, with `.retry` appended for the retry.) There is no
# spindump: `simctl spawn ... spindump` does not exist and the host `spindump`
# needs root.
#
# The script exits non-zero when any file failed or timed out; a missing
# variable, tool or booted simulator exits 2.
#
# Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
# Not affiliated with or endorsed by Trust Wallet.

set -uo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
file_timeout_s="${WCF_FILE_TIMEOUT_S:-720}" # 12 minutes per attempt; the overrides exist to test the watchdog
budget_s="${WCF_TOTAL_BUDGET_S:-1920}"
started=$SECONDS

device="${WCF_IOS_DEVICE:-}"
diag="${DIAG_DIR:-}"
if [ -z "$device" ]; then
  echo "ios_device_diag: WCF_IOS_DEVICE is not set (a booted simulator UDID, see 'xcrun simctl list devices booted')." >&2
  exit 2
fi
if [ -z "$diag" ]; then
  echo "ios_device_diag: DIAG_DIR is not set (the directory the diagnostics are written to)." >&2
  exit 2
fi
if ! command -v xcrun >/dev/null 2>&1; then
  echo "ios_device_diag: xcrun is not available (Xcode command line tools)." >&2
  exit 2
fi
booted="$(xcrun simctl list devices booted -j 2>/dev/null || true)"
if ! printf '%s' "$booted" | grep -Fq "\"udid\" : \"$device\""; then
  echo "ios_device_diag: simulator '$device' is not booted ('xcrun simctl list devices booted')." >&2
  exit 2
fi
mkdir -p "$diag" || exit 2

# The Runner target's bundle id, not the RunnerTests one. The fallback is the
# id the example app was created with.
bundle_id="$(sed -nE 's/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);.*/\1/p' \
  "$root/example/ios/Runner.xcodeproj/project.pbxproj" 2>/dev/null \
  | grep -v 'RunnerTests' | head -n 1)"
if [ -z "$bundle_id" ]; then
  bundle_id=dev.wcf.example.walletCoreFlutterExample
  echo "ios_device_diag: WARNING: no bundle id in project.pbxproj; assuming $bundle_id" >&2
fi

echo "ios_device_diag: simulator $device, app $bundle_id, diagnostics in $diag"

{
  echo "== xcrun simctl list devices booted"
  xcrun simctl list devices booted 2>&1
  echo "== sw_vers"
  sw_vers 2>&1
  echo "== xcodebuild -version"
  xcodebuild -version 2>&1
  echo "== sysctl machdep.cpu.brand_string"
  sysctl -n machdep.cpu.brand_string 2>&1
  echo "== bundle id: $bundle_id"
} >"$diag/device.txt"

log_pid=""
heartbeat_pid=""
cleanup() {
  local pid
  for pid in $heartbeat_pid $log_pid; do
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null # reaps it without a "Terminated" job notice
  done
  heartbeat_pid=""
  log_pid=""
}
trap cleanup EXIT

xcrun simctl spawn "$device" log stream --style compact --level debug \
  --predicate 'process CONTAINS "Runner" OR subsystem CONTAINS "flutter"' \
  >"$diag/simlog.txt" 2>&1 &
log_pid=$!

# Simulator apps are host processes, so pgrep on the host sees the Runner.
# stdout/stderr go to /dev/null so a leftover `sleep` holds no pipe of the
# caller open after the loop is killed.
(
  while :; do
    runner="$(pgrep -fl 'Runner.app' 2>/dev/null | tr '\n' ';')"
    uikit="$(xcrun simctl spawn "$device" launchctl list 2>/dev/null | grep -c UIKitApplication || true)"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) uikit_apps=${uikit:-?} runner=[${runner}]" >>"$diag/heartbeat.txt"
    sleep 20
  done
) >/dev/null 2>&1 &
heartbeat_pid=$!

# Evidence about a hung attempt: host stack sample of the Runner, a simulator
# screenshot, and any Runner crash report. Called by the watchdog BEFORE it
# kills the run, while the Runner is still alive.
collect_timeout_evidence() {
  local tag="$1" pid reports f
  for pid in $(pgrep -f 'Runner.app/Runner' 2>/dev/null); do
    sample "$pid" 5 -file "$diag/sample_${tag}_$pid.txt" >/dev/null 2>&1 \
      || echo "ios_device_diag: sample of pid $pid failed"
  done
  xcrun simctl io "$device" screenshot "$diag/screen_$tag.png" >/dev/null 2>&1 \
    || echo "ios_device_diag: screenshot failed"
  reports="$HOME/Library/Logs/DiagnosticReports"
  for f in "$reports"/Runner*; do
    [ -e "$f" ] && cp "$f" "$diag/Runner_crash_$(basename "$f")"
  done
  return 0
}

# True when $1 (a flutter test log) shows the VM-service discovery failure and
# no test ever ran: the error text is there and no `+N: <name>` result line
# other than `loading` and the closing "Some tests failed." is (flutter prints
# that line, as `+0 -1: Some tests failed.`, after a load error too).
is_tooling_failure() {
  local started_tests
  grep -q 'Error waiting for a debug connection' "$1" || return 1
  started_tests="$(grep -E '[0-9]{2}:[0-9]{2} \+[0-9]+( [-~][0-9]+)*: ' "$1" \
    | grep -Evc ': loading |: Some tests failed\.' || true)"
  [ "${started_tests:-0}" -eq 0 ]
}

# run_attempt <test file name> <log> <tag>: one `flutter test` run of one file.
# Sets attempt_rc: the exit code, 124 when the watchdog fired, 125 when the
# time budget left no room to start.
run_attempt() {
  local base="$1" log="$2" tag="$3" limit left flag wlog test_pid watchdog_pid tail_pid
  flag="$diag/.timeout_$tag"
  wlog="$diag/watchdog_$tag.txt"
  rm -f "$flag" "$wlog"
  left=$((budget_s - (SECONDS - started)))
  limit=$file_timeout_s
  [ "$left" -lt "$limit" ] && limit=$left
  if [ "$left" -lt 30 ]; then
    echo "ios_device_diag: $tag not started: ${left}s of the ${budget_s}s budget left" >&2
    attempt_rc=125
    return
  fi
  : >"$log" # exists before `tail -f` opens it
  echo "ios_device_diag: ===== $tag ($(date -u +%H:%M:%SZ), watchdog ${limit}s) ====="

  # WCF_TEST_EXTRA is split into words on purpose: it carries flags.
  # shellcheck disable=SC2086
  bash "$root/tools/device_test.sh" ios "integration_test/$base" \
    --verbose --reporter expanded ${WCF_TEST_EXTRA:-} >"$log" 2>&1 &
  test_pid=$!
  # The watchdog is a job of its own (set -m), so killing its group also kills
  # its `sleep`. Its output goes to a file: a leftover `sleep` must not hold the
  # caller's pipe open.
  (
    sleep "$limit"
    : >"$flag"
    echo "watchdog fired after ${limit}s; collecting evidence before the kill"
    collect_timeout_evidence "$tag"
    kill -TERM -- "-$test_pid" 2>/dev/null
    sleep 5
    kill -KILL -- "-$test_pid" 2>/dev/null
    echo "killed process group $test_pid"
  ) >"$wlog" 2>&1 &
  watchdog_pid=$!

  # Stream the log to the job output as it is written.
  tail -n +1 -f "$log" &
  tail_pid=$!

  wait "$test_pid" 2>/dev/null
  attempt_rc=$?
  kill -TERM -- "-$watchdog_pid" 2>/dev/null
  wait "$watchdog_pid" 2>/dev/null
  sleep 1 # let tail print the last lines
  kill "$tail_pid" 2>/dev/null
  wait "$tail_pid" 2>/dev/null

  if [ -e "$flag" ]; then
    rm -f "$flag"
    attempt_rc=124
    echo "ios_device_diag: $tag was killed by the watchdog after ${limit}s" >&2
    cat "$wlog" >&2
  else
    rm -f "$wlog" # the watchdog never fired
  fi
}

# Job control gives every background job its own process group, so a kill of
# -PID takes the flutter tool and everything it started with it.
set -m

failed=0
summary=""
for f in "$root"/example/integration_test/*_test.dart; do
  [ -e "$f" ] || continue
  base="$(basename "$f")"
  name="$(basename "$f" .dart)"
  out="$diag/flutter_test_$name.txt"
  retried=0

  run_attempt "$base" "$out" "$name"
  rc=$attempt_rc

  if [ "$rc" -ne 0 ] && [ "$rc" -ne 125 ] && is_tooling_failure "$out"; then
    left=$((budget_s - (SECONDS - started)))
    if [ "$left" -ge 120 ]; then
      echo "ios_device_diag: $name: VM-service discovery failed on attempt 1 (exit $rc, no test ran); retrying once" >&2
      out="$diag/flutter_test_$name.retry.txt"
      retried=1
      run_attempt "$base" "$out" "$name.retry"
      rc=$attempt_rc
    else
      echo "ios_device_diag: $name: VM-service discovery failed, but only ${left}s of budget is left; not retrying" >&2
    fi
  fi

  case "$rc" in
    0)
      if [ "$retried" -eq 1 ]; then
        summary="$summary$name: ok after retry (VM-service discovery failed on attempt 1)"$'\n'
      else
        summary="$summary$name: ok"$'\n'
      fi
      ;;
    124)
      summary="$summary$name: TIMEOUT$([ "$retried" -eq 1 ] && echo ' (on the retry)')"$'\n'
      failed=1
      ;;
    125)
      summary="$summary$name: NOT RUN (time budget exhausted)"$'\n'
      failed=1
      ;;
    *)
      echo "ios_device_diag: $name failed (exit $rc)" >&2
      summary="$summary$name: FAILED$([ "$retried" -eq 1 ] && echo ' after retry') (exit $rc)"$'\n'
      failed=1
      ;;
  esac
done

if [ -z "$summary" ]; then
  echo "ios_device_diag: no example/integration_test/*_test.dart files found." >&2
  exit 2
fi

cleanup

echo "===== simlog.txt (filtered, last 100 matching lines) ====="
grep -E 'flutter|Dart|VM Service|Observatory|crash|EXC_|Termination|dyld|libTrustWalletCore|wcf_' \
  "$diag/simlog.txt" | tail -n 100
for out in "$diag"/flutter_test_*.txt; do
  [ -e "$out" ] || continue
  echo "===== $(basename "$out") (last 40 lines) ====="
  tail -n 40 "$out"
done
echo "===== summary ====="
printf '%s' "$summary"
echo "ios_device_diag: diagnostics in $diag"
exit "$failed"
