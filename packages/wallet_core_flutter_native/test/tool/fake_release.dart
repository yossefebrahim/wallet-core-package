/// A loopback stand-in for a published artifact set: a manifest, some bytes,
/// and an `HttpServer` on `127.0.0.1` that counts what it was asked for.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// Not a test file — no `_test.dart` suffix, so the runner does not collect it.
///
/// The real primary is a GitHub Release download base URL and is unreachable
/// from a test (and from this sandbox).
/// The fetcher's HTTPS-only rule therefore needs the test-only
/// `--allow-insecure-loopback` flag, which permits plain `http` to
/// `127.0.0.1`, `::1`, and `localhost` and refuses every other host.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// One artifact in the fake set.
final class FakeArtifact {
  FakeArtifact(this.logicalName, this.bytes);

  /// Deterministic bytes of [length], distinguishable per [seed].
  factory FakeArtifact.generated(
    String logicalName, {
    int length = 2048,
    int seed = 1,
  }) => FakeArtifact(
    logicalName,
    List<int>.generate(length, (i) => (i * 31 + seed * 7) % 251),
  );

  /// The artifact's path in the manifest.
  final String logicalName;

  /// Its content.
  final List<int> bytes;

  /// Its 64-hex lowercase digest.
  String get sha256Hex => sha256.convert(bytes).toString();

  /// Its size in bytes.
  int get size => bytes.length;

  /// `logical_name` with `/` replaced by `-`.
  String get flatName => logicalName.replaceAll('/', '-');

  /// The primary asset name of DECISION-14 §3.1.
  String assetName(String setId) => '${setId}__${sha256Hex}__$flatName';
}

/// A fake GitHub Release and a fake mirror bucket, served from loopback.
///
/// Paths: `/releases/<asset_name>` for the primary and
/// `/mirror/<set>/<sha>/<logical>` for the mirror, matching the two templates
/// of DECISION-14 §3.1.
final class FakeReleaseServer {
  FakeReleaseServer._(this._server, this.setId);

  /// Binds on an ephemeral loopback port and serves [artifacts] from both
  /// layouts.
  static Future<FakeReleaseServer> start({
    required String setId,
    required List<FakeArtifact> artifacts,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeReleaseServer._(server, setId);
    for (final artifact in artifacts) {
      fake.publish(artifact);
    }
    unawaitedServe(fake);
    return fake;
  }

  final HttpServer _server;

  /// The artifact set id the asset names carry.
  final String setId;

  final Map<String, List<int>> _bodies = <String, List<int>>{};
  final Map<String, String> _redirects = <String, String>{};

  /// Every path the server was asked for, in order. The no-network tests assert
  /// this is empty.
  final List<String> requests = <String>[];

  /// `http://127.0.0.1:<port>`.
  String get origin => 'http://127.0.0.1:${_server.port}';

  /// The base URL a manifest's `retention.primary` points at.
  String get primaryBase => '$origin/releases';

  /// The base URL a manifest's `retention.mirror` points at.
  String get mirrorBase => '$origin/mirror';

  /// Serves [artifact] from both layouts.
  void publish(FakeArtifact artifact) {
    _bodies['/releases/${artifact.assetName(setId)}'] = artifact.bytes;
    _bodies['/mirror/$setId/${artifact.sha256Hex}/${artifact.logicalName}'] =
        artifact.bytes;
  }

  /// Serves [body] from the primary path of [artifact] — the substituted-bytes
  /// case of threat model TM-14.
  void publishPrimaryBody(FakeArtifact artifact, List<int> body) {
    _bodies['/releases/${artifact.assetName(setId)}'] = body;
  }

  /// Stops serving [artifact] from the primary, so a GET answers 404.
  void withdrawPrimary(FakeArtifact artifact) {
    _bodies.remove('/releases/${artifact.assetName(setId)}');
  }

  /// Stops serving [artifact] from the mirror.
  void withdrawMirror(FakeArtifact artifact) {
    _bodies.remove(
      '/mirror/$setId/${artifact.sha256Hex}/${artifact.logicalName}',
    );
  }

  /// Answers [artifact]'s primary path with `302 Found` pointing at [location],
  /// the way GitHub Releases redirects asset bytes to its object store.
  void redirectPrimary(FakeArtifact artifact, String location) {
    _redirects['/releases/${artifact.assetName(setId)}'] = location;
  }

  /// Serves [body] at an arbitrary [path], for a redirect target.
  void serveAt(String path, List<int> body) => _bodies[path] = body;

  /// Closes the socket.
  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    requests.add(request.uri.path);
    final redirect = _redirects[request.uri.path];
    if (redirect != null) {
      request.response.statusCode = HttpStatus.found;
      request.response.headers.set(HttpHeaders.locationHeader, redirect);
      await request.response.close();
      return;
    }
    final body = _bodies[request.uri.path];
    if (body == null) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('no such asset');
      await request.response.close();
      return;
    }
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.binary;
    request.response.add(body);
    await request.response.close();
  }

  /// Drives the request loop without awaiting it.
  static void unawaitedServe(FakeReleaseServer fake) {
    fake._server.listen((request) async {
      await fake._handle(request);
    });
  }
}

/// A manifest of the shape the fetcher reads, with the DECISION-14 §5.1 fields
/// it needs and the placeholder-free values a real set would have.
///
/// Only the fields the fetcher looks at are filled; `tools/manifest`'s
/// validator is the authority on the whole record, and this is not trying to be
/// a second one.
String fakeManifestJson({
  required String setId,
  required String upstreamTag,
  required String primary,
  required String? mirror,
  required List<FakeArtifact> artifacts,
  Map<String, Object?> Function(FakeArtifact artifact)? overrideRecord,
  bool includeMirrorKey = true,
}) {
  final artifactMap = <String, Object?>{};
  for (final artifact in artifacts) {
    artifactMap[artifact.logicalName] =
        overrideRecord?.call(artifact) ??
        <String, Object?>{
          'sha256': artifact.sha256Hex,
          'size': artifact.size,
          'asset_name': artifact.assetName(setId),
          'logical_name': artifact.logicalName,
        };
  }
  return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
    'upstream': <String, Object?>{
      'repo': 'trustwallet/wallet-core',
      'tag': upstreamTag,
      'commit': 'd692ac27749d0c615e17c751b70ab4f0aa75c59b',
    },
    'artifacts': artifactMap,
    'identity': <String, Object?>{
      'symbol': 'wcf_build_info',
      'artifact_set_id': setId,
      'upstream_commit': 'd692ac27749d0c615e17c751b70ab4f0aa75c59b',
    },
    'retention': <String, Object?>{
      'primary': primary,
      if (includeMirrorKey) 'mirror': mirror,
      'policy': 'https://example.invalid/retention',
    },
  });
}
