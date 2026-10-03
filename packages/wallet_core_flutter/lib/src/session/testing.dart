/// The internal test entry point. **Not exported**, and not part of any
/// public contract: reachable only by importing a `src/` path.
///
/// The public `WalletCore.initialize()` takes no library path and reads no
/// environment variable (threat model TM-13). Tests need both a path — the
/// host library a developer built — and an expected identity other than the
/// manifest's, whose artifact-set id is still a placeholder; and the
/// protocol tests need to swap the executor's handler for a fake. This file
/// is the only door to those seams.
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart'
    show LeakReport, LeakTracker;
import 'package:wallet_core_flutter_native/wallet_core_flutter_native.dart'
    show ManifestIdentity;

import '../worker/handler.dart';
import '../worker/transport.dart';
import 'session.dart';
import 'wallet_core.dart';

/// [WalletCore.initialize] with the seams the public call does not have.
///
/// [hostLibraryPath] is tried before the platform's default location;
/// [expectedIdentity] replaces the manifest's; [manifestBytes] turns on the
/// manifest-hash comparison; [handler] replaces the engine-backed handler
/// the in-process executor drives.
@visibleForTesting
Future<WalletCore> initializeForTesting({
  int queueLimit = 32,
  OperationTimeouts timeouts = const OperationTimeouts(),
  String? hostLibraryPath,
  ManifestIdentity expectedIdentity = ManifestIdentity.embedded,
  Uint8List? manifestBytes,
  RequestHandler? handler,
}) => startSession(
  queueLimit: queueLimit,
  timeouts: timeouts,
  hostLibraryPath: hostLibraryPath,
  expectedIdentity: expectedIdentity,
  manifestBytes: manifestBytes,
  transport: InProcessTransport.factory(handler ?? EngineRequestHandler()),
);

/// The in-process executor's handler behind [core].
@visibleForTesting
RequestHandler debugHandlerOf(WalletCore core) =>
    ((core as WalletCoreSession).transport as InProcessTransport).handler;

/// The leak tracker's report for [core]'s handles, or `null` when there is
/// no tracker (a release build, or a fake handler).
@visibleForTesting
LeakReport? debugLeakReportOf(WalletCore core) {
  final handler = debugHandlerOf(core);
  if (handler is! EngineRequestHandler) return null;
  final observer = handler.observer;
  return observer is LeakTracker ? observer.report : null;
}
