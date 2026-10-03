// Opening an .xcframework — a directory or a .zip — and finding its slices.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.
//
// Upstream ships its iOS library as a zipped xcframework, so the iOS checks
// want a second real input besides our relinked dylibs: the one upstream users
// ship today. A .zip is unpacked into TMPDIR and deleted afterwards; nothing
// is written inside the repository, and nothing found inside is executed —
// system tools are pointed at the files, that is all.

import 'dart:io';

import 'host.dart';
import 'proc.dart';

class XcframeworkSlice {
  const XcframeworkSlice({required this.identifier, required this.binaryPath});

  /// The slice directory name, e.g. `ios-arm64_x86_64-simulator`.
  final String identifier;

  /// The Mach-O inside the slice's `.framework`.
  final String binaryPath;
}

class OpenedXcframework {
  OpenedXcframework({required this.slices, required this.temporary});

  final List<XcframeworkSlice> slices;

  /// The scratch directory a `.zip` was unpacked into, deleted by [dispose].
  final Directory? temporary;

  void dispose() {
    final directory = temporary;
    if (directory != null && directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  }
}

/// Opens [path], unzipping it first when it is an archive.
OpenedXcframework openXcframework(String path) {
  Directory? temporary;
  var root = path;

  if (path.endsWith('.zip')) {
    if (!File(path).existsSync()) {
      throw ArgumentError('no such archive: $path');
    }
    temporary = scratchDirectory('wcf-xcframework-');
    final unzip = run('unzip', ['-q', '-o', path, '-d', temporary.path]);
    if (!unzip.ok) {
      temporary.deleteSync(recursive: true);
      throw StateError('could not unzip $path: ${unzip.stderr}');
    }
    final entries = temporary
        .listSync()
        .whereType<Directory>()
        .where((d) => d.path.endsWith('.xcframework'))
        .toList();
    if (entries.isEmpty) {
      temporary.deleteSync(recursive: true);
      throw StateError('no .xcframework inside $path');
    }
    root = entries.first.path;
  }

  final directory = Directory(root);
  if (!directory.existsSync()) {
    temporary?.deleteSync(recursive: true);
    throw ArgumentError('no such xcframework: $root');
  }

  final slices = <XcframeworkSlice>[];
  final sliceDirectories = directory.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final slice in sliceDirectories) {
    final identifier = slice.path.split(Platform.pathSeparator).last;
    final frameworks = slice
        .listSync()
        .whereType<Directory>()
        .where((d) => d.path.endsWith('.framework'))
        .toList();
    for (final framework in frameworks) {
      final name = framework.path
          .split(Platform.pathSeparator)
          .last
          .replaceAll('.framework', '');
      final binary = File('${framework.path}/$name');
      if (binary.existsSync()) {
        slices.add(
          XcframeworkSlice(identifier: identifier, binaryPath: binary.path),
        );
      }
    }
  }

  return OpenedXcframework(slices: slices, temporary: temporary);
}
