/// Generated bindings layer of the `wallet_core_flutter` workspace.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// This library exports the generated `ffigen` output over upstream's public C
/// API, the generated list of the symbol names those bindings bind — which the
/// native package's loader resolves against a loaded library — and the
/// hand-written ownership wrappers that own `TWData` and `TWString`
/// objects under the disposal contract of PRD §11.2. The generated protobuf
/// classes and the generated coin registry are *not* exported here; which of
/// them belong to this package's surface is decided with the advanced import
/// (T1.11, T1.12).
///
/// A consumer importing this package accepts the ownership and secret-handling
/// responsibilities of PRD §11: these are raw handles, released explicitly, and
/// the default SDK surface (`package:wallet_core_flutter/wallet_core_flutter.dart`)
/// exposes none of them.
library;

export 'src/generated/ffi/symbol_names.dart'
    show boundFunctionNames, exportedTwFunctionNames;
export 'src/generated/ffi/wallet_core_bindings.dart';
export 'src/memory/memory.dart';

/// The pub name of this package.
const String packageName = 'wallet_core_flutter_bindings';
