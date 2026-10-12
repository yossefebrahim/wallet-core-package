# Transaction compiler and message signing coverage probe

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

**Upstream Pin:** Tag 4.8.0, Commit `d692ac27749d0c615e17c751b70ab4f0aa75c59b`

**Library Checked:** Artifact Set `as_4.8.0_000`, Commit `d692ac27749d0c615e17c751b70ab4f0aa75c59b`, SHA-256 `bb9266dc15f6918c95f2117311f3d638841d15816bda57c61c37ef32db7cc9f7`

**Command:** `melos run probe:coverage`

## Method

Upstream publishes no boolean "supports" API for either operation, so each
answer combines static evidence from upstream's source at the pinned commit
with runtime evidence from the real host library.

### Static rules (upstream source at the pinned commit; applied per registry `blockchain`)

Compiler (`TWTransactionCompilerPreImageHashes` / `TWTransactionCompilerCompileWithSignatures`):

- `src/interface/TWTransactionCompiler.cpp:15-39` forwards to `anyCoinPreImageHashes` / `anyCoinCompileWithSignatures` (`src/Coin.cpp:339-349`), which call the C++ `coinDispatcher` (`src/Coin.cpp:138-142`, switch on the coin's blockchain) and then the entry's virtual `preImageHashes` / `compile`. Every exception is swallowed and an empty `TWData` is returned (`TWTransactionCompiler.cpp:21,36`).
- A C++ entry that does not override them inherits the empty default (`src/CoinEntry.h:68,70`) → **unsupported**. Applied to Aeternity, Everscale, Hedera, Nebulas, Nervos, Nimiq, Waves, Zilliqa (no `preImageHashes` in `src/<Chain>/Entry.h`).
- A C++ entry that overrides both (`src/<Chain>/Entry.h`, bodies use `txCompilerTemplate` / `txCompilerSingleTemplate`, `src/CoinEntry.h:109-160`) → **supported**. BitcoinCash inherits Bitcoin's (`src/BitcoinCash/Entry.h:17`), Komodo inherits Zcash's (`src/Komodo/Entry.h:13`).
- `Rust::RustCoinEntry` overrides both and forwards to Rust (`src/Rust/RustCoinEntry.cpp:105-126`); Rust's `CoinEntry` trait requires `preimage_hashes` and `compile` (`rust/tw_coin_entry/src/coin_entry.rs:100,107`) → **supported** for Aptos, Binance, Cosmos, Ethereum, Greenfield, Kusama, NativeEvmos, NativeInjective, Pactus, Polkadot, Polymesh, Ripple, Ronin, Solana, Sui, TheOpenNetwork, Thorchain.
- Exception: InternetComputer's Rust entry implements both as an explicit `Error_not_supported` stub (`rust/chains/tw_internet_computer/src/entry.rs:82-103`) → **unsupported**.

Generic message signer (`TWMessageSignerSign` / `TWMessageSignerPreImageHashes` / `TWMessageSignerVerify`):

- Defined only in Rust (`rust/tw_any_coin/src/ffi/tw_message_signer.rs:22-66`; there is no C++ `TWMessageSigner.cpp`). It dispatches through `coin_dispatcher` (`rust/tw_coin_registry/src/dispatcher.rs:98`), which returns `RegistryError::Unsupported` for blockchains with no Rust entry (`dispatcher.rs:94`), then through `CoinEntryExt::{sign_message,message_preimage_hashes,verify_message}` (`rust/tw_coin_entry/src/coin_entry_ext.rs:214-243`), which return `Error_not_supported` when the entry's `message_signer()` is `None`. The trait default is `None` (`rust/tw_coin_entry/src/coin_entry.rs:132`).
- Entries whose `message_signer()` returns `Some(..)` → **supported**: Ethereum (`rust/chains/tw_ethereum/src/entry.rs:98`), Ronin (`tw_ronin/src/entry.rs:97`), Solana (`tw_solana/src/entry.rs:92`), Sui (`tw_sui/src/entry.rs:96`). Every other registry blockchain → **unsupported** (Aptos returns an explicit `None`, `tw_aptos/src/entry.rs:100`).
- Coin-specific signers (`TWEthereumMessageSigner.h`, `TWBitcoinMessageSigner.h`, `TWTezosMessageSigner.h`, `TWTronMessageSigner.h`, `TWStarkExMessageSigner.h`, and the Rust-generated `TWTONMessageSigner`, exported by the library as `TWTONMessageSignerSignMessage`) take keys or strings, not a `TWCoinType`. The last column maps a coin to a signer only when its registry blockchain name equals the signer's family (Ethereum, Bitcoin, Tezos, Tron, TheOpenNetwork); forks and look-alikes are not inferred. StarkEx has no registry coin of its own, so no row maps to it.

### Runtime calls and classes

Each coin is probed in its own child process (`dart bin/coverage_probe.dart --lib <lib> --coin <id> --part compiler|message`, one process per coin per question) because a C++ exception or a Rust panic across the FFI boundary can abort the process. A child that dies by signal, exits non-zero, or prints no single JSON line is recorded as `crash (signal N | exit N | ...)`; one coin never aborts the table.

Compiler calls: `TWTransactionCompilerPreImageHashes` and `TWTransactionCompilerCompileWithSignatures` (no signatures, no public keys), each with an empty input and with a malformed input (`ff ff ff ff`, not a valid protobuf tag). Upstream exposes no error code on these functions; the only observable is the returned bytes:

| class | observation | reading |
|---|---|---|
| `reached` | some call returned non-empty bytes without `Error_not_supported` (24, `src/proto/Common.proto:71`) as a top-level varint | the coin's compiler module produced a serialized output (including its own input-validation error, e.g. `Error_input_parse` from `txCompilerTemplate`, `src/CoinEntry.h:112-120`) |
| `not-supported` | every non-empty return carries a top-level varint equal to 24 | the coin's compiler answers `Error_not_supported` |
| `empty` | every call returned zero bytes | upstream's empty default for an unimplemented entry, or a swallowed exception; the two are indistinguishable |
| `crash` | the child died | no runtime evidence |

Message-signing calls: `TWMessageSignerSign`, `TWMessageSignerPreImageHashes` and `TWMessageSignerVerify`, each with an empty input (a valid empty protobuf message). Upstream returns a null pointer for `Error_not_supported`, for an unsupported blockchain and for an unparsable input, and a serialized `MessageSigningOutput` (carrying its own error code) otherwise:

| class | observation |
|---|---|
| `supported` | `Sign` or `PreImageHashes` returned a non-null `TWData` |
| `unsupported` | both returned null |
| `crash` | the child died |

`Verify` returns a bare bool (`false` on every failure), so it is recorded in the child's output but never decides a class.

### Agreement

`supported` agrees with `reached` / `supported`; `unsupported` agrees with `empty` / `not-supported` / `unsupported`. Any other pairing is rendered as `conflict (static=…, runtime=…)` in the runtime column and counted under Conflict; it is not resolved here. A `crash` has no runtime evidence and is counted separately.

### Known limits

- Runtime evidence uses empty and malformed inputs only. It shows that a coin's code path exists and answers; it does not show that a valid transaction or message would compile or sign.
- For the compiler an `empty` result cannot tell an unimplemented entry from a swallowed exception.
- The static tables are hand-derived from the cited source lines; a drift in upstream (a new entry, a new override) is caught only when the runtime column disagrees.

## Totals

### Transaction compiler

- Coins: 167
- Static: 158 supported, 9 unsupported, 0 unclassified
- Runtime: 2 crash, 8 empty, 1 not-supported, 156 reached
- Static and runtime agree: 165
- Conflict: 0
- Crash (no runtime evidence): 2

### Generic message signer (`TWMessageSigner*`)

- Coins: 167
- Static: 63 supported, 104 unsupported, 0 unclassified
- Runtime: 63 supported, 104 unsupported
- Static and runtime agree: 167
- Conflict: 0
- Crash (no runtime evidence): 0

- Coins with a coin-specific message signer: 77

## Coverage Table

| coin id | TWCoinType | compile (static) | compile (runtime) | message signing (static) | message signing (runtime) | coin-specific message signer |
|---|---|---|---|---|---|---|
| 0 | TWCoinTypeBitcoin | supported | reached | unsupported | unsupported | TWBitcoinMessageSigner |
| 2 | TWCoinTypeLitecoin | supported | reached | unsupported | unsupported | TWBitcoinMessageSigner |
| 3 | TWCoinTypeDogecoin | supported | reached | unsupported | unsupported | TWBitcoinMessageSigner |
| 5 | TWCoinTypeDash | supported | reached | unsupported | unsupported | TWBitcoinMessageSigner |
| 14 | TWCoinTypeViacoin | supported | reached | unsupported | unsupported | TWBitcoinMessageSigner |
| 17 | TWCoinTypeGroestlcoin | supported | reached | unsupported | unsupported | — |
| 20 | TWCoinTypeDigiByte | supported | reached | unsupported | unsupported | TWBitcoinMessageSigner |
| 22 | TWCoinTypeMonacoin | supported | reached | unsupported | unsupported | TWBitcoinMessageSigner |
| 42 | TWCoinTypeDecred | supported | reached | unsupported | unsupported | — |
| 57 | TWCoinTypeSyscoin | supported | reached | unsupported | unsupported | TWBitcoinMessageSigner |
| 60 | TWCoinTypeEthereum | supported | reached | supported | supported | TWEthereumMessageSigner |
| 61 | TWCoinTypeEthereumClassic | supported | reached | supported | supported | TWEthereumMessageSigner |
| 74 | TWCoinTypeICON | supported | reached | unsupported | unsupported | — |
| 77 | TWCoinTypeVerge | supported | reached | unsupported | unsupported | — |
| 118 | TWCoinTypeCosmos | supported | reached | unsupported | unsupported | — |
| 119 | TWCoinTypePivx | supported | reached | unsupported | unsupported | TWBitcoinMessageSigner |
| 121 | TWCoinTypeZen | supported | reached | unsupported | unsupported | — |
| 133 | TWCoinTypeZcash | supported | reached | unsupported | unsupported | — |
| 136 | TWCoinTypeFiro | supported | reached | unsupported | unsupported | TWBitcoinMessageSigner |
| 137 | TWCoinTypeRootstock | supported | reached | supported | supported | TWEthereumMessageSigner |
| 141 | TWCoinTypeKomodo | supported | reached | unsupported | unsupported | — |
| 144 | TWCoinTypeXRP | supported | reached | unsupported | unsupported | — |
| 145 | TWCoinTypeBitcoinCash | supported | reached | unsupported | unsupported | — |
| 146 | TWCoinTypeNebl | supported | reached | unsupported | unsupported | — |
| 148 | TWCoinTypeStellar | supported | reached | unsupported | unsupported | — |
| 156 | TWCoinTypeBitcoinGold | supported | reached | unsupported | unsupported | TWBitcoinMessageSigner |
| 165 | TWCoinTypeNano | supported | reached | unsupported | unsupported | — |
| 169 | TWCoinTypeMantaPacific | supported | reached | supported | supported | TWEthereumMessageSigner |
| 175 | TWCoinTypeRavencoin | supported | reached | unsupported | unsupported | TWBitcoinMessageSigner |
| 178 | TWCoinTypePOANetwork | supported | reached | supported | supported | TWEthereumMessageSigner |
| 194 | TWCoinTypeEOS | supported | crash (signal 6 in preimage_empty) | unsupported | unsupported | — |
| 195 | TWCoinTypeTron | supported | reached | unsupported | unsupported | TWTronMessageSigner |
| 204 | TWCoinTypeOpBNB | supported | reached | supported | supported | TWEthereumMessageSigner |
| 223 | TWCoinTypeInternetComputer | unsupported | not-supported | unsupported | unsupported | — |
| 235 | TWCoinTypeFIO | supported | reached | unsupported | unsupported | — |
| 242 | TWCoinTypeNimiq | unsupported | empty | unsupported | unsupported | — |
| 283 | TWCoinTypeAlgorand | supported | reached | unsupported | unsupported | — |
| 291 | TWCoinTypeIOST | supported | reached | unsupported | unsupported | — |
| 304 | TWCoinTypeIoTeX | supported | reached | unsupported | unsupported | — |
| 309 | TWCoinTypeNervos | unsupported | empty | unsupported | unsupported | — |
| 313 | TWCoinTypeZilliqa | unsupported | empty | unsupported | unsupported | — |
| 330 | TWCoinTypeTerra | supported | reached | unsupported | unsupported | — |
| 354 | TWCoinTypePolkadot | supported | reached | unsupported | unsupported | — |
| 361 | TWCoinTypeThetaFuel | supported | reached | supported | supported | TWEthereumMessageSigner |
| 394 | TWCoinTypeCryptoOrg | supported | reached | unsupported | unsupported | — |
| 396 | TWCoinTypeEverscale | unsupported | empty | unsupported | unsupported | — |
| 397 | TWCoinTypeNEAR | supported | reached | unsupported | unsupported | — |
| 425 | TWCoinTypeAion | supported | reached | unsupported | unsupported | — |
| 434 | TWCoinTypeKusama | supported | reached | unsupported | unsupported | — |
| 457 | TWCoinTypeAeternity | unsupported | empty | unsupported | unsupported | — |
| 459 | TWCoinTypeKava | supported | reached | unsupported | unsupported | — |
| 461 | TWCoinTypeFilecoin | supported | reached | unsupported | unsupported | — |
| 474 | TWCoinTypeOasis | supported | reached | unsupported | unsupported | — |
| 483 | TWCoinTypeBluzelle | supported | reached | unsupported | unsupported | — |
| 494 | TWCoinTypeBandChain | supported | reached | unsupported | unsupported | — |
| 500 | TWCoinTypeTheta | supported | reached | unsupported | unsupported | — |
| 501 | TWCoinTypeSolana | supported | reached | supported | supported | — |
| 508 | TWCoinTypeMultiversX | supported | reached | unsupported | unsupported | — |
| 529 | TWCoinTypeSecret | supported | reached | unsupported | unsupported | — |
| 564 | TWCoinTypeAgoric | supported | reached | unsupported | unsupported | — |
| 595 | TWCoinTypePolymesh | supported | reached | unsupported | unsupported | — |
| 607 | TWCoinTypeTON | supported | reached | unsupported | unsupported | TWTONMessageSigner |
| 637 | TWCoinTypeAptos | supported | reached | unsupported | unsupported | — |
| 714 | TWCoinTypeBinance | supported | reached | unsupported | unsupported | — |
| 784 | TWCoinTypeSui | supported | reached | supported | supported | — |
| 787 | TWCoinTypeAcala | supported | reached | unsupported | unsupported | — |
| 818 | TWCoinTypeVeChain | supported | reached | unsupported | unsupported | — |
| 820 | TWCoinTypeCallisto | supported | reached | supported | supported | TWEthereumMessageSigner |
| 888 | TWCoinTypeNEO | supported | reached | unsupported | unsupported | — |
| 889 | TWCoinTypeViction | supported | reached | supported | supported | TWEthereumMessageSigner |
| 899 | TWCoinTypeECash | supported | reached | unsupported | unsupported | — |
| 931 | TWCoinTypeTHORChain | supported | reached | unsupported | unsupported | — |
| 966 | TWCoinTypePolygon | supported | reached | supported | supported | TWEthereumMessageSigner |
| 996 | TWCoinTypeOKXChain | supported | reached | supported | supported | TWEthereumMessageSigner |
| 999 | TWCoinTypeBitcoinDiamond | supported | reached | unsupported | unsupported | — |
| 1001 | TWCoinTypeThunderCore | supported | reached | supported | supported | TWEthereumMessageSigner |
| 1023 | TWCoinTypeHarmony | supported | reached | unsupported | unsupported | — |
| 1024 | TWCoinTypeOntology | supported | reached | unsupported | unsupported | — |
| 1030 | TWCoinTypeConfluxeSpace | supported | reached | supported | supported | TWEthereumMessageSigner |
| 1329 | TWCoinTypeSeiEVM | supported | reached | supported | supported | TWEthereumMessageSigner |
| 1729 | TWCoinTypeTezos | supported | reached | unsupported | unsupported | TWTezosMessageSigner |
| 1815 | TWCoinTypeCardano | supported | reached | unsupported | unsupported | — |
| 1890 | TWCoinTypeLightlink | supported | reached | supported | supported | TWEthereumMessageSigner |
| 2017 | TWCoinTypeKin | supported | reached | unsupported | unsupported | — |
| 2301 | TWCoinTypeQtum | supported | reached | unsupported | unsupported | TWBitcoinMessageSigner |
| 2718 | TWCoinTypeNebulas | unsupported | empty | unsupported | unsupported | — |
| 3030 | TWCoinTypeHedera | unsupported | empty | unsupported | unsupported | — |
| 4200 | TWCoinTypeMerlin | supported | reached | supported | supported | TWEthereumMessageSigner |
| 4326 | TWCoinTypeMegaETH | supported | reached | supported | supported | TWEthereumMessageSigner |
| 5000 | TWCoinTypeMantle | supported | reached | supported | supported | TWEthereumMessageSigner |
| 5600 | TWCoinTypeGreenfield | supported | reached | unsupported | unsupported | — |
| 6001 | TWCoinTypeBounceBit | supported | reached | supported | supported | TWEthereumMessageSigner |
| 6060 | TWCoinTypeGoChain | supported | reached | supported | supported | TWEthereumMessageSigner |
| 7332 | TWCoinTypeZenEON | supported | reached | supported | supported | TWEthereumMessageSigner |
| 8453 | TWCoinTypeBase | supported | reached | supported | supported | TWEthereumMessageSigner |
| 8964 | TWCoinTypeNULS | supported | reached | unsupported | unsupported | — |
| 9745 | TWCoinTypePlasma | supported | reached | supported | supported | TWEthereumMessageSigner |
| 10143 | TWCoinTypeMonad | supported | reached | supported | supported | TWEthereumMessageSigner |
| 14001 | TWCoinTypeWAX | supported | crash (signal 6 in preimage_empty) | unsupported | unsupported | — |
| 18000 | TWCoinTypeMeter | supported | reached | supported | supported | TWEthereumMessageSigner |
| 19167 | TWCoinTypeZelcash | supported | reached | unsupported | unsupported | — |
| 21888 | TWCoinTypePactus | supported | reached | unsupported | unsupported | — |
| 52752 | TWCoinTypeCelo | supported | reached | supported | supported | TWEthereumMessageSigner |
| 59144 | TWCoinTypeLinea | supported | reached | supported | supported | TWEthereumMessageSigner |
| 81457 | TWCoinTypeBlast | supported | reached | supported | supported | TWEthereumMessageSigner |
| 105105 | TWCoinTypeStratis | supported | reached | unsupported | unsupported | TWBitcoinMessageSigner |
| 534352 | TWCoinTypeScroll | supported | reached | supported | supported | TWEthereumMessageSigner |
| 810180 | TWCoinTypeZkLinkNova | supported | reached | supported | supported | TWEthereumMessageSigner |
| 5718350 | TWCoinTypeWanchain | supported | reached | supported | supported | TWEthereumMessageSigner |
| 5741564 | TWCoinTypeWaves | unsupported | empty | unsupported | unsupported | — |
| 10000025 | TWCoinTypeCronosChain | supported | reached | supported | supported | TWEthereumMessageSigner |
| 10000060 | TWCoinTypeNativeInjective | supported | reached | unsupported | unsupported | — |
| 10000070 | TWCoinTypeOptimism | supported | reached | supported | supported | TWEthereumMessageSigner |
| 10000100 | TWCoinTypeXDai | supported | reached | supported | supported | TWEthereumMessageSigner |
| 10000118 | TWCoinTypeOsmosis | supported | reached | unsupported | unsupported | — |
| 10000145 | TWCoinTypeSmartBitcoinCash | supported | reached | supported | supported | TWEthereumMessageSigner |
| 10000146 | TWCoinTypeSonic | supported | reached | supported | supported | TWEthereumMessageSigner |
| 10000250 | TWCoinTypeFantom | supported | reached | supported | supported | TWEthereumMessageSigner |
| 10000288 | TWCoinTypeBoba | supported | reached | supported | supported | TWEthereumMessageSigner |
| 10000321 | TWCoinTypeKuCoinCommunityChain | supported | reached | supported | supported | TWEthereumMessageSigner |
| 10000324 | TWCoinTypeZksync | supported | reached | supported | supported | TWEthereumMessageSigner |
| 10000330 | TWCoinTypeTerraV2 | supported | reached | unsupported | unsupported | — |
| 10000553 | TWCoinTypeECOChain | supported | reached | supported | supported | TWEthereumMessageSigner |
| 10000714 | TWCoinTypeSmartChainLegacy | supported | reached | supported | supported | TWEthereumMessageSigner |
| 10000787 | TWCoinTypeAcalaEVM | supported | reached | supported | supported | TWEthereumMessageSigner |
| 10000990 | TWCoinTypeCoreum | supported | reached | unsupported | unsupported | — |
| 10000999 | TWCoinTypeHyperEVM | supported | reached | supported | supported | TWEthereumMessageSigner |
| 10001088 | TWCoinTypeMetis | supported | reached | supported | supported | TWEthereumMessageSigner |
| 10001101 | TWCoinTypePolygonzkEVM | supported | reached | supported | supported | TWEthereumMessageSigner |
| 10001284 | TWCoinTypeMoonbeam | supported | reached | supported | supported | TWEthereumMessageSigner |
| 10001285 | TWCoinTypeMoonriver | supported | reached | supported | supported | TWEthereumMessageSigner |
| 10002020 | TWCoinTypeRonin | supported | reached | supported | supported | — |
| 10002222 | TWCoinTypeKavaEvm | supported | reached | supported | supported | TWEthereumMessageSigner |
| 10004663 | TWCoinTypeRobinhoodChain | supported | reached | supported | supported | TWEthereumMessageSigner |
| 10004689 | TWCoinTypeIoTeXEVM | supported | reached | supported | supported | TWEthereumMessageSigner |
| 10007000 | TWCoinTypeNativeZetaChain | supported | reached | unsupported | unsupported | — |
| 10007700 | TWCoinTypeNativeCanto | supported | reached | unsupported | unsupported | — |
| 10008217 | TWCoinTypeKaia | supported | reached | supported | supported | TWEthereumMessageSigner |
| 10009000 | TWCoinTypeAvalancheCChain | supported | reached | supported | supported | TWEthereumMessageSigner |
| 10009001 | TWCoinTypeEvmos | supported | reached | supported | supported | TWEthereumMessageSigner |
| 10042170 | TWCoinTypeArbitrumNova | supported | reached | supported | supported | TWEthereumMessageSigner |
| 10042221 | TWCoinTypeArbitrum | supported | reached | supported | supported | TWEthereumMessageSigner |
| 11000118 | TWCoinTypeSommelier | supported | reached | unsupported | unsupported | — |
| 12000118 | TWCoinTypeFetchAI | supported | reached | unsupported | unsupported | — |
| 13000118 | TWCoinTypeMars | supported | reached | unsupported | unsupported | — |
| 14000118 | TWCoinTypeUmee | supported | reached | unsupported | unsupported | — |
| 15000118 | TWCoinTypeQuasar | supported | reached | unsupported | unsupported | — |
| 16000118 | TWCoinTypePersistence | supported | reached | unsupported | unsupported | — |
| 17000118 | TWCoinTypeAkash | supported | reached | unsupported | unsupported | — |
| 18000118 | TWCoinTypeNoble | supported | reached | unsupported | unsupported | — |
| 19000118 | TWCoinTypeSei | supported | reached | unsupported | unsupported | — |
| 20000118 | TWCoinTypeStargaze | supported | reached | unsupported | unsupported | — |
| 20000714 | TWCoinTypeSmartChain | supported | reached | supported | supported | TWEthereumMessageSigner |
| 20007000 | TWCoinTypeZetaEVM | supported | reached | supported | supported | TWEthereumMessageSigner |
| 20009001 | TWCoinTypeNativeEvmos | supported | reached | unsupported | unsupported | — |
| 21000118 | TWCoinTypeTia | supported | reached | unsupported | unsupported | — |
| 22000118 | TWCoinTypeDydx | supported | reached | unsupported | unsupported | — |
| 30000118 | TWCoinTypeJuno | supported | reached | unsupported | unsupported | — |
| 30000714 | TWCoinTypeTBinance | supported | reached | unsupported | unsupported | — |
| 40000118 | TWCoinTypeStride | supported | reached | unsupported | unsupported | — |
| 50000118 | TWCoinTypeAxelar | supported | reached | unsupported | unsupported | — |
| 60000118 | TWCoinTypeCrescent | supported | reached | unsupported | unsupported | — |
| 70000118 | TWCoinTypeKujira | supported | reached | unsupported | unsupported | — |
| 80000118 | TWCoinTypeComdex | supported | reached | unsupported | unsupported | — |
| 90000118 | TWCoinTypeNeutron | supported | reached | unsupported | unsupported | — |
| 245022934 | TWCoinTypeNeon | supported | reached | supported | supported | TWEthereumMessageSigner |
| 1323161554 | TWCoinTypeAurora | supported | reached | supported | supported | TWEthereumMessageSigner |
