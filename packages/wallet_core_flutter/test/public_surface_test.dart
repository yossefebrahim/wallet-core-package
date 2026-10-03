// What each library of this package exports — a stopgap for the public-API
// lint of T1.15, which will check signatures rather than export lines.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/advanced.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';

final RegExp _export = RegExp(r"^export\s+'([^']+)'", multiLine: true);

List<String> _exports(String path) => _export
    .allMatches(File(path).readAsStringSync())
    .map((m) => m[1]!)
    .toList();

/// The type names no public signature of the default import may contain:
/// the generated coin registry, the foreign-function layer, protobuf.
final RegExp _forbiddenType = RegExp(
  r'\b(CoinType|CoinInfo|Derivation|Explorer|coinInfo|TW[A-Z]\w*|Pointer|'
  r'NativeType|Opaque|Struct|DynamicLibrary|GeneratedMessage|Int64|'
  r'ProtobufEnum|NativeContext|NativeResource|TWDataHandle|TWStringHandle)\b',
);

/// Every source file the default import exports from `src/`, and every
/// `part` file of those, by path.
Map<String, String> _exportedFiles() {
  final files = <String, String>{};
  for (final uri in _exports('lib/wallet_core_flutter.dart')) {
    if (!uri.startsWith('src/')) continue;
    final path = 'lib/$uri';
    final source = File(path).readAsStringSync();
    files[path] = source;
    final directory = File(path).parent.path;
    for (final part in RegExp(
      r"^part\s+'([^']+)'",
      multiLine: true,
    ).allMatches(source)) {
      final partPath = '$directory/${part[1]}';
      files[partPath] = File(partPath).readAsStringSync();
    }
  }
  return files;
}

/// Every name a `show` clause of [path]'s exports names.
Set<String> _shownNames(String path) {
  final source = File(path).readAsStringSync();
  return {
    for (final match in RegExp(
      r"^export\s+'[^']+'\s+show\s+([^;]+);",
      multiLine: true,
    ).allMatches(source))
      ...match[1]!.split(',').map((name) => name.trim()),
  };
}

/// The signatures of the public declarations [source] makes visible through
/// [shown]: top-level declarations whose name is shown, and the public
/// members of shown classes, each up to where its body or initializer
/// begins. Comments and string literals are stripped first. A text scan,
/// standing in for T1.15's analyzer-based lint.
List<String> _publicSignatures(String source, Set<String> shown) {
  final text = source
      .replaceAll(RegExp(r'//[^\n]*'), '')
      .replaceAll(RegExp(r"'''[\s\S]*?'''"), "''")
      .replaceAll(RegExp(r"'(?:[^'\\\n]|\\.)*'"), "''");
  final signatures = <String>[];
  var depth = 0;
  var parens = 0;
  var inShownClass = false;
  final statement = StringBuffer();
  var cut = false;

  /// Records the statement collected so far; returns whether it was a class
  /// header, whose `{` opens members rather than a body.
  bool finish() {
    final declaration = statement.toString().trim().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    statement.clear();
    if (declaration.isEmpty) return false;
    final classMatch = RegExp(
      r'\b(?:class|enum|mixin|extension type)\s+(\w+)',
    ).firstMatch(declaration);
    if (depth == 0 && classMatch != null) {
      inShownClass = shown.contains(classMatch[1]);
      return true;
    }
    final name = RegExp(r'(\w+)\s*(?:\(|$)').firstMatch(declaration)?[1];
    if (name == null || name.startsWith('_')) return false;
    if (RegExp(r'\b\w+\._\w*\s*\(').hasMatch(declaration)) return false;
    if (depth == 0 && !shown.contains(name)) return false;
    if (depth == 1 && !inShownClass) return false;
    signatures.add(declaration);
    return false;
  }

  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (depth <= 1 && !cut) {
      if (char == '(') parens++;
      if (char == ')') parens--;
      if (parens > 0) {
        // Inside a parameter list: braces are named parameters, not a body.
        statement.write(char);
        continue;
      }
      final atBodyOrValue =
          parens == 0 &&
          (char == '{' ||
              char == ';' ||
              (char == '=' && i + 1 < text.length && text[i + 1] != '='));
      if (atBodyOrValue) {
        final classHeader = finish();
        cut = char != ';' && !classHeader;
      } else {
        statement.write(char);
      }
    }
    if (char == '{') depth++;
    if (char == '}') {
      depth--;
      if (depth == 0) inShownClass = false;
      if (depth <= 1) {
        cut = false;
        parens = 0;
        statement.clear();
      }
    }
    if (char == ';' && depth <= 1) {
      cut = false;
      statement.clear();
    }
  }
  return signatures;
}

void main() {
  test('the default import exports no engine, binding, registry or ffi '
      'library', () {
    final exports = _exports('lib/wallet_core_flutter.dart');
    expect(exports, isNotEmpty);
    for (final uri in exports) {
      expect(uri, isNot(contains('engine')), reason: uri);
      expect(uri, isNot(contains('dart:ffi')), reason: uri);
      expect(uri, isNot(contains('wallet_core_flutter_bindings')), reason: uri);
      expect(uri, isNot(contains('generated')), reason: uri);
    }
    // The native package contributes exactly the ManifestCheck enum.
    expect(
      File('lib/wallet_core_flutter.dart').readAsStringSync(),
      contains("wallet_core_flutter_native.dart'\n    show ManifestCheck;"),
    );
  });

  test('the session surface is exported, and none of its machinery', () {
    final exports = _exports('lib/wallet_core_flutter.dart');
    for (final uri in exports) {
      // The protocol, the executor, the transport, the session
      // implementation and the test seam stay internal.
      expect(uri, isNot(contains('worker')), reason: uri);
      expect(uri, isNot(contains('testing')), reason: uri);
      expect(uri, isNot(endsWith('session/session.dart')), reason: uri);
      expect(uri, isNot(endsWith('session/scope.dart')), reason: uri);
    }
    // Every export names what it exports, so an implementation class
    // declared beside a public interface (WalletProxy, WalletFacadeImpl,
    // AddressFacadeImpl, ...) cannot leak by accident.
    final source = File('lib/wallet_core_flutter.dart').readAsStringSync();
    final exportCount = _export.allMatches(source).length;
    expect(
      RegExp(
        r"^export\s+'[^']+'\s+show\b",
        multiLine: true,
      ).allMatches(source).length,
      exportCount,
    );
    // Compiles only if these are reachable from the default import.
    expect(<Type>[
      WalletCore,
      Wallet,
      WalletRef,
      WalletFacade,
      AddressFacade,
      MnemonicFacade,
      OperationTimeouts,
      SessionScope,
      SessionState,
    ], hasLength(9));
  });

  test('the signing surface is exported, and none of its machinery', () {
    final source = File('lib/wallet_core_flutter.dart').readAsStringSync();
    final exports = _exports('lib/wallet_core_flutter.dart');
    for (final uri in exports) {
      // The family boundary, the signing core, the key-field check and the
      // session-backed implementation stay internal.
      expect(uri, isNot(contains('families')), reason: uri);
      expect(uri, isNot(endsWith('signing_core.dart')), reason: uri);
      expect(uri, isNot(endsWith('key_field_check.dart')), reason: uri);
      expect(uri, isNot(endsWith('local_signer.dart')), reason: uri);
    }
    for (final internal in [
      'issueKeyRef',
      'keyRefNumber',
      'withUsedKeys',
      'SessionSigner',
      'SigningCore',
      'TransactionFamily',
      'KeyFieldList',
      'KeyFieldEntry',
      'LocatorSpec',
    ]) {
      expect(
        RegExp('\\b$internal\\b').hasMatch(source),
        isFalse,
        reason: internal,
      );
    }
    // Compiles only if these are reachable from the default import.
    expect(<Type>[
      Signer,
      LocalSigner,
      KeyLocator,
      HdKeyLocator,
      ImportedKeyLocator,
      ExternalKeyLocator,
      KeyRole,
      KeyRef,
      TransactionRequest,
      MessageRequest,
      EvmTransactionRequest,
      SignResult,
      EvmSignResult,
      KeyResolutionReason,
    ], hasLength(14));
    expect(ChainFamily.evm.hasRequestBuilders, isTrue);
  });

  test('no file the default import exports — part files included — declares '
      'a synchronous dispose, imports dart:ffi, or names a generated or '
      'protobuf type', () {
    final files = _exportedFiles();
    expect(
      files.keys,
      contains('lib/src/requests/evm/evm_transaction_request.dart'),
      reason: 'part files are read too',
    );
    final dispose = RegExp(r'^\s*void\s+dispose\s*\(', multiLine: true);
    for (final MapEntry(key: path, value: source) in files.entries) {
      expect(dispose.hasMatch(source), isFalse, reason: path);
      expect(source, isNot(contains("import 'dart:ffi'")), reason: path);
      expect(source, isNot(contains('.pb.dart')), reason: path);
      expect(source, isNot(contains('Pointer<')), reason: path);
    }
  });

  test('no public signature of an exported declaration names a registry, '
      'foreign-function, or protobuf type', () {
    final shown = _shownNames('lib/wallet_core_flutter.dart');
    final scanned = <String>[
      for (final MapEntry(key: path, value: source) in _exportedFiles().entries)
        for (final signature in _publicSignatures(source, shown))
          '$path: $signature',
    ];
    // The scan reaches real declarations, the part file's included.
    expect(scanned.length, greaterThan(100));
    expect(
      scanned,
      contains(
        'lib/src/requests/evm/evm_transaction_request.dart: final BigInt nonce',
      ),
    );
    expect(scanned.where((s) => s.contains('Coin get coin')), isNotEmpty);
    expect(scanned.where(_forbiddenType.hasMatch), isEmpty);
  });

  test('the signature scan finds what it is for (self-check)', () {
    const fixture = '''
final class Shown {
  final CoinType? _private;
  final CoinType leaked;
  CoinInfo get info => _x;
  void take(int a, {required TWCoinType coin}) {}
  static const Shown x = Shown._(CoinType.bitcoin);
  void ok() { final CoinType local = CoinType.bitcoin; }
}
final class Hidden { final CoinType alsoFine; }
CoinType helper(Coin coin) => coin._type;
''';
    final flagged = _publicSignatures(fixture, {
      'Shown',
    }).where(_forbiddenType.hasMatch).toList();
    expect(flagged, hasLength(3), reason: flagged.join('\n'));
    expect(flagged.join('\n'), contains('leaked'));
    expect(flagged.join('\n'), contains('get info'));
    expect(flagged.join('\n'), contains('TWCoinType coin'));
  });

  test('both imports together are unambiguous', () {
    // Compiles only if no name is exported by both libraries from different
    // declarations; the values are incidental.
    expect(packageName, 'wallet_core_flutter');
    expect(HDWallet, isNotNull);
    expect(CoinType.ethereum.coinId, 60);
    expect(TWCoinType.TWCoinTypeEthereum.value, 60);
    expect(const DisposedError('HDWallet'), isA<WalletCoreException>());
    expect(Coin.ethereum.id, 'ethereum');
  });
}
