import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart';

import 'compiler_probe.dart';

const disclaimer =
    'Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.';

/// One coin's row for the message-signing question.
class MessageRow {
  final int coinId;
  final String coinName;
  final String blockchain;
  final QuestionResult result;

  /// Coin-specific message signer header for this coin's blockchain, or `null`.
  final String? specificSigner;

  const MessageRow({
    required this.coinId,
    required this.coinName,
    required this.blockchain,
    required this.result,
    required this.specificSigner,
  });
}

// ---------------------------------------------------------------------------
// Static evidence
// ---------------------------------------------------------------------------

/// Registry blockchains whose Rust `CoinEntry::message_signer()` returns
/// `Some(..)`: Ethereum (`rust/chains/tw_ethereum/src/entry.rs:98`), Ronin
/// (`tw_ronin/src/entry.rs:97`), Solana (`tw_solana/src/entry.rs:92`), Sui
/// (`tw_sui/src/entry.rs:96`).
const genericMessageSignerBlockchains = {'Ethereum', 'Ronin', 'Solana', 'Sui'};

/// Registry blockchains that reach a Rust entry (`blockchain_dispatcher`,
/// `rust/tw_coin_registry/src/dispatcher.rs:66-95`) whose `message_signer()`
/// is the trait default `None` (`rust/tw_coin_entry/src/coin_entry.rs:132`) or
/// an explicit `None` (Aptos, `tw_aptos/src/entry.rs:100`), plus blockchains with
/// no Rust entry at all (`BlockchainType::Unsupported`, `dispatcher.rs:94`).
/// Every registry blockchain outside [genericMessageSignerBlockchains] is
/// therefore unsupported by the generic `TWMessageSigner*` functions.
bool genericMessageStatic(String blockchain) {
  if (blockchain == 'unknown') return false;
  return genericMessageSignerBlockchains.contains(blockchain);
}

/// Coin-specific message signer by registry blockchain name. Matching is by
/// blockchain family name only; forks and EVM look-alikes are not inferred.
/// `TWStarkExMessageSigner` has no registry coin of its own, so no coin maps to it.
String? coinSpecificSigner(String blockchain) => switch (blockchain) {
  'Ethereum' => 'TWEthereumMessageSigner',
  'Bitcoin' => 'TWBitcoinMessageSigner',
  'Tezos' => 'TWTezosMessageSigner',
  'Tron' => 'TWTronMessageSigner',
  'TheOpenNetwork' => 'TWTONMessageSigner',
  _ => null,
};

// ---------------------------------------------------------------------------
// Runtime evidence
// ---------------------------------------------------------------------------

abstract interface class MessageSignerNative {
  /// `null` when upstream returned a null pointer.
  Uint8List? sign(int coinId, Uint8List input);
  Uint8List? preImageHashes(int coinId, Uint8List input);
  bool verify(int coinId, Uint8List input);
}

/// Runs the minimal message-signer calls for one coin (empty input is a valid
/// empty protobuf message, so a coin with a signer parses it and answers).
Map<String, CallObservation> observeMessageSigner(
  MessageSignerNative native,
  int coinId, {
  void Function(String call)? onCall,
}) {
  final empty = Uint8List(0);
  final calls = <String, CallObservation>{};
  void observe(String name, CallObservation Function() call) {
    onCall?.call(name);
    calls[name] = call();
  }

  CallObservation bytes(Uint8List? b) =>
      b == null ? CallObservation.nullPointer() : CallObservation.bytes(b);
  observe('sign_empty', () => bytes(native.sign(coinId, empty)));
  observe('preimage_empty', () => bytes(native.preImageHashes(coinId, empty)));
  observe(
    'verify_empty',
    () => CallObservation.boolean(native.verify(coinId, empty)),
  );
  return calls;
}

/// Classifies one coin's message-signing observations.
///
/// * `supported` — `TWMessageSignerSign` or `TWMessageSignerPreImageHashes`
///   returned a non-null `TWData` (upstream returns null for
///   `Error_not_supported`, an unsupported blockchain and an unparsable input;
///   `rust/tw_any_coin/src/ffi/tw_message_signer.rs:22-66`).
/// * `unsupported` — both returned null on an empty (valid) input.
/// * `crash` — the child process died.
///
/// `TWMessageSignerVerify` only returns a bool (`false` for every failure), so
/// it is recorded but never decides the class.
({String label, bool? supported, String? crash}) classifyMessageRuntime(
  ChildOutcome outcome,
) {
  if (outcome.isCrash) {
    return (label: 'crash', supported: null, crash: outcome.crashDetail);
  }
  final calls = outcome.calls!;
  final reached = [
    'sign_empty',
    'preimage_empty',
  ].any((k) => calls[k] != null && !calls[k]!.isNull);
  return reached
      ? (label: 'supported', supported: true, crash: null)
      : (label: 'unsupported', supported: false, crash: null);
}

MessageRow messageRow({
  required int coinId,
  required String coinName,
  required String blockchain,
  required ChildOutcome outcome,
}) {
  final runtime = classifyMessageRuntime(outcome);
  return MessageRow(
    coinId: coinId,
    coinName: coinName,
    blockchain: blockchain,
    specificSigner: coinSpecificSigner(blockchain),
    result: QuestionResult(
      staticSupported: genericMessageStatic(blockchain),
      runtimeClass: runtime.label,
      runtimeSupported: runtime.supported,
      crashDetail: runtime.crash,
    ),
  );
}

Future<List<MessageRow>> probeMessageSignerViaChildren({
  required String executable,
  required String script,
  required String libPath,
  int concurrency = 8,
}) async {
  final blockchains = registryBlockchains();
  final coins = TWCoinType.values.toList();
  return mapConcurrent(coins, concurrency, (coin) async {
    final outcome = await runChild(
      executable: executable,
      script: script,
      libPath: libPath,
      coinId: coin.value,
      part: 'message',
    );
    return messageRow(
      coinId: coin.value,
      coinName: coin.name,
      blockchain: blockchains[coin.value] ?? 'unknown',
      outcome: outcome,
    );
  });
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

/// Renders the whole evidence document from both probes' rows. Pure and
/// deterministic: rows are sorted by coin id; no timestamps, no paths.
String renderCoverageMarkdown(
  List<CompilerRow> compilerRows,
  List<MessageRow> messageRows, {
  required String upstreamTag,
  required String upstreamCommit,
  required String libraryCommit,
  required String artifactSetId,
  required String librarySha256,
}) {
  final compiler = List<CompilerRow>.from(compilerRows)
    ..sort((a, b) => a.coinId.compareTo(b.coinId));
  final messages = {for (final r in messageRows) r.coinId: r};

  final buffer = StringBuffer()
    ..writeln('# Transaction compiler and message signing coverage probe')
    ..writeln()
    ..writeln(disclaimer)
    ..writeln()
    ..writeln('**Upstream Pin:** Tag $upstreamTag, Commit `$upstreamCommit`')
    ..writeln()
    ..writeln(
      '**Library Checked:** Artifact Set `$artifactSetId`, Commit `$libraryCommit`, SHA-256 `$librarySha256`',
    )
    ..writeln()
    ..writeln('**Command:** `melos run probe:coverage`')
    ..writeln()
    ..write(_methodSection)
    ..writeln('## Totals')
    ..writeln()
    ..write(
      renderQuestionTotals(
        'Transaction compiler',
        compiler.map((r) => r.result),
      ),
    )
    ..writeln()
    ..write(
      renderQuestionTotals(
        'Generic message signer (`TWMessageSigner*`)',
        compiler.map((r) => messages[r.coinId]!.result),
      ),
    )
    ..writeln()
    ..writeln(
      '- Coins with a coin-specific message signer: ${compiler.where((r) => messages[r.coinId]!.specificSigner != null).length}',
    )
    ..writeln()
    ..writeln('## Coverage Table')
    ..writeln()
    ..writeln(
      '| coin id | TWCoinType | compile (static) | compile (runtime) | message signing (static) | message signing (runtime) | coin-specific message signer |',
    )
    ..writeln('|---|---|---|---|---|---|---|');
  for (final c in compiler) {
    final m = messages[c.coinId]!;
    buffer.writeln(
      '| ${c.coinId} | ${c.coinName} | ${c.result.staticCell} | ${c.result.runtimeCell} | ${m.result.staticCell} | ${m.result.runtimeCell} | ${m.specificSigner ?? '—'} |',
    );
  }
  return buffer.toString();
}

/// The same rows as [renderCoverageMarkdown], as JSON for machine readers
/// (`tools/matrix`). Pure and deterministic: rows sorted by coin id, two-space
/// indent, a trailing newline, no timestamps or paths.
///
/// Each row carries the probe's own verdicts verbatim — `static`
/// (`supported` / `unsupported` / `unclassified`), `runtime` (the class label),
/// `agreement` (`agree` / `conflict` / `crash` / `unclassified`) and, for a
/// crash, `crash_detail` — so a reader never has to parse the Markdown cells.
String renderCoverageJson(
  List<CompilerRow> compilerRows,
  List<MessageRow> messageRows, {
  required String upstreamTag,
  required String upstreamCommit,
  required String libraryCommit,
  required String artifactSetId,
  required String librarySha256,
}) {
  Map<String, Object?> question(QuestionResult r) => {
    'static': r.staticCell,
    'runtime': r.runtimeClass,
    'agreement': r.agreement.name,
    'crash_detail': ?r.crashDetail,
  };
  final compiler = List<CompilerRow>.from(compilerRows)
    ..sort((a, b) => a.coinId.compareTo(b.coinId));
  final messages = List<MessageRow>.from(messageRows)
    ..sort((a, b) => a.coinId.compareTo(b.coinId));
  final document = <String, Object?>{
    'schema': 1,
    'upstream': {'tag': upstreamTag, 'commit': upstreamCommit},
    'library': {
      'artifact_set_id': artifactSetId,
      'commit': libraryCommit,
      'sha256': librarySha256,
    },
    'compiler': [
      for (final r in compiler)
        {
          'coin_id': r.coinId,
          'coin_type': r.coinName,
          'blockchain': r.blockchain,
          ...question(r.result),
        },
    ],
    'message': [
      for (final r in messages)
        {
          'coin_id': r.coinId,
          'coin_type': r.coinName,
          'blockchain': r.blockchain,
          ...question(r.result),
          'specific_signer': r.specificSigner,
        },
    ],
  };
  return '${const JsonEncoder.withIndent('  ').convert(document)}\n';
}

const _methodSection = '''
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

''';

// ---------------------------------------------------------------------------
// FFI implementation (used only by the child process)
// ---------------------------------------------------------------------------

class FfiMessageSignerNative implements MessageSignerNative {
  final WalletCoreBindings bindings;

  FfiMessageSignerNative(this.bindings);

  Pointer<TWData$1> _makeData(Uint8List bytes) {
    final data = bindings.TWDataCreateWithSize(bytes.length);
    if (bytes.isNotEmpty) {
      bindings.TWDataBytes(
        data,
      ).cast<Uint8>().asTypedList(bytes.length).setAll(0, bytes);
    }
    return data;
  }

  Uint8List? _takeResult(Pointer<TWData$1> result) {
    if (result == nullptr) return null;
    final length = bindings.TWDataSize(result);
    final copy = length == 0
        ? Uint8List(0)
        : Uint8List.fromList(
            bindings.TWDataBytes(result).cast<Uint8>().asTypedList(length),
          );
    bindings.TWDataDelete(result);
    return copy;
  }

  @override
  Uint8List? sign(int coinId, Uint8List input) {
    final data = _makeData(input);
    try {
      return _takeResult(
        bindings.TWMessageSignerSign(TWCoinType.fromValue(coinId), data),
      );
    } finally {
      bindings.TWDataDelete(data);
    }
  }

  @override
  Uint8List? preImageHashes(int coinId, Uint8List input) {
    final data = _makeData(input);
    try {
      return _takeResult(
        bindings.TWMessageSignerPreImageHashes(
          TWCoinType.fromValue(coinId),
          data,
        ),
      );
    } finally {
      bindings.TWDataDelete(data);
    }
  }

  @override
  bool verify(int coinId, Uint8List input) {
    final data = _makeData(input);
    try {
      return bindings.TWMessageSignerVerify(TWCoinType.fromValue(coinId), data);
    } finally {
      bindings.TWDataDelete(data);
    }
  }
}
