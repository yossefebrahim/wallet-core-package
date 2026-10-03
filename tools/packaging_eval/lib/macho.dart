// Parsers for the Mach-O tools: lipo, vtool, otool, nm, codesign.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.
//
// Every function here is pure: it takes the text a tool printed and returns
// what it means. The tests feed them saved outputs committed under
// fixtures/tool_output/, the way check_alignment.sh's --readelf-output does.

/// One architecture inside a universal (fat) Mach-O.
class FatSlice {
  const FatSlice({
    required this.arch,
    required this.offset,
    required this.size,
    required this.align,
  });

  final String arch;
  final int offset;
  final int size;

  /// Alignment as the power of two `lipo` reports (`align 2^14` -> 14).
  final int align;

  int get alignBytes => 1 << align;

  Map<String, Object?> toJson() => {
    'arch': arch,
    'offset': offset,
    'size': size,
    'align_pow2': align,
    'align_bytes': alignBytes,
  };
}

/// `lipo -info FILE`, both the thin and the fat wording.
///
///   Non-fat file: libX.dylib is architecture: arm64
///   Architectures in the fat file: libX.dylib are: x86_64 arm64
List<String> parseLipoInfo(String output) {
  for (final line in output.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final fat = RegExp(r'are:\s*(.+)$').firstMatch(trimmed);
    if (trimmed.startsWith('Architectures in the fat file') && fat != null) {
      return fat.group(1)!.trim().split(RegExp(r'\s+'));
    }
    final thin = RegExp(r'is architecture:\s*(\S+)').firstMatch(trimmed);
    if (thin != null) return [thin.group(1)!];
  }
  return const [];
}

/// `lipo -detailed_info FILE` for a fat file. Returns an empty list for a thin
/// one, which prints no `architecture` blocks.
List<FatSlice> parseLipoDetailedInfo(String output) {
  final slices = <FatSlice>[];
  String? arch;
  int? offset;
  int? size;
  int? align;

  void flush() {
    if (arch != null && offset != null && size != null && align != null) {
      slices.add(
        FatSlice(arch: arch!, offset: offset!, size: size!, align: align!),
      );
    }
    arch = null;
    offset = null;
    size = null;
    align = null;
  }

  for (final line in output.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('architecture ')) {
      flush();
      arch = trimmed.substring('architecture '.length).trim();
      continue;
    }
    if (arch == null) continue;
    final offsetMatch = RegExp(r'^offset\s+(\d+)$').firstMatch(trimmed);
    if (offsetMatch != null) offset = int.parse(offsetMatch.group(1)!);
    final sizeMatch = RegExp(r'^size\s+(\d+)$').firstMatch(trimmed);
    if (sizeMatch != null) size = int.parse(sizeMatch.group(1)!);
    final alignMatch = RegExp(r'^align\s+2\^(\d+)').firstMatch(trimmed);
    if (alignMatch != null) align = int.parse(alignMatch.group(1)!);
  }
  flush();
  return slices;
}

/// The deployment target of one slice.
class BuildVersion {
  const BuildVersion({
    required this.platform,
    required this.minOs,
    required this.sdk,
    required this.loadCommand,
  });

  final String platform;
  final String minOs;
  final String sdk;

  /// `LC_BUILD_VERSION` on a modern binary, `LC_VERSION_MIN_*` on an old one.
  final String loadCommand;

  Map<String, Object?> toJson() => {
    'platform': platform,
    'min_os': minOs,
    'sdk': sdk,
    'load_command': loadCommand,
  };
}

/// `vtool -arch <arch> -show-build FILE`.
///
///       cmd LC_BUILD_VERSION
///  platform IOS
///     minos 13.0
///       sdk 26.5
///
/// Also understands the older `LC_VERSION_MIN_IPHONEOS` form, whose fields are
/// `version` and `sdk` and whose platform is implied by the command name.
BuildVersion? parseVtoolShowBuild(String output) {
  String? command;
  String? platform;
  String? minOs;
  String? sdk;
  for (final line in output.split('\n')) {
    final trimmed = line.trim();
    final match = RegExp(r'^(\w+)\s+(\S+)$').firstMatch(trimmed);
    if (match == null) continue;
    final key = match.group(1)!;
    final value = match.group(2)!;
    switch (key) {
      case 'cmd':
        if (value.startsWith('LC_BUILD_VERSION') ||
            value.startsWith('LC_VERSION_MIN_')) {
          command = value;
          platform ??= _platformFromVersionMin(value);
        }
      case 'platform':
        platform = value;
      case 'minos':
      case 'version':
        minOs ??= value;
      case 'sdk':
        sdk ??= value;
    }
  }
  if (command == null || minOs == null) return null;
  return BuildVersion(
    platform: platform ?? 'UNKNOWN',
    minOs: minOs,
    sdk: sdk ?? 'unknown',
    loadCommand: command,
  );
}

String? _platformFromVersionMin(String command) => switch (command) {
  'LC_VERSION_MIN_IPHONEOS' => 'IOS',
  'LC_VERSION_MIN_MACOSX' => 'MACOS',
  'LC_VERSION_MIN_TVOS' => 'TVOS',
  'LC_VERSION_MIN_WATCHOS' => 'WATCHOS',
  _ => null,
};

/// `otool -L`: the install name (first line after the header) and every
/// dependent library. The header line is `<path>:` or
/// `<path> (architecture arm64):`.
class LinkedLibraries {
  const LinkedLibraries({
    required this.installName,
    required this.dependencies,
  });

  final String? installName;
  final List<String> dependencies;
}

LinkedLibraries parseOtoolL(String output) {
  final entries = <String>[];
  for (final line in output.split('\n')) {
    if (!line.startsWith('\t') && !line.startsWith('  ')) continue;
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final match = RegExp(
      r'^(\S.*?)\s+\(compatibility version',
    ).firstMatch(trimmed);
    if (match != null) entries.add(match.group(1)!);
  }
  if (entries.isEmpty) {
    return const LinkedLibraries(installName: null, dependencies: []);
  }
  return LinkedLibraries(
    installName: entries.first,
    dependencies: entries.skip(1).toList(),
  );
}

/// `otool -D`: the install name on the line after the header.
String? parseOtoolD(String output) {
  final lines = output
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].endsWith(':')) {
      if (i + 1 < lines.length) return lines[i + 1];
    }
  }
  return lines.length == 1 ? lines.single : null;
}

/// `otool -l`: every `LC_RPATH`'s path.
///
///      cmd LC_RPATH
///  cmdsize 32
///     path @loader_path/Frameworks (offset 12)
List<String> parseOtoolRpaths(String output) {
  final rpaths = <String>[];
  var inRpath = false;
  for (final line in output.split('\n')) {
    final trimmed = line.trim();
    if (trimmed == 'cmd LC_RPATH') {
      inRpath = true;
      continue;
    }
    if (trimmed.startsWith('cmd ')) {
      inRpath = false;
      continue;
    }
    if (!inRpath) continue;
    final match = RegExp(
      r'^path\s+(.+?)(\s+\(offset \d+\))?$',
    ).firstMatch(trimmed);
    if (match != null) {
      rpaths.add(match.group(1)!.trim());
      inRpath = false;
    }
  }
  return rpaths;
}

/// `nm` output. Three shapes, all of which end in the symbol name:
///   `0000000000c026d8 D _AptosDP`      defined, `nm -gU`
///   `                 U _stat`         undefined, `nm`
///   `_stat`                            undefined, `nm -u`
/// Banner lines (`libX.dylib (for architecture arm64):`) are dropped.
/// Returns the names in file order.
List<String> parseNmNames(String output) {
  final names = <String>[];
  for (final line in output.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    if (trimmed.endsWith(':')) continue;
    final fields = trimmed.split(RegExp(r'\s+'));
    final name = fields.last;
    if (!RegExp(r'^[A-Za-z_$][A-Za-z0-9_.$]*$').hasMatch(name)) continue;
    names.add(name);
  }
  return names;
}

/// How a Mach-O is signed. `codesign -dv` exits non-zero on an unsigned file
/// and says so on stderr; that is a fact to record, not a failure (our
/// relinked dylibs are expected unsigned — DECISION-9 §5 leaves signing to the
/// packaging option).
enum SigningState { unsigned, adhoc, signed, unknown }

class CodesignInfo {
  const CodesignInfo({
    required this.state,
    this.identifier,
    this.teamIdentifier,
    this.authority,
  });

  final SigningState state;
  final String? identifier;
  final String? teamIdentifier;
  final String? authority;

  Map<String, Object?> toJson() => {
    'state': state.name,
    if (identifier != null) 'identifier': identifier,
    if (teamIdentifier != null) 'team_identifier': teamIdentifier,
    if (authority != null) 'authority': authority,
  };
}

CodesignInfo parseCodesignOutput(String output) {
  if (output.contains('code object is not signed at all')) {
    return const CodesignInfo(state: SigningState.unsigned);
  }
  String? identifier;
  String? teamIdentifier;
  String? authority;
  var adhoc = false;
  for (final line in output.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('Identifier=')) {
      identifier = trimmed.substring('Identifier='.length);
    } else if (trimmed.startsWith('TeamIdentifier=')) {
      teamIdentifier = trimmed.substring('TeamIdentifier='.length);
    } else if (trimmed.startsWith('Authority=')) {
      authority ??= trimmed.substring('Authority='.length);
    } else if (trimmed.startsWith('Signature=adhoc')) {
      adhoc = true;
    }
  }
  if (identifier == null && !adhoc) {
    return const CodesignInfo(state: SigningState.unknown);
  }
  return CodesignInfo(
    state: adhoc ? SigningState.adhoc : SigningState.signed,
    identifier: identifier,
    teamIdentifier: teamIdentifier,
    authority: authority,
  );
}
