#!/usr/bin/env bash
#
# run_native_tests.sh — `melos run test:native`: the `native`-tagged unit tests
# of wallet_core_flutter_bindings (`dart test`, or `flutter test --no-pub` when
# WCF_NO_NETWORK=1, set by test:no-network) and wallet_core_flutter
# (`flutter test --no-pub`), against the real host library, with an absent library a
# failure rather than a skip.
#
# Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
# Not affiliated with or endorsed by Trust Wallet.
#
# WHY A FILE AND NOT AN INLINE `sh -c`. melos passes a script's body to the
# shell unquoted, so `sh -c 'A=1 B=2 dart test'` reached the shell as
# `sh -c 'A=1` plus loose words: the inner shell ran one assignment, exited 0,
# and the gate reported success having run nothing. Here every step is a line
# of its own and the exit status is the tests'.
#
# WHICH LIBRARY. WCF_NATIVE_LIB when set, and authoritative: a path that does
# not exist fails the run, nothing else is tried. Unset, the git-ignored copy a
# developer keeps at third_party/wcf-native/macos/arm64_x86_64/ when present,
# otherwise the path `melos run native:host-lib` writes to. This file never
# downloads anything and never builds anything.
#
# Both packages always run, so one failing does not hide the other's result;
# the exit status is non-zero when either fails.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"

repo_copy="$root/third_party/wcf-native/macos/arm64_x86_64/libTrustWalletCore.dylib"
host_lib_out="${WCF_NATIVE_OUT:-${TMPDIR:-/tmp}/wcf-native}/artifacts/macos/arm64_x86_64/libTrustWalletCore.dylib"

if [ -z "${WCF_NATIVE_LIB:-}" ]; then
  if [ -f "$repo_copy" ]; then
    WCF_NATIVE_LIB="$repo_copy"
  else
    WCF_NATIVE_LIB="$host_lib_out"
  fi
fi
export WCF_NATIVE_LIB
export WCF_NATIVE_REQUIRED=1

if [ ! -f "$WCF_NATIVE_LIB" ]; then
  echo "test:native: no host library at WCF_NATIVE_LIB=$WCF_NATIVE_LIB" >&2
  echo "test:native: build it with \`melos run native:host-lib\`, or point" \
    "WCF_NATIVE_LIB at a libTrustWalletCore built from the pinned commit." >&2
  exit 1
fi

echo "test:native: WCF_NATIVE_LIB=$WCF_NATIVE_LIB"

status=0

bindings_cmd="dart test"
# WCF_NO_NETWORK is set by test:no-network. `dart test` has no `--no-pub`; its implicit
# resolution re-checks online (pub.dev advisories) whenever the checkout leaves
# pubspec.yaml newer than pubspec.lock or the lock newer than package_config.json, and
# pub never rewrites an unchanged lockfile, so an offline `dart pub get` does not
# prevent it; under the sandbox that fetch is SIGKILLed. Analytics is handled
# separately by FLUTTER_SUPPRESS_ANALYTICS in run_no_network_test.sh.
if [ "${WCF_NO_NETWORK:-0}" = "1" ]; then
  # flutter test supports --no-pub, which skips dependency resolution
  bindings_cmd="flutter test --no-pub"
fi

echo "test:native: wallet_core_flutter_bindings ($bindings_cmd --tags native)"
(cd "$root/packages/wallet_core_flutter_bindings" && $bindings_cmd --tags native) \
  || status=1

echo "test:native: wallet_core_flutter (flutter test --no-pub --tags native)"
(cd "$root/packages/wallet_core_flutter" && flutter test --no-pub --tags native) \
  || status=1

if [ "$status" -ne 0 ]; then
  echo "test:native: FAILED" >&2
fi
exit "$status"
