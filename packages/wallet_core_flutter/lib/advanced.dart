/// The advanced import: a same-isolate wallet, and the generated bindings and
/// coin registry underneath the SDK. **Explicitly outside the public
/// contract.**
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// This library exports [HDWallet], which owns its upstream handle in the
/// caller's isolate and follows the synchronous disposal contract of PRD §11.2
/// — `dispose()`, a `DisposedError` after disposal, a native finalizer as the
/// fallback — and re-exports `package:wallet_core_flutter_bindings`'s barrel
/// and its coin registry (`registry.dart`). It is for tests, command-line
/// tools, and callers who accept the ownership and secret-handling
/// responsibilities of PRD §11. Import it alongside
/// `package:wallet_core_flutter/wallet_core_flutter.dart`, which declares the
/// coin facade, the value types, and the errors [HDWallet] uses.
///
/// Three statements govern everything here
/// (`docs/architecture/lifecycle.md` §7):
///
/// 1. **[HDWallet] is not a proxy and holds no session reference; nothing
///    acknowledges its disposal.**
/// 2. **It must never be shared across isolates.** Two isolates each owning
///    their own handles is supported; one handle used from two isolates is not.
/// 3. **The generated bindings and the serialization classes are re-exported
///    here, and only here. Anything a caller does with them is outside the
///    memory contract this SDK upholds elsewhere.**
///
/// At this version the re-export covers the foreign-function bindings, the
/// bindings' memory wrappers, and the coin registry. The protobuf
/// serialization classes are **not** re-exported: the signing path exists,
/// but its family code uses them internally, and the raw-protobuf signing
/// entry point (`RawSigningInput`, `docs/architecture/signing.md` §6) that
/// would bring them here is not written yet.
///
/// [HDWallet] reports a null or out-of-range value from upstream as
/// [NativeResultError], which is exported here for that reason; the session
/// converts the same failure into a typed `WalletCoreException`.
///
/// Two names of the bindings barrel are hidden to keep this library usable
/// next to the default import: `packageName`, and the bindings' own
/// `DisposedError` — an `Error` the raw `TWData`/`TWString` wrappers raise.
/// The `DisposedError` visible here is the SDK's, which [HDWallet] raises;
/// depend on the bindings package directly to name the other.
library;

export 'package:wallet_core_flutter_bindings/registry.dart';
export 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart'
    hide DisposedError, packageName;

export 'src/engine/hd_wallet.dart' show HDWallet;
export 'src/errors/boundary.dart' show NativeResultError;
