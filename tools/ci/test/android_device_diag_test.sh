#!/usr/bin/env bash
#
# android_device_diag_test.sh — dry-run test of tools/ci/android_device_diag.sh
# without a device: the retry rule, the summary, the exit code, the budget and
# the per-attempt timeout, against canned `flutter test` output.
#
# Usage: bash tools/ci/test/android_device_diag_test.sh
#
# It copies the script into a scratch tree next to a stub tools/device_test.sh
# (replays canned output per file and attempt), and puts stub `adb` and
# `timeout` (macOS has neither GNU timeout nor gtimeout) first on PATH. It
# never touches a device. Exit code 0 when every case passes. Takes ~15 s (two
# cases wait out a real 2-second timeout and a 4-second "slow" test).
#
# Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
# Not affiliated with or endorsed by Trust Wallet.

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script_src="$here/../android_device_diag.sh"
base="$(mktemp -d "${TMPDIR:-/tmp}/android_diag_test.XXXXXX")"
trap 'rm -rf "$base"' EXIT

pass=0
fail=0
check() { # check <description> <command...>
  local what="$1"
  shift
  if "$@"; then
    pass=$((pass + 1))
    echo "  ok   $what"
  else
    fail=$((fail + 1))
    echo "  FAIL $what"
  fi
}

# ---- stubs ------------------------------------------------------------------

bin="$base/bin"
mkdir -p "$bin"

cat >"$bin/adb" <<'EOF'
#!/usr/bin/env bash
echo "adb $*" >>"$ADB_LOG"
case "$*" in
  *get-state*) echo device ;;
  *" root"*) echo "adbd cannot run as root in production builds" ;;
  *" pull "*) exit 1 ;;
esac
exit 0
EOF

# `timeout -s KILL <n>[sm] cmd...`: just enough of GNU timeout.
cat >"$bin/timeout" <<'EOF'
#!/usr/bin/env bash
shift 2
lim="$1"
shift
n="${lim%[sm]}"
case "$lim" in *m) n=$((n * 60)) ;; esac
"$@" &
pid=$!
(sleep "$n" && kill -KILL "$pid" 2>/dev/null) >/dev/null 2>&1 &
watcher=$!
wait "$pid"
rc=$?
kill "$watcher" 2>/dev/null
exit "$rc"
EOF
chmod +x "$bin/adb" "$bin/timeout"

# Replays $SCEN/<name>.<attempt>.{out,rc,hang,sleep}; counts attempts.
stub_device_test() {
  cat >"$1" <<'EOF'
#!/usr/bin/env bash
# args: android integration_test/<name>.dart --verbose --reporter expanded ...
name="$(basename "$2" .dart)"
n=$(($(cat "$SCEN/count_$name" 2>/dev/null || echo 0) + 1))
echo "$n" >"$SCEN/count_$name"
echo "$*" >>"$SCEN/args_$name"
[ -f "$SCEN/$name.$n.sleep" ] && sleep "$(cat "$SCEN/$name.$n.sleep")"
[ -f "$SCEN/$name.$n.out" ] && cat "$SCEN/$name.$n.out"
[ -f "$SCEN/$name.$n.hang" ] && exec sleep 60
exit "$(cat "$SCEN/$name.$n.rc" 2>/dev/null || echo 0)"
EOF
}

# ---- scenario helpers -------------------------------------------------------

new_tree() { # new_tree <case>; sets tree, SCEN, ADB_LOG, diag, out
  tree="$base/$1"
  SCEN="$tree/scen"
  ADB_LOG="$tree/adb.log"
  diag="$tree/diag"
  out="$tree/run.out"
  mkdir -p "$tree/tools/ci" "$tree/example/integration_test" "$tree/example/android/app" "$SCEN"
  cp "$script_src" "$tree/tools/ci/android_device_diag.sh"
  stub_device_test "$tree/tools/device_test.sh"
  echo 'applicationId = "dev.test.app"' >"$tree/example/android/app/build.gradle.kts"
  : >"$ADB_LOG"
  export SCEN ADB_LOG
}

file() { : >"$tree/example/integration_test/$1_test.dart"; }
canned() { # canned <name> <attempt> <rc>  (output from stdin)
  cat >"$SCEN/${1}_test.$2.out"
  echo "$3" >"$SCEN/${1}_test.$2.rc"
}
attempts() { cat "$SCEN/count_${1}_test" 2>/dev/null || echo 0; }
summary_has() { sed -n '/^===== summary =====$/,$p' "$out" | grep -Fxq "$1"; }
adb_has() { grep -Fq -- "$1" "$ADB_LOG"; }

run_diag() { # run_diag [VAR=value...]; sets rc
  env PATH="$bin:$PATH" WCF_ANDROID_DEVICE=emulator-5554 DIAG_DIR="$diag" \
    WCF_TEST_EXTRA="--no-enable-impeller" "$@" \
    bash "$tree/tools/ci/android_device_diag.sh" >"$out" 2>&1
  rc=$?
}

ATTACH_FAIL='[  +528 ms] Warning: Failed to start DDS: Failed to start Dart Development Service
00:00 +0 -1: loading /w/example/integration_test/X_test.dart [E]
  Failed to load "/w/example/integration_test/X_test.dart": Failed to start Dart Development Service
00:00 +0 -1: Some tests failed.'
IOS_ATTACH_FAIL='00:00 +0: loading /w/example/integration_test/X_test.dart
Error waiting for a debug connection: The log reader stopped unexpectedly, or never started.
00:00 +0 -1: Some tests failed.'
PASSING='00:00 +0: loading /w/example/integration_test/X_test.dart
00:03 +1: /w/example/integration_test/X_test.dart: clause 1
00:04 +2: All tests passed!'

# ---- case 1: the five classifications in one run ----------------------------

echo "case 1: classification, retry, summary"
new_tree c1
for n in a_ok b_attach c_started d_failure e_twice f_ios; do file "$n"; done
printf '%s\n' "$PASSING" | canned a_ok 1 0
printf '%s\n' "$ATTACH_FAIL" | canned b_attach 1 1
printf '%s\n' "$PASSING" | canned b_attach 2 0
# DDS text, but a test ran: a run in which tests started is never retried.
printf '%s\n%s\n' '00:03 +2: /w/example/integration_test/X_test.dart: clause 2' "$ATTACH_FAIL" | canned c_started 1 1
# a plain test failure, no attach text
printf '%s\n' '00:01 +1 -1: /w/example/integration_test/X_test.dart: clause 1 [E]' '00:02 +1 -1: Some tests failed.' | canned d_failure 1 1
printf '%s\n' "$ATTACH_FAIL" | canned e_twice 1 1
printf '%s\n' "$ATTACH_FAIL" | canned e_twice 2 1
printf '%s\n' "$IOS_ATTACH_FAIL" | canned f_ios 1 1
printf '%s\n' "$PASSING" | canned f_ios 2 0
run_diag
check "exit code is 1 when any file failed" test "$rc" -eq 1
check "ok file ran once" test "$(attempts a_ok)" -eq 1
check "attach failure, no test line: retried (2 attempts)" test "$(attempts b_attach)" -eq 2
check "…and reported 'ok after retry'" summary_has "b_attach_test: ok after retry (Failed to start Dart Development Service on attempt 1)"
check "test started + DDS text: NOT retried" test "$(attempts c_started)" -eq 1
check "…reported FAILED (exit 1)" summary_has "c_started_test: FAILED (exit 1)"
check "test failure: NOT retried" test "$(attempts d_failure)" -eq 1
check "…reported FAILED (exit 1)" summary_has "d_failure_test: FAILED (exit 1)"
check "attach failure on both attempts: retried once only" test "$(attempts e_twice)" -eq 2
check "…reported FAILED after retry (exit 1)" summary_has "e_twice_test: FAILED after retry (exit 1)"
check "iOS-style attach error is retried too" test "$(attempts f_ios)" -eq 2
check "…reported 'ok after retry'" summary_has "f_ios_test: ok after retry (Error waiting for a debug connection on attempt 1)"
check "plain ok file: 'ok'" summary_has "a_ok_test: ok"
check "files run in sorted order" bash -c "grep -o '===== [a-f]_[a-z]*_test' '$out' | awk '!s[\$0]++' | tr '\n' ' ' | grep -Fq '===== a_ok_test ===== b_attach_test ===== c_started_test ===== d_failure_test ===== e_twice_test ===== f_ios_test'"
check "retry log kept next to the first log" test -f "$diag/flutter_test_b_attach_test.retry.txt" -a -f "$diag/flutter_test_b_attach_test.txt"
check "no retry log for a file that was not retried" test ! -e "$diag/flutter_test_d_failure_test.retry.txt"
check "force-stop of the app before a retry" adb_has "-s emulator-5554 shell am force-stop dev.test.app"
check "forwards removed before a retry" adb_has "-s emulator-5554 forward --remove-all"
check "cleanup ran 3 times (b, e, f), not for c or d" test "$(grep -c 'forward --remove-all' "$ADB_LOG")" -eq 3
check "flutter test args: one file, verbose, expanded, extra flags" grep -Fxq "android integration_test/a_ok_test.dart --verbose --reporter expanded --no-enable-impeller" "$SCEN/args_a_ok_test"

# ---- case 2: all green ------------------------------------------------------

echo "case 2: all files pass"
new_tree c2
file a_ok
file b_ok
printf '%s\n' "$PASSING" | canned a_ok 1 0
printf '%s\n' "$PASSING" | canned b_ok 1 0
run_diag
check "exit code 0" test "$rc" -eq 0
check "summary lists both as ok" bash -c "sed -n '/^===== summary =====\$/,\$p' '$out' | grep -c ': ok\$' | grep -qx 2"
check "no retry cleanup" test "$(grep -c 'forward --remove-all' "$ADB_LOG")" -eq 0

# ---- case 3: per-attempt timeout --------------------------------------------

echo "case 3: attempt killed by its timeout is not retried"
new_tree c3
file a_hang
file b_ok
: >"$SCEN/a_hang_test.1.hang"
printf '%s\n' "$ATTACH_FAIL" >"$SCEN/a_hang_test.1.out" # attach text present, but the kill wins
printf '%s\n' "$PASSING" | canned b_ok 1 0
run_diag WCF_FILE_TIMEOUT_S=2
check "exit code 1" test "$rc" -eq 1
check "hung file reported TIMEOUT (exit 137)" summary_has "a_hang_test: TIMEOUT (exit 137)"
check "hung file ran once (a timeout is never retried)" test "$(attempts a_hang)" -eq 1
check "the next file still ran and passed" summary_has "b_ok_test: ok"
check "evidence collected right after the kill" test -f "$diag/screen_hang_a_hang_test.png" -a -f "$diag/activity_hang_a_hang_test.txt"

# ---- case 4: budget ---------------------------------------------------------

echo "case 4: under 120 s of budget left: no retry"
new_tree c4
file a_attach
file b_ok
printf '%s\n' "$ATTACH_FAIL" | canned a_attach 1 1
printf '%s\n' "$PASSING" | canned b_ok 1 0
run_diag WCF_TOTAL_BUDGET_S=100
check "exit code 1" test "$rc" -eq 1
check "attach failure not retried for lack of budget" test "$(attempts a_attach)" -eq 1
check "…reported FAILED (exit 1)" summary_has "a_attach_test: FAILED (exit 1)"
check "the next file ran" summary_has "b_ok_test: ok"

echo "case 5: budget exhausted: later file is not started"
new_tree c5
file a_slow
file b_ok
echo 4 >"$SCEN/a_slow_test.1.sleep"
printf '%s\n' "$PASSING" | canned a_slow 1 0
printf '%s\n' "$PASSING" | canned b_ok 1 0
run_diag WCF_TOTAL_BUDGET_S=33
check "exit code 1" test "$rc" -eq 1
check "first file ok" summary_has "a_slow_test: ok"
check "second file NOT RUN" summary_has "b_ok_test: NOT RUN (time budget exhausted)"
check "second file never launched" test "$(attempts b_ok)" -eq 0

# ---- case 6: exit code 2 ----------------------------------------------------

echo "case 6: usage errors exit 2"
new_tree c6
env PATH="$bin:$PATH" DIAG_DIR="$diag" bash "$tree/tools/ci/android_device_diag.sh" >/dev/null 2>&1
check "missing WCF_ANDROID_DEVICE" test "$?" -eq 2
env PATH="$bin:$PATH" WCF_ANDROID_DEVICE=emulator-5554 bash "$tree/tools/ci/android_device_diag.sh" >/dev/null 2>&1
check "missing DIAG_DIR" test "$?" -eq 2
env PATH="/usr/bin:/bin" WCF_ANDROID_DEVICE=emulator-5554 DIAG_DIR="$diag" bash "$tree/tools/ci/android_device_diag.sh" >/dev/null 2>&1
check "adb not on PATH" test "$?" -eq 2
run_diag
check "no test files" test "$rc" -eq 2

echo
echo "android_device_diag_test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
