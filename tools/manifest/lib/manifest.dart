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

class Artifacts {
  final ArtifactFile androidArm64;
  final ArtifactFile androidArmeabi;
  final ArtifactFile androidX86_64;
  final ArtifactFile iosXcframework;

  Artifacts({
    required this.androidArm64,
    required this.androidArmeabi,
    required this.androidX86_64,
    required this.iosXcframework,
  });

  factory Artifacts.fromJson(Map<String, dynamic> json) => Artifacts(
    androidArm64: ArtifactFile.fromJson(
      json['android/arm64-v8a/libTrustWalletCore.so'] as Map<String, dynamic>,
    ),
    androidArmeabi: ArtifactFile.fromJson(
      json['android/armeabi-v7a/libTrustWalletCore.so'] as Map<String, dynamic>,
    ),
    androidX86_64: ArtifactFile.fromJson(
      json['android/x86_64/libTrustWalletCore.so'] as Map<String, dynamic>,
    ),
    iosXcframework: ArtifactFile.fromJson(
      json['ios/TrustWalletCore.xcframework.zip'] as Map<String, dynamic>,
    ),
  );
}

class ArtifactFile {
  final String sha256;
  final int size;
  ArtifactFile({required this.sha256, required this.size});
  factory ArtifactFile.fromJson(Map<String, dynamic> json) =>
      ArtifactFile(sha256: json['sha256'] as String, size: json['size'] as int);
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

class Toolchain {
  final String ndk;
  final String xcode;
  final String cmake;
  final String rust;
  Toolchain({
    required this.ndk,
    required this.xcode,
    required this.cmake,
    required this.rust,
  });
  factory Toolchain.fromJson(Map<String, dynamic> json) => Toolchain(
    ndk: json['ndk'] as String,
    xcode: json['xcode'] as String,
    cmake: json['cmake'] as String,
    rust: json['rust'] as String,
  );
}

class Identity {
  final String symbol;
  final String artifactSetId;
  final String upstreamCommit;
  Identity({
    required this.symbol,
    required this.artifactSetId,
    required this.upstreamCommit,
  });
  factory Identity.fromJson(Map<String, dynamic> json) => Identity(
    symbol: json['symbol'] as String,
    artifactSetId: json['artifact_set_id'] as String,
    upstreamCommit: json['upstream_commit'] as String,
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
