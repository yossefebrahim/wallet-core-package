#!/usr/bin/env bash
#
# device_test.sh — run example/integration_test on one already-running device.
#
# Usage: tools/device_test.sh android|ios
#
#   android  needs WCF_ANDROID_DEVICE, an adb serial (for example emulator-5554),
#            and `adb -s <serial> get-state` must report `device`.
#   ios      needs WCF_IOS_DEVICE, a simulator UDID, and that UDID must be listed
#            by `xcrun simctl list devices booted`.
#
# The script never starts a device and never picks one: the caller names the
# device, so a run can never land on a device the caller did not mean. A missing
# variable or a device that is not up prints the remedy and exits 2.
#
# Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
# Not affiliated with or endorsed by Trust Wallet.

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"

usage() {
  echo "usage: tools/device_test.sh android|ios" >&2
  exit 2
}

[ "$#" -eq 1 ] || usage

case "$1" in
  android)
    id="${WCF_ANDROID_DEVICE:-}"
    if [ -z "$id" ]; then
      echo "device_test: WCF_ANDROID_DEVICE is not set." >&2
      echo "  Start an emulator or connect a device, read its serial from 'adb devices'," >&2
      echo "  then run: WCF_ANDROID_DEVICE=<serial> melos run test:android" >&2
      exit 2
    fi
    if ! command -v adb >/dev/null 2>&1; then
      echo "device_test: adb is not on PATH (Android SDK platform-tools)." >&2
      exit 2
    fi
    state="$(adb -s "$id" get-state 2>/dev/null || true)"
    if [ "$state" != "device" ]; then
      echo "device_test: Android device '$id' is not online (adb get-state: '${state:-none}')." >&2
      echo "  'adb devices' lists what is attached; start the emulator or fix WCF_ANDROID_DEVICE." >&2
      exit 2
    fi
    ;;
  ios)
    id="${WCF_IOS_DEVICE:-}"
    if [ -z "$id" ]; then
      echo "device_test: WCF_IOS_DEVICE is not set." >&2
      echo "  Boot a simulator ('xcrun simctl boot <udid>'), read its UDID from" >&2
      echo "  'xcrun simctl list devices booted', then run:" >&2
      echo "  WCF_IOS_DEVICE=<udid> melos run test:ios" >&2
      exit 2
    fi
    if ! command -v xcrun >/dev/null 2>&1; then
      echo "device_test: xcrun is not available (Xcode command line tools)." >&2
      exit 2
    fi
    booted="$(xcrun simctl list devices booted -j 2>/dev/null || true)"
    if ! printf '%s' "$booted" | grep -Fq "\"udid\" : \"$id\""; then
      echo "device_test: simulator '$id' is not booted." >&2
      echo "  'xcrun simctl list devices booted' lists the booted ones; boot it with" >&2
      echo "  'xcrun simctl boot $id' or fix WCF_IOS_DEVICE." >&2
      exit 2
    fi
    ;;
  *)
    usage
    ;;
esac

cd "$root/example"
exec flutter test integration_test -d "$id"
