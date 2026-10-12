import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart';
import 'package:wcf_tool_probes/compiler_probe.dart';
import 'package:wcf_tool_probes/message_signing_probe.dart';

typedef WcfBuildInfoC = Pointer<Int8> Function();
typedef WcfBuildInfoDart = Pointer<Int8> Function();

const usage =
    'Usage: probe:coverage [--lib <path>] [--out <path>]\n'
    '  (internal child mode: --coin <id> --part compiler|message)';

const defaultOut = 'docs/decisions/evidence/compiler_and_message_coverage.md';
const defaultLib =
    'third_party/wcf-native/macos/arm64_x86_64/libTrustWalletCore.dylib';

String _readString(Pointer<Int8> ptr) {
  final bytes = <int>[];
  var i = 0;
  while (true) {
    final byte = ptr[i];
    if (byte == 0) break;
    bytes.add(byte);
    i++;
  }
  return utf8.decode(bytes);
}

Never _usage() {
  stderr.writeln(usage);
  exit(64);
}

DynamicLibrary _open(String libPath) {
  if (!File(libPath).existsSync()) {
    stderr.writeln(
      'Library not found at $libPath. Run `melos run native:host-lib` first.',
    );
    exit(1);
  }
  try {
    return DynamicLibrary.open(libPath);
  } catch (e) {
    stderr.writeln(
      'Failed to open library at $libPath. Run `melos run native:host-lib` first. Error: $e',
    );
    exit(1);
  }
}

Future<void> main(List<String> args) async {
  String? libArg;
  String outPath = defaultOut;
  int? coin;
  String? part;

  for (var i = 0; i < args.length; i++) {
    final hasValue = i + 1 < args.length;
    switch (args[i]) {
      case '--lib' when hasValue:
        libArg = args[++i];
      case '--out' when hasValue:
        outPath = args[++i];
      case '--coin' when hasValue:
        coin = int.tryParse(args[++i]);
        if (coin == null) _usage();
      case '--part' when hasValue:
        part = args[++i];
        if (part != 'compiler' && part != 'message') _usage();
      default:
        _usage();
    }
  }
  if ((coin == null) != (part == null)) _usage();

  final libPath =
      libArg ?? Platform.environment['WCF_NATIVE_LIB'] ?? defaultLib;
  final dylib = _open(libPath);

  if (coin != null) {
    _runChild(dylib, coin, part!);
    return;
  }

  File manifestFile = File('compat_manifest.json');
  if (!manifestFile.existsSync()) {
    manifestFile = File('../../compat_manifest.json');
    if (!manifestFile.existsSync()) {
      stderr.writeln('compat_manifest.json not found in repository root.');
      exit(1);
    }
  }
  final manifest =
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
  final upstream = manifest['upstream'] as Map<String, dynamic>;
  final manifestTag = upstream['tag'] as String;
  final manifestCommit = upstream['commit'] as String;

  final Map<String, dynamic> buildInfo;
  try {
    final wcfBuildInfo = dylib.lookupFunction<WcfBuildInfoC, WcfBuildInfoDart>(
      'wcf_build_info',
    );
    buildInfo = jsonDecode(_readString(wcfBuildInfo())) as Map<String, dynamic>;
  } catch (e) {
    stderr.writeln('Failed to read wcf_build_info from library: $e');
    exit(1);
  }
  final libraryCommit = buildInfo['upstream_commit'] as String;
  final artifactSetId = buildInfo['artifact_set_id'] as String;
  if (libraryCommit != manifestCommit) {
    stderr.writeln(
      'Library commit $libraryCommit differs from manifest commit $manifestCommit',
    );
    exit(1);
  }
  final librarySha256 = sha256
      .convert(File(libPath).readAsBytesSync())
      .toString();

  final executable = Platform.resolvedExecutable;
  final script = Platform.script.toFilePath();
  final compilerRows = await probeCompilerViaChildren(
    executable: executable,
    script: script,
    libPath: libPath,
  );
  final messageRows = await probeMessageSignerViaChildren(
    executable: executable,
    script: script,
    libPath: libPath,
  );

  final markdown = renderCoverageMarkdown(
    compilerRows,
    messageRows,
    upstreamTag: manifestTag,
    upstreamCommit: manifestCommit,
    libraryCommit: libraryCommit,
    artifactSetId: artifactSetId,
    librarySha256: librarySha256,
  );

  final outFile = File(outPath);
  outFile.parent.createSync(recursive: true);
  outFile.writeAsStringSync(markdown);
  exit(0);
}

/// Child mode: run one coin's calls and print exactly one JSON line. The
/// parent treats any non-zero exit or signal as `crash`.
void _runChild(DynamicLibrary dylib, int coin, String part) {
  final bindings = WalletCoreBindings(dylib);
  void mark(String call) => stderr.writeln('call:$call');
  final calls = part == 'compiler'
      ? observeCompiler(FfiCompilerNative(bindings), coin, onCall: mark)
      : observeMessageSigner(
          FfiMessageSignerNative(bindings),
          coin,
          onCall: mark,
        );
  stdout.writeln(
    jsonEncode({
      'coin': coin,
      'part': part,
      'calls': calls.map((k, v) => MapEntry(k, v.toJson())),
    }),
  );
  exit(0);
}
