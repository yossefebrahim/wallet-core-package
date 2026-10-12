import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

// The generated registry is deliberately not part of the bindings' public library.
// ignore: implementation_imports
import 'package:wallet_core_flutter_bindings/src/generated/registry/coin_info.dart';
import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart';

/// What one native call returned: `isNull` for a null pointer (or a `false`
/// bool result is carried in [boolValue]), otherwise the returned bytes.
class CallObservation {
  final bool isNull;
  final Uint8List bytes;
  final bool? boolValue;

  CallObservation.bytes(this.bytes) : isNull = false, boolValue = null;
  CallObservation.nullPointer()
    : isNull = true,
      bytes = Uint8List(0),
      boolValue = null;
  CallObservation.boolean(bool value)
    : isNull = false,
      bytes = Uint8List(0),
      boolValue = value;

  Map<String, Object?> toJson() => {
    'null': isNull,
    'len': bytes.length,
    'hex': _hex(bytes.length > 256 ? bytes.sublist(0, 256) : bytes),
    'bool': ?boolValue,
  };

  static CallObservation fromJson(Map<String, Object?> json) {
    if (json['bool'] is bool) {
      return CallObservation.boolean(json['bool']! as bool);
    }
    if (json['null'] == true) return CallObservation.nullPointer();
    return CallObservation.bytes(_unhex(json['hex']! as String));
  }
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _unhex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

/// Outcome of one child process: the observed calls, or a crash description.
class ChildOutcome {
  final Map<String, CallObservation>? calls;
  final String? crashDetail;

  ChildOutcome.ok(Map<String, CallObservation> this.calls) : crashDetail = null;
  ChildOutcome.crash(String this.crashDetail) : calls = null;

  bool get isCrash => calls == null;
}

/// Verdict for one question of one coin.
enum Agreement { agree, conflict, crash, unclassified }

/// Static and runtime evidence for one question (compile, or message signing)
/// for one coin.
class QuestionResult {
  /// Static evidence: `true` supported, `false` unsupported, `null` when the
  /// coin's blockchain is in none of the rule tables.
  final bool? staticSupported;

  /// Runtime class label, e.g. `reached`, `empty`, `crash`.
  final String runtimeClass;

  /// Whether the runtime evidence says the path exists; `null` on a crash.
  final bool? runtimeSupported;
  final String? crashDetail;

  const QuestionResult({
    required this.staticSupported,
    required this.runtimeClass,
    required this.runtimeSupported,
    this.crashDetail,
  });

  Agreement get agreement {
    if (staticSupported == null) return Agreement.unclassified;
    if (runtimeSupported == null) return Agreement.crash;
    return staticSupported == runtimeSupported
        ? Agreement.agree
        : Agreement.conflict;
  }

  String get staticCell => switch (staticSupported) {
    true => 'supported',
    false => 'unsupported',
    null => 'unclassified',
  };

  String get runtimeCell {
    if (agreement == Agreement.conflict) {
      return 'conflict (static=$staticCell, runtime=$runtimeClass)';
    }
    if (runtimeSupported == null) return 'crash ($crashDetail)';
    return runtimeClass;
  }
}

/// One coin's row for the compiler question.
class CompilerRow {
  final int coinId;
  final String coinName;
  final String blockchain;
  final QuestionResult result;

  const CompilerRow({
    required this.coinId,
    required this.coinName,
    required this.blockchain,
    required this.result,
  });
}

/// `coin id` -> registry `blockchain` string, from the generated registry.
Map<int, String> registryBlockchains() => {
  for (final entry in coinInfo.entries)
    entry.key.coinId: entry.value.blockchain,
};

// ---------------------------------------------------------------------------
// Static evidence (upstream 4.8.0 source; rules are cited in the evidence file)
// ---------------------------------------------------------------------------

/// Registry blockchains whose legacy C++ `CoinEntry` overrides both
/// `preImageHashes` and `compile` (`src/<Chain>/Entry.h`), including entries
/// that inherit them: BitcoinCash from Bitcoin, Komodo from Zcash.
const cppCompilerBlockchains = {
  'Aion',
  'Algorand',
  'Bitcoin',
  'BitcoinCash',
  'BitcoinDiamond',
  'Cardano',
  'Decred',
  'EOS',
  'FIO',
  'Filecoin',
  'Groestlcoin',
  'Harmony',
  'IOST',
  'Icon',
  'IoTeX',
  'Komodo',
  'MultiversX',
  'NEAR',
  'NEO',
  'NULS',
  'Nano',
  'OasisNetwork',
  'Ontology',
  'Stellar',
  'Tezos',
  'Theta',
  'Tron',
  'Vechain',
  'Verge',
  'Zcash',
  'Zen',
};

/// Registry blockchains dispatched through `Rust::RustCoinEntry`
/// (`src/Rust/RustCoinEntry.cpp:105-126`) whose Rust entry implements
/// `preimage_hashes` and `compile` with a real compiler module.
const rustCompilerBlockchains = {
  'Aptos',
  'Binance',
  'Cosmos',
  'Ethereum',
  'Greenfield',
  'Kusama',
  'NativeEvmos',
  'NativeInjective',
  'Pactus',
  'Polkadot',
  'Polymesh',
  'Ripple',
  'Ronin',
  'Solana',
  'Sui',
  'TheOpenNetwork',
  'Thorchain',
};

/// Registry blockchains whose C++ entry does not override `preImageHashes` /
/// `compile`, so `CoinEntry.h:68,70` returns the empty default.
const cppDefaultCompilerBlockchains = {
  'Aeternity',
  'Everscale',
  'Hedera',
  'Nebulas',
  'Nervos',
  'Nimiq',
  'Waves',
  'Zilliqa',
};

/// Registry blockchains whose Rust entry is an explicit `Error_not_supported`
/// stub for both methods (`rust/chains/tw_internet_computer/src/entry.rs:82-103`).
const explicitStubCompilerBlockchains = {'InternetComputer'};

/// Static verdict for the compiler question: `true` / `false`, or `null`
/// when the blockchain is in no table.
bool? compilerStatic(String blockchain) {
  if (cppCompilerBlockchains.contains(blockchain) ||
      rustCompilerBlockchains.contains(blockchain)) {
    return true;
  }
  if (cppDefaultCompilerBlockchains.contains(blockchain) ||
      explicitStubCompilerBlockchains.contains(blockchain)) {
    return false;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Runtime evidence
// ---------------------------------------------------------------------------

/// `Common.Proto.SigningError.Error_not_supported` (`src/proto/Common.proto:71`).
const errorNotSupported = 24;

/// Top-level `(field number, varint value)` pairs of a protobuf message, or
/// `null` when the bytes are not a well-formed wire message.
List<(int, int)>? topLevelVarints(Uint8List bytes) {
  final fields = <(int, int)>[];
  var i = 0;
  (int, int)? readVarint() {
    var value = 0;
    var shift = 0;
    while (i < bytes.length) {
      final b = bytes[i++];
      if (shift < 63) value |= (b & 0x7f) << shift;
      if (b & 0x80 == 0) return (value, i);
      shift += 7;
      if (shift > 63) return null;
    }
    return null;
  }

  while (i < bytes.length) {
    final tag = readVarint();
    if (tag == null) return null;
    final field = tag.$1 >> 3;
    switch (tag.$1 & 7) {
      case 0:
        final v = readVarint();
        if (v == null) return null;
        fields.add((field, v.$1));
      case 1:
        i += 8;
      case 2:
        final len = readVarint();
        if (len == null) return null;
        i += len.$1;
      case 5:
        i += 4;
      default:
        return null;
    }
    if (i > bytes.length) return null;
  }
  return fields;
}

/// Native entry points behind a small interface so the classifier and renderer
/// are testable without the library.
abstract interface class CompilerNative {
  Uint8List preImageHashes(int coinId, Uint8List input);
  Uint8List compile(
    int coinId,
    Uint8List input,
    List<Uint8List> signatures,
    List<Uint8List> publicKeys,
  );
}

/// Four bytes that are not a well-formed protobuf message (tag varint with a
/// continuation bit set and no terminator).
final Uint8List garbageInput = Uint8List.fromList([0xff, 0xff, 0xff, 0xff]);

/// Runs the minimal compiler calls for one coin. Throws only if the native
/// call itself does; the child process turns that into a crash.
///
/// [onCall] is told the name of each call just before it starts, so a crash can
/// be attributed to the call that caused it.
Map<String, CallObservation> observeCompiler(
  CompilerNative native,
  int coinId, {
  void Function(String call)? onCall,
}) {
  final empty = Uint8List(0);
  final calls = <String, CallObservation>{};
  void observe(String name, Uint8List Function() call) {
    onCall?.call(name);
    calls[name] = CallObservation.bytes(call());
  }

  observe('preimage_empty', () => native.preImageHashes(coinId, empty));
  observe(
    'preimage_garbage',
    () => native.preImageHashes(coinId, garbageInput),
  );
  observe(
    'compile_empty',
    () => native.compile(coinId, empty, const [], const []),
  );
  observe(
    'compile_garbage',
    () => native.compile(coinId, garbageInput, const [], const []),
  );
  return calls;
}

/// Classifies one coin's compiler observations.
///
/// * `not-supported` — a call returned a serialized message carrying a
///   top-level varint equal to `Error_not_supported` (24) and no call returned
///   anything else non-empty.
/// * `reached` — some call returned non-empty bytes that are not that error: the
///   coin's compiler module produced a serialized output (including its own
///   input-validation error).
/// * `empty` — every call returned zero bytes: upstream's default `{}` for an
///   unimplemented entry, or a caught exception (indistinguishable).
/// * `crash` — the child process died.
({String label, bool? supported, String? crash}) classifyCompilerRuntime(
  ChildOutcome outcome,
) {
  if (outcome.isCrash) {
    return (label: 'crash', supported: null, crash: outcome.crashDetail);
  }
  var anyNonEmpty = false;
  var anyOther = false;
  var anyNotSupported = false;
  for (final call in outcome.calls!.values) {
    if (call.bytes.isEmpty) continue;
    anyNonEmpty = true;
    final varints = topLevelVarints(call.bytes);
    final notSupported =
        varints != null && varints.any((f) => f.$2 == errorNotSupported);
    if (notSupported) {
      anyNotSupported = true;
    } else {
      anyOther = true;
    }
  }
  if (!anyNonEmpty) return (label: 'empty', supported: false, crash: null);
  if (anyNotSupported && !anyOther) {
    return (label: 'not-supported', supported: false, crash: null);
  }
  return (label: 'reached', supported: true, crash: null);
}

/// Builds the row for one coin from its static verdict and child outcome.
CompilerRow compilerRow({
  required int coinId,
  required String coinName,
  required String blockchain,
  required ChildOutcome outcome,
}) {
  final runtime = classifyCompilerRuntime(outcome);
  return CompilerRow(
    coinId: coinId,
    coinName: coinName,
    blockchain: blockchain,
    result: QuestionResult(
      staticSupported: compilerStatic(blockchain),
      runtimeClass: runtime.label,
      runtimeSupported: runtime.supported,
      crashDetail: runtime.crash,
    ),
  );
}

/// Totals block for one question.
String renderQuestionTotals(String title, Iterable<QuestionResult> results) {
  final list = results.toList();
  final staticYes = list.where((r) => r.staticSupported == true).length;
  final staticNo = list.where((r) => r.staticSupported == false).length;
  final staticUnclassified = list
      .where((r) => r.staticSupported == null)
      .length;
  final runtimeCounts = <String, int>{};
  for (final r in list) {
    runtimeCounts[r.runtimeClass] = (runtimeCounts[r.runtimeClass] ?? 0) + 1;
  }
  int count(Agreement a) => list.where((r) => r.agreement == a).length;
  final buffer = StringBuffer()
    ..writeln('### $title')
    ..writeln()
    ..writeln('- Coins: ${list.length}')
    ..writeln(
      '- Static: $staticYes supported, $staticNo unsupported, $staticUnclassified unclassified',
    );
  final labels = runtimeCounts.keys.toList()..sort();
  buffer.writeln(
    '- Runtime: ${labels.map((l) => '${runtimeCounts[l]} $l').join(', ')}',
  );
  buffer
    ..writeln('- Static and runtime agree: ${count(Agreement.agree)}')
    ..writeln('- Conflict: ${count(Agreement.conflict)}')
    ..writeln('- Crash (no runtime evidence): ${count(Agreement.crash)}');
  return buffer.toString();
}

// ---------------------------------------------------------------------------
// Child process isolation
// ---------------------------------------------------------------------------

/// Runs one child probe process and parses its single JSON line. A child that
/// dies by signal, exits non-zero, or prints no parsable line is a crash.
Future<ChildOutcome> runChild({
  required String executable,
  required String script,
  required String libPath,
  required int coinId,
  required String part,
}) async {
  final ProcessResult result;
  try {
    result = await Process.run(executable, [
      script,
      '--lib',
      libPath,
      '--coin',
      '$coinId',
      '--part',
      part,
    ]);
  } on ProcessException catch (e) {
    return ChildOutcome.crash('spawn failed: ${e.message}');
  }
  if (result.exitCode != 0) {
    final marker = RegExp(
      r'^call:(\w+)$',
      multiLine: true,
    ).allMatches(result.stderr.toString()).lastOrNull?.group(1);
    final how = result.exitCode < 0
        ? 'signal ${-result.exitCode}'
        : 'exit ${result.exitCode}';
    return ChildOutcome.crash(marker == null ? how : '$how in $marker');
  }
  return parseChildLine(result.stdout.toString());
}

/// Parses a child's stdout (one JSON line) into an outcome.
ChildOutcome parseChildLine(String stdout) {
  final lines = const LineSplitter()
      .convert(stdout)
      .where((l) => l.trim().isNotEmpty)
      .toList();
  if (lines.length != 1) return ChildOutcome.crash('no single json line');
  try {
    final json = jsonDecode(lines.single) as Map<String, Object?>;
    final calls = (json['calls']! as Map<String, Object?>).map(
      (k, v) =>
          MapEntry(k, CallObservation.fromJson(v! as Map<String, Object?>)),
    );
    return ChildOutcome.ok(calls);
  } on Object {
    return ChildOutcome.crash('unparsable child output');
  }
}

/// Runs [run] for every item with at most [concurrency] in flight; results keep
/// the order of [items].
Future<List<R>> mapConcurrent<T, R>(
  List<T> items,
  int concurrency,
  Future<R> Function(T item) run,
) async {
  final results = List<R?>.filled(items.length, null);
  var next = 0;
  Future<void> worker() async {
    while (true) {
      final index = next++;
      if (index >= items.length) return;
      results[index] = await run(items[index]);
    }
  }

  await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
  return results.cast<R>();
}

/// Probes every `TWCoinType` for the compiler question, one child per coin.
Future<List<CompilerRow>> probeCompilerViaChildren({
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
      part: 'compiler',
    );
    return compilerRow(
      coinId: coin.value,
      coinName: coin.name,
      blockchain: blockchains[coin.value] ?? 'unknown',
      outcome: outcome,
    );
  });
}

// ---------------------------------------------------------------------------
// FFI implementation (used only by the child process)
// ---------------------------------------------------------------------------

class FfiCompilerNative implements CompilerNative {
  final WalletCoreBindings bindings;

  FfiCompilerNative(this.bindings);

  TWCoinType _coin(int id) => TWCoinType.fromValue(id);

  Pointer<TWData$1> _makeData(Uint8List bytes) {
    final data = bindings.TWDataCreateWithSize(bytes.length);
    if (bytes.isNotEmpty) {
      bindings.TWDataBytes(
        data,
      ).cast<Uint8>().asTypedList(bytes.length).setAll(0, bytes);
    }
    return data;
  }

  Uint8List _takeResult(Pointer<TWData$1> result) {
    if (result == nullptr) return Uint8List(0);
    final length = bindings.TWDataSize(result);
    final copy = length == 0
        ? Uint8List(0)
        : Uint8List.fromList(
            bindings.TWDataBytes(result).cast<Uint8>().asTypedList(length),
          );
    bindings.TWDataDelete(result);
    return copy;
  }

  Pointer<TWDataVector> _makeVector(
    List<Uint8List> items,
    List<Pointer<TWData$1>> owned,
  ) {
    final vector = bindings.TWDataVectorCreate();
    for (final item in items) {
      final data = _makeData(item);
      owned.add(data);
      bindings.TWDataVectorAdd(vector, data);
    }
    return vector;
  }

  @override
  Uint8List preImageHashes(int coinId, Uint8List input) {
    final data = _makeData(input);
    try {
      return _takeResult(
        bindings.TWTransactionCompilerPreImageHashes(_coin(coinId), data),
      );
    } finally {
      bindings.TWDataDelete(data);
    }
  }

  @override
  Uint8List compile(
    int coinId,
    Uint8List input,
    List<Uint8List> signatures,
    List<Uint8List> publicKeys,
  ) {
    final data = _makeData(input);
    final owned = <Pointer<TWData$1>>[];
    final sigs = _makeVector(signatures, owned);
    final keys = _makeVector(publicKeys, owned);
    try {
      return _takeResult(
        bindings.TWTransactionCompilerCompileWithSignatures(
          _coin(coinId),
          data,
          sigs,
          keys,
        ),
      );
    } finally {
      bindings.TWDataVectorDelete(sigs);
      bindings.TWDataVectorDelete(keys);
      for (final d in owned) {
        bindings.TWDataDelete(d);
      }
      bindings.TWDataDelete(data);
    }
  }
}
