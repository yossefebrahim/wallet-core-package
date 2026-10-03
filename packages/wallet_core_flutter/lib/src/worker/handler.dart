/// The executor's request handler: one request in, one reply out, over the
/// engine and the table of wallets it owns. **Internal**: never exported.
library;

import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart'
    hide DisposedError;
import 'package:wallet_core_flutter_native/wallet_core_flutter_native.dart'
    show WalletCoreNative, identitySymbol, verifyIdentity, verifyManifestHash;

import '../engine/engine.dart';
import '../engine/hd_wallet.dart';
import '../errors/boundary.dart';
import '../errors/errors.dart';
import '../lifecycle/session_state.dart';
import 'protocol.dart';

/// Turns one [WorkerRequest] into its one [WorkerReply], synchronously, in
/// the isolate that owns the native handles.
///
/// This is the seam both executors share: the M0 in-process transport and
/// T2.1's worker isolate drive the same handler through the same
/// `WorkerLoop`, so neither the protocol nor this contract changes when the
/// transport does. T1.12 adds a case for `Sign` to the implementation's
/// `switch`, which the sealed request family forces.
///
/// **The error rule.** [handle] returns [Failed] for every error that
/// `toWalletCoreException` maps. Anything it does not map — a `RangeError`
/// from a corrupt native size, a `StateError` from a null native buffer, an
/// `ArgumentError` from a defect — is **rethrown**: it means the executor's
/// own invariants can no longer be trusted, and the loop treats it as the
/// worker dying with an uncaught error (DECISION-12 §3.10), not as one failed
/// operation.
///
/// [Cancel] is the loop's business and never reaches a handler.
abstract interface class RequestHandler {
  /// Handles [request] and returns its reply. Rethrows unmapped errors.
  WorkerReply handle(WorkerRequest request);

  /// How many wallets are live in the reference table.
  int get liveRefCount;

  /// Releases every handle, swallowing any failure, and returns how many were
  /// released. The path a dying or killed executor takes; never throws.
  int releaseAll();
}

/// The production [RequestHandler]: owns a [WalletEngine] once [Init] has
/// run, and the table from wallet reference to [HDWallet].
///
/// Order inside every operation is DECISION-12 §3.9's: the engine parses
/// upstream's output into Dart values and releases every temporary — derived
/// keys included — in its own `finally`, and only then does this method
/// return the reply the loop posts. Nothing here keeps a request after
/// [handle] returns, and the one `Uint8List` a request owns, [ImportWallet]'s
/// entropy copy, is overwritten with zeros before [handle] returns.
final class EngineRequestHandler implements RequestHandler {
  /// Creates a handler with no library loaded; [Init] loads one.
  EngineRequestHandler();

  WalletEngine? _engine;
  bool _shutDown = false;

  /// Wallets by reference. References start at 1 and are never reused.
  final Map<int, HDWallet> _wallets = <int, HDWallet>{};
  int _nextRef = 1;

  /// The observer every handle reports to — a `LeakTracker` in a debug build,
  /// the no-op observer in a release build — or `null` before [Init].
  ResourceObserver? get observer => _engine?.context.observer;

  @override
  int get liveRefCount => _wallets.length;

  @override
  WorkerReply handle(WorkerRequest request) {
    try {
      return _dispatch(request);
    } on Object catch (error) {
      final mapped = toWalletCoreException(error);
      if (mapped == null) rethrow;
      return Failed(request.id, mapped);
    } finally {
      overwriteOwnedSecrets(request);
    }
  }

  WorkerReply _dispatch(WorkerRequest request) {
    if (request is Init) return _init(request);
    if (_shutDown) {
      // A late dispose is a no-op that still answers (DECISION-12 §3.7);
      // anything else is refused.
      if (request is DisposeRef) {
        return Disposed(request.id, walletRef: request.walletRef);
      }
      throw const ClosedError('WalletCore');
    }
    final engine = _engine;
    if (engine == null) {
      throw SessionStateError(
        SessionState.initializing,
        attempted: request.operation,
      );
    }
    return switch (request) {
      Init() => throw StateError('unreachable'),
      CreateWallet(:final id, :final strength, :final passphrase) => _adopt(
        id,
        engine.createWallet(strength: strength, passphrase: passphrase),
      ),
      ImportWallet(:final id, :final mnemonic?, :final passphrase) => _adopt(
        id,
        engine.importMnemonic(mnemonic, passphrase: passphrase),
      ),
      ImportWallet(:final id, :final entropy, :final passphrase) => _adopt(
        id,
        engine.importEntropy(entropy!, passphrase: passphrase),
      ),
      ExportMnemonic(:final id, :final walletRef) => MnemonicExported(
        id,
        engine.exportMnemonic(_resolve(walletRef)),
      ),
      DeriveAddress(
        :final id,
        :final walletRef,
        :final coin,
        :final network,
        :final style,
        :final path,
      ) =>
        AddressDerived(
          id,
          engine.deriveAccount(
            _resolve(walletRef),
            coin,
            network: network,
            style: style,
            path: path,
          ),
        ),
      ValidateAddress(:final id, :final value, :final coin, :final network) =>
        AddressValidated(
          id,
          isValid: engine.isValidAddress(value, coin, network: network),
        ),
      ValidateMnemonic(:final id, :final mnemonic) => MnemonicValidated(
        id,
        isValid: engine.isValidMnemonic(mnemonic),
      ),
      ValidateMnemonicWord(:final id, :final word) => MnemonicWordValidated(
        id,
        isValid: engine.isValidMnemonicWord(word),
      ),
      SuggestMnemonicWords(:final id, :final prefix) => MnemonicWordsSuggested(
        id,
        engine.suggestMnemonicWords(prefix),
      ),
      DisposeRef(:final id, :final walletRef) => _dispose(id, walletRef),
      Cancel(:final id, :final target) => NotCancellable(id, target: target),
      Shutdown(:final id) => _shutdown(id),
    };
  }

  /// Load → identity → manifest hash → symbols, synchronously, then the
  /// engine. Any failure leaves no engine and nothing to release.
  WorkerReply _init(Init request) {
    if (_engine != null || _shutDown) {
      throw SessionStateError(
        _shutDown ? SessionState.closed : SessionState.ready,
        attempted: request.operation,
      );
    }
    final library = WalletCoreNative.load(
      hostLibraryPath: request.hostLibraryPath,
    );
    verifyIdentity(library, expected: request.expectedIdentity);
    final manifestBytes = request.manifestBytes;
    if (manifestBytes != null) verifyManifestHash(manifestBytes);
    // Comparison 1 of DECISION-14 §2.3 — the three packages' release-set ids
    // — belongs here, after comparison 2 and before the symbol check, and is
    // T3.11's to add: until T3.11 generates the SDK's and the bindings'
    // `releaseSetId`, every value `verifyReleaseSet` could be given is the
    // `TBD-T3.11` placeholder it rejects by design. Not called with
    // placeholders, so that its absence is visible rather than vacuous.
    final symbols = <String>[...boundFunctionNames, identitySymbol];
    WalletCoreNative.requireSymbols(library, symbols);
    _engine = WalletEngine(
      NativeContext(
        WalletCoreBindings(library),
        observer: LeakTracker.maybeCreate() ?? const NoopResourceObserver(),
      ),
    );
    return InitOk(request.id, symbolCount: symbols.length);
  }

  WalletCreated _adopt(int id, HDWallet wallet) {
    final ref = _nextRef++;
    _wallets[ref] = wallet;
    return WalletCreated(id, walletRef: ref);
  }

  /// The wallet [ref] names. A reference this table never issued is an
  /// [InvalidInputError]; one it issued and has since released is a
  /// [ClosedError] (DECISION-12 §3.3). Neither touches native code.
  HDWallet _resolve(int ref) {
    final wallet = _wallets[ref];
    if (wallet != null) return wallet;
    if (ref < 1 || ref >= _nextRef) {
      throw const InvalidInputError(
        'this wallet reference was not issued by this session',
        inputName: 'wallet',
      );
    }
    throw const ClosedError('Wallet');
  }

  Disposed _dispose(int id, int ref) {
    _wallets.remove(ref)?.dispose();
    return Disposed(id, walletRef: ref);
  }

  ShutdownComplete _shutdown(int id) {
    final count = _disposeAll();
    _shutDown = true;
    // Shutdown released everything, so nothing collected from here on is a
    // missed dispose (DECISION-12 §3.7, the leak tracker's `stop`).
    final observer = this.observer;
    if (observer is LeakTracker) observer.stop();
    return ShutdownComplete(id, disposedCount: count);
  }

  int _disposeAll() {
    final wallets = _wallets.values.toList();
    _wallets.clear();
    for (final wallet in wallets) {
      wallet.dispose();
    }
    return wallets.length;
  }

  @override
  int releaseAll() {
    final wallets = _wallets.values.toList();
    _wallets.clear();
    var released = 0;
    for (final wallet in wallets) {
      try {
        wallet.dispose();
        released++;
      } on Object {
        // Best effort on a path that must not throw: the native finalizer
        // remains attached to anything this failed to release.
      }
    }
    _shutDown = true;
    return released;
  }
}
