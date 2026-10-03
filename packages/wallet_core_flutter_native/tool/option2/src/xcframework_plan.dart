/// How the iOS pod obtains `TrustWalletCore.xcframework` from a manifest, and
/// the property lists an assembled one carries.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// DECISION-2 Option 2 (evaluation branch, T1.9). Pure: decoded manifest JSON
/// in, a plan or a property-list string out. The I/O that acts on the plan is
/// `../prepare_xcframework.dart`.
///
/// Two shapes of manifest are understood, decided by which rows it lists:
///
/// | Rows | Plan | Who signs |
/// |---|---|---|
/// | `ios/TrustWalletCore.xcframework.zip` | [ZipPlan]: verify, unzip, vendor as shipped | the CI build that produced the zip |
/// | `ios/<abi>/libTrustWalletCore.dylib` and `ios-simulator/<abi>/libTrustWalletCore.dylib` | [AssemblePlan]: verify, wrap each dylib in a framework bundle, write the xcframework | ad hoc, at `pod install`; the app's embed phase re-signs |
///
/// The zip row wins when present, placeholder or not: a manifest that names
/// an xcframework artifact means that artifact, and a `TBD-` digest on it is
/// the fetch tool's to refuse, not a reason to fall back to something else.
library;

/// The framework's name — and therefore its bundle directory, its binary, and
/// the second iOS default location of the loader
/// (`TrustWalletCore.framework/TrustWalletCore`). `test/packaging/` asserts it
/// matches the loader's `iosFrameworkLibraryPath`.
const String frameworkName = 'TrustWalletCore';

/// The xcframework the podspec vendors, relative to the pod's `Frameworks/`.
const String xcframeworkDirName = '$frameworkName.xcframework';

/// The manifest row of a CI-produced xcframework (the root manifest's row).
const String xcframeworkZipLogicalName = 'ios/$frameworkName.xcframework.zip';

/// The install name every framework slice is given. The dylibs are built as
/// `@rpath/libTrustWalletCore.dylib`; inside a framework bundle the image must
/// name its own path, or the app's load command points at a file the bundle
/// does not contain.
const String frameworkInstallName =
    '@rpath/$frameworkName.framework/$frameworkName';

/// `CFBundleIdentifier` of the framework bundles. Not a package name.
const String frameworkBundleIdentifier = 'dev.wcf.wallet-core-flutter.native';

final RegExp _dylibRow = RegExp(
  r'^(ios|ios-simulator)/([^/]+)/libTrustWalletCore\.dylib$',
);

/// Mach-O architecture names an Apple ABI string can be made of, longest
/// first so `arm64e` is not read as `arm64` followed by garbage.
const List<String> _appleArchs = ['x86_64', 'arm64e', 'arm64', 'armv7'];

/// The architectures named by a manifest `abi` such as `arm64` or
/// `arm64_x86_64` (DECISION-14 §5.1: a fat slice joins them with `_`).
///
/// Throws [FormatException] for anything that is not a `_`-joined sequence of
/// known architecture names — `x86_64` contains the separator, so a naive
/// split would not do.
List<String> archsOfAbi(String abi) {
  final archs = <String>[];
  var rest = abi;
  while (rest.isNotEmpty) {
    final arch = _appleArchs.firstWhere(
      (a) => rest == a || rest.startsWith('${a}_'),
      orElse: () => throw FormatException(
        'not a "_"-joined list of Apple architectures',
        abi,
      ),
    );
    archs.add(arch);
    if (rest.length == arch.length) break;
    rest = rest.substring(arch.length + 1);
    if (rest.isEmpty) {
      throw FormatException('trailing "_"', abi);
    }
  }
  if (archs.isEmpty) {
    throw FormatException('empty ABI', abi);
  }
  return archs;
}

/// One framework slice of an assembled xcframework.
final class SliceSpec {
  const SliceSpec({
    required this.logicalName,
    required this.simulator,
    required this.abi,
    required this.archs,
    required this.minOs,
  });

  /// The manifest row, e.g. `ios/arm64/libTrustWalletCore.dylib`.
  final String logicalName;

  /// Whether this is the `ios-simulator` slice.
  final bool simulator;

  /// The manifest `abi`, e.g. `arm64_x86_64`.
  final String abi;

  /// [archsOfAbi] of [abi], in manifest order.
  final List<String> archs;

  /// The manifest `min_os`, e.g. `13.0`.
  final String minOs;

  /// Xcode's own slice directory name: `ios-arm64`,
  /// `ios-arm64_x86_64-simulator`.
  String get libraryIdentifier =>
      'ios-${archs.join('_')}${simulator ? '-simulator' : ''}';

  /// `CFBundleSupportedPlatforms` of the framework's Info.plist.
  String get supportedPlatform => simulator ? 'iPhoneSimulator' : 'iPhoneOS';

  @override
  String toString() => '$logicalName -> $libraryIdentifier (min $minOs)';
}

/// What the pod does with the manifest.
sealed class XcframeworkPlan {
  const XcframeworkPlan();

  /// The manifest rows the fetch tool must verify.
  List<String> get logicalNames;
}

/// Verify the CI-produced zip and vendor its content unchanged.
final class ZipPlan extends XcframeworkPlan {
  const ZipPlan();

  @override
  List<String> get logicalNames => const [xcframeworkZipLogicalName];
}

/// Verify the dylib rows and assemble the xcframework from them.
final class AssemblePlan extends XcframeworkPlan {
  const AssemblePlan({
    required this.slices,
    required this.upstreamTag,
    required this.artifactSetId,
    required this.upstreamCommit,
  });

  /// Device slice first, then simulator.
  final List<SliceSpec> slices;

  /// `upstream.tag`: `CFBundleShortVersionString`.
  final String upstreamTag;

  /// `identity.artifact_set_id`: recorded in the framework's Info.plist.
  final String artifactSetId;

  /// `identity.upstream_commit`: recorded in the framework's Info.plist.
  final String upstreamCommit;

  /// The device slice.
  SliceSpec get device => slices.firstWhere((s) => !s.simulator);

  @override
  List<String> get logicalNames => [for (final s in slices) s.logicalName];
}

/// The manifest cannot be turned into an xcframework.
final class XcframeworkPlanException implements Exception {
  XcframeworkPlanException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The plan [manifest] implies.
///
/// For an [AssemblePlan], exactly one device row and exactly one simulator row
/// are required, each with an `abi` and a `min_os`, and the device slice's
/// `min_os` must not be newer than [podDeploymentTarget] — a pod that declares
/// iOS 13 while vendoring a binary that needs 14 builds an app that crashes at
/// launch on the older OS.
XcframeworkPlan xcframeworkPlan(
  Map<String, Object?> manifest, {
  required String podDeploymentTarget,
}) {
  final artifacts = manifest['artifacts'];
  if (artifacts is! Map<String, Object?>) {
    throw XcframeworkPlanException('the manifest has no "artifacts" object');
  }
  if (artifacts.containsKey(xcframeworkZipLogicalName)) {
    return const ZipPlan();
  }

  final device = <SliceSpec>[];
  final simulator = <SliceSpec>[];
  for (final entry in artifacts.entries) {
    final match = _dylibRow.firstMatch(entry.key);
    if (match == null) continue;
    final record = entry.value;
    if (record is! Map<String, Object?>) {
      throw XcframeworkPlanException('artifacts["${entry.key}"] is not a map');
    }
    final abi = record['abi'];
    final minOs = record['min_os'];
    if (abi is! String || minOs is! String) {
      throw XcframeworkPlanException(
        'artifacts["${entry.key}"] needs "abi" and "min_os" (DECISION-14 '
        '§5.1) to become a framework slice',
      );
    }
    if (abi != match.group(2)) {
      throw XcframeworkPlanException(
        'artifacts["${entry.key}"].abi is "$abi" but the key says '
        '"${match.group(2)}"',
      );
    }
    final List<String> archs;
    try {
      archs = archsOfAbi(abi);
    } on FormatException catch (e) {
      throw XcframeworkPlanException(
        'artifacts["${entry.key}"].abi "$abi": ${e.message}',
      );
    }
    final isSimulator = match.group(1) == 'ios-simulator';
    (isSimulator ? simulator : device).add(
      SliceSpec(
        logicalName: entry.key,
        simulator: isSimulator,
        abi: abi,
        archs: archs,
        minOs: minOs,
      ),
    );
  }

  if (device.length != 1 || simulator.length != 1) {
    throw XcframeworkPlanException(
      'expected $xcframeworkZipLogicalName, or exactly one '
      'ios/<abi>/libTrustWalletCore.dylib and one '
      'ios-simulator/<abi>/libTrustWalletCore.dylib row; found '
      '${device.length} device and ${simulator.length} simulator rows',
    );
  }
  if (compareVersions(device.single.minOs, podDeploymentTarget) > 0) {
    throw XcframeworkPlanException(
      '${device.single.logicalName} needs iOS ${device.single.minOs} but the '
      'pod declares $podDeploymentTarget; raise s.platform in the podspec',
    );
  }

  String field(String block, String key) {
    final map = manifest[block];
    final value = map is Map<String, Object?> ? map[key] : null;
    if (value is! String || value.isEmpty) {
      throw XcframeworkPlanException('the manifest has no $block.$key');
    }
    return value;
  }

  return AssemblePlan(
    slices: [device.single, simulator.single],
    upstreamTag: field('upstream', 'tag'),
    artifactSetId: field('identity', 'artifact_set_id'),
    upstreamCommit: field('identity', 'upstream_commit'),
  );
}

/// Compares two dotted numeric versions: negative, zero, or positive.
int compareVersions(String a, String b) {
  List<int> parts(String v) =>
      v.split('.').map((p) => int.tryParse(p) ?? -1).toList();
  final pa = parts(a);
  final pb = parts(b);
  for (var i = 0; i < pa.length || i < pb.length; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

String _escape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

const String _plistHeader =
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
    '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
    '<plist version="1.0">\n';

/// The `Info.plist` of one framework bundle.
///
/// `CFBundleShortVersionString` and `CFBundleVersion` are the upstream tag,
/// because App Store validation requires numeric versions; the artifact set
/// and commit the binary belongs to are recorded under `WCFArtifactSetId` and
/// `WCFUpstreamCommit`, which nothing reads at run time — the run-time
/// identity is `wcf_build_info()` (DECISION-14 §2).
String frameworkInfoPlist(SliceSpec slice, AssemblePlan plan) {
  final buffer = StringBuffer(_plistHeader)..writeln('<dict>');
  void string(String key, String value) {
    buffer
      ..writeln('\t<key>$key</key>')
      ..writeln('\t<string>${_escape(value)}</string>');
  }

  string('CFBundleDevelopmentRegion', 'en');
  string('CFBundleExecutable', frameworkName);
  string('CFBundleIdentifier', frameworkBundleIdentifier);
  string('CFBundleInfoDictionaryVersion', '6.0');
  string('CFBundleName', frameworkName);
  string('CFBundlePackageType', 'FMWK');
  string('CFBundleShortVersionString', plan.upstreamTag);
  buffer
    ..writeln('\t<key>CFBundleSupportedPlatforms</key>')
    ..writeln('\t<array>')
    ..writeln('\t\t<string>${slice.supportedPlatform}</string>')
    ..writeln('\t</array>');
  string('CFBundleVersion', plan.upstreamTag);
  string('MinimumOSVersion', slice.minOs);
  string('WCFArtifactSetId', plan.artifactSetId);
  string('WCFUpstreamCommit', plan.upstreamCommit);
  buffer
    ..writeln('</dict>')
    ..writeln('</plist>');
  return buffer.toString();
}

/// The `Info.plist` at the root of the xcframework: the slice table Xcode and
/// CocoaPods read to pick the slice for an SDK. Written directly rather than
/// by `xcodebuild -create-xcframework`, so `pod install` does not depend on a
/// working `xcodebuild` and the output is byte-stable for a given manifest.
String xcframeworkInfoPlist(AssemblePlan plan) {
  final buffer = StringBuffer(_plistHeader)
    ..writeln('<dict>')
    ..writeln('\t<key>AvailableLibraries</key>')
    ..writeln('\t<array>');
  for (final slice in plan.slices) {
    buffer
      ..writeln('\t\t<dict>')
      ..writeln('\t\t\t<key>BinaryPath</key>')
      ..writeln(
        '\t\t\t<string>$frameworkName.framework/$frameworkName</string>',
      )
      ..writeln('\t\t\t<key>LibraryIdentifier</key>')
      ..writeln('\t\t\t<string>${slice.libraryIdentifier}</string>')
      ..writeln('\t\t\t<key>LibraryPath</key>')
      ..writeln('\t\t\t<string>$frameworkName.framework</string>')
      ..writeln('\t\t\t<key>SupportedArchitectures</key>')
      ..writeln('\t\t\t<array>');
    for (final arch in slice.archs) {
      buffer.writeln('\t\t\t\t<string>$arch</string>');
    }
    buffer
      ..writeln('\t\t\t</array>')
      ..writeln('\t\t\t<key>SupportedPlatform</key>')
      ..writeln('\t\t\t<string>ios</string>');
    if (slice.simulator) {
      buffer
        ..writeln('\t\t\t<key>SupportedPlatformVariant</key>')
        ..writeln('\t\t\t<string>simulator</string>');
    }
    buffer.writeln('\t\t</dict>');
  }
  buffer
    ..writeln('\t</array>')
    ..writeln('\t<key>CFBundlePackageType</key>')
    ..writeln('\t<string>XFWK</string>')
    ..writeln('\t<key>XCFrameworkFormatVersion</key>')
    ..writeln('\t<string>1.0</string>')
    ..writeln('</dict>')
    ..writeln('</plist>');
  return buffer.toString();
}
