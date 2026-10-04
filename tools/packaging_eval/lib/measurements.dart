// The measurements. Each returns result rows and knows nothing about build
// hooks, podspecs, Gradle plugins, or which option is being evaluated: it
// measures files and app bundles.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.

import 'dart:convert';
import 'dart:io';

import 'artifact_record.dart';
import 'gates.dart';
import 'gradle_libcxx.dart';
import 'host.dart';
import 'macho.dart';
import 'mini_yaml.dart';
import 'proc.dart';
import 'required_reason.dart';
import 'results.dart';

/// `19 721 208` as `18.81 MiB`, for a table cell.
String humanBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KiB', 'MiB', 'GiB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(2)} ${units[unit]}';
}

int directorySize(Directory directory) {
  var total = 0;
  for (final entity in directory.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File) total += entity.lengthSync();
  }
  return total;
}

/// Size of an app bundle (`.app` directory), an `.apk`/`.ipa`/`.aab` file, or
/// any other file or directory.
int? bundleSize(String path) {
  final directory = Directory(path);
  if (directory.existsSync()) return directorySize(directory);
  final file = File(path);
  if (file.existsSync()) return file.lengthSync();
  return null;
}

// ---------------------------------------------------------------------------
// size — PRD §12.2 step 5
// ---------------------------------------------------------------------------

/// Per-artifact size, thin-slice sizes of a fat Mach-O, and the cross-check
/// against the DECISION-14 §5.1 record for the same file.
List<ResultRow> measureSize({
  required String artifact,
  required String target,
}) {
  final file = File(artifact);
  if (!file.existsSync()) {
    return [
      ResultRow(
        check: 'size',
        target: target,
        status: CheckStatus.unmeasured,
        command: formatCommand('wc', ['-c', artifact]),
        notes: 'no such file: $artifact',
      ),
    ];
  }

  final size = file.lengthSync();
  final values = <String, Object?>{
    'path': artifact,
    'size_bytes': size,
    'size_human': humanBytes(size),
  };
  final commands = <String>[
    formatCommand('wc', ['-c', artifact]),
  ];
  final notes = <String>[];
  var status = CheckStatus.pass;

  // Thin slices, when the file is a universal Mach-O.
  final detailed = run('lipo', ['-detailed_info', artifact]);
  if (detailed.ok) {
    commands.add(detailed.command);
    final slices = parseLipoDetailedInfo(detailed.stdout);
    if (slices.isNotEmpty) {
      values['slices'] = [for (final slice in slices) slice.toJson()];
      values['slice_sizes'] = {
        for (final slice in slices) slice.arch: slice.size,
      };
    } else {
      values['slices'] = const <Object?>[];
      final info = run('lipo', ['-info', artifact]);
      if (info.ok) {
        commands.add(info.command);
        values['architectures'] = parseLipoInfo(info.stdout);
      }
    }
  }

  // Cross-check against the record (DECISION-14 §5.1).
  final record = ArtifactRecord.forArtifact(artifact);
  if (record != null) {
    values['record'] = record.recordPath;
    values['record_size'] = record.size;
    values['record_sha256'] = record.sha256;
    values['provenance'] = record.provenance;
    if (record.size != null && record.size != size) {
      status = CheckStatus.fail;
      notes.add(
        'record says ${record.size} bytes, the file is $size bytes '
        '(${record.recordPath})',
      );
    }
    final digest = sha256OfFile(artifact);
    if (digest != null) {
      values['sha256'] = digest;
      commands.add(formatCommand('shasum', ['-a', '256', artifact]));
      if (record.sha256 != null && record.sha256 != digest) {
        status = CheckStatus.fail;
        notes.add(
          'record sha256 ${record.sha256} does not match the file '
          '($digest)',
        );
      }
    }
  }

  final sliceSizes = values['slice_sizes'];
  final summary = sliceSizes is Map<String, Object?> && sliceSizes.isNotEmpty
      ? '${humanBytes(size)} '
            '(${sliceSizes.entries.map((e) => '${e.key} ${humanBytes(e.value! as int)}').join(', ')})'
      : humanBytes(size);
  values['summary'] = summary;

  return [
    ResultRow(
      check: 'size',
      target: target,
      status: status,
      values: values,
      command: commands.join(' ; '),
      notes: notes.join('; '),
    ),
  ];
}

/// App-size delta: the same app built without and with the SDK.
List<ResultRow> measureAppSizeDelta({
  required String baselineApp,
  required String sdkApp,
  required String target,
}) {
  final command =
      'du -sb ${shellQuote(baselineApp)} ${shellQuote(sdkApp)} '
      '(bundle byte totals, differenced)';
  final baseline = bundleSize(baselineApp);
  final withSdk = bundleSize(sdkApp);
  if (baseline == null || withSdk == null) {
    return [
      ResultRow(
        check: 'app-size-delta',
        target: target,
        status: CheckStatus.unmeasured,
        command: command,
        notes: [
          if (baseline == null) 'no baseline app at $baselineApp',
          if (withSdk == null) 'no SDK app at $sdkApp',
        ].join('; '),
      ),
    ];
  }
  final delta = withSdk - baseline;
  return [
    ResultRow(
      check: 'app-size-delta',
      target: target,
      status: CheckStatus.pass,
      values: {
        'baseline_bytes': baseline,
        'with_sdk_bytes': withSdk,
        'delta_bytes': delta,
        'summary':
            '+${humanBytes(delta)} (${humanBytes(baseline)} -> '
            '${humanBytes(withSdk)})',
      },
      command: command,
    ),
  ];
}

// ---------------------------------------------------------------------------
// symbols — PRD §12.2 step 4
// ---------------------------------------------------------------------------

/// The 464 exported `TW*` function names, derived from T1.3's inventory.json.
/// Never hand-maintained: the list is a projection of the generated file.
List<String> exportedTwFunctions(String inventoryPath) {
  final json = jsonDecode(File(inventoryPath).readAsStringSync());
  if (json is! Map<String, Object?>) {
    throw FormatException('$inventoryPath is not a JSON object');
  }
  final symbols = json['symbols'];
  if (symbols is! Map<String, Object?>) {
    throw FormatException('$inventoryPath has no `symbols` map');
  }
  final names = <String>[
    for (final entry in symbols.entries)
      if (entry.value is Map<String, Object?> &&
          (entry.value! as Map<String, Object?>)['kind'] == 'function' &&
          entry.key.startsWith('TW'))
        entry.key,
  ]..sort();
  return names;
}

/// Export presence and visibility of the shipped library, against a symbol
/// list derived from inventory.json. One row per architecture.
///
/// Mach-O: by calling `tools/native_build/check_exports.sh`. ELF: by reading
/// the dynamic symbol table directly ([measureElfSymbols]).
///
/// [expectIdentity] is false for a library that is not ours — upstream's
/// framework carries no `wcf_build_info`, and that is a fact to record rather
/// than a failure of the packaging option. [allowExtra] names `TW*` exports
/// outside the list that are not a failure (ELF only: upstream's JNI glue).
List<ResultRow> measureSymbols({
  required String artifact,
  required String format,
  required String target,
  String? inventoryPath,
  String? nmPath,
  bool expectIdentity = true,
  List<String> allowExtra = const [],
}) {
  final inventory = inventoryPath ?? inventoryJsonPath();
  if (format == 'elf' && File(artifact).existsSync()) {
    return measureElfSymbols(
      artifact: artifact,
      target: target,
      inventoryPath: inventory,
      nmPath: nmPath,
      expectIdentity: expectIdentity,
      allowExtra: allowExtra,
    );
  }
  if (!File(artifact).existsSync()) {
    return [
      ResultRow(
        check: 'symbols',
        target: target,
        status: CheckStatus.unmeasured,
        command:
            'tools/native_build/check_exports.sh --binary ${shellQuote(artifact)} '
            '--symbol-list <inventory-derived> --format $format',
        notes: 'no such file: $artifact',
      ),
    ];
  }

  final scratch = scratchDirectory('wcf-symbols-');
  try {
    final names = exportedTwFunctions(inventory);
    final listFile = File('${scratch.path}/tw_symbols.txt')
      ..writeAsStringSync('${names.join('\n')}\n');

    final gate = run(nativeBuildScript('check_exports.sh'), [
      '--binary',
      artifact,
      '--symbol-list',
      listFile.path,
      '--format',
      format,
      if (nmPath != null) ...['--nm', nmPath],
    ]);

    final archs = parseCheckExportsLog(gate.combined);
    final command =
        '${gate.command}   # symbol list: '
        '${names.length} exported TW* functions projected from '
        '${_relative(inventory)}';

    if (archs.isEmpty) {
      return [
        ResultRow(
          check: 'symbols',
          target: target,
          status: CheckStatus.fail,
          values: {'summary': 'gate produced no per-architecture output'},
          command: command,
          notes: gate.combined.trim().split('\n').take(5).join(' / '),
        ),
      ];
    }

    return [
      for (final arch in archs)
        ResultRow(
          check: 'symbols',
          target: target,
          status: arch.reconciles && (!expectIdentity || arch.identityExported)
              ? CheckStatus.pass
              : CheckStatus.fail,
          values: {
            ...arch.toJson(),
            'symbol_list_size': names.length,
            'symbol_list_source': _relative(inventory),
            'identity_expected': expectIdentity,
            'summary':
                '${arch.arch}: ${arch.twExports}/${arch.expected} TW*, '
                '${arch.definedExternal} defined external, wcf_build_info '
                '${arch.identityExported ? 'yes' : 'no'}',
          },
          command: command,
          notes: [
            if (!expectIdentity && !arch.identityExported)
              'no wcf_build_info: expected for a library we did not relink',
            if (arch.missing > 0) '${arch.missing} names missing',
            if (arch.unexpected > 0)
              '${arch.unexpected} unexpected TW* exports (stale symbol list)',
          ].join('; '),
        ),
    ];
  } finally {
    scratch.deleteSync(recursive: true);
  }
}

/// The ELF half of [measureSymbols]: one row, from
///
///   `llvm-nm --dynamic --defined-only --extern-only <artifact>`
///
/// run here and reconciled by [parseElfDynamicExports] — the command
/// `check_exports.sh` runs for ELF since 56560e8. It is run directly rather
/// than through the gate so the measurement does not depend on which version
/// of the gate a checkout carries: a gate without `--dynamic` reads `.symtab`,
/// which a stripped release `.so` does not have, and reports 0 exports.
/// [nmPath] is the NDK's llvm-nm (neither `nm` nor `llvm-nm` on a macOS PATH
/// reads ELF reliably); without one the row is `unmeasured`.
List<ResultRow> measureElfSymbols({
  required String artifact,
  required String target,
  required String inventoryPath,
  String? nmPath,
  bool expectIdentity = true,
  List<String> allowExtra = const [],
}) {
  const nmFlags = ['--dynamic', '--defined-only', '--extern-only'];
  final names = exportedTwFunctions(inventoryPath);
  final listNote =
      '# symbol list: ${names.length} exported TW* functions projected from '
      '${_relative(inventoryPath)}'
      '${allowExtra.isEmpty ? '' : '; allowed extra: ${allowExtra.join(', ')}'}';
  if (nmPath == null) {
    return [
      ResultRow(
        check: 'symbols',
        target: target,
        status: CheckStatus.unmeasured,
        values: {'summary': 'no NDK llvm-nm'},
        command:
            '\$ANDROID_NDK/toolchains/llvm/prebuilt/<host>/bin/llvm-nm '
            '${nmFlags.join(' ')} ${shellQuote(artifact)}   $listNote',
        notes:
            'no llvm-nm: no NDK found under \$ANDROID_NDK, \$ANDROID_HOME/ndk '
            'or ~/Library/Android/sdk/ndk; pass --nm',
      ),
    ];
  }
  final result = run(nmPath, [...nmFlags, artifact]);
  final command = '${result.command}   $listNote';
  if (!result.ok) {
    return [
      ResultRow(
        check: 'symbols',
        target: target,
        status: CheckStatus.fail,
        values: {'summary': 'llvm-nm exited ${result.exitCode}'},
        command: command,
        notes: result.combined.trim().split('\n').take(5).join(' / '),
      ),
    ];
  }
  final arch = parseElfDynamicExports(
    result.stdout,
    expected: names,
    allowExtra: allowExtra,
  );
  final listed = arch.twExports - arch.allowedExtra.length - arch.unexpected;
  return [
    ResultRow(
      check: 'symbols',
      target: target,
      status: arch.reconciles && (!expectIdentity || arch.identityExported)
          ? CheckStatus.pass
          : CheckStatus.fail,
      values: {
        ...arch.toJson(),
        'symbol_list_size': names.length,
        'symbol_list_source': _relative(inventoryPath),
        'identity_expected': expectIdentity,
        'summary':
            '${arch.arch}: $listed/${arch.expected} TW*, '
            '${arch.definedExternal} defined external, wcf_build_info '
            '${arch.identityExported ? 'yes' : 'no'}'
            '${arch.allowedExtra.isEmpty ? '' : ', ${arch.allowedExtra.length} allowed extra'}',
      },
      command: command,
      notes: [
        'read from the dynamic symbol table (.dynsym), what dlsym resolves',
        if (arch.allowedExtra.isNotEmpty)
          '${arch.allowedExtra.length} TW* exports outside the list, allowed: '
              '${arch.allowedExtra.join(', ')}',
        if (!expectIdentity && !arch.identityExported)
          'no wcf_build_info: expected for a library we did not relink',
        if (arch.missing > 0) '${arch.missing} names missing',
        if (arch.unexpected > 0)
          '${arch.unexpected} unexpected TW* exports (stale symbol list)',
      ].join('; '),
    ),
  ];
}

// ---------------------------------------------------------------------------
// alignment — PRD §12.2 step 8
// ---------------------------------------------------------------------------

/// 16 KB ELF `LOAD`-segment alignment, by calling
/// `tools/native_build/check_alignment.sh`.
List<ResultRow> measureElfAlignment({
  required String target,
  String? binary,
  String? readelfOutput,
  String? readelfPath,
}) {
  final readelf = readelfPath ?? ndkLlvmTool('llvm-readelf');
  final arguments = <String>[
    if (binary != null) ...['--binary', binary],
    if (readelfOutput != null) ...['--readelf-output', readelfOutput],
    if (binary != null && readelf != null) ...['--readelf', readelf],
  ];
  final script = nativeBuildScript('check_alignment.sh');

  if (binary != null && !File(binary).existsSync()) {
    return [
      ResultRow(
        check: 'alignment',
        target: target,
        status: CheckStatus.unmeasured,
        command: formatCommand(script, [
          '--binary',
          binary,
          '--readelf',
          readelf ??
              '\$ANDROID_NDK/toolchains/llvm/prebuilt/<host>/bin/llvm-readelf',
        ]),
        notes: 'no such file: $binary',
      ),
    ];
  }
  if (binary != null && readelf == null) {
    return [
      ResultRow(
        check: 'alignment',
        target: target,
        status: CheckStatus.unmeasured,
        command: formatCommand(script, [
          '--binary',
          binary,
          '--readelf',
          '\$ANDROID_NDK/toolchains/llvm/prebuilt/<host>/bin/llvm-readelf',
        ]),
        notes:
            'no llvm-readelf: neither readelf nor llvm-readelf is on PATH on '
            'macOS and no NDK was found',
      ),
    ];
  }

  final gate = run(script, arguments);
  final parsed = parseCheckAlignmentLog(gate.combined);
  if (parsed == null) {
    return [
      ResultRow(
        check: 'alignment',
        target: target,
        status: CheckStatus.fail,
        values: {'summary': 'no LOAD segment summary in the gate output'},
        command: gate.command,
        notes: gate.combined.trim().split('\n').take(5).join(' / '),
      ),
    ];
  }
  return [
    ResultRow(
      check: 'alignment',
      target: target,
      status: parsed.skippedAs32Bit
          ? CheckStatus.skip
          : parsed.passed
          ? CheckStatus.pass
          : CheckStatus.fail,
      values: {
        ...parsed.toJson(),
        'binary': ?binary,
        'summary': parsed.skippedAs32Bit
            ? '32-bit ELF, not applicable'
            : '${parsed.loadSegments} LOAD @ ${parsed.requiredAlign}, '
                  '${parsed.belowAlignment} below',
      },
      command: gate.command,
      notes: parsed.skippedAs32Bit
          ? '16 KB alignment is a 64-bit ABI requirement'
          : '',
    ),
  ];
}

/// APK/AAB packaging alignment: `zipalign -c -P 16 -v 4 <apk>`.
///
/// `-P 16` is the flag that checks uncompressed `.so` entries against 16 KB
/// boundaries; without it `zipalign -c 4` passes an APK that a 16 KB-page
/// device will refuse to load.
List<ResultRow> measureApkAlignment({
  required String target,
  String? apk,
  String? zipalignOutput,
  String? zipalignBinary,
}) {
  final String output;
  final String command;

  if (zipalignOutput != null) {
    final file = File(zipalignOutput);
    if (!file.existsSync()) {
      return [
        ResultRow(
          check: 'alignment-apk',
          target: target,
          status: CheckStatus.unmeasured,
          command: 'zipalign -c -P 16 -v 4 <apk>',
          notes: 'no such saved output: $zipalignOutput',
        ),
      ];
    }
    output = file.readAsStringSync();
    command = 'zipalign -c -P 16 -v 4 <apk>   # replayed from $zipalignOutput';
  } else {
    final zipalign = zipalignBinary ?? zipalignPath();
    if (apk == null || !File(apk).existsSync() || zipalign == null) {
      return [
        ResultRow(
          check: 'alignment-apk',
          target: target,
          status: CheckStatus.unmeasured,
          command:
              '${zipalign ?? '\$ANDROID_HOME/build-tools/<version>/zipalign'} '
              '-c -P 16 -v 4 ${apk == null ? '<apk>' : shellQuote(apk)}',
          notes: [
            if (apk == null) 'no APK given',
            if (apk != null && !File(apk).existsSync()) 'no such APK: $apk',
            if (zipalign == null) 'zipalign not found',
          ].join('; '),
        ),
      ];
    }
    final result = run(zipalign, ['-c', '-P', '16', '-v', '4', apk]);
    output = result.combined;
    command = result.command;
  }

  final report = parseZipalignCheck(output);
  return [
    ResultRow(
      check: 'alignment-apk',
      target: target,
      status: report.verified && report.badSharedObjects.isEmpty
          ? CheckStatus.pass
          : CheckStatus.fail,
      values: {
        ...report.toJson(),
        'bad_shared_object_names': [
          for (final entry in report.badSharedObjects) entry.name,
        ],
        'summary':
            '${report.sharedObjects.length} .so entries, '
            '${report.badSharedObjects.length} off a 16 KB boundary',
      },
      command: command,
      notes: report.verified
          ? ''
          : 'zipalign reported Verification FAILED (exit 1)',
    ),
  ];
}

// ---------------------------------------------------------------------------
// libcxx-conflict — PRD §12.2 step 9
// ---------------------------------------------------------------------------

List<ResultRow> measureLibcxxConflict({
  required String target,
  String? gradleOutputPath,
  String? buildCommand,
}) {
  final fallbackCommand =
      buildCommand ??
      'flutter build apk --debug 2>&1 | tee "\$OUT/gradle.log"  # consumer app '
          'with the SDK and tools/packaging_eval/fixtures/libcxx_plugin';
  if (gradleOutputPath == null || !File(gradleOutputPath).existsSync()) {
    return [
      ResultRow(
        check: 'libcxx-conflict',
        target: target,
        status: CheckStatus.unmeasured,
        command: fallbackCommand,
        notes: gradleOutputPath == null
            ? 'no Android build log given; no Android artifact exists to build '
                  'against'
            : 'no such build log: $gradleOutputPath',
      ),
    ];
  }
  final report = classifyGradleOutput(
    File(gradleOutputPath).readAsStringSync(),
  );
  return [
    ResultRow(
      check: 'libcxx-conflict',
      target: target,
      status: switch (report.outcome) {
        LibcxxOutcome.singleCopy ||
        LibcxxOutcome.pickFirstResolved => CheckStatus.pass,
        LibcxxOutcome.duplicateFailure ||
        LibcxxOutcome.versionConflict => CheckStatus.fail,
        LibcxxOutcome.unknown => CheckStatus.unmeasured,
      },
      values: {
        ...report.toJson(),
        'log': gradleOutputPath,
        'summary': report.outcome.name,
      },
      command: '$fallbackCommand   # classified from $gradleOutputPath',
      notes: report.evidence.take(2).join(' / '),
    ),
  ];
}

// ---------------------------------------------------------------------------
// ios-archive — PRD §12.2 step 10
// ---------------------------------------------------------------------------

/// Deployment target, exported-symbol visibility, install name and rpaths,
/// linked libraries, code-signing state, and the required-reason API scan, per
/// architecture of a Mach-O.
Future<List<ResultRow>> measureIosArchive({
  required String binary,
  required String target,
  RequiredReasonApis? apis,
}) async {
  if (!File(binary).existsSync()) {
    return [
      ResultRow(
        check: 'ios-archive',
        target: target,
        status: CheckStatus.unmeasured,
        command:
            'vtool -arch <arch> -show-build ${shellQuote(binary)} ; '
            'nm -gU -arch <arch> ${shellQuote(binary)} ; '
            'nm -u -arch <arch> ${shellQuote(binary)} ; '
            'otool -D -arch <arch> ${shellQuote(binary)} ; '
            'codesign -dv ${shellQuote(binary)}',
        notes: 'no such file: $binary',
      ),
    ];
  }
  final requiredReason = apis ?? await RequiredReasonApis.load();

  final info = run('lipo', ['-info', binary]);
  final architectures = info.ok ? parseLipoInfo(info.stdout) : <String>[];
  if (architectures.isEmpty) {
    return [
      ResultRow(
        check: 'ios-archive',
        target: target,
        status: CheckStatus.fail,
        values: {'summary': 'lipo could not read the file as a Mach-O'},
        command: info.command,
        notes: info.combined.trim().split('\n').take(3).join(' / '),
      ),
    ];
  }

  // Whole-file facts, recorded once and repeated on each architecture's row.
  final codesign = run('codesign', ['-dv', binary]);
  final signing = parseCodesignOutput(codesign.combined);

  final rows = <ResultRow>[];
  for (final arch in architectures) {
    final commands = <String>[];
    final values = <String, Object?>{'arch': arch, 'binary': binary};
    final notes = <String>[];
    var status = CheckStatus.pass;

    final build = run('vtool', ['-arch', arch, '-show-build', binary]);
    commands.add(build.command);
    final version = build.ok ? parseVtoolShowBuild(build.stdout) : null;
    if (version != null) {
      values['deployment_target'] = version.toJson();
    } else {
      status = CheckStatus.fail;
      notes.add('no LC_BUILD_VERSION / LC_VERSION_MIN_* on $arch');
    }

    final exported = run('nm', ['-gU', '-arch', arch, binary]);
    commands.add(exported.command);
    final exportedNames = exported.ok
        ? parseNmNames(exported.stdout)
        : const <String>[];
    final twNames = exportedNames.where((n) => n.startsWith('_TW')).toSet();
    values['exported_symbols'] = exportedNames.length;
    values['exported_tw_functions'] = twNames.length;
    values['identity_symbol_exported'] = exportedNames.contains(
      '_wcf_build_info',
    );

    final undefined = run('nm', ['-u', '-arch', arch, binary]);
    commands.add(undefined.command);
    final undefinedNames = undefined.ok
        ? parseNmNames(undefined.stdout)
        : const <String>[];
    values['undefined_symbols'] = undefinedNames.length;
    final hits = scanRequiredReasonApis(requiredReason, undefinedNames);
    final withHits = hits.where((h) => h.any).toList();
    values['required_reason_apis'] = {
      'source': requiredReason.source,
      'transcribed_on': requiredReason.transcribedOn,
      'categories': [for (final hit in withHits) hit.toJson()],
    };

    final installName = run('otool', ['-D', '-arch', arch, binary]);
    commands.add(installName.command);
    if (installName.ok) {
      values['install_name'] = parseOtoolD(installName.stdout);
    }

    final loadCommands = run('otool', ['-l', '-arch', arch, binary]);
    commands.add(loadCommands.command);
    if (loadCommands.ok) {
      values['rpaths'] = parseOtoolRpaths(loadCommands.stdout);
    }

    final linked = run('otool', ['-L', '-arch', arch, binary]);
    commands.add(linked.command);
    if (linked.ok) {
      values['linked_libraries'] = parseOtoolL(linked.stdout).dependencies;
    }

    commands.add(codesign.command);
    values['codesign'] = signing.toJson();
    notes.add(
      'code signing recorded, not a pass/fail criterion: '
      '${signing.state.name}',
    );

    final categorySummary = withHits.isEmpty
        ? 'no required-reason hits'
        : '${withHits.length} required-reason '
              '${withHits.length == 1 ? 'category' : 'categories'} '
              '(${withHits.map((h) => h.symbols.join(',')).join(' | ')})';
    if (withHits.isNotEmpty) {
      notes.add(
        'a PrivacyInfo.xcprivacy declaring these categories is required of '
        'the app that links this library (PRD §12.2 step 10)',
      );
    }

    values['summary'] =
        '$arch: min ${version?.platform ?? '?'} ${version?.minOs ?? '?'}, '
        '${twNames.length} TW* of ${exportedNames.length} exports, '
        '${signing.state.name}, $categorySummary';

    rows.add(
      ResultRow(
        check: 'ios-archive',
        target: target,
        status: status,
        values: values,
        command: commands.join(' ; '),
        notes: notes.join('; '),
      ),
    );
  }
  return rows;
}

/// Symbols defined in more than one of [binaries], per architecture.
///
/// Streamed and hashed, not compared pairwise: an upstream-style build exports
/// on the order of 57 174 names per slice (DECISION-9 §5), so the scan is
/// O(n log n) in the number of symbols and never materialises a cross product.
Future<List<ResultRow>> measureDuplicateSymbols({
  required List<String> binaries,
  required String target,
  String? nmPath,
}) async {
  final missing = binaries.where((b) => !File(b).existsSync()).toList();
  final nm = nmPath ?? 'nm';
  final commandTemplate = binaries
      .map((b) => '$nm -gU -arch <arch> ${shellQuote(b)}')
      .join(' ; ');
  if (binaries.length < 2 || missing.isNotEmpty) {
    return [
      ResultRow(
        check: 'ios-duplicate-symbols',
        target: target,
        status: CheckStatus.unmeasured,
        command: binaries.length < 2
            ? '$nm -gU -arch <arch> <libA> ; $nm -gU -arch <arch> <libB>'
            : commandTemplate,
        notes: binaries.length < 2
            ? 'a duplicate-symbol scan needs at least two libraries that would '
                  'both be linked into one app'
            : 'missing: ${missing.join(', ')}',
      ),
    ];
  }

  // Architectures common to every input; a symbol only collides within one.
  final perBinaryArchs = <String, List<String>>{};
  for (final binary in binaries) {
    final info = run('lipo', ['-info', binary]);
    perBinaryArchs[binary] = info.ok ? parseLipoInfo(info.stdout) : const [];
  }
  final shared =
      perBinaryArchs.values
          .map((a) => a.toSet())
          .reduce((a, b) => a.intersection(b))
          .toList()
        ..sort();

  final rows = <ResultRow>[];
  for (final arch in shared) {
    final owner = <String, int>{};
    final duplicates = <String, Set<int>>{};
    final commands = <String>[];
    var totals = 0;

    for (var index = 0; index < binaries.length; index++) {
      final result = await runStreaming(
        nm,
        ['-gU', '-arch', arch, binaries[index]],
        (line) {
          final names = parseNmNames(line);
          if (names.isEmpty) return;
          final name = names.single;
          totals++;
          final first = owner[name];
          if (first == null) {
            owner[name] = index;
          } else if (first != index) {
            duplicates.putIfAbsent(name, () => {first}).add(index);
          }
        },
      );
      commands.add(result.command);
    }

    final names = duplicates.keys.toList()..sort();
    rows.add(
      ResultRow(
        check: 'ios-duplicate-symbols',
        target: target,
        status: names.isEmpty ? CheckStatus.pass : CheckStatus.fail,
        values: {
          'arch': arch,
          'libraries': binaries,
          'symbols_scanned': totals,
          'distinct_symbols': owner.length,
          'duplicate_symbols': names.length,
          'first_duplicates': names.take(20).toList(),
          'summary':
              '$arch: ${names.length} of ${owner.length} names defined in '
              'more than one of ${binaries.length} libraries',
        },
        command: commands.join(' ; '),
        notes: names.isEmpty
            ? ''
            : 'two libraries in one app define the same names; the linker '
                  'picks one and which one is not something the app controls',
      ),
    );
  }
  return rows;
}

// ---------------------------------------------------------------------------
// min-version — PRD §12.2 step 6
// ---------------------------------------------------------------------------

/// Records the host Flutter/Dart versions and the `environment:` constraints
/// the three packages declare.
///
/// The step's real question — the minimum Flutter each packaging option needs
/// — is a statement the evaluation makes from a successful build on the oldest
/// Flutter it tried, not something a scan can answer. This row is the evidence
/// that statement is written against.
List<ResultRow> measureMinVersion({
  required String target,
  List<String>? packagePaths,
}) {
  final root = repoRoot().path;
  final packages =
      packagePaths ??
      [
        '$root/packages/wallet_core_flutter',
        '$root/packages/wallet_core_flutter_bindings',
        '$root/packages/wallet_core_flutter_native',
      ];

  final commands = <String>[];
  final values = <String, Object?>{};

  final flutter = flutterPath();
  if (flutter != null) {
    final version = run(flutter, ['--version', '--machine']);
    commands.add(version.command);
    if (version.ok) {
      try {
        final decoded = jsonDecode(version.stdout);
        if (decoded is Map<String, Object?>) {
          values['flutter_version'] = decoded['frameworkVersion'];
          values['dart_version'] = decoded['dartSdkVersion'];
          values['flutter_channel'] = decoded['channel'];
        }
      } on FormatException {
        values['flutter_version'] = version.stdout.trim();
      }
    }
  }

  final constraints = <String, Object?>{};
  for (final package in packages) {
    final pubspec = File('$package/pubspec.yaml');
    if (!pubspec.existsSync()) continue;
    commands.add('grep -A3 \'^environment:\' ${shellQuote(pubspec.path)}');
    final parsed = parseMiniYaml(pubspec.readAsStringSync());
    final name = parsed['name'] as String? ?? package;
    final environment = parsed['environment'];
    constraints[name] = environment is Map<String, Object?>
        ? environment
        : null;
  }
  values['package_constraints'] = constraints;

  final flutterConstraints = <String>{
    for (final entry in constraints.entries)
      if (entry.value is Map<String, Object?> &&
          (entry.value! as Map<String, Object?>)['flutter'] != null)
        '${(entry.value! as Map<String, Object?>)['flutter']}',
  };
  final sdkConstraints = <String>{
    for (final entry in constraints.entries)
      if (entry.value is Map<String, Object?> &&
          (entry.value! as Map<String, Object?>)['sdk'] != null)
        '${(entry.value! as Map<String, Object?>)['sdk']}',
  };

  values['summary'] =
      'host Flutter ${values['flutter_version'] ?? '?'} / Dart '
      '${values['dart_version'] ?? '?'}; declared sdk '
      '${sdkConstraints.join(', ')}; flutter '
      '${flutterConstraints.join(', ')}';

  return [
    ResultRow(
      check: 'min-version',
      target: target,
      status: flutter == null ? CheckStatus.skip : CheckStatus.pass,
      values: values,
      command: commands.join(' ; '),
      notes:
          'the declared constraints and the host toolchain. The minimum '
          'Flutter each packaging option *needs* is the evaluation\'s '
          'statement from a build on the oldest Flutter it tried '
          '(PRD §12.2 step 6); this row is its evidence, not its answer.',
    ),
  ];
}

String _relative(String path) {
  final root = '${repoRoot().path}/';
  return path.startsWith(root) ? path.substring(root.length) : path;
}
