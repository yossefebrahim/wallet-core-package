/// The `wallet_core_flutter` example app: the M0 flow, step by step, on the
/// public SDK surface.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// The app imports `package:flutter/*`, the public SDK library, and its own
/// files — never `advanced.dart`, a `src/` path of the SDK, `dart:ffi`, or a
/// generated or protobuf type (AGENTS.md rules 4 and 12). See README.md.
library;

import 'package:flutter/material.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';

import 'src/m0_flow.dart';
import 'src/m0_page.dart';

void main() => runApp(const ExampleApp());

/// The app. [startSession] is step 1's call: [WalletCore.initialize], which
/// takes no library path. A test supplies the SDK's test entry point.
class ExampleApp extends StatelessWidget {
  /// The app over [startSession].
  const ExampleApp({super.key, this.startSession = WalletCore.initialize});

  /// Starts the session step 1 shows.
  final SessionStarter startSession;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'wallet_core_flutter example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: M0Page(startSession: startSession),
    );
  }
}
