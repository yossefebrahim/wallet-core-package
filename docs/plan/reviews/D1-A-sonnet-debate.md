# D1-A report — DECISION-1, M0 exit criteria, Phase-1 ratifications

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

Debater A, checkout `D1-A` at `main` 4e1ff93. Pinned upstream `d692ac27749d0c615e17c751b70ab4f0aa75c59b` (read at `third_party/wallet-core`).

**What I ran, and what I could not.** `melos` and `flutter` cannot run in this sandbox: they write to `~/flutter/bin/cache` (`engine.stamp`, `engine.realm`: "Operation not permitted"). The `dart` binary from the Flutter SDK does run when called by its full path. I ran two gates that way:
- `dart run tools/lint/bin/public_api_lint.dart` → `49 exported elements checked, 0 violations`.
- `dart run tools/vectors/bin/validate.dart test_vectors` → `Files: 2, Vectors: 5, Exclusions: 0`.

I did **not** re-run `analyze`, `test`, `test:native`, `gen:check` or `inventory:check`. Their results are "orchestrator-measured, CI run 38154205218 on `08e3b17`" and I label them so. `gh run view` was denied (network), so I could not check the CI claim either. Everything else below is read from files; line numbers are on this checkout.

---

## A. Recommendation per contested point

### A.1 DECISION-1 — recommend Position C: A is the shipped design now, B stays reserved behind named triggers, and the T2.0 seam is made B-ready

**Three strongest data points**

1. **A's measured residual is small and I count it the same way.**
   - Copies of the key on the Dart heap: **0**. Reading `withDerivedKey` (`engine/hd_wallet.dart:327-369`) and `SyncSigningCore.sign` (`signing/signing_core.dart:153-210`), I count:
     - one Dart-visible `Uint8List` *view* over upstream's `TWData` (`hd_wallet.dart:367`);
     - one SDK-allocated `calloc` staging buffer, filled by `setAll` and zeroed by `fillRange` in a `finally` (`engine/secret_buffers.dart:113-141`);
     - three upstream objects (`TWPrivateKey`, the key `TWData`, the keyed-input `TWData`), each released before the reply (DECISION-1-approach-a.md §2).
   - No protobuf message and no Dart list ever holds the key: the key field is prepended as tag‖length‖key into the native buffer (`signing_core.dart:220-228`).
2. **The dominant residuals are identical under A and B, so B cannot remove them.**
   - I read the upstream source. Ethereum signs through `RustCoinEntry::sign` (`src/rust/RustCoinEntry.cpp:98-103`), which copies the whole keyed input into a Rust `TWData`. That is a `Vec<u8>` (`rust/tw_memory/src/ffi/tw_data.rs:10-30`) freed by dropping the box (`:75-78`) with no zeroize.
   - A copy of the key-carrying input is therefore freed unwiped on every sign, under A and B alike.
   - What B removes is exactly the view and the calloc buffer, and it shortens how long the key `TWData` lives: A holds #1, #2 and #4 while upstream signs, B holds #1 and #4 (DECISION-1-approach-b.md §2.1, on the branch).
   - Upstream *does* wipe what it controls: `~PrivateKey` memzero (`src/PrivateKey.cpp:399-400`), `TWDataDelete` memzero (`src/interface/TWData.cpp:106-115`), and `~HDWallet` memzero of seed, mnemonic and passphrase (`src/HDWallet.cpp:102-105`).
3. **B's cost is in build, provenance and evidence, and none of it exists for mobile.**
   - The shim is wired only into `build_apple.sh --with-shim`, which refuses every slice but macOS. `git show eval/approach-b:tools/native_build/build_android.sh` has 0 mentions of "shim" and `.github/workflows/build-native.yml` has 0. `build_apple.sh` has 47.
   - The branch was cut before the hook was ported: `git ls-tree eval/approach-b packages/wallet_core_flutter_native` shows no `hook/`, and the branch is 64 commits behind `main`.
   - A shipped B means a different artifact set (`as_<tag>-shim_nnn`), a third `provenance` value in the manifest schema, and the library is no longer "upstream's object code plus a label" (B doc §6).
   - Every Phase-1 device result (CI x86_64 and iOS simulator, local arm64 and consumer_check) is for the standard set `as_4.8.0_001`. B would invalidate all of it and force a re-run.
   - B adds 263 lines of C (about 105 statements) on the key path, a hand-written FFI signature no generator checks, a per-family adapter, and a C splice walker for nested key fields (B doc §7-§8).

**SignJSON (T1.14) does not matter to DECISION-1.** It matters only to Phase-5 breadth, and even there raw proto signing in `advanced.dart` covers every coin.
- Upstream's JSON path is `JsonStringToMessage` → `input.set_private_key(key)` → `SerializeAsString()` → a `Data` copy → `sign` → the Rust copy (`src/rust/RustCoinEntry.h:36-60`, read). That is a protobuf object holding the key, a `std::string` and a `Data`, none wiped, *more* unwiped native copies than A makes.
- It returns only `hex(encoded)` for Ethereum (`src/Ethereum/Entry.cpp:13-19`), with no v/r/s and no error code.
- It fills one top-level field only, and Bitcoin is not covered (`sign_json_coverage.md`: 106 of 167 supported, Ethereum and Solana yes, Bitcoin no).
- "Key stays native" is true but is not "key is wiped".

**Strongest point against.**
- B is cheap on the host: one session, 143 turns, $6.72 (PROGRESS.md T1.13 row), +384 bytes, 9 s build.
- It removes the only two pieces of key handling that are SDK-controlled. A's `fillRange` has no `volatile` guarantee (B doc §2.3), and a future edit could retain the view.
- Deferral gets dearer with each family. Bitcoin and Solana code written against `Uint8List` keys will have to be redone if B comes later.

**Position C is neutral at the public API; I checked.**
- The public `Signer.sign(TransactionRequest, Set<KeyLocator>) → Future<SignResult>` (`signing/signer.dart:35`) names no key bytes and no handle. `lint:public-api` is 49/0, and `CoinType` is not in the export list (`lib/wallet_core_flutter.dart`).
- `SigningCore` is internal and "never exported" (`signing/signing_core.dart:1-3, 30`). Its factory is `typedef SigningCoreFactory = SigningCore Function(NativeContext)` (`worker/handler.dart:29`, default at `:139`).
- B's own seam change touched three library files and moved `privateKey` from `Uint8List` to `PrivateKeyHandle` (B doc §1.2). All of it is internal.
- But "later" is not free: it is a new artifact set, a provenance schema change and a full device re-run, not an SDK API change.
- **Ownership gap (finding D6):** the multi-key injection that Bitcoin and Solana need (`SigningCore.sign` takes one key at `signing_core.dart:56`; `_resolveKeys` throws `StateError` unless the family needs exactly `KeyRole.primary`, `handler.dart:452`) is owned by no Phase-2 task. T2.0's owned paths exclude `signing_core.dart`, `engine/hd_wallet.dart` and `worker/handler.dart`, and T2.5 and T2.6 own only `requests/` and `families/`. The shape of that seam is where A and B differ (`Map<KeyRole, Uint8List>` against `Map<KeyRole, PrivateKeyHandle>`). Decide it now, or it gets redesigned twice.

**What would flip me to B**
- (a) A release/AOT measurement showing the staging-buffer zeroing is elided or not performed. I did not run one; I can't build in this sandbox.
- (b) A P1 user requirement, or the external review (T5.8), that no Dart-visible key view may exist.
- (c) Upstream wipes the Rust copy and exposes a handle-taking sign entry point, which would make B's gain real and its C trivial.
- (d) B built with relink-in on Android and the iOS device slice, with the manifest/provenance schema change accepted by the owner and device evidence re-run in under about one T1.16b+T1.17b cycle.

**Triggers to record in DECISION-1:** (a)–(c) above, plus "T2.5 shows the multi-key seam cannot take a borrowed `Uint8List` view without a copy".

### A.2 Phase-1 close — recommend Position Y, scoped: the device-flow clause assertions are not hardware-gated and must be fixed. Physical devices need a recorded owner waiver or a run.

**Three strongest data points**

1. **The device runs are credited with clauses they do not assert.**
   - `example/integration_test/m0_flow_test.dart:56` checks only `signed!.error == null`.
   - `tools/consumer_check.sh:446` checks only `result.encoded.isEmpty` is false, and its summary string is literally `"signed N bytes; gap: no public KeyRef"` (`:453`).
   - `example/lib/src/m0_flow.dart:138-144` says the device flow signs with the HD-derived key, so "the bytes produced differ from the vector's".
   - The vector `ethereum-sign-eip1559-1` uses a raw private key (`test_vectors/ethereum/vectors.yaml`), so byte-for-byte on a device through the public surface is structurally impossible today. It is proven only on the macOS host (`signing_core_native_test.dart:101`).
   - Invalid address and invalid path are not on any device. The device test checks only the invalid mnemonic (`m0_flow_test.dart:26-32`).
   - Leak-tracker-zero and identity-mismatch are host only (C.2, C.3).
2. **The iOS device slice has never been executed.**
   - It is a different binary (`ios-arm64`) from the simulator slice. It has been built unsigned only: `consumer_check.sh:394-398` runs `flutter build ios --release --no-codesign`, and a simulator cannot run release.
   - PRD §12.2 step 3 ("confirm the app launches and signs") is thus unmet for iOS release on any target.
   - This is the PRD-level risk the physical rows cover: "does the shipped device binary load, sign and launch under platform code-signing".
3. **D1a already named these as pre-close gaps.**
   - Opus D1a Q5, "Before Phase 1 closes": physical arm64 Android and iPhone, debug and release; x86_64 runtime; second Flutter version; cold Gradle cache (`D1a-opus-debate.md:142-150`).
   - Codex D1a listed "physical devices" as a closure gate (`D1a-codex-debate.md:129`).
   - The owner ratified only the x86_64 item (DECISION-14 §10a). That one is now met (CI, orchestrator-measured). No physical-device waiver exists anywhere: `grep -i "waiver"` over PROGRESS and the D1a debates finds none.

**What emulator/simulator evidence does cover (so Position X is not baseless).**
- The arm64-v8a ISA path: local arm64 emulator, both `.so` sha256 equal to the manifest (`consumer_check.sh:374-381`).
- The x86_64 path (CI). The iphonesimulator slice (CI and local).
- Android release in arm64: `am start` plus a logcat `WCF_M0 PASS` (`consumer_check.sh:534-575`).
- The hook fetch, sha/size verification, packaging and packaged-dependency consumption on both platforms.

**Minimum evidence to close (my Y).**
1. **Not hardware-gated, must be fixed first.**
   - Byte-for-byte vector signing on a simulator/emulator. The only route that keeps AGENTS.md rule 7 provenance is a package-level `integration_test` that drives `SyncSigningCore` with the vector's raw key on device. The plan's T1.17 owned `packages/wallet_core_flutter/integration_test/`, which does not exist.
   - Invalid-address and invalid-path asserts in the device flow.
   - A device-side identity-mismatch test: `initializeForTesting(expectedIdentity: wrong)` with a null host path on device. TM-13's owner list expects exactly this: "T1.17 (identity-mismatch negative test on a device)".
   - Either a leak-report seam on device, or an owner-approved rewording (see D3).
2. **One physical iPhone, debug and release** (`flutter run --release`). This is the single cheapest evidence against the biggest unproven binary.
3. **Physical Android: waivable.** It is the same arm64-v8a bytes the emulator ran, sha-verified. The residual (vendor linker, runtime 16 KB-page behaviour) must be named in the waiver. A 16 KB-page emulator image run, if one exists for API 35, would cover the page-size part without hardware (inference).

**Strongest point against (Position X's best case).** Hardware may not be available, the Phase-1 emulator/simulator evidence base is already large, and the owner's lane decisions so far have all been emulator/simulator-based. A named waiver with an owner and a re-open trigger is a legitimate, honest closing record.

**What flips me.** The owner records a waiver for the physical rows naming owner, task and trigger (suggest: a pre-alpha gate task and DECISION-2's App Store reopen trigger), **and** the F1–F3 assertions land.

### A.3 DECISION-2 — ratify as final (Option 1, build hooks)

- **Data.**
  - Every condition in `DECISION-2.md §2` is met: eval/option1 ported (`hook/build.dart`, T1.R1), `android_libcpp_shared` dropped (`packages/wallet_core_flutter_native/pubspec.yaml:30-32` comment, no dependency), ABI refusal documented (`wallet_core_flutter_native/README.md:26`), release published.
  - The provisional condition is met: networked hosted fetch, both `.so` digests equal to the manifest.
  - Device CI is green on x86_64 and the iOS simulator (orchestrator-measured).
- **Against.** The iOS device slice has never run; the privacy manifest needs a consumer edit (`README.md:21`) and a signed archive has not been validated by App Store Connect; AAB was not built (README gives the command, no result); one Flutter version only.
- **Flips.** An App Store rejection, a hooks-protocol change in a Flutter stable, or the iOS device load failing. These are already DECISION-2 §4's reopen triggers. Record the signed-archive, AAB and second-Flutter items as pre-alpha gates, not Phase-1 gates.

### A.4 DECISION-6 — ratify (Flutter >=3.47.5)

- **Data.** All four `pubspec.yaml`s and CI pin 3.47.5 / Dart 3.13.4 (`ci.yml`, `flutter-version: 3.47.5`); the floor equals the only measured version.
- **Against.** `>=3.47.5` is open-ended upward and untested above; D1a Opus listed a second Flutter version as pre-close.
- **Flips.** Any failure on the next stable. The re-measure trigger is already in DECISION-6 §3. Keep it; add a CI job on the next stable when one ships.

### A.5 DECISION-14 remaining items — ratify §§2–5 and fix the text of §10 g and §10 h

- **§10 a–f**: ratified 2026-10-05 (DECISION-14 lines 349-353). a (x86_64 run) is now met by CI.
- **§10 g** is amended by the owner to "comparison 2 opt-in until T3.11". The code agrees: `handler.dart:277-278` checks only when `manifestBytes != null`, and `session/wallet_core.dart:44` passes none. The paragraph still ends "Neither is chosen here", which contradicts its own first sentence. Comparisons 3 and 4 (artifact-set id, upstream commit) do run by default.
- **§10 h** says "Published 2026-10-05… Ratified" and also "The release is still a draft". DECISION-2 §2 records the hosted fetch from that release, so it is published; the draft sentence is stale.
- **The header** says "overall ratification of the record still owed", and PROGRESS marks DECISION-5, -9, -11, -12, -13 and -14 §§2–5 "awaiting your ratification" (PROGRESS.md decisions log). Phase 1 built on all of them; ratify at D1 (DECISION-5 stays re-openable at T3.12).
- **Flips.** None of substance; this is paperwork the owner owes.

### A.6 `--no-enable-impeller` — a CI-lane note, not an exit-criteria problem

- **Why.** It changes the render path of the test app, not the library load/sign path. Release and packaged evidence come from local runs without the flag. The hang it works around is upstream Flutter issue flutter/flutter#192736 (per `ci.yml:295-298`).
- **Caveat.** Causation is unproven. The d2 change bundled the flag with an AVD snapshot cache, a verbose reporter, an inner timeout and diagnostics (PROGRESS.md T1.17 row). There is one green run (38154205218) and no control run with the flag only. The first run hung in 54 minutes with no logs.
- **Ask.** Record it in PROGRESS as a known Flutter issue with a removal trigger, and take two more runs of the Android job for flake data before relying on it. It does not block closing.

---

## B. Evidence matrix (question 1)

**Cell codes.** `P` PROVEN, `U` UNPROVEN, `N/A` not applicable (reason in the key). Each environment shows **debug / release**. AE = Android emulator, AD = Android device, IS = iOS simulator, ID = iOS device.

**Evidence key**
- **E1** CI job "Android emulator" (x86_64, API 35, `--no-enable-impeller`), `example/integration_test/m0_flow_test.dart`, run 38154205218 (orchestrator-measured; I could not fetch it).
- **E2** CI job "iOS simulator" (iPhone 17 / iOS 26.5), same test, same run.
- **E3** local `tools/consumer_check.sh` run 2026-10-11 (orchestrator-measured, exit 0, 8/8): arm64 emulator debug and release, iOS simulator debug. Its flow is `runM0` (`consumer_check.sh:408-453`).
- **H** macOS host tests, tag `native`, CI job "Native tests" and local.
- **R** iOS release is built only (`consumer_check.sh:394-398`). A simulator cannot run it.

| Clause (PRD §18 M0 exit) | AE | AD | IS | ID |
|---|---|---|---|---|
| Create wallet | **P/P**: E1 (`m0_flow_test.dart:15-20`) x86_64 debug; E3 arm64 debug+release (`m0.dart` `create`). x86_64 release not run | U/U | **P**/N/A (R): E2, E3 | U/U |
| Import known mnemonic | **P/P**: E1 (`:35-38`), E3 | U/U | **P**/N/A (R) | U/U |
| Derive `0x9968…69b1` at `m/44'/60'/0'/0/1` | **P/P**: E1 (`:43-52`); E3 exact-match `throw` (`consumer_check.sh:422`) | U/U | **P**/N/A (R) | U/U |
| Sign EIP-1559 and match the vector **byte for byte** | **U/U**: devices assert only `error == null` (`:56`) or non-empty bytes (`consumer_check.sh:446`); the flow's key differs from the vector's (`m0_flow.dart:138-144`). Host only: `signing_core_native_test.dart:101` ("reproduces the vector's encoded, v, r and s byte for byte"), H | U/U | **U**/N/A (R) | U/U |
| Invalid **mnemonic** raises a typed error | **P/P**: E1 (`:26-32`, title `InvalidInputError`); E3 (`consumer_check.sh:427`, debug+release) | U/U | **P**/N/A (R) | U/U |
| Invalid **address** raises a typed error | **U/U**: host only, `engine_native_test.dart:207` ("a valid and an invalid Ethereum address"), H | U/U | **U**/N/A (R) | U/U |
| Invalid **derivation path** raises a typed error | **U/U**: host only, `derivation_path_test.dart:45` (pure Dart), `sign_handler_native_test.dart:207` (H) | U/U | **U**/N/A (R) | U/U |
| Explicit `close()` / `dispose()` exercised | **P/P**: E1 (`:59-64` closeWallets + shutdown); E3 (`wallet.close()`, `core.shutdown()`, `consumer_check.sh:449-450`) | U/U | **P**/N/A (R) | U/U |
| Leak tracker reports zero undisposed | **U/N/A**: the example cannot read the report ("not on the public surface", `m0_flow.dart:512-526`); in release the tracker is not constructed (assert-gated), so the check is vacuous. Host only: `example/test/m0_flow_native_test.dart:96-103` (`live == 0`, `finalizedWithoutDispose == 0`), `signer_native_test.dart:218` + tearDown `:62-70`, H | U/N/A | **U**/N/A | U/N/A |
| Fresh consumer from packaged (not path) dependencies, no manual native edits | **P/P**: E3, loopback hosted repository, lockfile `source: hosted` checked (`consumer_check.sh` stages 1-8). Local only; not in CI. Caveat: App Store submission needs a manual iOS edit (D15) | U/U | **P**/built (R): E3 | U/U |
| Identity check **passes** | **P/P** implicit: `initialize()` verifies, and E1 and E3 initialize on device. No explicit assert | U/U | **P**/N/A (R): E2, E3 implicit | U/U |
| A **mismatched manifest fails** | **U/U** on device. Host only: `session_native_test.dart:118` ("an identity mismatch is `ManifestMismatchError(artifactSetMismatch)` and leaves nothing to close"), `:147-161` (manifest-hash mismatch), `verify_identity_test.dart:36, 154`, H. Wrong checksum at **build**: Option 1 eval row 7, "wrong digest: build fails" (`DECISION-2-option1.md:74`) | U/U | **U**/N/A (R) (host only; build-time pass in eval) | U/U |
| DECISION-1 recorded with data | Evidence docs exist (`DECISION-1-approach-a.md` on `main`, `…-approach-b.md` on the branch). **No decision record**: `docs/decisions/DECISION-1.md` does not exist and the log row (`PROGRESS.md:477`) is open | | | |
| DECISION-2 recorded with data | **P**: `DECISION-2.md` plus the option docs | | | |
| DECISION-6 recorded (plan addition) | **P**: `DECISION-6.md` | | | |
| DECISION-14 recorded (plan addition) | **P** for §10 a–h; §§2–5 overall ratification owed (DECISION-14 header) | | | |
| `gen:check` on every generated dir (plan addition) | **P** per orchestrator: CI job "Generated code" (`ci.yml`, run 38154205218). I did not re-run it | | | |
| `lint:public-api` (plan addition) | **P**: I ran it, 49 elements, 0 violations. Also in the CI "gates" job | | | |
| No public signature exposes `CoinType` (plan addition) | **P**: export list read (`lib/wallet_core_flutter.dart`), no `CoinType`; lint 0 violations | | | |

**Row counts for the owner.** All 12 clause rows on the device columns are U for AD and ID. On AE/IS the clauses *not* proven by any device run are: byte-for-byte, invalid address, invalid path, leak tracker, identity mismatch (5 of 12).

---

## C. Answers

### C.0 Threat model (§7 mandatory question)

I checked each cited row against code. The model is dated 2026-10-04/05 and was refreshed against `main` `672e09e`, before T1.16b and T1.17 landed (PROGRESS.md T1.16 and T1.17 rows).

**Rows that change under each DECISION-1 outcome**

| Row | If A (as built on `main`) | If B (`eval/approach-b`) |
|---|---|---|
| TM-01 key residence | Residual: view + zeroed calloc buffer + upstream objects #1, #2, #4. Owner T1.12 (built), T2.0, T2.1, T2.10 | Residual shrinks to #1 and #4 (+ upstream's copies); the view and buffer disappear. Owner adds the shim |
| TM-17 lengths, TM-19, TM-20 null returns | The rows list "adapter" as a component, but no adapter exists. Their wrapper-side mitigations are what apply | New C bounds (input at most 2 GiB − 1024, key 1–256 bytes) and a NULL-return contract in `wcf_sign.c`. A C owner is added |
| TM-24 request carries a key | The key-field check runs in Dart only (`handler.dart:346`, `signing_core.dart`). Per-family lists reviewed in Dart | Injection is in C. Needs the `#define` ↔ `key_fields.json` test (`field_number_test.dart`) per family and a C-side layout probe |
| TM-15 compromised CI, TM-33 build-time modification | Artifact = upstream object code + the identity object | The shim is our code on the key path in the artifact; a third `provenance` value; the record must carry the adapter source hash (B doc §6) |
| TM-14/TM-16 artifact and manifest integrity | Unchanged: digests in the manifest for set `as_4.8.0_001` | New set id (`as_<tag>-shim_nnn`), new digests, and the release re-published |
| TM-34 allow-listed exports | Four JNI extras | `wcf_sign_ethereum` added to the export gate |
| TM-13 library path | Main's hook loader on iOS opens only the framework path and never `DynamicLibrary.process()` (`code_asset_locations.dart:59-80`), so B's §5.3 ambiguity concern is moot under Option 1 | A second library would also need to be opened by name |
| TM-36 gates not in CI | n/a | `run_shim_tests.sh` has no CI step (B doc §10) |
| New rows B needs | None | C memory safety next to the key; hand-written FFI signature drift; ABI coupling to upstream headers per tag (B doc §9) |

**Rows whose stated mitigation is not implemented on `main`**
- **TM-24**: "a test asserts the check fires for Bitcoin's `repeated bytes private_key` and Solana's three key fields." No test does. `grep fee_payer_private_key|nonce_account_private_key` over `packages/wallet_core_flutter/test` and `lib` returns nothing. The only repeated-field test is synthetic (`evm_family_test.dart:305-317`, an Ethereum `Access.stored_keys`). Owners: T2.0, T2.5, T2.6, T2.12.
- **TM-30**: "a test asserts [the debug aids] are inert in a release-mode build." `leak_tracker_test.dart:250-251` and `leak_tracker.dart:155-157` hand the proof to T1.17. T1.17 is complete and no such test exists (grep for `inert|release-mode|kReleaseMode` over tests and tools finds only those two comments).
- **TM-13**: its owner list says "T1.17 (identity-mismatch negative test **on a device**)". That test exists on the host only.
- **TM-16**: comparison 2 is not on the default path. The owner amended this at D1a (DECISION-14 §10 g), so it is recorded rather than a defect.
- **Stale the other way** (mitigation now built, row still says it is not):
  - **TM-10** says the no-network runtime test "does not exist". `melos run test:no-network` exists (`pubspec.yaml:149-152`).
  - **TM-36** says CI does not run `test:native`, `lint:public-api`, `lint:runtime-deps` or `vectors:validate`. `ci.yml` now runs all four (the `gates` and `native` jobs).
  - §7 says the D1 outline lacks this very question ("As of 2026-10-04 the D1 outline… does not yet carry that question"). `phases/phase-1-m0-spike.md:101-105` still lacks it.

### C.2 Leak tracker on a device run?

**No.** Not asserted on any device or simulator run.
- The example flow shows `leak-tracker report: not on the public surface (see README)` (`m0_flow.dart:520-524`), and `m0_flow_test.dart` has no leak assertion.
- Host only: `example/test/m0_flow_native_test.dart:96-103`, `signer_native_test.dart:62-70` (tearDown) and `:218` ("20 signs in a loop leave zero undisposed"), `engine_native_test.dart`, `session_native_test.dart`, and the bindings' `leak_tracker_test.dart`.
- In release the tracker is `null`: it is built only inside an `assert` (`LeakTracker.maybeCreate()`, per TM-30 evidence; `leak_tracker.dart:203` is the assert). "Leak tracker reports zero in release" is vacuous, and the PRD clause needs rewording or a defined meaning.

### C.3 Identity check passes / mismatch fails

- **Passes.** Every successful `WalletCore.initialize()` on a device or simulator runs the embedded-manifest comparison: E1, E2, E3. It is implicit, with no explicit assertion.
- **Mismatch fails.** Proven on the macOS host only:
  - `session_native_test.dart:118` (expected `as_wrong`, actual `as_4.8.0_000`, which is the locally built host library, not the published `as_4.8.0_001`);
  - `session_native_test.dart:147-161` (manifest-hash mismatch);
  - `verify_identity_test.dart:36, 51, 67, 154, 183-250`, which use a fake identity function.
- **On a device or simulator: UNPROVEN.**
- **Build-time wrong checksum** is proven in the Option 1 evaluation (`DECISION-2-option1.md:74`: "wrong digest: build fails"), not on the shipped landing code.

### C.4 Approach B and the mobile artifacts

**Does it compile into Android/iOS artifacts at all? No.**
- `eval/approach-b` has the shim only in `build_apple.sh`. There, `--with-shim` "refuses every slice but macos-arm64_x86_64" (lines 38-40). The branch's `build_android.sh` and `build-native.yml` mention shim 0 times.
- The branch has no `hook/` directory (cut from `integration/W3` before T1.R1). `main` is 64 commits ahead.
- T1.13 is host scope only, as you said. B doc §5.2-5.3 is explicitly "analysis, not built, pending D1a".

**What Option 1's hook needs to change to ship B**
- **Relink-in (recommended by B doc §5):** nothing in `hook/`. `hook/build.dart` selects the manifest artifact per target, verifies sha256 and size, and emits one `CodeAsset` (`hook/build.dart:1-20`). Whatever library the manifest names works.
- **Second library:** two code assets per target, a loader change for the second library, and a same-image check change. Not recommended.
- **What the work actually is** (inferences from B doc §6 and the files above):
  - lift the macOS-only guard in `build_apple.sh`;
  - add a generated `src/` file for Android, as is done for the identity file;
  - `--require-symbol wcf_sign_ethereum` in the export gate for 2 ABIs and 3 Apple slices;
  - a manifest schema and validator change (third `provenance`, adapter source hash);
  - a new artifact set id and a re-published release;
  - re-run T1.16b and T1.17b device evidence.

**Estimate in T1.13's units** (label: inference, from T1.13's own numbers)
- T1.13 was one implementer session plus delta 1: 143 turns, $6.72, about 105 lines of C statements, 130 lines of Dart, +109 build-script lines, an 80-line test runner, and about 1,200 test lines (B doc §4).
- Mobile wiring is **about one more implementer session plus one delta** (the build scripts) **plus one orchestrator publish cycle** (T1.2 pattern, with the burn-the-id rule in DECISION-14 §10 f).
- The **dominant cost is re-evidence**: T1.16b alone took d1–d9 and T1.17b took d1–d2 (PROGRESS rows). That would repeat on every platform.
- Bitcoin and Solana add one adapter per family, plus a C splice for Solana's nested `create_nonce_account` and BitcoinV2's nested `private_keys` (50–70 lines and a fuzz target per B doc §3 and §8).

### C.5 Does Phase-1 code constrain DECISION-1?

- **No public API constraint.** `SigningCore.sign` takes `Uint8List privateKey` (`signing_core.dart:52-58`), is internal, and is built through `SigningCoreFactory` (`handler.dart:29, 139`). `PrivateKeyHandle` lives in `engine/handles.dart:59` and is not exported (`advanced.dart` exports only `HDWallet`, `NativeResultError`, the registry and the bindings library).
- **`withDerivedKey` is the only door to a key** (`hd_wallet.dart:327`), never exported.
- Choosing B later changes the internal seam from `Uint8List` to `PrivateKeyHandle`, as T1.13 did, and adds a library-symbol requirement at `Init`. The only user-visible effects are existing error types (`NativeLoadError`, `ManifestMismatchError`) and a new artifact set.
- **Internal constraint:** one key per sign call, `KeyRole.primary` only (`handler.dart:452`). Multi-key is needed for either approach and is unowned (D6).

### C.6 Overclaims

The "pass" does not prove the claim in each of these:
1. **DECISION-2 §2 and the T1.16 row**: "the M0 flow passed on the Android emulator (debug and release) and the iOS simulator (debug)." The consumer flow checks address match, the invalid mnemonic and non-empty signed bytes (`consumer_check.sh:408-453`); it does not compare bytes, test address/path errors, or read a leak report. Release is launch plus a logcat line.
2. **T1.17 "identity-mismatch negative test"**: macOS host only (C.3). TM-13 expects it on a device.
3. **T1.12 acceptance "byte-for-byte match"** is true on the host. The device flow cannot match it.
4. **TM-24**: claims tests for Bitcoin and Solana key fields that do not exist (C.0).
5. **T1.17 closed without TM-30's release-mode inertness test**, which two code comments hand to it.
6. **All five vectors have `platforms_verified: []`** (`test_vectors/ethereum/vectors.yaml:13, 26, 39, …`), including the ones the host tests verify. A "Tested" count derived from the inventory would be zero.
7. **DECISION-14 §10 h** says "published" and "still a draft" in one paragraph; **§10 g** says "Amended by the owner" and "Neither is chosen here".
8. **DECISION-1-approach-a.md §2.1** says upstream's signing-time copies are "not reachable… not verified here". The source shows the Rust copy is freed unwiped (B doc §9; I verified `RustCoinEntry.cpp:98-103` and `tw_data.rs`). The approach-a doc counts "3 native objects + 1 buffer" while the B doc counts A as "4 native objects" — the same facts, two framings.
9. **PROGRESS T1.13 row** says "awaiting DECISION-1 at D6"; the plan says D1.

---

## D. Findings

| # | Severity | Where | Description | Suggested fix | Owner |
|---|---|---|---|---|---|
| D1 | **blocking-for-phase-close** | `example/integration_test/m0_flow_test.dart:56`; `tools/consumer_check.sh:446`; `example/lib/src/m0_flow.dart:138-144` | No device or simulator run asserts the EIP-1559 result against the vector. The device flow signs with the HD-derived key; the vector uses a raw key, so the bytes differ by construction | Package-level `integration_test` driving `SyncSigningCore` with the vector's raw key on device (keeps rule 7 provenance); or an owner-approved vector for the HD key with a stated provenance kind. Assert encoded, v, r, s | new T1.R task (suggest T1.R2) |
| D2 | **blocking-for-phase-close** | `m0_flow_test.dart:26-32` | Only the invalid mnemonic is asserted on a device. Invalid address and path are host-only (`engine_native_test.dart:207`, `derivation_path_test.dart:45`) | Add both steps to the device flow, with `InvalidInputError.inputName` asserted | T1.R2 |
| D3 | **blocking-for-phase-close** (or owner rewording) | `m0_flow.dart:512-526`; `leak_tracker.dart:203` | Leak-tracker-zero is host-only; the example prints "not on the public surface"; in release the tracker is `null` | Read the report through the internal seam in a package-level `integration_test` (debug devices), and reword the PRD clause for release ("no tracker is built in release") with the owner's sign-off | T1.R2, owner for wording |
| D4 | **blocking-for-phase-close** (needs a run or a recorded waiver) | `consumer_check.sh:394-398` | iOS device slice (`ios-arm64`) never loaded, signed or launched; iOS release never run on any target; physical Android never run | One physical iPhone debug + release run; Android physical waivable if the residual is named. Waiver goes in PROGRESS with owner, task and re-open trigger | owner; run by owner/orchestrator |
| D5 | **blocking-for-phase-close** (cheap) | `session_native_test.dart:118`; TM-13 owner list | Identity mismatch is host-only; TM-13 expects a device test | `initializeForTesting(expectedIdentity: wrong)` in the device integration test | T1.R2 |
| D6 | should-fix-before-T2.0 | `signing_core.dart:52-58`; `handler.dart:452`; `phases/phase-2-*.md` T2.0/T2.5/T2.6 "Owns" | The multi-key injection seam (a key per `KeyRole`) is owned by no Phase-2 task. T2.0's paths exclude `signing_core.dart`, `hd_wallet.dart`, `handler.dart` | Add those paths to T2.0 and fix the seam type at D1 (A: borrowed views; B-ready: borrowed `PrivateKeyHandle`s) | T2.0 brief, orchestrator |
| D7 | should-fix-before-T2.0 | `leak_tracker.dart:155-157`; `leak_tracker_test.dart:250-251` | TM-30's release-mode inertness test is owed to T1.17, which closed without it | Add the test (compile a release/AOT program) and list it in a Phase-2 or rework task | T1.R2 or T2.1 |
| D8 | should-fix-before-T2.0 | `docs/security/threat_model.md` TM-10, TM-24, TM-30, TM-36, §7 | Rows stale against T1.16b/T1.17; TM-24 claims non-existent tests; the D1 outline still lacks the §7 question | Refresh TM to `main` HEAD; add the question to `phases/phase-1-m0-spike.md` | orchestrator (TM refresh) |
| D9 | should-fix | `PROGRESS.md:477` | `docs/decisions/DECISION-1.md` is linked but does not exist | Write the record at D1 with the DECISION-1 evidence and triggers | orchestrator |
| D10 | should-fix | `DECISION-1-approach-a.md` §2.1 | States upstream's signing-time copies are unverified. They are verified: the Rust keyed-input copy is freed unwiped | Say so, and carry it into `docs/security/memory_contract.md` as a known, approach-independent residual | T1.18-follow-up |
| D11 | should-fix | `ci.yml` device jobs; `tools/consumer_check.sh` | CI device jobs run **debug only**; release builds and the packaged consumer are a one-off local run (2026-10-11) | Record the commit and run id of that consumer_check, or add a periodic CI job | orchestrator; T3.x |
| D12 | should-fix | DECISION-14 §10 g, h; header | Contradictory text (see C.6 item 7); "overall ratification owed" | Edit text; ratify §§2–5 | owner + orchestrator |
| D13 | should-fix | `ci.yml:295-298`; PROGRESS T1.17 row | `--no-enable-impeller` causation unproven; one green run | Two more runs; record removal trigger | orchestrator |
| D14 | nit | `DECISION-2.md:7`, `DECISION-6.md:7` | Evidence links point to `evidence/DECISION-2-option1.md`; the file is `docs/decisions/DECISION-2-option1.md` | Fix the links | orchestrator |
| D15 | nit | `README.md:21`; `wallet_core_flutter_native/README.md:61-85` | The PRD clause says "no manual native edits"; App Store submission needs a consumer edit to `PrivacyInfo.xcprivacy` | State in the exit record: install, build and run need none; store submission needs this one | orchestrator |
| D16 | nit | `test_vectors/ethereum/vectors.yaml` | `platforms_verified: []` on all five vectors | Fill from CI at T2.2-T2.4, or document that the field is not yet written | T2.x vector tasks |
| D17 | nit | PROGRESS T1.13 row | "D6" should be "D1" | Fix | orchestrator |
| D18 | nit | `phases/phase-1-m0-spike.md` T1.17 "Owns" | `packages/wallet_core_flutter/integration_test/` does not exist; device tests live in `example/integration_test` | Note the deviation in PROGRESS, or create the package-level test in D1 | orchestrator |
| D19 | nit | `eval/approach-b` | Branch is 64 commits behind and predates `hook/`; B doc §5 is stale after D1a (it says "pending D1a" and carries an iOS `process()` concern the Option-1 loader removes) | If B stays reserved, add a header note to the branch doc | orchestrator |
| D20 | nit | `docs/decisions/evidence/sign_json_coverage.md` | Measured on the locally built host library `as_4.8.0_000`, not the shipped `as_4.8.0_001` set | Note it; coverage derives from the coin registry at the same commit, so I expect no difference (inference) | T1.14 follow-up |

---

## E. Items the owner must decide at D1, in dependency order

1. **Ratify the Phase-0 decisions "awaiting ratification" (DECISION-9, -11, -12, -13, -14 §§2–5).** Recommend: ratify as built. Keep DECISION-5 re-openable at T3.12.
2. **Ratify DECISION-14 §10 g and h with the corrected text** (comparison 2 opt-in until T3.11; release `native-4.8.0-001` is published). Recommend: yes.
3. **Ratify DECISION-6 (Flutter >=3.47.5).** Recommend: yes, with "re-measure on each new stable" as the trigger.
4. **Make DECISION-2 final (Option 1).** Recommend: yes. Record the signed-archive / App Store Connect check, the AAB build and a second Flutter version as pre-alpha gates, not Phase-1 gates.
5. **Physical-device policy.** Recommend: require one physical iPhone, debug and release, before the tag; waive physical Android in PROGRESS naming the residual (vendor linker, runtime 16 KB-page behaviour), the owning task and the re-open trigger.
6. **Authorise a rework task (T1.R2) for the clause assertions that need no hardware:** vector byte-for-byte on device, invalid address and path, device identity-mismatch, and the leak report (debug devices). Recommend: yes, before the tag.
7. **Decide the PRD wording for "leak tracker reports zero" in release** (no tracker is built in release). Recommend: debug devices plus host assert it; release records "no tracker built".
8. **DECISION-1: A now, B later (Position C)** with the triggers in A.1, recorded as `docs/decisions/DECISION-1.md`. Recommend: yes.
9. **Fix the multi-key seam shape and assign its ownership in T2.0.** Recommend: borrowed `PrivateKeyHandle` per `KeyRole`, so B is insertable without touching the handler. T2.0's owned paths gain `signing_core.dart`, `engine/hd_wallet.dart` and `worker/handler.dart`.
10. **Threat-model refresh before the tag** (TM-10, TM-24, TM-30, TM-36, §7 question). Recommend: yes, as `T0.R`/`TM-update`.
11. **`--no-enable-impeller`: CI-lane note only.** Recommend: yes. Take two more Android runs and set a removal trigger.
12. **Tag `phase-1-closed`** only after items 5 and 6 are done or waived in PROGRESS. Recommend: no tag today.
13. **Host-config question already open in PROGRESS:** re-enable Swift Package Manager globally on this Mac. Recommend: yes; it removes the `example/ios` pollution.

---

## F. Readiness

**Phase 1 ready to close (`phase-1-closed`): No.** The single most important reason: the device runs credited with the M0 exit clauses do not assert them. There is no byte-for-byte vector check on any device (`m0_flow_test.dart:56` checks `error == null`), no invalid-address or invalid-path check, no leak or identity-mismatch check, and no physical device or iOS release run has happened at all. The first four are fixable on an emulator or simulator in one rework task; the last needs one iPhone run or a recorded owner waiver.

**T2.0 ready to start: No, for now.** The single most important reason: T2.0 depends on Phase 1 closed, and DECISION-1 is unrecorded. The multi-key signing seam T2.0 needs to build on is owned by no Phase-2 task, and its shape differs between approaches. Once D1 records DECISION-1 as "A now, B later" and assigns the seam to T2.0, T2.0 can start.
