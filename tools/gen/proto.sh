#!/usr/bin/env bash
#
# proto.sh — the only supported way to produce
# packages/wallet_core_flutter_bindings/lib/src/generated/proto/.
#
# Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
# Not affiliated with or endorsed by Trust Wallet.
#
# WHAT IT DOES
#   1. Verifies that the `protoc` and `protoc-gen-dart` on PATH are exactly the
#      versions pinned in compat_manifest.json (`generators.protoc`,
#      `generators.protoc_gen_dart`). Both are printed on mismatch.
#   2. Runs protoc over every third_party/wallet-core/src/proto/*.proto at the
#      pinned upstream commit, emitting Dart into a staging directory and a
#      FileDescriptorSet into a temporary file. The output is staged and swapped.
#   3. Derives key_fields.json from that FileDescriptorSet: every message field
#      whose *proto* name contains `private_key`, keyed by the fully-qualified
#      protobuf message name — which is exactly what
#      `GeneratedMessage.info_.qualifiedMessageName` returns at runtime, so a
#      caller looks a message up without reflection (PRD §11.4).
#   4. Cross-checks every Dart class and field name recorded in key_fields.json
#      against the Dart protoc actually emitted, so the two cannot drift.
#   5. Formats the generated directory, so the committed output is
#      format-clean and `melos run format:check` needs no exclusion.
#
# WHY THE DESCRIPTOR SET AND NOT THE .proto TEXT. key_fields.json feeds PRD
# §11.4's reviewed per-family key-field list; a miss there is a private key
# injected into a request nobody checked. protoc's own parse of the same input
# that produced the Dart classes cannot disagree with those classes about
# nested messages, oneof members, map entries, or `import`s, whereas a
# hand-rolled .proto text parser can. The wire-format reader below is ~90 lines
# and needs no protobuf runtime, which is why this stays a plain shell script
# and does not depend on tools/gen/ being a Dart package.
#
# THE MATCH RULE IS DELIBERATELY WIDE. Substring `private_key`, so
# `fee_payer_private_key`, `owner_private_key`, `nonce_account_private_key` and
# BitcoinV2's plural `private_keys` are all caught. It over-matches on purpose:
# EOS's `private_key_type` is an enum selector, not key material. Every entry
# records its protobuf type so the human review PRD §11.4 requires starts from
# a complete list rather than a convenient one.
#
# third_party/ is untrusted input. This script feeds it to protoc and reads it
# as text; it executes nothing from it.

set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(cd -- "$here/../.." && pwd)

manifest="$root/compat_manifest.json"
proto_src="$root/third_party/wallet-core/src/proto"
out_dir="$root/packages/wallet_core_flutter_bindings/lib/src/generated/proto"

# Stable collation so the *.proto glob below expands in the same order on every
# host; protoc writes one Dart file per input, but key_fields.json is one file
# built from all of them.
export LC_ALL=C

die() {
  echo "proto.sh: $*" >&2
  exit 1
}

manifest_get() {
  python3 -c 'import json,sys
d = json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    d = d[k]
print(d)' "$manifest" "$1"
}

# --------------------------------------------------------------------------
# 1. Generator pins.
# --------------------------------------------------------------------------

[ -f "$manifest" ] || die "missing $manifest"
[ -d "$proto_src" ] || die "missing $proto_src — run 'melos run upstream:fetch' first"

want_protoc=$(manifest_get generators.protoc)
want_plugin=$(manifest_get generators.protoc_gen_dart)

command -v protoc >/dev/null 2>&1 ||
  die "protoc not found on PATH; compat_manifest.json pins protoc $want_protoc"

# `protoc --version` prints "libprotoc <version>".
have_protoc=$(protoc --version | awk '{print $2}')
if [ "$have_protoc" != "$want_protoc" ]; then
  die "protoc version mismatch
  compat_manifest.json generators.protoc = $want_protoc
  protoc on PATH                         = $have_protoc ($(command -v protoc))
Install the pinned protoc, or update the manifest deliberately and regenerate."
fi

plugin_path=$(command -v protoc-gen-dart || true)
[ -n "$plugin_path" ] ||
  die "protoc-gen-dart not found on PATH; install it with
  dart pub global activate protoc_plugin $want_plugin
and put \$HOME/.pub-cache/bin on PATH"

# protoc-gen-dart is a protoc plugin: it reads a CodeGeneratorRequest from
# stdin and has no --version flag. `dart pub global activate` writes the
# package and version into the launcher script it installs, so the launcher on
# PATH describes itself — which is stronger than asking pub what is activated,
# because it is the file protoc will actually execute.
have_plugin=$(awk '/^# Package: protoc_plugin$/ {ok=1}
  ok && /^# Version: / {print $3; exit}' "$plugin_path")
if [ -z "$have_plugin" ]; then
  die "cannot determine the version of protoc-gen-dart at $plugin_path
It does not look like a 'dart pub global activate protoc_plugin' launcher, so
the pin in compat_manifest.json (protoc_gen_dart = $want_plugin) cannot be
enforced. Install it with:
  dart pub global activate protoc_plugin $want_plugin"
fi
if [ "$have_plugin" != "$want_plugin" ]; then
  die "protoc-gen-dart version mismatch
  compat_manifest.json generators.protoc_gen_dart = $want_plugin
  protoc-gen-dart on PATH                         = $have_plugin ($plugin_path)
The generated code and the 'protobuf' runtime pinned in
packages/wallet_core_flutter_bindings/pubspec.yaml are a matched pair; a
different plugin version drifts them apart. Install the pinned one with:
  dart pub global activate protoc_plugin $want_plugin"
fi

command -v dart >/dev/null 2>&1 || die "dart not found on PATH"
command -v python3 >/dev/null 2>&1 ||
  die "python3 not found on PATH (used to read the protoc descriptor set)"

# --------------------------------------------------------------------------
# 2. Generate.
# --------------------------------------------------------------------------

# `mktemp -d` with no template ignores TMPDIR on macOS (it uses the Darwin
# per-user temp directory), which breaks wherever that is not writable; an
# explicit template does not. Same reasoning as tools/native_build/lib/common.sh.
tmp_base=${TMPDIR:-/tmp}
work=$(mktemp -d "${tmp_base%/}/wcf-gen-proto.XXXXXXXX")
staging="$out_dir.staging.$$"
cleanup() {
  if [ -d "$out_dir.old" ] && [ ! -e "$out_dir" ]; then
    mv "$out_dir.old" "$out_dir"
  fi
  rm -rf "$out_dir.old"
  rm -rf "$staging"
  rm -rf "$work"
}
trap cleanup EXIT
descriptors="$work/descriptors.bin"

mkdir -p "$staging"

pushd "$proto_src" >/dev/null
# nullglob so an empty directory yields an empty array rather than the literal
# pattern, and the guard below reports it instead of protoc doing so obscurely.
shopt -s nullglob
protos=(*.proto)
shopt -u nullglob
[ "${#protos[@]}" -gt 0 ] || die "no .proto files in $proto_src"
protoc \
  -I . \
  --dart_out="$staging" \
  --descriptor_set_out="$descriptors" \
  "${protos[@]}"
popd >/dev/null

proto_in=${#protos[@]}
dart_out=$(find "$staging" -name '*.dart' | wc -l | tr -d ' ')

# --------------------------------------------------------------------------
# 3. key_fields.json, from protoc's own descriptors.
# --------------------------------------------------------------------------

python3 - "$descriptors" "$manifest" "$proto_src" "$staging" <<'PY'
import json, os, sys

descriptors, manifest_path, proto_src, out_dir = sys.argv[1:5]

MATCH = 'private_key'

# --- minimal protobuf wire reader (descriptor.proto subset) ----------------

def read_varint(b, i):
    r = 0
    s = 0
    while True:
        x = b[i]
        i += 1
        r |= (x & 0x7F) << s
        if not x & 0x80:
            return r, i
        s += 7

def fields(b):
    """Wire-decode one message into {field_number: [value, ...]}."""
    out = {}
    i, n = 0, len(b)
    while i < n:
        tag, i = read_varint(b, i)
        num, wire = tag >> 3, tag & 7
        if wire == 0:
            v, i = read_varint(b, i)
        elif wire == 2:
            ln, i = read_varint(b, i)
            v = b[i:i + ln]
            i += ln
        elif wire == 5:
            v, i = b[i:i + 4], i + 4
        elif wire == 1:
            v, i = b[i:i + 8], i + 8
        else:
            raise SystemExit('proto.sh: unsupported wire type %d in descriptor '
                             'set' % wire)
        out.setdefault(num, []).append(v)
    return out

def text(d, num):
    v = d.get(num)
    return v[0].decode('utf-8') if v else ''

def uint(d, num, default=0):
    v = d.get(num)
    return v[0] if v else default

# FieldDescriptorProto.Type
TYPE = {1: 'double', 2: 'float', 3: 'int64', 4: 'uint64', 5: 'int32',
        6: 'fixed64', 7: 'fixed32', 8: 'bool', 9: 'string', 10: 'group',
        11: 'message', 12: 'bytes', 13: 'uint32', 14: 'enum',
        15: 'sfixed32', 16: 'sfixed64', 17: 'sint32', 18: 'sint64'}
LABEL_REPEATED = 3

messages = {}
by_file = {}

def walk(raw, package, path, proto_file):
    """DescriptorProto -> record matching fields, then recurse into nested_type."""
    d = fields(raw)
    path = path + [text(d, 1)]

    # DescriptorProto.options(7).map_entry(7): synthetic map-entry messages are
    # not real messages and have no Dart class of their own.
    opts = d.get(7)
    map_entry = bool(uint(fields(opts[0]), 7)) if opts else False

    if not map_entry:
        matched = []
        for raw_field in d.get(2, []):          # DescriptorProto.field
            f = fields(raw_field)
            name = text(f, 1)                   # FieldDescriptorProto.name
            if MATCH not in name:
                continue
            matched.append({
                'protoName': name,
                'dartName': text(f, 10),        # json_name, lowerCamelCase
                'number': uint(f, 3),
                'repeated': uint(f, 4) == LABEL_REPEATED,
                'type': TYPE.get(uint(f, 5), 'unknown'),
            })
        if matched:
            joined = '.'.join(path)
            qualified = '%s.%s' % (package, joined) if package else joined
            messages[qualified] = {
                'file': proto_file,
                'dartFile': proto_file[:-len('.proto')] + '.pb.dart',
                # protoc_plugin flattens nested messages: A.B -> A_B.
                'dartClass': '_'.join(path),
                'fields': sorted(matched, key=lambda x: x['number']),
            }
            by_file.setdefault(proto_file, []).append(qualified)

    for nested in d.get(3, []):                 # DescriptorProto.nested_type
        walk(nested, package, path, proto_file)

with open(descriptors, 'rb') as fh:
    fds = fields(fh.read())

for raw_file in fds.get(1, []):                 # FileDescriptorSet.file
    f = fields(raw_file)
    proto_file = text(f, 1)                     # FileDescriptorProto.name
    package = text(f, 2)                        # FileDescriptorProto.package
    for raw_msg in f.get(4, []):                # FileDescriptorProto.message_type
        walk(raw_msg, package, [], proto_file)

for names in by_file.values():
    names.sort()

# --- cross-check the recorded Dart names against the emitted Dart ----------
#
# dartClass and dartName are this script's model of what protoc_plugin names
# things. Verifying them against the files protoc just wrote turns a silent
# modelling error into a failed generation.

problems = []
sources = {}
for entry in messages.values():
    path = os.path.join(out_dir, entry['dartFile'])
    if path not in sources:
        try:
            with open(path) as fh:
                sources[path] = fh.read()
        except OSError as e:
            problems.append(str(e))
            sources[path] = ''
    src = sources[path]
    if 'class %s extends' % entry['dartClass'] not in src:
        problems.append('%s: no class %s in %s'
                        % (entry['file'], entry['dartClass'], entry['dartFile']))
    for field in entry['fields']:
        if "'%s'" % field['dartName'] not in src:
            problems.append("%s: %s.%s -> no Dart name '%s' in %s"
                            % (entry['file'], entry['dartClass'],
                               field['protoName'], field['dartName'],
                               entry['dartFile']))

# --- files that mention private_key but declare no such field --------------
#
# Recorded rather than dropped: PRD §11.4 wants a complete list, and a silent
# gap between "46 .proto files mention private_key" and the entry count is the
# kind of thing a reviewer should not have to rediscover. Today the only such
# file is Common.proto, where the matches are SigningError enum *value* names.

mentions_without_fields = {}
for name in sorted(os.listdir(proto_src)):
    if not name.endswith('.proto') or name in by_file:
        continue
    with open(os.path.join(proto_src, name)) as fh:
        lines = [ln.strip() for ln in fh if MATCH in ln]
    if lines:
        mentions_without_fields[name] = lines

if problems:
    sys.stderr.write('proto.sh: key_fields.json disagrees with the generated '
                     'Dart:\n')
    for p in problems:
        sys.stderr.write('  %s\n' % p)
    raise SystemExit(1)

with open(manifest_path) as fh:
    manifest = json.load(fh)

document = {
    'generated': 'tools/gen/proto.sh — do not hand-edit',
    'source': 'protoc FileDescriptorSet of '
              'third_party/wallet-core/src/proto/*.proto',
    'upstream': {
        'repo': manifest['upstream']['repo'],
        'tag': manifest['upstream']['tag'],
        'commit': manifest['upstream']['commit'],
        'proto_dir_sha': manifest['schemas']['proto_dir_sha'],
    },
    'matchRule': "field name contains '%s'" % MATCH,
    'key': 'fully-qualified protobuf message name, as returned by '
           'GeneratedMessage.info_.qualifiedMessageName',
    'summary': {
        'protoFilesScanned': len([n for n in os.listdir(proto_src)
                                  if n.endswith('.proto')]),
        'protoFilesWithKeyFields': len(by_file),
        'messages': len(messages),
        'fields': sum(len(m['fields']) for m in messages.values()),
    },
    'messages': messages,
    'byFile': by_file,
    'mentionsWithoutFieldMatches': mentions_without_fields,
}

with open(os.path.join(out_dir, 'key_fields.json'), 'w') as fh:
    json.dump(document, fh, indent=2, sort_keys=True)
    fh.write('\n')

print('proto.sh: key_fields.json — %d messages, %d fields, %d/%d .proto files'
      % (document['summary']['messages'], document['summary']['fields'],
         document['summary']['protoFilesWithKeyFields'],
         document['summary']['protoFilesScanned']))
PY

# --------------------------------------------------------------------------
# 4. Format, as the last step of generation.
# --------------------------------------------------------------------------

dart format "$staging" >/dev/null

rm -rf "$out_dir.old"
if [ -e "$out_dir" ]; then mv "$out_dir" "$out_dir.old"; fi
mv "$staging" "$out_dir"
rm -rf "$out_dir.old"

echo "proto.sh: $proto_in .proto in -> $dart_out .dart out in ${out_dir#"$root"/}"
