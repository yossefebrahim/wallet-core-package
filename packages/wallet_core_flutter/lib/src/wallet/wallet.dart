/// [Wallet], a proxy to a wallet the session's owning isolate holds;
/// [WalletRef]; and [WalletFacade] (`docs/architecture/lifecycle.md` §2).
library;

import 'dart:typed_data';

import '../account/account.dart';
import '../account/derivation_path.dart';
import '../coin/coin.dart';
import '../coin/network.dart';
import '../core/input_checks.dart';
import '../errors/errors.dart';
import '../lifecycle/session_state.dart';
import '../session/session.dart';
import '../worker/protocol.dart';

/// Creating and importing wallets. Obtained from `WalletCore.wallets`.
///
/// Every input is checked in Dart before anything crosses to the owning
/// isolate (PRD §16 S5): a strength, an entropy length, a mnemonic's word
/// count, a passphrase's length, and text that could not reach native code
/// unchanged are all rejected with [InvalidInputError] without a message
/// being sent.
abstract interface class WalletFacade {
  /// Creates a wallet with a new random mnemonic of [strength] bits — 128,
  /// 160, 192, 224, or 256.
  ///
  /// [passphrase] crosses to the owning isolate and is key material. **The
  /// new mnemonic does not come back from this call**: it is obtained the
  /// same way any other wallet's is, by calling [Wallet.exportMnemonic] on the
  /// result, so that a mnemonic crosses the boundary by exactly one path.
  Future<Wallet> create({int strength = 128, String passphrase = ''});

  /// Imports a wallet from a BIP-39 English mnemonic.
  ///
  /// Carries a secret across the isolate boundary. The mnemonic is a Dart
  /// `String`: this SDK drops its own references once the wallet exists and
  /// cannot erase the caller's copy or the platform's input buffers.
  Future<Wallet> importMnemonic(String mnemonic, {String passphrase = ''});

  /// Imports a wallet from 16, 20, 24, 28, or 32 bytes of BIP-39 entropy.
  ///
  /// [entropy] is copied when this is called, so changing it afterwards does
  /// not change which wallet is imported; the copy is overwritten with zeros
  /// once the owning isolate has used it. Same secret-handling note as
  /// [importMnemonic] for the caller's own list.
  Future<Wallet> importEntropy(Uint8List entropy, {String passphrase = ''});
}

/// A handle-free reference to a wallet owned by the session's isolate.
///
/// The object holds an opaque reference and plain values only. It cannot
/// free anything itself; [close] asks the owner to free it and awaits the
/// acknowledgement. A proxy that is dropped without [close] is still
/// released: its finalizer asks the owner to free it, while the session is
/// ready (PRD §11.2 item 8). Closing explicitly is the primary path.
abstract interface class Wallet {
  /// Opaque, session-scoped identity of this wallet. It is not a capability
  /// to key material and carries no key.
  WalletRef get ref;

  /// Whether [close] has been called — `true` from the moment it is called,
  /// not from the moment it completes — or the session has ended.
  bool get isClosed;

  /// Derives an account descriptor. Nothing native crosses back: the result
  /// is an address, a public key, and a path.
  ///
  /// Throws [UnsupportedOperationError] when ([coin], [network], [style]) has
  /// no derivation at the pinned upstream tag, and [InvalidInputError] when
  /// [path] is not a well-formed BIP-32 path — both before anything crosses.
  Future<Account> account(
    Coin coin, {
    Network network = Network.mainnet,
    AddressStyle style = AddressStyle.standard,
    String? path,
  });

  /// The wallet's mnemonic.
  ///
  /// Returns a Dart `String` because it exists to be shown to a person. The
  /// string lives until it is collected and cannot be erased. Display it once
  /// and drop the reference.
  ///
  /// This is the **only** payload that carries key material *back* across
  /// the isolate boundary (DECISION-12 §3.2). A wallet made by
  /// [WalletFacade.create] surrenders its mnemonic here too, and nowhere else.
  Future<String> exportMnemonic();

  /// Releases this wallet in the owning isolate and awaits the
  /// acknowledgement.
  ///
  /// Idempotent: repeated and concurrent calls await the same completion.
  /// The proxy is unusable from the moment this is called — every other
  /// member then throws [ClosedError] — and the underlying handle is freed
  /// after any operation already submitted on it has finished.
  ///
  /// **This wait has no deadline**, and there is no timeout setting for it
  /// (DECISION-12 §3.5). It completes when the acknowledgement arrives, or
  /// with [WorkerTerminatedError] if the session's isolate ends first — never
  /// with [OperationTimeoutError]. After `WalletCore.shutdown()` it completes
  /// at once: shutdown released everything.
  Future<void> close();
}

/// An opaque, session-scoped reference. Not forgeable, not transferable
/// between sessions, not a key.
///
/// Holding a reference keeps its [Wallet] proxy reachable, so a wallet whose
/// reference is still in use is never released by the proxy's finalizer.
final class WalletRef {
  WalletRef._(this._session, this._id);

  final WalletCoreSession _session;
  final int _id;

  /// The proxy this names. Never read; held so that the proxy, and with it
  /// the handle, lives at least as long as anything that names it.
  // ignore: unused_field
  late final Wallet _wallet;

  /// The reference's number within its session. Not a secret, not a key.
  @override
  String toString() => 'WalletRef(#$_id)';
}

/// The executor-issued id [ref] carries, once [ref] has been checked to
/// belong to [session]. **Internal.**
///
/// Throws [KeyResolutionError] for a reference from another session
/// (DECISION-12 §3.3, DECISION-13 §Q5): there is no way to hand a reference
/// from one session to another. T1.12's signer calls this for every wallet a
/// `KeyLocator` names.
int resolveWalletRef(WalletCoreSession session, WalletRef ref) {
  if (!identical(ref._session, session)) {
    throw const KeyResolutionError(
      'the wallet reference belongs to another session',
    );
  }
  return ref._id;
}

/// The [WalletFacade] of [WalletCoreSession]. **Internal.**
final class WalletFacadeImpl implements WalletFacade {
  /// Creates the facade over [session].
  WalletFacadeImpl(this._session);

  final WalletCoreSession _session;

  @override
  Future<Wallet> create({int strength = 128, String passphrase = ''}) async {
    checkStrength(strength);
    checkPassphrase(passphrase);
    return _adopt(
      _session.submit(
        (id) => CreateWallet(id, strength: strength, passphrase: passphrase),
        timeout: _session.timeouts.walletOperation,
        parse: _walletRef,
      ),
    );
  }

  @override
  Future<Wallet> importMnemonic(
    String mnemonic, {
    String passphrase = '',
  }) async {
    checkMnemonicShape(mnemonic);
    checkPassphrase(passphrase);
    return _adopt(
      _session.submit(
        (id) => ImportWallet.mnemonic(id, mnemonic, passphrase: passphrase),
        timeout: _session.timeouts.walletOperation,
        parse: _walletRef,
      ),
    );
  }

  @override
  Future<Wallet> importEntropy(
    Uint8List entropy, {
    String passphrase = '',
  }) async {
    checkEntropy(entropy);
    checkPassphrase(passphrase);
    return _adopt(
      _session.submit(
        (id) => ImportWallet.entropy(id, entropy, passphrase: passphrase),
        timeout: _session.timeouts.walletOperation,
        parse: _walletRef,
      ),
    );
  }

  Future<Wallet> _adopt(Future<int> created) async =>
      WalletProxy._(_session, await created);

  static int _walletRef(WorkerReply reply) => switch (reply) {
    WalletCreated(:final walletRef) => walletRef,
    _ => throw StateError('unexpected reply ${reply.runtimeType}'),
  };
}

/// What the proxy finalizer needs: the session and the number. Never the
/// proxy — a token that reached it would keep it alive for ever.
final class _FinalizerTicket {
  const _FinalizerTicket(this.session, this.walletRef);

  final WalletCoreSession session;
  final int walletRef;
}

/// The [Wallet] of [WalletCoreSession]. **Internal.**
final class WalletProxy implements Wallet {
  WalletProxy._(this._session, this._refId)
    : ref = WalletRef._(_session, _refId) {
    ref._wallet = this;
    _finalizer.attach(this, _FinalizerTicket(_session, _refId), detach: this);
  }

  /// One managed finalizer for every proxy (PRD §11.2 item 8). Its callback
  /// posts `DisposeRef` only while the session is `ready`, and never throws
  /// (lifecycle.md §5, the proxy finalizer rule).
  static final Finalizer<_FinalizerTicket> _finalizer =
      Finalizer<_FinalizerTicket>(
        (ticket) => ticket.session.postFinalizerDispose(ticket.walletRef),
      );

  final WalletCoreSession _session;
  final int _refId;
  Future<void>? _closing;

  @override
  final WalletRef ref;

  @override
  bool get isClosed =>
      _closing != null ||
      _session.state == SessionState.closed ||
      _session.state == SessionState.failed;

  @override
  Future<Account> account(
    Coin coin, {
    Network network = Network.mainnet,
    AddressStyle style = AddressStyle.standard,
    String? path,
  }) async {
    _checkOpen();
    resolveDerivation(coin, network, style);
    if (path != null) checkDerivationPath(path);
    return _session.submit(
      (id) => DeriveAddress(
        id,
        walletRef: _refId,
        coin: coin,
        network: network,
        style: style,
        path: path,
      ),
      timeout: _session.timeouts.derivation,
      parse: (reply) => switch (reply) {
        AddressDerived(:final account) => account,
        _ => throw StateError('unexpected reply ${reply.runtimeType}'),
      },
    );
  }

  @override
  Future<String> exportMnemonic() async {
    _checkOpen();
    return _session.submit(
      (id) => ExportMnemonic(id, walletRef: _refId),
      timeout: _session.timeouts.walletOperation,
      parse: (reply) => switch (reply) {
        MnemonicExported(:final mnemonic) => mnemonic,
        _ => throw StateError('unexpected reply ${reply.runtimeType}'),
      },
    );
  }

  @override
  Future<void> close() {
    final existing = _closing;
    if (existing != null) return existing;
    // Closed locally first, then the dispose is posted and the finalizer
    // detached: a later collection must post nothing (DECISION-12 §3.8).
    final closing = _session.releaseWallet(_refId);
    _closing = closing;
    _finalizer.detach(this);
    return closing;
  }

  void _checkOpen() {
    if (_closing != null) throw const ClosedError('Wallet');
  }

  /// The reference's number, and nothing else.
  @override
  String toString() => 'Wallet(#$_refId${isClosed ? ', closed' : ''})';
}
