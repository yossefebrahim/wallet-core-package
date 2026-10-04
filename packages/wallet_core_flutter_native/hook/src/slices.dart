/// Taking one architecture out of a verified artifact.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// Flutter invokes the hook once per architecture and then runs
/// `lipo -create` over the files of one asset id. A universal artifact emitted
/// unchanged for both the arm64 and the x86_64 invocation would make that
/// `lipo` fail ("have the same architectures"), so for a universal Mach-O the
/// hook emits the one slice the invocation is for. A slice is a byte range of
/// the verified file — nothing is re-linked, re-signed or rewritten, and the
/// digest that was checked covers every byte that is emitted.
///
/// For a thin file the same function checks that the file *is* the requested
/// architecture, and for an Android `.so` that its ELF machine is the ABI's.
/// A manifest that files a library under the wrong slice is caught here at
/// build time instead of as a load failure on a device.
///
/// Pure: works on bytes, so the tests use synthetic headers.
library;

import 'dart:typed_data';

/// A Mach-O architecture this package ships, with its `<mach/machine.h>` CPU
/// type and the name the manifest's logical names use.
enum MachOArch {
  arm64(0x0100000c, 'arm64'),
  x86_64(0x01000007, 'x86_64');

  const MachOArch(this.cpuType, this.abiName);

  /// `cputype` in a Mach-O header or a fat-arch entry.
  final int cpuType;

  /// The segment of a manifest logical name: `ios/arm64/…`.
  final String abiName;
}

/// An ELF `e_machine` this package ships, per Android ABI.
enum ElfMachine {
  aarch64(183, 64),
  arm(40, 32),
  x86_64(62, 64);

  const ElfMachine(this.code, this.bits);

  /// `e_machine`.
  final int code;

  /// `EI_CLASS`: 32 or 64.
  final int bits;

  static ElfMachine forAndroidAbi(String abi) => switch (abi) {
    'arm64-v8a' => ElfMachine.aarch64,
    'armeabi-v7a' => ElfMachine.arm,
    'x86_64' => ElfMachine.x86_64,
    _ => throw ArgumentError.value(abi, 'abi', 'not a shipped Android ABI'),
  };
}

/// What to take out of an artifact.
sealed class SliceSpec {
  const SliceSpec();

  const factory SliceSpec.machO(MachOArch arch) = MachOSlice;
  const factory SliceSpec.elf(ElfMachine machine) = ElfSlice;
}

/// One architecture of a Mach-O, thin or universal.
final class MachOSlice extends SliceSpec {
  const MachOSlice(this.arch);
  final MachOArch arch;
}

/// A whole ELF shared object whose machine must be [machine].
final class ElfSlice extends SliceSpec {
  const ElfSlice(this.machine);
  final ElfMachine machine;
}

/// The artifact does not contain what the target needs.
final class SliceError implements Exception {
  const SliceError(this.message);
  final String message;
  @override
  String toString() => message;
}

const int _mhMagic64 = 0xfeedfacf;
const int _mhMagic32 = 0xfeedface;
const int _fatMagic = 0xcafebabe;
const int _fatMagic64 = 0xcafebabf;

/// The bytes of [bytes] to bundle for [spec].
///
/// A view into [bytes], not a copy. [source] names the artifact in errors.
Uint8List takeSlice(Uint8List bytes, SliceSpec spec, {required String source}) {
  return switch (spec) {
    MachOSlice(:final arch) => _machOSlice(bytes, arch, source),
    ElfSlice(:final machine) => _checkElf(bytes, machine, source),
  };
}

Uint8List _machOSlice(Uint8List bytes, MachOArch arch, String source) {
  if (bytes.length < 8) {
    throw SliceError('$source is ${bytes.length} bytes, not a Mach-O file');
  }
  final data = ByteData.sublistView(bytes);
  final big = data.getUint32(0, Endian.big);
  final little = data.getUint32(0, Endian.little);

  if (little == _mhMagic64) {
    final cpu = data.getUint32(4, Endian.little);
    if (cpu != arch.cpuType) {
      throw SliceError(
        '$source is a thin Mach-O for CPU type 0x${cpu.toRadixString(16)}, '
        'not ${arch.name} (0x${arch.cpuType.toRadixString(16)})',
      );
    }
    return bytes;
  }
  if (little == _mhMagic32) {
    throw SliceError('$source is a 32-bit Mach-O; only 64-bit slices ship');
  }
  if (big != _fatMagic && big != _fatMagic64) {
    throw SliceError(
      '$source is not a Mach-O file (magic 0x${big.toRadixString(16)})',
    );
  }

  final wide = big == _fatMagic64;
  final count = data.getUint32(4, Endian.big);
  final entrySize = wide ? 32 : 20;
  if (8 + count * entrySize > bytes.length) {
    throw SliceError('$source has a truncated universal header');
  }
  final found = <String>[];
  for (var i = 0; i < count; i++) {
    final at = 8 + i * entrySize;
    final cpu = data.getUint32(at, Endian.big);
    final offset = wide
        ? data.getUint64(at + 8, Endian.big)
        : data.getUint32(at + 8, Endian.big);
    final size = wide
        ? data.getUint64(at + 16, Endian.big)
        : data.getUint32(at + 12, Endian.big);
    found.add('0x${cpu.toRadixString(16)}');
    if (cpu != arch.cpuType) continue;
    if (offset + size > bytes.length || size < 8) {
      throw SliceError(
        '$source: the ${arch.name} slice (offset $offset, size $size) lies '
        'outside the ${bytes.length}-byte file',
      );
    }
    final slice = Uint8List.sublistView(bytes, offset, offset + size);
    final magic = ByteData.sublistView(slice).getUint32(0, Endian.little);
    if (magic != _mhMagic64) {
      throw SliceError(
        '$source: the ${arch.name} slice does not start with a 64-bit Mach-O '
        'header',
      );
    }
    return slice;
  }
  throw SliceError(
    '$source is a universal Mach-O without a ${arch.name} slice '
    '(CPU types present: ${found.join(', ')})',
  );
}

Uint8List _checkElf(Uint8List bytes, ElfMachine machine, String source) {
  if (bytes.length < 20 ||
      bytes[0] != 0x7f ||
      bytes[1] != 0x45 ||
      bytes[2] != 0x4c ||
      bytes[3] != 0x46) {
    throw SliceError('$source is not an ELF file');
  }
  final bits = switch (bytes[4]) {
    1 => 32,
    2 => 64,
    _ => 0,
  };
  if (bytes[5] != 1) {
    throw SliceError('$source is not a little-endian ELF file');
  }
  final code = ByteData.sublistView(bytes).getUint16(18, Endian.little);
  if (code != machine.code || bits != machine.bits) {
    throw SliceError(
      '$source is ELF$bits machine $code, not ${machine.name} '
      '(ELF${machine.bits} machine ${machine.code})',
    );
  }
  return bytes;
}
