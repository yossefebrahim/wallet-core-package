/// The [SessionScope] behind `WalletCore.scope`. **Internal.**
library;

import 'dart:typed_data';

import '../errors/errors.dart';
import '../wallet/wallet.dart';
import 'session.dart';
import 'wallet_core.dart';

/// Runs [body] with a fresh scope over [session] and closes everything the
/// scope created, in reverse order of creation, on return and on throw
/// (PRD §11.2 item 6).
///
/// A creation still in flight when [body] ends is awaited and its wallet
/// closed too. A creation that failed has nothing to close.
Future<T> runInScope<T>(
  WalletCoreSession session,
  Future<T> Function(SessionScope scope) body,
) async {
  final scope = _Scope(session);
  final T result;
  try {
    result = await body(scope);
  } on Object {
    // The body's error is the one the caller sees; closing errors do not
    // replace it.
    await scope._closeAll();
    rethrow;
  }
  final closeError = await scope._closeAll();
  if (closeError != null) throw closeError;
  return result;
}

final class _Scope implements SessionScope {
  _Scope(this._session);

  final WalletCoreSession _session;

  /// Every creation, in submission order.
  final List<Future<Wallet>> _created = <Future<Wallet>>[];
  bool _ended = false;

  @override
  Future<Wallet> createWallet({int strength = 128, String passphrase = ''}) =>
      _track(
        () =>
            _session.wallets.create(strength: strength, passphrase: passphrase),
      );

  @override
  Future<Wallet> importMnemonic(String mnemonic, {String passphrase = ''}) =>
      _track(
        () => _session.wallets.importMnemonic(mnemonic, passphrase: passphrase),
      );

  @override
  Future<Wallet> importEntropy(Uint8List entropy, {String passphrase = ''}) =>
      _track(
        () => _session.wallets.importEntropy(entropy, passphrase: passphrase),
      );

  Future<Wallet> _track(Future<Wallet> Function() create) {
    if (_ended) return Future<Wallet>.error(const ClosedError('SessionScope'));
    final created = create();
    // A failed creation the body never awaited must not surface as an
    // uncaught error; the body sees it if it awaits.
    created.ignore();
    _created.add(created);
    return created;
  }

  /// Closes every wallet in reverse order of creation and returns the first
  /// error a close raised, or `null`.
  Future<Object?> _closeAll() async {
    _ended = true;
    Object? firstError;
    for (final created in _created.reversed) {
      final Wallet wallet;
      try {
        wallet = await created;
      } on Object {
        continue;
      }
      try {
        await wallet.close();
      } on Object catch (error) {
        firstError ??= error;
      }
    }
    _created.clear();
    return firstError;
  }
}
