/// Embeds `compat_manifest.json` into `wallet_core_flutter_native`.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// Two outputs, one run (`melos run gen:manifest`):
///
///  1. `packages/wallet_core_flutter_native/lib/src/generated/manifest.dart` —
///     `const` Dart values the runtime identity check of DECISION-14 §2.3
///     compares against. Constants rather than the asset because that check
///     runs in the worker isolate during `Init` (DECISION-12 §5), where
///     `rootBundle` needs a binary messenger that does not exist there, and
///     because the loader must also work from a pure-Dart CLI.
///  2. `packages/wallet_core_flutter_native/assets/compat_manifest.json` — a
///     byte-for-byte copy of the root manifest, which is what PRD §15.3 means
///     by "shipped inside `wallet_core_flutter_native`" and what the
///     build-time fetch tool (plain Dart, no Flutter) reads from the package
///     directory.
///
/// `gen:check` diffs both, so neither can drift from the root manifest without
/// failing the gate.
///
/// This is the precursor of DECISION-14 §4.1's `embed_release_set.dart`: T3.11
/// extends it to `wallet_core_flutter` and `wallet_core_flutter_bindings` so
/// that comparison 1 (the three packages' release-set ids) has three constants
/// to compare.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Where the generated Dart file lands, relative to the native package root.
const String generatedDartRelativePath = 'lib/src/generated/manifest.dart';

/// Where the manifest copy lands, relative to the native package root.
const String assetRelativePath = 'assets/compat_manifest.json';

/// The values written into the generated Dart file.
///
/// Every field is a string exactly as `compat_manifest.json` carries it,
/// placeholders included: a `TBD-<task>` value names the task that will fill
/// it and is copied through unchanged, because a generator that substituted
/// something for a placeholder would hide the fact that the value is unknown.
final class EmbeddedManifest {
  const EmbeddedManifest({
    required this.upstreamRepo,
    required this.upstreamTag,
    required this.upstreamCommit,
    required this.identitySymbol,
    required this.identityArtifactSetId,
    required this.identityUpstreamCommit,
    required this.releaseSetId,
    required this.manifestSha256,
  });

  /// `upstream.repo`.
  final String upstreamRepo;

  /// `upstream.tag`.
  final String upstreamTag;

  /// `upstream.commit`.
  final String upstreamCommit;

  /// `identity.symbol` — the build-identity symbol's C name.
  final String identitySymbol;

  /// `identity.artifact_set_id` — comparison 3's expected value.
  final String identityArtifactSetId;

  /// `identity.upstream_commit` — comparison 4's expected value.
  final String identityUpstreamCommit;

  /// `release_set` — comparison 1's value for this package.
  final String releaseSetId;

  /// The sha256 of the manifest **file's bytes exactly as committed**, not of
  /// a re-serialisation of its JSON. See [manifestSha256Of].
  final String manifestSha256;

  /// Reads the manifest from its own bytes.
  ///
  /// The bytes are both the parse input and the hash input, so the digest can
  /// never describe a different byte sequence than the values beside it.
  factory EmbeddedManifest.fromBytes(Uint8List bytes) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException catch (e) {
      throw FormatException(
        'compat_manifest.json is not valid JSON: ${e.message}',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const FormatException(
        'compat_manifest.json must be a JSON object at the root',
      );
    }
    final upstream = _object(decoded, 'upstream');
    final identity = _object(decoded, 'identity');
    return EmbeddedManifest(
      upstreamRepo: _string(upstream, 'repo', path: 'upstream'),
      upstreamTag: _string(upstream, 'tag', path: 'upstream'),
      upstreamCommit: _string(upstream, 'commit', path: 'upstream'),
      identitySymbol: _string(identity, 'symbol', path: 'identity'),
      identityArtifactSetId: _string(
        identity,
        'artifact_set_id',
        path: 'identity',
      ),
      identityUpstreamCommit: _string(
        identity,
        'upstream_commit',
        path: 'identity',
      ),
      releaseSetId: _string(decoded, 'release_set', path: ''),
      manifestSha256: manifestSha256Of(bytes),
    );
  }

  /// Reads the manifest file at [path].
  factory EmbeddedManifest.fromFile(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('manifest not found', path);
    }
    return EmbeddedManifest.fromBytes(file.readAsBytesSync());
  }

  /// The constant name → value map, which is what the renderer emits.
  Map<String, String> get constants => <String, String>{
    'identityArtifactSetId': identityArtifactSetId,
    'identitySymbol': identitySymbol,
    'identityUpstreamCommit': identityUpstreamCommit,
    'manifestSha256': manifestSha256,
    'releaseSetId': releaseSetId,
    'upstreamCommit': upstreamCommit,
    'upstreamRepo': upstreamRepo,
    'upstreamTag': upstreamTag,
  };
}

/// The sha256 of the manifest **file's bytes**, lowercase hex.
///
/// The digest covers the file as committed — every byte, including the two
/// space indent, the key order, and the trailing newline. It is deliberately
/// *not* the digest of a canonical re-serialisation: the runtime check
/// (DECISION-14 §2.3 comparison 2) hashes the shipped asset, which is a byte
/// copy of this same file, so hashing bytes on both sides makes the comparison
/// a statement about the file rather than about two encoders agreeing. T3.11
/// embeds this same value into the other two packages and compares against the
/// same definition.
String manifestSha256Of(List<int> manifestBytes) =>
    sha256.convert(manifestBytes).toString();

/// What one [generate] run wrote.
final class EmbedResult {
  const EmbedResult({
    required this.values,
    required this.dartPath,
    required this.dartSource,
    required this.assetPath,
    required this.dartChanged,
    required this.assetChanged,
  });

  final EmbeddedManifest values;
  final String dartPath;
  final String dartSource;
  final String assetPath;

  /// Whether the file on disk differed from what this run rendered. Both are
  /// `false` on a second run over an unchanged manifest, which is what makes
  /// `gen:check` meaningful.
  final bool dartChanged;
  final bool assetChanged;
}

/// Writes both outputs for the manifest at [manifestPath] into the native
/// package rooted at [nativePackageDir].
///
/// Writes only when the rendered bytes differ from what is already there, so
/// that a no-op regeneration does not touch mtimes.
EmbedResult generate({
  required String manifestPath,
  required String nativePackageDir,
}) {
  final manifestFile = File(manifestPath);
  if (!manifestFile.existsSync()) {
    throw FileSystemException('manifest not found', manifestPath);
  }
  final bytes = manifestFile.readAsBytesSync();
  final values = EmbeddedManifest.fromBytes(bytes);
  final source = formatDartSource(renderManifestLibrary(values));

  final dartFile = File('$nativePackageDir/$generatedDartRelativePath');
  final assetFile = File('$nativePackageDir/$assetRelativePath');

  final dartChanged =
      !dartFile.existsSync() || dartFile.readAsStringSync() != source;
  if (dartChanged) {
    dartFile.parent.createSync(recursive: true);
    dartFile.writeAsStringSync(source);
  }

  final assetChanged =
      !assetFile.existsSync() ||
      !_sameBytes(assetFile.readAsBytesSync(), bytes);
  if (assetChanged) {
    assetFile.parent.createSync(recursive: true);
    assetFile.writeAsBytesSync(bytes);
  }

  return EmbedResult(
    values: values,
    dartPath: dartFile.path,
    dartSource: source,
    assetPath: assetFile.path,
    dartChanged: dartChanged,
    assetChanged: assetChanged,
  );
}

/// Runs `dart format` over [source] and returns the result.
///
/// The generator's last step, so the committed generated file passes
/// `melos run format:check` without an exclusion. It shells out to the SDK's
/// own formatter rather than importing `package:dart_style`, because
/// `format:check` runs `dart format`: using anything else would let the two
/// disagree about a line break and turn a green generator into a red gate.
///
/// `dart format` has no stdin mode, so the source goes through a temporary
/// file outside the repository.
String formatDartSource(String source) {
  final dir = Directory.systemTemp.createTempSync('wcf-embed-fmt-');
  try {
    final file = File('${dir.path}/generated.dart')..writeAsStringSync(source);
    final result = Process.runSync('dart', <String>['format', file.path]);
    if (result.exitCode != 0) {
      throw ProcessException(
        'dart',
        <String>['format', file.path],
        '${result.stdout}${result.stderr}',
        result.exitCode,
      );
    }
    return file.readAsStringSync();
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// The generated Dart source, before formatting.
///
/// Deterministic: the constants are emitted in sorted name order, so the same
/// manifest always renders the same bytes and `git diff` over the generated
/// path is about the manifest and never about ordering. [generate] passes the
/// result through [formatDartSource] before writing it.
String renderManifestLibrary(EmbeddedManifest values) {
  final buffer = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
    ..writeln('//')
    ..writeln('// Written by `melos run gen:manifest`')
    ..writeln('// (tools/manifest/bin/embed.dart) from the repository root\'s')
    ..writeln('// compat_manifest.json. Edit that file, then regenerate.')
    ..writeln()
    ..writeln(
      '/// Values embedded from `compat_manifest.json`, the integrity root of',
    )
    ..writeln('/// PRD §15.3.')
    ..writeln('///')
    ..writeln(
      '/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core',
    )
    ..writeln('/// library. Not affiliated with or endorsed by Trust Wallet.')
    ..writeln('///')
    ..writeln(
      '/// **Why constants and not the shipped asset at runtime.** The identity',
    )
    ..writeln(
      '/// and release-set check of DECISION-14 §2.3 runs in the worker isolate',
    )
    ..writeln(
      '/// during `Init`, before `initialize()` returns (DECISION-12 §5).',
    )
    ..writeln(
      '/// `rootBundle` is unavailable there: asset loading needs a binary',
    )
    ..writeln(
      '/// messenger, which a plain isolate does not have. The same loader must',
    )
    ..writeln(
      '/// also work from a pure-Dart CLI, which has no asset bundle at all. So',
    )
    ..writeln(
      '/// the few values the check needs are compiled in, and the manifest copy',
    )
    ..writeln(
      '/// under `assets/` exists for the build-time fetch tool and for PRD',
    )
    ..writeln('/// §15.3\'s "shipped inside the package".')
    ..writeln('///')
    ..writeln(
      '/// **What [manifestSha256] is.** The sha256 of `compat_manifest.json`\'s',
    )
    ..writeln(
      '/// bytes **exactly as committed** — not of a canonical re-serialisation',
    )
    ..writeln(
      '/// of its JSON. Both sides of comparison 2 therefore hash bytes: this',
    )
    ..writeln(
      '/// constant, and the asset copy, which is a byte copy of the same file.',
    )
    ..writeln(
      '/// T3.11 compares its own embedded copies against this definition.',
    )
    ..writeln('///')
    ..writeln(
      '/// A `TBD-<task>` value is a placeholder naming the task that fills it,',
    )
    ..writeln(
      '/// copied through unchanged. It means "unknown" and never compares equal',
    )
    ..writeln('/// to anything, including itself.')
    ..writeln('library;')
    ..writeln();

  final names = values.constants.keys.toList()..sort();
  for (var i = 0; i < names.length; i++) {
    if (i > 0) buffer.writeln();
    final name = names[i];
    for (final line in _docs[name]!) {
      buffer.writeln('/// $line');
    }
    buffer.writeln(
      'const String $name = ${_dartStringLiteral(values.constants[name]!)};',
    );
  }
  return buffer.toString();
}

/// Doc comment lines per constant. Kept beside the renderer so a new constant
/// cannot be emitted without one.
const Map<String, List<String>> _docs = <String, List<String>>{
  'identityArtifactSetId': <String>[
    'Manifest `identity.artifact_set_id` — the expected value of comparison 3',
    '(DECISION-14 §2.3): `wcf_build_info().artifact_set_id` must equal it.',
  ],
  'identitySymbol': <String>[
    'Manifest `identity.symbol` — the C name of the build-identity symbol the',
    'loader looks up. Its absence is a load failure, not a mismatch.',
  ],
  'identityUpstreamCommit': <String>[
    'Manifest `identity.upstream_commit` — the expected value of comparison 4',
    '(DECISION-14 §2.3): `wcf_build_info().upstream_commit` must equal it.',
  ],
  'manifestSha256': <String>[
    'The sha256 of `compat_manifest.json`\'s bytes as committed — the expected',
    'value of comparison 2 (DECISION-14 §2.3), which hashes the shipped asset',
    'copy of the same file. See this library\'s doc comment for why it is the',
    'file\'s bytes rather than a canonical re-serialisation.',
  ],
  'releaseSetId': <String>[
    'Manifest `release_set` — this package\'s side of comparison 1',
    '(DECISION-14 §2.3), which requires all three packages to carry the same',
    'value. The other two packages gain their copies in T3.11.',
  ],
  'upstreamCommit': <String>[
    'Manifest `upstream.commit` — the upstream commit this package set is',
    'generated and tested against.',
  ],
  'upstreamRepo': <String>[
    'Manifest `upstream.repo` — the upstream repository, `owner/name`.',
  ],
  'upstreamTag': <String>[
    'Manifest `upstream.tag` — the upstream release tag this set tracks.',
  ],
};

/// A single-quoted Dart string literal for [value].
///
/// Rejects control characters rather than escaping them: nothing the manifest
/// legitimately carries contains one, and a generator that silently encoded a
/// newline into a constant would make the generated file harder to review than
/// the manifest it came from.
String _dartStringLiteral(String value) {
  for (final unit in value.codeUnits) {
    if (unit < 0x20 || unit == 0x7f) {
      throw FormatException(
        'manifest value contains a control character (U+'
        '${unit.toRadixString(16).padLeft(4, '0').toUpperCase()}): $value',
      );
    }
  }
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$');
  return "'$escaped'";
}

Map<String, Object?> _object(Map<String, Object?> parent, String key) {
  final value = parent[key];
  if (value is! Map<String, Object?>) {
    throw FormatException('compat_manifest.json: `$key` must be an object');
  }
  return value;
}

String _string(
  Map<String, Object?> parent,
  String key, {
  required String path,
}) {
  final where = path.isEmpty ? key : '$path.$key';
  final value = parent[key];
  if (value is! String || value.isEmpty) {
    throw FormatException(
      'compat_manifest.json: `$where` must be a non-empty string',
    );
  }
  return value;
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
