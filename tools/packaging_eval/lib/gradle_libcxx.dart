// Reading an Android build log for the libc++_shared.so outcome
// (PRD §12.2 step 9).
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.
//
// The question the step asks is not "does the build succeed" but "how did the
// packaging option resolve two plugins that each bundle libc++_shared.so".
// Gradle has three observable answers and one non-answer, and they are told
// apart by what the log says, so this classifier is the whole check once the
// build has run.

/// How the Android build resolved a duplicated `libc++_shared.so`.
enum LibcxxOutcome {
  /// Gradle refused: "More than one file was found with OS independent path
  /// `lib/<abi>/libc++_shared.so`". The packaging option must state a rule.
  duplicateFailure,

  /// A `pickFirst` (or `packagingOptions`/`jniLibs.pickFirsts`) rule silently
  /// chose one copy. Which one, and whether the versions agree, is then the
  /// evaluation's problem to state.
  pickFirstResolved,

  /// Only one copy reached the merge — the packaging option deduplicated
  /// upstream of Gradle, or only one contributor bundles the library.
  singleCopy,

  /// Two copies with different contents or an NDK/STL version mismatch that
  /// the build called out.
  versionConflict,

  /// The log says nothing about the file. Not a pass.
  unknown,
}

class LibcxxConflictReport {
  const LibcxxConflictReport({
    required this.outcome,
    required this.evidence,
    required this.buildSucceeded,
  });

  final LibcxxOutcome outcome;

  /// The log lines the classification rests on, in order, deduplicated.
  final List<String> evidence;

  final bool buildSucceeded;

  Map<String, Object?> toJson() => {
    'outcome': outcome.name,
    'build_succeeded': buildSucceeded,
    'evidence': evidence,
  };
}

final RegExp _duplicatePath = RegExp(
  r"More than one file was found with OS independent path '([^']*libc\+\+_shared\.so)'",
);
final RegExp _pickFirst = RegExp(
  r'pickFirsts?\b.*libc\+\+_shared|libc\+\+_shared.*\bpickFirst',
  caseSensitive: false,
);
final RegExp _versionConflict = RegExp(
  r'libc\+\+_shared.*(version conflict|different version|mismatch)|'
  r'(version conflict|different version|mismatch).*libc\+\+_shared',
  caseSensitive: false,
);
final RegExp _mergeMentions = RegExp(r'libc\+\+_shared\.so');

/// Classifies a Gradle / `flutter build apk` log.
LibcxxConflictReport classifyGradleOutput(String log) {
  final evidence = <String>[];
  var duplicate = false;
  var pickFirst = false;
  var versionConflict = false;
  var mentions = 0;

  void record(String line) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty && !evidence.contains(trimmed)) {
      evidence.add(trimmed);
    }
  }

  for (final line in log.split('\n')) {
    if (_duplicatePath.hasMatch(line)) {
      duplicate = true;
      record(line);
    }
    if (_versionConflict.hasMatch(line)) {
      versionConflict = true;
      record(line);
    }
    if (_pickFirst.hasMatch(line)) {
      pickFirst = true;
      record(line);
    }
    if (_mergeMentions.hasMatch(line)) mentions++;
  }

  final succeeded =
      log.contains('BUILD SUCCESSFUL') ||
      RegExp(r'^✓ Built ', multiLine: true).hasMatch(log);

  final LibcxxOutcome outcome;
  if (versionConflict) {
    outcome = LibcxxOutcome.versionConflict;
  } else if (duplicate && !succeeded) {
    outcome = LibcxxOutcome.duplicateFailure;
  } else if (pickFirst) {
    outcome = LibcxxOutcome.pickFirstResolved;
  } else if (duplicate) {
    // Gradle named the duplicate and the build still finished: something
    // resolved it. Report it as such rather than as a clean single copy.
    outcome = LibcxxOutcome.pickFirstResolved;
  } else if (mentions > 0 && succeeded) {
    outcome = LibcxxOutcome.singleCopy;
  } else {
    outcome = LibcxxOutcome.unknown;
  }

  return LibcxxConflictReport(
    outcome: outcome,
    evidence: evidence,
    buildSucceeded: succeeded,
  );
}
