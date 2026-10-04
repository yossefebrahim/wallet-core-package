// Parsers for the two tools/native_build gate scripts and for zipalign.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.
//
// The gates are *called*, not reimplemented (T1.2 owns them): the packaged
// library is checked by the same code that checked the built artifact. What
// lives here is the reading of their logs, so the harness can decide pass/fail
// itself — which matters for a target where a gate's own verdict is not the
// question being asked (upstream's framework carries no wcf_build_info, and
// that is expected rather than a failure).

/// One architecture's line group out of `check_exports.sh`.
class ArchExports {
  const ArchExports({
    required this.arch,
    required this.definedExternal,
    required this.twExports,
    required this.expected,
    required this.missing,
    required this.unexpected,
    required this.identityExported,
    this.allowedExtra = const [],
  });

  final String arch;
  final int definedExternal;

  /// Every exported `TW*` name, [allowedExtra] included.
  final int twExports;
  final int expected;
  final int missing;

  /// `TW*` exports outside the list and outside [allowedExtra].
  final int unexpected;
  final bool identityExported;

  /// `TW*` exports outside the list that the caller named as expected extras
  /// (`check_exports.sh --allow-extra`): upstream's JNI glue on Android.
  final List<String> allowedExtra;

  bool get reconciles => missing == 0 && unexpected == 0;

  Map<String, Object?> toJson() => {
    'arch': arch,
    'defined_external_symbols': definedExternal,
    'tw_exports': twExports,
    'expected': expected,
    'missing': missing,
    'unexpected': unexpected,
    'identity_symbol_exported': identityExported,
    if (allowedExtra.isNotEmpty) 'allowed_extra': allowedExtra,
  };
}

/// The exports of an ELF shared library, read from its **dynamic** symbol
/// table: the output of
///
///   `llvm-nm --dynamic --defined-only --extern-only <library.so>`
///
/// reconciled against [expected] the way `tools/native_build/check_exports.sh`
/// does since 56560e8. `.dynsym` is what a consumer can `dlsym`, and it is the
/// only symbol table a stripped release `.so` keeps: without `--dynamic`,
/// llvm-nm reads `.symtab`, finds none, prints `<file>: no symbols` (on
/// stderr), and every count is 0 — the harness defect this replaces
/// (T1.8b-d1).
///
/// A defined-external line is `<address> <type> <name>`. The name filter is
/// the gate's own (`$NF ~ /^[A-Za-z_][A-Za-z0-9_.$]*$/`, so a versioned
/// `name@@VER` counts for nothing); a line also needs a hex address and a
/// one-letter type, so a diagnostic such as `<file>: no symbols` is not read
/// as a symbol called `symbols` when stderr is mixed in. ELF names carry no
/// leading underscore. [allowExtra] are `TW*` names outside the list that are
/// not a failure (the gate's `--allow-extra`).
ArchExports parseElfDynamicExports(
  String nmOutput, {
  required Iterable<String> expected,
  Iterable<String> allowExtra = const [],
  String identitySymbol = 'wcf_build_info',
}) {
  final namePattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_.$]*$');
  final addressPattern = RegExp(r'^[0-9A-Fa-f]+$');
  final typePattern = RegExp(r'^[A-Za-z]$');
  final all = <String>{};
  for (final line in nmOutput.split('\n')) {
    final fields = line.trim().split(RegExp(r'\s+'));
    if (fields.length != 3 ||
        !addressPattern.hasMatch(fields[0]) ||
        !typePattern.hasMatch(fields[1])) {
      continue;
    }
    final name = fields.last;
    if (namePattern.hasMatch(name)) all.add(name);
  }
  final expectedSet = expected.toSet();
  final allowedSet = allowExtra.toSet();
  final tw = all.where((n) => RegExp(r'^TW[A-Za-z0-9_]*$').hasMatch(n)).toSet();
  final extra = tw.difference(expectedSet);
  final allowed = extra.intersection(allowedSet).toList()..sort();
  return ArchExports(
    arch: '.dynsym',
    definedExternal: all.length,
    twExports: tw.length,
    expected: expectedSet.length,
    missing: expectedSet.difference(tw).length,
    unexpected: extra.length - allowed.length,
    identityExported: all.contains(identitySymbol),
    allowedExtra: allowed,
  );
}

/// Reads `check_exports.sh`'s log (it writes to stderr through `wcf_log`).
///
///   arch arm64: 29435 defined external symbols, 464 of them TW*
///   arch arm64: expected 464, missing 0, unexpected 0
///   arch arm64: _wcf_build_info exported: yes
///
/// A thin binary logs `arch (single architecture): …`.
List<ArchExports> parseCheckExportsLog(String log) {
  final counts = <String, List<int>>{};
  final reconciliation = <String, List<int>>{};
  final identity = <String, bool>{};
  final order = <String>[];

  void note(String arch) {
    if (!order.contains(arch)) order.add(arch);
  }

  for (final line in log.split('\n')) {
    final trimmed = line.trim();
    final archMatch = RegExp(r'^arch (.+?): (.*)$').firstMatch(trimmed);
    if (archMatch == null) continue;
    final arch = archMatch.group(1)!;
    final rest = archMatch.group(2)!;

    final countMatch = RegExp(
      r'^(\d+) defined external symbols, (\d+) of them TW\*$',
    ).firstMatch(rest);
    if (countMatch != null) {
      note(arch);
      counts[arch] = [
        int.parse(countMatch.group(1)!),
        int.parse(countMatch.group(2)!),
      ];
      continue;
    }

    final reconcileMatch = RegExp(
      r'^expected (\d+), missing (\d+), unexpected (\d+)$',
    ).firstMatch(rest);
    if (reconcileMatch != null) {
      note(arch);
      reconciliation[arch] = [
        int.parse(reconcileMatch.group(1)!),
        int.parse(reconcileMatch.group(2)!),
        int.parse(reconcileMatch.group(3)!),
      ];
      continue;
    }

    final identityMatch = RegExp(
      r'^_?\w+ exported: (yes|no)$',
    ).firstMatch(rest);
    if (identityMatch != null) {
      note(arch);
      identity[arch] = identityMatch.group(1) == 'yes';
    }
  }

  return [
    for (final arch in order)
      ArchExports(
        arch: arch == '(single architecture)' ? 'single' : arch,
        definedExternal: counts[arch]?[0] ?? -1,
        twExports: counts[arch]?[1] ?? -1,
        expected: reconciliation[arch]?[0] ?? -1,
        missing: reconciliation[arch]?[1] ?? -1,
        unexpected: reconciliation[arch]?[2] ?? -1,
        identityExported: identity[arch] ?? false,
      ),
  ];
}

/// The verdict of `check_alignment.sh`.
class AlignmentGateResult {
  const AlignmentGateResult({
    required this.loadSegments,
    required this.belowAlignment,
    required this.requiredAlign,
    required this.skippedAs32Bit,
  });

  final int loadSegments;
  final int belowAlignment;
  final String requiredAlign;
  final bool skippedAs32Bit;

  bool get passed => !skippedAs32Bit && loadSegments > 0 && belowAlignment == 0;

  Map<String, Object?> toJson() => {
    'load_segments': loadSegments,
    'below_required_alignment': belowAlignment,
    'required_align': requiredAlign,
    'skipped_32_bit': skippedAs32Bit,
  };
}

/// Reads `check_alignment.sh`'s log.
///
///   4 LOAD segments, 0 below the required alignment 0x4000
AlignmentGateResult? parseCheckAlignmentLog(String log) {
  if (log.contains('is a 32-bit ELF; 16 KB alignment does not apply')) {
    return const AlignmentGateResult(
      loadSegments: 0,
      belowAlignment: 0,
      requiredAlign: '0x4000',
      skippedAs32Bit: true,
    );
  }
  final match = RegExp(
    r'(\d+) LOAD segments, (\d+) below the required alignment (\S+)',
  ).firstMatch(log);
  if (match == null) return null;
  return AlignmentGateResult(
    loadSegments: int.parse(match.group(1)!),
    belowAlignment: int.parse(match.group(2)!),
    requiredAlign: match.group(3)!,
    skippedAs32Bit: false,
  );
}

/// One entry of a `zipalign -c -v` listing.
class ZipalignEntry {
  const ZipalignEntry({
    required this.offset,
    required this.name,
    required this.verdict,
  });

  final int offset;
  final String name;

  /// `OK`, `OK - directory`, `OK - compressed`, or `BAD - <offset>`.
  final String verdict;

  bool get bad => verdict.startsWith('BAD');
  bool get isSharedObject => name.endsWith('.so');
}

/// The parsed result of `zipalign -c -P 16 -v 4 <apk>`.
class ZipalignReport {
  const ZipalignReport({
    required this.archive,
    required this.entries,
    required this.verified,
  });

  final String? archive;
  final List<ZipalignEntry> entries;

  /// `Verification successful` was printed.
  final bool verified;

  List<ZipalignEntry> get badEntries =>
      entries.where((e) => e.bad).toList(growable: false);

  List<ZipalignEntry> get badSharedObjects =>
      badEntries.where((e) => e.isSharedObject).toList(growable: false);

  List<ZipalignEntry> get sharedObjects =>
      entries.where((e) => e.isSharedObject).toList(growable: false);

  Map<String, Object?> toJson() => {
    if (archive != null) 'archive': archive,
    'entries': entries.length,
    'shared_objects': sharedObjects.length,
    'bad_entries': badEntries.length,
    'bad_shared_objects': badSharedObjects.length,
    'verified': verified,
  };
}

/// Reads `zipalign -c -P 16 -v 4 <apk>`.
///
///   Verifying alignment of aligned.apk (4)...
///        16384 lib/arm64-v8a/libc++_shared.so (OK)
///          138 lib/arm64-v8a/libc++_shared.so (BAD - 138)
///   Verification successful
///
/// `-P 16` is the flag that checks uncompressed `.so` entries against 16 KB
/// boundaries; `4` is the general entry alignment. Recorded verbatim in every
/// row this parser feeds (PRD §12.2 step 8).
ZipalignReport parseZipalignCheck(String output) {
  String? archive;
  final entries = <ZipalignEntry>[];
  var verified = false;
  for (final line in output.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final header = RegExp(
      r'^Verifying alignment of (.+?) \(\d+\)\.\.\.$',
    ).firstMatch(trimmed);
    if (header != null) {
      archive = header.group(1);
      continue;
    }
    if (trimmed == 'Verification successful') {
      verified = true;
      continue;
    }
    if (trimmed == 'Verification FAILED') continue;
    final entry = RegExp(r'^(\d+)\s+(.+?)\s+\((.+)\)$').firstMatch(trimmed);
    if (entry != null) {
      entries.add(
        ZipalignEntry(
          offset: int.parse(entry.group(1)!),
          name: entry.group(2)!,
          verdict: entry.group(3)!,
        ),
      );
    }
  }
  return ZipalignReport(archive: archive, entries: entries, verified: verified);
}
