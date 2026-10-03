/// Which manifest artifacts the Android Gradle build packages, and where.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// DECISION-2 Option 2 (evaluation branch, T1.9). Pure: a manifest's decoded
/// JSON in, a list of entries out, no file system and no process. The I/O that
/// acts on the plan is `../prepare_jni_libs.dart`.
///
/// **The manifest decides the ABI set.** Every artifact key of the form
/// `android/<abi>/<file>.so` becomes `<abi>/<file>.so` in the generated jniLibs
/// directory, so `armeabi-v7a` ships exactly when the manifest lists it
/// (PRD §12.2 step 8: it ships only if tested) and a `libc++_shared.so` row
/// ships next to `libTrustWalletCore.so` exactly when T1.2's build lists one.
/// Nothing here hard-codes an ABI list the manifest could disagree with.
library;

/// The library every ABI must carry. The same constant as the loader's
/// `androidLibraryName`; `test/packaging/` asserts the two agree.
const String jniLibraryName = 'libTrustWalletCore.so';

/// The C++ runtime a `c++_shared` build depends on (PRD §12.1, Android row).
const String libcxxSharedName = 'libc++_shared.so';

/// The Android ABIs AGP packages from a jniLibs directory. A manifest row for
/// any other directory name would be packaged by AGP into an APK no device
/// loads it from, so it is refused rather than shipped.
const Set<String> knownAndroidAbis = {
  'arm64-v8a',
  'armeabi-v7a',
  'x86',
  'x86_64',
};

final RegExp _androidRow = RegExp(r'^android/([^/]+)/([^/]+\.so)$');

/// One file the Gradle build packages.
final class JniLibEntry {
  const JniLibEntry({
    required this.logicalName,
    required this.abi,
    required this.fileName,
  });

  /// The manifest key, e.g. `android/arm64-v8a/libTrustWalletCore.so`.
  final String logicalName;

  /// The ABI directory, e.g. `arm64-v8a`.
  final String abi;

  /// The file name inside it, e.g. `libTrustWalletCore.so`.
  final String fileName;

  /// The path relative to the generated jniLibs root.
  String get jniLibsPath => '$abi/$fileName';

  @override
  bool operator ==(Object other) =>
      other is JniLibEntry &&
      other.logicalName == logicalName &&
      other.abi == abi &&
      other.fileName == fileName;

  @override
  int get hashCode => Object.hash(logicalName, abi, fileName);

  @override
  String toString() => '$logicalName -> $jniLibsPath';
}

/// The manifest cannot be turned into a jniLibs layout.
final class JniLibsPlanException implements Exception {
  JniLibsPlanException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The jniLibs entries [manifest] implies, sorted by ABI then file name.
///
/// Throws [JniLibsPlanException] when the manifest has no `artifacts` object,
/// lists no Android row at all, names an ABI AGP would not package, or lists
/// an ABI without [jniLibraryName] — a `libc++_shared.so` on its own would
/// build an APK that cannot load the SDK on that ABI.
///
/// The plan says nothing about whether a row is fetchable: a `TBD-` digest is
/// the fetch tool's to refuse, with its own message naming the task that fills
/// it.
List<JniLibEntry> jniLibsPlan(Map<String, Object?> manifest) {
  final artifacts = manifest['artifacts'];
  if (artifacts is! Map<String, Object?>) {
    throw JniLibsPlanException('the manifest has no "artifacts" object');
  }
  final entries = <JniLibEntry>[];
  for (final key in artifacts.keys) {
    final match = _androidRow.firstMatch(key);
    if (match == null) continue;
    final abi = match.group(1)!;
    if (!knownAndroidAbis.contains(abi)) {
      throw JniLibsPlanException(
        'artifacts["$key"]: "$abi" is not an Android ABI AGP packages '
        '(${knownAndroidAbis.join(", ")})',
      );
    }
    entries.add(
      JniLibEntry(logicalName: key, abi: abi, fileName: match.group(2)!),
    );
  }
  if (entries.isEmpty) {
    throw JniLibsPlanException(
      'the manifest lists no android/<abi>/<file>.so artifact, so there is '
      'nothing for the Android build to package',
    );
  }
  final abis = {for (final e in entries) e.abi};
  for (final abi in abis) {
    if (!entries.any((e) => e.abi == abi && e.fileName == jniLibraryName)) {
      throw JniLibsPlanException(
        'the manifest lists android/$abi/ files but not '
        'android/$abi/$jniLibraryName',
      );
    }
  }
  entries.sort((a, b) {
    final byAbi = a.abi.compareTo(b.abi);
    return byAbi != 0 ? byAbi : a.fileName.compareTo(b.fileName);
  });
  return entries;
}

/// The ABIs that would ship `libTrustWalletCore.so` without a
/// `libc++_shared.so` row beside it.
///
/// Not an error: a `c++_static` build needs none, and whether the artifact
/// depends on the shared runtime is a property of the binary (`DT_NEEDED`)
/// that only the artifact build knows. The prepare step prints these so a
/// `c++_shared` artifact set missing its runtime is visible at build time
/// rather than as an `UnsatisfiedLinkError` on a device.
List<String> abisWithoutLibcxx(List<JniLibEntry> plan) => [
  for (final abi in {for (final e in plan) e.abi})
    if (!plan.any((e) => e.abi == abi && e.fileName == libcxxSharedName)) abi,
];
