#!/usr/bin/env bash
#
# materialize_libcxx.sh — put the NDK's own libc++_shared.so into this
# fixture plugin's jniLibs, so a consumer app that also depends on
# wallet_core_flutter has two contributors of lib/<abi>/libc++_shared.so
# (PRD §12.2 step 9).
#
# Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
# Not affiliated with or endorsed by Trust Wallet.
#
# The .so is never committed. It is 1 MB per ABI, it is the NDK's file, and it
# is the exact file the duplicate is about — copying it at run time keeps the
# fixture honest and the repository small.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: materialize_libcxx.sh [--ndk PATH] [--dest DIR] [--abis "a b c"]

Options:
  --ndk PATH    NDK root. Default $ANDROID_NDK, then $ANDROID_NDK_HOME, then
                the highest-numbered directory under
                $ANDROID_HOME/ndk (or ~/Library/Android/sdk/ndk).
  --dest DIR    Where the <abi>/libc++_shared.so tree goes. Default this
                plugin's android/src/main/jniLibs, which is git-ignored.
  --abis LIST   Space-separated ABIs. Default "arm64-v8a armeabi-v7a x86_64".
  --clean       Remove the materialised libraries and exit.
  -h, --help    This text.

Two NDK layouts are handled: r27 and earlier keep the library under
sources/cxx-stl/llvm-libc++/libs/<abi>/, and r28 removed that tree in favour of
the sysroot copy under the target triple.
EOF
}

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ndk=''
dest="$here/../android/src/main/jniLibs"
abis='arm64-v8a armeabi-v7a x86_64'
clean=0

while (($#)); do
  case $1 in
    --ndk) ndk=${2:?--ndk needs a value}; shift 2 ;;
    --dest) dest=${2:?--dest needs a value}; shift 2 ;;
    --abis) abis=${2:?--abis needs a value}; shift 2 ;;
    --clean) clean=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; echo "error: unknown argument: $1" >&2; exit 1 ;;
  esac
done

if ((clean)); then
  for abi in $abis; do
    rm -f -- "$dest/$abi/libc++_shared.so"
    rmdir -- "$dest/$abi" 2>/dev/null || true
  done
  echo "removed materialised libraries under $dest" >&2
  exit 0
fi

if [[ -z $ndk ]]; then
  for candidate in "${ANDROID_NDK:-}" "${ANDROID_NDK_HOME:-}" "${ANDROID_NDK_ROOT:-}"; do
    if [[ -n $candidate && -d $candidate ]]; then ndk=$candidate; break; fi
  done
fi
if [[ -z $ndk ]]; then
  for root in "${ANDROID_HOME:-}/ndk" "${ANDROID_SDK_ROOT:-}/ndk" \
              "$HOME/Library/Android/sdk/ndk" "$HOME/Android/Sdk/ndk"; do
    [[ -d $root ]] || continue
    # Highest version by sort -V, which orders 28.2.x after 9.x.
    ndk=$(ls -1 "$root" | sort -V | tail -n1)
    ndk="$root/$ndk"
    break
  done
fi
[[ -n $ndk && -d $ndk ]] || {
  echo "error: no NDK found; pass --ndk" >&2
  exit 1
}

case $(uname -s) in
  Darwin) host=darwin-x86_64 ;;
  *) host=linux-x86_64 ;;
esac

triple_for() {
  case $1 in
    arm64-v8a) printf 'aarch64-linux-android' ;;
    armeabi-v7a) printf 'arm-linux-androideabi' ;;
    x86_64) printf 'x86_64-linux-android' ;;
    x86) printf 'i686-linux-android' ;;
    *) printf '' ;;
  esac
}

echo "NDK: $ndk" >&2
for abi in $abis; do
  triple=$(triple_for "$abi")
  source=''
  for candidate in \
    "$ndk/sources/cxx-stl/llvm-libc++/libs/$abi/libc++_shared.so" \
    "$ndk/toolchains/llvm/prebuilt/$host/sysroot/usr/lib/$triple/libc++_shared.so"
  do
    if [[ -f $candidate ]]; then source=$candidate; break; fi
  done
  if [[ -z $source ]]; then
    echo "warning: no libc++_shared.so for $abi under $ndk; skipped" >&2
    continue
  fi
  mkdir -p -- "$dest/$abi"
  cp -- "$source" "$dest/$abi/libc++_shared.so"
  echo "  $abi <- $source" >&2
done

echo "materialised under $dest (git-ignored; never commit the .so)" >&2
