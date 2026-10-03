/// The slice of `compat_manifest.json` a fetch needs, and the gate that
/// decides whether it may be fetched from at all.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// **The fetch tool trusts the manifest it is given.** That is the design, not
/// an oversight: `compat_manifest.json` *is* the integrity root for the
/// artifacts (threat model TM-16), it ships inside the package, and a consumer
/// who edits their own copy has disabled their own protection. What this file
/// does is refuse to act on a manifest that contradicts *itself* — an
/// `asset_name` whose embedded digest is not the record's `sha256`, a
/// `logical_name` that is not the map key, a base URL that is not `https://` —
/// because such a manifest cannot be a coherent instruction, whoever wrote it.
/// Those cross-checks duplicate `tools/manifest/lib/validator.dart` on purpose;
/// the fetcher cannot depend on the tooling package.
///
/// The parse is deliberately loose. A missing or ill-typed field becomes a gate
/// reason, not an exception, so `--dry-run` can report every blocker in the
/// manifest at once instead of the first one.
library;

import 'dart:convert';

import 'asset_names.dart';

/// The prefix a manifest field carries while the task that fills it has not
/// run yet — `TBD-T1.2`, `TBD-T0.11`.
///
/// The same constant as `placeholderPrefix` in
/// `lib/src/verify_identity.dart`, repeated rather than imported: that library
/// pulls in `dart:ffi` and this is a plain-Dart build-time tool.
const String placeholderPrefix = 'TBD-';

/// Whether [value] is an unfilled manifest placeholder.
bool isPlaceholder(String value) => value.startsWith(placeholderPrefix);

/// One entry of the manifest's `artifacts` map, as the fetcher reads it.
///
/// Every field is nullable because a record may be incomplete; [FetchManifest]
/// reports what is missing rather than refusing to parse.
final class ArtifactRecord {
  const ArtifactRecord({
    required this.key,
    required this.sha256,
    required this.size,
    required this.assetName,
    required this.logicalName,
  });

  /// The `artifacts` map key — the artifact's logical path, and the name every
  /// flag and message uses.
  final String key;

  /// `sha256`, as written: possibly a `TBD-` placeholder, possibly absent.
  final String? sha256;

  /// `size` in bytes, as written.
  final int? size;

  /// `asset_name` — the primary's whole path segment (DECISION-14 §3.1).
  final String? assetName;

  /// `logical_name` — the map key repeated inside the record.
  final String? logicalName;
}

/// `compat_manifest.json`, reduced to what a fetch needs.
final class FetchManifest {
  const FetchManifest({
    required this.source,
    required this.upstreamTag,
    required this.artifactSetId,
    required this.retentionPrimary,
    required this.retentionMirror,
    required this.mirrorKeyPresent,
    required this.artifacts,
  });

  /// Where the JSON was read from, for messages.
  final String source;

  /// `upstream.tag` — the cache directory's last segment.
  final String? upstreamTag;

  /// `identity.artifact_set_id`.
  final String? artifactSetId;

  /// `retention.primary`, a base URL with no trailing slash.
  final String? retentionPrimary;

  /// `retention.mirror`, or `null`. A `null` mirror is a recorded fact, not a
  /// missing field: DECISION-14 §3.3 keeps the key present and null until the
  /// mirror exists, and the mirror is used **only** when it is non-null.
  final String? retentionMirror;

  /// Whether the `mirror` key existed at all, so a manifest that dropped it can
  /// be told apart from one that recorded `null`.
  final bool mirrorKeyPresent;

  /// The `artifacts` map, in manifest order.
  final Map<String, ArtifactRecord> artifacts;

  /// Reads [json], the text of a `compat_manifest.json`.
  ///
  /// Throws [FormatException] only when the text is not a JSON object or has no
  /// `artifacts` map — a file that is not a manifest at all. Everything else is
  /// a gate reason.
  static FetchManifest parse(String json, {required String source}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (e) {
      throw FormatException('$source is not valid JSON: ${e.message}');
    }
    if (decoded is! Map<String, Object?>) {
      throw FormatException('$source is not a JSON object');
    }
    final artifactsRaw = decoded['artifacts'];
    if (artifactsRaw is! Map<String, Object?>) {
      throw FormatException('$source has no "artifacts" object');
    }

    final upstream = _objectAt(decoded, 'upstream');
    final identity = _objectAt(decoded, 'identity');
    final retention = _objectAt(decoded, 'retention');

    final artifacts = <String, ArtifactRecord>{};
    for (final key in artifactsRaw.keys) {
      final record = artifactsRaw[key];
      final map = record is Map<String, Object?>
          ? record
          : const <String, Object?>{};
      final size = map['size'];
      artifacts[key] = ArtifactRecord(
        key: key,
        sha256: _stringAt(map, 'sha256'),
        size: size is int ? size : null,
        assetName: _stringAt(map, 'asset_name'),
        logicalName: _stringAt(map, 'logical_name'),
      );
    }

    return FetchManifest(
      source: source,
      upstreamTag: _stringAt(upstream, 'tag'),
      artifactSetId: _stringAt(identity, 'artifact_set_id'),
      retentionPrimary: _stringAt(retention, 'primary'),
      retentionMirror: _stringAt(retention, 'mirror'),
      mirrorKeyPresent: retention.containsKey('mirror'),
      artifacts: artifacts,
    );
  }

  static Map<String, Object?> _objectAt(Map<String, Object?> map, String key) {
    final value = map[key];
    return value is Map<String, Object?> ? value : const <String, Object?>{};
  }

  static String? _stringAt(Map<String, Object?> map, String key) {
    final value = map[key];
    return value is String ? value : null;
  }
}

/// One reason the manifest cannot be fetched from, in a form a developer can
/// act on: what is wrong, and which task fills it.
final class GateReason {
  const GateReason({required this.field, required this.reason, this.fixedBy});

  /// The manifest path of the offending field, e.g.
  /// `artifacts["ios/TrustWalletCore.xcframework.zip"].sha256`.
  final String field;

  /// What is wrong with it.
  final String reason;

  /// The task that will fill or fix it, when one is known.
  final String? fixedBy;

  @override
  String toString() =>
      fixedBy == null ? '$field: $reason' : '$field: $reason ($fixedBy)';
}

/// Whether [url] may be opened.
///
/// HTTPS only. [allowInsecureLoopback] is a **test-only** escape hatch for the
/// loopback fake server in `test/tool/`: it permits `http` and only for
/// `127.0.0.1`, `::1`, and `localhost`. It never relaxes anything else, and in
/// particular it never permits plain `http` to a routable host.
String? insecureUrlReason(String url, {required bool allowInsecureLoopback}) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return 'not an absolute URL with a host';
  }
  if (uri.scheme == 'https') return null;
  if (uri.scheme != 'http') {
    return 'scheme "${uri.scheme}" is not https';
  }
  if (!allowInsecureLoopback) {
    return 'plain http is refused; artifacts are fetched over https only';
  }
  if (!isLoopbackHost(uri.host)) {
    return 'plain http is permitted only for loopback under '
        '--allow-insecure-loopback, and "${uri.host}" is not a loopback host';
  }
  return null;
}

/// Whether [host] is the local machine by literal address or by the one name
/// that always resolves to it.
bool isLoopbackHost(String host) =>
    host == '127.0.0.1' || host == '::1' || host == 'localhost';

/// Every reason the manifest cannot be fetched from, checked before any socket
/// is opened.
///
/// [selected] names the artifacts the run will touch (`--only`, or every key).
/// Manifest-wide fields are always checked; artifact records are checked for
/// the selected artifacts only, so `--only` on a manifest with one bad record
/// elsewhere is not blocked by it.
///
/// An empty result means every URL this run would build is consistent with the
/// manifest that produced it. It does **not** mean the bytes are right; that is
/// what the digest check after the download is for, and nothing skips it.
List<GateReason> manifestBlockers(
  FetchManifest manifest, {
  required Iterable<String> selected,
  bool allowInsecureLoopback = false,
}) {
  final reasons = <GateReason>[];

  final primary = manifest.retentionPrimary;
  if (primary == null) {
    reasons.add(
      const GateReason(
        field: 'retention.primary',
        reason: 'missing; there is nowhere to fetch from',
        fixedBy: 'T0.11',
      ),
    );
  } else if (isPlaceholder(primary)) {
    reasons.add(
      GateReason(
        field: 'retention.primary',
        reason:
            'is the unfilled placeholder "$primary"; no artifact set has '
            'been published, so there is no release to download from',
        fixedBy: primary.substring(placeholderPrefix.length),
      ),
    );
  } else {
    final insecure = insecureUrlReason(
      primary,
      allowInsecureLoopback: allowInsecureLoopback,
    );
    if (insecure != null) {
      reasons.add(
        GateReason(field: 'retention.primary', reason: '"$primary" $insecure'),
      );
    }
  }

  if (!manifest.mirrorKeyPresent) {
    reasons.add(
      const GateReason(
        field: 'retention.mirror',
        reason:
            'key is absent; DECISION-14 §3.3 keeps it present and null '
            'until a mirror exists, so that "no mirror" is a recorded fact',
      ),
    );
  }
  final mirror = manifest.retentionMirror;
  if (mirror != null) {
    if (isPlaceholder(mirror)) {
      reasons.add(
        GateReason(
          field: 'retention.mirror',
          reason:
              'is the unfilled placeholder "$mirror"; record null until '
              'the mirror exists rather than a placeholder',
          fixedBy: mirror.substring(placeholderPrefix.length),
        ),
      );
    } else {
      final insecure = insecureUrlReason(
        mirror,
        allowInsecureLoopback: allowInsecureLoopback,
      );
      if (insecure != null) {
        reasons.add(
          GateReason(field: 'retention.mirror', reason: '"$mirror" $insecure'),
        );
      }
    }
  }

  final setId = manifest.artifactSetId;
  if (setId == null) {
    reasons.add(
      const GateReason(
        field: 'identity.artifact_set_id',
        reason: 'missing; a downloaded file could not be tied to a set',
        fixedBy: 'T1.2',
      ),
    );
  } else if (isPlaceholder(setId)) {
    reasons.add(
      GateReason(
        field: 'identity.artifact_set_id',
        reason:
            'is the unfilled placeholder "$setId"; the CI native build has '
            'not allocated an artifact set yet',
        fixedBy: setId.substring(placeholderPrefix.length),
      ),
    );
  }

  for (final name in selected) {
    final record = manifest.artifacts[name];
    if (record == null) {
      reasons.add(
        GateReason(
          field: 'artifacts["$name"]',
          reason: 'is not in the manifest',
        ),
      );
      continue;
    }
    reasons.addAll(_artifactBlockers(record, setId));
  }

  return reasons;
}

List<GateReason> _artifactBlockers(ArtifactRecord record, String? setId) {
  final reasons = <GateReason>[];
  final path = 'artifacts["${record.key}"]';

  if (!isLogicalName(record.key)) {
    reasons.add(
      GateReason(
        field: path,
        reason:
            'the map key is not a logical name: "/"-separated segments of '
            '[A-Za-z0-9._+-], no "." or ".." segment and no "__"',
      ),
    );
  }

  final sha = record.sha256;
  if (sha == null) {
    reasons.add(
      GateReason(field: '$path.sha256', reason: 'missing', fixedBy: 'T1.2'),
    );
  } else if (isPlaceholder(sha)) {
    reasons.add(
      GateReason(
        field: '$path.sha256',
        reason:
            'is the unfilled placeholder "$sha"; there is no digest to '
            'verify a download against',
        fixedBy: sha.substring(placeholderPrefix.length),
      ),
    );
  } else if (!isSha256(sha)) {
    reasons.add(
      GateReason(
        field: '$path.sha256',
        reason: 'is not 64 lowercase hex characters: "$sha"',
      ),
    );
  }

  final size = record.size;
  if (size == null) {
    reasons.add(
      GateReason(field: '$path.size', reason: 'missing', fixedBy: 'T1.2'),
    );
  } else if (size <= 0) {
    reasons.add(
      GateReason(
        field: '$path.size',
        reason: 'is $size; a published artifact has a positive size',
        fixedBy: 'T1.2',
      ),
    );
  }

  final logical = record.logicalName;
  if (logical == null) {
    reasons.add(
      GateReason(
        field: '$path.logical_name',
        reason:
            'missing; DECISION-14 §5.1 repeats the map key inside the '
            'record so it is self-describing once detached from the map',
        fixedBy: 'T1.2',
      ),
    );
  } else if (logical != record.key) {
    reasons.add(
      GateReason(
        field: '$path.logical_name',
        reason: 'is "$logical" but the map key is "${record.key}"',
      ),
    );
  }

  final assetName = record.assetName;
  if (assetName == null) {
    reasons.add(
      GateReason(
        field: '$path.asset_name',
        reason:
            'missing; it is the primary URL\'s whole path segment and the '
            'fetcher does not guess it',
        fixedBy: 'T1.2',
      ),
    );
    return reasons;
  }

  if (assetName.length > 255) {
    reasons.add(
      GateReason(
        field: '$path.asset_name',
        reason:
            'is ${assetName.length} characters, over the 255-character '
            'GitHub release asset limit',
      ),
    );
  }

  final ParsedAssetName parsed;
  try {
    parsed = parseAssetName(assetName);
  } on FormatException catch (e) {
    reasons.add(
      GateReason(
        field: '$path.asset_name',
        reason: '"$assetName": ${e.message}',
      ),
    );
    return reasons;
  }

  // The two cross-checks that matter most: the asset name is the URL, so a
  // name that disagrees with the record it sits in is a URL the manifest
  // contradicts. Refuse it rather than download from it and find out.
  if (sha != null && !isPlaceholder(sha) && parsed.sha256 != sha) {
    reasons.add(
      GateReason(
        field: '$path.asset_name',
        reason: 'carries digest ${parsed.sha256} but $path.sha256 is $sha',
      ),
    );
  }
  if (setId != null && !isPlaceholder(setId) && parsed.artifactSetId != setId) {
    reasons.add(
      GateReason(
        field: '$path.asset_name',
        reason:
            'carries set id ${parsed.artifactSetId} but '
            'identity.artifact_set_id is $setId',
      ),
    );
  }
  final flat = flatName(record.key);
  if (parsed.flatName != flat) {
    reasons.add(
      GateReason(
        field: '$path.asset_name',
        reason:
            'carries flat name ${parsed.flatName} but the logical name '
            'flattens to $flat',
      ),
    );
  }

  return reasons;
}
