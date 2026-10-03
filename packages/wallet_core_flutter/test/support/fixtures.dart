/// Shared test fixtures: the vector inventory, a context that cannot reach
/// native code, and the redaction assertion.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/advanced.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';
import 'package:wcf_tool_vectors/inventory.dart';

import 'host_library.dart';

/// The repository's test-vector inventory, read through the T0.8 loader.
Inventory loadInventory() {
  final root = repositoryRoot();
  if (root == null) throw StateError('repository root not found');
  final inventory = Inventory.load(
    Directory('${root.path}${Platform.pathSeparator}test_vectors'),
  );
  if (inventory.loadProblems.isNotEmpty) {
    throw StateError('vector inventory: ${inventory.loadProblems}');
  }
  return inventory;
}

/// The vector with [id]; fails the test when it is missing.
Vector vectorById(Inventory inventory, String id) => inventory.vectors
    .singleWhere((vector) => vector.id == id, orElse: () => fail('no $id'));

/// A context whose bindings resolve symbols in the test process itself, which
/// exports none of upstream's.
///
/// Symbol lookup is lazy, so constructing it touches nothing; any native call
/// made through it throws `ArgumentError` from the failed lookup. A test that
/// expects a typed Dart-side rejection through this context therefore also
/// proves the rejection happened **before** any native call (PRD §16 S5).
NativeContext unreachableNativeContext() =>
    NativeContext(WalletCoreBindings(DynamicLibrary.process()));

/// Asserts that neither [error]'s `toString()` nor, for an SDK error, its
/// message contains any of [secrets] — the whole secret, and each of its
/// whitespace-separated parts of four characters or more (threat model
/// TM-09, TM-31).
void expectRedacted(Object error, Iterable<String> secrets) {
  final rendered = <String>[
    error.toString(),
    if (error is WalletCoreException) error.message,
  ];
  for (final secret in secrets) {
    final fragments = <String>{
      secret,
      ...secret.split(RegExp(r'\s+')).where((part) => part.length >= 4),
    }..removeWhere((fragment) => fragment.isEmpty);
    for (final text in rendered) {
      for (final fragment in fragments) {
        // Deliberately not `contains(...)` as a matcher: a failing matcher
        // would print the secret into the test log.
        if (text.contains(fragment)) {
          fail(
            '${error.runtimeType} rendered a secret fragment of length '
            '${fragment.length}',
          );
        }
      }
    }
  }
}
