// Synthetic binaries and manifests for the hook tests.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.
//
// The headers are the real on-disk layouts — <mach-o/loader.h> mach_header_64,
// <mach-o/fat.h> fat_header/fat_arch(_64), the ELF identification and
// e_machine — around filler bytes. Nothing here is a working library; the hook
// never runs what it bundles, so the tests need only what it reads.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const int cpuArm64 = 0x0100000c;
const int cpuX86_64 = 0x01000007;

/// A thin 64-bit Mach-O of [length] bytes for [cpuType], filled with [fill].
Uint8List thinMachO(int cpuType, {int length = 64, int fill = 0xab}) {
  final bytes = Uint8List(length)..fillRange(0, length, fill);
  ByteData.sublistView(bytes)
    ..setUint32(0, 0xfeedfacf, Endian.little)
    ..setUint32(4, cpuType, Endian.little);
  return bytes;
}

/// A universal Mach-O holding [slices] at 16-byte-aligned offsets.
Uint8List fatMachO(List<Uint8List> slices, {bool wide = false}) {
  final entrySize = wide ? 32 : 20;
  var offset = 8 + slices.length * entrySize;
  offset = (offset + 15) & ~15;
  final offsets = <int>[];
  for (final slice in slices) {
    offsets.add(offset);
    offset = (offset + slice.length + 15) & ~15;
  }
  final bytes = Uint8List(offset);
  final data = ByteData.sublistView(bytes)
    ..setUint32(0, wide ? 0xcafebabf : 0xcafebabe, Endian.big)
    ..setUint32(4, slices.length, Endian.big);
  for (var i = 0; i < slices.length; i++) {
    final at = 8 + i * entrySize;
    final cpu = ByteData.sublistView(slices[i]).getUint32(4, Endian.little);
    data.setUint32(at, cpu, Endian.big);
    if (wide) {
      data
        ..setUint64(at + 8, offsets[i], Endian.big)
        ..setUint64(at + 16, slices[i].length, Endian.big)
        ..setUint32(at + 24, 4, Endian.big);
    } else {
      data
        ..setUint32(at + 8, offsets[i], Endian.big)
        ..setUint32(at + 12, slices[i].length, Endian.big)
        ..setUint32(at + 16, 4, Endian.big);
    }
    bytes.setRange(offsets[i], offsets[i] + slices[i].length, slices[i]);
  }
  return bytes;
}

/// An ELF header of [length] bytes: [bits] class, little-endian, [machine].
Uint8List elf({required int machine, int bits = 64, int length = 64}) {
  final bytes = Uint8List(length);
  bytes.setRange(0, 4, const [0x7f, 0x45, 0x4c, 0x46]);
  bytes[4] = bits == 64 ? 2 : 1;
  bytes[5] = 1;
  ByteData.sublistView(bytes).setUint16(18, machine, Endian.little);
  return bytes;
}

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

const String fakeSetId = 'as_9.9.9_001';
const String fakeCommit = 'd692ac27749d0c615e17c751b70ab4f0aa75c59b';

/// A manifest in the DECISION-14 §5.1 shape for [artifacts] (logical name →
/// bytes), with an https primary that no test ever contacts: every test that
/// uses it is `--offline` or has the file in a vendored directory.
///
/// [digestOverrides] replaces a recorded digest — consistently in `sha256`
/// and in `asset_name`, so the manifest still agrees with itself and the
/// mismatch is found where it must be, in the bytes.
String manifestFor(
  Map<String, List<int>> artifacts, {
  Map<String, String> digestOverrides = const {},
}) {
  final records = <String, Object?>{};
  artifacts.forEach((name, bytes) {
    final digest = digestOverrides[name] ?? sha256Hex(bytes);
    records[name] = {
      'sha256': digest,
      'size': bytes.length,
      'asset_name': '${fakeSetId}__${digest}__${name.replaceAll('/', '-')}',
      'logical_name': name,
    };
  });
  return const JsonEncoder.withIndent('  ').convert({
    'upstream': {'tag': '9.9.9', 'commit': fakeCommit},
    'artifacts': records,
    'identity': {
      'symbol': 'wcf_build_info',
      'artifact_set_id': fakeSetId,
      'upstream_commit': fakeCommit,
    },
    'retention': {
      'primary': 'https://wcf-test.invalid/never-contacted',
      'mirror': null,
    },
  });
}

/// Writes [artifacts] under [root] laid out by logical name.
void writeVendored(Directory root, Map<String, List<int>> artifacts) {
  artifacts.forEach((name, bytes) {
    File('${root.path}/$name')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes);
  });
}

/// One hex character of [digest] changed: the "flipped digest" of PRD §12.2
/// step 7.
String flipDigest(String digest) =>
    '${digest[0] == '0' ? '1' : '0'}${digest.substring(1)}';
