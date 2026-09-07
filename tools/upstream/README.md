# `tools/upstream` — pin and fetch the upstream source tree

Package `wcf_tool_upstream`. Build-time tooling; nothing here is shipped in
`wallet_core_flutter`, `wallet_core_flutter_bindings`, or
`wallet_core_flutter_native`, and nothing here is reachable from them.

```
melos run upstream:fetch -- --from <archive.tar.gz> --commit <40-hex sha>
melos run upstream:fetch                             # CI: download from the pin
```

The command reads `upstream.repo` and `upstream.tag` from
`compat_manifest.json`, puts that tree into `third_party/wallet-core/`, writes
the three `schemas.*` digests back into the manifest, and regenerates
`THIRD_PARTY_NOTICES.md` from upstream's own licence files. T1.3 (ffigen), T1.4
(protobuf), and T1.5 (registry) read that tree and nothing else.

`third_party/` is git-ignored: the tree is a build input reproduced from the
pin, not source we carry.

## Modes

| Mode | Flag | Used by |
|---|---|---|
| Pre-fetched archive | `--from <path>` | Local development, air-gapped CI |
| Download | *(none)* | CI, from `https://codeload.github.com/<repo>/tar.gz/refs/tags/<tag>` |

Both modes end in the same code path: the archive is hashed, then extracted
with the same validation. The URL is built by `sourceArchiveUrl` in
`lib/download.dart` — a pure function of `upstream.repo` and `upstream.tag`, so
that what CI fetches is decided by the manifest and by nothing else.

## The commit sha

A GitHub source archive is a `git archive` of the tree: it carries no object
metadata, so the commit sha cannot be derived from it. It is therefore supplied
with `--commit`:

- while `upstream.commit` holds a `TBD-` placeholder, `--commit` is required
  and is adopted;
- once `upstream.commit` holds a 40-hex sha, `--commit` is **verified** against
  it and a mismatch is an error. A fetch checks the pin; it never repins.

`identity.upstream_commit` (PRD §15.3) is filled from the same value when it
still holds a placeholder, so the two can never disagree.

## Directory hash — normative definition

`schemas.headers_sha` and `schemas.proto_dir_sha` are digests of directory
trees, computed as follows.

1. Walk the tree and collect every **regular file**. Directories contribute
   nothing of their own, so an empty directory is invisible to the digest.
   Symbolic links and other non-regular entries are an error, not something to
   skip: skipping would let the digest under-cover the tree.
2. For each file take
   - its path relative to the hashed root, written with POSIX `/` separators
     and no leading `./`; and
   - the lowercase-hex SHA-256 of its bytes.
3. Sort the pairs by relative path, ordinal (UTF-16 code-unit) comparison.
4. Concatenate `"<relative path>\n<sha256>\n"` for each pair, in that order.
5. The directory hash is the lowercase-hex SHA-256 of the UTF-8 encoding of
   that concatenation.

The digest is a function of file paths and file contents and of nothing else:
not extraction order, not mtimes, not permissions, not the absolute location of
the root, not the filesystem's directory-listing order. Two extractions of the
same archive to different paths produce the same digest, and so does a
`git checkout` of the same tree.

`schemas.registry_json_sha` is the plain SHA-256 of `registry.json`'s bytes —
one file, so no tree rule applies.

These are integrity hashes over build inputs (PRD §12.3). They are not
cryptography in the wallet sense, and this package implements none (repo rule
2).

## Extraction safety

`third_party/wallet-core/` is **untrusted third-party data**. The archive is a
third party's bytes and its entry names are treated as hostile:

- every entry name is normalised and rejected if it is absolute, carries a
  Windows drive or UNC prefix, contains a NUL, or normalises to `..` or below
  (`lib/paths.dart`, `safeRelativePath`);
- every symlink target is rejected if it is absolute or resolves outside the
  extraction root (`safeSymlinkTarget`);
- the archive must have exactly one top-level directory, which is stripped;
- the destination is emptied first, so the tree is a function of the archive
  alone and a stale file from an earlier pin cannot survive into a digest.

The tool writes bytes and reads back only the two licence files and the bytes
that go into the digests. It never executes anything from the tree and never
reads anything in it as configuration or instructions.

## Idempotence

Running the fetch twice at the same pin leaves `compat_manifest.json` and
`THIRD_PARTY_NOTICES.md` byte-identical. The manifest is decoded, mutated, and
re-encoded with the repository's formatting (two-space indent, one trailing
newline), and both files are written only when their bytes would change.

## Layout

| File | Contents |
|---|---|
| `bin/fetch.dart` | Command-line entry point. |
| `lib/fetch.dart` | Option parsing and the run itself. |
| `lib/paths.dart` | Archive-entry path validation (pure). |
| `lib/extract.dart` | Archive decoding and safe extraction. |
| `lib/hashing.dart` | SHA-256 helpers and the directory hash. |
| `lib/download.dart` | URL construction (pure) and the CI download. |
| `lib/manifest_edit.dart` | Manifest read/encode and commit-pin resolution. |
| `lib/notices.dart` | `THIRD_PARTY_NOTICES.md` rendering. |
