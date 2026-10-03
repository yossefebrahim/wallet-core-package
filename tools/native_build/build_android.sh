#!/usr/bin/env bash
#
# build_android.sh — DECISION-9 Option B: build upstream from source at the
# pinned commit, with our build-identity object linked into the library.
#
# Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
# Not affiliated with or endorsed by Trust Wallet.
#
# THERE IS NO ALTERNATIVE ON ANDROID. Upstream's 4.8.0 release carries eight
# assets and not one of them is an Android artifact; its Android library lives
# on GitHub Packages behind an access token (upstream README line 48). There is
# nothing to mirror and no unauthenticated URL to compare against, so every
# Android artifact this project ships is one we compiled.
#
# THIS SCRIPT RUNS UPSTREAM'S OWN BUILD TOOLING — tools/install-*,
# tools/generate-files, and Gradle — against a source tree we did not review.
# That is inherent in building from source. The tree is treated as data: this
# script reads it, copies two files into it, makes one patch to its Gradle
# module, and executes exactly the entry points upstream's own android-ci.yml
# executes, in the same order. Nothing in the tree is consulted for
# instructions about what to do.
#
# HOW THE IDENTITY OBJECT GETS IN, WITH ALMOST NO BUILD PATCHES.
# Upstream's root CMakeLists.txt gathers Android sources with
#   file(GLOB_RECURSE core_sources src/*.c src/*.cc src/*.cpp src/*.h ...)
# so a .c file placed under src/ is compiled into libTrustWalletCore.so with no
# edit to any build file. We therefore write ONE generated file into src/ that
# #defines the three identity values and #includes our wcf_build_info.c from a
# directory the glob does not reach. The reviewed source stays the file in
# packages/wallet_core_flutter_native/src/identity/. The only build file we
# patch is android/wallet-core/build.gradle, just to pass -DFLUTTER=ON so the
# C API is exported (which matters because every such patch is something that
# silently stops applying at the next upstream tag).
#
# UNRUN. This script has never been executed: it needs an Android SDK, NDK,
# JDK, Gradle, a Rust toolchain and boost, none of which were available where
# it was written. Its first run is the workflow's, and the two gates at the end
# are what will say whether it worked.

set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

usage() {
  cat <<'EOF'
Usage: build_android.sh --out-dir DIR --commit SHA
                        (--source-dir DIR | --source-archive FILE)
                        [--tag TAG] [--artifact-set-id ID] [--build-workflow URL]
                        [--abis LIST] [--ndk-version V] [--cmake-version V]
                        [--min-sdk N] [--symbol-list FILE]
                        [--expect-symbol-count N] [--skip-deps]
                        [--work-dir DIR] [--keep-work]

Builds libTrustWalletCore.so per ABI from upstream's git tree at the pinned
commit, runs the export-visibility and 16 KB alignment gates on each, and
writes the DECISION-14 §5.1 record for each.

Required:
  --out-dir DIR         Output root, outside the repository working tree.
  --commit SHA          40 lowercase hex pinned commit. If the source tree is a
                        git checkout its HEAD is verified against this value;
                        if it is an unpacked archive the value is asserted, not
                        verified, and the script says so.
  --source-dir DIR      An already-prepared upstream tree, or
  --source-archive FILE a .tar.gz of it, unpacked into the work directory.

Optional:
  --tag TAG             Upstream tag, default 4.8.0.
  --artifact-set-id ID  as_<tag>_<nnn>, default as_<tag>_000.
  --build-workflow URL  Absolute workflow-run URL. Default "local".
  --abis LIST           Comma-separated ABIs to SHIP, default arm64-v8a,x86_64.
                        Upstream's release variant builds every ABI its NDK
                        supports; this list selects which of them we publish.
                        armeabi-v7a and x86 are deliberately not shipped: PRD
                        §12.2 step 8 says an ABI that is not tested on a device
                        is dropped rather than shipped, and nothing in Phase 1
                        tests them.
  --ndk-version V       Default 28.0.12674087 — the version upstream's own
                        android/wallet-core/build.gradle pins at this tag, and
                        comfortably past the r27 floor that makes
                        -Wl,-z,max-page-size=16384 the default. Anything below
                        r27 is rejected.
  --cmake-version V     Default 3.18.1, the version upstream's Gradle module
                        requires.
  --min-sdk N           minSdkVersion recorded in the manifest. Read from
                        upstream's build.gradle when it can be, default 23.
  --symbol-list FILE    Canonical TW* names for the export gate. Default:
                        generated from the tree's own
                        include/TrustWalletCore/ headers.
  --expect-symbol-count N   Fail unless the list has exactly N names.
  --skip-deps           Do not run upstream's tools/install-* scripts. For a
                        machine that already has the toolchain.
  --work-dir DIR        Scratch directory, default a fresh mktemp -d.
  --keep-work           Do not delete the scratch directory.
  -h, --help            This text.

Outputs under --out-dir: the same four shapes build_apple.sh produces —
artifacts/, records/, upload/, SHA256SUMS, inputs.json.

Environment: ANDROID_HOME or ANDROID_SDK_ROOT must point at an Android SDK.
EOF
}

out_dir='' commit='' source_dir='' source_archive='' tag='' set_id='' build_workflow=''
abis='arm64-v8a,x86_64'
ndk_version='28.0.12674087'
cmake_version='3.18.1'
min_sdk=''
symbol_list='' expect_symbol_count=''
skip_deps=0 work_dir='' keep_work=0

while (($#)); do
  case $1 in
    --out-dir) out_dir=${2:?}; shift 2 ;;
    --commit) commit=${2:?}; shift 2 ;;
    --source-dir) source_dir=${2:?}; shift 2 ;;
    --source-archive) source_archive=${2:?}; shift 2 ;;
    --tag) tag=${2:?}; shift 2 ;;
    --artifact-set-id) set_id=${2:?}; shift 2 ;;
    --build-workflow) build_workflow=${2:?}; shift 2 ;;
    --abis) abis=${2:?}; shift 2 ;;
    --ndk-version) ndk_version=${2:?}; shift 2 ;;
    --cmake-version) cmake_version=${2:?}; shift 2 ;;
    --min-sdk) min_sdk=${2:?}; shift 2 ;;
    --symbol-list) symbol_list=${2:?}; shift 2 ;;
    --expect-symbol-count) expect_symbol_count=${2:?}; shift 2 ;;
    --skip-deps) skip_deps=1; shift ;;
    --work-dir) work_dir=${2:?}; shift 2 ;;
    --keep-work) keep_work=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; wcf_die "unknown argument: $1" ;;
  esac
done

[[ -n $out_dir ]] || { usage >&2; wcf_die '--out-dir is required'; }
[[ -n $commit ]] || { usage >&2; wcf_die '--commit is required'; }
if [[ -n $source_dir && -n $source_archive ]]; then
  wcf_die '--source-dir and --source-archive are mutually exclusive'
fi
[[ -n $source_dir || -n $source_archive ]] ||
  { usage >&2; wcf_die 'one of --source-dir or --source-archive is required'; }

[[ -n $tag ]] || tag='4.8.0'
[[ -n $set_id ]] || set_id="as_${tag}_000"
[[ -n $build_workflow ]] || build_workflow='local'
wcf_require_identity_values "$commit" "$set_id" "$build_workflow"

wcf_require_cmd jq unzip tar find

# r27 is the floor: it is the first NDK that passes
# -Wl,-z,max-page-size=16384 by default, and the alignment gate below is what
# proves the flag reached these bytes.
ndk_major=${ndk_version%%.*}
[[ $ndk_major =~ ^[0-9]+$ ]] || wcf_die "cannot read a major version out of --ndk-version $ndk_version"
(( ndk_major >= 27 )) ||
  wcf_die "NDK $ndk_version is older than r27; 16 KB page alignment would not be the default"

android_sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
[[ -n $android_sdk ]] || wcf_die 'set ANDROID_HOME (or ANDROID_SDK_ROOT) to an Android SDK'
[[ -d $android_sdk ]] || wcf_die "not a directory: $android_sdk"

mkdir -p -- "$out_dir"
out_dir=$(cd -- "$out_dir" && pwd)
mkdir -p -- "$out_dir/artifacts" "$out_dir/records" "$out_dir/upload"

if [[ -z $work_dir ]]; then work_dir=$(wcf_mktemp_dir); fi
mkdir -p -- "$work_dir"
work_dir=$(cd -- "$work_dir" && pwd)
cleanup() { if (( ! keep_work )); then rm -rf -- "$work_dir"; fi; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Source tree
# ---------------------------------------------------------------------------

wcf_section 'source tree'
commit_verified=false
if [[ -n $source_archive ]]; then
  [[ -f $source_archive ]] || wcf_die "not a file: $source_archive"
  archive_sha=$(wcf_sha256 "$source_archive")
  archive_size=$(wcf_size "$source_archive")
  wcf_log "$source_archive"
  wcf_log "sha256 $archive_sha ($archive_size bytes)"
  unpack="$work_dir/src"
  mkdir -p -- "$unpack"
  wcf_run tar -xzf "$source_archive" -C "$unpack"
  # A GitHub source archive unpacks into exactly one top-level directory.
  roots=()
  while IFS= read -r candidate; do roots+=("$candidate"); done < <(find "$unpack" -mindepth 1 -maxdepth 1 -type d)
  (( ${#roots[@]} == 1 )) || wcf_die "expected one top-level directory in $source_archive, found ${#roots[@]}"
  source_dir=${roots[0]}
  jq -n --arg name "$(basename -- "$source_archive")" --arg sha "$archive_sha" \
    --argjson size "$archive_size" --arg commit "$commit" --arg tag "$tag" \
    '{ input_source: { name: $name, upstream_tag: $tag, sha256: $sha, size: $size,
                       asserted_commit: $commit,
                       checksum_provenance: "first_seen_by_this_project",
                       commit_verified: false,
                       note: "An unpacked source archive carries no git metadata, so the commit is the one the caller asserted. A git checkout would let the build verify it." } }' \
    >"$out_dir/inputs.json"
else
  [[ -d $source_dir ]] || wcf_die "not a directory: $source_dir"
  source_dir=$(cd -- "$source_dir" && pwd)
  if [[ -e $source_dir/.git ]] && command -v git >/dev/null 2>&1; then
    head=$(git -C "$source_dir" rev-parse HEAD)
    [[ $head == "$commit" ]] ||
      wcf_die "source tree HEAD is $head, not the pinned $commit"
    commit_verified=true
    wcf_log "git HEAD verified: $head"
  else
    wcf_log 'warning: the source tree is not a git checkout; the commit is asserted, not verified.'
  fi
  jq -n --arg dir "$source_dir" --arg commit "$commit" --arg tag "$tag" \
    --argjson verified "$commit_verified" \
    '{ input_source: { path: $dir, upstream_tag: $tag, asserted_commit: $commit, commit_verified: $verified } }' \
    >"$out_dir/inputs.json"
fi
wcf_log "source: $source_dir"

[[ -f $source_dir/CMakeLists.txt ]] || wcf_die "no CMakeLists.txt in $source_dir — this is not the wallet-core git tree (the TrustWalletCore-<tag>.tar.xz release asset is NOT source)"
[[ -d $source_dir/android ]] || wcf_die "no android/ in $source_dir — this is not the wallet-core git tree"

if [[ -z $min_sdk ]]; then
  min_sdk=$(grep -m1 -oE 'minSdkVersion[[:space:]]+[0-9]+' "$source_dir/android/wallet-core/build.gradle" 2>/dev/null |
    grep -oE '[0-9]+' || true)
  [[ -n $min_sdk ]] || min_sdk=23
fi
wcf_log "minSdkVersion: $min_sdk"

# ---------------------------------------------------------------------------
# Identity object: one generated file inside the glob, our source outside it
# ---------------------------------------------------------------------------

wcf_section 'identity object'
identity_source=$(wcf_identity_source)
identity_header="$(dirname -- "$identity_source")/wcf_build_info.h"
[[ -f $identity_source && -f $identity_header ]] ||
  wcf_die "identity sources not found next to $identity_source"

identity_dir="$source_dir/wcf_identity"
mkdir -p -- "$identity_dir"
cp -- "$identity_source" "$identity_header" "$identity_dir/"

generated="$source_dir/src/wcf_build_info_generated.c"
cat >"$generated" <<EOF
/* GENERATED by tools/native_build/build_android.sh — do not edit, do not
 * commit. Upstream's CMakeLists.txt globs src/*.c, so this file is what pulls
 * the build-identity object into libTrustWalletCore.so. It carries the values
 * for this build and includes the reviewed source, which lives outside the
 * glob so that it is never compiled without them. */
#define WCF_UPSTREAM_COMMIT "$commit"
#define WCF_ARTIFACT_SET_ID "$set_id"
#define WCF_BUILD_WORKFLOW  "$build_workflow"
#include "../wcf_identity/wcf_build_info.c"
/* Upstream builds Android with TW_UNITY_BUILD=ON, so this file may be
 * concatenated with other translation units. A quoted #include still resolves
 * against the directory of the file containing the directive, so the path
 * above is correct either way; the macros are undefined again so that nothing
 * downstream in the same unity blob inherits them. */
#undef WCF_UPSTREAM_COMMIT
#undef WCF_ARTIFACT_SET_ID
#undef WCF_BUILD_WORKFLOW
EOF
wcf_log "wrote $generated"
wcf_log "identity sources copied to $identity_dir"

# ---------------------------------------------------------------------------
# Toolchain
# ---------------------------------------------------------------------------

wcf_section 'toolchain'
sdkmanager=''
for candidate in \
  "$android_sdk/cmdline-tools/latest/bin/sdkmanager" \
  "$android_sdk/cmdline-tools/bin/sdkmanager" \
  "$android_sdk/tools/bin/sdkmanager"; do
  if [[ -x $candidate ]]; then sdkmanager=$candidate; break; fi
done
[[ -n $sdkmanager ]] || wcf_die "no sdkmanager under $android_sdk"

if (( skip_deps )); then
  wcf_log 'skipping upstream dependency installation (--skip-deps)'
else
  # Exactly the steps of upstream's android-ci.yml, in its order, plus the
  # explicit NDK/CMake pin. install-android-dependencies installs the NDK the
  # emulator step wants (23.1.7779620), which is NOT the one the library is
  # built with and is far below the r27 floor, so we install ours by hand.
  wcf_run "$sdkmanager" --install "ndk;$ndk_version" "cmake;$cmake_version"
  (
    cd -- "$source_dir"
    if [[ $(uname -s) == Darwin ]]; then
      wcf_run tools/install-sys-dependencies-mac
    else
      wcf_run tools/install-sys-dependencies-linux
    fi
    wcf_run tools/install-rust-dependencies
    wcf_run tools/install-android-dependencies
    wcf_run tools/install-dependencies
  )
fi

# CMake must find Boost from the host, not the NDK sysroot (upstream's
# find_host_package). Upstream's install-sys-dependencies-mac writes
# BOOST_ROOT into ~/.zprofile, which a non-interactive shell never reads, and
# the Android SDK's CMake 3.18 does not search Apple Silicon's brew prefix
# (/opt/homebrew) on its own — upstream's CI runs on Intel runners where
# /usr/local is searched by default. So export it here for Gradle's CMake.
if [[ -z ${BOOST_ROOT:-} ]] && command -v brew >/dev/null 2>&1; then
  if boost_prefix=$(brew --prefix boost 2>/dev/null) && [[ -d $boost_prefix/include/boost ]]; then
    export BOOST_ROOT=$boost_prefix
  fi
fi
[[ -n ${BOOST_ROOT:-} ]] && wcf_log "BOOST_ROOT: $BOOST_ROOT"

ndk_dir="$android_sdk/ndk/$ndk_version"
[[ -d $ndk_dir ]] || wcf_die "NDK $ndk_version is not installed at $ndk_dir"

host_tag=''
for candidate in darwin-x86_64 linux-x86_64 darwin-arm64; do
  if [[ -d $ndk_dir/toolchains/llvm/prebuilt/$candidate ]]; then host_tag=$candidate; break; fi
done
[[ -n $host_tag ]] || wcf_die "no llvm prebuilt toolchain under $ndk_dir"
llvm_bin="$ndk_dir/toolchains/llvm/prebuilt/$host_tag/bin"
[[ -x $llvm_bin/llvm-nm ]] || wcf_die "llvm-nm not found at $llvm_bin"
[[ -x $llvm_bin/llvm-readelf ]] || wcf_die "llvm-readelf not found at $llvm_bin"
wcf_log "ndk:      $ndk_version ($llvm_bin)"

rust_version=$( (rustc --version 2>/dev/null || printf 'unknown') | head -1)
gradle_version=$( (cd -- "$source_dir/android" && ./gradlew --version 2>/dev/null || printf '') |
  awk '/^Gradle / {print $2; exit}')
[[ -n $gradle_version ]] || gradle_version='unknown'
jdk_version=$( (java -version 2>&1 || printf 'unknown') | head -1)
boost_version=$( (brew list --versions boost 2>/dev/null || printf '') | awk '{print $2}')
[[ -n $boost_version ]] || boost_version='unknown'

wcf_log "cmake:    $cmake_version"
wcf_log "rust:     $rust_version"
wcf_log "gradle:   $gradle_version"
wcf_log "jdk:      $jdk_version"
wcf_log "boost:    $boost_version"
# boost, ninja and the rest come from brew, which has no per-formula version
# pin. They are recorded after the fact rather than pinned in advance; that
# residual is stated in tools/native_build/README.md and is the one thing in
# this build that a version number cannot fix.

# ---------------------------------------------------------------------------
# Generate upstream's own sources, then build the AAR
# ---------------------------------------------------------------------------

wcf_section 'generate upstream sources'
(
  cd -- "$source_dir"
  wcf_run tools/generate-files android
)

# Upstream hides every C symbol on Android unless CMake sees FLUTTER=ON
# (cmake/StandardSettings.cmake: CMAKE_CXX_VISIBILITY_PRESET hidden) — its
# AAR serves the JNI binding, which never needed the TW* C API exported,
# and only TWData/TWString/TWCardano carry TW_VISIBILITY_DEFAULT (27 of 464;
# build-native run 37155340955). dart:ffi needs all of them, so pass the
# same switch upstream's own tools/flutter-build passes. This is the one
# edit we make to upstream's build files; the identity object is the only
# other change to the tree, and both are stated in the record's notes.
gradle_module="$source_dir/android/wallet-core/build.gradle"
[[ -f $gradle_module ]] || wcf_die "no Gradle module at $gradle_module"
if ! grep -q -- '-DFLUTTER=ON' "$gradle_module"; then
  wcf_run sed -i.wcf-orig 's/"-DTW_UNITY_BUILD=ON"/"-DTW_UNITY_BUILD=ON", "-DFLUTTER=ON"/' "$gradle_module"
  grep -q -- '-DFLUTTER=ON' "$gradle_module" || wcf_die "could not add -DFLUTTER=ON to $gradle_module (upstream's cmake arguments line changed?)"
  rm -f -- "$gradle_module.wcf-orig"
fi
wcf_log "gradle cmake arguments: $(grep -o 'arguments .*' "$gradle_module" | head -1)"

wcf_section 'gradle assembleRelease'
(
  cd -- "$source_dir/android"
  wcf_run ./gradlew --no-daemon assembleRelease
)

aar="$source_dir/android/wallet-core/build/outputs/aar/wallet-core-release.aar"
[[ -f $aar ]] || wcf_die "no AAR at $aar"
wcf_log "aar: $aar ($(wcf_size "$aar") bytes)"

aar_dir="$work_dir/aar"
mkdir -p -- "$aar_dir"
wcf_run unzip -q -o "$aar" -d "$aar_dir"

# ---------------------------------------------------------------------------
# Symbol list for the export gate
# ---------------------------------------------------------------------------

wcf_section 'symbol list'
if [[ -z $symbol_list ]]; then
  symbol_list="$work_dir/tw_symbols.txt"
  gen=("$here/generate_symbol_list.sh" --headers "$source_dir/include/TrustWalletCore" --out "$symbol_list")
  if [[ -n $expect_symbol_count ]]; then gen+=(--expect-count "$expect_symbol_count"); fi
  wcf_run "${gen[@]}"
else
  [[ -f $symbol_list ]] || wcf_die "not a file: $symbol_list"
  wcf_log "using the symbol list passed on the command line: $symbol_list"
fi

# ---------------------------------------------------------------------------
# Per-ABI extraction and gates
# ---------------------------------------------------------------------------

toolchain_json=$(jq -n \
  --arg ndk "$ndk_version" --arg cmake "$cmake_version" --arg rust "$rust_version" \
  --arg gradle "$gradle_version" --arg jdk "$jdk_version" --arg boost "$boost_version" \
  '{ndk: $ndk, cmake: $cmake, rust: $rust, gradle: $gradle, jdk: $jdk, boost: $boost}')

IFS=',' read -r -a abi_list <<<"$abis"

for abi in "${abi_list[@]}"; do
  wcf_section "abi $abi"
  built="$aar_dir/jni/$abi/libTrustWalletCore.so"
  [[ -f $built ]] ||
    wcf_die "the AAR has no jni/$abi/libTrustWalletCore.so; upstream's release variant did not build this ABI"

  logical_name="android/$abi/libTrustWalletCore.so"
  final="$out_dir/artifacts/$logical_name"
  mkdir -p -- "$(dirname -- "$final")"
  cp -- "$built" "$final"
  wcf_log "extracted $final ($(wcf_size "$final") bytes)"

  # Gate 1: export visibility. This is the gate upstream issue #4638 exists
  # for. If it fails, the first remedy is -fvisibility=default on the TW
  # translation units; the second is dropping any version script or
  # --gc-sections from the Android link. Do not publish past a failure.
  wcf_run "$here/check_exports.sh" \
    --binary "$final" \
    --symbol-list "$symbol_list" \
    --format elf \
    --nm "$llvm_bin/llvm-nm"

  # Gate 2: 16 KB page alignment, on every 64-bit ELF.
  wcf_run "$here/check_alignment.sh" \
    --binary "$final" \
    --readelf "$llvm_bin/llvm-readelf"

  wcf_run "$here/emit_artifact_record.sh" \
    --file "$final" \
    --logical-name "$logical_name" \
    --artifact-set-id "$set_id" \
    --source-commit "$commit" \
    --build-workflow "$build_workflow" \
    --linkage dynamic \
    --target-os android \
    --abi "$abi" \
    --min-os "$min_sdk" \
    --toolchain "$toolchain_json" \
    --provenance built_from_source \
    --out "$out_dir/records/$(wcf_flat_name "$logical_name").json"

  asset=$(wcf_asset_name "$set_id" "$(wcf_sha256 "$final")" "$logical_name")
  cp -- "$final" "$out_dir/upload/$asset"
  wcf_log "upload: $asset"
done

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

wcf_section 'done'
wcf_log "artifacts:  $out_dir/artifacts"
wcf_log "records:    $out_dir/records"
wcf_log "upload:     $out_dir/upload"
