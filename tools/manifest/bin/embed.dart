/// `melos run gen:manifest` — embeds `compat_manifest.json` into
/// `wallet_core_flutter_native`.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// Writes the generated constants file — formatted with `dart format` as the
/// last step, so the committed result passes `format:check` without an
/// exclusion — and the asset copy. Run from the repository root; both paths
/// default to their canonical locations.
library;

import 'dart:io';

import 'package:wcf_tool_manifest/embed.dart';

const String _defaultManifest = 'compat_manifest.json';
const String _defaultPackage = 'packages/wallet_core_flutter_native';

void main(List<String> args) {
  var manifestPath = _defaultManifest;
  var packageDir = _defaultPackage;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--help' || arg == '-h') {
      stdout.writeln(_usage);
      return;
    } else if (arg == '--manifest') {
      manifestPath = _next(args, i++, arg);
    } else if (arg.startsWith('--manifest=')) {
      manifestPath = arg.substring('--manifest='.length);
    } else if (arg == '--package-dir') {
      packageDir = _next(args, i++, arg);
    } else if (arg.startsWith('--package-dir=')) {
      packageDir = arg.substring('--package-dir='.length);
    } else {
      stderr.writeln('Unknown argument: $arg\n\n$_usage');
      exit(2);
    }
  }

  final EmbedResult result;
  try {
    result = generate(manifestPath: manifestPath, nativePackageDir: packageDir);
  } on FileSystemException catch (e) {
    stderr.writeln('gen:manifest failed: ${e.message}: ${e.path}');
    exit(1);
  } on FormatException catch (e) {
    stderr.writeln('gen:manifest failed: ${e.message}');
    exit(1);
  } on ProcessException catch (e) {
    stderr.writeln('gen:manifest failed: ${e.executable}: ${e.message}');
    exit(1);
  }

  stdout
    ..writeln('manifest:  $manifestPath')
    ..writeln('sha256:    ${result.values.manifestSha256} (file bytes)')
    ..writeln(
      'identity:  ${result.values.identityArtifactSetId} @ '
      '${result.values.identityUpstreamCommit}',
    )
    ..writeln('release:   ${result.values.releaseSetId}')
    ..writeln(
      'constants: ${result.dartPath}'
      '${result.dartChanged ? "" : " (unchanged)"}',
    )
    ..writeln(
      'asset:     ${result.assetPath}'
      '${result.assetChanged ? "" : " (unchanged)"}',
    );
}

String _next(List<String> args, int i, String flag) {
  if (i + 1 >= args.length) {
    stderr.writeln('$flag needs a value\n\n$_usage');
    exit(2);
  }
  return args[i + 1];
}

const String _usage =
    '''
Usage: dart run tools/manifest/bin/embed.dart [options]

  --manifest <path>      Manifest to embed (default: $_defaultManifest)
  --package-dir <path>   Native package root (default: $_defaultPackage)

Writes the constants and the manifest copy into the native package:
  $generatedDartRelativePath  (formatted with `dart format`)
  $assetRelativePath''';
