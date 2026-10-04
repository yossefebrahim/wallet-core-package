# wallet_core_flutter example

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

A Flutter app that walks through the M0 flow one step at a time, using only the
public SDK surface: `package:wallet_core_flutter/wallet_core_flutter.dart`. The
app never imports `advanced.dart`, a `src/` path of the SDK, `dart:ffi`, or a
generated or protobuf type, and never names `CoinType`.

## What the app shows

One scrolling page, six steps. Each card names the SDK call it makes and shows
what came back: the result, or the error's public type name (`NativeLoadError`,
`InvalidInputError`, `ClosedError`, …) with its message.

| Step | Public API | Shown |
|---|---|---|
| 1. Start a session | `WalletCore.initialize()` | `SessionState`, and every state the `states` stream reports; a failure (`NativeLoadError` / `ManifestMismatchError`) is a state: no session, nothing to close |
| 2. Create a wallet | `wallets.create(strength:)`, then `wallet.exportMnemonic()` | the wallet reference; `create()` does not return the mnemonic, so the app asks `exportMnemonic()` for it, shows it once, and drops it when you hide it |
| 3. Import a mnemonic | `mnemonics.isValidWord`, `mnemonics.suggest`, `mnemonics.isValid`, then `wallets.importMnemonic()` | a live check as you type: word count, positions of words not in the BIP-39 English list, whether the last word is still being typed, whether the whole is valid |
| 4. Derive an address | `wallet.account(Coin.ethereum, path:)` | the `Account`: coin, network, address style, path, address, public key |
| 5. Sign a transfer | `EvmTransactionRequest.transfer(…)`, `signer.sign(request, {KeyLocator.hdPath(wallet.ref, coin, path)})` | the `EvmSignResult`: encoded transaction, `v`, `r`, `s`, pre-hash when present, `usedKeys` |
| 6. Close and shut down | `wallet.close()`, `WalletCore.shutdown()` | each wallet as closed, then `SessionState.closed` |

The request in step 5 carries no key: the `KeyLocator` names the key of the
account derived in step 4, and the signer resolves it inside the session. The
form's defaults are the request of the repository's test vector
`ethereum-sign-eip1559-1` (`test_vectors/ethereum/vectors.yaml`): chain id 3, a
deprecated testnet, so a transaction signed here is not valid on mainnet. That
vector signs with a raw private key, which the public surface has no way to
name, so the bytes the app produces are not the vector's.

**Leak-tracker report.** Not part of the public surface: the SDK exposes it
only through its internal test entry point. The app therefore shows the
session's states after `shutdown()` instead. The `native`-tagged test reads the
report through the test seam and asserts it is zero after step 6.

**Secrets.** Nothing is logged, sent anywhere, or kept by the app beyond the
step that needs it. The mnemonic from step 2 is held only while it is on
screen, is not selectable, and is excluded from the semantics tree (so
accessibility services and semantics dumps do not receive it; the trade-off is
that a screen-reader user cannot read it either). The import field is obscured,
with suggestions, autocorrect and keyboard learning off, and is cleared once
the wallet is imported; the live check reports positions and counts, never a
word. Widget keys name controls, never values. None of this erases the copies
a Dart `String` and the platform's input buffers leave behind; see
`docs/security/memory_contract.md`.

## Running it

The app depends on the SDK by path (`../packages/wallet_core_flutter`) and is
not a member of the pub workspace, so resolve it on its own:

```sh
cd example
flutter pub get
flutter analyze
flutter test                      # everything; the native test skips without a host library
flutter test --tags native        # only the host-library test
```

`flutter test` needs no native library: the in-process tests run the SDK's real
session, queue and executor over a fake request handler. The `native`-tagged
test runs the same six steps against the real library and checks the derived
address and public key against test vector `ethereum-address-n/a-1`. It looks
for the library at `$WCF_NATIVE_LIB`, else at
`third_party/wcf-native/macos/arm64_x86_64/libTrustWalletCore.dylib` (build it
with `melos run native:host-lib`), and skips when neither exists;
`WCF_NATIVE_REQUIRED=1` makes absence a failure.

The tests start their sessions through the SDK's internal test entry point
(`package:wallet_core_flutter/src/session/testing.dart`), because the public
`initialize()` takes no library path. Every such import is in
`test/support/test_seam.dart`, as in the SDK package's own tests; nothing under
`lib/` uses it.

## What depends on packaging

The app builds today (`flutter build apk --debug` succeeds), but no native
library is packaged into it: the APK carries `libflutter.so` and no
`libTrustWalletCore.so`, so step 1 on a device or emulator shows
`NativeLoadError` (or `ManifestMismatchError` if a library with another
identity is found). Shipping
the library is DECISION-2's packaging mechanism — build hooks or
Gradle/podspec — and the shipped manifest's identity is a placeholder until the
first native release.

TODO(T1.16b, after DECISION-2): wire the chosen packaging into a consumer the
way a real app would (a hosted dependency, no edits under `android/` or `ios/`),
then run this flow on the Android emulator and the iOS simulator in debug and
release. That is `tools/consumer_check.sh`; today its `create_consumer` and
`publish_locally` stages run, and the packaging-dependent stages exit 2,
"waiting for DECISION-2 (T1.16b)".

`android/` and `ios/` are exactly what
`flutter create --platforms=android,ios --org dev.wcf.example --project-name wallet_core_flutter_example`
wrote, under an empty `HOME` so that no Apple development team was recorded.
They carry no native edits (PRD §12.2 step 1).
