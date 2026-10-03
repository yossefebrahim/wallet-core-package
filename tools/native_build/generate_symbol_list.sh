#!/usr/bin/env bash
#
# generate_symbol_list.sh — the canonical list of exported TW* C functions,
# derived from upstream's own headers at the pinned tag.
#
# Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
# Not affiliated with or endorsed by Trust Wallet.
#
# The list has two consumers and they must agree:
#   1. tools/native_build/build_apple.sh turns it into the linker's -u list.
#      Under DECISION-9 Option A′ that list is load-bearing, not decoration:
#      -Wl,-all_load fails on eight undefined Monero symbols in range_proof.o
#      (T0.5, evidence §4.3), so members are pulled by demand from these entry
#      points instead of wholesale.
#   2. tools/native_build/check_exports.sh reconciles it against what the built
#      artifact actually exports (DECISION-9 §5, upstream issue #4638).
#
# THIS IS A STOPGAP OWNER. T1.4/T1.5 own the canonical 464-name list as a
# generated artifact; when it lands, pass it to both consumers with
# --symbol-list and delete nothing here — this script stays as the way the list
# is regenerated from headers at a new tag, and as the cross-check against the
# generated one.

set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: generate_symbol_list.sh --headers DIR [--out FILE] [--expect-count N]

Extracts every TW* C function name declared in upstream's headers and writes
them one per line, sorted and de-duplicated.

Options:
  --headers DIR       Directory of upstream headers, searched recursively.
                      Either include/TrustWalletCore/ from
                      TrustWalletCore-<tag>.tar.xz (143 files at 4.8.0) or
                      Headers/ from a WalletCore.xcframework slice (85 files).
                      Both declare the same 464 functions (evidence §4.2).
  --out FILE          Write here instead of stdout.
  --expect-count N    Fail unless exactly N names were found. Use 464 at 4.8.0.
  -h, --help          This text.

The extraction command, recorded so every consumer runs the same one:

  grep -rhoE "^[A-Za-z_][A-Za-z0-9_ *]*\bTW[A-Za-z0-9_]+\(" DIR \
    | grep -oE "TW[A-Za-z0-9_]+\($" | tr -d '(' | sort -u

It anchors at the start of a line, so it takes declarations and not calls
inside comments or macro bodies. At 4.8.0 the result is identical to the 464
`T _TW…` symbols the shipped dynamic framework exports (evidence §2.6).
EOF
}

headers=''
out=''
expect_count=''

while (($#)); do
  case $1 in
    --headers) headers=${2:?--headers needs a value}; shift 2 ;;
    --out) out=${2:?--out needs a value}; shift 2 ;;
    --expect-count) expect_count=${2:?--expect-count needs a value}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; wcf_die "unknown argument: $1" ;;
  esac
done

[[ -n $headers ]] || { usage >&2; wcf_die '--headers is required'; }
[[ -d $headers ]] || wcf_die "not a directory: $headers"

names=$(
  grep -rhoE "^[A-Za-z_][A-Za-z0-9_ *]*\bTW[A-Za-z0-9_]+\(" "$headers" |
    grep -oE "TW[A-Za-z0-9_]+\($" |
    tr -d '(' |
    sort -u
)
[[ -n $names ]] || wcf_die "no TW* declarations found under $headers"

count=$(printf '%s\n' "$names" | wc -l | tr -d ' ')

if [[ -n $expect_count ]] && [[ $count != "$expect_count" ]]; then
  wcf_die "expected $expect_count TW* names under $headers, found $count"
fi

wcf_log "generate_symbol_list.sh: $count TW* names from $headers"

if [[ -n $out ]]; then
  mkdir -p -- "$(dirname -- "$out")"
  printf '%s\n' "$names" >"$out"
  wcf_log "generate_symbol_list.sh: wrote $out"
else
  printf '%s\n' "$names"
fi
