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
# 12-minute watchdog. `gtimeout` is used when it exists; a stock macOS has no
# GNU `timeout`, so otherwise a background `sleep` kills the run's process
# group, with a warning.
#
# What it writes to $DIAG_DIR:
#   device.txt                   booted simulators, sw_vers, Xcode, host CPU
#   simlog.txt                   `log stream` of the simulator for the whole run
#   heartbeat.txt                every 20 s: UTC time, host Runner.app processes,
#                                UIKit applications known to the simulator
#   flutter_test_<name>.txt      the verbose `flutter test` output of one file
#   sample_<name>.txt            host `sample` of the Runner process (timeout only)
#   spindump_<name>.txt          simulator spindump (timeout only, when cheap)
#   screen_<name>.png            simulator screenshot (timeout only)
#   Runner_crash_<file>          Runner crash reports from DiagnosticReports
#
# The evidence of a timeout is collected after the `flutter test` process group
# has been killed; the Runner app is a child of the simulator, not of the
# flutter tool, so it is normally still running then.
#
# The script exits non-zero when any file failed or timed out; a missing
# variable, tool or booted simulator exits 2.
#
# Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
# Not affiliated with or endorsed by Trust Wallet.

set -uo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
file_timeout_s="${WCF_FILE_TIMEOUT_S:-720}" # 12 minutes per file; the override exists to test the watchdog

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

timeout_bin=""
if command -v gtimeout >/dev/null 2>&1; then
  timeout_bin=gtimeout
elif command -v timeout >/dev/null 2>&1; then
  timeout_bin=timeout
else
  echo "ios_device_diag: WARNING: neither gtimeout nor timeout is on PATH;" >&2
  echo "  each test file is bounded by a background sleep that kills its process group." >&2
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

# Evidence about a hung file: host stack sample of the Runner, simulator
# spindump and screenshot, and any Runner crash report.
collect_timeout_evidence() {
  local name="$1" pid reports f
  for pid in $(pgrep -f 'Runner.app/Runner' 2>/dev/null); do
    sample "$pid" 5 -file "$diag/sample_${name}_$pid.txt" >/dev/null 2>&1 \
      || echo "ios_device_diag: sample of pid $pid failed" >&2
  done
  xcrun simctl spawn "$device" spindump -notarget >"$diag/spindump_$name.txt" 2>&1 || true
  xcrun simctl io "$device" screenshot "$diag/screen_$name.png" >/dev/null 2>&1 \
    || echo "ios_device_diag: screenshot failed" >&2
  reports="$HOME/Library/Logs/DiagnosticReports"
  for f in "$reports"/Runner*; do
    [ -e "$f" ] && cp "$f" "$diag/Runner_crash_$(basename "$f")"
  done
  return 0
}

# Job control gives every background job its own process group, so a kill of
# -PID takes the flutter tool and everything it started with it.
set -m

failed=0
summary=""
for f in "$root"/example/integration_test/*_test.dart; do
  [ -e "$f" ] || continue
  name="$(basename "$f" .dart)"
  out="$diag/flutter_test_$name.txt"
  flag="$diag/.timeout_$name"
  rm -f "$flag"
  : >"$out" # exists before `tail -f` opens it
  echo "ios_device_diag: ===== $name ($(date -u +%H:%M:%SZ)) ====="

  # WCF_TEST_EXTRA is split into words on purpose: it carries flags.
  # shellcheck disable=SC2086
  if [ -n "$timeout_bin" ]; then
    "$timeout_bin" -s KILL "$file_timeout_s" \
      bash "$root/tools/device_test.sh" ios "integration_test/$(basename "$f")" \
      --verbose --reporter expanded ${WCF_TEST_EXTRA:-} >"$out" 2>&1 &
    test_pid=$!
    watchdog_pid=""
  else
    bash "$root/tools/device_test.sh" ios "integration_test/$(basename "$f")" \
      --verbose --reporter expanded ${WCF_TEST_EXTRA:-} >"$out" 2>&1 &
    test_pid=$!
    (
      sleep "$file_timeout_s"
      : >"$flag"
      kill -TERM -- "-$test_pid" 2>/dev/null
      sleep 5
      kill -KILL -- "-$test_pid" 2>/dev/null
    ) >/dev/null 2>&1 &
    watchdog_pid=$!
  fi

  # Stream the file's output to the job log as it is written.
  tail -n +1 -f "$out" &
  tail_pid=$!

  wait "$test_pid" 2>/dev/null
  rc=$?
  if [ -n "$watchdog_pid" ]; then
    kill "$watchdog_pid" 2>/dev/null
    wait "$watchdog_pid" 2>/dev/null
  fi
  sleep 1 # let tail print the last lines
  kill "$tail_pid" 2>/dev/null
  wait "$tail_pid" 2>/dev/null

  if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ] || [ -e "$flag" ]; then
    rm -f "$flag"
    rc=124
    echo "ios_device_diag: $name was killed after ${file_timeout_s}s; collecting evidence" >&2
    collect_timeout_evidence "$name"
    summary="$summary$name: TIMEOUT"$'\n'
    failed=1
  elif [ "$rc" -ne 0 ]; then
    echo "ios_device_diag: $name failed (exit $rc)" >&2
    summary="$summary$name: FAILED (exit $rc)"$'\n'
    failed=1
  else
    summary="$summary$name: ok"$'\n'
  fi
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
