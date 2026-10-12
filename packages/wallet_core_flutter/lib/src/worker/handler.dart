/// The executor's request handler: one request in, one reply out, over the
/// engine and the table of wallets it owns. **Internal**: never exported.
library;

import 'dart:ffi' show DynamicLibrary;

import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart'
    hide DisposedError;
import 'package:wallet_core_flutter_native/wallet_core_flutter_native.dart'
    show WalletCoreNative, identitySymbol, verifyIdentity, verifyManifestHash;

import '../account/derivation_path.dart';
import '../coin/coin.dart';
import '../engine/engine.dart';
import '../engine/hd_wallet.dart';
import '../errors/boundary.dart';
import '../errors/errors.dart';
import '../families/families.dart';
import '../lifecycle/session_state.dart';
import '../requests/requests.dart';
import '../signing/key_field_check.dart';
import '../signing/key_locator.dart';
import '../signing/sign_result.dart';
import '../signing/signing_core.dart';
import 'protocol.dart';

/// Builds the [SigningCore] an [EngineRequestHandler] signs through, over the
/// context its `Init` loaded.
typedef SigningCoreFactory = SigningCore Function(NativeContext context);

/// Builds the bindings an [EngineRequestHandler] calls through, over the
/// library its `Init` loaded and verified.
typedef BindingsFactory = WalletCoreBindings Function(DynamicLibrary library);

/// The public error a [NativeResultError] raised while handling [request]
/// becomes (DECISION-12 §3.10, which names exactly these two types for a
/// soft native failure):
///
/// * [Sign] and [SignMessage] → [SigningError] with [SigningError.malformedOutputCode]: the
///   signing operation failed inside upstream, as an unacceptable output
///   does.
/// * Every other operation → [InvalidInputError] naming the operation's
///   principal input — the type the engine already gives upstream's other
///   refusals (a null wallet, a null key at a path), and whose contract
///   covers input "rejected by upstream". Its message says the result was
///   unusable, so it does not read as the caller's mistake.
///
/// The message names the native call and what was wrong with its result,
/// never a value.
WalletCoreException softNativeFailure(
  WorkerRequest request,
  NativeResultError error,
) {
  final message = 'upstream returned an unusable result: ${error.what}';
  return switch (request) {
    Sign() ||
    SignMessage() => SigningError(SigningError.malformedOutputCode, message),
    CreateWallet() => InvalidInputError(message, inputName: 'passphrase'),
    ImportWallet(:final mnemonic) => InvalidInputError(
      message,
      inputName: mnemonic != null ? 'mnemonic' : 'entropy',
    ),
    ExportMnemonic() ||
    DisposeRef() => InvalidInputError(message, inputName: 'wallet'),
    DeriveAddress() => InvalidInputError(message, inputName: 'derivationPath'),
    ValidateAddress() => InvalidInputError(message, inputName: 'address'),
    ValidateMnemonic() => InvalidInputError(message, inputName: 'mnemonic'),
    ValidateMnemonicWord() => InvalidInputError(message, inputName: 'word'),
    SuggestMnemonicWords() => InvalidInputError(message, inputName: 'prefix'),
    Init() || Cancel() || Shutdown() => InvalidInputError(message),
  };
}

/// Turns one [WorkerRequest] into its one [WorkerReply], synchronously, in
/// the isolate that owns the native handles.
///
/// This is the seam both executors share: the M0 in-process transport and
/// T2.1's worker isolate drive the same handler through the same
/// `WorkerLoop`, so neither the protocol nor this contract changes when the
/// transport does.
///
/// **The error rule** (DECISION-12 §3.10). [handle] returns [Failed] for
/// every error that `toWalletCoreException` maps, and for every *soft native
/// failure* — a null return or an out-of-range size at the native boundary,
/// raised as `NativeResultError` — which becomes the operation's typed error
/// ([softNativeFailure]) while the session stays `ready`. Anything else — a
/// `StateError` or `RangeError` from a broken invariant of this SDK's own
/// code, an `ArgumentError` from a defect — is **rethrown**: it means the
/// executor's own invariants can no longer be trusted, and the loop treats
/// it as the worker dying with an uncaught error, not as one failed
/// operation.
///
/// [Cancel] is the loop's business and never reaches a handler.
abstract interface class RequestHandler {
  /// Handles [request] and returns its reply. Rethrows unmapped errors.
  WorkerReply handle(WorkerRequest request);

  /// Releases whatever [reply] made that nobody will now receive — the
  /// wallet a [WalletCreated] names — because the operation's deadline passed
  /// and the loop is dropping [reply] unposted. Anything else needs nothing:
  /// its temporaries were released before [handle] returned. Never throws.
  void discard(WorkerReply reply);

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
///
/// **Signing** ([Sign]) is the one operation that holds a private key; the
/// doc comment of its private `_sign` gives the order of its checks and the
/// key's lifetime.
final class EngineRequestHandler implements RequestHandler {
  /// Creates a handler with no library loaded; [Init] loads one.
  ///
  /// [signingCore] builds the core [Sign] is signed through, once [Init] has
  /// a context: [SyncSigningCore] — Approach A of DECISION-1 — unless a test,
  /// or T1.13's Approach B, supplies another. Everything in front of the core
  /// (locator resolution, validation, encoding, key derivation) and the
  /// reply behind it stay as they are whichever core signs.
  ///
  /// [bindings] replaces the bindings over the loaded library — a test seam,
  /// for driving the soft-native-failure path with an upstream function that
  /// returns null or a corrupt size. Defaults to `WalletCoreBindings.new`.
  EngineRequestHandler({
    SigningCoreFactory? signingCore,
    BindingsFactory? bindings,
  }) : _signingCoreFactory = signingCore ?? SyncSigningCore.new,
       _bindingsFactory = bindings ?? WalletCoreBindings.new;

  final SigningCoreFactory _signingCoreFactory;
  final BindingsFactory _bindingsFactory;

  WalletEngine? _engine;
  SigningCore? _signingCore;
  int _sessionToken = 0;
  bool _shutDown = false;

  /// How many times the signing path has asked upstream to derive a private
  /// key. A diagnostic for tests asserting that a rejected [Sign] derived
  /// none; a count, never a key or anything about one.
  int get keysDerived => _keysDerived;
  int _keysDerived = 0;

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
    } on NativeResultError catch (error) {
      // A soft native failure: typed, for this operation only; the session
      // stays ready (DECISION-12 §3.10, TM-19, TM-20).
      return Failed(request.id, softNativeFailure(request, error));
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
      Sign(:final id, :final request, :final keys) => Signed(
        id,
        _sign(engine, _signingCore!, request, keys),
      ),
      SignMessage(:final id, :final request, :final keys) => MessageSigned(
        id,
        _signMessage(_signingCore!, request, keys),
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
    final context = NativeContext(
      _bindingsFactory(library),
      observer: LeakTracker.maybeCreate() ?? const NoopResourceObserver(),
    );
    _signingCore = _signingCoreFactory(context);
    _sessionToken = request.sessionToken;
    _engine = WalletEngine(context);
    return InitOk(request.id, symbolCount: symbols.length);
  }

  /// Signs [request] with the keys [keys] name, and returns the parsed
  /// result with empty `usedKeys` (see [Signed]).
  ///
  /// **Everything before step 5 runs before any key exists.** In this order:
  ///
  /// 1. **Resolve** [keys] against `familyFor(request).requiredRoles(request)`
  ///    ([_resolveKeys]), in pure Dart — no native call. The answer is one HD
  ///    locator per role the family requires, in the family's order.
  /// 2. **Resolve the wallet and check the path** of each of those locators
  ///    with `checkDerivationPath`.
  /// 3. **Check the recipient** with upstream's address validation for the
  ///    request's coin, the EIP-55 checksum included
  ///    ([WalletEngine.checkRecipient]).
  /// 4. **Encode** the key-less input (`encodeKeylessInput`) and run the
  ///    key-field check on it (`checkKeylessInput`) — the decode proving the
  ///    bytes one complete, well-formed signing input, the walk proving every
  ///    key field absent, which is the precondition of the core's injection —
  ///    so that a defective encoder fails before a key is derived. The core
  ///    runs the check again; the core does not rely on its caller either.
  /// 5. **Derive** one key per role in one scope ([withDerivedKeys]):
  ///    `TWHDWalletGetKey` into a `TWPrivateKey` each. The handles are lent to
  ///    the core; **no key bytes exist yet**, and none are made here.
  /// 6. **Sign** with [core] ([SigningCore.sign]), which borrows the handles,
  ///    reads each key only while it assembles the keyed input, calls
  ///    upstream, and parses the output — parse before release.
  /// 7. **Release**, in `withDerivedKeys`' scope, on every path: every
  ///    `TWPrivateKey` (`TWPrivateKeyDelete`, whose destructor overwrites its
  ///    bytes). Only after that does this return, and only after this
  ///    returns is the reply posted — release before reply (DECISION-12
  ///    §3.9).
  ///
  /// Every error is typed and none carries key material. A failure at steps
  /// 1–4 derives nothing and does not reach [core]: the tests assert both,
  /// with [keysDerived] and a recording core.
  SignResult _sign(
    WalletEngine engine,
    SigningCore core,
    TransactionRequest request,
    Set<LocatorSpec> keys,
  ) {
    final family = familyFor(request);
    final roles = family.requiredRoles(request);
    final locators = _resolveKeys(request.coin, roles, keys);
    final derivations = <KeyRole, KeyDerivation>{};
    for (final MapEntry(key: role, value: locator) in locators.entries) {
      final wallet = _resolve(locator.walletRef);
      final path = checkDerivationPath(locator.derivationPath);
      derivations[role] = KeyDerivation(wallet, locator.coin, path);
    }
    switch (request) {
      case EvmTransactionRequest(:final to, :final coin, :final network):
        engine.checkRecipient(to, coin, network: network);
    }
    final keyless = family.encodeKeylessInput(request);
    checkKeylessInput(keyless, family);
    _keysDerived += derivations.length;
    return withDerivedKeys(
      derivations,
      (handles) => core.sign(
        keyless,
        family: family,
        coin: request.coin,
        requiredRoles: roles,
        keys: handles,
        usedKeys: const <KeyLocator>{},
      ),
    );
  }

  /// Signs the message [request] with the keys [keys] name, and returns the
  /// parsed signature with empty `usedKeys` (see [MessageSigned]).
  ///
  /// [_sign]'s order with the recipient check replaced by the shape check,
  /// and every property of it: nothing before step 5 of [_sign] runs after a
  /// key exists, the keys are derived in one scope, lent to the core, and
  /// released before the reply. In this order:
  ///
  /// 1. **Encode** the key-less input ([MessageFamily.encodeKeylessInput]),
  ///    which also refuses a shape this SDK does not sign — an EIP-155
  ///    variant — with [UnsupportedOperationError], first, so that the answer
  ///    does not depend on the keys.
  /// 2. **Resolve** [keys] against the family's roles ([_resolveKeys], shared
  ///    with [_sign]), then the wallet and path of each locator.
  /// 3. **Check** the key-less bytes ([checkKeylessInput]).
  /// 4. **Derive**, **sign** through the core's message path
  ///    ([MessageSigningCore.signMessage]), and **release**.
  ///
  /// A failure at steps 1–3 derives nothing and does not reach the core.
  SignResult _signMessage(
    SigningCore core,
    MessageRequest request,
    Set<LocatorSpec> keys,
  ) {
    // A defect, not an input's fault: a core handed to the handler that signs
    // transactions only cannot be asked for a message.
    final messageCore = core is MessageSigningCore
        ? core as MessageSigningCore
        : throw StateError('the signing core cannot sign messages');
    final family = familyForMessage(request);
    final keyless = family.encodeKeylessInput(request);
    final roles = family.requiredRoles(request);
    final locators = _resolveKeys(request.coin, roles, keys);
    final derivations = <KeyRole, KeyDerivation>{};
    for (final MapEntry(key: role, value: locator) in locators.entries) {
      final wallet = _resolve(locator.walletRef);
      final path = checkDerivationPath(locator.derivationPath);
      derivations[role] = KeyDerivation(wallet, locator.coin, path);
    }
    checkKeylessInput(keyless, family);
    _keysDerived += derivations.length;
    return withDerivedKeys(
      derivations,
      (handles) => messageCore.signMessage(
        keyless,
        family: family,
        coin: request.coin,
        requiredRoles: roles,
        keys: handles,
        usedKeys: const <KeyLocator>{},
      ),
    );
  }

  /// Resolves [keys] for a request on [coin] and returns the HD locator that
  /// fills each of [required] — the family's roles for the request, in the
  /// family's order, which the result keeps — or throws, in this order, so
  /// that the answer
  /// does not depend on the set's iteration order:
  ///
  /// 1. An [ExternalLocatorSpec] anywhere: [UnsupportedOperationError] for
  ///    capability `'external-signer'`.
  /// 2. An [HdLocatorSpec] whose session token is not this executor's:
  ///    [KeyResolutionError], [KeyResolutionReason.foreignRef].
  /// 3. An [ImportedLocatorSpec] anywhere:
  ///    [KeyResolutionError], [KeyResolutionReason.noKeyForAccount]. No
  ///    import exists at this version, so no [KeyRef] names a key here.
  /// 4. Roles. A locator with no role fills the family's only slot; in a
  ///    family with several it fills none. A locator whose role the family
  ///    does not require, or whose role another locator already fills, is
  ///    [KeyResolutionReason.unusedLocator]; a required role left unfilled
  ///    is [KeyResolutionReason.missingRole] — an empty set included. Equal
  ///    locators are one locator.
  /// 5. A locator whose coin is not the request's: [InvalidInputError]
  ///    (`inputName: 'keys'`). The coin selects upstream's derivation and
  ///    curve, and a key derived for another coin is not this request's.
  ///
  /// The wallet reference itself is resolved by the caller, through the same
  /// table lookup every other operation uses.
  Map<KeyRole, HdLocatorSpec> _resolveKeys(
    Coin coin,
    List<KeyRole> required,
    Set<LocatorSpec> keys,
  ) {
    final unique = keys.toSet();
    if (unique.any((key) => key is ExternalLocatorSpec)) {
      throw UnsupportedOperationError(coin, 'external-signer');
    }
    for (final key in unique) {
      if (key is HdLocatorSpec && key.sessionToken != _sessionToken) {
        throw const KeyResolutionError(
          'a key locator names a wallet of another session',
          reason: KeyResolutionReason.foreignRef,
        );
      }
    }
    if (unique.any((key) => key is ImportedLocatorSpec)) {
      throw const KeyResolutionError(
        'no imported key exists in this session at this version',
        reason: KeyResolutionReason.noKeyForAccount,
      );
    }

    final filled = <KeyRole, HdLocatorSpec>{};
    for (final key in unique.whereType<HdLocatorSpec>()) {
      final role = key.role ?? (required.length == 1 ? required.single : null);
      if (role == null) {
        throw const KeyResolutionError(
          'a key locator names no role, and this transaction has several',
          reason: KeyResolutionReason.unusedLocator,
        );
      }
      if (!required.contains(role)) {
        throw KeyResolutionError(
          'no key of role ${role.id} is used by this transaction',
          reason: KeyResolutionReason.unusedLocator,
        );
      }
      if (filled.containsKey(role)) {
        throw KeyResolutionError(
          'more than one key locator fills the role ${role.id}',
          reason: KeyResolutionReason.unusedLocator,
        );
      }
      filled[role] = key;
    }
    for (final role in required) {
      if (!filled.containsKey(role)) {
        throw KeyResolutionError(
          'no key locator fills the role ${role.id}',
          reason: KeyResolutionReason.missingRole,
        );
      }
    }
    for (final key in filled.values) {
      if (key.coin != coin) {
        throw InvalidInputError(
          'a key locator is for ${key.coin.id} and the transaction for '
          '${coin.id}',
          inputName: 'keys',
        );
      }
    }
    return <KeyRole, HdLocatorSpec>{
      for (final role in required) role: filled[role]!,
    };
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

  @override
  void discard(WorkerReply reply) {
    if (reply is! WalletCreated) return;
    try {
      _wallets.remove(reply.walletRef)?.dispose();
    } on Object {
      // Never throws: the native finalizer stays attached to anything this
      // failed to release, and shutdown releases the rest.
    }
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
