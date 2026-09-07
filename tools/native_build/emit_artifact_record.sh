#!/usr/bin/env bash
#
# emit_artifact_record.sh — the per-artifact manifest record of DECISION-14
# §5.1, produced from the bytes we just built.
#
# Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
# Not affiliated with or endorsed by Trust Wallet.
#
# Fourteen fields, because PRD §12.3's "Durability [REQ]" names all of them:
# source commit, build workflow, linkage type, target OS, ABI, minimum OS,
# toolchain, size, checksum, signature, and attestation identity — plus
# DECISION-9's `provenance` and the two name fields DECISION-14 §3.1 needs.
#
# Production belongs here because this is the only place that knows the
# toolchain versions, the link mode, the deployment target, and the workflow
# run: it is the job that ran them. Validation belongs to tools/manifest, which
# `melos run manifest:validate` gates.
#
# The sha256 recorded here is a FIRST-SEEN value for a relinked artifact's
# input as well as for its output: six of upstream's eight 4.8.0 release assets
# carry no upstream-published checksum, TrustWalletCore-<tag>.tar.xz among
# them, so nothing upstream attests to the bytes we relinked (evidence §1, F1).
#
# Output is a one-key JSON object, `{"<logical_name>": {...}}`, so a whole set
# merges with `jq -s 'add'`.

set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: emit_artifact_record.sh --file FILE --logical-name NAME
         --artifact-set-id ID --source-commit SHA --build-workflow URL
         --linkage static|dynamic --target-os OS --abi ABI --min-os VERSION
         --toolchain JSON --provenance KIND
         [--signature NAME] [--attestation JSON] [--out FILE]

Computes sha256, size and asset_name over FILE and writes the DECISION-14 §5.1
record for it.

Options:
  --file FILE            The built artifact.
  --logical-name NAME    The manifest key: a '/'-separated path such as
                         android/arm64-v8a/libTrustWalletCore.so. Repeated
                         inside the record so a detached record is
                         self-describing.
  --artifact-set-id ID   as_<tag>_<nnn>. Never reused.
  --source-commit SHA    40 lowercase hex: the upstream commit these bits came
                         from. Per artifact, not per set — a recovery release
                         may rebuild one platform against a patched tree.
  --build-workflow URL   Absolute workflow-run URL.
  --linkage KIND         static | dynamic.
  --target-os OS         android | ios | ios-simulator | macos.
  --abi ABI              The platform's own vocabulary: arm64-v8a, armeabi-v7a,
                         x86_64, arm64, arm64_x86_64 (a fat slice).
  --min-os VERSION       As the platform states it: an Android API level (21)
                         or an Apple deployment target (13.0). A string, not a
                         normalised number — the two are not the same kind of
                         value.
  --toolchain JSON       Per-artifact toolchain object, e.g.
                         '{"ndk":"r27c","cmake":"3.29.3","rust":"1.81.0"}' or
                         '{"xcode":"17F113","clang":"…","sdk":"iphoneos26.5"}'.
                         Per artifact because one set contains artifacts built
                         by two different toolchains (DECISION-9 Option C).
  --provenance KIND      built_from_source | relinked_from_upstream_release_asset
  --signature NAME       Detached-signature asset name. Omit for null.
  --attestation JSON     Attestation object. Omit for null (until T4.5).
  --out FILE             Write here instead of stdout.
  -h, --help             This text.

`signature` and `attestation` are always present and explicitly null when they
do not exist, so "not yet attested" is a recorded fact rather than a missing
field.
EOF
}

file='' logical_name='' set_id='' source_commit='' build_workflow=''
linkage='' target_os='' abi='' min_os='' toolchain='' provenance=''
signature='' attestation='' out=''

while (($#)); do
  case $1 in
    --file) file=${2:?}; shift 2 ;;
    --logical-name) logical_name=${2:?}; shift 2 ;;
    --artifact-set-id) set_id=${2:?}; shift 2 ;;
    --source-commit) source_commit=${2:?}; shift 2 ;;
    --build-workflow) build_workflow=${2:?}; shift 2 ;;
    --linkage) linkage=${2:?}; shift 2 ;;
    --target-os) target_os=${2:?}; shift 2 ;;
    --abi) abi=${2:?}; shift 2 ;;
    --min-os) min_os=${2:?}; shift 2 ;;
    --toolchain) toolchain=${2:?}; shift 2 ;;
    --provenance) provenance=${2:?}; shift 2 ;;
    --signature) signature=${2:?}; shift 2 ;;
    --attestation) attestation=${2:?}; shift 2 ;;
    --out) out=${2:?}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; wcf_die "unknown argument: $1" ;;
  esac
done

wcf_require_cmd jq

for required in file logical_name set_id source_commit build_workflow \
                linkage target_os abi min_os toolchain provenance; do
  [[ -n ${!required} ]] || { usage >&2; wcf_die "--${required//_/-} is required"; }
done

[[ -f $file ]] || wcf_die "not a file: $file"
wcf_validate_commit "$source_commit"
wcf_validate_artifact_set_id "$set_id"
wcf_validate_build_workflow "$build_workflow"

case $linkage in static|dynamic) : ;; *) wcf_die "--linkage must be static or dynamic, got: $linkage" ;; esac
case $target_os in android|ios|ios-simulator|macos) : ;; *) wcf_die "--target-os must be android, ios, ios-simulator or macos, got: $target_os" ;; esac
case $provenance in
  built_from_source|relinked_from_upstream_release_asset) : ;;
  *) wcf_die "--provenance must be built_from_source or relinked_from_upstream_release_asset, got: $provenance" ;;
esac

[[ $logical_name =~ ^[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)*$ ]] ||
  wcf_die "logical name must be '/'-separated path segments, got: $logical_name"
[[ $logical_name != *__* ]] || wcf_die "logical name must not contain '__': $logical_name"

jq -e 'type == "object"' <<<"$toolchain" >/dev/null ||
  wcf_die "--toolchain must be a JSON object, got: $toolchain"

sha256=$(wcf_sha256 "$file")
size=$(wcf_size "$file")
(( size > 0 )) || wcf_die "artifact is empty: $file"
asset_name=$(wcf_asset_name "$set_id" "$sha256" "$logical_name")

signature_json=null
if [[ -n $signature ]]; then signature_json=$(jq -n --arg s "$signature" '$s'); fi

attestation_json=null
if [[ -n $attestation ]]; then
  jq -e 'type == "object"' <<<"$attestation" >/dev/null ||
    wcf_die "--attestation must be a JSON object, got: $attestation"
  attestation_json=$attestation
fi

record=$(
  jq -n \
    --arg logical_name "$logical_name" \
    --arg sha256 "$sha256" \
    --argjson size "$size" \
    --arg source_commit "$source_commit" \
    --arg build_workflow "$build_workflow" \
    --arg linkage "$linkage" \
    --arg target_os "$target_os" \
    --arg abi "$abi" \
    --arg min_os "$min_os" \
    --argjson toolchain "$toolchain" \
    --argjson signature "$signature_json" \
    --argjson attestation "$attestation_json" \
    --arg provenance "$provenance" \
    --arg asset_name "$asset_name" \
    '{ ($logical_name): {
         sha256: $sha256,
         size: $size,
         source_commit: $source_commit,
         build_workflow: $build_workflow,
         linkage: $linkage,
         target_os: $target_os,
         abi: $abi,
         min_os: $min_os,
         toolchain: $toolchain,
         signature: $signature,
         attestation: $attestation,
         provenance: $provenance,
         asset_name: $asset_name,
         logical_name: $logical_name
       } }'
)

wcf_log "record: $logical_name  sha256=$sha256  size=$size"
wcf_log "record: asset_name=$asset_name (${#asset_name} characters)"

if [[ -n $out ]]; then
  mkdir -p -- "$(dirname -- "$out")"
  printf '%s\n' "$record" >"$out"
  wcf_log "record: wrote $out"
else
  printf '%s\n' "$record"
fi
