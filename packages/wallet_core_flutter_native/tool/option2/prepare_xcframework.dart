/// Produces the pod's `Frameworks/TrustWalletCore.xcframework` from verified
/// manifest artifacts.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// DECISION-2 Option 2 (evaluation branch, T1.9). Run by
/// `ios/wallet_core_flutter_native.podspec` while CocoaPods evaluates it during
/// `pod install`, never by hand in a normal build:
///
/// ```
/// dart --packages=<app>/.dart_tool/package_config.json \
///     <package>/tool/option2/prepare_xcframework.dart \
///     --manifest <compat_manifest.json> --out <pod>/Frameworks \
///     --work <pod>/.wcf_work --privacy-manifest <pod>/Resources/PrivacyInfo.xcprivacy \
///     --deployment-target 13.0 [--vendored <dir>] [--offline] [--cache-dir <dir>]
/// ```
///
/// 1. The manifest's iOS rows are obtained through `tool/fetch_artifacts.dart`
///    (`src/verified_acquisition.dart`): sha256 and size verified, no flag
///    accepts a mismatch. A failure here fails `pod install`.
/// 2. **Assemble** (the dylib rows of a local or relinked set): each verified
///    dylib is *moved* into a framework bundle, given the install name
///    `@rpath/TrustWalletCore.framework/TrustWalletCore`, an `Info.plist`, and
///    the pod's `PrivacyInfo.xcprivacy`, and the bundle is signed ad hoc; the
///    xcframework's own `Info.plist` lists the two slices. **Unzip** (a
///    CI-produced `ios/TrustWalletCore.xcframework.zip` row): the verified zip
///    is expanded with `ditto` and vendored exactly as shipped, its signature
///    untouched.
/// 3. Two stamps are written next to the xcframework — the sha256 of the
///    manifest bytes it was built from, and the sha256 of every framework
///    binary — which the pod's build-time script phase re-checks, so a manifest
///    edited after `pod install`, or a binary changed after it, fails the
///    Xcode build too.
///
/// `--work` and `--out` sit in the pod directory, which every app using this
/// copy of the package shares. Steps 1–3 therefore run under an exclusive
/// lock on `<work>/.lock`, and the fetch passes write into a fresh
/// `<work>/run-*` directory that only this run uses and that is removed when
/// it ends; the stamps always describe the set this run verified.
///
/// Build time only: nothing here is part of the package's library API and
/// nothing under `lib/` imports it (AGENTS.md rule 3).
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'src/verified_acquisition.dart';
import 'src/xcframework_plan.dart';

/// The stamp holding the manifest digest the xcframework was built from.
const String manifestStampName = 'wcf_manifest.sha256';

/// The stamp holding every framework binary's digest, in `shasum -c` format.
const String binariesStampName = 'wcf_binaries.sha256';

Future<void> main(List<String> argv) async {
  exitCode = await prepareXcframework(argv);
}

/// The command, separated from [main] for tests.
Future<int> prepareXcframework(
  List<String> argv, {
  String? packageDir,
  Map<String, String>? environment,
}) async {
  final PrepareArgs args;
  try {
    args = PrepareArgs.parse(
      argv,
      extraOptions: const {'privacy-manifest', 'deployment-target'},
    );
    for (final required in const ['privacy-manifest', 'deployment-target']) {
      if (!args.extra.containsKey(required)) {
        throw FormatException('--$required is required');
      }
    }
  } on FormatException catch (e) {
    stderr.writeln('prepare_xcframework: ${e.message}');
    return prepareUsageExit;
  }
  if (!Platform.isMacOS) {
    stderr.writeln(
      'prepare_xcframework: an xcframework is built on macOS only',
    );
    return prepareUsageExit;
  }

  // The pod directory — and with it `--work` and `--out` — is shared by every
  // app that uses this copy of the package (for a hosted package, the
  // pub-cache copy). Without the lock, a concurrent `pod install` against
  // another manifest can replace this run's verified files between the copy-out
  // pass and the rename, and this run would then stamp the other set's
  // binaries with this run's manifest digest. Released when the process ends,
  // whatever way it ends.
  final work = Directory(args.work)..createSync(recursive: true);
  final lock = File(
    '${work.path}/$lockFileName',
  ).openSync(mode: FileMode.append);
  try {
    try {
      lock.lockSync(FileLock.exclusive);
    } on FileSystemException {
      stdout.writeln(
        'wallet_core_flutter_native: waiting for another prepare step '
        '(${lock.path})',
      );
      await lock.lock(FileLock.blockingExclusive);
    }
    // Under the lock no other prepare step runs, so a `run-*` directory left
    // here is a crashed run's.
    for (final stale in work.listSync().whereType<Directory>()) {
      if (_isRunDirectory(stale)) stale.deleteSync(recursive: true);
    }
    final run = work.createTempSync(runDirectoryPrefix);
    try {
      return await _prepareLocked(
        args.withWork(run.path),
        packageDir: packageDir,
        environment: environment,
      );
    } finally {
      if (run.existsSync()) run.deleteSync(recursive: true);
    }
  } finally {
    lock.closeSync();
  }
}

/// The lock file under `--work`, held for the whole prepare-and-stamp step.
const String lockFileName = '.lock';

/// The prefix of the directory under `--work` that one run owns.
const String runDirectoryPrefix = 'run-';

bool _isRunDirectory(Directory directory) => directory.uri.pathSegments
    .lastWhere((s) => s.isNotEmpty)
    .startsWith(runDirectoryPrefix);

/// Everything after the lock: [args] `.work` is this run's own directory.
Future<int> _prepareLocked(
  PrepareArgs args, {
  String? packageDir,
  Map<String, String>? environment,
}) async {
  final manifestBytes = File(args.manifest).readAsBytesSync();
  final XcframeworkPlan plan;
  try {
    final decoded = jsonDecode(utf8.decode(manifestBytes));
    if (decoded is! Map<String, Object?>) {
      throw XcframeworkPlanException('${args.manifest} is not a JSON object');
    }
    plan = xcframeworkPlan(
      decoded,
      podDeploymentTarget: args.extra['deployment-target']!,
    );
  } on Object catch (e) {
    stderr.writeln('prepare_xcframework: ${args.manifest}: $e');
    return preparePlanExit;
  }

  stdout.writeln(
    'wallet_core_flutter_native: packaging for iOS '
    '(${plan is ZipPlan ? "verify and unzip $xcframeworkZipLogicalName" : "assemble $xcframeworkDirName"})',
  );
  if (plan is AssemblePlan) {
    for (final slice in plan.slices) {
      stdout.writeln('  $slice');
    }
  }

  final code = await acquireVerified(
    packageDir: packageDir ?? packageDirOfScript(),
    args: args,
    logicalNames: plan.logicalNames,
    environment: environment,
  );
  if (code != 0) {
    stderr.writeln(
      'wallet_core_flutter_native: the native artifacts did not verify '
      'against ${args.manifest} (fetch tool exit $code). No xcframework was '
      'produced; pod install stops here.',
    );
    return code;
  }

  final build = Directory('${args.work}/assembly')..createSync();
  final xcframework = Directory('${build.path}/$xcframeworkDirName');

  try {
    switch (plan) {
      case ZipPlan():
        _run('ditto', [
          '-x',
          '-k',
          '${args.work}/$xcframeworkZipLogicalName',
          build.path,
        ]);
        if (!File('${xcframework.path}/Info.plist').existsSync()) {
          throw StateError(
            '$xcframeworkZipLogicalName did not contain '
            '$xcframeworkDirName/Info.plist at its root',
          );
        }
      case AssemblePlan():
        _assemble(
          plan,
          xcframework: xcframework,
          work: args.work,
          privacyManifest: args.extra['privacy-manifest']!,
        );
    }
  } on Object catch (e) {
    stderr.writeln('prepare_xcframework: $e');
    return 1;
  }

  final out = Directory(args.out);
  if (out.existsSync()) out.deleteSync(recursive: true);
  out.createSync(recursive: true);
  xcframework.renameSync('${out.path}/$xcframeworkDirName');

  final binaries = _frameworkBinaries(out);
  if (binaries.isEmpty) {
    stderr.writeln('prepare_xcframework: no framework binary in ${out.path}');
    return 1;
  }
  File('${out.path}/$binariesStampName').writeAsStringSync(
    binaries
        .map(
          (relative) =>
              '${_sha256(File('${out.path}/$relative').readAsBytesSync())}  '
              '$relative\n',
        )
        .join(),
  );
  File(
    '${out.path}/$manifestStampName',
  ).writeAsStringSync('${_sha256(manifestBytes)}\n');

  stdout.writeln(
    'wallet_core_flutter_native: ${out.path}/$xcframeworkDirName '
    '(${binaries.length} slices) from ${args.manifest}',
  );
  return 0;
}

void _assemble(
  AssemblePlan plan, {
  required Directory xcframework,
  required String work,
  required String privacyManifest,
}) {
  for (final slice in plan.slices) {
    final bundle = Directory(
      '${xcframework.path}/${slice.libraryIdentifier}/$frameworkName.framework',
    )..createSync(recursive: true);
    final binary = '${bundle.path}/$frameworkName';
    // A rename, not a copy: these are the bytes the fetch tool just verified
    // in this directory.
    File('$work/${slice.logicalName}').renameSync(binary);

    final archs = _run('lipo', ['-archs', binary]).trim().split(' ').toSet();
    if (archs.length != slice.archs.length || !archs.containsAll(slice.archs)) {
      throw StateError(
        '${slice.logicalName} contains ${archs.join(", ")} but its manifest '
        'abi "${slice.abi}" says ${slice.archs.join(", ")}',
      );
    }
    // Changes the binary, so it invalidates the ad hoc signature the fat
    // simulator dylib was linked with; the bundle is re-signed below.
    _run('install_name_tool', ['-id', frameworkInstallName, binary]);
    File(
      '${bundle.path}/Info.plist',
    ).writeAsStringSync(frameworkInfoPlist(slice, plan));
    // Apple's guidance for a framework is a privacy manifest at the bundle
    // root; the pod also ships it as a resource bundle (see the podspec).
    File(privacyManifest).copySync('${bundle.path}/PrivacyInfo.xcprivacy');
    // Ad hoc: seals the binary, Info.plist and PrivacyInfo.xcprivacy. The
    // app's [CP] Embed Pods Frameworks phase re-signs with the app's identity
    // whenever the app itself is signed.
    _run('codesign', [
      '--force',
      '--sign',
      '-',
      '--timestamp=none',
      bundle.path,
    ]);
  }
  File(
    '${xcframework.path}/Info.plist',
  ).writeAsStringSync(xcframeworkInfoPlist(plan));
}

/// `<slice>/TrustWalletCore.framework/TrustWalletCore` for every slice under
/// [out]/TrustWalletCore.xcframework, relative to [out], sorted.
List<String> _frameworkBinaries(Directory out) {
  final root = Directory('${out.path}/$xcframeworkDirName');
  final found = <String>[];
  for (final slice in root.listSync().whereType<Directory>()) {
    final name = slice.uri.pathSegments.where((s) => s.isNotEmpty).last;
    final relative =
        '$xcframeworkDirName/$name/$frameworkName.framework/$frameworkName';
    if (File('${out.path}/$relative').existsSync()) found.add(relative);
  }
  return found..sort();
}

String _run(String executable, List<String> arguments) {
  final result = Process.runSync(executable, arguments);
  if (result.exitCode != 0) {
    throw StateError(
      '$executable ${arguments.join(" ")} exited ${result.exitCode}:\n'
      '${result.stdout}${result.stderr}',
    );
  }
  return result.stdout as String;
}

// Integrity hashing of this step's own output (PRD §12.3; AGENTS.md rule 2
// permits it): the build-time script phase compares these with `shasum`.
String _sha256(List<int> bytes) => sha256.convert(bytes).toString();
