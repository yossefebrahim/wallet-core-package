#!/usr/bin/env bash
#
# run_no_network_test.sh — Process-level OS sandbox denying network
# access (macOS only). Proves that native code and isolates cannot reach the network.
# Layer A = IOOverrides/HttpOverrides in no_network_test.dart recording attempts.
# Layer B = this sandbox. Note that loopback is allowed.
# Usage: Requires `melos bootstrap` and a prior `melos run test:native` to warm the
# build-hook artifact cache (the native package's hook downloads the macOS library on
# first use, and inside the sandbox that download is SIGKILLed).
#
# Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
# Not affiliated with or endorsed by Trust Wallet.

set -euo pipefail

if [ "$(uname)" != "Darwin" ]; then
  echo "test:no-network: macOS only until a Linux host library exists (T1.17a)" >&2
  exit 2
fi

root="$(cd "$(dirname "$0")/../.." && pwd)"


if [ ! -f "$root/.dart_tool/hooks_runner/shared/wallet_core_flutter_native/build/artifacts/macos/arm64_x86_64/libTrustWalletCore.dylib" ]; then
  echo "test:no-network: run 'melos run test:native' first to warm the build-hook artifact cache" >&2
  exit 1
fi

export FLUTTER_SUPPRESS_ANALYTICS=true
export WCF_NO_NETWORK=1

profile=$(mktemp "${TMPDIR:-/tmp}/wcf_no_network.XXXXXX")
tmp_srv=$(mktemp -d)

PORT=$(( (RANDOM % 10000) + 10000 ))
python3 -m http.server --bind 127.0.0.1 --directory "$tmp_srv" "$PORT" >/dev/null 2>&1 &
SRV_PID=$!

cleanup() {
  rm -f "$profile"
  kill $SRV_PID 2>/dev/null || true
  wait $SRV_PID 2>/dev/null || true
  rm -rf "$tmp_srv"
}
trap cleanup EXIT INT TERM

cat << 'PROFILE' > "$profile"
(version 1)
(allow default)
(deny network-outbound (with send-signal SIGKILL))
(allow network-outbound (remote ip "localhost:*"))
PROFILE

echo "test:no-network: verifying sandbox (Layer B negative control)..."
set +e
sandbox-exec -f "$profile" /usr/bin/curl -sS -m 5 https://1.1.1.1 >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 137 ] || { echo "test:no-network: FAIL: outbound probe exited $rc, expected 137 (SIGKILL by sandbox)" >&2; exit 1; }

up=0
for i in {1..50}; do
  if curl -s -o /dev/null http://127.0.0.1:$PORT; then
    up=1
    break
  fi
  sleep 0.1
done
if [ $up -eq 0 ]; then
  echo "test:no-network: FAIL: loopback probe server did not start" >&2
  exit 1
fi

if ! sandbox-exec -f "$profile" /usr/bin/curl -sS -m 5 http://127.0.0.1:$PORT >/dev/null 2>&1; then
  echo "test:no-network: FAIL: sandbox blocked loopback network access" >&2
  exit 1
fi
echo "test:no-network: loopback allowed (OK)"

sandbox-exec -f "$profile" "$root/tools/native_build/run_native_tests.sh" "$@"
