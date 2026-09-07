#!/usr/bin/env bash
#
# check_alignment.sh — the 16 KB page-alignment gate for 64-bit ELF artifacts
# (PRD §12.2 step 8, DECISION-9 §5, evidence §6).
#
# Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
# Not affiliated with or endorsed by Trust Wallet.
#
# Android devices with 16 KB pages will not load a library whose LOAD segments
# are aligned to 4 KB. NDK r27 and later pass -Wl,-z,max-page-size=16384 by
# default; earlier NDKs do not, which is why the build pins r27+ and why this
# gate exists to prove the flag took effect in these bytes rather than assuming
# the NDK version implies it.
#
# THE EXACT COMMAND, for the record and for T1.19:
#
#   llvm-readelf -l <artifact>
#
# Every LOAD program header's Align column must read 0x4000 (16384).
#
# Nothing here applies to Apple artifacts: 16 KB alignment is an ELF property
# and Mach-O has no equivalent program header. The Apple build does not call
# this script.

set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: check_alignment.sh --binary FILE [--readelf PATH] [--align 0x4000]
       check_alignment.sh --readelf-output FILE [--align 0x4000]

Fails unless every LOAD program header of a 64-bit ELF shared object is aligned
to 16 KB.

Options:
  --binary FILE          The .so to check.
  --readelf PATH         llvm-readelf to use. There is no default: neither
                         readelf nor llvm-readelf is on PATH on macOS, so the
                         caller passes the NDK-qualified path
                         $ANDROID_NDK/toolchains/llvm/prebuilt/<host>/bin/llvm-readelf.
                         If llvm-readelf is on PATH it is used when --readelf
                         is omitted.
  --readelf-output FILE  Check a saved `llvm-readelf -l` output instead of
                         running the tool. This is how the parser is tested on
                         a machine with no Android build.
  --align VALUE          Required alignment, default 0x4000 (16384).
  -h, --help             This text.

A 32-bit ELF (armeabi-v7a) is reported and skipped: the requirement is on
64-bit ABIs. PRD §12.2 step 8 additionally requires the packaged APK/AAB to
preserve the alignment (`zipalign -c -P 16 -v`); that check belongs to the
consumer-side harness (T1.19), not to the artifact build.
EOF
}

binary=''
readelf_bin=''
readelf_output=''
align='0x4000'

while (($#)); do
  case $1 in
    --binary) binary=${2:?--binary needs a value}; shift 2 ;;
    --readelf) readelf_bin=${2:?--readelf needs a value}; shift 2 ;;
    --readelf-output) readelf_output=${2:?--readelf-output needs a value}; shift 2 ;;
    --align) align=${2:?--align needs a value}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; wcf_die "unknown argument: $1" ;;
  esac
done

if [[ -z $binary && -z $readelf_output ]]; then
  usage >&2
  wcf_die 'one of --binary or --readelf-output is required'
fi
if [[ -n $binary && -n $readelf_output ]]; then
  wcf_die '--binary and --readelf-output are mutually exclusive'
fi

workdir=$(wcf_mktemp_dir)
trap 'rm -rf -- "$workdir"' EXIT
headers="$workdir/headers"
label=''

if [[ -n $binary ]]; then
  [[ -f $binary ]] || wcf_die "not a file: $binary"
  label=$binary

  # ELF class lives in byte 4 of the identification header: 1 = 32-bit,
  # 2 = 64-bit. od is portable; `file` output wording is not.
  magic=$(od -An -tx1 -N5 "$binary" | tr -d ' \n')
  case $magic in
    7f454c4602) : ;;                                     # \x7fELF, 64-bit
    7f454c4601)
      wcf_log "check_alignment.sh: $binary is a 32-bit ELF; 16 KB alignment does not apply. Skipped."
      exit 0 ;;
    *) wcf_die "not an ELF object (magic $magic): $binary" ;;
  esac

  if [[ -z $readelf_bin ]]; then
    if command -v llvm-readelf >/dev/null 2>&1; then
      readelf_bin=llvm-readelf
    else
      wcf_die 'llvm-readelf is not on PATH; pass --readelf with the NDK toolchain copy'
    fi
  fi

  wcf_section "16 KB alignment gate: $binary"
  wcf_run "$readelf_bin" -l "$binary" >"$headers"
else
  [[ -f $readelf_output ]] || wcf_die "not a file: $readelf_output"
  label=$readelf_output
  wcf_section "16 KB alignment gate: saved llvm-readelf output $readelf_output"
  cp -- "$readelf_output" "$headers"
fi

# `llvm-readelf -l` prints one line per program header:
#   LOAD  0x000000 0x0000000000000000 0x0000000000000000 0x0122ac 0x0122ac R  0x1000
# The alignment is the last column.
# `mapfile` would be shorter; macOS ships bash 3.2, which does not have it.
load_aligns=()
while IFS= read -r align_value; do
  load_aligns+=("$align_value")
done < <(awk '$1 == "LOAD" { print $NF }' "$headers")

count=${#load_aligns[@]}
(( count > 0 )) || wcf_die "no LOAD program headers found in $label"

bad=0
for value in "${load_aligns[@]}"; do
  if [[ $value != "$align" ]]; then
    wcf_log "  LOAD segment aligned $value, expected $align"
    bad=$((bad + 1))
  fi
done

wcf_log "$count LOAD segments, $bad below the required alignment $align"

if (( bad > 0 )); then
  wcf_die "16 KB alignment gate FAILED for $label: rebuild with NDK r27+ (or -Wl,-z,max-page-size=16384)"
fi

wcf_log "16 KB alignment gate PASSED for $label"
