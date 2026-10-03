# DECISION-1 evidence — Approach B as prototyped (T1.13)

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

| | |
|---|---|
| **Question** | PRD §11.4: where is the signing protobuf, with its private key, assembled — in Dart (Approach A), in a thin native adapter (Approach B), or A now and B later behind the same `Signer`? |
| **This document** | Evidence for the other side of that question: Approach B as prototyped for the EVM family on branch `eval/approach-b`, measured on the macOS host library, compared with Approach A as it is in the same tree (`DECISION-1-approach-a.md`, whose copy on this branch describes this tree's seam). Mobile packaging is **analysis only, not built, pending D1a**. |
| **Status** | **Evidence only.** DECISION-1 is the owner's to decide at M0 exit; nothing here decides it. The prototype is not the shipped design and is not the default: `EngineRequestHandler` still signs through Approach A unless it is given `AdapterSigningCore.new`. |
| **Pinned upstream** | tag `4.8.0`, commit `d692ac27749d0c615e17c751b70ab4f0aa75c59b` |
| **Libraries** | **standard:** `third_party/wcf-native/macos/arm64_x86_64/libTrustWalletCore.dylib` (unchanged by this task; sha256 `bb9266dc…db7cc9f7`, artifact set `as_4.8.0_000`). **shim:** `third_party/wcf-native-shim/macos/arm64_x86_64/libTrustWalletCore.dylib` (`build_apple.sh --with-shim`, sha256 `8ad763b1…4644ddb9`, artifact set **`as_4.8.0-shim_000`**). Both git-ignored, both built locally |
| **Date** | 2026-10-02; revised the same day (T1.13 delta 1) after the independent Approach B review and the port of T1.12's review fixes: the key field is now **prepended** in C as in Dart (§1, §3) |

---

## 1. What Approach B is, as built

PRD §11.4 sketches Approach B as "Dart encodes the key-less input, a small C adapter injects the key and calls `TWAnySignerSign`". As built:

- **Dart hands the adapter two things:** the key-less signing input as a `TWData`, and the **pointer** of the `PrivateKeyHandle` that owns upstream's `TWPrivateKey` — plus the coin type.
- **The C adapter** `wcf_sign_ethereum(TWData *keyless_input, struct TWPrivateKey *key, enum TWCoinType coin)` (`packages/wallet_core_flutter_native/src/shim/wcf_sign.c`): refuses NULL arguments and any coin whose upstream blockchain is not `TWBlockchainEthereum`; bounds the input (≤ 2 GiB − 1024) and the key (1–256 bytes); reads the key with `TWPrivateKeyData`; creates **one upstream `TWData` at the exact keyed size** (`TWDataCreateWithSize`) and writes into it, in this order, **the tag and length of `private_key = 9`, the key, and the key-less bytes**; deletes the key's `TWData` at once; calls `TWAnySignerSign`; deletes the keyed input; overwrites its own stack array through a volatile pointer; returns upstream's output (caller owns) or NULL. No logging. Plain C11, upstream's public headers only.
- **The precondition** (`wcf_sign.h`, restated in delta 1): the key-less input is **one complete, well-formed** `TW.Ethereum.Proto.SigningInput` with `private_key` absent. Well-formedness is the property that matters (§3). The Dart caller establishes it with `checkKeylessInput`'s decode before every call; the adapter does not check it.
- **The key is prepended, as in Approach A since T1.12 delta 1.** The first build *appended*; REVIEW B finding 1 showed that after key-less bytes truncated inside a length-delimited field, an appended key becomes that field's payload — the reviewer's probe got `error = 0` and a broadcastable transaction whose calldata was the key. Prepended, the key is always a complete field of its own, whatever follows. `keyed_layout_shim_test.dart` keeps the reviewer's probe as a regression test (§10).
- **One place decides the layout on each side**: `keyedInputParts` in Dart, the body of `wcf_sign_ethereum` in C; the same probes hold both to it (§10).

**No Dart code on the B path reads a key byte.** What Dart touches: the key-less bytes (copied into a `TWData` with `secretData`, as Approach A copies its keyed input, so a null from `TWDataCreateWithBytes` is that one operation's `SigningError` and the session stays `ready` — they hold no key, the check proves it first), the `PrivateKeyHandle`'s pointer value (the address of upstream's `TWPrivateKey`, passed to C and never dereferenced), the output bytes, and the `TWHDWalletGetKey` / `TWPrivateKeyDelete` calls in `withDerivedKey`, which create and destroy the key object without reading it. This is a statement about this SDK's code, not an isolation boundary: Dart and the adapter share one process and one address space, and `advanced.dart` lets a consumer call `TWPrivateKeyData` on its own.

### 1.1 File map

| File | Lines (total / code) | Role |
|---|---|---|
| `packages/wallet_core_flutter_native/src/shim/wcf_sign.h` | 115 / 24 | Contract and precondition, `WCF_SIGN_EXPORT`, `#define WCF_ETHEREUM_SIGNING_INPUT_PRIVATE_KEY_FIELD 9`, bounds |
| `packages/wallet_core_flutter_native/src/shim/wcf_sign.c` | 148 / 83 | The adapter |
| `packages/wallet_core_flutter/lib/src/signing/adapter/adapter_signing_core.dart` | 237 / 129 | `AdapterSigningCore implements SigningCore`; the hand-written binding (key typed `Pointer<TWPrivateKey>`); `adapterPrivateKeyField` (Dart mirror of the `#define`) |
| `tools/native_build/build_apple.sh` | +102 / −3 | `--with-shim`: compile the adapter per arch, link it, gate its export; refuses non-macOS slices, an `--out-dir` with `.`/`..` or whose resolved own name lacks "shim" (before creating it), and a non-shim artifact set id; writes no record and no uploadable |
| `tools/native_build/check_exports.sh` | +21 | `--require-symbol NAME` (repeatable, refuses `TW*` names) |
| `tools/native_build/run_shim_tests.sh` | 80 | The shim test run that cannot pass by skipping (§10) |
| `packages/wallet_core_flutter/lib/src/signing/signing_core.dart`, `engine/hd_wallet.dart`, `worker/handler.dart` | seam change, §1.2 | |
| `packages/wallet_core_flutter/test/signing/adapter/` | 1049 (6 files) | §10 |
| `packages/wallet_core_flutter/test/signing/keyed_layout_probes.dart`, `keyed_layout_native_test.dart` | 239 | The layout probes shared by both approaches |

"Code" lines exclude comments and blank lines. The C is about 105 lines of statements; the Dart core about 130.

### 1.2 The seam change, and what it did to Approach A

`SigningCore.sign` took `Uint8List privateKey`; a core that must not read the key cannot take bytes. It now takes **`PrivateKeyHandle privateKey`** (borrowed: never disposed, never retained). Consequences:

- `withDerivedKey` (`engine/hd_wallet.dart`) now derives the `TWPrivateKey` and hands its handle to `use`; it no longer calls `TWPrivateKeyData` or makes the view.
- `SyncSigningCore.sign` (Approach A) does the `TWPrivateKeyData` → `TWDataHandle` → `asTypedList` view step itself, after the coin and key-field checks, and releases that `TWData` in its own `finally`. A null result, an out-of-range or zero size, or a null buffer there is a `NativeResultError` (ported from T1.12 delta 1, where `withDerivedKey` raises it): the handler reports it as that one operation's `SigningError` and the session survives. `soft_native_failure_native_test.dart` drives exactly this path in this tree. The rest is the old body, now `signWithKeyBytes`, kept callable so that the byte-level tests (keys upstream rejects, a view over native memory, the caller's buffer left as it was) still run — a `TWPrivateKey` holding a malformed key cannot be constructed.
- Effect on A's copy table: the same four objects; #2 (the key's `TWData`) is created inside the core and released at the end of `SyncSigningCore.sign` instead of in `withDerivedKey`'s `finally` — before the core returns to the handler. `DECISION-1-approach-a.md` on this branch now says so (its §1, §1.1, §2, §3, §4, §7, §8 describe this tree).
- `SigningCoreFactory` gained the `DynamicLibrary` `Init` loaded: `SigningCore Function(NativeContext, DynamicLibrary)`. The default is `(context, _) => SyncSigningCore(context)`. One existing test changed shape (`sign_handler_native_test.dart`: the factory takes two arguments; `RecordingCore` records the handle and its liveness instead of the key's length, and the test asserts the handle was disposed before the reply).

### 1.3 How the adapter symbol is bound

The adapter is not an upstream header, so `inventory:check` (headers vs generated bindings, 466/0) is unaffected and `lib/src/generated/**` was not touched. The binding is hand-written in the SDK: `DynamicLibrary.lookupFunction<Pointer<TWData> Function(Pointer<TWData>, Pointer<TWPrivateKey>, Uint32), …>('wcf_sign_ethereum')`. The key is typed `Pointer<TWPrivateKey>` — the generated opaque struct — because `TWData` is `Void` in the generated bindings: with both untyped, swapping the two pointer arguments compiled and C would have read a `TWPrivateKey` as a `TWData` (REVIEW B finding 6). Typed, it does not compile; the change surfaced two such call sites in this task's own tests.

The lookup is on **the `DynamicLibrary` `Init` loaded and verified** — which is why the factory receives it. `AdapterSigningCore`'s constructor throws `NativeLoadError` when the symbol is absent (the standard artifact), so `Init` fails, with nothing to release; and `StateError` when the library it was given is not the image behind the context (`TWDataDelete`'s address compared). **That check is only as strong as the `DynamicLibrary` it is handed:** on macOS, Android and in the host tests it is one opened file; on iOS the loader tries `DynamicLibrary.process()` first (§5.3), and then both lookups search the whole process and the comparison cannot fail (REVIEW B finding 5).

Rejected alternatives: `@Native` (needs the native-assets asset id, which is D1a's business); `DynamicLibrary.process()` *as the chosen mechanism* (finds whichever loaded image exports the name — which is what iOS gets anyway, §5.3); a second `ffigen` config over `wcf_sign.h` (right for a shipped B, §11 item 5; overhead for a prototype).

## 2. A vs B side by side

Counted from the code, for one `wc.signer.sign(request, {KeyLocator.hdPath(...)})` on the EVM path, after the seam change.

### 2.1 Every copy of the key during one signing operation

| # | Where the key is | Approach A (`SyncSigningCore`) | Approach B (`AdapterSigningCore` + `wcf_sign.c`) | Who can overwrite it |
|---|---|---|---|---|
| 1 | Upstream `TWPrivateKey` (`TWHDWalletGetKey`) | From derivation to `withDerivedKey`'s `finally`, after the core returns | Same | Upstream: `TWPrivateKeyDelete` → `~PrivateKey()` → `memzero` (source, `src/PrivateKey.h:93`, `.cpp:399–400`) |
| 2 | Upstream `TWData` of the key's bytes (`TWPrivateKeyData`) | Created by Dart in `SyncSigningCore.sign`; alive **across** `TWAnySignerSign` and the parse; released in the core's `finally` | Created by the C adapter; **deleted before `TWAnySignerSign` is called** | Upstream: `TWDataDelete` → `memzero` (`src/interface/TWData.cpp:106–115`) |
| — | `Uint8List` view over #2 | **Exists in Dart**, for the length of one call; Dart code could read, copy or retain it | **Does not exist** | Not a copy; nothing to overwrite. The risk is what Dart code does with it |
| 3 | Staging buffer: tag-length ‖ key ‖ key-less | **Dart-allocated** `calloc` (`secretDataFromParts`); filled by `setAll`; overwritten with zeros by Dart (`fillRange`) and freed before `TWAnySignerSign` | **Does not exist.** The adapter writes straight into #4; its only array (`header[16]`) holds the tag and the key's *length*, and is overwritten on every exit anyway | A: this SDK's Dart code. B: n/a |
| 4 | Upstream `TWData`: keyed signing input (tag-length ‖ key ‖ key-less in both) | `TWDataCreateWithBytes(#3)`; alive across `TWAnySignerSign` and the Dart parse; released in the core's `finally` | `TWDataCreateWithSize`, filled in place; **deleted as soon as `TWAnySignerSign` returns**, before Dart sees the output | Upstream: `TWDataDelete` → `memzero` |
| U | Upstream's Rust `TWData`: a copy of #4 made inside `TWAnySignerSign` | Exists for the length of the call | Same | **Nobody: freed without being overwritten** (§9) |

| Count | A | B |
|---|---|---|
| Copies on the Dart heap | 0 | 0 |
| Dart-allocated buffers holding the key | **1** (#3) | **0** |
| Dart objects through which the key's bytes are readable | **1** (the view) | **0** |
| Native objects holding the key that this SDK causes to exist (counted as in `DECISION-1-approach-a.md` §2; upstream's internal copies such as U excluded) | **4** (#1–#4) | **3** (#1, #2, #4) |
| Held while upstream signs | #1, #2, #4 | #1, #4 |
| Held while Dart parses the output | #1, #2, #4 | #1 |

### 2.2 What crosses FFI

| | A | B |
|---|---|---|
| Calls on the key path | `TWPrivateKeyData`, `TWDataSize`, `TWDataBytes` (→ view), `TWDataCreateWithBytes` (keyed), `TWAnySignerSign`, `TWDataDelete` ×3 | `TWDataCreateWithBytes` (**key-less**), `wcf_sign_ethereum`, `TWDataDelete` ×2 (key-less input, output) |
| Key bytes in a Dart-visible buffer | Yes — the view over #2; `setAll` moves them into #3 | No — only a pointer value |
| What the native call receives | A keyed `TWData` the Dart side built | A key-less `TWData` and an opaque `TWPrivateKey*`, typed as such in Dart |
| Generated bindings used | All from `ffigen` | All from `ffigen`, plus one hand-written lookup |

### 2.3 Exposure

- **Dart heap.** Neither approach puts the key on the Dart heap. A's residual Dart-side exposure is the view: code that holds a `Uint8List` over key bytes for one call — a future change could log, copy or retain it (it would then dangle). B removes it.
- **Native memory.** A has one buffer this SDK allocates and must overwrite (#3); it is overwritten from Dart with `fillRange`, and Dart has no `volatile`: the stores are not removed by today's VM, but nothing in the language promises it. B has no such buffer; its only own array is overwritten through a volatile pointer, and every key copy it causes is an upstream `TWData` that upstream overwrites. Both share upstream's unwiped copy U, and both leave whatever `memcpy`/`memmove` leaves in registers and on the stack.

## 3. The precondition, and whether the adapter should check it natively

**What the precondition is.** The key-less input must be one **complete, well-formed** message with the key field absent. The first version of this section — and of `wcf_sign.h` — asked only for absence, which guards the less dangerous case (REVIEW B finding 1):

- *A key field planted in well-formed bytes* comes **after** the prepended one and wins (for a singular field the last occurrence is parsed): the transaction is signed with the planted key. The caller's key is not exposed; the signature is wrong. Absence still has to be proved for that reason.
- *Bytes that end inside a length-delimited field* were the dangerous case under appending: the key became that field's payload. Under prepending the key is a complete field before the truncated bytes, and upstream's parse fails on the truncation instead — the layout probe in §10 shows no key in the output and no signed transaction.

So prepending removes the case that exposes the key, and the decode in `checkKeylessInput` still rejects both cases before any key is touched. The adapter checks neither natively.

**What a native check would cost.** A top-level wire-format walk in C over the whole input — read a tag varint, dispatch on wire type 0/1/2/5 (reject 3/4), skip a varint, 8 or 4 bytes, or a length bounded by the remaining buffer, fail on field 9 with wire type 2, and fail unless the walk ends exactly at the end of the buffer. That proves top-level well-formedness and top-level absence: about 50–70 lines of C, every length bounds-checked, and it should be fuzzed, because a parser over untrusted bytes is the riskiest kind of C to add. It does not prove a nested sub-message well-formed (upstream's parse still catches that), and nested key fields (Solana's nonce account, BitcoinV2) need a per-family table of enclosing field numbers, generated from `key_fields.json`, not hand-kept. This is protobuf parsing, not cryptography (AGENTS.md rule 2 permits it). Not built. With prepending in place, its remaining value is defence in depth for a caller that skips the decode (a future `RawSigningInput`), at the price of the riskiest C in the adapter.

## 4. Effort actually spent

One implementer session on 2026-10-02, plus delta 1 the same day. The C compiled clean at `-std=c11 -Wall -Wextra -Werror -fvisibility=hidden` against the tarball's headers on the first attempt, before and after the prepend change; the shim build linked and passed the export gate on its first run each time. Written: ~105 lines of C statements, ~130 lines of Dart core, +109 lines of build scripts plus an 80-line test runner, about 1,200 lines of tests. The seam change touched three library files and three existing test files; delta 1's port of T1.12's fixes copied 21 files unchanged and merged four by hand (`hd_wallet.dart`, `signing_core.dart`, `handler.dart`, `signing_core_native_test.dart`), plus one test that needed adapting to the seam (`key_identity_native_test.dart`). The largest single cost remains the seam change and keeping A's tests meaningful through it, not the C.

## 5. Build complexity per platform

### 5.1 macOS host — measured

`--with-shim` adds two `clang -c` invocations (one per arch, same flags as the identity object plus `-std=c11` and `-I <tarball>/include`), one object on each link line, and one `--require-symbol` to the export gate.

Measured after the prepend change, from **one build of each**, back to back on the same machine and toolchain (Xcode 27.0, `MacOSX27.0.sdk`), same inputs. The shim row **is** the library the tests ran against (copied byte for byte to `third_party/wcf-native-shim/`):

| Library | Size | sha256 | `__TEXT` arm64 / x86_64 | Defined externals arm64 / x86_64 | Exported `TW*` |
|---|---|---|---|---|---|
| standard, built for this comparison (`$TMPDIR/wcf-native-std-d1/…`) | 41,340,696 B | `5c175409…b2bc68f1` | 12,353,536 / 13,910,016 | 29,435 / 30,003 | 464 |
| **shim, tested** (`third_party/wcf-native-shim/…`) | 41,341,080 B (**+384 B**) | `8ad763b1…4644ddb9` | identical | 29,436 / 30,004 — the adapter only | 464 |
| `third_party/wcf-native/…` — the `test:native` default, built earlier with another toolchain; **not comparable** | 41,242,056 B | `bb9266dc…db7cc9f7` | 12,304,384 / 13,856,768 | 29,435 / 30,003 | 464 |

Wall time: 5 s standard, 5 s `--with-shim` (whole seconds). `wcf_sign.o`: 13,424 B arm64, 13,504 B x86_64, with debug info. The first version of this table took the shim size from a different build than the hashed, tested library and named the wrong standard library (REVIEW B finding 8); the table above replaces it.

The object's undefined references are `TWAnySignerSign`, `TWCoinTypeBlockchain`, `TWDataBytes`, `TWDataCreateWithSize`, `TWDataDelete`, `TWDataSize`, `TWPrivateKeyData`, `memcpy` and the stack protector — every `TW*` one is already on the `-u` list, so the adapter changes nothing about which archive members are pulled. In the linked library the adapter's calls to upstream are direct branches (`llvm-objdump --disassemble-symbols=_wcf_sign_ethereum`: `bl _TWAnySignerSign`, no symbol stub). Two `--with-shim` builds of the same inputs in T1.13 produced different bytes; scratch paths reach the output. Not investigated: it bears on T4.4, not on this decision.

### 5.2 Android — analysis, **not built, pending D1a**

DECISION-9 already fixes Android to Option B: built from upstream's git tree at the pinned commit, with `wcf_build_info.c` compiled in through upstream's own `file(GLOB_RECURSE … src/*.c …)` — one generated file in `src/` that `#include`s our reviewed source, no build file patched (`tools/native_build/build_android.sh`). The adapter can enter **the same way**: a second generated file including `wcf_sign.c`; upstream's include path already resolves `<TrustWalletCore/…>`. Under this "relink-in" route neither packaging option changes at all — the `.so` per ABI just exports one more symbol.

| | Relink into `libTrustWalletCore.so` | Second shared library `libwcf_sign.so` |
|---|---|---|
| **Option 1 (build hooks)** | Hook unchanged: one code asset per ABI | Either our CI builds `libwcf_sign.so` per ABI (4 NDK `clang` invocations, linked against the prebuilt `.so` with `DT_NEEDED libTrustWalletCore.so`) and the hook emits **two** code assets per ABI; or the hook compiles `wcf_sign.c` at the consumer's build with `native_toolchain_c` — then part of the key path is built by the consumer's toolchain, outside our artifact set and its records |
| **Option 2 (Gradle/AAR)** | AAR unchanged | A prebuilt `libwcf_sign.so` in `jniLibs/<abi>/`, or `externalNativeBuild` (CMake) in the plugin compiling it against an `IMPORTED` prebuilt — a CMake dependency in every consumer build |
| **Both** | — | SONAME/`DT_NEEDED` must resolve from the app's lib dir; the Dart side opens two libraries and the same-image check becomes a "linked-against" check; `-Wl,-z,max-page-size=16384` (NDK r27+ default) and `check_alignment.sh` on the second `.so`; `-fvisibility=hidden` + `WCF_SIGN_EXPORT` and `check_exports.sh --require-symbol` on it |

Symbol visibility: upstream issue #4638 (TW symbols hidden in an Android build) is the reason `WCF_SIGN_EXPORT` exists; the export gate is what proves it worked. 16 KB alignment is unaffected by relink-in (same `.so`, same link flags). The Android loader opens `libTrustWalletCore.so` by name (`NamedLibrary`), so the same-image check of §1.3 compares two lookups in that one handle.

### 5.3 iOS — analysis, **not built, pending D1a**

The Apple job is DECISION-9 Option A′: relink of `WalletCoreCommon.xcframework`'s static archives per slice. `build_apple.sh`'s per-arch compile and link are already slice-generic; `--with-shim` refuses `ios-arm64` and `ios-arm64_x86_64-simulator` only because this task is host-scoped. Lifting that guard is the whole script change for relink-in.

| | Relink into the dynamic library | Second framework |
|---|---|---|
| **Option 1 (build hooks)** | Unchanged: one `DynamicLoadingBundled` code asset per slice | Two code assets per slice, the second linking `@rpath/libTrustWalletCore.dylib`; two dylibs to sign and embed |
| **Option 2 (podspec/SPM)** | The xcframework we assemble (T1.9) is unchanged in shape | A second xcframework with its own slices and signing; or `wcf_sign.c` as pod/SPM C sources compiled into the plugin against the vendored framework — cheap to write, but compiled by the consumer's Xcode, outside our records |
| **Both** | Privacy manifest unaffected: the adapter uses no required-reason API, no network, no storage; it calls seven upstream functions and `memcpy` | Same |

**Which image the adapter binds to on iOS.** The native loader's iOS candidates are `ProcessLibrary()` first, then the framework by path (`packages/wallet_core_flutter_native/lib/src/library_location.dart`, `NativePlatform.ios`). When the process lookup succeeds, `Init` verifies the identity symbol, and `AdapterSigningCore` looks up `wcf_sign_ethereum` and compares `TWDataDelete`, all through `DynamicLibrary.process()` — the whole process's namespace. The same-image comparison then compares a lookup with itself and cannot fail, and the adapter binds to the first loaded image that exports the name, which the identity check does not tie to the verified library. With relink-in there is one such image in a normal app; a second framework (right column), or anything else in the app exporting the same names, would make the binding ambiguous. A shipped B on iOS would need either a framework-path load (no `process()` fallback) for the adapter's library, or an identity check that reads the identity symbol of the image that actually defines `wcf_sign_ethereum` (`dladdr` on the looked-up address) — not built, and not needed for the host prototype.

## 6. The artifact pipeline, and what it does to provenance

What `build-native.yml` would have to change if B shipped:

- **Apple job:** `--with-shim` on every slice (guard lifted), `--require-symbol wcf_sign_ethereum` in the export gate per slice — or the adapter made unconditional.
- **Android job:** the second generated `src/` file; `--require-symbol` in the export gate per ABI.
- **Identity:** a shim build is now identified as artifact set `as_<tag>-shim_<nnn>` (`build_apple.sh` refuses any other id with `--with-shim`), so `verifyIdentity` refuses a shim library wherever the standard set is expected — `adapter_session_shim_test.dart` shows `ManifestMismatchError(artifactSetMismatch)` for exactly that. A shipped B would make the adapter-carrying set the expected one.
- **Records and manifest:** `--with-shim` writes no record, because the record's `provenance` admits two values (`built_from_source`, `relinked_from_upstream_release_asset`; `emit_artifact_record.sh`, `tools/manifest/lib/validator.dart`) and neither is true of a shim library. A shipped B needs a schema change, and the source hash of the adapter in the record.
- **Runtime:** `Init` would add `wcf_sign_ethereum` to `requireSymbols`, so a standard artifact is rejected rather than failing later.

**Provenance.** DECISION-9's Apple artifact is "upstream's object code from the release asset, relinked, plus one identity object of ours" — and the identity object handles no key. With B it is **upstream's object code relinked with two objects of ours, one of which receives every private key the SDK signs with and writes it into upstream's signing input.** The library is no longer upstream's bytes plus a label; a person checking the artifact has to review our C on the key path, and the claim "the key-handling code in this library is upstream's" stops being true on both platforms. On Android, where the library is built from source anyway, B adds one more of our translation units to a build that already contains one.

## 7. Review scope

Line numbers in this tree, `packages/wallet_core_flutter/lib/src/`:

| | Approach A | Approach B |
|---|---|---|
| Dart, key path | `worker/handler.dart` 310–472 (`_sign`, `_resolveKeys`); `engine/hd_wallet.dart` 296–353 (`withDerivedKey`); `signing/signing_core.dart` 78–355 (`SyncSigningCore`, `keyedInputParts`, `lengthDelimitedHeader`); `engine/secret_buffers.dart` 100–141 (`secretDataFromParts`); `signing/key_field_check.dart`; `families/` (encoder, parser, reviewed list); `engine/handles.dart` 59–86; `errors/boundary.dart` 21–61 | The same handler, `withDerivedKey`, key-field check, families, handles and boundary; `signing/adapter/adapter_signing_core.dart` (all, 232) **instead of** `SyncSigningCore` and `secretDataFromParts` |
| C | none | `wcf_sign.c` + `wcf_sign.h` (263 lines, ~105 of statements): the precondition, bounds, every exit path, the varint writer, the layout, the volatile overwrite, the blockchain check |
| Build | none on the key path | the `--with-shim` sections of `build_apple.sh`; for mobile, the generated-file inclusion on Android and the slice changes on Apple |
| Cross-language | — | the hand-written FFI signature against the C prototype (no generator compares them; the key's pointer type now does catch swapped arguments); the `#define` ↔ Dart mirror ↔ `key_fields.json` test; the shared layout probes |
| Skills | Dart and `dart:ffi` | Dart, `dart:ffi`, and C memory safety |

About the same number of lines; B trades A's Dart-side injection (`_injectAndSign`, `secretDataFromParts`) for ~105 lines of C and a second language on the key path.

## 8. Generalizing

`key_fields.json` at the pinned commit (see `DECISION-1-approach-a.md` §5): Ethereum `private_key = 9`; Bitcoin `private_key = 6` **repeated**; BitcoinV2 `private_keys = 1` repeated, nested in `signing_v2 = 21`; Solana `private_key = 1`, `fee_payer_private_key = 17`, and **nested** `create_nonce_account = 13 { nonce_account_private_key = 3 }`.

- **Bitcoin's repeated field.** One adapter call with N handles: prepend N `private_key = 6` fields, one per distinct key; order is irrelevant (upstream matches keys to inputs by script). The C contract becomes `(keyless, struct TWPrivateKey *const *keys, size_t n, coin)`. Not measured (needs T2.5's UTXO vector).
- **Solana's three fields.** The two top-level ones are two prepended fields. The nested one cannot be added as a second occurrence of `create_nonce_account` at all: `DECISION-1-approach-a.md` §5 measured that appending only the nested key signs a **different transaction with `error = 0`**, and that prepending it (alone or with the whole sub-message) loses the key and fails with upstream's error 15 — upstream's Rust parser replaces a repeated sub-message, last one wins, where Dart merges it. The adapter would have to **splice**: find the key-less `create_nonce_account` occurrence, drop it, and emit one occurrence carrying both its key-less fields and the key — a top-level wire-format splitter in C, the walk §3 describes, now on the success path.
- **One adapter per family** (`wcf_sign_ethereum`, `wcf_sign_solana(keyless, primary, fee_payer, nonce_account, coin)`, `wcf_sign_bitcoin(keyless, keys, n, coin)`): straight-line C per family, a `#define` per field tested against `key_fields.json` as `field_number_test.dart` does for Ethereum, and a native rebuild and artifact release for every new family.
- **A generic `wcf_sign(keyless, const struct wcf_key_field *fields, size_t n_fields, struct TWPrivateKey *const *keys, coin)`**, each field a path of field numbers: one C function, no rebuild per family — but the field numbers then come over FFI from Dart, so the adapter puts the key where Dart tells it to, and the argument for B (the key's placement is decided outside Dart) weakens. Keeping it requires a compiled-in allowlist of (blockchain, path) pairs **generated from `key_fields.json` at build time** into a header, so the numbers are tied to the generated inventory by generation, with a test like `field_number_test.dart` over the generated header.

Either way the nested case needs the splice; A needs the same logic in Dart.

## 9. Residual risk

**Common to both — unchanged by the choice:**

- **Upstream's signing-time copy, confirmed unwiped.** Ethereum's `Entry` is a `Rust::RustCoinEntry` (`src/Ethereum/Entry.h:13`); its `sign` copies the **whole keyed input** into a Rust `TWData` with `tw_data_create_with_bytes` (`src/rust/RustCoinEntry.cpp:98–103`). That `TWData` is a `Vec<u8>` filled by `to_vec()` (`rust/tw_memory/src/ffi/tw_data.rs:14`, `:24`), and `tw_data_delete` frees it by dropping the box (`:75–78`); `TWData` has no `Drop` implementation, and no file in `rust/tw_memory` uses `memzero` or a Rust memory-wiping crate. So on every signing operation, under A and B alike, a copy of the key-carrying input is freed without being overwritten — read from the source at the pinned commit (REVIEW B finding 9). What the Rust signer copies beyond that (its protobuf parse, its key value) was not traced.
- Copies upstream makes while deriving (trezor-crypto's HD node); the seed inside an open `TWHDWallet`; whatever `memcpy` leaves in registers and on the stack; a process killed mid-operation (#1–#4 stay as they are); swap and core dumps; the caller's own `String`s (PRD §11.3). Neither approach is an isolation boundary: same process, same address space.

**A only:** a Dart view over key bytes on the key path, and one Dart-allocated buffer whose overwrite relies on the VM not eliding stores to native memory.

**B only:** our C on the key path — a memory-safety bug there sits next to the key; ABI coupling to upstream's headers at each tag (struct `TWPrivateKey`, enum values), caught only by rebuilding; reliance on `TWDataBytes` returning a writable pointer into the `TWData` (documented API, `uint8_t *`); a hand-written FFI signature no generator checks (pointer types now catch swapped arguments, not a changed C prototype); on iOS, a binding the identity check does not cover (§5.3); upstream allocation failures inside `TWDataCreateWithSize`/`TWPrivateKeyData` throw C++ exceptions through a C frame (terminate) — the same as under A, where they throw through Dart's FFI frame; an artifact that is no longer upstream's code plus a label (§6).

**Imported keys (T3.4), both approaches.** Under B an imported key must first become a `TWPrivateKey` via `TWPrivateKeyCreateWithData` (`src/interface/TWPrivateKey.cpp:32–42`), one Dart-side copy into native memory at import. Upstream copies the bytes into a `Data` that is *moved* into the key when it is accepted — wiped with the key at delete — but is **freed without being overwritten when upstream rejects the key** (`TWDataCopyBytes` failing, or `PrivateKey::isValid` false). The reviewer's note that it "leaves an unwiped copy" holds for that reject path; on the accept path the source shows a move, not a copy.

## 10. Test evidence

`test/signing/adapter/`:

- `field_number_test.dart` (3, pure): the `#define` parsed from `wcf_sign.h` = `key_fields.json`'s `TW.Ethereum.Proto.SigningInput.private_key` = the Dart mirror = the EVM family's injection field.
- `adapter_core_shim_test.dart` (14, tags `native` + `shim`): `ethereum-sign-eip1559-1` byte for byte through the adapter; equal to Approach A for the same key and input; a planted key field, a coin outside the family, and — new — **a truncated key-less input never reach the adapter**; the core's own guards — new — a family whose injection field is not field 9 (`StateError`), a family whose signing input is not Ethereum's (`UnsupportedOperationError('signing-adapter')`), and `bindAdapter` over the shim library with a context over the standard one (`StateError`); an injected `nullptr` → `SigningError(malformedOutputCode)`; the real adapter returns NULL — no crash — for a NULL key, a NULL input, Bitcoin and Solana; an empty key-less input comes back as upstream's own typed error; `LeakTracker` zero live and zero finalized-without-dispose after every test.
- `adapter_session_shim_test.dart` (5, `native` + `shim`): the public flow with `AdapterSigningCore.new` equals a second session's Approach A result — now over the **standard** library when present — for the same request; 50 signs leave only the wallet live after each; — new — the shim library loaded where the standard identity is expected is `ManifestMismatchError(artifactSetMismatch)`, `as_4.8.0_000` vs `as_4.8.0-shim_000`; and — new, the adapter path's own soft failure, since `soft_native_failure_native_test.dart`'s Dart-side `TWPrivateKeyData` injection cannot reach a call made in C — an adapter returning NULL inside a live session is that operation's `SigningError`, the key is released, and the next sign succeeds; and a null from `TWDataCreateWithBytes` for the key-less input, injected through `EngineRequestHandler(bindings:)`, is likewise that operation's `SigningError` with the session still `ready`, as under Approach A. Every shim test now loads the shim library with `shimIdentity` explicitly.
- `keyed_layout_shim_test.dart` (4, `native` + `shim`) and `../keyed_layout_native_test.dart` (4, `native`): **the same four probes** (`keyed_layout_probes.dart`) against each side's one layout-deciding place — `wcf_sign_ethereum` and `keyedInputParts` — with the key-less check bypassed: a well-formed input signs the vector; a key planted *after* the key-less bytes wins (so the injected key is not appended); a key planted *before* them wins too (so the injected key is the first field); and REVIEW B finding 1's truncated input yields no run of the key in the output and no signed transaction. The C side is observed through upstream's parse of what the production shim binary builds — not a C harness, interposition, or a test-only build: the adapter's calls to upstream are direct branches inside the dylib (§5.1), so they cannot be interposed, and a test hook would test a different binary from the one evaluated.
- `adapter_absent_native_test.dart` (2, `native`): over the standard library the core's constructor and `Init` with the adapter factory both fail with `NativeLoadError`.

Approach A, in this tree: `signing_core_native_test.dart` (16) adds, through the production `sign` (handle) entry point, the vector and three rejections — planted key field, coin outside the family, truncated input — each with no native object created by the core, so `TWPrivateKeyData` is never reached (REVIEW B finding 7). Ported from T1.12 delta 1 with this tree's seam: `soft_native_failure_native_test.dart` (3; its `TWPrivateKeyData` null now lands in `SyncSigningCore.sign`), `key_identity_native_test.dart` (2; `withDerivedKey`'s key checked through the handle, the reference signature through `signWithKeyBytes`), `session_test.dart`, `protocol_test.dart`, `signer_session_test.dart`, `public_surface_test.dart`.

**How the shim tests are run so that they cannot skip silently.** `melos run test` and `melos run test:native` let them skip when the shim library is absent. The run that exists to exercise them is

```
bash tools/native_build/run_shim_tests.sh
```

It sets `WCF_NATIVE_SHIM_REQUIRED=1` — so an absent library is a load failure in every shim file, not a skip — and then fails unless the summary shows at least one passing test and no skipped one. Measured: with `WCF_NATIVE_SHIM_LIB=/nonexistent` the script exits 1, and `flutter test --tags shim` under `WCF_NATIVE_SHIM_REQUIRED=1` fails to load all three shim files. There is no melos script for it (the root `pubspec.yaml` is outside this evaluation's paths) and no CI step (`.github/` likewise); the orchestrator invokes the script directly after building the shim library.

Gate tails, 2026-10-02 (delta 1):

```
$ melos run analyze
[wallet_core_flutter]: No issues found!   (and every other package)
     └> SUCCESS

$ melos run format:check
Formatted 399 files (0 changed) in 0.95 seconds.

$ melos run test
[wallet_core_flutter]: 00:04 +300: All tests passed!
[wallet_core_flutter_bindings]: 00:00 +64: All tests passed!
[wallet_core_flutter_native]: 00:01 +190: All tests passed!

$ melos run test:native                                   (shim library present)
00:00 +42: All tests passed!        (wallet_core_flutter_bindings, --tags native)
00:03 +106: All tests passed!       (wallet_core_flutter, --tags native)

$ WCF_NATIVE_SHIM_LIB=/nonexistent melos run test:native  (shim library absent)
00:00 +42: All tests passed!
00:04 +84 ~22: All tests passed!    (the 22 shim tests skip)

$ melos run inventory:check
functions: {in_headers: 466, in_generated: 466, missing: 0}
packages/wallet_core_flutter_bindings/lib/src/generated/inventory.json: up to date

$ tools/native_build/build_apple.sh --tarball ~/.cache/wcf-upstream/4.8.0/TrustWalletCore-4.8.0.tar.xz \
    --commit d692ac27749d0c615e17c751b70ab4f0aa75c59b --slices macos-arm64_x86_64 \
    --out-dir "$TMPDIR/wcf-native-shim" --expect-symbol-count 464 --with-shim
arch arm64: expected 464, missing 0, unexpected 0
arch arm64: required symbol _wcf_sign_ethereum exported: yes
export-visibility gate PASSED
with-shim: sha256 8ad763b12e940eaf09355a74ad9ecc4a910256fe0d400d56d614e9bf4644ddb9 (evaluation artifact; no record, no uploadable)

$ bash tools/native_build/run_shim_tests.sh               (three runs)
run 1: 00:03 +22: All tests passed!   test:shim: passed, none skipped
run 2: 00:02 +22: All tests passed!   test:shim: passed, none skipped
run 3: 00:03 +22: All tests passed!   test:shim: passed, none skipped

$ tools/native_build/check_exports.sh --binary third_party/wcf-native-shim/... --require-symbol wcf_sign_ethereum
arch x86_64: required symbol _wcf_sign_ethereum exported: yes
arch arm64: required symbol _wcf_sign_ethereum exported: yes
export-visibility gate PASSED
```

`--with-shim` guard probes, each refused with nothing created — the probe compares a listing of its scratch directory before and after every run: `--out-dir $TMPDIR/shim/../wcf-native` (`.`/`..` components); `$TMPDIR/shim/wcf-native` and `$TMPDIR/shim/a/b/wcf-native` (own name lacks "shim"; the out-dir check runs before `mkdir -p`, on the existing directory's resolved name or, for a new one, its last component); a symlink named `shim-link` to a non-shim directory (resolved name); a dangling symlink named `dangling-shim`; an existing file; `--artifact-set-id as_4.8.0_000` (not a shim id). An out-dir named `new-shim` passes the guard.

## 11. Open items for D1

1. **Native well-formedness/absence walk** (§3): ~50–70 lines of C plus fuzzing for defence in depth against a caller that skips the decode — or keep the check in Dart only. Prepending already removes the case that exposes the key.
2. **Per-family adapters vs a generic adapter with a generated allowlist** (§8).
3. **Relink-in vs second library** on Android and iOS (§5.2, §5.3) — depends on D1a; relink-in costs nothing measurable on the host and changes neither packaging option.
4. **Provenance and manifest** if B ships (§6): a third `provenance` value, the adapter's source hash in the record, `requireSymbols` at `Init`, the adapter-carrying artifact set as the expected identity.
5. **Binding through `ffigen`** if B ships: a second config over `wcf_sign.h` so `gen:check` catches signature drift, and `inventory:check` taught about non-upstream symbols.
6. **`DECISION-1-approach-a.md` on this branch** was corrected in delta 1 for this tree's seam (its file map, copy-table lifetimes, order line, review-scope lines, and the 32-byte test claim); its count is now 4 native objects (#1–#4), matching §2.1. The T1.12 tree's copy describes the seam before T1.13 and is correct there.
7. **iOS binding** (§5.3): a framework-path load for the adapter's library, or an identity check on the image that defines `wcf_sign_ethereum`, if B ships on iOS.
8. **Upstream's unwiped Rust copy** of the keyed input (§9) affects A and B equally; whether to raise it upstream is outside DECISION-1.
9. **A then B?** The seam now carries a handle, so both cores fit behind it and the handler picks one by factory; switching later is a packaging and provenance change (§6), not an SDK API change.
10. **Byte stability of `build_apple.sh` output** (§5.1) — for T4.4, not for D1.
