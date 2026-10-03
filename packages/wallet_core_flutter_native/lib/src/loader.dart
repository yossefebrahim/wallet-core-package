/// Loading the native library and checking that it is healthy.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
library;

import 'dart:ffi';

import 'errors.dart';
import 'library_location.dart';

/// The documented way to open the native library, and the symbol-lookup health
/// check that follows it.
///
/// Everything here is synchronous, uses only `dart:ffi` and `dart:io`, and
/// imports no Flutter: the identity check runs in the worker isolate during
/// `Init` (DECISION-12 §5) and the same code has to work from a pure-Dart CLI.
///
/// **The library file is never hashed at runtime.** Hashing it would be
/// meaningless for a statically linked image — there is no separate file to
/// hash — and false assurance for a dynamic one, since an attacker who can
/// replace the file can replace whatever computes the digest beside it
/// (PRD §12.3, threat model TM-13). Checksums are verified once, at build
/// time, against `compat_manifest.json`; at run time the integrity signal is
/// the build-identity symbol and nothing else.
///
/// **No path from the environment.** This class never reads an environment
/// variable and never accepts a caller-supplied path on Android or iOS: on a
/// device platform the library is resolved by the packaging mechanism's own
/// identity (TM-13). [hostLibraryPath] exists for macOS and Linux development
/// hosts, where the library is a build output with no packaging mechanism to
/// find it. A test that wants to point the loader at a file reads its own
/// environment variable and passes the path in.
final class WalletCoreNative {
  const WalletCoreNative._();

  /// Opens the native library, trying each of [locations] in order.
  ///
  /// Returns the first library that opens. When every location fails, throws
  /// [NativeLoadError] carrying one [LibraryLoadAttempt] per location, in the
  /// order tried, each with its own error — so a report names every place that
  /// was looked at rather than only the last.
  ///
  /// [locations] defaults to [defaultLocations] for [platform], which itself
  /// defaults to the running platform. A packaging option that needs another
  /// place to look supplies it here; see [LibraryLocation].
  ///
  /// [hostLibraryPath] is honoured on macOS, Linux, and unknown hosts only,
  /// and is rejected with an [ArgumentError] on Android and iOS. It is ignored
  /// when [locations] is given explicitly, because then the caller has already
  /// said where to look.
  static DynamicLibrary load({
    Iterable<LibraryLocation>? locations,
    NativePlatform? platform,
    String? hostLibraryPath,
  }) {
    final effectivePlatform = platform ?? NativePlatform.current;
    final tried =
        locations?.toList() ??
        defaultLocations(
          platform: effectivePlatform,
          hostLibraryPath: hostLibraryPath,
        );

    if (tried.isEmpty) {
      throw NativeLoadError(
        'no location to try for ${effectivePlatform.name}: this platform has '
        'no packaged native library, so a path must be supplied',
      );
    }

    final attempts = <LibraryLoadAttempt>[];
    for (final location in tried) {
      try {
        return location.open();
      } on Object catch (e) {
        attempts.add(
          LibraryLoadAttempt(location: location.description, error: e),
        );
      }
    }
    throw NativeLoadError(
      'could not load the native library on ${effectivePlatform.name} after '
      '${attempts.length} '
      '${attempts.length == 1 ? "attempt" : "attempts"}',
      cause: attempts.last.error,
      attempts: attempts,
    );
  }

  /// The names in [symbols] that [library] does not resolve, in the order
  /// given. An empty list means the library is healthy.
  ///
  /// This is the health check `initialize()` runs after the identity check: it
  /// answers "is this library complete", which a version string cannot. The
  /// names come from the caller — the bindings package owns the canonical list
  /// (its generated `inventory.json`), and this package cannot depend on it
  /// because the dependency runs the other way.
  static List<String> symbolLookupAll(
    DynamicLibrary library,
    Iterable<String> symbols,
  ) => symbols.where((name) => !library.providesSymbol(name)).toList();

  /// [symbolLookupAll], but throws [NativeLoadError] naming the missing
  /// symbols instead of returning them.
  ///
  /// The message lists at most [maxNamed] names and then a count, because a
  /// library that resolves nothing would otherwise produce a message hundreds
  /// of names long and no more informative for it.
  static void requireSymbols(
    DynamicLibrary library,
    Iterable<String> symbols, {
    int maxNamed = 10,
  }) {
    final missing = symbolLookupAll(library, symbols);
    if (missing.isEmpty) return;
    final named = missing.take(maxNamed).join(', ');
    final rest = missing.length - maxNamed;
    throw NativeLoadError(
      'the loaded library does not resolve ${missing.length} of the '
      '${symbols.length} symbols it must export: $named'
      '${rest > 0 ? ' and $rest more' : ''}',
    );
  }
}
