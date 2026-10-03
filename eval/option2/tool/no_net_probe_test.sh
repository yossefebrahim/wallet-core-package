#!/usr/bin/env bash
# eval/option2/tool/no_net_probe_test.sh — the network-denial probe's
# classification, with the strings `nc -v -z` prints on macOS (and the empty
# output of `nc -z`, which hid the denial in the first version).
#
# Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
# Not affiliated with or endorsed by Trust Wallet.
#
# Usage: bash eval/option2/tool/no_net_probe_test.sh   (run_eval.sh runs it in
# its preflight). Exit 0 when every case classifies as expected.

set -uo pipefail
# shellcheck source=no_net_probe.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/no_net_probe.sh"

refused='nc: connectx to 127.0.0.1 port 9 (tcp) failed: Connection refused'
denied='nc: connectx to 127.0.0.1 port 9 (tcp) failed: Operation not permitted'
empty=''

failures=0
check() { # name expected(applies|not) control denied
  local got verdict
  if verdict="$(no_net_classify "$3" "$4")"; then got=applies; else got=not; fi
  if [ "$got" = "$2" ]; then
    printf 'ok   %s: %s\n' "$1" "$verdict"
  else
    printf 'FAIL %s: expected %s, got %s (%s)\n' "$1" "$2" "$got" "$verdict"
    failures=$((failures + 1))
  fi
}

check 'refused, then not permitted: the profile applies' applies "$refused" "$denied"
check 'refused, then empty (nc -z without -v)' not "$refused" "$empty"
check 'refused both times: the profile did not apply' not "$refused" "$refused"
check 'empty control' not "$empty" "$denied"
check 'not permitted both times: already denied outside the profile' not "$denied" "$denied"
check 'empty both times' not "$empty" "$empty"
check 'multi-line output is still read' applies \
  "$(printf 'warning\n%s\n' "$refused")" "$(printf 'warning\n%s\n' "$denied")"

# `nc -z` alone prints nothing on success or failure; without -v every run
# classifies as "no output" (the first version's defect).
case " ${NO_NET_PROBE[*]} " in
  *' -v '*) echo "ok   the probe runs nc with -v: ${NO_NET_PROBE[*]}" ;;
  *) echo "FAIL the probe runs nc without -v: ${NO_NET_PROBE[*]}"; failures=$((failures + 1)) ;;
esac

if [ "$failures" -ne 0 ]; then
  echo "no_net_probe_test.sh: $failures case(s) failed" >&2
  exit 1
fi
echo "no_net_probe_test.sh: all cases passed"
