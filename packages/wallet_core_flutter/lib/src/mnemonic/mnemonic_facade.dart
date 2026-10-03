/// [MnemonicFacade]: BIP-39 mnemonic checks and word suggestions, through the
/// session.
library;

import '../core/input_checks.dart';
import '../session/session.dart';
import '../worker/protocol.dart';

/// Mnemonic helpers for a session. Obtained from `WalletCore.mnemonics`.
///
/// Every answer is upstream's, asked in the session's owning isolate
/// (DECISION-12 §1), for the BIP-39 English word list.
///
/// **What is being checked is usually a secret.** A mnemonic typed in to be
/// validated is very likely somebody's real one, and a word or a prefix is
/// part of one. Each crosses to the owning isolate only when a local check
/// cannot already answer — a text with the wrong number of words, a word
/// longer than any in the list, a prefix with a character no word has — and
/// is handled there like the secrets of an import: never logged, never put
/// into an error, not kept once answered. The SDK cannot erase the caller's
/// copy.
abstract interface class MnemonicFacade {
  /// Whether [mnemonic] is a valid BIP-39 English mnemonic: known words, a
  /// supported length, a correct checksum. Never throws for any input.
  Future<bool> isValid(String mnemonic);

  /// Whether [word] is in the BIP-39 English word list. Never throws for any
  /// input.
  Future<bool> isValidWord(String word);

  /// The BIP-39 English words that start with [prefix], in upstream's order.
  ///
  /// Upstream caps how many words it suggests, so this is a typing aid, not
  /// access to the whole list. A prefix that cannot begin a word — empty,
  /// too long, or containing anything but `a`–`z` — yields an empty list.
  Future<List<String>> suggest(String prefix);
}

/// The [MnemonicFacade] of [WalletCoreSession]. **Internal.**
final class MnemonicFacadeImpl implements MnemonicFacade {
  /// Creates the facade over [session].
  MnemonicFacadeImpl(this._session);

  final WalletCoreSession _session;

  @override
  Future<bool> isValid(String mnemonic) async {
    _session.checkReady('mnemonics.isValid');
    if (!mnemonicHasPlausibleShape(mnemonic)) return false;
    return _session.submit(
      (id) => ValidateMnemonic(id, mnemonic),
      timeout: _session.timeouts.derivation,
      parse: (reply) => switch (reply) {
        MnemonicValidated(:final isValid) => isValid,
        _ => throw StateError('unexpected reply ${reply.runtimeType}'),
      },
    );
  }

  @override
  Future<bool> isValidWord(String word) async {
    _session.checkReady('mnemonics.isValidWord');
    if (word.isEmpty ||
        word.length > maxMnemonicWordLength ||
        !isNativeSafeString(word)) {
      return false;
    }
    return _session.submit(
      (id) => ValidateMnemonicWord(id, word),
      timeout: _session.timeouts.derivation,
      parse: (reply) => switch (reply) {
        MnemonicWordValidated(:final isValid) => isValid,
        _ => throw StateError('unexpected reply ${reply.runtimeType}'),
      },
    );
  }

  @override
  Future<List<String>> suggest(String prefix) async {
    _session.checkReady('mnemonics.suggest');
    if (prefix.isEmpty || prefix.length > maxMnemonicWordLength) {
      return const <String>[];
    }
    for (var i = 0; i < prefix.length; i++) {
      final unit = prefix.codeUnitAt(i);
      if (unit < 0x61 || unit > 0x7A) return const <String>[];
    }
    return _session.submit(
      (id) => SuggestMnemonicWords(id, prefix),
      timeout: _session.timeouts.derivation,
      parse: (reply) => switch (reply) {
        MnemonicWordsSuggested(:final words) => words,
        _ => throw StateError('unexpected reply ${reply.runtimeType}'),
      },
    );
  }
}
