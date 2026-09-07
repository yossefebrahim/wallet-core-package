import 'dart:convert';
import 'dart:io';

class Manifest {
  final Upstream upstream;
  final Generators generators;
  final Schemas schemas;
  final Artifacts artifacts;
  final Packages packages;
  final Toolchain toolchain;
  final String releaseSet;
  final Identity identity;
  final Retention retention;
  final String? sbom;
  final bool reproducibleBuildVerified;

  Manifest({
    required this.upstream,
    required this.generators,
    required this.schemas,
    required this.artifacts,
    required this.packages,
    required this.toolchain,
    required this.releaseSet,
    required this.identity,
    required this.retention,
    this.sbom,
    required this.reproducibleBuildVerified,
  });

  static Manifest load(String path) {
    final file = File(path);
    final json = file.readAsStringSync();
    return parse(json);
  }

  static Manifest parse(String jsonString) {
    final raw = jsonDecode(jsonString) as Map<String, dynamic>;
    return Manifest(
      upstream: Upstream.fromJson(raw['upstream'] as Map<String, dynamic>),
      generators: Generators.fromJson(
        raw['generators'] as Map<String, dynamic>,
      ),
      schemas: Schemas.fromJson(raw['schemas'] as Map<String, dynamic>),
      artifacts: Artifacts.fromJson(raw['artifacts'] as Map<String, dynamic>),
      packages: Packages.fromJson(raw['packages'] as Map<String, dynamic>),
      toolchain: Toolchain.fromJson(raw['toolchain'] as Map<String, dynamic>),
      releaseSet: raw['release_set'] as String,
      identity: Identity.fromJson(raw['identity'] as Map<String, dynamic>),
      retention: Retention.fromJson(raw['retention'] as Map<String, dynamic>),
      sbom: raw['sbom'] as String?,
      reproducibleBuildVerified: raw['reproducible_build_verified'] as bool,
    );
  }
}

class Upstream {
  final String repo;
  final String tag;
  final String commit;
  Upstream({required this.repo, required this.tag, required this.commit});
  factory Upstream.fromJson(Map<String, dynamic> json) => Upstream(
    repo: json['repo'] as String,
    tag: json['tag'] as String,
    commit: json['commit'] as String,
  );
}

class Generators {
  final String ffigen;
  final String protoc;
  final String protocGenDart;
  final String registryTransform;
  Generators({
    required this.ffigen,
    required this.protoc,
    required this.protocGenDart,
    required this.registryTransform,
  });
  factory Generators.fromJson(Map<String, dynamic> json) => Generators(
    ffigen: json['ffigen'] as String,
    protoc: json['protoc'] as String,
    protocGenDart: json['protoc_gen_dart'] as String,
    registryTransform: json['registry_transform'] as String,
  );
}

class Schemas {
  final String protoDirSha;
  final String registryJsonSha;
  final String headersSha;
  Schemas({
    required this.protoDirSha,
    required this.registryJsonSha,
    required this.headersSha,
  });
  factory Schemas.fromJson(Map<String, dynamic> json) => Schemas(
    protoDirSha: json['proto_dir_sha'] as String,
    registryJsonSha: json['registry_json_sha'] as String,
    headersSha: json['headers_sha'] as String,
  );
}

/// The artifact set, keyed by logical name.
///
/// The Phase 0 model named four fixed artifacts as fields, which made the ABI
/// set a code change (D0 finding F14). It is a map now: an artifact set is
/// whatever the build produced, and which ABIs that is is a manifest fact.
class Artifacts {
  final Map<String, ArtifactFile> byLogicalName;

  Artifacts(this.byLogicalName);

  factory Artifacts.fromJson(Map<String, dynamic> json) => Artifacts({
    for (final entry in json.entries)
      entry.key: ArtifactFile.fromJson(
        entry.key,
        entry.value as Map<String, dynamic>,
      ),
  });

  Iterable<String> get logicalNames => byLogicalName.keys;

  ArtifactFile? operator [](String logicalName) => byLogicalName[logicalName];

  /// Artifacts whose `sha256` is a real digest rather than a `TBD-`
  /// placeholder — the ones a consumer build could actually fetch.
  Iterable<ArtifactFile> get populated =>
      byLogicalName.values.where((a) => a.isPopulated);
}

/// One artifact's record: the fourteen fields of DECISION-14 §5.1.
///
/// Everything past `sha256` and `size` is nullable in this model, and null
/// means "the manifest does not carry it yet", which is the state of every
/// entry until T1.2's workflow runs. The validator is what decides when that
/// is allowed; this class only reads.
class ArtifactFile {
  final String logicalNameKey;
  final String sha256;
  final int size;
  final String? sourceCommit;
  final String? buildWorkflow;
  final String? linkage;
  final String? targetOs;
  final String? abi;
  final String? minOs;
  final Map<String, String>? toolchain;
  final String? signature;
  final Map<String, dynamic>? attestation;
  final String? provenance;
  final String? assetName;
  final String? logicalName;

  ArtifactFile({
    required this.logicalNameKey,
    required this.sha256,
    required this.size,
    this.sourceCommit,
    this.buildWorkflow,
    this.linkage,
    this.targetOs,
    this.abi,
    this.minOs,
    this.toolchain,
    this.signature,
    this.attestation,
    this.provenance,
    this.assetName,
    this.logicalName,
  });

  factory ArtifactFile.fromJson(String key, Map<String, dynamic> json) {
    final rawToolchain = json['toolchain'];
    final rawAttestation = json['attestation'];
    return ArtifactFile(
      logicalNameKey: key,
      sha256: json['sha256'] as String,
      size: json['size'] as int,
      sourceCommit: json['source_commit'] as String?,
      buildWorkflow: json['build_workflow'] as String?,
      linkage: json['linkage'] as String?,
      targetOs: json['target_os'] as String?,
      abi: json['abi'] as String?,
      minOs: json['min_os'] as String?,
      toolchain: rawToolchain is Map<String, dynamic>
          ? rawToolchain.map((k, v) => MapEntry(k, v as String))
          : null,
      signature: json['signature'] as String?,
      attestation: rawAttestation is Map<String, dynamic>
          ? rawAttestation
          : null,
      provenance: json['provenance'] as String?,
      assetName: json['asset_name'] as String?,
      logicalName: json['logical_name'] as String?,
    );
  }

  bool get isPopulated => RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256);
}

class Packages {
  final String walletCoreFlutter;
  final String walletCoreFlutterBindings;
  final String walletCoreFlutterNative;
  Packages({
    required this.walletCoreFlutter,
    required this.walletCoreFlutterBindings,
    required this.walletCoreFlutterNative,
  });
  factory Packages.fromJson(Map<String, dynamic> json) => Packages(
    walletCoreFlutter: json['wallet_core_flutter'] as String,
    walletCoreFlutterBindings: json['wallet_core_flutter_bindings'] as String,
    walletCoreFlutterNative: json['wallet_core_flutter_native'] as String,
  );
}

/// The set-wide toolchain summary (DECISION-14 §5.1 note 1).
///
/// Not authoritative: under DECISION-9 Option C one set is built by two
/// toolchains, so the per-artifact `toolchain` object is what describes a
/// binary and this carries only what every artifact in the set agrees on. The
/// key set is therefore open, and reading it is a lookup rather than four
/// fields.
class Toolchain {
  final Map<String, String> entries;
  Toolchain(this.entries);
  factory Toolchain.fromJson(Map<String, dynamic> json) =>
      Toolchain({for (final e in json.entries) e.key: e.value as String});

  String? operator [](String key) => entries[key];
}

class Identity {
  final String symbol;
  final String artifactSetId;
  final String upstreamCommit;

  /// DECISION-14 §5's new field: the workflow run that produced the set. Null
  /// until the manifest carries a real artifact set.
  final String? buildWorkflow;

  Identity({
    required this.symbol,
    required this.artifactSetId,
    required this.upstreamCommit,
    this.buildWorkflow,
  });
  factory Identity.fromJson(Map<String, dynamic> json) => Identity(
    symbol: json['symbol'] as String,
    artifactSetId: json['artifact_set_id'] as String,
    upstreamCommit: json['upstream_commit'] as String,
    buildWorkflow: json['build_workflow'] as String?,
  );
}

class Retention {
  final String primary;
  final String? mirror;
  final String policy;
  Retention({required this.primary, this.mirror, required this.policy});
  factory Retention.fromJson(Map<String, dynamic> json) => Retention(
    primary: json['primary'] as String,
    mirror: json['mirror'] as String?,
    policy: json['policy'] as String,
  );
}
