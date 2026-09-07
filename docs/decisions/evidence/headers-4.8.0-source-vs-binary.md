# Headers at 4.8.0: git tree vs. binary distribution

Measured by T1.1 on 2026-09-07 against `trustwallet/wallet-core` tag `4.8.0`,
commit `d692ac27749d0c615e17c751b70ab4f0aa75c59b`.

**This file measures and reports. It changes no decision.** In particular it
does not change ffigen's header source (T1.3) or the link list (T1.2); it gives
those tasks the numbers they need to choose.

## 1. The three header sets

| Set | Source | Count |
|---|---|---|
| **Git tree** | `include/TrustWalletCore/*.h` in the source archive for tag 4.8.0, extracted by `melos run upstream:fetch` into `third_party/wallet-core/` | **67** |
| **Binary distribution** | `./include/TrustWalletCore/*.h` inside release asset `TrustWalletCore-4.8.0.tar.xz` | **143** |
| **xcframework slice** | `WalletCore.xcframework/<slice>/WalletCore.framework/Headers/*.h`, identical in both slices | **85** |

Provenance of each measurement:

- Git tree: `ls` of the tree this task extracted. That tree is the same bytes
  the orchestrator fetched independently on 2026-09-07 — `registry.json` and
  `TWCoinType.h` in `docs/decisions/evidence/prefetch-2026-09-07/upstream-src/`
  are byte-identical (SHA-256 `efc954c9…` and `53523472…` respectively) to the
  extracted files.
- Binary distribution: `tar -tJf` listing of the local copy of the release
  asset at `~/.cache/wcf-upstream/4.8.0/TrustWalletCore-4.8.0.tar.xz`
  (SHA-256 `30b0532d9f143b6409aa405f3ba124625fb01e70f13d8e52b3904334c617ff60`,
  53 949 676 bytes, recorded in `prefetch-2026-09-07/SUMMARY.md`).
  **The listing checked into `prefetch-2026-09-07/` was not sufficient on its
  own**: `source-tarball-4.8.0-toplevel.txt` records only the top two levels
  (`./License`, `./Sources`, `./include`, `./WalletCoreCommon.xcframework`) and
  names no individual header. The per-file listing was therefore taken from the
  cached asset itself. It confirms `SUMMARY.md`'s count of 143.
- xcframework: `prefetch-2026-09-07/xcframework-4.8.0-listing.txt`, the `unzip
  -l` output T0.5 recorded. 85 `.h` entries per slice; the two slices carry the
  same names.

## 2. Set difference, git tree vs. binary distribution

**The 67 git-tree headers are a strict subset of the 143.** Nothing is present
in the git tree and absent from the binary distribution:

```
headers(git tree) \ headers(TrustWalletCore-4.8.0.tar.xz) = ∅   (0 files)
headers(TrustWalletCore-4.8.0.tar.xz) \ headers(git tree) = 76 files
```

### 2.1 The 76, split by kind

**60 `TW*Proto.h`** — one per `.proto` file in `src/proto/`:

```
TWAeternityProto.h        TWAionProto.h              TWAlgorandProto.h
TWAptosProto.h            TWBabylonStakingProto.h    TWBarzProto.h
TWBinanceProto.h          TWBitcoinProto.h           TWBitcoinV2Proto.h
TWBizPasskeySessionProto.h TWBizProto.h              TWCardanoProto.h
TWCommonProto.h           TWCosmosProto.h            TWDecredProto.h
TWDecredV2Proto.h         TWEOSProto.h               TWEthereumAbiProto.h
TWEthereumProto.h         TWEthereumRlpProto.h       TWEverscaleProto.h
TWFIOProto.h              TWFilecoinProto.h          TWGreenfieldProto.h
TWHarmonyProto.h          TWHederaProto.h            TWIOSTProto.h
TWIconProto.h             TWInternetComputerProto.h  TWIoTeXProto.h
TWLiquidStakingProto.h    TWMultiversXProto.h        TWNEARProto.h
TWNEOProto.h              TWNULSProto.h              TWNanoProto.h
TWNebulasProto.h          TWNervosProto.h            TWNimiqProto.h
TWOasisProto.h            TWOntologyProto.h          TWPactusProto.h
TWPolkadotProto.h         TWPolymeshProto.h          TWRippleProto.h
TWSolanaProto.h           TWStellarProto.h           TWSuiProto.h
TWTHORChainSwapProto.h    TWTezosProto.h             TWTheOpenNetworkProto.h
TWThetaProto.h            TWTransactionCompilerProto.h TWTronProto.h
TWUtxoProto.h             TWVeChainProto.h           TWWalletConnectProto.h
TWWavesProto.h            TWZcashProto.h             TWZilliqaProto.h
```

**16 non-proto headers:**

```
TWBarz.h                TWBiz.h                  TWBizPasskeySession.h
TWCryptoBoxPublicKey.h  TWCryptoBoxSecretKey.h   TWEip7702.h
TWEthereum.h            TWEthereumChainID.h      TWHRP.h
TWMessageSigner.h       TWSolanaTransaction.h    TWTONAddressConverter.h
TWTONMessageSigner.h    TWTONWallet.h            TWWalletConnectRequest.h
TWWebAuthnSolidity.h
```

## 3. Where the 76 come from — direct evidence from the tree

All four items below are quotations from the extracted tree, not inference.

### 3.1 Upstream's own `.gitignore` lists exactly this set

`.gitignore` lines 40–59 of the pinned tree:

```
include/TrustWalletCore/TWHRP.h
include/TrustWalletCore/TW*Proto.h
include/TrustWalletCore/TWEthereumChainID.h

# Generated
include/TrustWalletCore/TWTONAddressConverter.h
include/TrustWalletCore/TWFFITest.h
include/TrustWalletCore/TWTONWallet.h
include/TrustWalletCore/TWTONMessageSigner.h
include/TrustWalletCore/TWMessageSigner.h
include/TrustWalletCore/TWWalletConnectRequest.h
include/TrustWalletCore/TWSolanaTransaction.h
include/TrustWalletCore/TWCryptoBoxPublicKey.h
include/TrustWalletCore/TWCryptoBoxSecretKey.h
include/TrustWalletCore/TWEthereum.h
include/TrustWalletCore/TWBarz.h
include/TrustWalletCore/TWBiz.h
include/TrustWalletCore/TWBizPasskeySession.h
include/TrustWalletCore/TWEip7702.h
include/TrustWalletCore/TWWebAuthnSolidity.h
```

That is `TW*Proto.h` plus 16 named files, of which 15 are listed explicitly and
`TWHRP.h`/`TWEthereumChainID.h` sit above the `# Generated` comment. One of the
explicitly ignored files, `TWFFITest.h`, is not shipped in the binary
distribution either — it is a test fixture. Removing it leaves exactly the 16
non-proto headers of §2.1.

**The set difference is not a mystery: it is upstream's generated-header set,
by upstream's own declaration.** The git tree does not carry them because they
are build outputs; the binary distribution carries them because it is packaged
after the build.

### 3.2 The `TW*Proto.h` headers come from `protoc`

`tools/generate-files`:

```
# Generate Proto interface file
"$PROTOC" -I=$PREFIX/include -I=src/proto --plugin=$PREFIX/bin/protoc-gen-c-typedef --c-typedef_out include/TrustWalletCore src/proto/*.proto
```

The mapping is 1:1 and exact. `src/proto/` in the pinned tree holds 60 `.proto`
files; applying `X.proto → TWXProto.h` to those 60 names reproduces the 60
missing proto headers **byte-identically as a sorted name list** (both lists
hash to `8150b197…`).

The plugin is `protoc-gen-c-typedef`, built by upstream's own build (it is not
a stock protoc plugin), so these headers are C typedef shims over the protobuf
messages, not the message definitions themselves.

### 3.3 `TWHRP.h` and `TWEthereumChainID.h` come from `registry.json`

`codegen/bin/coins` (Ruby) reads `registry.json` and renders, among others:

```ruby
{'template' => 'hrp.h.erb',              'folder' => 'include/TrustWalletCore', 'file' => 'TWHRP.h'},
{'template' => 'TWEthereumChainID.h.erb','folder' => 'include/TrustWalletCore', 'file' => 'TWEthereumChainID.h'}
```

Both templates are present in the pinned tree at
`codegen/lib/templates/hrp.h.erb` and
`codegen/lib/templates/TWEthereumChainID.h.erb`.

### 3.4 The remaining 14 come from `codegen-v2` over the Rust crates

`tools/rust-bindgen` ends with:

```
echo "Generating C++ files..."
pushd codegen-v2 && cargo run -- cpp && popd
```

and `codegen-v2/src/codegen/cpp/code_gen.rs` line 11:

```rust
static HEADER_OUT_DIR: &str = "../include/TrustWalletCore/";
```

**[INFERENCE]** The 14 remaining headers (`TWBarz.h`, `TWBiz.h`,
`TWBizPasskeySession.h`, `TWCryptoBoxPublicKey.h`, `TWCryptoBoxSecretKey.h`,
`TWEip7702.h`, `TWEthereum.h`, `TWMessageSigner.h`, `TWSolanaTransaction.h`,
`TWTONAddressConverter.h`, `TWTONMessageSigner.h`, `TWTONWallet.h`,
`TWWalletConnectRequest.h`, `TWWebAuthnSolidity.h`) are the output of that
`codegen-v2 cpp` pass over the Rust FFI surface. The inference is that these
particular files are that pass's output: `code_gen.rs` writes into
`include/TrustWalletCore/`, upstream's `.gitignore` marks exactly these files
generated, and every one of them names a Rust-implemented subsystem
(`rust/frameworks/tw_ton_sdk`, `rust/tw_evm`, the Barz/Biz account-abstraction
crates). What is *not* inferred is the output directory and the ignore list —
both are quoted above.

**[INFERENCE, weaker]** `codegen-v2/manifest/` holds 106 `.yaml` files, of
which only 48 of the 76 generated headers have a counterpart. That directory is
therefore **not** a reliable index of the generated set at this tag — 28 of the
76 have no manifest entry, including all of `TWBiz*`, `TWCryptoBox*Key`,
`TWEip7702`, `TWMessageSigner`, `TWSolanaTransaction`, `TWTON*` and 16 proto
headers. Do not use `codegen-v2/manifest/` as the header inventory.

## 4. The xcframework's 85, for completeness

```
85 = 67 (git tree) + 16 (non-proto generated, §2.1) + WalletCore.h + WalletCore-Swift.h
```

Every git-tree header is present in the xcframework slice (difference is
empty). The xcframework ships **no** `TW*Proto.h` at all — the Swift package
reaches protobuf through `WalletCoreSwiftProtobuf` instead. `WalletCore.h` and
`WalletCore-Swift.h` are the two headers present in the xcframework and absent
from `TrustWalletCore-4.8.0.tar.xz`; they are the framework umbrella header and
the Swift-generated interface, artefacts of the framework packaging.

So the three sets nest cleanly:

```
git tree (67)  ⊂  xcframework minus umbrella headers (83)  ⊂  binary tar.xz (143)
                                                              ∪ {WalletCore.h, WalletCore-Swift.h}
```

## 5. Two further measurements, for T1.3 and T1.2

### 5.1 The 67 checked-in headers are self-contained

Every `#include` appearing anywhere in the 67 headers resolves either to
another of the 67 or to a C standard header. The complete set of unresolved
includes is:

```
stdbool.h   stddef.h   stdint.h   stdlib.h
```

**No checked-in header includes a generated one.** A parser pointed at the git
tree's `include/TrustWalletCore/` will therefore parse cleanly without any
build step; it will simply not see the 76.

### 5.2 Function-like declarations in the 67

Counting line-initial `TW_EXPORT_*` macros across the 67 headers:

| Macro | Count |
|---|---|
| `TW_EXPORT_STATIC_METHOD` | 187 |
| `TW_EXPORT_METHOD` | 127 |
| `TW_EXPORT_PROPERTY` | 72 |
| **function-like total** | **386** |
| `TW_EXPORT_STRUCT` | 28 |
| `TW_EXPORT_CLASS` | 18 |
| `TW_EXPORT_ENUM` | 17 |

(`TW_EXPORT_STATIC_PROPERTY` is defined in `TWBase.h` and used nowhere in the
67.)

## 6. What this implies — for T1.3 and T1.2 to decide, not this task

- **T1.3 (ffigen).** Running ffigen over the git tree's 67 headers yields a
  binding surface that omits all 60 protobuf typedef headers and the 16
  Rust/registry-generated headers — including `TWMessageSigner`,
  `TWSolanaTransaction`, `TWEthereum`, `TWTONWallet`, `TWCryptoBox*Key`, and
  the `TWHRP`/`TWEthereumChainID` enums. §5.1 says the 67 parse standalone, so
  this is a *coverage* question, not a *build* question. The options T1.3 has,
  stated neutrally: (a) generate from the 67 and document the gap; (b) also
  consume the 143 headers from `TrustWalletCore-4.8.0.tar.xz`, which are the
  same generated files upstream ships and whose sha is pinnable; (c) run
  upstream's generation steps (`protoc` + `codegen/bin/coins` + `codegen-v2`)
  to materialise them from the pinned tree, which pulls protoc, Ruby, and a
  Rust toolchain into our generation path. This task takes no position.
  Whichever is chosen, `schemas.headers_sha` as written by T1.1 covers the 67
  git-tree headers only, and its meaning would have to be restated if the
  header source changes.
- **T1.2 (464-symbol link list).** The 386 function-like declarations of §5.2
  come from the 67 headers alone. If the link list is 464 symbols, the balance
  is in the 76 generated headers (and in symbols not declared through the
  `TW_EXPORT_*` macros). A link list derived from the git tree's headers alone
  will be short of a list derived from the shipped library. DECISION-9 Option C
  has T1.2 consuming both this source tree and the binary tarball, so both
  header sets are already available to it.

## 7. Reproducing these numbers

```bash
melos run upstream:fetch -- --from <wallet-core-4.8.0.tar.gz> \
                            --commit d692ac27749d0c615e17c751b70ab4f0aa75c59b
ls third_party/wallet-core/include/TrustWalletCore/ | sort            # 67
tar -tJf TrustWalletCore-4.8.0.tar.xz \
  | grep '^\./include/TrustWalletCore/.*\.h$' | sed 's#.*/##' | sort  # 143
grep -o 'ios-arm64/WalletCore.framework/Headers/.*$' \
  docs/decisions/evidence/prefetch-2026-09-07/xcframework-4.8.0-listing.txt \
  | sed 's#.*Headers/##' | grep -v '^$' | sort                        # 85
```

`TrustWalletCore-4.8.0.tar.xz` is not in the repository; the orchestrator's
copy is at `~/.cache/wcf-upstream/4.8.0/`, sha256
`30b0532d9f143b6409aa405f3ba124625fb01e70f13d8e52b3904334c617ff60`.
