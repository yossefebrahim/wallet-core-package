#!/usr/bin/env bash
#
# consumer_check.sh — PRD §12.2 step 11, T1.16: consume the three packages the
# way a real app will. A fresh `flutter create` app; the packages published to
# a local package repository; the SDK added as a hosted dependency, never by
# path; debug and release builds for Android and iOS; the M0 flow run on a
# device. No manual native edits.
#
# Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
# Not affiliated with or endorsed by Trust Wallet.
#
# STATUS (T1.16a). create_consumer, publish_locally and report work today.
# add_dependency, the four builds and run_m0_flow depend on how the native
# library is packaged (build hooks or Gradle/podspec) and exit 2 with
# "waiting for DECISION-2 (T1.16b)" until that decision lands; each says what
# it will run.
#
# Everything is written under the work directory, outside the repository:
# $WCF_CONSUMER_CHECK_DIR, default $TMPDIR/wcf-consumer-check. Nothing is
# downloaded; the package repository listens on 127.0.0.1 only. Stage results
# are kept in <work dir>/status/ for `report`.
#
# Bash 3.2 (macOS /bin/bash): no associative arrays, no mapfile, no ${x,,}.
set -euo pipefail

STAGES="create_consumer publish_locally add_dependency build_debug_android \
build_release_android build_debug_ios build_release_ios run_m0_flow report"

usage() {
  cat <<USAGE
Usage: tools/consumer_check.sh [--stage NAME] [--device DEVICE_ID]

Runs PRD §12.2 step 11 against a fresh consumer app. With no --stage, runs
every stage in order (each in its own process), stops at the first failure,
and prints the report. With --stage, runs that one stage alone.

Stages, in order:
  create_consumer        flutter create, under an empty HOME (no team id)
  publish_locally        publish the three packages to a loopback package
                         repository and fetch them back over HTTP
  add_dependency         add wallet_core_flutter as a hosted dependency
  build_debug_android    flutter build apk --debug
  build_release_android  flutter build apk --release
  build_debug_ios        flutter build ios --debug --no-codesign
  build_release_ios      flutter build ios --release --no-codesign
  run_m0_flow            run the M0 flow on --device DEVICE_ID
  report                 summarize the recorded stage results

Exit status: 0 passed; 1 failed; 2 waiting for DECISION-2 (T1.16b);
64 usage error.

Work directory: \$WCF_CONSUMER_CHECK_DIR, default \$TMPDIR/wcf-consumer-check
(must be outside the repository).
USAGE
}

usage_error() {
  echo "consumer_check: $*" >&2
  usage >&2
  exit 64
}

STAGE=""
DEVICE_ID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --stage)
      [ $# -ge 2 ] || usage_error "--stage needs a stage name"
      STAGE="$2"
      shift 2
      ;;
    --device)
      [ $# -ge 2 ] || usage_error "--device needs a device id"
      DEVICE_ID="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage_error "unknown argument: $1"
      ;;
  esac
done

if [ -n "$STAGE" ]; then
  case " $STAGES " in
    *" $STAGE "*) ;;
    *) usage_error "unknown stage: $STAGE" ;;
  esac
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
SCRIPT_PATH="$REPO_ROOT/tools/consumer_check.sh"
tmp_base="${TMPDIR:-/tmp}"
WORK_DIR="${WCF_CONSUMER_CHECK_DIR:-${tmp_base%/}/wcf-consumer-check}"

# The work directory must not be inside the checkout: a consumer app or a
# staged package there would be picked up by the workspace and by git.
mkdir -p "$(dirname "$WORK_DIR")"
work_parent="$(cd "$(dirname "$WORK_DIR")" && pwd -P)"
WORK_DIR="$work_parent/$(basename "$WORK_DIR")"
case "$WORK_DIR/" in
  "$REPO_ROOT"/*) usage_error "the work directory must be outside the repository: $WORK_DIR" ;;
esac

CONSUMER_DIR="$WORK_DIR/consumer"
PUB_REPOSITORY_DIR="$WORK_DIR/pub-repository"
STATUS_DIR="$WORK_DIR/status"

# --- Stage bookkeeping. Every stage runs as the only stage of its process, so
# --- these may exit.

record() {
  mkdir -p "$STATUS_DIR"
  printf '%s\n' "$2" >"$STATUS_DIR/$1"
}

pass() {
  echo "$1: OK — $2"
  record "$1" "ok — $2"
}

fail() {
  local stage="$1"
  shift
  echo "$stage: FAILED — $*" >&2
  record "$stage" "failed — $*"
  exit 1
}

# A stage whose commands depend on the packaging mechanism DECISION-2 picks.
waiting() {
  local stage="$1"
  shift
  echo "$stage: waiting for DECISION-2 (T1.16b)"
  echo "  will run: $*"
  record "$stage" "waiting for DECISION-2 (T1.16b)"
  exit 2
}

require() {
  command -v "$2" >/dev/null 2>&1 || fail "$1" "$2 is not on PATH"
}

# --- Stages ------------------------------------------------------------------

# A fresh app, exactly as `flutter create` writes it. HOME points at an empty
# directory for the call, so flutter finds no Apple signing identity and writes
# no DEVELOPMENT_TEAM — a personal identifier (same reason as
# eval/option1/tool/create_consumer.sh). --no-pub: dependencies are
# add_dependency's business.
create_consumer() {
  require create_consumer flutter
  mkdir -p "$WORK_DIR"
  rm -rf "$CONSUMER_DIR"
  local empty_home
  empty_home="$(mktemp -d "${tmp_base%/}/wcf-consumer-home.XXXXXX")"
  if ! HOME="$empty_home" flutter create \
    --project-name wcf_consumer_check \
    --org dev.wcf.consumer \
    --platforms android,ios \
    --no-pub \
    "$CONSUMER_DIR"; then
    rm -rf "$empty_home"
    fail create_consumer "flutter create failed"
  fi
  rm -rf "$empty_home"
  if grep -rq 'DEVELOPMENT_TEAM' "$CONSUMER_DIR/ios"; then
    fail create_consumer "a DEVELOPMENT_TEAM was written despite the empty HOME"
  fi
  if grep -q 'wallet_core_flutter' "$CONSUMER_DIR/pubspec.yaml"; then
    fail create_consumer "the fresh app already names wallet_core_flutter"
  fi
  pass create_consumer "$CONSUMER_DIR (android, ios; no DEVELOPMENT_TEAM)"
}

# The three packages, staged and served by the T1.19 loopback repository
# (tools/packaging_eval/lib/local_pub_repository.dart), fetched back and
# checked by tools/consumer_check/publish_locally.dart. The server stops when
# the stage ends: its port is baked into the staged pubspecs, so the consumer's
# `flutter pub get` must run against the same running server — in one process,
# as tools/packaging_eval/lib/consumer_gen.dart does — which is add_dependency.
publish_locally() {
  require publish_locally dart
  if [ ! -f "$REPO_ROOT/.dart_tool/package_config.json" ]; then
    fail publish_locally "no workspace package config; run \`melos bootstrap\` first"
  fi
  if ! (cd "$REPO_ROOT/tools/consumer_check" && dart run publish_locally.dart \
    --staging-dir "$PUB_REPOSITORY_DIR"); then
    fail publish_locally "see the output above"
  fi
  pass publish_locally "3 packages served on loopback and fetched back intact; staged under $PUB_REPOSITORY_DIR"
}

add_dependency() {
  waiting add_dependency \
    "serve the repository again and, while it runs, add" \
    "\`wallet_core_flutter: {hosted: <url>, version: <pin>}\` to $CONSUMER_DIR/pubspec.yaml" \
    "plus whatever the chosen mechanism needs there (Option 1: hooks.user_defines)," \
    "then \`flutter pub get\` and assert the lock shows the three packages hosted" \
    "and no path entry (tools/packaging_eval/lib/consumer_gen.dart assertHostedLock)"
}

build_debug_android() {
  waiting build_debug_android "(cd $CONSUMER_DIR && flutter build apk --debug --target-platform android-arm64,android-x64)"
}

build_release_android() {
  waiting build_release_android "(cd $CONSUMER_DIR && flutter build apk --release --target-platform android-arm64,android-x64)"
}

build_debug_ios() {
  waiting build_debug_ios "(cd $CONSUMER_DIR && flutter build ios --debug --no-codesign)"
}

build_release_ios() {
  waiting build_release_ios "(cd $CONSUMER_DIR && flutter build ios --release --no-codesign)"
}

run_m0_flow() {
  waiting run_m0_flow \
    "the example's M0 flow as an integration test in the consumer:" \
    "(cd $CONSUMER_DIR && flutter test integration_test -d ${DEVICE_ID:-<--device DEVICE_ID>})," \
    "debug and release, on the Android emulator and the iOS simulator"
}

report() {
  echo "consumer_check report — $WORK_DIR"
  local stage line
  for stage in $STAGES; do
    [ "$stage" = report ] && continue
    if [ -f "$STATUS_DIR/$stage" ]; then
      line="$(cat "$STATUS_DIR/$stage")"
    else
      line="not run"
    fi
    printf '  %-22s %s\n' "$stage" "$line"
  done
}

# Every stage but report, each in its own process so that its exit status is
# its own; stop at the first failure; a waiting stage does not stop the run.
# Exits 1 if a stage failed, else 2 if one is waiting, else 0.
run_all() {
  rm -rf "$STATUS_DIR"
  local stage status worst=0
  for stage in $STAGES; do
    [ "$stage" = report ] && continue
    status=0
    if [ -n "$DEVICE_ID" ]; then
      "$BASH" "$SCRIPT_PATH" --stage "$stage" --device "$DEVICE_ID" || status=$?
    else
      "$BASH" "$SCRIPT_PATH" --stage "$stage" || status=$?
    fi
    if [ "$status" -eq 2 ]; then
      worst=2
    elif [ "$status" -ne 0 ]; then
      worst=1
      break
    fi
  done
  report
  return "$worst"
}

if [ -n "$STAGE" ]; then
  "$STAGE"
else
  run_all
fi
