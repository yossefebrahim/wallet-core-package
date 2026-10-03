/// The URL and file-name grammar of DECISION-14 §3.1, as pure functions.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// Nothing here touches the filesystem or the network; every function is a
/// string transformation, so the grammar can be tested exhaustively without a
/// server, a cache, or a manifest. The I/O that uses them lives in
/// `fetcher.dart`.
///
/// These functions deliberately re-implement checks that
/// `tools/manifest/lib/validator.dart` also makes. That duplication is the
/// point: the fetcher must not build a URL out of a manifest that contradicts
/// itself, and it cannot depend on the tooling package (tooling is not a
/// package dependency of `wallet_core_flutter_native`).
library;

/// A logical name's path in the manifest flattened for a GitHub release asset
/// name: `/` becomes `-` (DECISION-14 §3.1, `wcf_flat_name` in
/// `tools/native_build/lib/common.sh`).
///
/// `android/arm64-v8a/libTrustWalletCore.so` →
/// `android-arm64-v8a-libTrustWalletCore.so`.
String flatName(String logicalName) => logicalName.replaceAll('/', '-');

/// The primary download URL: `base + "/" + assetName`.
///
/// [base] is `retention.primary`, a base URL with no trailing slash pointing at
/// one GitHub Release; a release asset is a flat file with no path component
/// under the tag, so the whole address is one segment (DECISION-14 §3.1).
String primaryUrl(String base, String assetName) =>
    '${_withoutTrailingSlash(base)}/$assetName';

/// The mirror download URL:
/// `base + "/" + artifactSetId + "/" + sha256 + "/" + logicalName`.
///
/// [base] is `retention.mirror`, a bucket prefix that holds every set. The
/// caller is responsible for using this only when `retention.mirror` is
/// non-null (DECISION-14 §3.1); there is no default mirror.
String mirrorUrl(
  String base,
  String artifactSetId,
  String sha256,
  String logicalName,
) => '${_withoutTrailingSlash(base)}/$artifactSetId/$sha256/$logicalName';

/// The three fields a primary asset name carries.
final class ParsedAssetName {
  const ParsedAssetName({
    required this.artifactSetId,
    required this.sha256,
    required this.flatName,
  });

  /// The set the artifact belongs to, `as_<tag>_<nnn>`.
  final String artifactSetId;

  /// The artifact's full 64-character lowercase hex digest.
  final String sha256;

  /// The `logical_name` with `/` replaced by `-`.
  final String flatName;

  @override
  String toString() => '${artifactSetId}__${sha256}__$flatName';
}

/// A 64-character lowercase hex digest and nothing else.
///
/// A prefix is rejected on purpose: DECISION-14 §3.1 carries the whole digest
/// in the asset name, because a 12-hex prefix commits to 48 bits and is not
/// content addressing (D0 finding F7).
final RegExp _sha256RegExp = RegExp(r'^[0-9a-f]{64}$');

/// Whether [value] is a full 64-character lowercase hex sha256.
bool isSha256(String value) => _sha256RegExp.hasMatch(value);

/// Splits a primary asset name into its three `__`-separated fields.
///
/// `__` cannot occur inside a set id, a hex digest, or a logical name, so the
/// name parses unambiguously in either direction. Throws [FormatException]
/// with a message naming what was wrong when there are not exactly three
/// fields, when any of them is empty, or when the middle field is not a full
/// 64-character lowercase hex digest.
ParsedAssetName parseAssetName(String assetName) {
  final parts = assetName.split('__');
  if (parts.length != 3) {
    throw FormatException(
      'expected <artifact_set_id>__<sha256>__<flat_name>, three "__"-separated '
      'fields, got ${parts.length}',
      assetName,
    );
  }
  for (var i = 0; i < parts.length; i++) {
    if (parts[i].isEmpty) {
      const names = ['artifact_set_id', 'sha256', 'flat_name'];
      throw FormatException('${names[i]} is empty', assetName);
    }
  }
  if (!isSha256(parts[1])) {
    throw FormatException(
      'the embedded digest must be 64 lowercase hex characters, got '
      '"${parts[1]}" (${parts[1].length} characters)',
      assetName,
    );
  }
  return ParsedAssetName(
    artifactSetId: parts[0],
    sha256: parts[1],
    flatName: parts[2],
  );
}

/// [parseAssetName], returning `null` instead of throwing.
ParsedAssetName? tryParseAssetName(String assetName) {
  try {
    return parseAssetName(assetName);
  } on FormatException {
    return null;
  }
}

/// A manifest artifact key: `/`-separated segments of `[A-Za-z0-9._+-]`.
///
/// The `artifacts` map is a path grammar, not a fixed set (D0 finding F14), so
/// nothing here knows which artifacts exist.
final RegExp _logicalNameRegExp = RegExp(
  r'^[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)*$',
);

/// Whether [name] is a well-formed artifact logical name.
///
/// Rejects `__` (it is the asset name's field separator), and `.` or `..`
/// segments (they would let a manifest write outside the cache directory).
bool isLogicalName(String name) =>
    _logicalNameRegExp.hasMatch(name) &&
    !name.contains('__') &&
    !name.split('/').any((s) => s == '.' || s == '..');

/// Where an artifact lives inside the cache directory: the cache root followed
/// by the logical name, which is itself a relative path.
///
/// [separator] defaults to `/`, which `dart:io` accepts on every platform we
/// target including Windows; it is a parameter so this function stays free of
/// `dart:io`.
///
/// Throws [ArgumentError] for a logical name that is not one ([isLogicalName]),
/// so a manifest can never address a file outside [cacheDir].
String cachePathFor(
  String cacheDir,
  String logicalName, {
  String separator = '/',
}) {
  if (!isLogicalName(logicalName)) {
    throw ArgumentError.value(
      logicalName,
      'logicalName',
      'not a valid artifact logical name',
    );
  }
  var root = cacheDir;
  while (root.length > 1 && (root.endsWith('/') || root.endsWith(separator))) {
    root = root.substring(0, root.length - 1);
  }
  final relative = separator == '/'
      ? logicalName
      : logicalName.replaceAll('/', separator);
  if (root.endsWith('/') || root.endsWith(separator)) return '$root$relative';
  return '$root$separator$relative';
}

String _withoutTrailingSlash(String base) {
  var end = base.length;
  while (end > 1 && base[end - 1] == '/') {
    end--;
  }
  return base.substring(0, end);
}
