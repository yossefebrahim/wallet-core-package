/// Test seams: a [ResourceObserver] that records, and a [WalletCoreBindings]
/// that counts the two delete calls.
///
/// Both are test-only. The counting bindings exist because "the wrapper called
/// upstream's delete exactly once" is otherwise unobservable from Dart: the
/// generated bindings class is a plain class whose methods can be overridden,
/// so a subclass can count the calls and still make every one of them.
library;

// The two overrides below must carry upstream's own names, which the generated
// bindings keep verbatim.
// ignore_for_file: non_constant_identifier_names

import 'dart:ffi';

import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart';

/// Records which resources were created and which were disposed.
///
/// This is the hook T1.6b's `LeakTracker` implements. It stores the resources
/// themselves so a test can assert on identity; it never reads their contents.
final class RecordingObserver implements ResourceObserver {
  /// Every resource this observer was told about, in creation order.
  final List<NativeResource> created = <NativeResource>[];

  /// Every resource this observer was told was disposed, in disposal order.
  final List<NativeResource> disposed = <NativeResource>[];

  @override
  void onResourceCreated(NativeResource resource) => created.add(resource);

  @override
  void onResourceDisposed(NativeResource resource) => disposed.add(resource);
}

/// Bindings that count `TWDataDelete` and `TWStringDelete` and then make the
/// real call.
final class CountingBindings extends WalletCoreBindings {
  /// Looks symbols up in [library], like the generated class does.
  CountingBindings(super.library);

  /// How many times `TWDataDelete` has been called through these bindings.
  int dataDeletes = 0;

  /// How many times `TWStringDelete` has been called through these bindings.
  int stringDeletes = 0;

  @override
  void TWDataDelete(Pointer<TWData> data) {
    dataDeletes++;
    super.TWDataDelete(data);
  }

  @override
  void TWStringDelete(Pointer<TWString> string) {
    stringDeletes++;
    super.TWStringDelete(string);
  }
}
