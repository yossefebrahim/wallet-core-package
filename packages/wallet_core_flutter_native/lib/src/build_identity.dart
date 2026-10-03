/// Reading `wcf_build_info()` out of a loaded library.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
library;

import 'dart:convert';
import 'dart:ffi';

import 'errors.dart';
import 'generated/manifest.dart' show identitySymbol;

/// The C signature of the build-identity symbol.
typedef _BuildInfoNative = Pointer<Uint8> Function();
typedef _BuildInfoDart = Pointer<Uint8> Function();

/// A hard bound on the identity string, so a library that returns a pointer
/// into something that is not a NUL-terminated string fails instead of being
/// scanned to the end of the address space.
///
/// The real string is around 120 bytes; 64 KiB is four hundred times that and
/// still nowhere near a page walk.
const int _maxIdentityBytes = 64 * 1024;

/// What the loaded library says it is.
///
/// The three keys of DECISION-14 §2.1, parsed out of the JSON that
/// `wcf_build_info()` returns. Unknown keys are ignored on purpose: the format
/// may gain a field without breaking an older loader.
///
/// This type is a *claim*, not a proof. It says which build the library
/// asserts it is, and comparing it against the manifest (see
/// `verify_identity.dart`) is what turns the claim into a check. Nothing here
/// hashes the library file — see [BuildIdentity.read].
final class BuildIdentity {
  const BuildIdentity({
    required this.upstreamCommit,
    required this.artifactSetId,
    required this.buildWorkflow,
  });

  /// The upstream commit the C API in this image came from — 40 lowercase hex,
  /// validated on parse.
  final String upstreamCommit;

  /// The id of the artifact set this binary belongs to, e.g. `as_4.8.0_001`.
  ///
  /// Not format-checked here. The build workflow allocates it and the manifest
  /// validator checks its shape; a loader that also enforced the shape would
  /// reject a set id it merely did not recognise, turning a naming change into
  /// a load failure on every device.
  final String artifactSetId;

  /// The workflow run that produced the binary — the human-readable end of the
  /// provenance chain. A locally built development library carries something
  /// else (`local`), which is fine: this field is never compared.
  final String buildWorkflow;

  /// Reads and parses the identity from [library].
  ///
  /// Throws [NativeLoadError] when [symbol] is absent, when the returned
  /// pointer is null, or when what it points at is not the identity JSON
  /// DECISION-14 §2.1 specifies. All of those mean the loaded library is not
  /// one of ours, which DECISION-14 §2.3 makes a load failure rather than a
  /// mismatch.
  ///
  /// **The returned pointer is never freed.** It is static storage owned by
  /// the library, valid for the lifetime of the loaded image, and it is *not*
  /// a `TWString` — upstream's delete functions must never be called on it
  /// (`src/identity/wcf_build_info.h`). This function copies the bytes into a
  /// Dart string and forgets the pointer.
  ///
  /// **The library file is never hashed.** Reading this symbol is the whole
  /// integrity check at load time; see `WalletCoreNative` for why.
  static BuildIdentity read(
    DynamicLibrary library, {
    String symbol = identitySymbol,
  }) {
    if (!library.providesSymbol(symbol)) {
      throw NativeLoadError(
        'the loaded library does not export "$symbol", so it is not an '
        'artifact of this project (DECISION-14 §2.3)',
      );
    }

    final Pointer<Uint8> pointer;
    try {
      pointer = library
          .lookupFunction<_BuildInfoNative, _BuildInfoDart>(symbol)
          .call();
    } on Object catch (e) {
      throw NativeLoadError(
        'calling "$symbol" in the loaded library failed',
        cause: e,
      );
    }

    if (pointer == nullptr) {
      throw NativeLoadError('"$symbol" returned a null pointer');
    }
    return parse(_readNulTerminated(pointer, symbol), symbol: symbol);
  }

  /// Parses the identity JSON.
  ///
  /// Separate from [read] so every parse rule is testable without a library:
  /// a string is the whole input.
  static BuildIdentity parse(String json, {String symbol = identitySymbol}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (e) {
      throw NativeLoadError(
        '"$symbol" did not return JSON: ${e.message}',
        cause: e,
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw NativeLoadError(
        '"$symbol" must return a JSON object, got '
        '${decoded == null ? 'null' : decoded.runtimeType}',
      );
    }

    final commit = _requiredString(decoded, 'upstream_commit', symbol);
    if (!_isCommit(commit)) {
      throw NativeLoadError(
        '"$symbol" reported an upstream_commit that is not 40 lowercase hex '
        'digits: "$commit"',
      );
    }
    return BuildIdentity(
      upstreamCommit: commit,
      artifactSetId: _requiredString(decoded, 'artifact_set_id', symbol),
      buildWorkflow: _requiredString(decoded, 'build_workflow', symbol),
    );
  }

  @override
  String toString() =>
      'BuildIdentity(artifactSetId: $artifactSetId, '
      'upstreamCommit: $upstreamCommit, buildWorkflow: $buildWorkflow)';

  static final RegExp _commit = RegExp(r'^[0-9a-f]{40}$');

  static bool _isCommit(String value) => _commit.hasMatch(value);

  static String _requiredString(
    Map<String, Object?> json,
    String key,
    String symbol,
  ) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      throw NativeLoadError(
        value == null
            ? '"$symbol" returned no "$key" key'
            : '"$symbol" returned a "$key" that is not a non-empty string',
      );
    }
    return value;
  }
}

/// Copies the NUL-terminated UTF-8 string at [pointer] into a Dart string.
///
/// Bounded by [_maxIdentityBytes] and strict about UTF-8: both are properties
/// of data crossing the boundary from a library that may not be ours, and
/// "untrusted in both directions" is the rule (threat model §4).
String _readNulTerminated(Pointer<Uint8> pointer, String symbol) {
  var length = 0;
  while (length < _maxIdentityBytes && pointer[length] != 0) {
    length++;
  }
  if (length == _maxIdentityBytes) {
    throw NativeLoadError(
      '"$symbol" returned a string with no NUL terminator within '
      '$_maxIdentityBytes bytes',
    );
  }
  final bytes = pointer.asTypedList(length);
  try {
    return utf8.decode(bytes);
  } on FormatException catch (e) {
    throw NativeLoadError(
      '"$symbol" returned bytes that are not valid UTF-8: ${e.message}',
      cause: e,
    );
  }
}
