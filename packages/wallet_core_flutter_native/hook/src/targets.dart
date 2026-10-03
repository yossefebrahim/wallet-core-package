/// Which manifest artifact one hook invocation bundles, and under what name.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// Pure: no file, no process, no network. The hook is invoked once per target
/// OS, architecture and — on iOS — SDK (`iphoneos`, `iphonesimulator`), and
/// every one of those invocations must emit the **same asset id and the same
/// file name** (PRD §12.1, iOS row): Flutter combines the per-architecture
/// files of one asset id with `lipo` and wraps them in one framework named
/// after the file, so a `_sim` or per-architecture suffix would split one
/// library into several frameworks.
library;

import 'package:code_assets/code_assets.dart';

import 'slices.dart';

/// The asset name inside this package; the asset id is
/// `package:wallet_core_flutter_native/wallet_core`. One id for every target.
const String codeAssetName = 'wallet_core';

/// The file every Apple invocation emits. Flutter turns it into
/// `TrustWalletCore.framework/TrustWalletCore` (drops `lib` and `.dylib`).
const String appleLibraryFileName = 'libTrustWalletCore.dylib';

/// The file every Android invocation emits; Flutter packages it as
/// `lib/<abi>/libTrustWalletCore.so`.
const String androidLibraryFileName = 'libTrustWalletCore.so';

/// The Android ABI directory name for [architecture], or `null` when no
/// artifact is shipped for it.
///
/// `ia32` (x86) and `riscv64` are deliberately absent: the artifact set has no
/// 32-bit x86 or RISC-V library, and PRD §12.2 step 8 ships an ABI only if it
/// is tested.
String? androidAbi(Architecture architecture) => switch (architecture) {
  Architecture.arm64 => 'arm64-v8a',
  Architecture.arm => 'armeabi-v7a',
  Architecture.x64 => 'x86_64',
  _ => null,
};

/// The Mach-O slice [architecture] names, or `null` when Apple has none we
/// ship.
MachOArch? machOArch(Architecture architecture) => switch (architecture) {
  Architecture.arm64 => MachOArch.arm64,
  Architecture.x64 => MachOArch.x86_64,
  _ => null,
};

/// What one invocation bundles.
final class ArtifactSelection {
  const ArtifactSelection({
    required this.target,
    required this.candidates,
    required this.fileName,
    required this.slice,
    this.optional = false,
  });

  /// Whether a manifest without an artifact for this target means "no asset"
  /// rather than a failed build.
  ///
  /// True for macOS only. macOS is a development host, not a shipped
  /// platform (PRD §12), but every `flutter test` on a Mac runs this hook for
  /// macOS — in this package, in the SDK, and in every consumer's project —
  /// so a manifest that ships no macOS library must not fail those runs. A
  /// macOS artifact that *is* listed is still verified like any other, and a
  /// listed one that cannot be verified still fails the build.
  final bool optional;

  /// Human-readable target, for messages: `iOS iphonesimulator arm64`.
  final String target;

  /// Manifest logical names that can serve this target, most specific first:
  /// a thin per-architecture artifact before a universal one. The first one
  /// the manifest lists wins ([chooseLogicalName]).
  final List<String> candidates;

  /// The file name emitted, identical across every SDK and architecture of
  /// one OS.
  final String fileName;

  /// What must be taken out of the verified artifact: the Mach-O slice to
  /// extract on Apple, the ELF machine to confirm on Android.
  final SliceSpec slice;
}

/// The hook cannot serve this target. The build fails with [message].
final class UnsupportedTarget implements Exception {
  const UnsupportedTarget(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The artifact for [os]/[architecture]/[iosSdk], or `null` when this package
/// ships no library for [os] at all.
///
/// `null` is not an error: a Linux or Windows desktop build, or a host
/// `flutter test` on such a machine, gets no asset and the loader reports the
/// absence at run time, rather than every consumer build on an unsupported
/// host failing. A *supported* OS with an unsupported architecture or SDK
/// throws [UnsupportedTarget] — that is a build that would ship a broken app.
ArtifactSelection? selectArtifact({
  required OS os,
  required Architecture architecture,
  IOSSdk? iosSdk,
}) {
  if (os == OS.android) {
    final abi = androidAbi(architecture);
    if (abi == null) {
      throw UnsupportedTarget(
        'Android ${architecture.name} is not shipped: the artifact set has '
        'arm64-v8a, armeabi-v7a and x86_64 libraries only. Restrict the app '
        'to those ABIs (android.defaultConfig.ndk.abiFilters).',
      );
    }
    return ArtifactSelection(
      target: 'Android $abi',
      candidates: ['android/$abi/$androidLibraryFileName'],
      fileName: androidLibraryFileName,
      slice: SliceSpec.elf(ElfMachine.forAndroidAbi(abi)),
    );
  }

  if (os == OS.iOS) {
    if (iosSdk == null) {
      throw const UnsupportedTarget(
        'iOS build with no target SDK in the hook input; expected iphoneos or '
        'iphonesimulator',
      );
    }
    final arch = machOArch(architecture);
    final device = iosSdk == IOSSdk.iPhoneOS;
    if (arch == null || (device && arch != MachOArch.arm64)) {
      throw UnsupportedTarget(
        'iOS $iosSdk ${architecture.name} is not shipped: the artifact set has '
        'an arm64 device library and an arm64 + x86_64 simulator library.',
      );
    }
    final directory = device ? 'ios' : 'ios-simulator';
    return ArtifactSelection(
      target: 'iOS $iosSdk ${architecture.name}',
      candidates: [
        '$directory/${arch.abiName}/$appleLibraryFileName',
        if (!device) '$directory/arm64_x86_64/$appleLibraryFileName',
      ],
      fileName: appleLibraryFileName,
      slice: SliceSpec.machO(arch),
    );
  }

  if (os == OS.macOS) {
    final arch = machOArch(architecture);
    if (arch == null) {
      throw UnsupportedTarget(
        'macOS ${architecture.name} is not shipped: the artifact set has an '
        'arm64 + x86_64 macOS library.',
      );
    }
    return ArtifactSelection(
      target: 'macOS ${architecture.name}',
      candidates: [
        'macos/${arch.abiName}/$appleLibraryFileName',
        'macos/arm64_x86_64/$appleLibraryFileName',
      ],
      fileName: appleLibraryFileName,
      slice: SliceSpec.machO(arch),
      optional: true,
    );
  }

  return null;
}

/// The first of [selection]'s candidates that [manifestKeys] contains.
///
/// Throws [UnsupportedTarget] naming every candidate and every key when none
/// is there — the shape of the manifest, not the target, is then what is
/// wrong, and the message says so.
String chooseLogicalName(
  ArtifactSelection selection,
  Iterable<String> manifestKeys, {
  required String manifestSource,
}) {
  final keys = manifestKeys.toSet();
  for (final candidate in selection.candidates) {
    if (keys.contains(candidate)) return candidate;
  }
  final listed = keys.isEmpty ? '  (none)' : keys.map((k) => '  $k').join('\n');
  throw UnsupportedTarget(
    '$manifestSource has no artifact for ${selection.target}.\n'
    'Looked for:\n${selection.candidates.map((c) => '  $c').join('\n')}\n'
    'The manifest lists:\n$listed\n'
    'A build hook bundles one library per SDK and architecture, so this '
    'packaging option needs per-slice library artifacts (an Apple .dylib per '
    'SDK, an Android .so per ABI); an .xcframework.zip cannot be bundled by a '
    'hook.',
  );
}
