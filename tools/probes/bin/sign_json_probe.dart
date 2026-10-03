import 'dart:io';
import 'dart:ffi';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart';
import 'package:wcf_tool_probes/sign_json_probe.dart';

typedef WcfBuildInfoC = Pointer<Int8> Function();
typedef WcfBuildInfoDart = Pointer<Int8> Function();

String _readString(Pointer<Int8> ptr) {
  final bytes = <int>[];
  int i = 0;
  while (true) {
    final byte = ptr[i];
    if (byte == 0) break;
    bytes.add(byte);
    i++;
  }
  return utf8.decode(bytes);
}

void main(List<String> args) {
  String? libPath;
  String outPath = 'docs/decisions/evidence/sign_json_coverage.md';
  bool allowMismatch = false;

  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--lib' && i + 1 < args.length) {
      libPath = args[i + 1];
      i++;
    } else if (args[i] == '--out' && i + 1 < args.length) {
      outPath = args[i + 1];
      i++;
    } else if (args[i] == '--allow-mismatch') {
      allowMismatch = true;
    } else {
      stderr.writeln(
        'Usage: probe:sign-json [--lib <path>] [--out <path>] [--allow-mismatch]',
      );
      exit(64);
    }
  }

  final String? wcfNativeOut = Platform.environment['WCF_NATIVE_OUT'];
  final String tmpDir = Directory.systemTemp.path;
  final String hostLibPath =
      '${wcfNativeOut ?? '$tmpDir/wcf-native'}/artifacts/macos/arm64_x86_64/libTrustWalletCore.dylib';

  final List<String> pathsToTry = [
    ?libPath,
    ?Platform.environment['WCF_NATIVE_LIB'],
    'third_party/wcf-native/macos/arm64_x86_64/libTrustWalletCore.dylib',
    hostLibPath,
  ];

  File? libFile;
  String? actualLibPath;

  for (final path in pathsToTry) {
    final file = File(path);
    if (file.existsSync()) {
      libFile = file;
      actualLibPath = path;
      break;
    }
  }

  if (libFile == null || actualLibPath == null) {
    stderr.writeln('Library not found. Paths tried:');
    for (final path in pathsToTry) {
      stderr.writeln('  - $path');
    }
    stderr.writeln('Run `melos run native:host-lib` first.');
    exit(1);
  }

  late final DynamicLibrary dylib;
  try {
    dylib = DynamicLibrary.open(actualLibPath);
  } catch (e) {
    stderr.writeln(
      'Failed to open library at $actualLibPath. Run `melos run native:host-lib` first. Error: $e',
    );
    exit(1);
  }

  File manifestFile = File('compat_manifest.json');
  if (!manifestFile.existsSync()) {
    manifestFile = File('../../compat_manifest.json');
    if (!manifestFile.existsSync()) {
      stderr.writeln('compat_manifest.json not found in repository root.');
      exit(1);
    }
  }
  final manifestJson =
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
  final upstream = manifestJson['upstream'] as Map<String, dynamic>;
  final manifestTag = upstream['tag'] as String;
  final manifestCommit = upstream['commit'] as String;

  Pointer<Int8> buildInfoPtr;
  try {
    final wcfBuildInfo = dylib.lookupFunction<WcfBuildInfoC, WcfBuildInfoDart>(
      'wcf_build_info',
    );
    buildInfoPtr = wcfBuildInfo();
  } catch (e) {
    stderr.writeln('Failed to bind wcf_build_info from library: $e');
    exit(1);
  }

  final buildInfoString = _readString(buildInfoPtr);
  final buildInfoJson = jsonDecode(buildInfoString) as Map<String, dynamic>;
  final libraryCommit = buildInfoJson['upstream_commit'] as String;
  final artifactSetId = buildInfoJson['artifact_set_id'] as String;

  if (libraryCommit != manifestCommit) {
    if (!allowMismatch) {
      stderr.writeln(
        'Library commit $libraryCommit differs from manifest commit $manifestCommit',
      );
      exit(1);
    }
  }

  final librarySha256 = sha256.convert(libFile.readAsBytesSync()).toString();

  final bindings = WalletCoreBindings(dylib);

  final rows = probe(bindings);

  final markdown = renderMarkdown(
    rows,
    upstreamTag: manifestTag,
    upstreamCommit: manifestCommit,
    libraryCommit: libraryCommit,
    artifactSetId: artifactSetId,
    librarySha256: librarySha256,
  );

  final outFile = File(outPath);
  if (!outFile.parent.existsSync()) {
    outFile.parent.createSync(recursive: true);
  }
  outFile.writeAsStringSync(markdown);

  exit(0);
}
