/// The manifest → xcframework plan the podspec consumes, and the property
/// lists an assembled xcframework carries.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/option2/src/xcframework_plan.dart';

Map<String, Object?> _dylibManifest({
  String deviceMinOs = '13.0',
  String simulatorAbi = 'arm64_x86_64',
  bool withZip = false,
}) => {
  'upstream': {'tag': '4.8.0'},
  'identity': {
    'artifact_set_id': 'as_4.8.0_000',
    'upstream_commit': 'd692ac27749d0c615e17c751b70ab4f0aa75c59b',
  },
  'artifacts': {
    'android/arm64-v8a/libTrustWalletCore.so': {
      'sha256': 'TBD-T1.2',
      'size': 0,
    },
    'ios/arm64/libTrustWalletCore.dylib': {
      'abi': 'arm64',
      'min_os': deviceMinOs,
    },
    'ios-simulator/$simulatorAbi/libTrustWalletCore.dylib': {
      'abi': simulatorAbi,
      'min_os': '14.0',
    },
    'macos/arm64_x86_64/libTrustWalletCore.dylib': {
      'abi': 'arm64_x86_64',
      'min_os': '26.0',
    },
    if (withZip)
      'ios/TrustWalletCore.xcframework.zip': {'sha256': 'TBD-T1.2', 'size': 0},
  },
};

void main() {
  group('archsOfAbi', () {
    test('splits on "_" without splitting x86_64', () {
      expect(archsOfAbi('arm64'), ['arm64']);
      expect(archsOfAbi('arm64_x86_64'), ['arm64', 'x86_64']);
      expect(archsOfAbi('x86_64_arm64'), ['x86_64', 'arm64']);
      expect(archsOfAbi('x86_64'), ['x86_64']);
      expect(archsOfAbi('arm64e_arm64'), ['arm64e', 'arm64']);
    });

    test('refuses anything else', () {
      for (final bad in ['', 'x86', 'arm64_', 'arm64__x86_64', 'arm64-v8a']) {
        expect(() => archsOfAbi(bad), throwsFormatException, reason: bad);
      }
    });
  });

  group('xcframeworkPlan', () {
    test('the dylib rows of a local set become two slices', () {
      final plan = xcframeworkPlan(
        _dylibManifest(),
        podDeploymentTarget: '13.0',
      );
      expect(plan, isA<AssemblePlan>());
      final assemble = plan as AssemblePlan;
      expect(assemble.slices.map((s) => s.libraryIdentifier), [
        'ios-arm64',
        'ios-arm64_x86_64-simulator',
      ]);
      expect(assemble.logicalNames, [
        'ios/arm64/libTrustWalletCore.dylib',
        'ios-simulator/arm64_x86_64/libTrustWalletCore.dylib',
      ]);
      expect(assemble.device.minOs, '13.0');
      expect(assemble.artifactSetId, 'as_4.8.0_000');
    });

    test('a zip row wins, placeholder or not', () {
      final plan = xcframeworkPlan(
        _dylibManifest(withZip: true),
        podDeploymentTarget: '13.0',
      );
      expect(plan, isA<ZipPlan>());
      expect(plan.logicalNames, [xcframeworkZipLogicalName]);
    });

    test('the root manifest shape is a zip plan', () {
      final plan = xcframeworkPlan({
        'artifacts': {
          'ios/TrustWalletCore.xcframework.zip': {
            'sha256': 'TBD-T1.2',
            'size': 0,
          },
        },
      }, podDeploymentTarget: '13.0');
      expect(plan, isA<ZipPlan>());
    });

    test('a device slice newer than the pod deployment target is refused', () {
      expect(
        () => xcframeworkPlan(
          _dylibManifest(deviceMinOs: '15.0'),
          podDeploymentTarget: '13.0',
        ),
        throwsA(
          isA<XcframeworkPlanException>().having(
            (e) => e.message,
            'message',
            contains('needs iOS 15.0'),
          ),
        ),
      );
    });

    test('a missing simulator row is refused', () {
      final manifest = _dylibManifest();
      (manifest['artifacts']! as Map).remove(
        'ios-simulator/arm64_x86_64/libTrustWalletCore.dylib',
      );
      expect(
        () => xcframeworkPlan(manifest, podDeploymentTarget: '13.0'),
        throwsA(isA<XcframeworkPlanException>()),
      );
    });

    test('a record without abi/min_os is refused', () {
      expect(
        () => xcframeworkPlan({
          'artifacts': {
            'ios/arm64/libTrustWalletCore.dylib': {'sha256': 'TBD-T1.2'},
            'ios-simulator/arm64/libTrustWalletCore.dylib': {
              'sha256': 'TBD-T1.2',
            },
          },
        }, podDeploymentTarget: '13.0'),
        throwsA(isA<XcframeworkPlanException>()),
      );
    });

    test('an abi that contradicts its key is refused', () {
      final manifest = _dylibManifest();
      ((manifest['artifacts']! as Map)['ios/arm64/libTrustWalletCore.dylib']
              as Map)['abi'] =
          'x86_64';
      expect(
        () => xcframeworkPlan(manifest, podDeploymentTarget: '13.0'),
        throwsA(isA<XcframeworkPlanException>()),
      );
    });
  });

  test('compareVersions', () {
    expect(compareVersions('13.0', '13.0'), 0);
    expect(compareVersions('13', '13.0'), 0);
    expect(compareVersions('14.0', '13.0'), greaterThan(0));
    expect(compareVersions('12.4', '13.0'), lessThan(0));
    expect(compareVersions('13.10', '13.9'), greaterThan(0));
  });

  group('property lists', () {
    final plan =
        xcframeworkPlan(_dylibManifest(), podDeploymentTarget: '13.0')
            as AssemblePlan;

    test('the framework plist names the binary, platform and identity', () {
      final device = frameworkInfoPlist(plan.device, plan);
      expect(device, contains('<string>$frameworkName</string>'));
      expect(device, contains('<string>FMWK</string>'));
      expect(device, contains('<string>iPhoneOS</string>'));
      expect(device, contains('<string>13.0</string>'));
      expect(device, contains('<string>as_4.8.0_000</string>'));
      final simulator = frameworkInfoPlist(plan.slices.last, plan);
      expect(simulator, contains('<string>iPhoneSimulator</string>'));
      expect(simulator, contains('<string>14.0</string>'));
    });

    test('the xcframework plist lists both slices with their archs', () {
      final xml = xcframeworkInfoPlist(plan);
      expect(xml, contains('<string>ios-arm64</string>'));
      expect(xml, contains('<string>ios-arm64_x86_64-simulator</string>'));
      expect(xml, contains('<string>x86_64</string>'));
      expect('SupportedPlatformVariant'.allMatches(xml), hasLength(1));
      expect(xml, contains('<string>XFWK</string>'));
      expect(xcframeworkInfoPlist(plan), xml, reason: 'byte-stable');
    });

    test('both are well-formed property lists (plutil -lint)', () {
      final dir = Directory.systemTemp.createTempSync('wcf-plist-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final files = {
        'framework.plist': frameworkInfoPlist(plan.device, plan),
        'simulator.plist': frameworkInfoPlist(plan.slices.last, plan),
        'xcframework.plist': xcframeworkInfoPlist(plan),
      };
      for (final entry in files.entries) {
        final path = '${dir.path}/${entry.key}';
        File(path).writeAsStringSync(entry.value);
        final result = Process.runSync('plutil', ['-lint', path]);
        expect(result.exitCode, 0, reason: '${result.stdout}');
      }
    }, skip: Platform.isMacOS ? false : 'plutil is macOS-only');
  });
}
