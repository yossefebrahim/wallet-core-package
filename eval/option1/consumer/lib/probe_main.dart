// Entry point for a release run on a device or simulator, where integration
// tests do not run (PRD §12.2 steps 2 and 3):
//
//   flutter run --release -t lib/probe_main.dart \
//       --dart-define=WCF_EXPECTED_ARTIFACT_SET_ID=as_4.8.0_001 \
//       --dart-define=WCF_EXPECTED_UPSTREAM_COMMIT=d692ac27749d0c615e17c751b70ab4f0aa75c59b
//
// Shows the probe's outcome on screen and prints it, prefixed WCF_PROBE.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.

import 'package:flutter/material.dart';

import 'wallet_core_probe.dart';

void main() {
  String outcome;
  try {
    outcome = 'PASS ${runProbe()}';
  } on Object catch (e) {
    outcome = 'FAIL $e';
  }
  // ignore: avoid_print
  print('WCF_PROBE $outcome');
  runApp(
    MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(outcome, key: const Key('wcf-probe-outcome')),
          ),
        ),
      ),
    ),
  );
}
