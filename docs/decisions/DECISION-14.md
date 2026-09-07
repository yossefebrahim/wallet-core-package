# DECISION-14 — Distribution contract

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

| | |
|---|---|
| **Question** | What does this project promise about the binaries and the package set it publishes: how a build proves *which* library it linked, where artifacts live and for how long, how the three packages are pinned to each other, in what order they publish, and what happens when a published set turns out to be wrong? |
| **Governing PRD sections** | §12.3 (artifact acquisition, identity, durability), §12.4 (the two separate integrity requirements), §15.3 (manifest), §15.4 (versioning, publication order, recovery release), §16 S3, §22 DECISION-14 |
| **Depends on** | [`DECISION-9`](DECISION-9.md) (T0.5) and [`evidence/release-assets-4.8.0.md`](evidence/release-assets-4.8.0.md) |
| **Fills manifest fields** | `identity`, `release_set`, `retention`, `sbom`, and DECISION-9's per-artifact `provenance` |
| **Status** | recommended by T0.11; adjudicated at D0; recorded by the human |

---

## 1. Context

Three upstream facts, all established by T0.5, set the problem:

1. **The 4.8.0 headers expose no version symbol.** There is no way to ask the loaded library which upstream commit it came from. Identity has to be ours (PRD §12.3), on every path.
2. **Upstream ships no Android binary on GitHub Releases.** Release 4.8.0 has 8 assets, none of them Android; upstream's Android library is on GitHub Packages behind an access token (upstream README line 48). Every Android artifact a consumer of this SDK fetches is one we produced and host.
3. **The iOS xcframework *is* on GitHub Releases and does carry a checksum** — `WalletCore.xcframework.zip`, sha256 `0c79df1a901a3abfbccee5052229984b1e743696483176b3cfb68eaf90f400bc`, declared in upstream's `Package.swift` for SPM and confirmed byte-for-byte locally. It is the **only** upstream-attested checksum available to us: six of the eight assets have no published checksum at all, including `TrustWalletCore-4.8.0.tar.xz`, which is the input DECISION-9's Apple path relinks.

DECISION-9's recommendation, pending D0, is **Option C**: Apple libraries are relinked from the static archives inside `TrustWalletCore-<tag>.tar.xz` together with our `wcf_build_info.c` (one dynamic library per slice, 464 `TW*` symbols plus ours, and a macOS host library from the same step); Android is built from the git tree at the pinned commit with the identity file in the link; Apple moves to from-source at M3. This record is designed on that shape, and §7 says what changes if D0 picks B-only.

## 2. The build-identity symbol

### 2.1 Exact C signature

```c
/* packages/wallet_core_flutter_native/src/identity/wcf_build_info.c
 * Compiled by us and linked into every artifact we publish, on every platform.
 * The returned pointer is static storage owned by the library. The caller must
 * not free it, and it is NOT a TWString — upstream's delete functions must
 * never be called on it. It stays valid for the lifetime of the loaded image.
 */
const char *wcf_build_info(void);
```

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

### 3.1 Content-addressed immutable URLs

```
{retention.primary}/{artifact_set_id}/{sha256}/{filename}
```

for example

```
https://github.com/<org>/<repo>/releases/download/native-4.8.0-001/as_4.8.0_001/<sha256>/android-arm64-v8a-libTrustWalletCore.so
```

Rules, all enforced by the build workflow (T1.2):

- The sha256 in the path is the sha256 the manifest pins for that artifact. A URL therefore *names its own content*; a URL that returns different bytes is detectable without trusting the host, because the fetcher compares against the manifest anyway and the path makes a substitution obvious to a human reading a log.
- A release tag `native-<upstreamTag>-<seq>` is created once and never re-uploaded to. Correcting an artifact means a new set id and a new tag, never a replacement under an existing URL.
- `retention.primary` is a base URL, not a per-file URL, so a mirror is a base-URL swap and nothing else changes.
- The fetch is build-time only (PRD §16 S4). Nothing in this scheme is reachable at runtime.

### 3.2 Retention promise — wording to publish

Published in `docs/artifact_retention.md` (T3.13) and linked from `retention.policy`:

> **Artifact retention.** Every native artifact set referenced by a published version of `wallet_core_flutter`, `wallet_core_flutter_bindings`, or `wallet_core_flutter_native` stays fetchable, unmodified, from the primary URL and from the mirror for **at least 24 months** after the last package version that references it is superseded, and in no case for less than **12 months** after that version is retired from pub.dev's recommended set. Artifact sets are never modified in place: a correction is always a new set with a new id, published as a new release of the package set. If retention is ever going to end for a set, notice is published in the repository's releases and in `SECURITY.md` at least 90 days beforehand. This promise is made by this project about storage this project controls; it is not a service-level agreement, and it is not a promise about GitHub, pub.dev, or any other third party's availability.

The last sentence is the honest part and must not be dropped: a retention promise that implies a guarantee about someone else's infrastructure is a claim we cannot keep.

### 3.3 Mirror candidates and an honest cost estimate

**Size per artifact set.** Only the Apple side is measured: T0.5's relinked iOS device library is **19 720 768 bytes** and the macOS host library **19 876 872 bytes**. The simulator slice is a fat binary of two architectures, so on the order of 40 MB. **No Android `.so` exists yet anywhere** — upstream ships none and we have not built one — so the Android figure is an estimate anchored on upstream's own 26 MB iOS device slice: 20–35 MB per ABI. With three ABIs that gives roughly:

| Component | Size |
|---|---|
| Android × 3 ABIs | 60–105 MB *(estimated, no artifact exists yet)* |
| iOS device | ~20 MB *(measured)* |
| iOS simulator (fat) | ~40 MB *(estimated from the device slice)* |
| macOS host | ~20 MB *(measured)* |
| **Total per set** | **≈ 140–185 MB**, call it **200 MB** with dSYMs and checksums |

**Cadence.** Upstream tagged 4.8.0 on 2026-08-28. Assuming we absorb 8–15 upstream tags a year plus a few recovery releases, that is **1.6–3 GB of new artifacts per year**, and with the 24-month promise a steady state of roughly **4–6 GB** under retention.

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
const String manifestSha256 = '<sha256 of the canonical JSON of compat_manifest.json>';
```

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
| `artifacts.<path>.provenance` | **new per-artifact field**: `built_from_source` \| `relinked_from_upstream_release_asset` | DECISION-9 §4.4 |

Two of these are schema changes to files this task does not own: `identity.build_workflow` and the per-artifact `provenance`. `compat_manifest.json` and `tools/manifest/lib/manifest.dart` belong to T0.7; the changes are requested here and applied by **T1.2** (which produces the values) with the validator updated in the same change. Until then `manifest:validate` neither requires nor rejects them.

## 6. Consequences for tasks

| Task | What changes |
|---|---|
| **T1.2** — native artifacts workflow | Owns `wcf_build_info.c` and the JSON of §2.1 (three keys, `build_workflow` included); allocates `artifact_set_id`; uploads under the content-addressed URL scheme of §3.1; emits the CycloneDX SBOM; writes `identity`, `artifacts` (with `provenance`), `toolchain`, and extends the manifest schema and validator for the two new fields. |
| **T1.7** — native package core | Implements the four comparisons of §2.3 with a distinguishing `check` on `ManifestMismatchError`; treats a missing `wcf_build_info` as `NativeLoadError`; never hashes the loaded library; fetches from `retention.primary` and falls back to `retention.mirror` **only** when it is non-null, applying the same checksum check to both. |
| **T0.7 follow-up (in T1.2)** | `compat_manifest.json` gains `identity.build_workflow` and per-artifact `provenance`; the validator accepts and requires them once populated. |
| **T3.11** — release set | Owns `tools/manifest/embed_release_set.dart`, the exact pins of §4.2, the publication order and hosted-install smoke of §4.3 as a workflow, and `docs/releases/process.md` including §4.4 verbatim. |
| **T3.13** — retention policy and `SECURITY.md` | Publishes §3.2's wording, re-checks the mirror pricing of §3.3 against current rate cards, and links the advisory process of §4.4.5. |
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

Nothing in this record needs rewriting under B-only; §5's `provenance` column collapses to one value.

## 8. Answers to threat-model questions

Questions 1–3 of `docs/security/threat_model.md` §6 are addressed to DECISION-12 and 4–6 to DECISION-13; none is addressed to this record. Four threat rows are answered by it, and they are recorded here so T5.7 can check them against the built system:

- **TM-14 (artifact substitution in transit).** §3.1's content-addressed immutable URLs plus the manifest's sha256, with no "continue anyway" path in the fetcher (T1.7).
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
