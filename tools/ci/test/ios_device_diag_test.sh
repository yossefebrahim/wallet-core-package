#!/usr/bin/env bash
#
# ios_device_diag_test.sh — dry-run test of tools/ci/ios_device_diag.sh without
# a simulator: which first attempts are retried, against canned `flutter test`
# output.
#
# Usage: bash tools/ci/test/ios_device_diag_test.sh
#        IOS_SCRIPT=<path to another copy of the script> bash tools/ci/test/ios_device_diag_test.sh
#
# It copies the script into a scratch tree next to a stub tools/device_test.sh
# (replays canned output per file and attempt) and puts a stub `xcrun` first on
# PATH; HOME is a scratch directory. It never touches a simulator. Exit code 0
# when every case passes. Takes ~10 s (one case waits out a real 2-second
# watchdog).
#
# Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
# Not affiliated with or endorsed by Trust Wallet.

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script_src="${IOS_SCRIPT:-$here/../ios_device_diag.sh}"
base="$(mktemp -d "${TMPDIR:-/tmp}/ios_diag_test.XXXXXX")"
trap 'rm -rf "$base"' EXIT

udid=00000000-0000-0000-0000-000000000001

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
mkdir -p "$bin" "$base/home"

cat >"$bin/xcrun" <<EOF
#!/usr/bin/env bash
case "\$*" in
  "simctl list devices booted -j") echo '{ "devices" : { "x" : [ { "udid" : "$udid" } ] } }' ;;
esac
exit 0
EOF
chmod +x "$bin/xcrun"

# Replays $SCEN/<name>.<attempt>.{out,rc,hang}; counts attempts.
stub_device_test() {
  cat >"$1" <<'EOF'
#!/usr/bin/env bash
# args: ios integration_test/<name>.dart --verbose --reporter expanded ...
name="$(basename "$2" .dart)"
n=$(($(cat "$SCEN/count_$name" 2>/dev/null || echo 0) + 1))
echo "$n" >"$SCEN/count_$name"
[ -f "$SCEN/$name.$n.out" ] && cat "$SCEN/$name.$n.out"
[ -f "$SCEN/$name.$n.hang" ] && exec sleep 60
exit "$(cat "$SCEN/$name.$n.rc" 2>/dev/null || echo 0)"
EOF
}

# ---- scenario helpers -------------------------------------------------------

new_tree() { # new_tree <case>; sets tree, SCEN, diag, out
  tree="$base/$1"
  SCEN="$tree/scen"
  diag="$tree/diag"
  out="$tree/run.out"
  mkdir -p "$tree/tools/ci" "$tree/example/integration_test" "$SCEN"
  cp "$script_src" "$tree/tools/ci/ios_device_diag.sh"
  stub_device_test "$tree/tools/device_test.sh"
  export SCEN
}

file() { : >"$tree/example/integration_test/$1_test.dart"; }
canned() { # canned <name> <attempt> <rc>  (output from stdin)
  cat >"$SCEN/${1}_test.$2.out"
  echo "$3" >"$SCEN/${1}_test.$2.rc"
}
attempts() { cat "$SCEN/count_${1}_test" 2>/dev/null || echo 0; }
summary_has() { sed -n '/^===== summary =====$/,$p' "$out" | grep -Fxq -- "$1"; }

run_diag() { # run_diag [VAR=value...]; sets rc
  env PATH="$bin:$PATH" HOME="$base/home" WCF_IOS_DEVICE="$udid" DIAG_DIR="$diag" "$@" \
    bash "$tree/tools/ci/ios_device_diag.sh" >"$out" 2>&1
  rc=$?
}

# `flutter test` ends a load error with `+0 -1: Some tests failed.` too.
ATTACH_FAIL='00:00 +0: loading /w/example/integration_test/X_test.dart
Error waiting for a debug connection: The log reader stopped unexpectedly, or never started.
00:00 +0 -1: Some tests failed.'
PASSING='00:00 +0: loading /w/example/integration_test/X_test.dart
00:03 +1: /w/example/integration_test/X_test.dart: clause 1
00:04 +2: All tests passed!'

# ---- case 1: classification -------------------------------------------------

echo "case 1: classification and retry"
new_tree c1
for n in a_attach b_started c_failure d_twice e_ok; do file "$n"; done
# the reported bug: attach failure, only `loading`, closing line, no watchdog
printf '%s\n' "$ATTACH_FAIL" | canned a_attach 1 1
printf '%s\n' "$PASSING" | canned a_attach 2 0
# error text, but a test ran
printf '%s\n%s\n' '00:03 +2: /w/example/integration_test/X_test.dart: clause 2' "$ATTACH_FAIL" | canned b_started 1 1
# a plain test failure
printf '%s\n' '00:01 +1 -1: /w/example/integration_test/X_test.dart: clause 1 [E]' '00:02 +1 -1: Some tests failed.' | canned c_failure 1 1
printf '%s\n' "$ATTACH_FAIL" | canned d_twice 1 1
printf '%s\n' "$ATTACH_FAIL" | canned d_twice 2 1
printf '%s\n' "$PASSING" | canned e_ok 1 0
run_diag
check "exit code is 1 when any file failed" test "$rc" -eq 1
check "attach error + loading + closing line: retried (2 attempts)" test "$(attempts a_attach)" -eq 2
check "…reported 'ok after retry'" summary_has "a_attach_test: ok after retry (VM-service discovery failed on attempt 1)"
check "started test + attach error: NOT retried" test "$(attempts b_started)" -eq 1
check "…reported FAILED (exit 1)" summary_has "b_started_test: FAILED (exit 1)"
check "test failure: NOT retried" test "$(attempts c_failure)" -eq 1
check "…reported FAILED (exit 1)" summary_has "c_failure_test: FAILED (exit 1)"
check "attach failure on both attempts: retried once only" test "$(attempts d_twice)" -eq 2
check "…reported FAILED after retry (exit 1)" summary_has "d_twice_test: FAILED after retry (exit 1)"
check "plain ok file: ran once, 'ok'" test "$(attempts e_ok)" -eq 1
check "…reported ok" summary_has "e_ok_test: ok"
check "retry log kept next to the first log" test -f "$diag/flutter_test_a_attach_test.retry.txt" -a -f "$diag/flutter_test_a_attach_test.txt"
check "no retry log for a file that was not retried" test ! -e "$diag/flutter_test_c_failure_test.retry.txt"

# ---- case 2: watchdog -------------------------------------------------------

echo "case 2: watchdog kill"
new_tree c2
file a_hang_error
file b_hang_quiet
# killed by the watchdog, the log has the attach error and no test line: retried
printf '%s\n' '00:00 +0: loading /w/example/integration_test/X_test.dart' 'Error waiting for a debug connection: the log reader never started.' >"$SCEN/a_hang_error_test.1.out"
: >"$SCEN/a_hang_error_test.1.hang"
printf '%s\n' "$PASSING" | canned a_hang_error 2 0
# killed by the watchdog with no attach error: a hang, not this tooling failure
printf '%s\n' '00:00 +0: loading /w/example/integration_test/X_test.dart' >"$SCEN/b_hang_quiet_test.1.out"
: >"$SCEN/b_hang_quiet_test.1.hang"
run_diag WCF_FILE_TIMEOUT_S=2
check "exit code is 1 (the quiet hang failed)" test "$rc" -eq 1
check "watchdog kill, attach error, no test line: retried" test "$(attempts a_hang_error)" -eq 2
check "…reported 'ok after retry'" summary_has "a_hang_error_test: ok after retry (VM-service discovery failed on attempt 1)"
check "watchdog kill without the attach error: NOT retried" test "$(attempts b_hang_quiet)" -eq 1
check "…reported TIMEOUT" summary_has "b_hang_quiet_test: TIMEOUT"

# ---- case 3: usage ----------------------------------------------------------

echo "case 3: usage errors exit 2"
new_tree c3
env PATH="$bin:$PATH" DIAG_DIR="$diag" bash "$tree/tools/ci/ios_device_diag.sh" >/dev/null 2>&1
check "missing WCF_IOS_DEVICE" test "$?" -eq 2
run_diag
check "no test files" test "$rc" -eq 2

echo
echo "ios_device_diag_test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
