# eval/option2/tool/no_net_probe.sh — sourced by run_eval.sh and by
# no_net_probe_test.sh. Bash.
#
# Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
# Not affiliated with or endorsed by Trust Wallet.
#
# Whether `sandbox-exec -p "$NO_NET_PROFILE"` really denies outbound
# connections on this host, decided from two runs of the same connect to a
# closed loopback port:
#
#   control  "$NO_NET_PROBE"[@]                        must say "Connection refused"
#   denied   sandbox-exec -p "$NO_NET_PROFILE" "$NO_NET_PROBE"[@]
#                                                      must say "Operation not permitted"
#
# Only that pair shows the profile is what refused the connect. `nc -z` prints
# nothing without `-v` (measured, Xcode 27.0 host), which is why the first
# version of this probe never classified a denial.

NO_NET_PROFILE='(version 1)(allow default)(deny network-outbound)'
NO_NET_PROBE=(/usr/bin/nc -v -z -G 2 127.0.0.1 9)

# no_net_classify CONTROL_OUTPUT DENIED_OUTPUT
# Prints "applies" and returns 0 when the pair is the expected one; otherwise
# prints why not and returns 1.
no_net_classify() {
  local control="${1//$'\n'/ }" denied="${2//$'\n'/ }"
  case "$control" in
    *'Connection refused'*) ;;
    *)
      printf 'the control connect did not say "Connection refused" (%s)' "${control:-no output}"
      return 1
      ;;
  esac
  case "$denied" in
    *'Operation not permitted'*)
      printf 'applies'
      return 0
      ;;
    *)
      printf 'the connect under sandbox-exec did not say "Operation not permitted" (%s)' "${denied:-no output}"
      return 1
      ;;
  esac
}
