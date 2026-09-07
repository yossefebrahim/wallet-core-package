# DECISION-9 — Source of the native artifacts

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

| | |
|---|---|
| **Question** | Where does this project's native libraries come from, given that PRD §12.3 requires every artifact set to carry a build-identity symbol `wcf_build_info()` that upstream does not provide? |
| **Governing PRD sections** | §12.1–12.4, §15.3, §22 DECISION-9 and DECISION-14 |
| **Evidence** | [`evidence/release-assets-4.8.0.md`](evidence/release-assets-4.8.0.md) (T0.5, 2026-09-07), built on `evidence/prefetch-2026-09-07/` |
| **Status** | **Recorded 2026-09-07 - Option C adopted** (section 7). Recommended by T0.5, adjudicated at D0, contested there, and decided against that contest for the reasons stated. DECISION-14 (distribution contract) depends on this; DECISION-2 (packaging mechanism) consumes finding F2. |
| **Recommendation** | **Option C**, in the specific shape of §5 below: relink upstream's release-asset static archives on Apple platforms, build from source in CI on Android, one identity symbol linked into both. |

---

## 1. Context

PRD §12.3 requires that each artifact set embed a build-identity symbol, `wcf_build_info()`, returning the upstream commit and an artifact-set id, which `WalletCore.initialize()` compares against `compat_manifest.json` and on mismatch raises `ManifestMismatchError` (PRD §15.3). The requirement exists because **[VERIFIED 2026-09-07, orchestrator]** the 4.8.0 headers expose no library-version symbol, and hashing a loaded library at runtime is meaningless when the library may be statically linked into the host binary. T0.5 corroborated this by inspection: the only version-shaped exported symbols in any 4.8.0 artifact are Xcode's `@(#)PROGRAM:WalletCore  PROJECT:TrustWalletCore-1` stamp and the bundled protobuf runtime's own version (evidence F6). Neither `4.8.0` nor `d692ac27749d0c615e17c751b70ab4f0aa75c59b` is recoverable from anything upstream ships.

**The identity symbol is ours in every option.** DECISION-9 is therefore not "can we have identity?" but "what do we have to build in order to have it, and what else does that buy or cost?"

Two facts from the evidence file reshape the question as the PRD framed it:

- **The PRD's iOS assumption is wrong at this tag.** §12.1 records `[UNVERIFIED] whether a dynamic slice is available or must be built` and describes upstream's iOS distribution as a static xcframework. `WalletCore.xcframework.zip` at 4.8.0 is a **dynamic** framework (`MH_DYLIB`, install name `@rpath/WalletCore.framework/WalletCore`, device and simulator slices, iOS 13 minimum) that exports exactly the 464 `TW*` C functions its headers declare (F2, F3).
- **Android has nothing to mirror.** Release 4.8.0 carries 8 assets and not one is an Android artifact. Upstream's Android binary lives on GitHub Packages behind an access token (README line 48, group `com.trustwallet.walletcore`) (F7). "Mirror upstream's binaries" has no Android meaning.

A third fact reshapes the options themselves: **[MEASURED]** the `TrustWalletCore-4.8.0.tar.xz` release asset contains `WalletCoreCommon.xcframework`, four families of **static archives** — `ios-arm64`, `ios-arm64_x86_64-simulator`, `ios-arm64_x86_64-maccatalyst`, and **`macos-arm64_x86_64`** — each carrying the same 464 symbols with upstream's Rust components already compiled in (F10). Relinking one of those archives together with a four-line C file that defines `wcf_build_info()` produces a loadable dynamic library with both the full C API and our identity symbol; the macOS result was opened with `dart:ffi` and called successfully, and the iOS device result is a 19.7 MB Swift-free dylib against upstream's 26.2 MB (F11).

---

## 2. Options

### Option A — mirror upstream's binaries plus a separate companion identity library

Take upstream's `WalletCore.xcframework.zip` as published, re-checksum it into our manifest, and ship beside it a tiny per-platform library that we compile, containing nothing but `wcf_build_info()` and the artifact-set id.

- **How identity is provided.** A second library, `libwcf_identity.dylib` / `.so`, loaded next to upstream's by `wallet_core_flutter_native`. `WalletCore.initialize()` resolves `wcf_build_info` from the companion, the 464 `TW*` symbols from upstream's.
- **What the consumer downloads.** Upstream's asset (32 MB compressed, 150 MB extracted, two iOS slices) **plus** `WalletCoreSwiftProtobuf.xcframework.zip` (3.3 MB), which upstream's framework hard-links via `LC_LOAD_DYLIB` (F4), plus our companion (kilobytes). On Android: nothing, because there is nothing (F7).
- **What CI must build.** Only the companion — a C file per ABI/slice. Minutes.
- **What T1.2 must produce.** A mirror job (download, verify, re-upload to our Releases with content-addressed URLs), a companion-library build matrix, and manifest rows for both. `packages/*_native/src/identity/` holds one C file.
- **T1.6 host tests.** No. Upstream ships no directly loadable host library; the macOS binary that exists is a static `ar` archive (F10), and using it means relinking, which is Option A′.
- **What T1.7 verifies.** That both libraries load, that `wcf_build_info()` from the companion matches the manifest, and — the weak point — nothing that ties the companion to the upstream library beside it. The companion asserts an identity it has no way to check.
- **T1.8 dynamic iOS slice.** Satisfied as shipped (F2). But the build hook must emit **three** code assets per iOS SDK/arch (WalletCore, WalletCoreSwiftProtobuf, companion) under identical names across SDKs, which is exactly the constraint the Flutter docs warn about (PRD §12.1, iOS specifics row).
- **Android.** Not available. Option A cannot be the whole answer.

### Option A′ — relink upstream's release-asset static archives with our identity object *(measured variant of A; not in the original option set)*

Take `TrustWalletCore-4.8.0.tar.xz`, extract `WalletCoreCommon.xcframework`, and for each Apple slice link the static archive plus our `wcf_build_info.c` into one dynamic library that we publish.

- **How identity is provided.** Linked into the same binary as the C API. There is no companion to get separated from, and `wcf_build_info` and `TWAnyAddressIsValid` provably came out of one link step.
- **What the consumer downloads.** One library per Apple slice, ~19.7 MB for iOS arm64 (F11) against 26.2 MB + 3.3 MB for Option A, with no Swift-runtime or SwiftProtobuf linkage.
- **What CI must build.** `lipo -thin` + one `clang -dynamiclib` per slice, with a `-u` list generated from the 464 header-declared names. No Rust, CMake, protoc, or boost. Minutes, on a macOS runner.
- **What T1.2 must produce.** The relink script under `tools/native_build/`, the identity C file under `packages/*_native/src/identity/`, plus the symbol-list generator (shared with T1.4/T1.5) and dSYM emission if crash symbolication is wanted — upstream's `WalletCore.xcframework.dSYM.zip` does not describe a relinked binary.
- **T1.6 host tests.** **Yes.** The `macos-arm64_x86_64` slice relinks into a `.dylib` that `dart:ffi` opens and calls (F11). `melos run test:native` gets a real library on the host with no source build.
- **What T1.7 verifies.** Identity, release-set id, and the full 464-symbol lookup, all against one library.
- **T1.8 dynamic iOS slice.** Yes, and a cleaner one: one code asset per SDK/arch instead of three.
- **Android.** Still nothing. Option A′ cannot be the whole answer either.
- **Cost.** We depend on the internal structure of an asset upstream does not document and does not checksum (only two of eight assets have published checksums, and this is not one of them — F1). The archives are not self-consistent: `-Wl,-all_load` fails on eight undefined Monero symbols in `range_proof.o` (F11 caveats), so the `-u` list is load-bearing and must be regenerated at every tag.

### Option B — build from source in CI at the pinned commit, with the identity symbol linked in

Fetch the git tree at `d692ac27749d0c615e17c751b70ab4f0aa75c59b`, run upstream's dependency and codegen tooling, build per platform, and add our `wcf_build_info.c` to the link.

- **How identity is provided.** Linked into every artifact we produce, on every platform, by one mechanism.
- **What the consumer downloads.** Our artifacts only: per-ABI Android `.so`, an Apple xcframework or per-slice dylibs, and a host library for CI. Nothing from upstream at consumer build time.
- **What CI must build.** Everything upstream's own `android-ci.yml` and `ios-ci.yml` build: `tools/install-sys-dependencies-*`, `tools/install-rust-dependencies`, `tools/install-android-dependencies`, `tools/install-dependencies`, `tools/generate-files`, then CMake/Gradle/Xcode. JDK 17, Gradle 8.10.2, a pinned NDK (r27+ for 16 KB defaults — §4), CMake, a Rust toolchain, boost. Upstream runs the Android job on `macos-latest-large` and the Kotlin job on `macos-latest-xlarge`.
- **What T1.2 must produce.** `build-native.yml` with a full toolchain matrix, artifact upload with content-addressed URLs, checksums, an export-visibility check on every `.so`, and the 16 KB alignment check.
- **T1.6 host tests.** Yes on macOS, and additionally on Linux if we build a Linux host library — the only route to one, since no Linux artifact exists upstream (evidence §5).
- **What T1.7 verifies.** Same as A′, plus manifest `toolchain` fields that are genuinely ours to state.
- **T1.8 dynamic iOS slice.** Yes — we choose the link mode, so a dynamic slice is available by construction.
- **Android.** **This is the only option that produces an Android library at all.**
- **Cost.** The longest CI path in the project, a toolchain surface we must pin and keep working across upstream refactors, and the unresolved symbol-visibility report of issue #4638 (F8) sitting on exactly the `tools/android-build` path we would use.

### Option C — both

A′ (or A) for Apple; B for Android; one `wcf_build_info.c` shared by both link steps; both feeding one artifact set with one `release_set` id.

---

## 3. Risks

| Risk | Applies to | Assessment |
|---|---|---|
| **Android upstream binaries are token-gated.** README line 48: GitHub Packages, "you need to add GitHub access token to install it" (F7). | A | Not a risk to manage — a hard exclusion. No unauthenticated consumer, build hook, or CI job can fetch it, and mirroring a token-gated Maven artifact is not a thing we should do quietly. Android forces B. |
| **Symbol visibility on Android — issue #4638** (open, 2026-01-29, no maintainer reply): a Flutter user built the `.aar` with `./tools/android-build` at v4.5.0, confirmed `libTrustWalletCore.so` present and loadable, and got `Failed to lookup symbol 'TWAnyAddressIsValid': undefined symbol` (F8). | B | Real and unresolved, but **not proven to be a wallet-core bug**: the reporter gives no `nm` output, and the cause could be `-fvisibility=hidden`, a version script, `--gc-sections`, or their own ffigen setup. The Android build is tuned for JNI, where `TW*` symbols need only be reachable *within* the `.so`, not exported *from* it — so a visibility gap there would be unsurprising. Mitigation is cheap and mandatory either way: `llvm-nm --defined-only --extern-only` on every `.so`, reconciled against the 464-name list, as a **build-job gate**, plus `-fvisibility=default` on the TW translation units if it fails. It does not reproduce on iOS (F3), which tells us the source declarations are annotated correctly and the problem, if any, is in the Android link configuration. |
| **Build time and toolchain pinning.** Rust + CMake + NDK + Gradle + protoc + boost, on macOS runners, per ABI. | B | The dominant recurring cost. Every upstream tag bump risks a toolchain break that blocks the release rather than degrading it. NDK must be r27+ so `-Wl,-z,max-page-size=16384` is the default; upstream's `android-ci.yml` pins `ndk: 23.1.7779620` in its emulator step, which we cannot inherit (evidence §6). |
| **Trust and provenance of mirrored bits.** We would redistribute binaries we did not compile, under our release page, with our checksums. | A, A′ | Two-sided. Against: we cannot state a toolchain for objects we did not build, so `compat_manifest.json.toolchain` is partly a copy of upstream's `Info.plist` (`DTXcodeBuild 17F113`, `iphoneos26.5`) rather than a fact about our build, and PRD §12.4's **Demonstrated reproducibility [REQ]** is unreachable for those bits by construction. In favour: on iOS the relinked objects are byte-for-byte the ones inside upstream's own published release asset for the pinned tag (`TrustWalletCore-4.8.0.tar.xz`, F10) — arguably a *stronger* claim than "we rebuilt it and it seems fine". What that asset is used for downstream of upstream's release page is not something this evidence establishes, and no claim is made about it. The honest framing is that A′ trades our provenance for upstream's, and the manifest must say which. |
| **A′ depends on undocumented asset internals.** `TrustWalletCore-4.8.0.tar.xz` has no published checksum, no documented layout, and at least one internally inconsistent object (F11 caveats). | A′ | Medium. The failure mode is loud (extract fails, or the link fails) rather than silent, and T4.3's upstream-watch job would catch a layout change at the next tag. But it means A′ can stop working at any upstream release with no notice and no recourse, which is why it must not be the *only* path. |
| **Split identity in Option A.** The companion library asserts an identity for a neighbour it cannot verify. | A | This is the reason to prefer A′ over A. A′ removes the failure mode entirely by linking identity and API in one step. |
| **Two build paths to maintain.** | C | Real, but smaller than it looks: the Apple path is one `clang` invocation and the Android path is required regardless. The genuine cost is that `release_set` must be assembled from two jobs and the manifest must record two provenance kinds. |
| **16 KB alignment is unverifiable today.** No ELF object exists in anything upstream ships (F12). | all | Blocks a PRD §12.2 step-8 acceptance criterion until T1.2 produces a `.so`. Not a discriminator between options — it is a gate on B's output whichever option we choose, because only B produces Android artifacts. |

---

## 4. Recommendation

**Option C**, with this shape:

1. **Android — Option B, unconditionally.** Build from the git tree at `d692ac27749d0c615e17c751b70ab4f0aa75c59b` with `tools/android-build`, NDK r27 or newer, `wcf_build_info.c` in the link. There is no alternative: upstream publishes no Android artifact and its GitHub Packages coordinate is token-gated.
2. **Apple — Option A′ first.** Relink `WalletCoreCommon.xcframework`'s `ios-arm64`, `ios-arm64_x86_64-simulator` and `macos-arm64_x86_64` static archives with `wcf_build_info.c` into dynamic libraries we publish. Do **not** ship Option A's separate companion library; a linked-in symbol is strictly better and, as measured, no harder.
3. **Apple — keep Option B as the declared target for M3.** When the Android from-source pipeline is working, the incremental cost of building the Apple slices the same way is a CMake/Xcode matrix on a runner that is already provisioned. Moving Apple to B is what makes PRD §12.4's **Demonstrated reproducibility [REQ]** reachable for the whole artifact set, and it removes the dependency on an undocumented asset layout.
4. **One `wcf_build_info.c`, one `release_set` id, one manifest**, regardless of which path produced which row. Add a per-artifact `provenance` field (`relinked_from_upstream_release_asset` / `built_from_source`) so the manifest never implies we compiled bits we did not.

**Reasoning.** The recommendation is forced from both ends and the middle is where the judgement lies.

It is forced *toward* B by Android: 8 assets, none of them Android, and the one upstream binary that exists is behind a token. Whatever else we decide, a from-source Android build exists in this project.

It is forced *away from* B-only by the schedule. B's Apple leg costs a full Rust+CMake+Xcode pipeline, and T1.2 gates T1.7, T1.8, T1.9 and T1.19 — four of the heaviest Phase-1 tasks, two of them the DECISION-2 packaging evaluations that the whole M0 milestone turns on. A′ delivers a working, identity-carrying, dynamically loadable Apple library from a 54 MB download and one `clang` invocation, and it delivers something B cannot deliver quickly at all: a **real macOS host library for `melos run test:native`**, which is what lets T1.6's memory and disposal tests run against actual `TWData`/`TWString` behaviour instead of a fake. That is worth more to the correctness of this SDK than uniform provenance is, this early.

The middle judgement is A versus A′, and the measurement settles it. Option A as briefed — mirror plus a *separate* companion — has the companion asserting an identity for a library it cannot check, ships two extra frameworks on iOS because upstream's build drags in SwiftProtobuf and the Swift runtime (F4), and makes T1.8's build hook emit three code assets per SDK/arch under naming constraints the Flutter docs specifically caution about. A′ has none of that, produces a smaller binary (19.7 MB vs 26.2 MB + 3.3 MB), and links identity and API in one step. There is no measured reason to prefer A over A′.

The strongest single fact behind all of it: **the same release download that gives Apple everything — dynamic framework, static archives, headers, and a macOS host slice — gives Android nothing at all.** One source cannot serve both platforms, so C is not a hedge; it is a description of what the artifacts are.

**What would make this wrong.** If D0 weights uniform provenance above schedule — a defensible position for a wallet SDK — then B-only is the answer, and the cost is paid in T1.2 becoming the long pole and T1.6 losing its host library until the Apple pipeline lands. That trade is the orchestrator's to make, and it is the one thing in this record that measurement cannot decide.

---

## 5. Consequences for tasks

| Task | Change |
|---|---|
| **T1.1** — upstream pin and source fetch | Must fetch the **git tree** at commit `d692ac27749d0c615e17c751b70ab4f0aa75c59b`, not a release asset: `src/proto/` and `registry.json` exist in no asset (F13). Add a second fetch for release asset `TrustWalletCore-4.8.0.tar.xz` (54 MB) as the Apple binary input, and compare its `include/TrustWalletCore/` (143 headers) against the git tree's before setting `schemas.headers_sha`. Record that the asset has no upstream-published checksum. |
| **T1.2** — native artifacts workflow | Two jobs, not one. **Apple job** (macOS runner): download + verify asset 3, extract, `lipo -thin`, generate the `-u` symbol list from headers, `clang -dynamiclib` with `packages/*_native/src/identity/wcf_build_info.c`, per slice; emit dSYM. **Android job**: full from-source build at the pinned commit, NDK **r27+**, identity file in the link; then two mandatory gates — export-visibility (`llvm-nm --defined-only --extern-only` reconciled against the 464-name list, per issue #4638) and 16 KB alignment (`llvm-readelf -l`, every `LOAD` segment `Align 0x4000`). Both jobs emit a **macOS host library** for `test:native`. Manifest gains a per-artifact `provenance` field. |
| **T1.4 / T1.5** — proto and registry generation | Unchanged in substance, but they now own the canonical **464-name symbol list**, which T1.2 consumes as the linker `-u` list and as the visibility-gate expectation. Make it a generated artifact, not an ad-hoc grep. |
| **T1.6** — memory wrappers, `Disposable`, leak tracker | **Unblocked earlier than planned.** A real macOS host library is obtainable from a release asset with no source build (F11), so `melos run test:native` can exercise `TWData`/`TWString` lifetimes, double-dispose, and finalizer behaviour against the actual library from Phase 1. Add native-backed tests rather than relying only on fakes. |
| **T1.7** — native package core | Verifies **one** library per platform, not a library plus a companion: resolve `wcf_build_info`, compare `upstream_commit` and `artifact_set_id` against `compat_manifest.json`, raise `ManifestMismatchError` on mismatch (PRD §15.3), then look up all 464 symbols. Add a negative test that a library **without** `wcf_build_info` fails loudly — that is the case a mirrored-without-relink artifact would hit. |
| **T1.8** — build-hooks evaluation (Option 1) | **The dynamic iOS slice question is answered: yes** (F2). Upstream already ships a dynamic framework, and A′ produces one too, so `DynamicLoadingBundled()` has something to bundle and PRD §12.1's *Static vs dynamic* `[UNVERIFIED]` row can be closed. Evaluate against the **A′ artifact** (one code asset per SDK/arch), not upstream's (which would need three, including `WalletCoreSwiftProtobuf`). |
| **T1.9** — conventional packaging evaluation (Option 2) | Same input artifacts. The podspec/SPM path must decide whether to wrap the A′ dylibs in an xcframework we assemble or vend them directly; note that upstream's own device slice is unsigned and its simulator slice only ad-hoc signed (F5), so signing is ours to do either way. |
| **T1.19** — packaging measurement harness | Gains three concrete checks it can now specify precisely: export-visibility reconciliation against 464 names; `llvm-readelf -l` alignment on 64-bit `.so` files; duplicate-symbol scan sized by the measured 57 174 total exports of an upstream-style build. `libc++_shared` handling on Android and the iOS privacy manifest remain **T1.19's own measurements** — this record only notes that upstream ships no `PrivacyInfo.xcprivacy` and that our Apple artifacts link `/usr/lib/libc++.1.dylib`. |
| **T4.3 (upstream watcher)** | Must watch two things, not one: the tag, and the **layout of `TrustWalletCore-*.tar.xz`**. A′ breaks silently at the next release if `WalletCoreCommon.xcframework` moves, loses its macOS slice, or changes archive structure. |
| **T0.11 / DECISION-14** | Consumes this record directly: identity symbol shape and where it is linked; per-artifact `provenance`; content-addressed retention for artifacts we host (which is all of them, on both paths); the `release_set` id spanning two build jobs; and the fact that six of eight upstream assets carry no upstream checksum, so our recorded values are first-seen. |
| **DECISION-2** | Finding F2 removes the *Static vs dynamic* uncertainty from PRD §12.1's comparison table. Both packaging options now start from a dynamic Apple library. |

---

## 6. Revisit trigger

Re-open this decision when any of the following occurs:

1. **Upstream publishes an Android artifact on GitHub Releases**, or drops the token requirement on GitHub Packages — Option A becomes possible on Android and the case for a from-source Android build weakens to the identity symbol alone.
2. **The layout of `TrustWalletCore-<tag>.tar.xz` changes** — specifically if `WalletCoreCommon.xcframework` loses its `macos-arm64_x86_64` slice, stops being static archives, or the relink stops producing all 464 symbols. Any of these ends Option A′ at that tag.
3. **Upstream adds a version or build-identity symbol** to the C API — the premise of the whole record (identity must be ours) changes, though a *our*-artifact-set id would still be needed.
4. **The Android from-source build reproduces issue #4638** after `-fvisibility=default` and version-script fixes — Option B's Android leg would then be blocked and the decision becomes "no Android support at 4.8.0", which is a product decision, not a packaging one.
5. **PRD §12.4's Demonstrated reproducibility [REQ] reaches its M3 milestone** — at that point every artifact must come from a pinned-toolchain build we control, i.e. Apple moves from A′ to B and this record's step 3 is executed.
6. **The Apple from-source pipeline lands** (planned M3) — retire A′ or keep it as a cross-check, and record which.

---

## 7. Decision

**Option C is adopted, in the exact shape of section 4**: Android built from source at the pinned commit, Apple
relinked from the release-asset static archives (A') with our identity object, one `wcf_build_info.c`, one release-set
id, one manifest, and a per-artifact `provenance` field. Apple moving to a from-source build stays the declared **M3**
target, not an aspiration - section 4 step 3 and revisit trigger 5 are the commitment.

**Why C over the B-only position D0 defended.** Four reasons, in the order they carry weight:

1. **Android decides nothing here.** Upstream ships no Android artifact and its Packages coordinate is token-gated, so
   a from-source Android build exists in this project under every option. The real question is only what Apple does in
   Phase 1.
2. **A' buys a real macOS host library now.** It is what lets `melos run test:native` exercise `TWData`/`TWString`
   lifetimes, double-dispose, and finalizer behaviour against the actual library at **T1.6**, the task that writes the
   PRD section 11.2 disposal contract. Testing that contract against a fake, and finding the difference in Phase 2, is
   a worse failure than non-uniform provenance.
3. **The provenance objection is answered structurally, not waived.** Every relinked row is labelled
   `relinked_from_upstream_release_asset` in the manifest; the record states that six of eight upstream assets carry no
   upstream checksum and that ours are therefore first-seen values; and PRD section 12.4's Demonstrated reproducibility
   [REQ] is *not* claimed for A' rows - AGENTS.md rule 8 forbids the word until the M3 demonstration exists. Nothing on
   this path lets the project assert more than it can show.
4. **T1.2 is on the critical path.** It gates T1.7, T1.8, T1.9 and T1.19, two of which are the DECISION-2 packaging
   evaluations that M0 turns on. Making a full Rust + CMake + Xcode pipeline the long pole of Phase 1 risks the
   milestone for a property M3 delivers anyway.

**Condition attached.** A' breaks silently if the tarball layout moves, so revisit trigger 2 is not optional
bookkeeping: **T4.3 must watch the layout of `TrustWalletCore-*.tar.xz`**, not only the tag. If that watch is not
built, this decision loses its safety net and B-only becomes the right answer.

**What would reverse this.** The M3 Apple-from-source move slipping past M3 without a recorded reason, or a measured
finding in T1.2 that the relinked Apple artifacts differ observably from a from-source build. Either turns section 4
step 3 from a schedule into a defect.

Recorded **2026-09-07 by the orchestrator**, under the repository owner's standing authorization to keep Phase 0 moving while they were unavailable, and **subject to the owner's ratification** (`docs/plan/PROGRESS.md` -> Needs your eyes -> "Decisions recorded on your behalf"). The choice is reversible at the cost stated in the revisit trigger; nothing is published.
