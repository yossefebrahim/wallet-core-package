/// [KeyLocator], [KeyRole], and [KeyRef]: how a caller names a key without
/// carrying it (`docs/architecture/signing.md` §2, DECISION-13 §4.2).
///
/// Nothing here holds key material, and nothing here can: a locator is a name
/// — a wallet reference and a path, an imported-key reference, or a device id
/// and a public key — and every `toString()` renders the name only.
library;

import 'dart:typed_data';

import '../coin/coin.dart';
import '../errors/errors.dart';
import '../wallet/wallet.dart' show WalletRef;

/// Names a key without carrying it.
///
/// A locator crosses the isolate boundary as plain data. Resolving it into an
/// actual key happens only inside the isolate that owns the wallet, only for
/// the duration of one operation.
///
/// Locators are values: two locators naming the same key in the same role are
/// equal, so a duplicate in a `Set<KeyLocator>` is harmless.
sealed class KeyLocator {
  /// Which slot of the operation this key fills. When omitted, a family with a
  /// single key slot assigns it implicitly; a family with several slots
  /// requires it explicitly.
  KeyRole? get role;

  /// A key derived from a session-owned wallet at an explicit path.
  ///
  /// [derivationPath] is the full BIP-32 path, e.g. `"m/44'/60'/0'/0/0"`. It
  /// is checked when the locator is resolved, not here.
  const factory KeyLocator.hdPath(
    WalletRef wallet,
    Coin coin,
    String derivationPath, {
    KeyRole? role,
  }) = HdKeyLocator;

  /// A key imported into the session, for example from an encrypted keystore.
  const factory KeyLocator.imported(KeyRef key, {KeyRole? role}) =
      ImportedKeyLocator;

  /// A key held by an external signing device.
  ///
  /// **Reserved.** Declared in 1.0 so that adding external signing later is not
  /// a breaking change to this sealed hierarchy. Every 1.0 signer rejects it
  /// with [UnsupportedOperationError] for capability `'external-signer'`.
  ///
  /// [publicKey] is copied; the caller's list is not retained.
  factory KeyLocator.external(
    String deviceId,
    Uint8List publicKey, {
    KeyRole? role,
  }) = ExternalKeyLocator;
}

/// A key derived from a session-owned HD wallet at an explicit path.
final class HdKeyLocator implements KeyLocator {
  /// Names the key of [wallet] at [derivationPath] for [coin].
  const HdKeyLocator(this.wallet, this.coin, this.derivationPath, {this.role});

  /// The wallet the key is derived from. Valid only in its own session.
  final WalletRef wallet;

  /// The coin whose curve and conventions the key is derived for.
  final Coin coin;

  /// The full BIP-32 derivation path.
  final String derivationPath;

  @override
  final KeyRole? role;

  @override
  bool operator ==(Object other) =>
      other is HdKeyLocator &&
      other.wallet == wallet &&
      other.coin == coin &&
      other.derivationPath == derivationPath &&
      other.role == role;

  @override
  int get hashCode => Object.hash(wallet, coin, derivationPath, role);

  /// The wallet reference's number, the coin, the path, and the role. A path
  /// is not a secret; the key it leads to is never rendered, because it is
  /// never here.
  @override
  String toString() =>
      'HdKeyLocator($wallet, ${coin.id}, $derivationPath${_roleSuffix(role)})';
}

/// A key imported into the session, named by its opaque [KeyRef].
final class ImportedKeyLocator implements KeyLocator {
  /// Names the imported key [key].
  const ImportedKeyLocator(this.key, {this.role});

  /// The session-scoped reference to the imported key.
  final KeyRef key;

  @override
  final KeyRole? role;

  @override
  bool operator ==(Object other) =>
      other is ImportedKeyLocator && other.key == key && other.role == role;

  @override
  int get hashCode => Object.hash(key, role);

  @override
  String toString() => 'ImportedKeyLocator($key${_roleSuffix(role)})';
}

/// A key held by an external signing device. **Reserved**: every 1.0 signer
/// rejects it with [UnsupportedOperationError] (`'external-signer'`).
final class ExternalKeyLocator implements KeyLocator {
  /// Names the key with [publicKey] on the device [deviceId]. [publicKey] is
  /// copied.
  ExternalKeyLocator(this.deviceId, Uint8List publicKey, {this.role})
    : _publicKey = Uint8List.fromList(publicKey);

  /// The device's identifier, as the device reports it.
  final String deviceId;

  final Uint8List _publicKey;

  /// The public key of the key on the device. A read-only view; the locator
  /// keeps its own copy.
  Uint8List get publicKey => _publicKey.asUnmodifiableView();

  @override
  final KeyRole? role;

  @override
  bool operator ==(Object other) {
    if (other is! ExternalKeyLocator ||
        other.deviceId != deviceId ||
        other.role != role ||
        other._publicKey.length != _publicKey.length) {
      return false;
    }
    for (var i = 0; i < _publicKey.length; i++) {
      if (other._publicKey[i] != _publicKey[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(deviceId, role, Object.hashAll(_publicKey));

  /// The device id and the public key's *length*. The key's bytes are public,
  /// but `docs/architecture/signing.md` grants no rendering of them, so none
  /// is made.
  @override
  String toString() =>
      'ExternalKeyLocator($deviceId, publicKey: ${_publicKey.length} bytes'
      '${_roleSuffix(role)})';
}

/// The slot a key fills in an operation.
///
/// Equal by [id], so a role that crossed an isolate boundary by copy is equal
/// to the constant it was.
final class KeyRole {
  const KeyRole._(this.id);

  /// Stable id: `'primary'`, `'feePayer'`, or `'input:<n>'`.
  final String id;

  /// The transaction's own signer. The only role most chains have.
  static const KeyRole primary = KeyRole._('primary');

  /// A separate account paying the fee, where the chain supports one.
  static const KeyRole feePayer = KeyRole._('feePayer');

  /// The key for transaction input number [n] of a UTXO spend.
  ///
  /// Throws [InvalidInputError] (`inputName: 'n'`) when [n] is negative.
  static KeyRole input(int n) {
    if (n < 0) {
      throw const InvalidInputError(
        'an input index must not be negative',
        inputName: 'n',
      );
    }
    return KeyRole._('input:$n');
  }

  @override
  bool operator ==(Object other) => other is KeyRole && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'KeyRole($id)';
}

/// An opaque, session-scoped reference to an imported key. Not a key.
///
/// There is no public way to make one at this version: the keystore import
/// that issues them is a later task. Equal by identity.
final class KeyRef {
  const KeyRef._(this._id);

  final int _id;

  /// The reference's number within its session. Not a secret, not a key.
  @override
  String toString() => 'KeyRef(#$_id)';
}

/// A new [KeyRef] numbered [id]. **Internal**: for the session that issues
/// imported-key references, and for tests; never exported.
KeyRef issueKeyRef(int id) => KeyRef._(id);

/// The number [ref] carries, as it crosses to the executor. **Internal**;
/// never exported.
int keyRefNumber(KeyRef ref) => ref._id;

String _roleSuffix(KeyRole? role) => role == null ? '' : ', role: ${role.id}';
