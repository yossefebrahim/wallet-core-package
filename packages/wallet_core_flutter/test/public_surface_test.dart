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

  test('no file the default import exports declares a synchronous dispose, '
      'imports dart:ffi, or names a generated or protobuf type', () {
    final exported = _exports('lib/wallet_core_flutter.dart')
        .where((uri) => uri.startsWith('src/'))
        .map((uri) => File('lib/$uri').readAsStringSync());
    final dispose = RegExp(r'^\s*void\s+dispose\s*\(', multiLine: true);
    for (final source in exported) {
      expect(dispose.hasMatch(source), isFalse);
      expect(source, isNot(contains("import 'dart:ffi'")));
      expect(source, isNot(contains('.pb.dart')));
      expect(source, isNot(contains('Pointer<')));
    }
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
