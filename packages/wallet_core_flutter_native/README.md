# wallet_core_flutter_native

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

The native distribution layer of the `wallet_core_flutter` workspace. Applications depend on `wallet_core_flutter`, not on this package directly; it is documented here because it is the package that decides which binary a build links and proves which one it got.

## What it does

- **Loads the library.** `WalletCoreNative.load()` resolves the native library from the locations the packaging mechanism itself provides — a bundled asset, an AAR, an xcframework — never from a caller-supplied path or an environment variable at run time.
- **Checks the build identity.** Every artifact this project publishes exports `wcf_build_info()`, a symbol we compile and link ourselves, returning the upstream commit and the artifact-set id it was built for. `verifyIdentity` compares those with the compatibility manifest before any other symbol is used. Upstream's C API exposes no version symbol, so this identity is ours; a library without it is not one of ours and is rejected.
- **Ships the manifest.** `assets/compat_manifest.json` is a byte copy of the repository's `compat_manifest.json`, written by `melos run gen:manifest` and diffed by `melos run gen:check`. It carries the sha256 and the size of every artifact in the set.
- **Fetches the artifacts at build time.** `tool/fetch_artifacts.dart` downloads what the manifest lists and verifies it. That tool is the subject of the rest of this file.

Nothing in `lib/` opens a socket. The fetch is build-time tooling under `tool/`, outside the package's library API.

## Fetching artifacts

```
dart run packages/wallet_core_flutter_native/tool/fetch_artifacts.dart --help
dart run packages/wallet_core_flutter_native/tool/fetch_artifacts.dart --dry-run
dart run packages/wallet_core_flutter_native/tool/fetch_artifacts.dart
```

`--dry-run` prints, per artifact, the primary URL, the mirror URL or `no mirror`, the cache path, and whether the cache entry is `verified`, `missing`, or `corrupt` — and opens no socket. It exits 0 when the manifest can be fetched from and 2 when it cannot, so it works as a CI preflight.

**Today it cannot fetch anything, and says so.** The shipped manifest is still the placeholder shape: `retention.primary`, `identity.artifact_set_id`, and every artifact digest are `TBD-` values that the CI native build has not filled yet. `--dry-run` names each blocked field and the task that fills it.

### The cache directory

In order:

1. `--cache-dir <path>`, if given;
2. `$WCF_ARTIFACT_DIR`, if set — this is the configurable cache directory an air-gapped or containerised build points at;
3. otherwise `~/.cache/wallet_core_flutter/<upstream.tag>/`, tag-scoped because two upstream tags are two different artifact sets.

Inside it, an artifact lives at its logical name from the manifest, e.g. `android/arm64-v8a/libTrustWalletCore.so`.

A cached file is re-hashed before it is trusted. One that does not match the manifest is deleted rather than reused, and fetched again.

### Offline and vendored builds

`--vendored <dir>` takes a directory laid out by logical name, pre-populated by you. Each file is verified against the manifest exactly as a download is, **before** it is copied into the cache; a file that does not match is rejected and not copied. It is tried before the network, so a partially vendored directory still works.

`--offline` never opens a socket. It succeeds from a warm cache or a vendored directory and otherwise fails, naming the artifact and both places it looked. Combine the two for an air-gapped build:

```
dart run packages/wallet_core_flutter_native/tool/fetch_artifacts.dart \
  --vendored /mnt/artifacts --offline
```

Other flags: `--only <logical_name>` (repeatable) to fetch one artifact, `--keep-going` to report every failure rather than stopping at the first (the exit code stays non-zero), `--manifest <path>` to read a manifest other than the shipped one.

### Verification

**Every artifact is verified against the manifest's sha256 and its recorded size, from every source — the network, the cache, or a vendored directory — and there is no flag, environment variable, or code path that skips that check or accepts a mismatch.** Bytes land on a temporary name inside the cache directory and are renamed into place only after they verify, so a failed or interrupted run never leaves a wrong byte at the cache path. A mismatch is reported with the artifact's name, the URL, and both digests and both sizes, and stops the run.

Downloads are HTTPS only. Redirects are followed — GitHub Releases answers an asset URL with a redirect to its object store — up to five hops, each of which must also be HTTPS; the digest, not the host, is the control.

The artifacts are **checksum-pinned**: the manifest that pins them is checked into the repository, reviewed in the same change that publishes them, and shipped inside this package. An independent-rebuild comparison is a separate, later requirement and is not claimed here.

## Licence

MIT. See `LICENSE` at the repository root and `THIRD_PARTY_NOTICES.md` for upstream's Apache 2.0 notice.
