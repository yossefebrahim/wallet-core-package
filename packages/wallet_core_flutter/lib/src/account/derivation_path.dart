/// The derivation-path grammar check that runs before a path reaches native
/// code (PRD §16 S5). **Internal**: never exported.
///
/// A purely syntactic check. Deriving a key at the path is upstream's job, and
/// nothing here computes one (AGENTS.md rule 2).
library;

import '../core/input_checks.dart';
import '../errors/errors.dart';

/// The deepest path accepted. BIP-32 stores depth in one byte.
const int maxDerivationPathDepth = 255;

/// The first index value that is not representable without the hardened bit.
const int _hardenedOffset = 0x80000000;

/// Returns [path] when it is a well-formed BIP-32 path, and throws
/// [InvalidInputError] (`inputName: 'derivationPath'`) otherwise.
///
/// The grammar is `m` followed by one to [maxDerivationPathDepth] components
/// `/<index>` or `/<index>'`, where `<index>` is a decimal number below 2³¹
/// written without leading zeros. That is the form the pinned registry writes
/// every default path in (`m/44'/60'/0'/0/0`), and it rejects, for example,
/// `m/44/60/invalid`.
///
/// The message never quotes the path.
String checkDerivationPath(String path) {
  final problem = _problem(path);
  if (problem != null) {
    throw InvalidInputError(
      'not a valid BIP-32 derivation path: $problem',
      inputName: 'derivationPath',
    );
  }
  return path;
}

/// Whether [path] passes [checkDerivationPath], without throwing.
bool isValidDerivationPath(String path) => _problem(path) == null;

String? _problem(String path) {
  if (path.length > maxDerivationPathLength) {
    return 'longer than $maxDerivationPathLength characters';
  }
  if (!path.startsWith('m/')) return "it must start with 'm/'";
  final components = path.substring(2).split('/');
  if (components.length > maxDerivationPathDepth) {
    return 'deeper than $maxDerivationPathDepth levels';
  }
  for (var i = 0; i < components.length; i++) {
    final component = components[i];
    final digits = component.endsWith("'")
        ? component.substring(0, component.length - 1)
        : component;
    if (digits.isEmpty || digits.length > 10) {
      return 'component ${i + 1} is not an index';
    }
    for (var j = 0; j < digits.length; j++) {
      final unit = digits.codeUnitAt(j);
      if (unit < 0x30 || unit > 0x39) {
        return 'component ${i + 1} is not an index';
      }
    }
    if (digits.length > 1 && digits.codeUnitAt(0) == 0x30) {
      return 'component ${i + 1} has a leading zero';
    }
    if (int.parse(digits) >= _hardenedOffset) {
      return 'component ${i + 1} is not below 2^31';
    }
  }
  return null;
}
