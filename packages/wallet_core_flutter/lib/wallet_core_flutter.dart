/// Public SDK layer of the `wallet_core_flutter` workspace.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// This library exports the typed SDK surface only: no `dart:ffi` type, no
/// generated `TW*` class, no generated coin-registry type, and no protobuf
/// class ever appears in a signature here (PRD §8, AGENTS.md rules 4 and 12).
///
/// Start at [WalletCore.initialize]. A session creates and imports wallets
/// ([WalletCore.wallets]), whose [Wallet] proxies export a mnemonic and
/// derive [Account]s; validates addresses ([WalletCore.addresses]) and
/// mnemonics ([WalletCore.mnemonics]); scopes resources
/// ([WalletCore.scope]); signs ([WalletCore.signer]); and shuts down
/// ([WalletCore.shutdown]). Every call is asynchronous, and every resource
/// closes with an acknowledged `Future<void> close()`
/// (`docs/architecture/lifecycle.md` §1–§4). Beside the session: the stable
/// coin facade of DECISION-11 ([Coin], [Network], [AddressStyle],
/// [ChainFamily]), the handle-free value types [Account] and [Address], the
/// signing model of DECISION-13 — key-less requests
/// ([EvmTransactionRequest]), keys named by [KeyLocator]s, sealed
/// [SignResult]s (`docs/architecture/signing.md`) — and the sealed
/// [WalletCoreException] hierarchy.
///
/// Transaction signing covers the EVM family at this version. Message
/// signing and UTXO planning are not part of it.
library;

export 'package:wallet_core_flutter_native/wallet_core_flutter_native.dart'
    show ManifestCheck;

export 'src/account/account.dart' show Account;
export 'src/address/address.dart' show Address;
export 'src/address/address_facade.dart' show AddressFacade;
export 'src/coin/chain_family.dart' show ChainFamily;
export 'src/coin/coin.dart' show Coin, CoinStatus;
export 'src/coin/network.dart' show AddressStyle, Network;
export 'src/errors/errors.dart'
    show
        ClosedError,
        DisposedError,
        InvalidInputError,
        KeyResolutionError,
        KeyResolutionReason,
        ManifestMismatchError,
        NativeLoadAttempt,
        NativeLoadError,
        OperationCancelledError,
        OperationTimeoutError,
        QueueFullError,
        SessionStateError,
        SigningError,
        UnknownCoinError,
        UnsupportedOperationError,
        WalletCoreException,
        WorkerTerminatedError,
        WorkerTerminationKind;
export 'src/lifecycle/session_state.dart' show SessionState;
export 'src/mnemonic/mnemonic_facade.dart' show MnemonicFacade;
export 'src/requests/requests.dart'
    show EvmTransactionRequest, MessageRequest, TransactionRequest;
export 'src/session/wallet_core.dart'
    show OperationTimeouts, SessionScope, WalletCore;
export 'src/signing/key_locator.dart'
    show
        ExternalKeyLocator,
        HdKeyLocator,
        ImportedKeyLocator,
        KeyLocator,
        KeyRef,
        KeyRole;
export 'src/signing/sign_result.dart' show EvmSignResult, SignResult;
export 'src/signing/signer.dart' show LocalSigner, Signer;
export 'src/wallet/wallet.dart' show Wallet, WalletFacade, WalletRef;

/// The pub name of this package.
const String packageName = 'wallet_core_flutter';
