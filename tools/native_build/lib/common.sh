# shellcheck shell=bash
#
# tools/native_build/lib/common.sh — helpers shared by the native build and gate
# scripts. Sourced, never executed.
#
# Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
# Not affiliated with or endorsed by Trust Wallet.
#
# Every script under tools/native_build/ is build-time tooling. Nothing here is
# reachable from wallet_core_flutter, wallet_core_flutter_bindings, or
# wallet_core_flutter_native at runtime (AGENTS.md rule 3, PRD §16 S4).

set -euo pipefail

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

wcf_log() { printf '%s\n' "$*" >&2; }

wcf_section() { printf '\n== %s ==\n' "$*" >&2; }

wcf_die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

# Echo a command in copy-pasteable form and then run it. Every gate in this
# directory runs through wcf_run so that the log records the exact command that
# produced the result (DECISION-9 §5, DECISION-14 §2.1).
wcf_run() {
  local q=()
  local arg
  for arg in "$@"; do q+=("$(printf '%q' "$arg")"); done
  printf '+ %s\n' "${q[*]}" >&2
  "$@"
}

# A scratch directory inside TMPDIR. `mktemp -d` with no template ignores
# TMPDIR on macOS (it uses the Darwin per-user temp directory), which breaks in
# any environment where that directory is not writable; an explicit template
# does not.
wcf_mktemp_dir() {
  local base=${TMPDIR:-/tmp}
  base=${base%/}
  mktemp -d "$base/wcf-native-build.XXXXXXXX"
}

wcf_require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || wcf_die "required command not found: $cmd"
  done
}

# ---------------------------------------------------------------------------
# Hashing and sizes (PRD §12.3; AGENTS.md rule 2 permits integrity hashing)
# ---------------------------------------------------------------------------

# Lowercase 64-hex sha256 of a file. macOS ships shasum, Linux ships sha256sum.
wcf_sha256() {
  local file=$1
  [[ -f $file ]] || wcf_die "not a file: $file"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | cut -d' ' -f1
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | cut -d' ' -f1
  else
    wcf_die 'neither shasum nor sha256sum is available'
  fi
}

wcf_size() {
  local file=$1
  [[ -f $file ]] || wcf_die "not a file: $file"
  # BSD stat and GNU stat disagree on flags; wc -c is portable and exact.
  wc -c <"$file" | tr -d ' '
}

# ---------------------------------------------------------------------------
# Identity values (DECISION-14 §2.1)
#
# The preprocessor can only check the length of an injected literal, so the
# shape checks live here, in front of every build.
# ---------------------------------------------------------------------------

wcf_validate_commit() {
  local commit=$1
  [[ $commit =~ ^[0-9a-f]{40}$ ]] ||
    wcf_die "upstream commit must be 40 lowercase hex characters, got: $commit"
}

# as_<upstreamTag>_<3-digit sequence>. The tag may contain dots and dashes; the
# sequence is exactly three digits. Sequence 000 is reserved by convention for
# local developer builds that are never uploaded (see the README).
wcf_validate_artifact_set_id() {
  local id=$1
  [[ $id =~ ^as_[0-9A-Za-z._-]+_[0-9]{3}$ ]] ||
    wcf_die "artifact set id must look like as_<tag>_<nnn>, got: $id"
  [[ $id != *__* ]] ||
    wcf_die "artifact set id must not contain '__' (it is the asset-name separator): $id"
}

# A published record carries an absolute workflow-run URL. A local build passes
# something else; that is allowed here and warned about, and the manifest
# validator — which only ever sees published records — requires the URL.
wcf_validate_build_workflow() {
  local url=$1
  [[ -n $url ]] || wcf_die 'build workflow must not be empty'
  [[ $url != *'"'* && $url != *'\'* ]] ||
    wcf_die "build workflow must not contain a quote or a backslash: $url"
  if [[ $url != https://* ]]; then
    wcf_log "warning: build workflow is not an absolute https URL ($url)."
    wcf_log "warning: artifacts built this way must not be published; DECISION-14 §2.1 requires the workflow-run URL."
  fi
}

wcf_require_identity_values() {
  wcf_validate_commit "$1"
  wcf_validate_artifact_set_id "$2"
  wcf_validate_build_workflow "$3"
}

# The -D flags that inject the identity values into wcf_build_info.c.
#
# The double quotes are part of the argument: the C preprocessor needs a string
# literal, so the argv element must read -DWCF_UPSTREAM_COMMIT="d692…". Printed
# one per line so a caller can read them into an array with `mapfile`, which
# passes them to clang with no further shell quoting to get wrong.
wcf_identity_defines() {
  local commit=$1 set_id=$2 workflow=$3
  printf -- '-DWCF_UPSTREAM_COMMIT="%s"\n' "$commit"
  printf -- '-DWCF_ARTIFACT_SET_ID="%s"\n' "$set_id"
  printf -- '-DWCF_BUILD_WORKFLOW="%s"\n' "$workflow"
}

# ---------------------------------------------------------------------------
# Asset naming (DECISION-14 §3.1)
# ---------------------------------------------------------------------------

# logical_name with '/' replaced by '-'.
wcf_flat_name() { printf '%s' "${1//\//-}"; }

# <artifact_set_id>__<full 64-hex sha256>__<flat_name>, and never longer than
# the 255 characters a GitHub release asset name allows.
wcf_asset_name() {
  local set_id=$1 sha=$2 logical=$3
  [[ $sha =~ ^[0-9a-f]{64}$ ]] || wcf_die "asset name needs a full 64-hex digest, got: $sha"
  [[ $logical != *__* ]] || wcf_die "logical name must not contain '__': $logical"
  local name="${set_id}__${sha}__$(wcf_flat_name "$logical")"
  (( ${#name} <= 255 )) ||
    wcf_die "asset name is ${#name} characters, over the 255-character GitHub limit: $name"
  printf '%s' "$name"
}

# ---------------------------------------------------------------------------
# Manifest reading (build inputs only; the manifest is never written from here)
# ---------------------------------------------------------------------------

# Read a dotted key out of compat_manifest.json. Fails if the value is still a
# TBD- placeholder, naming the task that fills it.
wcf_manifest_value() {
  local manifest=$1 key=$2
  wcf_require_cmd jq
  [[ -f $manifest ]] || wcf_die "manifest not found: $manifest"
  local value
  value=$(jq -r --arg k "$key" 'getpath($k | split("."))  // empty' "$manifest")
  [[ -n $value ]] || wcf_die "manifest $manifest has no value at $key"
  if [[ $value == TBD-* ]]; then
    wcf_die "manifest $manifest still has the placeholder $value at $key; pass the value explicitly or wait for that task"
  fi
  printf '%s' "$value"
}

# ---------------------------------------------------------------------------
# Repository layout
# ---------------------------------------------------------------------------

# Absolute path of the repository root, derived from this file's location so
# the scripts work from any working directory.
wcf_repo_root() {
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd
}

wcf_identity_source() {
  printf '%s/packages/wallet_core_flutter_native/src/identity/wcf_build_info.c' "$(wcf_repo_root)"
}
