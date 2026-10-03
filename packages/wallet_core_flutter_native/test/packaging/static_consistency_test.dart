/// The Gradle file, the podspec, the two prepare scripts and the loader agree
/// on the library name, the manifest path, and the build-time inputs.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// A static check: it reads the files as text. Neither Gradle nor CocoaPods is
/// run here (the evaluation's `eval/option2/run_eval.sh` does that), so what
/// this pins is that the two build integrations cannot drift apart from each
/// other or from the Dart they call.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter_native/wallet_core_flutter_native.dart';

import '../../tool/option2/src/jni_libs_plan.dart';
import '../../tool/option2/prepare_xcframework.dart'
    show binariesStampName, manifestStampName;
import '../../tool/option2/src/xcframework_plan.dart';

String _read(String path) => File(path).readAsStringSync();

const String _gradlePath = 'android/build.gradle';
const String _podspecPath = 'ios/wallet_core_flutter_native.podspec';

/// The build-time inputs both integrations read, by environment name.
const Set<String> _buildInputs = {
  'WCF_MANIFEST',
  'WCF_VENDORED_DIR',
  'WCF_OFFLINE',
  'WCF_ARTIFACT_DIR',
};

void main() {
  final gradle = _read(_gradlePath);
  final podspec = _read(_podspecPath);

  test('the platform library names are the loader\'s', () {
    expect(jniLibraryName, androidLibraryName);
    expect('$frameworkName.framework/$frameworkName', iosFrameworkLibraryPath);
    expect(frameworkInstallName, '@rpath/$iosFrameworkLibraryPath');
  });

  test('both integrations default to the shipped manifest', () {
    expect(manifestAssetPath, 'assets/compat_manifest.json');
    expect(gradle, contains('"$manifestAssetPath"'));
    expect(podspec, contains("'assets', 'compat_manifest.json'"));
    // And the script phase re-checks the same default.
    expect(
      podspec,
      contains(
        r'${PODS_TARGET_SRCROOT}/../'
        '$manifestAssetPath',
      ),
    );
  });

  test('both integrations read the same build-time inputs', () {
    final pattern = RegExp(r'WCF_[A-Z_]+');
    Set<String> named(String text) =>
        pattern.allMatches(text).map((m) => m.group(0)!).toSet();
    expect(named(gradle), _buildInputs);
    expect(named(podspec), _buildInputs);
  });

  test('each integration calls its own prepare script, which exists', () {
    // Both resolve it from the package root: Gradle from its projectDir's
    // parent, the podspec from `..` of its own directory.
    expect(gradle, contains('def wcfPackageDir = projectDir.parentFile'));
    expect(
      gradle,
      contains('new File(wcfPackageDir, "tool/option2/prepare_jni_libs.dart")'),
    );
    expect(File('tool/option2/prepare_jni_libs.dart').existsSync(), isTrue);
    expect(podspec, contains("wcf_package_dir = File.expand_path('..'"));
    expect(
      podspec,
      contains(
        "File.join(wcf_package_dir, 'tool', 'option2', "
        "'prepare_xcframework.dart')",
      ),
    );
    expect(File('tool/option2/prepare_xcframework.dart').existsSync(), isTrue);
  });

  test('verified_acquisition.dart exists once, shared by both scripts', () {
    final copies = Directory('.')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('/verified_acquisition.dart'))
        .where((f) => !f.path.contains('/.dart_tool/'))
        .map((f) => f.path)
        .toList();
    expect(copies, ['./tool/option2/src/verified_acquisition.dart']);
    for (final script in [
      'tool/option2/prepare_jni_libs.dart',
      'tool/option2/prepare_xcframework.dart',
    ]) {
      expect(
        _read(script),
        contains("import 'src/verified_acquisition.dart';"),
      );
    }
  });

  test('the Gradle file packages through a generated jniLibs directory', () {
    expect(gradle, contains('addGeneratedSourceDirectory'));
    expect(gradle, contains('useLegacyPackaging = false'));
    expect(gradle, isNot(contains('src/main/jniLibs')));
    expect(gradle, isNot(contains('externalNativeBuild')));
  });

  test('a variant without jniLibs sources fails instead of shipping none', () {
    // `jniLibs?.` skipped the wiring silently, and the app built without the
    // library (review T1.9a-d3, finding 13).
    expect(gradle, isNot(contains('jniLibs?.')));
    expect(
      gradle,
      matches(
        RegExp(r'if \(jniLibs == null\) \{\s+throw new GradleException\('),
      ),
    );
    expect(gradle, contains('jniLibs.addGeneratedSourceDirectory(prepare)'));
  });

  test('the podspec vendors the xcframework the prepare step writes', () {
    expect(podspec, contains("'Frameworks/$xcframeworkDirName'"));
    expect(podspec, contains("File.join(wcf_pod_dir, 'Frameworks')"));
    expect(podspec, contains("'Resources/PrivacyInfo.xcprivacy'"));
    expect(podspec, contains(manifestStampName));
    expect(podspec, contains(binariesStampName));
    expect(podspec, contains('Pod::Informative'));
  });

  test('the podspec adds no load-all linker flags', () {
    expect(podspec, isNot(contains('-all_load')));
    expect(podspec, isNot(contains('-force_load')));
    expect(podspec, isNot(contains('OTHER_LDFLAGS')));
    expect(podspec, isNot(contains('user_target_xcconfig')));
  });

  test(
    'the pod deployment target admits the evaluation set\'s device slice',
    () {
      final declared = RegExp(
        r"wcf_deployment_target = '([0-9.]+)'",
      ).firstMatch(podspec)!.group(1)!;
      expect(podspec, contains('s.platform = :ios, wcf_deployment_target'));
      final manifest = File('../../eval/option2/eval_manifest.json');
      if (!manifest.existsSync()) {
        markTestSkipped('no eval/option2/eval_manifest.json on this branch');
        return;
      }
      // Xcode 27's iphoneos SDK and Flutter 3.47's Flutter.framework both
      // start at 15.0; the pod may not declare less.
      expect(compareVersions(declared, '15.0'), greaterThanOrEqualTo(0));
      final plan = xcframeworkPlan(
        jsonDecode(manifest.readAsStringSync()) as Map<String, Object?>,
        podDeploymentTarget: declared,
      );
      // The library's own measured minimum stays recorded, and is older.
      final device = (plan as AssemblePlan).device;
      expect(device.minOs, '13.0');
      expect(compareVersions(device.minOs, declared), lessThanOrEqualTo(0));
    },
  );

  test('pubspec declares the FFI plugin on both platforms', () {
    final pubspec = _read('pubspec.yaml');
    expect(
      pubspec,
      matches(
        RegExp(
          r'plugin:\s+platforms:\s+android:\s+ffiPlugin: true\s+'
          r'ios:\s+ffiPlugin: true',
        ),
      ),
    );
  });

  test('the privacy manifest declares the two measured categories', () {
    final privacy = _read('ios/Resources/PrivacyInfo.xcprivacy');
    expect(privacy, contains('NSPrivacyAccessedAPICategoryFileTimestamp'));
    expect(privacy, contains('NSPrivacyAccessedAPICategorySystemBootTime'));
    if (Platform.isMacOS) {
      final result = Process.runSync('plutil', [
        '-lint',
        'ios/Resources/PrivacyInfo.xcprivacy',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}');
    }
  });

  test('the podspec is valid Ruby (ruby -c)', () {
    final ProcessResult result;
    try {
      result = Process.runSync('ruby', ['-c', _podspecPath]);
    } on ProcessException {
      markTestSkipped('no ruby on PATH');
      return;
    }
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  });
}
