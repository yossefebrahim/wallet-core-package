#!/usr/bin/env bash
#
# check_exports.sh — the export-visibility gate, mandatory on every artifact of
# every set, on both platforms (DECISION-9 §5, DECISION-14 §2.1).
#
# Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
# Not affiliated with or endorsed by Trust Wallet.
#
# It answers two questions that a build cannot answer any other way:
#
#   1. Are all of upstream's TW* C entry points exported from the artifact we
#      are about to publish? Upstream issue #4638 (open, no maintainer reply)
#      reports `undefined symbol: TWAnyAddressIsValid` from a Flutter app
#      against an .aar built by upstream's own tools/android-build. The Android
#      build is tuned for JNI, where those symbols only need to be reachable
#      *inside* the .so. This gate is what stops us shipping that.
#
#   2. Is wcf_build_info exported? The visibility attribute in
#      wcf_build_info.c makes the export happen; this gate proves it happened
#      in these bytes. A version script or --gc-sections can still drop an
#      annotated symbol, and a hidden identity symbol is indistinguishable at
#      load time from an artifact that was mirrored without a relink.
#
# THE EXACT COMMAND, for the record and for T1.19, which must run the same one:
#
#   llvm-nm [--dynamic] --defined-only --extern-only [--arch=<arch>] <artifact>
#
# reconciled in both directions against the canonical symbol list.

set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: check_exports.sh --binary FILE --symbol-list FILE --format macho|elf
                        [--nm PATH] [--identity-symbol NAME] [--max-report N]

Fails unless every name in the symbol list, plus the build-identity symbol, is
a defined external symbol of the binary, and unless the set of exported TW*
names is exactly the list (extra TW* exports mean the list is stale).

Options:
  --binary FILE          The artifact to check. A universal Mach-O is checked
                         one architecture at a time, so a symbol missing from
                         one slice cannot be masked by the other.
  --symbol-list FILE     Canonical TW* names, one per line. Produced by
                         generate_symbol_list.sh today; owned by T1.4/T1.5 once
                         they land.
  --format macho|elf     Mach-O names carry a leading underscore, ELF names do
                         not. Stated rather than sniffed so a wrong value fails
                         loudly instead of silently comparing nothing. ELF adds
                         --dynamic to read .dynsym from stripped releases.
  --nm PATH              llvm-nm to use. Default on Mach-O: the Xcode toolchain
                         copy (xcrun --find llvm-nm). On ELF there is no
                         default — pass the NDK's
                         toolchains/llvm/prebuilt/<host>/bin/llvm-nm, because
                         neither nm nor llvm-nm is on PATH on a macOS runner.
  --identity-symbol NAME Default wcf_build_info.
  --max-report N         How many missing/extra names to print. Default 20.
  -h, --help             This text.
EOF
}

binary=''
symbol_list=''
format=''
nm_bin=''
identity_symbol='wcf_build_info'
max_report=20

while (($#)); do
  case $1 in
    --binary) binary=${2:?--binary needs a value}; shift 2 ;;
    --symbol-list) symbol_list=${2:?--symbol-list needs a value}; shift 2 ;;
    --format) format=${2:?--format needs a value}; shift 2 ;;
    --nm) nm_bin=${2:?--nm needs a value}; shift 2 ;;
    --identity-symbol) identity_symbol=${2:?--identity-symbol needs a value}; shift 2 ;;
    --max-report) max_report=${2:?--max-report needs a value}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; wcf_die "unknown argument: $1" ;;
  esac
done

[[ -n $binary ]] || { usage >&2; wcf_die '--binary is required'; }
[[ -n $symbol_list ]] || { usage >&2; wcf_die '--symbol-list is required'; }
[[ -n $format ]] || { usage >&2; wcf_die '--format is required'; }
[[ -f $binary ]] || wcf_die "not a file: $binary"
[[ -f $symbol_list ]] || wcf_die "not a file: $symbol_list"

case $format in
  macho) prefix='_' ;;
  elf) prefix='' ;;
  *) wcf_die "--format must be macho or elf, got: $format" ;;
esac

if [[ -z $nm_bin ]]; then
  if [[ $format == macho ]]; then
    nm_bin=$(xcrun --find llvm-nm 2>/dev/null) ||
      wcf_die 'could not locate llvm-nm; pass --nm'
  else
    wcf_die 'no default llvm-nm for ELF; pass --nm with the NDK toolchain copy'
  fi
fi
[[ -x $nm_bin ]] || wcf_die "not executable: $nm_bin"

# Architectures to check. lipo reports one name for a thin Mach-O and several
# for a universal one; ELF is always single-architecture.
archs=('')
if [[ $format == macho ]] && command -v lipo >/dev/null 2>&1; then
  read -r -a archs <<<"$(lipo -archs "$binary" 2>/dev/null || printf '')"
  ((${#archs[@]})) || archs=('')
fi

workdir=$(wcf_mktemp_dir)
trap 'rm -rf -- "$workdir"' EXIT

expected="$workdir/expected"
sort -u -- "$symbol_list" >"$expected"
expected_count=$(wc -l <"$expected" | tr -d ' ')
(( expected_count > 0 )) || wcf_die "symbol list is empty: $symbol_list"

wcf_section "export-visibility gate: $binary"
wcf_log "symbol list: $symbol_list ($expected_count names, prefix '${prefix:-none}')"

failed=0

for arch in "${archs[@]}"; do
  local_label=${arch:-'(single architecture)'}
  nm_cmd=("$nm_bin" --defined-only --extern-only)
  # ELF: what a consumer can dlsym is the dynamic symbol table, and a release
  # .so is stripped of .symtab (upstream's AAR is), so read .dynsym. Mach-O
  # exports are in the one symbol table llvm-nm reads by default.
  if [[ $format == elf ]]; then nm_cmd+=(--dynamic); fi
  if [[ -n $arch ]]; then nm_cmd+=("--arch=$arch"); fi
  nm_cmd+=("$binary")

  raw="$workdir/nm.raw"
  wcf_run "${nm_cmd[@]}" >"$raw"

  # A defined-external line is `<address> <type> <name>`; anything else (the
  # "(for architecture x):" banner, blank lines) is dropped by the name filter.
  all="$workdir/all"
  awk 'NF >= 3 && $NF ~ /^[A-Za-z_][A-Za-z0-9_.$]*$/ { print $NF }' "$raw" |
    sort -u >"$all"

  total=$(wc -l <"$all" | tr -d ' ')

  # Exported TW* names, with the platform prefix stripped back off.
  actual="$workdir/actual"
  if [[ -n $prefix ]]; then
    grep -E "^${prefix}TW[A-Za-z0-9_]*$" "$all" | sed "s/^${prefix}//" | sort -u >"$actual" || true
  else
    grep -E '^TW[A-Za-z0-9_]*$' "$all" | sort -u >"$actual" || true
  fi
  actual_count=$(wc -l <"$actual" | tr -d ' ')

  missing="$workdir/missing"
  extra="$workdir/extra"
  comm -23 "$expected" "$actual" >"$missing"
  comm -13 "$expected" "$actual" >"$extra"
  missing_count=$(wc -l <"$missing" | tr -d ' ')
  extra_count=$(wc -l <"$extra" | tr -d ' ')

  identity_ok=no
  if grep -qxF "${prefix}${identity_symbol}" "$all"; then identity_ok=yes; fi

  wcf_log "arch $local_label: $total defined external symbols, $actual_count of them TW*"
  wcf_log "arch $local_label: expected $expected_count, missing $missing_count, unexpected $extra_count"
  wcf_log "arch $local_label: ${prefix}${identity_symbol} exported: $identity_ok"

  if (( missing_count > 0 )); then
    wcf_log "arch $local_label: MISSING (first $max_report):"
    head -n "$max_report" "$missing" | sed 's/^/  - /' >&2
    failed=1
  fi
  if (( extra_count > 0 )); then
    wcf_log "arch $local_label: UNEXPECTED TW* exports, the symbol list is stale (first $max_report):"
    head -n "$max_report" "$extra" | sed 's/^/  + /' >&2
    failed=1
  fi
  if [[ $identity_ok != yes ]]; then
    wcf_log "arch $local_label: build-identity symbol ${prefix}${identity_symbol} is NOT exported."
    wcf_log "  Either wcf_build_info.c was not linked in, or the link dropped it"
    wcf_log "  (version script, --gc-sections, -fvisibility without the attribute)."
    failed=1
  fi
done

if (( failed )); then
  wcf_die "export-visibility gate FAILED for $binary"
fi

wcf_log "export-visibility gate PASSED for $binary"
