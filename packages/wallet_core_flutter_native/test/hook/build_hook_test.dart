// The whole hook, in-process, through package:hooks' own test harness:
// target in, verified bytes through the real fetch tool, one CodeAsset out.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.
//
// Only success paths run here: on a failure the hooks runtime reports a
// BuildError by calling exit(), which would end the test process. The failure
// paths are covered without the runtime in acquire_test.dart and end to end,
// in a real `flutter build`, by eval/option1/run_eval.sh's negative fixture.

import 'dart:io';
import 'dart:typed_data';

import 'package:code_assets/code_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks/hooks.dart';

import '../../hook/build.dart' as hook;
import 'fixtures.dart';

void main() {
  late Directory dir;
  final armSim = thinMachO(cpuArm64, length: 160, fill: 0x31);
  final x86Sim = thinMachO(cpuX86_64, length: 128, fill: 0x32);
  final device = thinMachO(cpuArm64, length: 144, fill: 0x33);
  final androidArm64 = elf(machine: 183, length: 96);
  final artifacts = <String, List<int>>{
    'ios/arm64/libTrustWalletCore.dylib': device,
    'ios-simulator/arm64_x86_64/libTrustWalletCore.dylib': fatMachO([
      x86Sim,
      armSim,
    ]),
    'android/arm64-v8a/libTrustWalletCore.so': androidArm64,
  };

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('wcf-hook-build');
    writeVendored(Directory('${dir.path}/vendored'), artifacts);
    File('${dir.path}/manifest.json').writeAsStringSync(manifestFor(artifacts));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  PackageUserDefines defines() => PackageUserDefines(
    workspacePubspec: PackageUserDefinesSource(
      defines: const {
        'manifest': 'manifest.json',
        'vendored_dir': 'vendored',
        'cache_dir': 'cache',
        'offline': true,
      },
      basePath: Uri.directory(dir.path),
    ),
  );

  Future<CodeAsset> run(
    OS os,
    Architecture arch, {
    IOSSdk sdk = IOSSdk.iPhoneOS,
  }) async {
    CodeAsset? emitted;
    Uint8List? bytes;
    await testCodeBuildHook(
      mainMethod: hook.main,
      targetOS: os,
      targetArchitecture: arch,
      targetIOSSdk: sdk,
      userDefines: defines(),
      check: (input, output) {
        expect(output.assets.code, hasLength(1));
        emitted = output.assets.code.single;
        bytes = File.fromUri(emitted!.file!).readAsBytesSync();
        expect(
          output.dependencies.map((u) => u.toFilePath()),
          contains('${dir.path}/manifest.json'),
        );
      },
    );
    _lastBytes = bytes;
    return emitted!;
  }

  test('iOS simulator arm64 and x86_64: one id, one name, own slice', () async {
    final a = await run(
      OS.iOS,
      Architecture.arm64,
      sdk: IOSSdk.iPhoneSimulator,
    );
    final aBytes = _lastBytes;
    final x = await run(OS.iOS, Architecture.x64, sdk: IOSSdk.iPhoneSimulator);
    expect(a.id, 'package:wallet_core_flutter_native/wallet_core');
    expect(x.id, a.id);
    expect(a.linkMode, DynamicLoadingBundled());
    expect(a.file!.pathSegments.last, 'libTrustWalletCore.dylib');
    expect(x.file!.pathSegments.last, a.file!.pathSegments.last);
    expect(aBytes, armSim);
    expect(_lastBytes, x86Sim);
  });

  test('iOS device: the same id and name, the device bytes', () async {
    final d = await run(OS.iOS, Architecture.arm64);
    expect(d.id, 'package:wallet_core_flutter_native/wallet_core');
    expect(d.file!.pathSegments.last, 'libTrustWalletCore.dylib');
    expect(_lastBytes, device);
  });

  test('Android arm64-v8a: the .so, unchanged', () async {
    final s = await run(OS.android, Architecture.arm64);
    expect(s.id, 'package:wallet_core_flutter_native/wallet_core');
    expect(s.file!.pathSegments.last, 'libTrustWalletCore.so');
    expect(_lastBytes, androidArm64);
  });

  test('Linux: no asset, no failure', () async {
    await testCodeBuildHook(
      mainMethod: hook.main,
      targetOS: OS.linux,
      targetArchitecture: Architecture.x64,
      userDefines: defines(),
      check: (input, output) => expect(output.assets.code, isEmpty),
    );
  });
}

Uint8List? _lastBytes;
