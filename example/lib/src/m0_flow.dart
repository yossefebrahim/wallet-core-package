/// The M0 flow: its state, and every call the example makes into the SDK.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// The only SDK import is `package:wallet_core_flutter/wallet_core_flutter.dart`
/// — the public surface (AGENTS.md rules 4 and 12): no `advanced.dart`, no
/// `dart:ffi`, no generated or protobuf type, no `CoinType`. Nothing here
/// logs. A mnemonic is held only while it is on screen, and the text typed
/// for an import only as long as the field shows it.
library;

import 'package:flutter/foundation.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';

/// Starts a session: [WalletCore.initialize] in the app. A test passes the
/// SDK's internal test entry point instead, because the public call takes no
/// library path (threat model TM-13).
typedef SessionStarter = Future<WalletCore> Function();

/// The strengths [WalletFacade.create] accepts, as its doc comment lists them.
/// The public surface does not export the list.
const List<int> mnemonicStrengths = <int>[128, 160, 192, 224, 256];

/// The stable name of [error]'s public type. An exhaustive switch over the
/// sealed hierarchy, so a new error type is a compile error here, and
/// independent of `runtimeType`, which an obfuscated release build renames.
String errorTypeName(WalletCoreException error) => switch (error) {
  UnknownCoinError() => 'UnknownCoinError',
  InvalidInputError() => 'InvalidInputError',
  UnsupportedOperationError() => 'UnsupportedOperationError',
  SigningError() => 'SigningError',
  KeyResolutionError() => 'KeyResolutionError',
  DisposedError() => 'DisposedError',
  ClosedError() => 'ClosedError',
  WorkerTerminatedError() => 'WorkerTerminatedError',
  NativeLoadError() => 'NativeLoadError',
  ManifestMismatchError() => 'ManifestMismatchError',
  SessionStateError() => 'SessionStateError',
  QueueFullError() => 'QueueFullError',
  OperationTimeoutError() => 'OperationTimeoutError',
  OperationCancelledError() => 'OperationCancelledError',
};

/// One line of a step's result. Public data only.
typedef Fact = ({String label, String value});

/// Why a step ended without a result.
@immutable
final class StepError {
  /// An error the SDK raised: its public type name, its message (which never
  /// contains a secret — the SDK's error contract), and what else the type
  /// carries that a developer can act on.
  StepError.sdk(WalletCoreException error)
    : title = errorTypeName(error),
      lines = <String>[
        error.message,
        if (error is InvalidInputError && error.inputName != null)
          'input: ${error.inputName}',
        if (error is ManifestMismatchError) 'check: ${error.check.name}',
        if (error is NativeLoadError)
          for (final attempt in error.attempts) 'tried $attempt',
      ];

  /// A step the app refused before calling the SDK.
  StepError.app(String reason) : title = 'Not sent', lines = [reason];

  /// The public error type name, or `Not sent`.
  final String title;

  /// The details.
  final List<String> lines;
}

/// What a step shows once it has run.
@immutable
final class StepOutcome {
  /// A step that completed.
  const StepOutcome.done(this.facts) : error = null;

  /// A step that failed.
  const StepOutcome.failed(StepError this.error) : facts = const <Fact>[];

  /// The result, when the step completed.
  final List<Fact> facts;

  /// The failure, when it did not.
  final StepError? error;
}

/// The live check of the mnemonic being typed for an import. Positions and
/// counts only: never a word.
@immutable
final class ImportCheck {
  /// The answer for a text of [wordCount] words.
  const ImportCheck({
    required this.wordCount,
    required this.unknownWords,
    required this.incompleteWord,
    required this.isValid,
  }) : error = null;

  /// The check itself failed.
  const ImportCheck.failed(StepError this.error)
    : wordCount = 0,
      unknownWords = const <int>[],
      incompleteWord = null,
      isValid = false;

  /// How many words were typed.
  final int wordCount;

  /// 1-based positions of words `mnemonics.isValidWord` rejected.
  final List<int> unknownWords;

  /// The 1-based position of the last word when it is still being typed and
  /// `mnemonics.suggest` has candidates for it; `null` otherwise.
  final int? incompleteWord;

  /// What `mnemonics.isValid` said about the whole text.
  final bool isValid;

  /// Why the check could not run.
  final StepError? error;
}

/// Which wallet steps 4 and 5 use.
enum WalletChoice {
  /// The wallet step 2 created.
  created,

  /// The wallet step 3 imported.
  imported,
}

/// The fields of the EIP-1559 transfer step 5 signs, as typed.
///
/// The defaults are the request of the repository's test vector
/// `ethereum-sign-eip1559-1` (test_vectors/ethereum/vectors.yaml; upstream
/// tests/chains/Ethereum/TWAnySignerTests.cpp at d692ac2), chain id 3 being
/// Ropsten, a deprecated testnet: a transaction signed here is not valid on
/// mainnet. The vector's own key is a raw private key, which this public-
/// surface example has no way to use, so the bytes produced differ from the
/// vector's; the request is the same.
final class TransferForm {
  /// The vector's request, as text.
  TransferForm();

  /// EIP-155 chain id.
  String chainId = '3';

  /// The sender's transaction count.
  String nonce = '6';

  /// The recipient.
  String to = '0xB9F5771C27664bF2282D98E09D7F50cEc7cB01a7';

  /// Value in wei.
  String valueWei = '543210987654321';

  /// EIP-1559 fee cap per gas, in wei.
  String maxFeePerGas = '3000000000';

  /// EIP-1559 priority fee per gas, in wei.
  String maxPriorityFeePerGas = '2000000000';

  /// Gas limit.
  String gasLimit = '21100';
}

/// Why the app refused a step before calling the SDK: a form field that is
/// not a whole number, or a step run out of order.
final class _NotSent implements Exception {
  const _NotSent(this.reason);

  final String reason;
}

/// The M0 flow's state, one step at a time, for the page to render.
final class M0Flow extends ChangeNotifier {
  /// A flow whose step 1 calls [startSession].
  M0Flow({this._startSession = WalletCore.initialize});

  final SessionStarter _startSession;

  WalletCore? _core;
  bool _busy = false;
  bool _disposed = false;

  Wallet? _created;
  Wallet? _imported;
  String? _shownMnemonic;
  bool _mnemonicExported = false;
  int _importCheckGeneration = 0;
  KeyLocator? _signingKey;

  /// Step 1's result.
  StepOutcome? initialized;

  /// The session's state when step 1 returned, then every state its
  /// `states` stream reported, in order. The `closed` state is delivered
  /// before `shutdown()` returns, though the page receives it asynchronously.
  final List<SessionState> states = <SessionState>[];

  /// The strength step 2 creates a wallet with.
  int strength = mnemonicStrengths.first;

  /// Step 2's result.
  StepOutcome? created;

  /// The reveal's result: how many words were shown, or why not.
  StepOutcome? revealed;

  /// The live check of the import text.
  ImportCheck? importCheck;

  /// Step 3's result.
  StepOutcome? imported;

  /// The wallet steps 4 and 5 use.
  WalletChoice choice = WalletChoice.created;

  /// Step 4's result.
  StepOutcome? derived;

  /// Step 5's request fields.
  final TransferForm form = TransferForm();

  /// Step 5's result.
  StepOutcome? signed;

  /// Step 6's result for the wallets.
  StepOutcome? walletsClosed;

  /// Step 6's result for the session.
  StepOutcome? shutDown;

  /// Whether a step is running.
  bool get isBusy => _busy;

  /// The session's state, or `null` before one exists.
  SessionState? get state => _core?.state;

  /// Whether the session accepts operations.
  bool get isReady => _core?.state == SessionState.ready;

  /// Whether a session has ended, so a new one may start.
  bool get hasEnded =>
      _core?.state == SessionState.closed ||
      _core?.state == SessionState.failed;

  /// Whether there is a created wallet whose mnemonic has not been shown yet.
  bool get canReveal => _created != null && !_mnemonicExported && isReady;

  /// The created wallet's mnemonic, while it is on screen; `null` otherwise.
  String? get shownMnemonic => _shownMnemonic;

  /// Whether a wallet exists for [choice].
  bool hasWallet(WalletChoice choice) => _walletFor(choice) != null;

  /// Whether step 5 has a key to sign with.
  bool get hasSigningKey => _signingKey != null;

  // --- Step 1 ---------------------------------------------------------------

  /// `WalletCore.initialize()`. A failure — `NativeLoadError` or
  /// `ManifestMismatchError` — returns no session, and is shown as the step's
  /// state; nothing needs closing.
  Future<void> initialize() => _run((o) => initialized = o, () async {
    if (_core != null) {
      throw const _NotSent('a session exists; shut it down and start over');
    }
    final core = await _startSession();
    _core = core;
    states
      ..clear()
      ..add(core.state);
    core.states.listen((state) {
      states.add(state);
      _notify();
    });
    return [(label: 'SessionState', value: core.state.name)];
  });

  // --- Step 2 ---------------------------------------------------------------

  /// Picks the strength step 2 creates a wallet with.
  void chooseStrength(int bits) {
    strength = bits;
    _notify();
  }

  /// `wallets.create(strength:)`. The mnemonic does not come back from this
  /// call; [revealMnemonic] asks for it, once.
  Future<void> createWallet() => _run((o) => created = o, () async {
    final core = _requireSession();
    await _created?.close();
    _created = null;
    _shownMnemonic = null;
    _mnemonicExported = false;
    revealed = null;
    final wallet = await core.wallets.create(strength: strength);
    _created = wallet;
    choice = WalletChoice.created;
    return [
      (label: 'wallet', value: '$wallet'),
      (label: 'strength', value: '$strength bits'),
      (
        label: 'mnemonic',
        value: 'not returned by create(); reveal it once with exportMnemonic()',
      ),
    ];
  });

  /// `wallet.exportMnemonic()` on the created wallet — once. The app shows the
  /// words until [hideMnemonic] and never asks again (PRD §11.3: display it
  /// once and drop the reference).
  Future<void> revealMnemonic() => _run((o) => revealed = o, () async {
    final wallet = _created;
    if (wallet == null) throw const _NotSent('create a wallet first');
    if (_mnemonicExported) {
      throw const _NotSent('the mnemonic has already been shown once');
    }
    final mnemonic = await wallet.exportMnemonic();
    _mnemonicExported = true;
    _shownMnemonic = mnemonic;
    return [
      (label: 'exportMnemonic()', value: '${_countWords(mnemonic)} words'),
    ];
  });

  /// Drops the app's only reference to the shown mnemonic.
  void hideMnemonic() {
    _shownMnemonic = null;
    revealed = const StepOutcome.done([
      (
        label: 'exportMnemonic()',
        value: 'shown once and dropped; this app will not show it again',
      ),
    ]);
    _notify();
  }

  // --- Step 3 ---------------------------------------------------------------

  /// Checks [text] as it is typed: each word with `mnemonics.isValidWord`, a
  /// last word still being typed with `mnemonics.suggest`, the whole with
  /// `mnemonics.isValid`. Shows counts and positions, never a word.
  Future<void> checkImportText(String text) async {
    final generation = ++_importCheckGeneration;
    final core = _core;
    final words = _words(text);
    if (core == null || !isReady || words.isEmpty) {
      importCheck = null;
      _notify();
      return;
    }
    ImportCheck check;
    try {
      final unknown = <int>[];
      int? incomplete;
      for (var i = 0; i < words.length; i++) {
        if (await core.mnemonics.isValidWord(words[i])) continue;
        final isLast = i == words.length - 1;
        if (isLast &&
            !_endsWithSpace(text) &&
            (await core.mnemonics.suggest(words[i])).isNotEmpty) {
          incomplete = i + 1;
        } else {
          unknown.add(i + 1);
        }
      }
      check = ImportCheck(
        wordCount: words.length,
        unknownWords: unknown,
        incompleteWord: incomplete,
        isValid: await core.mnemonics.isValid(text),
      );
    } on WalletCoreException catch (error) {
      check = ImportCheck.failed(StepError.sdk(error));
    }
    // A later keystroke started a newer check; this answer is stale.
    if (generation != _importCheckGeneration) return;
    importCheck = check;
    _notify();
  }

  /// `wallets.importMnemonic(text)`. Returns whether a wallet was imported,
  /// so the page can clear its field: the app keeps no copy of the text.
  Future<bool> importWallet(String text) async {
    var ok = false;
    await _run((o) => imported = o, () async {
      final core = _requireSession();
      await _imported?.close();
      _imported = null;
      final wallet = await core.wallets.importMnemonic(text);
      _imported = wallet;
      choice = WalletChoice.imported;
      ok = true;
      _importCheckGeneration++;
      importCheck = null;
      return [
        (label: 'wallet', value: '$wallet'),
        (label: 'mnemonic', value: 'cleared from the field'),
      ];
    });
    return ok;
  }

  // --- Step 4 ---------------------------------------------------------------

  /// Picks the wallet steps 4 and 5 use.
  void choose(WalletChoice value) {
    choice = value;
    _notify();
  }

  /// `wallet.account(Coin.ethereum, path:)` — the default path when [path]
  /// is empty. Remembers the key it names for step 5 as a `KeyLocator`.
  Future<void> deriveAddress(String path) => _run((o) => derived = o, () async {
    _requireSession();
    final wallet = _walletFor(choice);
    if (wallet == null) {
      throw _NotSent('there is no ${choice.name} wallet yet');
    }
    final trimmed = path.trim();
    final account = await wallet.account(
      Coin.ethereum,
      path: trimmed.isEmpty ? null : trimmed,
    );
    _signingKey = KeyLocator.hdPath(
      wallet.ref,
      account.coin,
      account.derivationPath,
    );
    return [
      (label: 'wallet', value: '$wallet'),
      (label: 'coin', value: '${account.coin.name} (${account.coin.id})'),
      (label: 'network', value: account.network.id),
      (label: 'style', value: account.addressStyle.id),
      (label: 'path', value: account.derivationPath),
      (label: 'address', value: account.address.value),
      (
        label: 'public key',
        value: '${account.publicKey.length} bytes, ${_hex(account.publicKey)}',
      ),
    ];
  });

  // --- Step 5 ---------------------------------------------------------------

  /// Builds an `EvmTransactionRequest` from [form] — key-less, validated at
  /// construction — and signs it with `signer.sign(request, {locator})`, the
  /// locator naming step 4's key. Shows the `EvmSignResult`'s fields.
  Future<void> signTransfer() => _run((o) => signed = o, () async {
    final core = _requireSession();
    final key = _signingKey;
    if (key == null) {
      throw const _NotSent('derive an address in step 4 first');
    }
    final request = EvmTransactionRequest.transfer(
      coin: Coin.ethereum,
      chainId: _int('chainId', form.chainId),
      nonce: _bigInt('nonce', form.nonce),
      to: form.to.trim(),
      valueWei: _bigInt('valueWei', form.valueWei),
      maxFeePerGas: _bigInt('maxFeePerGas', form.maxFeePerGas),
      maxPriorityFeePerGas: _bigInt(
        'maxPriorityFeePerGas',
        form.maxPriorityFeePerGas,
      ),
      gasLimit: _bigInt('gasLimit', form.gasLimit),
    );
    final result = await core.signer.sign(request, {key});
    // Sealed and per family: an exhaustive switch, no common `encoded`.
    return switch (result) {
      EvmSignResult() => [
        (label: 'result', value: 'EvmSignResult (${result.coin.id})'),
        (label: 'encoded', value: '${result.encoded.length} bytes'),
        (label: 'encoded hex', value: _hex(result.encoded)),
        (label: 'v', value: _hex(result.v)),
        (label: 'r', value: _hex(result.r)),
        (label: 's', value: _hex(result.s)),
        if (result.preHash case final preHash?)
          (label: 'pre-hash', value: _hex(preHash)),
        (label: 'usedKeys', value: result.usedKeys.join(', ')),
      ],
    };
  });

  // --- Step 6 ---------------------------------------------------------------

  /// `close()` on every wallet the flow holds; each awaits the owner's
  /// acknowledgement.
  Future<void> closeWallets() => _run((o) => walletsClosed = o, () async {
    final facts = <Fact>[];
    for (final (name, wallet) in [
      ('created', _created),
      ('imported', _imported),
    ]) {
      if (wallet == null) continue;
      await wallet.close();
      facts.add((label: '$name wallet', value: '$wallet'));
    }
    _shownMnemonic = null;
    if (facts.isEmpty) throw const _NotSent('there is no wallet to close');
    return facts;
  });

  /// `shutdown()`: releases everything the session holds and ends it.
  ///
  /// The leak tracker's report is not on the public surface, so the app
  /// shows the session's states instead (see the README).
  Future<void> shutdown() => _run((o) => shutDown = o, () async {
    final core = _core;
    if (core == null) throw const _NotSent('there is no session');
    await core.shutdown();
    _shownMnemonic = null;
    return [
      (label: 'SessionState', value: core.state.name),
      (
        label: 'leak-tracker report',
        value: 'not on the public surface (see README)',
      ),
    ];
  });

  /// Forgets the ended session so step 1 can start a new one.
  void startOver() {
    if (isReady) return;
    _core = null;
    _created = null;
    _imported = null;
    _shownMnemonic = null;
    _mnemonicExported = false;
    _signingKey = null;
    _importCheckGeneration++;
    initialized = created = revealed = imported = derived = signed = null;
    walletsClosed = shutDown = null;
    importCheck = null;
    states.clear();
    choice = WalletChoice.created;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _shownMnemonic = null;
    // Leaving the page ends the session; nothing is left to report to.
    if (isReady || state == SessionState.failed) _core?.shutdown().ignore();
    super.dispose();
  }

  // --- Plumbing -------------------------------------------------------------

  /// Runs one step: marks the flow busy, and records what [body] returned or
  /// the typed error it threw.
  Future<void> _run(
    void Function(StepOutcome outcome) record,
    Future<List<Fact>> Function() body,
  ) async {
    if (_busy) return;
    _busy = true;
    _notify();
    try {
      record(StepOutcome.done(await body()));
    } on WalletCoreException catch (error) {
      record(StepOutcome.failed(StepError.sdk(error)));
    } on _NotSent catch (problem) {
      record(StepOutcome.failed(StepError.app(problem.reason)));
    } finally {
      _busy = false;
      _notify();
    }
  }

  WalletCore _requireSession() {
    final core = _core;
    if (core == null) throw const _NotSent('start a session in step 1');
    return core;
  }

  Wallet? _walletFor(WalletChoice choice) => switch (choice) {
    WalletChoice.created => _created,
    WalletChoice.imported => _imported,
  };

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

final RegExp _whitespace = RegExp(r'\s+');

List<String> _words(String text) =>
    text.trim().split(_whitespace).where((w) => w.isNotEmpty).toList();

int _countWords(String text) => _words(text).length;

bool _endsWithSpace(String text) =>
    text.isNotEmpty && text.substring(text.length - 1).trim().isEmpty;

int _int(String name, String text) =>
    int.tryParse(text.trim()) ??
    (throw _NotSent('$name is not a whole number'));

BigInt _bigInt(String name, String text) =>
    BigInt.tryParse(text.trim()) ??
    (throw _NotSent('$name is not a whole number'));

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
