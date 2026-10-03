// The canonical PRD §12.2 row catalogue and target columns.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.
//
// The evaluation protocol has eleven steps. Some of them this harness
// measures; the rest are the evaluations' own (T1.8, T1.9) or the
// orchestrator's on a device. The catalogue carries all eleven either way, so
// the rendered table is the whole protocol and a step nobody has run yet shows
// as `unmeasured` next to the exact command that will run it — never as a gap
// and never as a pass.

/// Columns for the libraries themselves, measured directly. No debug/release
/// axis: an artifact is one file, built once.
const List<String> artifactTargets = [
  'ios/arm64',
  'ios-simulator/arm64_x86_64',
  'macos/arm64_x86_64',
  'android/arm64-v8a',
  'android/armeabi-v7a',
  'android/x86_64',
  'upstream/ios-arm64',
  'upstream/ios-arm64_x86_64-simulator',
  'ndk/arm64-v8a',
  'ndk/x86_64',
];

/// Columns for the consumer app, per PRD §12.2 step 2 and step 3: each device
/// target in each configuration. Always rendered, measured or not.
const List<String> appTargets = [
  'android-emulator-x86_64/debug',
  'android-emulator-x86_64/release',
  'android-device-arm64-v8a/debug',
  'android-device-arm64-v8a/release',
  'ios-simulator-arm64/debug',
  'ios-simulator-arm64/release',
  'ios-device-arm64/debug',
  'ios-device-arm64/release',
];

/// Columns that are neither a library nor a device.
const List<String> otherTargets = ['host/toolchain', 'consumer/pub'];

const List<String> androidAppTargets = [
  'android-emulator-x86_64/debug',
  'android-emulator-x86_64/release',
  'android-device-arm64-v8a/debug',
  'android-device-arm64-v8a/release',
];

const List<String> iosAppTargets = [
  'ios-simulator-arm64/debug',
  'ios-simulator-arm64/release',
  'ios-device-arm64/debug',
  'ios-device-arm64/release',
];

const List<String> releaseAppTargets = [
  'android-emulator-x86_64/release',
  'android-device-arm64-v8a/release',
  'ios-simulator-arm64/release',
  'ios-device-arm64/release',
];

/// One row of the rendered table.
class StepRow {
  const StepRow({
    required this.step,
    required this.check,
    required this.label,
    required this.targets,
    required this.command,
    this.ownedBy = 'harness',
  });

  /// The PRD §12.2 step this row belongs to, 1..11.
  final int step;

  /// The `check` field of the result rows that fill this row.
  final String check;

  /// Short human label for the leftmost column.
  final String label;

  /// The columns this row applies to. A column outside the list renders `—`
  /// (not applicable); a column inside it with no result renders
  /// `unmeasured` with [command].
  final List<String> targets;

  /// The exact command that produces this row. For a row this harness
  /// measures, it is a `dart run tools/packaging_eval/…` line; for a row the
  /// evaluations own, it is the command they will run.
  final String command;

  /// `harness`, `evaluation` (T1.8/T1.9) or `device` (the orchestrator on real
  /// hardware).
  final String ownedBy;
}

/// The eleven steps, in order, as rows.
const List<StepRow> stepCatalogue = [
  StepRow(
    step: 1,
    check: 'consumer-build',
    label: 'Clean consumer build, no manual native edits',
    targets: appTargets,
    ownedBy: 'evaluation',
    command:
        'flutter create --project-name wcf_eval_consumer "\$OUT/consumer" && '
        'flutter pub add wallet_core_flutter --hosted-url "\$LOCAL_PUB" && '
        'flutter build apk --debug (and --release, and ios --no-codesign)',
  ),
  StepRow(
    step: 2,
    check: 'run-on-target',
    label: 'Runs on emulator, device, simulator',
    targets: appTargets,
    ownedBy: 'device',
    command:
        'flutter run -d <device-id> --debug (and --release) in "\$OUT/consumer"',
  ),
  StepRow(
    step: 3,
    check: 'release-launch-and-sign',
    label: 'Release build launches and signs',
    targets: releaseAppTargets,
    ownedBy: 'device',
    command:
        'flutter run -d <device-id> --release in "\$OUT/consumer", then sign a '
        'transaction through the SDK on the device',
  ),
  StepRow(
    step: 4,
    check: 'symbols',
    label: 'Exported symbols of the shipped library',
    targets: artifactTargets,
    command:
        'dart run tools/packaging_eval/bin/symbols.dart --artifact <library> '
        '--format macho|elf --target <target>',
  ),
  StepRow(
    step: 4,
    check: 'symbols-runtime-lookup',
    label: 'Runtime lookup of the full symbol set',
    targets: appTargets,
    ownedBy: 'device',
    command:
        'flutter test integration_test/symbol_lookup_test.dart -d <device-id> '
        '(T1.7 symbolLookupAll over the 464 names in inventory.json)',
  ),
  StepRow(
    step: 5,
    check: 'size',
    label: 'Library size per ABI/slice',
    targets: artifactTargets,
    command:
        'dart run tools/packaging_eval/bin/size.dart --artifact <library> '
        '--target <target>',
  ),
  StepRow(
    step: 5,
    check: 'app-size-delta',
    label: 'App-size delta against a baseline app',
    targets: appTargets,
    command:
        'dart run tools/packaging_eval/bin/size.dart --baseline-app <bundle> '
        '--sdk-app <bundle> --target <target>',
  ),
  StepRow(
    step: 6,
    check: 'min-version',
    label: 'Declared Flutter/Dart constraints and host toolchain',
    targets: otherTargets,
    command:
        'dart run tools/packaging_eval/bin/min_version.dart '
        '--target host/toolchain',
  ),
  StepRow(
    step: 6,
    check: 'min-version-floor',
    label: 'Lowest Flutter the option builds on',
    targets: appTargets,
    ownedBy: 'evaluation',
    command:
        'repeat step 1 on each candidate Flutter release, oldest first, and '
        'record the oldest that builds: '
        'FLUTTER_ROOT=<sdk> flutter build apk --release in "\$OUT/consumer"',
  ),
  StepRow(
    step: 7,
    check: 'offline-install',
    label: 'Clean install offline; wrong checksum fails loudly',
    targets: appTargets,
    ownedBy: 'evaluation',
    command:
        'flutter pub get with only the artifact fetch reachable, then rerun '
        'with a corrupted sha256 in compat_manifest.json and confirm the build '
        'fails',
  ),
  StepRow(
    step: 8,
    check: 'alignment',
    label: '16 KB ELF LOAD-segment alignment',
    targets: [
      'android/arm64-v8a',
      'android/armeabi-v7a',
      'android/x86_64',
      'ndk/arm64-v8a',
      'ndk/x86_64',
    ],
    command:
        'dart run tools/packaging_eval/bin/alignment.dart --binary <so> '
        '--target <target>',
  ),
  StepRow(
    step: 8,
    check: 'alignment-apk',
    label: '16 KB APK/AAB packaging alignment',
    targets: androidAppTargets,
    command:
        'dart run tools/packaging_eval/bin/alignment.dart --apk <apk> '
        '--target <target>',
  ),
  StepRow(
    step: 9,
    check: 'libcxx-conflict',
    label: 'Second plugin bundling libc++_shared.so',
    targets: androidAppTargets,
    command:
        'tools/packaging_eval/fixtures/libcxx_plugin/tool/materialize_libcxx.sh, '
        'add the fixture plugin and the SDK to the consumer app, then '
        'flutter build apk --debug (and --release) 2>&1 | tee "\$OUT/gradle.log" '
        '&& dart run tools/packaging_eval/bin/libcxx_conflict.dart '
        '--gradle-output "\$OUT/gradle.log" --target <target>',
  ),
  StepRow(
    step: 10,
    check: 'ios-archive',
    label: 'iOS deployment target, visibility, signing, privacy APIs',
    targets: [
      'ios/arm64',
      'ios-simulator/arm64_x86_64',
      'macos/arm64_x86_64',
      'upstream/ios-arm64',
      'upstream/ios-arm64_x86_64-simulator',
    ],
    command:
        'dart run tools/packaging_eval/bin/ios_archive.dart --binary <library> '
        '--target <target>',
  ),
  StepRow(
    step: 10,
    check: 'ios-duplicate-symbols',
    label: 'Duplicate symbols across linked libraries',
    targets: [
      'ios/arm64',
      'ios-simulator/arm64_x86_64',
      'upstream/ios-arm64',
      'upstream/ios-arm64_x86_64-simulator',
    ],
    command:
        'dart run tools/packaging_eval/bin/ios_archive.dart '
        '--duplicate-scan <libA> --duplicate-scan <libB> --target <target>',
  ),
  StepRow(
    step: 10,
    check: 'ios-archive-link',
    label: 'Release archive links',
    targets: iosAppTargets,
    ownedBy: 'evaluation',
    command:
        'xcodebuild archive -workspace "\$OUT/consumer/ios/Runner.xcworkspace" '
        '-scheme Runner -configuration Release -destination '
        "'generic/platform=iOS' -archivePath \"\\\$OUT/consumer.xcarchive\"",
  ),
  StepRow(
    step: 11,
    check: 'consumer-gen',
    label: 'Consumed as hosted packages, never by path',
    targets: ['consumer/pub'],
    command:
        'dart run tools/packaging_eval/bin/consumer_gen.dart '
        '--out-dir "\$OUT/consumer-gen"',
  ),
];
