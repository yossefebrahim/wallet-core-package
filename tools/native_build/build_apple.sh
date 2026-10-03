#!/usr/bin/env bash
#
# build_apple.sh — DECISION-9 Option A′: relink upstream's release-asset static
# archives together with our build-identity object into one dynamic library per
# Apple slice.
#
# Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
# Not affiliated with or endorsed by Trust Wallet.
#
# WHAT THIS IS, STATED PLAINLY. The object code in the produced libraries is
# upstream's, taken from `WalletCoreCommon.xcframework` inside the
# `TrustWalletCore-<tag>.tar.xz` release asset. We did not compile it. The only
# object we compile is wcf_build_info.c. Every record this script emits carries
# `provenance: relinked_from_upstream_release_asset` so the manifest never
# implies otherwise, and PRD §12.4's independent-rebuild requirement is not
# available for these artifacts by construction (DECISION-9 §4, T4.4).
# Upstream publishes no checksum for that asset — six of its eight 4.8.0 assets
# have none — so the input digest this script records is a FIRST-SEEN value,
# not an attested one.
#
# WHY THE -u LIST IS LOAD-BEARING. `-Wl,-all_load` on these archives fails with
# eight undefined Monero symbols in range_proof.o (T0.5, evidence §4.3). No TW*
# entry point reaches that object, so the link pulls archive members by demand
# from the TW* entry points instead of wholesale. The list therefore has to be
# complete and current at every tag, which is why it is generated from the
# tag's own headers rather than kept by hand.
#
# THE macOS HOST LIBRARY. The `macos-arm64_x86_64` slice relinks into a .dylib
# that dart:ffi opens and calls. That file —
#   <out-dir>/artifacts/macos/arm64_x86_64/libTrustWalletCore.dylib
# — is what `melos run test:native` loads (T1.6). It is the highest-value
# output of this script and the reason DECISION-9 chose A′ for Phase 1.
#
# --with-shim (T1.13, DECISION-1 evaluation only). Also compiles
# packages/wallet_core_flutter_native/src/shim/wcf_sign.c — the Approach B
# signing adapter — into the macOS host library and gates its one export,
# wcf_sign_ethereum. Opt-in and off by default: without the flag nothing below
# behaves differently. With it the script refuses every slice but
# macos-arm64_x86_64; refuses, before creating anything, an --out-dir with . or
# .. components, or whose own name, once symlinks are resolved, does not
# contain "shim" (so a shim library is never written over a standard one);
# identifies the library as
# artifact set as_<tag>-shim_<nnn>, never the standard as_<tag>_<nnn> (so the
# runtime identity check refuses it where a standard library is expected);
# and writes no
# manifest record and no uploadable: the result is not upstream's object code
# plus an identity object any more, and the record format has no provenance
# value that says so.

set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

usage() {
  cat <<'EOF'
Usage: build_apple.sh (--tarball FILE | --cache-dir DIR) --out-dir DIR
                      (--commit SHA | --from-manifest FILE)
                      [--tag TAG] [--artifact-set-id ID] [--build-workflow URL]
                      [--slices LIST] [--symbol-list FILE]
                      [--expect-symbol-count N] [--expected-tarball-sha256 SHA]
                      [--ios-min VERSION] [--macos-min VERSION]
                      [--install-name NAME] [--work-dir DIR] [--keep-work]
                      [--with-shim]

Relinks upstream's Apple static archives with packages/wallet_core_flutter_native/
src/identity/wcf_build_info.c into one dynamic library per slice, emits a dSYM
per slice, runs the export-visibility gate on each library, and writes the
DECISION-14 §5.1 record for each.

Required:
  --tarball FILE        TrustWalletCore-<tag>.tar.xz. Downloaded by the
                        workflow; on a developer machine the cached copy under
                        ~/.cache/wcf-upstream/<tag>/ is the same file. Or
                        --cache-dir DIR, which resolves
                        DIR/<tag>/TrustWalletCore-<tag>.tar.xz once the tag is
                        known, so the tag is named once and not twice.
  --out-dir DIR         Output root. Created if absent; must be outside the
                        repository working tree so no build output is left in
                        the checkout.
  --commit SHA          40 lowercase hex upstream commit, injected into the
                        identity symbol. Or --from-manifest to read
                        upstream.commit and upstream.tag from
                        compat_manifest.json (which T1.1 fills).

Optional:
  --tag TAG             Upstream tag, default 4.8.0 or the manifest's.
  --artifact-set-id ID  as_<tag>_<nnn>, default as_<tag>_000. Sequence 000 is
                        the convention for a local build that is never
                        uploaded; the workflow always passes a real one.
  --build-workflow URL  Absolute workflow-run URL. Default "local", which the
                        script warns about — an artifact built that way must
                        not be published.
  --slices LIST         Comma-separated, default:
                        ios-arm64,ios-arm64_x86_64-simulator,macos-arm64_x86_64
                        (DECISION-9 §4 step 2; maccatalyst is not shipped).
  --symbol-list FILE    Canonical TW* names. Default: generated from the
                        tarball's own include/TrustWalletCore/ headers by
                        generate_symbol_list.sh. Pass T1.4/T1.5's generated
                        list here once it exists.
  --expect-symbol-count N   Fail unless the list has exactly N names (464 at
                        4.8.0). Off by default so a new tag is not blocked by
                        an old count.
  --expected-tarball-sha256 SHA   Compare the input digest against a value
                        seen before. Upstream publishes none for this asset, so
                        this is a pin against our own earlier observation, not
                        an upstream attestation.
  --ios-min VERSION     iOS deployment target, default 13.0 (upstream's own).
  --macos-min VERSION   macOS deployment target, default 11.0.
  --install-name NAME   -install_name for the dylibs, default
                        @rpath/libTrustWalletCore.dylib.
  --work-dir DIR        Scratch directory, default a fresh mktemp -d.
  --keep-work           Do not delete the scratch directory.
  --with-shim           DECISION-1 evaluation (T1.13): also compile and export
                        the Approach B adapter src/shim/wcf_sign.c. Only with
                        --slices macos-arm64_x86_64 and an --out-dir whose own
                        name, resolved, contains "shim". Artifact set id
                        defaults to as_<tag>-shim_000 and must match
                        as_<tag>-shim_<nnn>. Writes no record and no
                        uploadable.
  -h, --help            This text.

Outputs under --out-dir:
  artifacts/<logical_name>          the libraries, in manifest-key layout
  records/<flat_name>.json          DECISION-14 §5.1 record per library
  upload/<asset_name>               every uploadable, named per §3.1
  SHA256SUMS                        digests of everything in upload/
  inputs.json                       the input asset's first-seen digest
EOF
}

tarball='' cache_dir='' out_dir='' commit='' from_manifest='' tag='' set_id='' build_workflow=''
slices='ios-arm64,ios-arm64_x86_64-simulator,macos-arm64_x86_64'
symbol_list='' expect_symbol_count='' expected_tarball_sha256=''
ios_min='13.0' macos_min='11.0'
install_name='@rpath/libTrustWalletCore.dylib'
work_dir='' keep_work=0
with_shim=0

while (($#)); do
  case $1 in
    --tarball) tarball=${2:?}; shift 2 ;;
    --cache-dir) cache_dir=${2:?}; shift 2 ;;
    --out-dir) out_dir=${2:?}; shift 2 ;;
    --commit) commit=${2:?}; shift 2 ;;
    --from-manifest) from_manifest=${2:?}; shift 2 ;;
    --tag) tag=${2:?}; shift 2 ;;
    --artifact-set-id) set_id=${2:?}; shift 2 ;;
    --build-workflow) build_workflow=${2:?}; shift 2 ;;
    --slices) slices=${2:?}; shift 2 ;;
    --symbol-list) symbol_list=${2:?}; shift 2 ;;
    --expect-symbol-count) expect_symbol_count=${2:?}; shift 2 ;;
    --expected-tarball-sha256) expected_tarball_sha256=${2:?}; shift 2 ;;
    --ios-min) ios_min=${2:?}; shift 2 ;;
    --macos-min) macos_min=${2:?}; shift 2 ;;
    --install-name) install_name=${2:?}; shift 2 ;;
    --work-dir) work_dir=${2:?}; shift 2 ;;
    --keep-work) keep_work=1; shift ;;
    --with-shim) with_shim=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; wcf_die "unknown argument: $1" ;;
  esac
done

[[ -n $out_dir ]] || { usage >&2; wcf_die '--out-dir is required'; }
if [[ -n $tarball && -n $cache_dir ]]; then
  wcf_die '--tarball and --cache-dir are mutually exclusive'
fi
[[ -n $tarball || -n $cache_dir ]] ||
  { usage >&2; wcf_die 'one of --tarball or --cache-dir is required'; }
if (( with_shim )); then
  [[ $slices == macos-arm64_x86_64 ]] ||
    wcf_die '--with-shim builds the macOS host library only: pass --slices macos-arm64_x86_64 (mobile packaging of the adapter is pending D1a)'
  case /$out_dir/ in
    */../*|*/./*) wcf_die "--with-shim refuses an --out-dir with . or .. components; got: $out_dir" ;;
  esac
  # The name the library would land under, refused before anything is
  # created: an existing directory's own name with symlinks resolved; for one
  # that does not exist yet, its last component — every directory mkdir -p
  # creates is new, so none of them can be a symlink.
  if [[ -e $out_dir ]]; then
    landing=$(cd -- "$out_dir" 2>/dev/null && pwd -P) ||
      wcf_die "--with-shim needs an --out-dir that is a directory; got: $out_dir"
  elif [[ -L $out_dir ]]; then
    wcf_die "--with-shim refuses an --out-dir that is a dangling symlink; got: $out_dir"
  else
    landing=$out_dir
  fi
  [[ $(basename -- "$landing") == *shim* ]] ||
    wcf_die "--with-shim needs an --out-dir whose own name contains \"shim\" once resolved, so a shim library never lands where a standard one is expected; got: $out_dir"
fi

[[ $(uname -s) == Darwin ]] || wcf_die 'build_apple.sh needs macOS: it uses lipo, clang, dsymutil and the Apple SDKs'
wcf_require_cmd tar lipo clang dsymutil ditto xcrun jq

if [[ -n $from_manifest ]]; then
  [[ -z $commit ]] || wcf_die '--commit and --from-manifest are mutually exclusive'
  commit=$(wcf_manifest_value "$from_manifest" upstream.commit)
  [[ -n $tag ]] || tag=$(wcf_manifest_value "$from_manifest" upstream.tag)
fi
[[ -n $commit ]] || { usage >&2; wcf_die 'one of --commit or --from-manifest is required'; }
[[ -n $tag ]] || tag='4.8.0'

if [[ -n $cache_dir ]]; then
  tarball="$cache_dir/$tag/TrustWalletCore-$tag.tar.xz"
fi
[[ -f $tarball ]] || wcf_die "not a file: $tarball"
if (( with_shim )); then
  # A shim library states that it is one: its identity is never the standard
  # artifact set's, so verifyIdentity refuses it wherever a standard library
  # is expected, and a test that loads it names the shim identity explicitly.
  [[ -n $set_id ]] || set_id="as_${tag}-shim_000"
  [[ $set_id == *-shim_[0-9][0-9][0-9] ]] ||
    wcf_die "--with-shim needs an artifact set id of the form as_<tag>-shim_<nnn>, so a shim library never carries a standard identity; got: $set_id"
fi
[[ -n $set_id ]] || set_id="as_${tag}_000"
[[ -n $build_workflow ]] || build_workflow='local'

wcf_require_identity_values "$commit" "$set_id" "$build_workflow"

mkdir -p -- "$out_dir"
out_dir=$(cd -- "$out_dir" && pwd)
if (( with_shim )); then
  # Symlinks resolved, so the files land where the check above looked; checked
  # again on the created directory.
  out_dir=$(cd -- "$out_dir" && pwd -P)
  [[ $(basename -- "$out_dir") == *shim* ]] ||
    wcf_die "--with-shim needs an --out-dir whose own name contains \"shim\" once resolved, so a shim library never lands where a standard one is expected; got: $out_dir"
fi
mkdir -p -- "$out_dir/artifacts" "$out_dir/records" "$out_dir/upload"

if [[ -z $work_dir ]]; then work_dir=$(wcf_mktemp_dir); fi
mkdir -p -- "$work_dir"
work_dir=$(cd -- "$work_dir" && pwd)
cleanup() { if (( ! keep_work )); then rm -rf -- "$work_dir"; fi; }
trap cleanup EXIT

# Keep every child tool's scratch inside the work directory: clang, lipo and
# dsymutil all write there, and a sandboxed or read-only system temp directory
# would otherwise fail the build for a reason that has nothing to do with it.
export TMPDIR="$work_dir"

# ---------------------------------------------------------------------------
# Toolchain, recorded per artifact (DECISION-14 §5.1 note 1)
# ---------------------------------------------------------------------------

xcode_build=$(xcodebuild -version 2>/dev/null | awk '/^Build version/ {print $3}' || true)
[[ -n $xcode_build ]] || xcode_build='unknown'
clang_version=$(clang --version 2>/dev/null | head -1)

wcf_section 'toolchain'
wcf_log "xcode build:  $xcode_build"
wcf_log "clang:        $clang_version"

# ---------------------------------------------------------------------------
# Input asset: digest first, then extract
# ---------------------------------------------------------------------------

wcf_section 'input asset'
tarball_sha=$(wcf_sha256 "$tarball")
tarball_size=$(wcf_size "$tarball")
wcf_log "$tarball"
wcf_log "sha256 $tarball_sha  ($tarball_size bytes)"
wcf_log 'NOTE: upstream publishes no checksum for this asset (six of its eight'
wcf_log '4.8.0 release assets have none), so this digest is FIRST-SEEN by us,'
wcf_log 'not attested by upstream.'

if [[ -n $expected_tarball_sha256 ]]; then
  [[ $tarball_sha == "$expected_tarball_sha256" ]] ||
    wcf_die "input asset digest $tarball_sha does not match the expected $expected_tarball_sha256"
  wcf_log 'digest matches the value passed with --expected-tarball-sha256'
fi

jq -n \
  --arg path "$(basename -- "$tarball")" \
  --arg sha256 "$tarball_sha" \
  --argjson size "$tarball_size" \
  --arg tag "$tag" \
  '{ input_asset: {
       name: $path, upstream_tag: $tag, sha256: $sha256, size: $size,
       checksum_provenance: "first_seen_by_this_project",
       note: "Upstream publishes no checksum for TrustWalletCore-<tag>.tar.xz. This digest records the bytes we consumed; it is not an upstream attestation."
     } }' >"$out_dir/inputs.json"

wcf_section 'extract'
extracted="$work_dir/tarball"
mkdir -p -- "$extracted"
# Only the two entries we consume. The extracted tree is untrusted data: it is
# read by lipo, clang and grep and nothing in it is executed or sourced.
wcf_run tar -xJf "$tarball" -C "$extracted" WalletCoreCommon.xcframework include
xcframework="$extracted/WalletCoreCommon.xcframework"
headers="$extracted/include/TrustWalletCore"
[[ -d $xcframework ]] || wcf_die "WalletCoreCommon.xcframework not found in $tarball — upstream's asset layout changed (DECISION-9 revisit trigger 2)"
[[ -d $headers ]] || wcf_die "include/TrustWalletCore not found in $tarball — upstream's asset layout changed (DECISION-9 revisit trigger 2)"

# ---------------------------------------------------------------------------
# Symbol list and the linker -u response file
# ---------------------------------------------------------------------------

wcf_section 'symbol list'
if [[ -z $symbol_list ]]; then
  symbol_list="$work_dir/tw_symbols.txt"
  gen=("$here/generate_symbol_list.sh" --headers "$headers" --out "$symbol_list")
  if [[ -n $expect_symbol_count ]]; then gen+=(--expect-count "$expect_symbol_count"); fi
  wcf_run "${gen[@]}"
else
  [[ -f $symbol_list ]] || wcf_die "not a file: $symbol_list"
  wcf_log "using the symbol list passed on the command line: $symbol_list"
  if [[ -n $expect_symbol_count ]]; then
    have=$(sort -u <"$symbol_list" | wc -l | tr -d ' ')
    [[ $have == "$expect_symbol_count" ]] ||
      wcf_die "symbol list has $have names, expected $expect_symbol_count"
  fi
fi
symbol_count=$(sort -u <"$symbol_list" | wc -l | tr -d ' ')
wcf_log "$symbol_count TW* entry points"

# Mach-O prepends an underscore. One argument per line; clang reads it with @.
uflags="$work_dir/uflags.rsp"
sed 's/^/-Wl,-u,_/' <"$symbol_list" >"$uflags"

# ---------------------------------------------------------------------------
# Per-slice relink
# ---------------------------------------------------------------------------

# slice_id → target_os | abi | space-separated archs | sdk | min version
slice_config() {
  case $1 in
    ios-arm64)                  printf 'ios|arm64|arm64|iphoneos|%s' "$ios_min" ;;
    ios-arm64_x86_64-simulator) printf 'ios-simulator|arm64_x86_64|arm64 x86_64|iphonesimulator|%s' "$ios_min" ;;
    macos-arm64_x86_64)         printf 'macos|arm64_x86_64|arm64 x86_64|macosx|%s' "$macos_min" ;;
    *) return 1 ;;
  esac
}

# arch + slice → the clang target triple.
slice_triple() {
  local slice=$1 arch=$2 min=$3
  case $slice in
    ios-arm64)                  printf '%s-apple-ios%s' "$arch" "$min" ;;
    ios-arm64_x86_64-simulator) printf '%s-apple-ios%s-simulator' "$arch" "$min" ;;
    macos-arm64_x86_64)         printf '%s-apple-macos%s' "$arch" "$min" ;;
  esac
}

identity_source=$(wcf_identity_source)
[[ -f $identity_source ]] || wcf_die "identity source not found: $identity_source"
# `mapfile` would be shorter; macOS ships bash 3.2, which does not have it.
identity_defines=()
while IFS= read -r define_flag; do
  identity_defines+=("$define_flag")
done < <(wcf_identity_defines "$commit" "$set_id" "$build_workflow")

shim_source=''
if (( with_shim )); then
  shim_source="$(wcf_repo_root)/packages/wallet_core_flutter_native/src/shim/wcf_sign.c"
  [[ -f $shim_source ]] || wcf_die "shim source not found: $shim_source"
  wcf_log "with-shim: compiling $shim_source into the host library (DECISION-1 evaluation)"
fi

IFS=',' read -r -a slice_ids <<<"$slices"

for slice in "${slice_ids[@]}"; do
  config=$(slice_config "$slice") ||
    wcf_die "unknown slice '$slice'. Known: ios-arm64, ios-arm64_x86_64-simulator, macos-arm64_x86_64"
  IFS='|' read -r target_os abi archs sdk min_os <<<"$config"

  wcf_section "slice $slice -> $target_os/$abi (min $min_os)"

  slice_dir="$xcframework/$slice"
  [[ -d $slice_dir ]] ||
    wcf_die "slice $slice is not in this tarball — upstream's asset layout changed (DECISION-9 revisit trigger 2)"

  # The framework binary is Versions/A/WalletCoreCommon on macOS-style bundles
  # and WalletCoreCommon at the top on iOS-style ones; find copes with both.
  found=()
  while IFS= read -r candidate; do
    found+=("$candidate")
  done < <(find "$slice_dir" -type f -name WalletCoreCommon)
  (( ${#found[@]} == 1 )) ||
    wcf_die "expected exactly one WalletCoreCommon binary under $slice_dir, found ${#found[@]}"
  archive=${found[0]}
  wcf_log "static archive: $archive ($(wcf_size "$archive") bytes)"

  sdk_path=$(xcrun --sdk "$sdk" --show-sdk-path)
  sdk_version=$(xcrun --sdk "$sdk" --show-sdk-version)
  wcf_log "sdk: $sdk $sdk_version ($sdk_path)"

  read -r -a arch_list <<<"$archs"

  # `lipo -thin` needs a fat input; a single-architecture slice is already thin.
  for arch in "${arch_list[@]}"; do
    thin_archive="$work_dir/${slice}-${arch}.a"
    if (( ${#arch_list[@]} == 1 )); then
      cp -- "$archive" "$thin_archive"
    else
      wcf_run lipo -thin "$arch" -output "$thin_archive" "$archive"
    fi
  done

  # Two link attempts at most.
  #
  # Upstream compiled some archive members with a deployment target newer than
  # the one we ask for — at 4.8.0 four secp256k1 objects in the macOS slice are
  # built for macOS 26.0. The linker only warns, and LC_BUILD_VERSION in the
  # output would then record OUR number, which understates what the bytes
  # actually require. So: link, read the warnings, and if any member demands a
  # newer OS, link again at that version and record it. min_os in the manifest
  # then describes the artifact rather than our wish for it.
  thin_outputs=()
  for attempt in 1 2; do
    thin_outputs=()
    demanded=''
    for arch in "${arch_list[@]}"; do
      thin_archive="$work_dir/${slice}-${arch}.a"
      identity_object="$work_dir/${slice}-${arch}-wcf_build_info.o"
      link_log="$work_dir/${slice}-${arch}-link.log"
      triple=$(slice_triple "$slice" "$arch" "$min_os")

      # Our object is compiled separately, with -g so dsymutil has a debug map
      # entry to follow, and with -fvisibility=hidden so that the build proves
      # the visibility attribute in wcf_build_info.h is what exports the symbol
      # (DECISION-14 §2.1, D0 finding F9).
      wcf_run clang \
        -target "$triple" -isysroot "$sdk_path" \
        -c -O2 -g -fvisibility=hidden -Wall -Wextra -Werror \
        "${identity_defines[@]}" \
        -o "$identity_object" "$identity_source"

      # --with-shim: the adapter, compiled the same way and against the
      # tarball's own headers, so it is built against exactly the API it links
      # to. Its export comes from WCF_SIGN_EXPORT, not from the flags.
      shim_objects=()
      if (( with_shim )); then
        shim_object="$work_dir/${slice}-${arch}-wcf_sign.o"
        wcf_run clang \
          -target "$triple" -isysroot "$sdk_path" \
          -c -std=c11 -O2 -g -fvisibility=hidden -Wall -Wextra -Werror \
          -I "$extracted/include" \
          -o "$shim_object" "$shim_source"
        shim_objects=("$shim_object")
      fi

      thin_dylib="$work_dir/${slice}-${arch}.dylib"
      wcf_run clang \
        -target "$triple" \
        -isysroot "$sdk_path" \
        -dynamiclib \
        -install_name "$install_name" \
        -o "$thin_dylib" \
        "@$uflags" \
        "$identity_object" \
        ${shim_objects[@]+"${shim_objects[@]}"} \
        "$thin_archive" \
        -lc++ -framework Foundation -framework Security -framework CoreFoundation \
        2>"$link_log"
      cat "$link_log" >&2

      newer=$(grep -oE "built for newer '[^']+' version \([0-9.]+\)" "$link_log" |
        grep -oE '\([0-9.]+\)' | tr -d '()' | sort -V | tail -1 || true)
      if [[ -n $newer ]]; then
        demanded=$(printf '%s\n%s\n' "$demanded" "$newer" | grep -v '^$' | sort -V | tail -1)
      fi
      thin_outputs+=("$thin_dylib")
    done

    if [[ -z $demanded || $demanded == "$min_os" ]]; then break; fi
    if (( attempt == 2 )); then
      wcf_die "archive members still demand $demanded after relinking at $demanded"
    fi
    wcf_log "note: archive members are built for $demanded, newer than the requested $min_os."
    wcf_log "note: relinking at $demanded so min_os describes the artifact."
    min_os=$demanded
  done

  logical_dir="$target_os/$abi"
  logical_name="$logical_dir/libTrustWalletCore.dylib"
  final="$out_dir/artifacts/$logical_name"
  mkdir -p -- "$(dirname -- "$final")"

  if (( ${#thin_outputs[@]} == 1 )); then
    cp -- "${thin_outputs[0]}" "$final"
  else
    wcf_run lipo -create -output "$final" "${thin_outputs[@]}"
  fi
  wcf_log "built $final ($(wcf_size "$final") bytes)"

  # Deployment target as the produced binary declares it, not as we asked for
  # it: min_os in the manifest must describe the bytes.
  observed_min=$(xcrun vtool -arch "${arch_list[0]}" -show-build "$final" 2>/dev/null |
    awk '/ *minos/ {print $2; exit}' || true)
  if [[ -n $observed_min && $observed_min != "$min_os" ]]; then
    wcf_log "note: requested min $min_os, binary declares $observed_min; recording the binary's value"
    min_os=$observed_min
  fi

  # dSYM. Upstream's WalletCore.xcframework.dSYM.zip does not describe a
  # relinked binary, so if crash symbolication is wanted it has to be ours.
  dsym_dir="$work_dir/$(basename -- "$final").dSYM"
  wcf_run dsymutil "$final" -o "$dsym_dir" || wcf_log 'note: dsymutil reported problems; see above'
  dsym_zip="$out_dir/artifacts/$logical_dir/libTrustWalletCore.dylib.dSYM.zip"
  if [[ -d $dsym_dir ]]; then
    wcf_run ditto -c -k --keepParent "$dsym_dir" "$dsym_zip"
  else
    wcf_log 'note: dsymutil produced no bundle; no dSYM asset for this slice'
    dsym_zip=''
  fi

  # Gate: export visibility, on the artifact we are about to publish.
  exports_gate=("$here/check_exports.sh" \
    --binary "$final" \
    --symbol-list "$symbol_list" \
    --format macho)
  if (( with_shim )); then exports_gate+=(--require-symbol wcf_sign_ethereum); fi
  wcf_run "${exports_gate[@]}"

  if (( with_shim )); then
    # An evaluation library: no DECISION-14 record (its provenance is neither
    # value the record allows) and nothing to upload.
    wcf_log "with-shim: sha256 $(wcf_sha256 "$final") (evaluation artifact; no record, no uploadable)"
    continue
  fi

  toolchain_json=$(jq -n \
    --arg xcode "$xcode_build" \
    --arg clang "$clang_version" \
    --arg sdk "$sdk$sdk_version" \
    '{xcode: $xcode, clang: $clang, sdk: $sdk}')

  wcf_run "$here/emit_artifact_record.sh" \
    --file "$final" \
    --logical-name "$logical_name" \
    --artifact-set-id "$set_id" \
    --source-commit "$commit" \
    --build-workflow "$build_workflow" \
    --linkage dynamic \
    --target-os "$target_os" \
    --abi "$abi" \
    --min-os "$min_os" \
    --toolchain "$toolchain_json" \
    --provenance relinked_from_upstream_release_asset \
    --out "$out_dir/records/$(wcf_flat_name "$logical_name").json"

  # Uploadables, named per DECISION-14 §3.1. The dSYM is uploaded under the
  # same content-addressed scheme but is NOT a manifest artifact: the manifest
  # `artifacts` map is the list a consumer build fetches and verifies, and a
  # debug bundle is not on that path.
  uploadables=("$final")
  if [[ -n $dsym_zip ]]; then uploadables+=("$dsym_zip"); fi
  for uploadable in "${uploadables[@]}"; do
    rel=${uploadable#"$out_dir/artifacts/"}
    asset=$(wcf_asset_name "$set_id" "$(wcf_sha256 "$uploadable")" "$rel")
    cp -- "$uploadable" "$out_dir/upload/$asset"
    wcf_log "upload: $asset"
  done
done

# ---------------------------------------------------------------------------
# Digest listing over everything that will be uploaded
# ---------------------------------------------------------------------------

if (( ! with_shim )); then
wcf_section 'digests'
(
  cd -- "$out_dir/upload"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- * >"$out_dir/SHA256SUMS"
  else
    sha256sum -- * >"$out_dir/SHA256SUMS"
  fi
)
cat "$out_dir/SHA256SUMS" >&2
fi

wcf_section 'done'
wcf_log "artifacts:  $out_dir/artifacts"
wcf_log "records:    $out_dir/records"
wcf_log "upload:     $out_dir/upload"
if (( with_shim )); then
  wcf_log "shim host library for the shim-tagged tests (T1.13) — copy it to"
  wcf_log "third_party/wcf-native-shim/macos/arm64_x86_64/ or point WCF_NATIVE_SHIM_LIB at it:"
  wcf_log "  $out_dir/artifacts/macos/arm64_x86_64/libTrustWalletCore.dylib"
elif [[ -f $out_dir/artifacts/macos/arm64_x86_64/libTrustWalletCore.dylib ]]; then
  wcf_log "host library for melos run test:native (T1.6):"
  wcf_log "  $out_dir/artifacts/macos/arm64_x86_64/libTrustWalletCore.dylib"
fi
