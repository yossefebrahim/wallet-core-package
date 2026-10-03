/// Dart-side input validation that runs before any native call (PRD §16 S5).
/// **Internal**: never exported.
///
/// Every check here is syntactic — a length, a count, a set of allowed values.
/// None of them is BIP-39 or BIP-32 logic: whether a mnemonic's checksum holds
/// or a key derives is upstream's answer, asked for only once these pass
/// (AGENTS.md rule 2).
///
/// Every rejection is an [InvalidInputError] that names the input and never
/// quotes it, because most of what passes through here is a secret (threat
/// model TM-09, TM-31).
library;

import 'dart:typed_data';

import '../errors/errors.dart';

/// The mnemonic strengths, in bits, BIP-39 defines.
const List<int> mnemonicStrengths = <int>[128, 160, 192, 224, 256];

/// The entropy lengths, in bytes, BIP-39 defines — [mnemonicStrengths] / 8.
const List<int> entropyLengths = <int>[16, 20, 24, 28, 32];

/// The mnemonic lengths, in words, BIP-39 defines.
const List<int> mnemonicWordCounts = <int>[12, 15, 18, 21, 24];

/// Ceiling on a mnemonic's length in UTF-16 code units.
///
/// A 24-word English mnemonic is at most 24 × 8 letters and 23 separators,
/// 215 characters. The ceiling more than doubles that to tolerate stray
/// whitespace, and stops a hostile input from becoming a large allocation.
const int maxMnemonicLength = 512;

/// Ceiling on a BIP-39 passphrase's length in UTF-16 code units. BIP-39 sets
/// none; this bounds what crosses into native code.
const int maxPassphraseLength = 1024;

/// Ceiling on an address string's length in UTF-16 code units — several times
/// the longest address any registry chain writes.
const int maxAddressLength = 512;

/// Ceiling on a derivation path's length in UTF-16 code units.
const int maxDerivationPathLength = 1024;

/// Ceiling on a single mnemonic word or word prefix. The longest BIP-39
/// English word has 8 letters.
const int maxMnemonicWordLength = 64;

/// Whether [value] arrives in native code exactly as written.
///
/// Every string reaches upstream as NUL-terminated UTF-8, so two kinds of
/// text would silently become *different* text on the way: a U+0000 ends the
/// C string early, and an unpaired UTF-16 surrogate has no UTF-8 encoding and
/// is replaced with U+FFFD. Either way upstream would answer for an input the
/// caller never gave — for a mnemonic or a passphrase, a different wallet with
/// no error at all. Such a string is rejected here, never repaired.
bool isNativeSafeString(String value) {
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    if (unit == 0) return false;
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      // A high surrogate must be followed by a low one.
      if (i + 1 >= value.length) return false;
      final next = value.codeUnitAt(i + 1);
      if (next < 0xDC00 || next > 0xDFFF) return false;
      i++;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      // A low surrogate with no high one before it.
      return false;
    }
  }
  return true;
}

/// Throws [InvalidInputError] (`inputName:` [inputName]) unless [value]
/// passes [isNativeSafeString]. The message never quotes the value.
void checkNativeString(String value, {required String inputName}) {
  if (!isNativeSafeString(value)) {
    throw InvalidInputError(
      '$inputName contains a NUL character or an unpaired UTF-16 surrogate, '
      'which cannot reach native code unchanged',
      inputName: inputName,
    );
  }
}

/// Throws [InvalidInputError] unless [strength] is one of
/// [mnemonicStrengths].
void checkStrength(int strength) {
  if (!mnemonicStrengths.contains(strength)) {
    throw InvalidInputError(
      'strength must be one of ${mnemonicStrengths.join(', ')} bits; '
      'got $strength',
      inputName: 'strength',
    );
  }
}

/// Throws [InvalidInputError] unless [entropy] has one of the
/// [entropyLengths]. The bytes are never read, only counted.
void checkEntropy(Uint8List entropy) {
  if (!entropyLengths.contains(entropy.length)) {
    throw InvalidInputError(
      'entropy must be ${entropyLengths.join(', ')} bytes long',
      inputName: 'entropy',
    );
  }
}

/// Throws [InvalidInputError] when [passphrase] exceeds
/// [maxPassphraseLength] or fails [isNativeSafeString].
void checkPassphrase(String passphrase) {
  if (passphrase.length > maxPassphraseLength) {
    throw const InvalidInputError(
      'passphrase is longer than $maxPassphraseLength characters',
      inputName: 'passphrase',
    );
  }
  checkNativeString(passphrase, inputName: 'passphrase');
}

/// Throws [InvalidInputError] unless [mnemonic] is within
/// [maxMnemonicLength], has one of the [mnemonicWordCounts], and passes
/// [isNativeSafeString].
///
/// Whitespace-separated words are counted; nothing is normalised and no copy
/// is made — upstream receives the caller's text unchanged and decides whether
/// it is a valid mnemonic.
void checkMnemonicShape(String mnemonic) {
  if (mnemonic.isEmpty ||
      mnemonic.length > maxMnemonicLength ||
      !mnemonicWordCounts.contains(_countWords(mnemonic))) {
    throw InvalidInputError(
      'a mnemonic must have ${mnemonicWordCounts.join(', ')} words and at '
      'most $maxMnemonicLength characters',
      inputName: 'mnemonic',
    );
  }
  checkNativeString(mnemonic, inputName: 'mnemonic');
}

/// Whether [mnemonic] passes [checkMnemonicShape], without throwing.
bool mnemonicHasPlausibleShape(String mnemonic) {
  if (mnemonic.isEmpty || mnemonic.length > maxMnemonicLength) return false;
  return mnemonicWordCounts.contains(_countWords(mnemonic)) &&
      isNativeSafeString(mnemonic);
}

int _countWords(String text) {
  var words = 0;
  var inWord = false;
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    final isSpace =
        unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D;
    if (isSpace) {
      inWord = false;
    } else if (!inWord) {
      inWord = true;
      words++;
    }
  }
  return words;
}
