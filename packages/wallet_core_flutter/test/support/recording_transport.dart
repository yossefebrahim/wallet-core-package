/// A session over the in-process executor that records every reply the
/// executor posts, before the session sees it — what a worker isolate would
/// have sent across the boundary.
library;

import 'package:wallet_core_flutter/src/session/session.dart';
import 'package:wallet_core_flutter/src/session/wallet_core.dart';
import 'package:wallet_core_flutter/src/worker/handler.dart';
import 'package:wallet_core_flutter/src/worker/protocol.dart';
import 'package:wallet_core_flutter/src/worker/transport.dart';

/// Starts a session over [handler] and returns it with the list every
/// posted reply is appended to, in posting order.
Future<(WalletCoreSession, List<WorkerReply>)> startRecordingSession(
  RequestHandler handler, {
  int queueLimit = 32,
  OperationTimeouts timeouts = const OperationTimeouts(),
}) async {
  final posted = <WorkerReply>[];
  final session = await startSession(
    queueLimit: queueLimit,
    timeouts: timeouts,
    transport: ({required onReply, required onTerminated}) =>
        InProcessTransport(
          handler,
          onReply: (reply) {
            posted.add(reply);
            onReply(reply);
          },
          onTerminated: onTerminated,
        ),
  );
  return (session, posted);
}
