/// The generated constants, the shipped asset, and the root manifest must all
/// describe the same bytes.
///
/// `melos run gen:manifest` writes the first two from the third and
/// `melos run gen:check` diffs them, so these tests are the same statement
/// made where a consumer of the package can see it fail.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter_native/wallet_core_flutter_native.dart';

import 'host_library.dart';

File get _asset => File(manifestAssetPath);

File get _rootManifest => File('${repoRoot!.path}/compat_manifest.json');

void main() {
  test('the package ships the manifest where PRD §15.3 puts it', () {
    expect(manifestAssetPath, 'assets/compat_manifest.json');
    expect(_asset.existsSync(), isTrue, reason: 'run `melos run gen:manifest`');
  });

  test('the asset is byte-identical to the root manifest', () {
    expect(_asset.readAsBytesSync(), _rootManifest.readAsBytesSync());
  }, skip: repoRootSkip);

  test('manifestSha256 is the sha256 of both files\' bytes', () {
    // The definition the generator states and T3.11 will compare against: the
    // file's bytes exactly as committed, not a re-serialisation.
    final assetBytes = Uint8List.fromList(_asset.readAsBytesSync());
    expect(verifyManifestHash(assetBytes), manifestSha256);
    expect(
      verifyManifestHash(Uint8List.fromList(_rootManifest.readAsBytesSync())),
      manifestSha256,
    );
  }, skip: repoRootSkip);

  test('comparison 2 passes for the shipped asset alone', () {
    // The check a consumer runs: this package's own asset against this
    // package's own constant, with no repository in sight.
    expect(
      () => verifyManifestHash(Uint8List.fromList(_asset.readAsBytesSync())),
      returnsNormally,
    );
  });

  test('comparison 2 fails on a single altered byte (TM-16)', () {
    final bytes = Uint8List.fromList(_asset.readAsBytesSync());
    bytes[bytes.length - 1] = bytes[bytes.length - 1] ^ 0x01;
    expect(
      () => verifyManifestHash(bytes),
      throwsA(
        isA<ManifestMismatchError>().having(
          (e) => e.check,
          'check',
          ManifestCheck.manifestHashMismatch,
        ),
      ),
    );
  });

  test('the constants agree with the asset they were generated from', () {
    final manifest =
        jsonDecode(utf8.decode(_asset.readAsBytesSync()))
            as Map<String, Object?>;
    final upstream = manifest['upstream']! as Map<String, Object?>;
    final identity = manifest['identity']! as Map<String, Object?>;
    expect(upstreamRepo, upstream['repo']);
    expect(upstreamTag, upstream['tag']);
    expect(upstreamCommit, upstream['commit']);
    expect(identitySymbol, identity['symbol']);
    expect(identityArtifactSetId, identity['artifact_set_id']);
    expect(identityUpstreamCommit, identity['upstream_commit']);
    expect(releaseSetId, manifest['release_set']);
  });
}
