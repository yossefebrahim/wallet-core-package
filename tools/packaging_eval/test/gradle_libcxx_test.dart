// Classifying an Android build log for the libc++_shared.so outcome
// (PRD §12.2 step 9).
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.

import 'package:test/test.dart';
import 'package:wcf_tool_packaging_eval/gradle_libcxx.dart';

import 'fixtures.dart';

/// A build that never mentions the library at all.
const _cleanLog = '''
> Task :app:mergeDebugNativeLibs
> Task :app:package

BUILD SUCCESSFUL in 33s
✓ Built build/app/outputs/flutter-apk/app-debug.apk
''';

void main() {
  group('classifyGradleOutput on the committed fixtures', () {
    test('the duplicate-file failure is a duplicateFailure', () {
      final report = classifyGradleOutput(
        toolOutput('gradle_libcxx_duplicate_synthetic.txt'),
      );
      expect(report.outcome, LibcxxOutcome.duplicateFailure);
      expect(report.buildSucceeded, isFalse);
      expect(
        report.evidence.single,
        contains(
          "More than one file was found with OS independent path "
          "'lib/arm64-v8a/libc++_shared.so'",
        ),
      );
      expect(report.toJson()['outcome'], 'duplicateFailure');
      expect(report.toJson()['build_succeeded'], false);
    });

    test('a pickFirst rule that let the build finish is pickFirstResolved', () {
      final report = classifyGradleOutput(
        toolOutput('gradle_libcxx_pickfirst_synthetic.txt'),
      );
      expect(report.outcome, LibcxxOutcome.pickFirstResolved);
      expect(report.buildSucceeded, isTrue);
      expect(
        report.evidence,
        contains(
          "packagingOptions.jniLibs.pickFirsts += 'lib/**/libc++_shared.so'",
        ),
      );
    });
  });

  group('classifyGradleOutput', () {
    test('a build that never mentions the library classifies as unknown', () {
      final report = classifyGradleOutput(_cleanLog);
      expect(report.outcome, LibcxxOutcome.unknown);
      expect(report.buildSucceeded, isTrue);
      expect(report.evidence, isEmpty);
    });

    test('an empty log is unknown and not a success', () {
      final report = classifyGradleOutput('');
      expect(report.outcome, LibcxxOutcome.unknown);
      expect(report.buildSucceeded, isFalse);
    });

    test('one merged copy in a successful build is singleCopy', () {
      final report = classifyGradleOutput('''
> Task :app:mergeReleaseNativeLibs
  merging lib/arm64-v8a/libc++_shared.so from wallet_core_flutter_native

BUILD SUCCESSFUL in 40s
''');
      expect(report.outcome, LibcxxOutcome.singleCopy);
      expect(report.buildSucceeded, isTrue);
    });

    test('a stated version mismatch outranks everything else', () {
      final report = classifyGradleOutput('''
> Task :app:mergeDebugNativeLibs
   > 2 files found with path 'lib/arm64-v8a/libc++_shared.so' from inputs:
     More than one file was found with OS independent path 'lib/arm64-v8a/libc++_shared.so'.
     warning: libc++_shared.so version conflict: r21 vs r28

BUILD FAILED in 9s
''');
      expect(report.outcome, LibcxxOutcome.versionConflict);
      expect(report.evidence, hasLength(2));
    });

    test('a named duplicate in a build that finished is not a clean copy', () {
      final report = classifyGradleOutput('''
> Task :app:mergeDebugNativeLibs
     More than one file was found with OS independent path 'lib/x86_64/libc++_shared.so'.

BUILD SUCCESSFUL in 11s
''');
      expect(report.outcome, LibcxxOutcome.pickFirstResolved);
      expect(report.buildSucceeded, isTrue);
    });

    test('evidence is deduplicated and keeps the log order', () {
      final line =
          "     More than one file was found with OS independent path "
          "'lib/arm64-v8a/libc++_shared.so'.";
      final report = classifyGradleOutput('$line\n$line\nBUILD FAILED\n');
      expect(report.evidence, hasLength(1));
      expect(report.evidence.single, line.trim());
    });

    test('the five outcomes are the vocabulary and do not drift', () {
      expect(LibcxxOutcome.values.map((o) => o.name), [
        'duplicateFailure',
        'pickFirstResolved',
        'singleCopy',
        'versionConflict',
        'unknown',
      ]);
    });
  });
}
