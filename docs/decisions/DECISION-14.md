# DECISION-14 — Distribution contract

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

| | |
|---|---|
| **Question** | What does this project promise about the binaries and the package set it publishes: how a build proves *which* library it linked, where artifacts live and for how long, how the three packages are pinned to each other, in what order they publish, and what happens when a published set turns out to be wrong? |
| **Governing PRD sections** | §12.3 (artifact acquisition, identity, durability), §12.4 (the two separate integrity requirements), §15.3 (manifest), §15.4 (versioning, publication order, recovery release), §16 S3, §22 DECISION-14 |
| **Depends on** | [`DECISION-9`](DECISION-9.md) (T0.5) and [`evidence/release-assets-4.8.0.md`](evidence/release-assets-4.8.0.md) |
| **Fills manifest fields** | `identity`, `release_set`, `retention`, `sbom`, and the full per-artifact record of §5.1 (PRD §12.3's durability list plus DECISION-9's `provenance`) |
| **Status** | **Recorded 2026-09-07** - recommendation adopted as written, with the T0.R2/T0.R4 fixes. See the Decision section. Recorded by the orchestrator under the owner's standing authorization; subject to their ratification. |

---

## 1. Context

Three upstream facts, all established by T0.5, set the problem:

1. **The 4.8.0 headers expose no version symbol.** There is no way to ask the loaded library which upstream commit it came from. Identity has to be ours (PRD §12.3), on every path.
2. **Upstream ships no Android binary on GitHub Releases.** Release 4.8.0 has 8 assets, none of them Android; upstream's Android library is on GitHub Packages behind an access token (upstream README line 48). Every Android artifact a consumer of this SDK fetches is one we produced and host.
3. **The iOS xcframework *is* on GitHub Releases and does carry a checksum** — `WalletCore.xcframework.zip`, sha256 `0c79df1a901a3abfbccee5052229984b1e743696483176b3cfb68eaf90f400bc`, declared in upstream's `Package.swift` for SPM and confirmed byte-for-byte locally. It is the **only** upstream-attested checksum available to us: six of the eight assets have no published checksum at all, including `TrustWalletCore-4.8.0.tar.xz`, which is the input DECISION-9's Apple path relinks.

DECISION-9's recommendation, recorded 2026-09-07 and awaiting ratification (D0 closed 2026-09-07), is **Option C**: Apple libraries are relinked from the static archives inside `TrustWalletCore-<tag>.tar.xz` together with our `wcf_build_info.c` (one dynamic library per slice, 464 `TW*` symbols plus ours, and a macOS host library from the same step); Android is built from the git tree at the pinned commit with the identity file in the link; Apple moves to from-source at M3. This record is designed on that shape, and §7 says what changes if D0 picks B-only.

## 2. The build-identity symbol

### 2.1 Exact C signature

```c
/* packages/wallet_core_flutter_native/src/identity/wcf_build_info.c
 * Compiled by us and linked into every artifact we publish, on every platform.
 * The returned pointer is static storage owned by the library. The caller must
 * not free it, and it is NOT a TWString — upstream's delete functions must
 * never be called on it. It stays valid for the lifetime of the loaded image.
 */

/* The symbol must be exported from the built image on both toolchains, and it
 * must be exported explicitly rather than by default: the Android build is
 * tuned for JNI and may compile with -fvisibility=hidden (DECISION-9 §3,
 * upstream issue #4638), and a hidden identity symbol is indistinguishable at
 * load time from a mirrored-without-relink artifact. */
#if defined(_WIN32)
#  define WCF_EXPORT __declspec(dllexport)
#else
#  define WCF_EXPORT __attribute__((visibility("default")))
#endif

WCF_EXPORT const char *wcf_build_info(void);
```

`__attribute__((visibility("default")))` is the annotation for **both** toolchains we ship: Apple's clang and the Android NDK's clang accept it identically, and the NDK's own `JNIEXPORT` expands to exactly it. The annotation goes on the declaration in the header *and* on the definition, so a build that adds `-fvisibility=hidden` to our translation unit cannot hide it. The `_WIN32` arm exists only so the file compiles unchanged if a host build is ever added; no Windows artifact is published at 1.0.

**The annotation does not replace the export gate; it is checked by it.** T1.2 runs `llvm-nm --defined-only --extern-only` on **every** artifact in the set and fails the build unless `wcf_build_info` is present (as `_wcf_build_info` on Mach-O, `wcf_build_info` on ELF), alongside the existing reconciliation against the 464-name `TW*` list (DECISION-9 §5, T1.2). Annotation and gate answer different questions: the annotation makes the export happen, the gate proves it happened in the binary we are about to publish. Neither is sufficient alone — a link-time version script or `--gc-sections` can still drop an annotated symbol, which is precisely the failure the gate exists to catch.

It returns a NUL-terminated UTF-8 JSON object with exactly these keys:

```json
{
  "upstream_commit": "d692ac27749d0c615e17c751b70ab4f0aa75c59b",
  "artifact_set_id": "as_4.8.0_001",
  "build_workflow":  "https://github.com/<org>/<repo>/actions/runs/<run-id>"
}
```

- `upstream_commit` — 40 lowercase hex, the commit the C API came from (the git tree we built, or the tree upstream's release asset was built from, per `provenance`).
- `artifact_set_id` — the id of the artifact set this binary belongs to; format `as_<upstreamTag>_<3-digit sequence>`, allocated by the build workflow, **never reused**, monotonic within a tag.
- `build_workflow` — the absolute URL of the workflow run that produced the binary. It is the human-readable end of the provenance chain and pairs with the attestation of PRD §12.3 [REC] (T4.5).

Three keys, no more. A reader ignores keys it does not know, so the format can gain a field without breaking an older loader.

### 2.2 Why a JSON string rather than a struct or three symbols

A struct return crosses an ABI we do not control (layout, alignment, and calling convention differ between the compilers that build our Android and Apple artifacts) and would need versioning of its own. Three separate symbols mean three lookups and three ways to be half-present — the case where two match and one is missing has no good answer. One symbol returning one self-describing string has one failure mode: the symbol is absent, which is exactly the mirrored-without-relink artifact that T1.7's negative test must reject loudly.

T0.5 already built and called this symbol: a four-line C file linked with upstream's `macos-arm64_x86_64` static archive produced a `.dylib` that Dart opened, called, and got the JSON back from, alongside a working `TWAnyAddressIsValid` — so the shape is measured, not proposed.

### 2.3 What `initialize()` compares

Four comparisons, in the worker isolate, during `Init`, before any other symbol is used (DECISION-12 §5). Each failure names which comparison failed:

| # | Compare | Failure |
|---|---|---|
| 1 | the three packages' embedded `releaseSetId` constants against each other | `ManifestMismatchError(check: releaseSetMismatch)` |
| 2 | the embedded manifest hash against the sha256 of the manifest copy shipped in `_native` | `ManifestMismatchError(check: manifestHashMismatch)` |
| 3 | `wcf_build_info().artifact_set_id` against manifest `identity.artifact_set_id` | `ManifestMismatchError(check: artifactSetMismatch)` |
| 4 | `wcf_build_info().upstream_commit` against manifest `identity.upstream_commit` (and `upstream.commit`) | `ManifestMismatchError(check: upstreamCommitMismatch)` |

A missing `wcf_build_info` symbol is `NativeLoadError`, not a mismatch: it means the loaded library is not one of ours at all. The loaded file is **never hashed at runtime** — it is meaningless for a statically linked image and would be a false assurance for a dynamic one (PRD §12.3, threat model TM-13).

## 3. Artifact URLs, retention, and mirror

### 3.1 Content-addressed immutable URLs — two layouts, one identity

A GitHub Release asset is a **flat file**: it is served from `https://github.com/<org>/<repo>/releases/download/<tag>/<asset-name>` and has no path component under the tag. A nested `{artifact_set_id}/{sha256}/{filename}` route cannot exist there, so the set id and the checksum have to live in the *name* on the primary, and in the *path* only on the object-store mirror. Both layouts carry the same three facts and both are content-addressed as PRD §12.3 requires; they differ only in where the separators go.

**Primary — GitHub Releases, flat asset name.** The exact pattern, and it is a pattern the validator checks (§5.1):

```
<artifact_set_id>__<sha256>__<flat_name>
```

where `<sha256>` is the artifact's **full 64-character lowercase hex digest** — not a prefix — `<flat_name>` is the artifact's `logical_name` (its path in the manifest) with `/` replaced by `-` (`android/arm64-v8a/libTrustWalletCore.so` → `android-arm64-v8a-libTrustWalletCore.so`), and `__` (two underscores) is the field separator: it cannot occur inside a set id, a hex digest, or a logical name, so the name parses unambiguously in either direction. Assembled:

```
{retention.primary}/{artifact_set_id}__{sha256}__{flat_name}
```

```
https://github.com/<org>/<repo>/releases/download/native-4.8.0-001/as_4.8.0_001__9f2c1ab34de5f70e8a3b1c4d6e2079bd85fa1c3e97d024b658ea7c319f40db26__android-arm64-v8a-libTrustWalletCore.so
```

**The whole digest, because a prefix is not content addressing.** An earlier draft embedded only the first twelve hex characters of the digest and called it a human aid. That is not what PRD §12.3 asks for: a content-addressed URL is one whose identifier *is* the content's digest, so that the name commits to the bytes on its own. A 12-hex prefix commits to 48 bits, which is enough to read in a log and not enough to be the address. The full digest costs characters and nothing else — verification still compares the manifest's `sha256` against the downloaded bytes, but the URL now names its own content on the primary exactly as it does on the mirror.

**It fits.** A GitHub release asset name may be up to **255 characters**. The longest name this scheme can produce is bounded by: an `artifact_set_id` of `as_<tag>_<nnn>` (19 characters even for a 12-character upstream tag) + `__` + 64 + `__` + the longest `flat_name` we ship. The longest flat name at 4.8.0 is an Apple simulator debug bundle, `ios-simulator-arm64_x86_64-libTrustWalletCore.dylib.dSYM.zip`, at 59 characters; allowing 80 for headroom gives **19 + 2 + 64 + 2 + 80 = 167 characters**, leaving 88 in reserve. T1.2's validator enforces the 255 limit explicitly so a future artifact with a long path fails at build time rather than at upload time.

**Mirror — object store, hierarchical.** The nested layout is kept where it is expressible, because a bucket prefix per set is what makes listing, lifecycle rules, and a per-set delete tractable:

```
{retention.mirror}/{artifact_set_id}/{sha256}/{logical_name}
```

```
https://<bucket>.<host>/wcf-artifacts/as_4.8.0_001/<64 hex>/android/arm64-v8a/libTrustWalletCore.so
```

**Base-URL semantics, stated so a fetcher can be written from this paragraph alone.** `retention.primary` and `retention.mirror` are both base URLs with no trailing slash, and neither is ever a per-file URL. They differ in the template applied to them, and the template is fixed by the location kind, not configurable per release:

| | `retention.primary` | `retention.mirror` |
|---|---|---|
| Points at | one GitHub Release, tag `native-<upstreamTag>-<seq>` | a bucket prefix that holds every set |
| Template | `base + "/" + asset_name` (one segment) | `base + "/" + artifact_set_id + "/" + sha256 + "/" + logical_name` |
| Set id appears in | the asset name, and in the release tag | the path |
| Full sha256 appears in | the asset name, between the two `__` separators | the path, as its own segment |
| Changes per artifact set | yes — a new set is a new release tag, so a new base URL | no — one base serves every set |

That asymmetry is why the manifest records both `asset_name` and `logical_name` per artifact (§5.1) instead of letting a fetcher guess: `asset_name` is the primary's whole path segment, `logical_name` is the mirror's tail and the manifest's own artifact key.

Rules, all enforced by the build workflow (T1.2):

- **Both locations are content-addressed with the full digest**, so either URL names its own content on its own. That is a property of the name, not a substitute for checking: verification is always the manifest's 64-hex `sha256` recomputed over the downloaded bytes, on both locations, with no "continue anyway" path. What the embedded digest buys is that a substitution is visible in a log line and detectable before a byte is read, and that a downloaded file carries its own address in its name.
- A release tag `native-<upstreamTag>-<seq>` is created once and never re-uploaded to; an asset name is never reused. Correcting an artifact means a new set id and a new tag, never a replacement under an existing URL. The set id inside the asset name means a stray file cannot be mistaken for a member of another set even after it is downloaded and renamed.
- A mirror is a base-URL swap plus the mirror template; nothing else changes, and the manifest is unchanged by which location served the bytes.
- The fetch is build-time only (PRD §16 S4). Nothing in this scheme is reachable at runtime.

### 3.2 Retention promise — wording to publish

Published in `docs/artifact_retention.md` (T3.13) and linked from `retention.policy`:

> **Artifact retention.** For every native artifact set referenced by a published version of `wallet_core_flutter`, `wallet_core_flutter_bindings`, or `wallet_core_flutter_native`, this project undertakes: **not to intentionally delete or modify that set**, and **to keep it configured for serving from two locations** — the primary release and the mirror — for **at least 24 months** after the last package version that references it is superseded. Artifact sets are never modified in place: a correction is always a new set with a new id, published as a new release of the package set. If we decide to end retention for a set, notice is published in the repository's releases and in `SECURITY.md` at least 90 days beforehand.
>
> What this is not: it is **not** a promise that a set will be reachable at any given moment. Reachability depends on GitHub, on the mirror's provider, and on network conditions between them and you, none of which this project controls, and an outage or a provider's own action can make a set temporarily or permanently unavailable regardless of what we do. This is a statement of our own conduct and configuration, not a service-level agreement, and it carries no warranty. Consumers who need a stronger guarantee should use the offline/vendored artifact cache (PRD §12.3) and keep their own copy.

Two things about this wording are deliberate.

**It promises only what is ours.** The earlier draft said artifacts "stay fetchable", which is a claim about GitHub's and a storage provider's uptime — infrastructure we neither own nor pay for at a tier that would let us promise anything about it. What we can actually commit to is that we will not delete the bits, will not alter them, and will keep two locations configured; everything past that is the provider's availability, and the second paragraph says so plainly rather than in a disclaimer sentence a reader skips.

**The 24-month figure is a proposal, not yet a commitment.** It is the number this record recommends, and it is affordable under §3.3's cost estimate, but three things must be verified before it is published: current mirror pricing against a live rate card, who owns and pays for the mirror account (a personal account is not a 24-month promise), and a demonstrated restore — a fetch of an old set from the mirror, verified against the manifest. **T3.13 does that verification and either publishes 24 months or publishes the number the verification supports.** Until then the figure appears in this record and not in `docs/artifact_retention.md`.

### 3.3 Mirror candidates and an honest cost estimate

**Size per artifact set.** Only the Apple side is measured: T0.5's relinked iOS device library is **19 720 768 bytes** and the macOS host library **19 876 872 bytes**. The simulator slice is a fat binary of two architectures, so on the order of 40 MB. **No Android `.so` exists yet anywhere** — upstream ships none and we have not built one — so the Android figure is an estimate anchored on upstream's own 26 MB iOS device slice: 20–35 MB per ABI. With three ABIs that gives roughly:

| Component | Size |
|---|---|
| Android × 3 ABIs | 60–105 MB *(estimated, no artifact exists yet)* |
| iOS device | ~20 MB *(measured)* |
| iOS simulator (fat) | ~40 MB *(estimated from the device slice)* |
| macOS host | ~20 MB *(measured)* |
| **Total per set** | **≈ 140–185 MB**, call it **200 MB** with dSYMs and checksums |

**Cadence.** Upstream tagged 4.8.0 on 2026-08-28. Assuming we absorb 8–15 upstream tags a year plus a few recovery releases, that is **1.6–3 GB of new artifacts per year**, and at the proposed 24-month window a steady state of roughly **4–6 GB** under retention.

| Candidate | Cost | Assessment |
|---|---|---|
| **GitHub Releases on this repository** (primary) | none | Where PRD §12.3 already puts them. Generous size limits, no bandwidth billing, content served over HTTPS with a stable URL scheme. Weakness: same failure domain as the source, the CI, and the pin PRs — the single point of failure TM-15 names. |
| **Cloudflare R2** (recommended mirror) | first 10 GB-month of storage free, **no egress fee**; beyond that low single-digit dollars per year at our volume. *Pricing from published rate cards and **not** verifiable from this task — no network access — so T3.13 must re-check it before publishing the policy.* | Different provider, different failure domain, egress-free (the property that matters for a mirror nobody budgets for), and a base-URL swap under §3.1. |
| **Backblaze B2** | ~$6/TB-month storage; egress free to Cloudflare, metered otherwise | Cheaper storage than we need; the egress model is the reason it is second choice. |
| **A second GitHub organisation/repository** | none | Cheapest to operate and worth nothing against TM-15: one compromised account can reach both. Acceptable only as a *third* copy. |
| **A package-embedded copy of the artifacts** | none in money; large in package size | Rejected. It would put 200 MB in a pub.dev package and defeat PRD §12.3's "the pub.dev package stays small". |

**Recommendation:** primary = GitHub Releases; mirror = Cloudflare R2, stood up and populated **before the 1.0 tag** (PRD §12.3 says "before 1.0"); `retention.mirror` stays `null` until it exists, and the manifest validator must keep accepting `null` so the field does not lie. The 1.0 acceptance checklist (T5.11) gains "mirror populated and a fetch from it verified".

## 4. Release set, cross-package pins, and publication

### 4.1 Release-set id

Format `rs_<upstreamTag>_<3-digit sequence>`, e.g. `rs_4.8.0_001`. One release set = one simultaneous publication of the three packages plus the artifact set they were tested against. The sequence increments for every publication against the same upstream tag, including recovery releases.

**Where it is embedded.** A generator (`tools/manifest/embed_release_set.dart`, run by `melos run gen:all`, output under each package's generated directory so rule 1 covers it) writes into all three packages:

```dart
const String releaseSetId   = 'rs_4.8.0_001';
const String manifestSha256 = '<sha256 of compat_manifest.json as committed, byte for byte>';
```

`manifestSha256` is the sha256 of the manifest **file's bytes exactly as committed**, not of a re-serialisation of its JSON, because both sides of §2.3's comparison 2 hash bytes — the generator hashes the committed file and the runtime check hashes the byte copy shipped in `_native` — so the comparison is a statement about the file rather than about two encoders agreeing on a canonical form. *(amended 2026-09-08, T1.7a/T1.7b; the generator is `tools/manifest/bin/embed.dart`)*

`_native` additionally ships the manifest itself as an asset (`packages/*_native/assets/compat_manifest.json`, T1.7). `initialize()` runs the four comparisons of §2.3.

### 4.2 Exact pins

The SDK's pubspec pins `wallet_core_flutter_bindings: 0.3.2` and the bindings pin `wallet_core_flutter_native: 0.3.2` — **exact versions, no caret, no range** (PRD §15.4). The reason is not caution about semver; it is that the release-set check of §2.3 comparison 1 *will fail at runtime* if a consumer resolves a mixed set, so a range would let pub produce a combination that cannot start. An exact pin turns that into a resolution error at `pub get`, which is where a version problem should surface. CI resolves the hosted graph with no path overrides (T3.11) so what is tested is what resolves.

### 4.3 Publication order and the hosted-install smoke

```
1. build-native workflow produces artifact set as_<tag>_<n>, uploads it, records sha256s
2. manifest updated: artifacts, toolchain, identity, provenance, release_set  → committed, reviewed
3. publish wallet_core_flutter_native          ── wait for pub.dev to serve it
4. publish wallet_core_flutter_bindings        ── wait
5. publish wallet_core_flutter                 ── wait
6. HOSTED-INSTALL SMOKE  (blocking, before any announcement)
     flutter create a fresh app in a clean directory
     add wallet_core_flutter as a HOSTED dependency (no path, no override)
     build debug and release for Android and iOS
     run: initialize() → import the known mnemonic → derive the Ethereum address
          → sign the M0 vector → compare byte-for-byte → shutdown()
     assert: the identity check passed and the leak tracker reports zero
7. announce; tag the repository; attach the manifest and the SBOM to the release
```

Steps 3–5 are ordered because a dependency must exist before its dependent resolves. Step 6 is the step that matters: it is the only test that exercises what a consumer actually gets, and PRD §15.4 requires it ("a fresh application installs the hosted versions and signs a vector before a release is announced"). If step 6 fails, the response is §5 — the published versions cannot be withdrawn.

### 4.4 Recovery release

pub.dev has no yank that removes a version from existing resolutions, and our own artifact URLs are immutable by §3.1. So:

1. **Never** re-publish a version number, never re-upload an artifact URL, never move a release tag.
2. Fix forward: a **new patch version of all three packages**, published in the order of §4.3, with a new `release_set` sequence (`rs_4.8.0_002`).
3. **Artifacts:** if the defect is in Dart only, the new set reuses the existing `artifact_set_id` and the manifest's `artifacts` block is unchanged — the identity check still passes for the same binaries. If the defect is in a binary, a **new artifact set** is built and the old set's URLs stay live under the retention promise, so consumers pinned to the old version keep building while they migrate.
4. Every package's CHANGELOG names the defect, the affected versions, and the fixed version, and links the advisory.
5. For a security defect: a GitHub Security Advisory on this repository, `SECURITY.md`'s private channel acknowledged, and the expedited release channel used (skipping the soak period, PRD §15.2 [REC], T4.3). We have **no runtime channel to reach consumers** and will not build one, because that would mean network access at runtime (PRD §16 S4, threat model TM-29).
6. The procedure is written down in `docs/releases/process.md` **before the first publish** (PRD §15.4), which makes it T3.11's deliverable, not a thing improvised during an incident.

### 4.5 SBOM [REC]

A CycloneDX 1.5 JSON document per artifact set, produced by the build workflow, attached to the release, and recorded in manifest `sbom` as a path relative to the release (`sbom/as_4.8.0_001.cdx.json`). Contents:

- our components: `wcf_build_info.c`, the link script, and the toolchain versions from manifest `toolchain`;
- upstream: repository, tag, and commit, plus upstream's own third-party dependencies as declared at that commit (boost, protobuf, the Rust crates in `rust/`);
- for a **relinked** Apple artifact, the SBOM is explicitly marked with the artifact's `provenance` value and states that the component list for the upstream half is derived from upstream's declarations, not from our compilation — because we did not compile those objects and must not imply that we enumerated them.

Marked [REC] in the PRD; recommended here as **required from the first public alpha** rather than 1.0, because it costs a workflow step and the alternative — publishing binaries with no component inventory — is the thing an adopting company's review will ask about first.

**That earlier date is conditional, and the condition is the third bullet above.** Under Option C, a relinked Apple artifact's upstream half is enumerated from upstream's *declarations* at the pinned commit, not from anything we compiled; an SBOM that lists those components beside the ones we built, with no distinction, would assert an inventory we did not verify — which is worse than shipping no SBOM, because it is a document a reviewer will rely on. So:

> The first-alpha date holds **only if T1.2 demonstrates that its CycloneDX output distinguishes compiled components from declaration-derived inventory** — concretely, that each component carries the producing artifact's `provenance` and that a consumer of the document can tell, per component, whether it was observed in our build or copied from an upstream declaration. If T1.2 cannot show that, the SBOM stays a **1.0** commitment and the intervening alphas ship without one rather than with an undifferentiated one.

T1.2 records which of the two happened; the 1.0 acceptance checklist (§6, T5.11) requires the SBOM either way.

## 5. Manifest fields this record fills

| Field | Value / shape | Source |
|---|---|---|
| `identity.symbol` | `"wcf_build_info"` | §2.1 — already correct in `compat_manifest.json` |
| `identity.artifact_set_id` | `as_<tag>_<nnn>` | §2.1, written by T1.2 |
| `identity.upstream_commit` | 40 hex | §2.1, from T1.1's pin |
| `identity.build_workflow` | **new field**, workflow-run URL | §2.1 |
| `release_set` | `rs_<tag>_<nnn>` | §4.1, written by T3.11 |
| `retention.primary` | `https://github.com/<org>/<repo>/releases/download/native-<tag>-<nnn>` | §3.1 |
| `retention.mirror` | R2 base URL, `null` until it exists | §3.3 |
| `retention.policy` | URL of `docs/artifact_retention.md` | §3.2 |
| `sbom` | path to the CycloneDX document, `null` until T1.2 emits one | §4.5 |
| `artifacts.<logical_name>` | the per-artifact record of §5.1 — fourteen fields, not two | §5.1 |

### 5.1 The per-artifact record

PRD §12.3 "Durability [REQ]" names, in one sentence, everything the manifest must record per artifact: *source commit, build workflow, linkage type, target OS, ABI, minimum OS, toolchain, size, checksum, signature, and attestation identity*. PRD §15.3's code block shows only `sha256` and `size`, so the requirement and the illustration disagree today. This record models the full list — plus DECISION-9's `provenance` and the two name fields §3.1 needs — and the **orchestrator's PRD patch updates §15.3's block from this table**; nothing in this task edits the PRD.

The manifest key stays the artifact's logical path (`android/arm64-v8a/libTrustWalletCore.so`), and the value becomes an object:

| Field | Type / domain | Example | Required | PRD §12.3 term |
|---|---|---|---|---|
| `sha256` | 64 lowercase hex | `9f2c1a…` | always | checksum |
| `size` | integer bytes | `19720768` | always | size |
| `source_commit` | 40 lowercase hex — the upstream commit these bits came from | `d692ac27…` | always | source commit |
| `build_workflow` | absolute workflow-run URL | `https://github.com/<org>/<repo>/actions/runs/<id>` | always | build workflow |
| `linkage` | `static` \| `dynamic` | `dynamic` | always | linkage type |
| `target_os` | `android` \| `ios` \| `ios-simulator` \| `macos` | `android` | always | target OS |
| `abi` | architecture, in the platform's own vocabulary: `arm64-v8a`, `armeabi-v7a`, `x86_64`, `arm64`, `arm64_x86_64` (a fat slice) | `arm64-v8a` | always | ABI / architecture |
| `min_os` | minimum OS as the platform states it: an Android API level (`21`) or an Apple deployment target (`13.0`) | `21` | always | minimum OS |
| `toolchain` | object, per artifact, not per set — `{ "ndk": "r27c", "cmake": "3.29.3", "rust": "1.81.0" }` on Android, `{ "xcode": "17F113", "clang": "…", "sdk": "iphoneos26.5" }` on Apple | | always | toolchain |
| `signature` | detached-signature asset name, or `null` | `null` | nullable | signature |
| `attestation` | object identifying the attestation over these bytes — `{ "subject_digest": "sha256:…", "workflow_identity": "…", "bundle": "<asset name>" }` — or `null` until T4.5 | `null` | nullable | attestation identity |
| `provenance` | `built_from_source` \| `relinked_from_upstream_release_asset` | `relinked_from_upstream_release_asset` | always | — (DECISION-9 §4.4) |
| `asset_name` | the flat primary asset name of §3.1, carrying the full digest | `as_4.8.0_001__9f2c1ab34de5f70e8a3b1c4d6e2079bd85fa1c3e97d024b658ea7c319f40db26__android-arm64-v8a-libTrustWalletCore.so` | always | — (§3.1) |
| `logical_name` | the manifest key repeated inside the record, so a record is self-describing once detached from the map | `android/arm64-v8a/libTrustWalletCore.so` | always | — (§3.1) |

Four notes on the modelling, each of which is a choice a reader could reasonably have made differently:

1. **`toolchain` is per artifact and the top-level `toolchain` block stays as a set-wide summary.** Under Option C one set contains artifacts built by two different toolchains (a `clang` relink on Apple, a full NDK/CMake/Rust build on Android), so a single top-level block cannot describe them without being either wrong or empty. The per-artifact object is authoritative; the top-level block carries only what every artifact in the set agrees on, and the validator checks that agreement rather than assuming it.
2. **`source_commit` is per artifact even though it will usually equal `upstream.commit`.** It is what PRD §12.3 asks for, and the case where it differs is real: a recovery release that rebuilds one platform against a patched tree while the others are unchanged.
3. **`signature` and `attestation` are nullable, and nullable is not optional.** The keys are present and explicitly `null` before T4.5 lands, so the absence of an attestation is a recorded fact rather than a missing field, and a validator can distinguish "not yet attested" from "the producer forgot".
4. **`min_os` is a string in the platform's own vocabulary**, not a normalised number. An Android API level and an iOS deployment target are not the same kind of value, and coercing them into one would lose which is which.

**Who produces and who validates.** Production is **T1.2**'s: it is the only place that knows the toolchain versions, the link mode, the deployment target, and the workflow run, because it is the job that ran them. Validation is the manifest tool's, and **T1.2 extends `tools/manifest`** to do it in the same change that starts producing the values: presence of every required field, domain checks on `linkage` / `target_os` / `abi` / `provenance`, 64-hex `sha256` and 40-hex `source_commit`, `size > 0`, `asset_name` matching the §3.1 pattern, no longer than 255 characters, and **its embedded 64-hex digest equal — character for character, not by prefix — to this record's `sha256`** with its embedded set id equal to `identity.artifact_set_id`, `logical_name` equal to the map key and its `/`-to-`-` flattening equal to the `asset_name`'s tail, and `signature`/`attestation` present-but-nullable. `melos run manifest:validate` is the gate.

Three of these are schema changes to files this task does not own: `identity.build_workflow`, the per-artifact `provenance`, and the rest of the §5.1 record. `compat_manifest.json` and `tools/manifest/lib/manifest.dart` belong to T0.7; the changes are requested here and applied by **T1.2** (which produces the values) with the validator extended in the same change. Until then `manifest:validate` neither requires nor rejects the new fields.

## 6. Consequences for tasks

| Task | What changes |
|---|---|
| **T1.2** — native artifacts workflow | Owns `wcf_build_info.c` with the explicit default-visibility annotation of §2.1 and the JSON of §2.1 (three keys, `build_workflow` included); runs the per-artifact `nm` export gate for `wcf_build_info` and the 464 `TW*` names; allocates `artifact_set_id`; uploads under the flat asset-name pattern of §3.1 and mirrors under the hierarchical one; emits the CycloneDX SBOM, marked per §4.5 so compiled components are distinguishable from declaration-derived inventory (and reports whether that condition was met); **produces the full per-artifact record of §5.1** and **extends `tools/manifest` to validate it**. |
| **T1.7** — native package core | Implements the four comparisons of §2.3 with a distinguishing `check` on `ManifestMismatchError`; treats a missing `wcf_build_info` as `NativeLoadError`; never hashes the loaded library; builds the primary URL with the flat template of §3.1 and the mirror URL with the hierarchical one, falls back to `retention.mirror` **only** when it is non-null, and applies the same full-digest checksum check to both. |
| **T0.7 follow-up (in T1.2)** | `compat_manifest.json` gains `identity.build_workflow` and the §5.1 per-artifact record; the validator accepts and requires them once populated. |
| **T3.11** — release set | Owns `tools/manifest/embed_release_set.dart`, the exact pins of §4.2, the publication order and hosted-install smoke of §4.3 as a workflow, and `docs/releases/process.md` including §4.4 verbatim. |
| **T3.13** — retention policy and `SECURITY.md` | Publishes §3.2's wording; before publishing the window, verifies the three things §3.2 names — current mirror pricing against a live rate card, who owns and pays for the mirror account, and a demonstrated restore of an old set verified against the manifest — and publishes 24 months or the number that verification supports; links the advisory process of §4.4.5. |
| **T4.5** — attestations | The attestation subject is the artifact set id of §2.1, so an attestation and a running binary can be tied together through the same identifier. |
| **T4.3** — upstream watcher | Must also watch the layout of `TrustWalletCore-<tag>.tar.xz` (DECISION-9 §5): a layout change breaks the Apple relink and therefore the identity link step, silently, at the next tag. |
| **T4.4** — independent-rebuild comparison (PRD §12.4) | Applies only to artifacts whose `provenance` is `built_from_source`; for relinked Apple artifacts the comparison is *not available by construction*, and the report must say so per artifact rather than reporting an aggregate. |
| **T1.17** — CI | The identity-mismatch negative test covers all four checks of §2.3 separately, not just one. |
| **T5.11** — 1.0 acceptance | Adds "mirror populated and a verified fetch from it" and "SBOM attached to the current artifact set". |

## 7. If D0 chooses B-only instead of DECISION-9's Option C

Everything in §2, §3, §4, and §5 stands unchanged — identity, URLs, retention, pins, order, recovery, SBOM are all independent of where the bits come from. What changes:

- **`provenance` becomes uniformly `built_from_source`**, and §4.5's caveat about relinked components disappears; the SBOM's toolchain section becomes fully ours.
- **T4.4 becomes meaningful for the whole set** rather than the Android half — PRD §12.4's independent-rebuild requirement becomes reachable at every artifact, and its M3 milestone becomes a scheduling question rather than a structural one.
- **The `-u` symbol-list dependency disappears for Apple**, and with it DECISION-9's risk that an undocumented archive layout changes under us (its revisit trigger 2 stops applying).
- **The Apple `toolchain` block becomes a statement about our build** instead of a copy of upstream's `Info.plist` values.
- **The cost is schedule, not contract:** T1.2 becomes the long pole and T1.6 loses the macOS host library it would otherwise get from a single `clang` invocation, so `test:native` waits for the from-source Apple pipeline. DECISION-9 §4 makes that trade explicitly and calls it the orchestrator's to make.

Nothing in this record needs rewriting under B-only; §5.1's `provenance` field collapses to one value.

## 8. Answers to threat-model questions

Questions 1–3 of `docs/security/threat_model.md` §6 are addressed to DECISION-12 and 4–6 to DECISION-13; none is addressed to this record. Four threat rows are answered by it, and they are recorded here so T5.7 can check them against the built system:

- **TM-14 (artifact substitution in transit).** §3.1's immutable URLs, content-addressed with the full sha256 on the primary *and* the mirror, so a URL commits to its bytes in either location; plus recomputation of that digest over what was downloaded, with no "continue anyway" path in the fetcher (T1.7).
- **TM-15 (compromised CI or artifact host).** §3.3's separate-provider mirror, §2.1's `build_workflow` field binding a binary to a workflow run, and T4.5's attestation over the same `artifact_set_id`. The residual is unchanged: a compromise that lands both the artifact and its committed checksum in an approved PR defeats all of it, and human review of the pin PR is the remaining control.
- **TM-16 (manifest tampering).** §2.3's comparisons 1 and 2 — the three packages must agree on a release-set id *and* on a manifest hash, and `_native`'s shipped copy must hash to it.
- **TM-29 (no emergency-update path).** §4.4 is that path, written before the first publish, with the explicit statement that no runtime channel exists or will be built.

## 9. Revisit trigger

Re-open this record when any of the following occurs:

1. **Upstream adds a version or build-identity symbol to the C API** — §2 keeps our artifact-set id but the `upstream_commit` field could be cross-checked against upstream's own, which is strictly better evidence than our assertion.
2. **The mirror's pricing or terms change materially**, or the measured artifact-set size exceeds ~500 MB (a fourth Android ABI, unstripped debug artifacts, or an upstream size jump) — §3.3's "within the free tier" reasoning stops holding and the retention window becomes a budget decision.
3. **The first recovery release is executed** — §4.4 is exercised for real and should be rewritten from what actually happened.
4. **pub.dev gains a retraction mechanism that affects existing resolutions** — §4.4's "fix forward only" premise changes.
5. **DECISION-2 selects build hooks (Option 1)** — the fetch happens inside `hook/build.dart` and §3.1's URL consumer changes, though the scheme itself does not.
6. **An adopting organisation requires a signed SBOM or a specific attestation format** — §4.5 moves from [REC] to [REQ] with a named format, and T4.5's scope grows.

## 10. Build-time facts established by the first artifact runs (2026-10-03/04) — awaiting ratification at D1a

a. Android ABIs shipped: `arm64-v8a`, `x86_64`; `armeabi-v7a` is not built (PRD §12.2 step 8) — `.github/workflows/build-native.yml:73` `android_abis` default; the manifest's `armeabi-v7a` and `ios/TrustWalletCore.xcframework.zip` rows are placeholders that P0 must drop or replace with the per-slice `.dylib` keys the workflow records.
b. `-DFLUTTER=ON` is patched into upstream's `android/wallet-core/build.gradle` by `tools/native_build/build_android.sh:368` so the C API is exported (upstream hides it via `cmake/StandardSettings.cmake:4` unless `FLUTTER` is set); without it the SDK cannot call upstream on Android. This is a deviation from an unmodified upstream build; the patch is logged in the artifact record and in the build log.
c. Export gate reads `.dynsym` for ELF (release `.so` is stripped) — `tools/native_build/check_exports.sh:137`.
d. Four upstream JNI helpers (`TWDataCreateWithJByteArray`, `TWDataJByteArray`, `TWStringCreateWithJString`, `TWStringJString`) are exported by the Android library and allow-listed as known extras; the 464-symbol list stays authoritative for everything else (`tools/native_build/build_android.sh:441`).
e. `BOOST_ROOT=$(brew --prefix boost)` exported for Gradle's CMake on the Apple-Silicon runner (`tools/native_build/build_android.sh:311`); licence acceptance step `yes | sdkmanager --licenses` (`.github/workflows/build-native.yml:317`); `xcode_version` default `26.3.0` (`.github/workflows/build-native.yml:81`).
f. Retry semantics: the publish job refuses an existing release/tag (`.github/workflows/build-native.yml:156` "reserve the release tag" step), so a run that fails after the draft release is created cannot be retried under the same `artifact_set_id` — the next attempt uses the next id (`as_4.8.0_002`). Operating rule, consistent with §4.3's immutability: a failed publish burns its set id. No run has yet reached the publish job.
g. Comparison 2 (manifest hash) does not run on the default `initialize()` path today: `packages/wallet_core_flutter/lib/src/worker/handler.dart:278` only checks when `manifestBytes` are supplied and `packages/wallet_core_flutter/lib/src/session/wallet_core.dart:44` passes none. Two options are open for the owner at D1a: (i) embed the manifest bytes as a generated Dart constant at `gen:manifest` time and check by default; (ii) amend §2.3 to say comparison 2 is opt-in until T3.11's release-set work. Neither is chosen here.
h. The identity values (`identity.artifact_set_id`, artifact digests, toolchain) are still `TBD-T1.2` placeholders until P0 (`compat_manifest.json:50`); `manifest:validate` accepts them by design (strict mode reports 12).

---

## Decision

**The distribution contract of sections 2-5 is adopted**, including the three shapes that changed at D0: the
per-artifact manifest record of section 5.1 with a **per-artifact** `toolchain` (the top-level block becomes a
set-wide summary), the primary asset name `<artifact_set_id>__<sha256>__<flat_name>` carrying the **full 64-hex
digest** (section 3.1), and the retention wording of section 3.2, which promises only **our own conduct** and
disclaims the availability of third-party infrastructure. The 24-month window stays a **proposal** until T3.13 prices
it.

Binding on **T1.2** (which produces every field), **T1.7** (which verifies `wcf_build_info` against
`compat_manifest.json`), and T0.7's validator, which T1.2 extends to the per-artifact record.

This record consumes DECISION-9, recorded the same day as **Option C**; the `provenance` field exists precisely
because two build paths feed one manifest.

Recorded **2026-09-07 by the orchestrator**, under the repository owner's standing authorization to keep Phase 0 moving while they were unavailable, and **subject to the owner's ratification** (`docs/plan/PROGRESS.md` -> Needs your eyes -> "Decisions recorded on your behalf"). The choice is reversible at the cost stated in the revisit trigger; nothing is published.

Conditional, per D0: promoting the SBOM to the first alpha depends on the quality of T1.2's CycloneDX output. If it is
not usable the SBOM slips and this record is amended, not quietly ignored.
