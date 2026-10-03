// The sealed public error hierarchy and the boundary conversion. Pure Dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/src/errors/boundary.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';
import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart'
    as bindings;
import 'package:wallet_core_flutter_native/wallet_core_flutter_native.dart'
    as native;

import '../support/fixtures.dart';

/// Compiles only while the switch is exhaustive over the sealed hierarchy —
/// which is the property `sealed` exists to give a caller.
String _describe(WalletCoreException error) => switch (error) {
  UnknownCoinError() => 'unknown coin',
  InvalidInputError() => 'invalid input',
  UnsupportedOperationError() => 'unsupported',
  SigningError() => 'signing',
  KeyResolutionError() => 'key resolution',
  DisposedError() => 'disposed',
  ClosedError() => 'closed',
  WorkerTerminatedError() => 'worker terminated',
  NativeLoadError() => 'native load',
  ManifestMismatchError() => 'manifest mismatch',
  SessionStateError() => 'session state',
  QueueFullError() => 'queue full',
  OperationTimeoutError() => 'timeout',
  OperationCancelledError() => 'cancelled',
};

void main() {
  test('every member of the hierarchy is an Exception and renders its type '
      'and message', () {
    final errors = <WalletCoreException>[
      const InvalidInputError('bad', inputName: 'mnemonic'),
      const UnknownCoinError('nope'),
      UnsupportedOperationError(Coin.ethereum, 'network:testnet'),
      const SigningError(3, 'upstream said no'),
      const KeyResolutionError('missing role'),
      const DisposedError('HDWallet'),
      const ClosedError('Wallet'),
      const WorkerTerminatedError(WorkerTerminationKind.isolateExited),
      NativeLoadError('cannot open'),
      const ManifestMismatchError(
        check: ManifestCheck.artifactSetMismatch,
        expected: 'a',
        actual: 'b',
      ),
      const SessionStateError(SessionState.closing, attempted: 'sign'),
      const QueueFullError(32),
      const OperationTimeoutError('sign', Duration(seconds: 15)),
      const OperationCancelledError(42),
    ];
    for (final error in errors) {
      expect(error, isA<Exception>());
      expect(_describe(error), isNotEmpty);
      expect(error.message, isNotEmpty);
      expect(error.toString(), contains(error.message));
    }
    expect(
      UnsupportedOperationError(Coin.ethereum, 'network:testnet').toString(),
      startsWith(
        'UnsupportedOperationError: ethereum does not offer '
        'network:testnet',
      ),
    );
    expect(const UnknownCoinError('nope'), isA<InvalidInputError>());
  });

  test('UnknownCoinError shows the id, shortened when implausibly long', () {
    expect(const UnknownCoinError('nope').toString(), contains('"nope"'));
    final long = UnknownCoinError('x' * 500).toString();
    expect(long.length, lessThan(200));
  });

  test('WorkerTerminatedError names its cause by type only', () {
    const secret = 'zebra cabbage orbit secret';
    final error = WorkerTerminatedError(
      WorkerTerminationKind.uncaughtDartError,
      cause: StateError(secret),
    );
    expect(error.cause, isA<StateError>());
    expect(error.message, contains('StateError'));
    expectRedacted(error, [secret]);
  });

  group('boundary conversion', () {
    test('passes SDK errors through unchanged', () {
      const error = KeyResolutionError('x');
      expect(identical(toWalletCoreException(error), error), isTrue);
    });

    test("converts the bindings' DisposedError, keeping resourceType", () {
      final converted = toWalletCoreException(
        bindings.DisposedError('TWDataHandle'),
      );
      expect(
        converted,
        isA<DisposedError>().having(
          (e) => e.resourceType,
          'resourceType',
          'TWDataHandle',
        ),
      );
    });

    test("converts the native package's NativeLoadError, keeping every "
        'attempted location', () {
      final cause = ArgumentError('dlopen failed');
      final converted = toWalletCoreException(
        native.NativeLoadError(
          'could not load libTrustWalletCore',
          cause: cause,
          attempts: [
            native.LibraryLoadAttempt(
              location: '/a/libTrustWalletCore.dylib',
              error: ArgumentError('not found'),
            ),
            const native.LibraryLoadAttempt(
              location: 'process',
              error: 'symbol missing',
            ),
          ],
        ),
      );
      expect(converted, isA<NativeLoadError>());
      final error = converted! as NativeLoadError;
      expect(error.message, 'could not load libTrustWalletCore');
      expect(identical(error.cause, cause), isTrue);
      expect(error.attempts.map((a) => a.location), [
        '/a/libTrustWalletCore.dylib',
        'process',
      ]);
      expect(error.attempts.first.reason, contains('not found'));
      expect(error.attempts.last.reason, 'symbol missing');
      expect(error.toString(), contains('tried process: symbol missing'));
    });

    test("converts the native package's ManifestMismatchError, keeping "
        'check, expected, actual and detail', () {
      final converted = toWalletCoreException(
        native.ManifestMismatchError(
          check: native.ManifestCheck.upstreamCommitMismatch,
          expected: 'd692ac27',
          actual: 'deadbeef',
          detail: 'from wcf_build_info',
        ),
      );
      expect(
        converted,
        isA<ManifestMismatchError>()
            .having(
              (e) => e.check,
              'check',
              ManifestCheck.upstreamCommitMismatch,
            )
            .having((e) => e.expected, 'expected', 'd692ac27')
            .having((e) => e.actual, 'actual', 'deadbeef')
            .having((e) => e.detail, 'detail', 'from wcf_build_info'),
      );
      expect(converted!.message, contains('another upstream commit'));
    });

    test('leaves anything else to the caller', () {
      expect(toWalletCoreException(StateError('x')), isNull);
      expect(toWalletCoreException(RangeError('x')), isNull);
    });
  });
}
