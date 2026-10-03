#!/bin/sh
# How eval/option1/consumer/ was generated. Run once; the result is committed.
#
# Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
# Not affiliated with or endorsed by Trust Wallet.
#
#   eval/option1/tool/create_consumer.sh            # refuses if consumer/ exists
#
# Plain `flutter create`, with two differences in *where*, not *what*:
#
#  - HOME points at an empty directory under $TMPDIR for the duration, so
#    `flutter create` finds no Apple signing identity in the developer's
#    keychain and writes no DEVELOPMENT_TEAM into the generated Xcode projects.
#    Left alone it picks the machine owner's team id and commits it — a
#    personal identifier, and a project that is not the same on any other
#    machine. A team is a signing decision for whoever runs on a device.
#  - The app is generated under $TMPDIR and copied in without the IDE files
#    (.idea/, *.iml), which no step of the evaluation uses.
#
# Every file changed after this script ran is listed in eval/option1/README.md.
set -eu

repo=$(cd "$(dirname "$0")/../../.." && pwd)
dest="$repo/eval/option1/consumer"
if [ -e "$dest" ]; then
  echo "error: $dest exists; delete it first to regenerate" >&2
  exit 1
fi

tmp="${TMPDIR:-/tmp}"
work=$(mktemp -d "$tmp/wcf-option1-create.XXXXXX")
mkdir -p "$work/home"

HOME="$work/home" flutter create \
  --project-name wcf_eval_option1 \
  --org dev.wcf.eval \
  --platforms ios,android,macos \
  --no-pub \
  "$work/consumer"

if grep -rq 'DEVELOPMENT_TEAM' "$work/consumer/ios" "$work/consumer/macos"; then
  echo "error: a DEVELOPMENT_TEAM was written despite the empty HOME" >&2
  exit 1
fi

mkdir -p "$dest"
(cd "$work/consumer" && tar -cf - --exclude ./.idea --exclude '*.iml' .) |
  (cd "$dest" && tar -xf -)
rm -rf "$work"
echo "generated $dest"
