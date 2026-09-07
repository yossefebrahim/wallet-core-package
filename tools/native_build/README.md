# `tools/native_build/`

Scripts that produce one native artifact set and prove it is fit to publish.
`.github/workflows/build-native.yml` calls them; each one also runs on its own
and answers `--help`.

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not
affiliated with or endorsed by Trust Wallet.

Everything here is **build-time tooling**. Nothing in this directory is
reachable from `wallet_core_flutter`, `wallet_core_flutter_bindings` or
`wallet_core_flutter_native` at runtime (AGENTS.md rule 3, PRD §16 S4).

| Script | What it does |
|---|---|
| `build_apple.sh` | DECISION-9 Option A′: relink upstream's release-asset static archives with our identity object into one dynamic library per Apple slice, emit a dSYM, run the export gate, write the manifest record. |
| `build_android.sh` | DECISION-9 Option B: build upstream's git tree at the pinned commit with our identity object linked in, extract one `.so` per ABI, run both gates, write the manifest record. |
| `generate_symbol_list.sh` | The canonical list of exported `TW*` C functions, derived from the tag's own headers. |
| `check_exports.sh` | Export-visibility gate. Runs on every artifact, on both platforms. |
| `check_alignment.sh` | 16 KB page-alignment gate. 64-bit ELF only. |
| `emit_artifact_record.sh` | The fourteen-field per-artifact record of DECISION-14 §5.1. |
| `lib/common.sh` | Shared helpers. Sourced, never executed. |

## The macOS host library for `melos run test:native`

The highest-value output of this directory, and what T1.6 depends on. One
invocation produces it:

```
tools/native_build/build_apple.sh \
  --tarball ~/.cache/wcf-upstream/4.8.0/TrustWalletCore-4.8.0.tar.xz \
  --commit d692ac27749d0c615e17c751b70ab4f0aa75c59b \
  --slices macos-arm64_x86_64 \
  --out-dir "$TMPDIR/wcf-native" \
  --expect-symbol-count 464
```

and the library lands at a path that is fixed and may be depended on:

```
<out-dir>/artifacts/macos/arm64_x86_64/libTrustWalletCore.dylib
```

It is a universal `arm64` + `x86_64` Mach-O dynamic library exporting all 464
`TW*` functions plus `wcf_build_info`. `dart:ffi` opens it and calls it; that
was verified on 2026-09-07 against this exact script.

`melos run native:host-lib` wraps the same command and reads the tag and commit
from `compat_manifest.json`, so it starts working once T1.1 fills
`upstream.commit`. Until then, pass `--commit` yourself as above. Nothing is
written inside the repository: pick an `--out-dir` outside the checkout, as the
melos script does.

A local build is identified as `as_<tag>_000` with `build_workflow` `local`.
**Sequence `000` is reserved for local builds and is never uploaded** — the
script warns that an artifact built that way must not be published, and the
manifest validator rejects a non-URL `build_workflow` on a populated record.

## The two gates, and the exact command each runs

Both are mandatory on every artifact in every set (DECISION-9 §5). They are
scripts rather than inline steps so that T1.19's packaging harness runs the
same check on the packaged library that the build ran on the artifact.

**Export visibility** — `check_exports.sh`:

```
llvm-nm --defined-only --extern-only [--arch=<arch>] <artifact>
```

reconciled in both directions against the canonical symbol list, plus a
presence check for `wcf_build_info` (`_wcf_build_info` on Mach-O). A universal
Mach-O is checked one architecture at a time, so a symbol missing from one
slice cannot be masked by the other. Extra `TW*` exports fail too: they mean
the list is stale.

This is the gate upstream issue #4638 exists for — a Flutter user got
`undefined symbol: TWAnyAddressIsValid` from an `.aar` built by upstream's own
`tools/android-build`. If it fails on Android, the first remedy is
`-fvisibility=default` on the TW translation units and the second is removing
any version script or `--gc-sections` from that link. Do not publish past a
failure.

**16 KB page alignment** — `check_alignment.sh`:

```
llvm-readelf -l <artifact>
```

Every `LOAD` program header's `Align` column must read `0x4000`. A 32-bit ELF
is reported and skipped; Apple artifacts are not checked at all, because
alignment of this kind is an ELF property. Neither `readelf` nor `llvm-readelf`
is on `PATH` on macOS, so pass `--readelf` with the NDK-qualified path.

PRD §12.2 step 8 also requires the packaged APK/AAB to preserve the alignment
(`zipalign -c -P 16 -v`). That is a check on a consumer build, so it belongs to
T1.19's harness rather than to the artifact build.

## Where the symbol list comes from

`generate_symbol_list.sh` derives it from upstream's headers at build time:

```
grep -rhoE "^[A-Za-z_][A-Za-z0-9_ *]*\bTW[A-Za-z0-9_]+\(" <headers> \
  | grep -oE "TW[A-Za-z0-9_]+\($" | tr -d '(' | sort -u
```

At 4.8.0 that is exactly 464 names, and exactly the `T _TW…` symbols upstream's
own dynamic framework exports (evidence §2.6). No copy of the list is kept in
this repository, deliberately: a hand-maintained list goes stale silently and
the whole point of the gate is to catch that.

**T1.4/T1.5 own the canonical list** as a generated artifact (DECISION-9 §5).
When it lands, pass it to both consumers with `--symbol-list` and this script
becomes the cross-check rather than the source. Both `build_apple.sh` and
`build_android.sh` already accept the flag, so wiring it is a workflow edit and
not a code change here.

## What is pinned, and the one thing that is not

`build-native.yml` pins the runner image, Xcode, the NDK, CMake, the JDK,
Gradle, and the upstream commit; upstream's own `tools/install-rust-dependencies`
pins the Rust toolchain to a dated nightly. Each artifact's record carries the
versions that actually applied to it, per artifact, because one set is built by
two toolchains (DECISION-14 §5.1 note 1).

The exception is `tools/install-sys-dependencies-mac`, upstream's script, which
runs `brew install boost ninja xcodegen xcbeautify` with no per-formula version.
We cannot pin those in advance without forking upstream's dependency script, so
`build_android.sh` records the resolved boost version in the artifact's
toolchain object **after the fact**. That is a real residual and it is stated
here rather than papered over.

## What "identity-carrying" and "checksummed" mean here, and what they do not

Every artifact carries `wcf_build_info()` — the upstream commit, the artifact
set id, and the workflow-run URL, injected at compile time — and every artifact
has its SHA-256 recorded in `compat_manifest.json` and embedded in its own
asset name.

They are **not** reproducible artifacts. PRD §12.4's independent-rebuild
demonstration has not happened, and the Apple half of this directory is by
construction a relink of object code upstream compiled, which puts that
demonstration out of reach for those artifacts until Apple moves to a
from-source build at M3 (DECISION-9 §4 step 3). Every Apple record says
`provenance: relinked_from_upstream_release_asset` so the manifest never
implies otherwise.

The digests are also **first-seen, not attested**: six of upstream's eight
4.8.0 release assets carry no upstream-published checksum, and
`TrustWalletCore-<tag>.tar.xz` — the input the Apple relink consumes — is one of
them. `--expected-tarball-sha256` pins a later run to an earlier observation of
ours, which is the strongest statement available and is not an upstream
attestation.

## Output layout

Both build scripts write the same four things under `--out-dir`:

```
artifacts/<logical_name>       the libraries, in manifest-key layout
records/<flat_name>.json       one DECISION-14 §5.1 record per manifest artifact
upload/<asset_name>            every uploadable, named per DECISION-14 §3.1
SHA256SUMS                     digests over upload/
inputs.json                    the input asset or source tree, and its digest
```

A whole set's `artifacts` block is `jq -s 'add' records/*.json`.

dSYM bundles are uploaded under the same content-addressed asset-name scheme
but are **not** manifest artifacts: the manifest's `artifacts` map is the list a
consumer build fetches and verifies, and a debug bundle is not on that path.
Their digests are in `SHA256SUMS`.

## Not yet run

`build_android.sh` has never been executed. It needs an Android SDK, an NDK, a
JDK, Gradle, a Rust toolchain and boost, none of which were present where it
was written, and there is no Android artifact anywhere upstream to test
against. Its first run is the workflow's. What has been exercised of it: the
identity-injection mechanism it uses (a generated `src/*.c` that defines the
three values and includes the reviewed source from outside upstream's
`file(GLOB_RECURSE src/*.c)`) was compiled with NDK r27 clang in both the plain
and the CMake-unity-build shape, and both gates were run against real ELF
objects — a 16 KB-aligned `.so` we built and a 4 KB-aligned one from the NDK
sysroot, which the alignment gate correctly passes and fails.
