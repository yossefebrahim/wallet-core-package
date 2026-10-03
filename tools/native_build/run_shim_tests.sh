#!/usr/bin/env bash
#
# run_shim_tests.sh — the `shim`-tagged tests of wallet_core_flutter (T1.13,
# DECISION-1 evaluation of Approach B) against the shim host library, with an
# absent library a FAILURE rather than a skip.
#
# Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
# Not affiliated with or endorsed by Trust Wallet.
#
# WHY THIS EXISTS. The shim tests skip themselves when the shim library is
# absent, so that `melos run test` and `melos run test:native` stay green on
# the standard library. That makes a run that is *supposed* to exercise the
# shim able to pass by skipping everything. This script sets
# WCF_NATIVE_SHIM_REQUIRED=1, which turns the skip into a load failure, and
# then also requires that the run reported at least one passing test and no
# skipped one.
#
# WHICH LIBRARY. WCF_NATIVE_SHIM_LIB when set, and authoritative; otherwise
# third_party/wcf-native-shim/macos/arm64_x86_64/libTrustWalletCore.dylib.
# Build it with build_apple.sh --with-shim (see README.md). This file never
# builds or downloads anything.
#
# THE STANDARD LIBRARY. Some shim tests compare against the standard host
# library (Approach A's reference signature, the same-image refusal); they use
# WCF_NATIVE_LIB with the same defaults as run_native_tests.sh and fall back to
# the shim library, or report a skip, when it is absent — which this script
# then treats as a failure.
#
# Usage: bash tools/native_build/run_shim_tests.sh
# (No melos script: the root pubspec.yaml is not this evaluation's to change.)

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"

if [ -z "${WCF_NATIVE_SHIM_LIB:-}" ]; then
  WCF_NATIVE_SHIM_LIB="$root/third_party/wcf-native-shim/macos/arm64_x86_64/libTrustWalletCore.dylib"
fi
export WCF_NATIVE_SHIM_LIB
export WCF_NATIVE_SHIM_REQUIRED=1

if [ -z "${WCF_NATIVE_LIB:-}" ]; then
  repo_copy="$root/third_party/wcf-native/macos/arm64_x86_64/libTrustWalletCore.dylib"
  if [ -f "$repo_copy" ]; then
    WCF_NATIVE_LIB="$repo_copy"
    export WCF_NATIVE_LIB
  fi
fi

if [ ! -f "$WCF_NATIVE_SHIM_LIB" ]; then
  echo "test:shim: no shim library at WCF_NATIVE_SHIM_LIB=$WCF_NATIVE_SHIM_LIB" >&2
  echo "test:shim: build it with tools/native_build/build_apple.sh --with-shim" >&2
  exit 1
fi

echo "test:shim: WCF_NATIVE_SHIM_LIB=$WCF_NATIVE_SHIM_LIB"
echo "test:shim: WCF_NATIVE_LIB=${WCF_NATIVE_LIB:-<unset>}"

log="$(mktemp "${TMPDIR:-/tmp}/wcf-shim-tests.XXXXXXXX")"
trap 'rm -f -- "$log"' EXIT

(cd "$root/packages/wallet_core_flutter" && flutter test --tags shim) 2>&1 | tee "$log"
status=${PIPESTATUS[0]}

# The final summary line, e.g. "00:02 +22: All tests passed!" or
# "00:02 +20 ~2: All tests passed!" — a "~" means something skipped.
summary=$(grep -E '\+[0-9]+.*: (All tests passed!|Some tests failed\.)' "$log" | tail -1)
if [ "$status" -ne 0 ]; then
  echo "test:shim: FAILED" >&2
  exit "$status"
fi
case $summary in
  *'~'*)
    echo "test:shim: FAILED — tests were skipped in a run that must not skip: $summary" >&2
    exit 1 ;;
  *'+0:'*|'')
    echo "test:shim: FAILED — no test ran" >&2
    exit 1 ;;
esac
echo "test:shim: passed, none skipped"
