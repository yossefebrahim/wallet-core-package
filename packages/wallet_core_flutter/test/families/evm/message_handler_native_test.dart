/// The executor's message-signing path against the real host library, driven
/// at the handler with a recording core: every refusal is typed and none
/// derives a key or reaches the core; a valid request derives exactly one key,
/// calls the core's message path once with the primary role, and leaves
/// nothing undisposed. A core that cannot sign messages is a defect, not an
/// input's fault.
///
/// Skips when the library is absent; `WCF_NATIVE_REQUIRED=1` turns that into
/// a failure (see `../../support/host_library.dart`).
@Tags(['native'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/advanced.dart' show LeakTracker;
import 'package:wallet_core_flutter/src/engine/handles.dart';
import 'package:wallet_core_flutter/src/errors/boundary.dart'
    show NativeResultError;
import 'package:wallet_core_flutter/src/families/family.dart';
import 'package:wallet_core_flutter/src/signing/signing_core.dart';
import 'package:wallet_core_flutter/src/worker/handler.dart';
import 'package:wallet_core_flutter/src/worker/protocol.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';

import '../../signing/signing_support.dart';
import '../../support/fixtures.dart';
import '../../support/host_library.dart';

const int _token = 7;

/// Signs transactions and messages through [delegate], recording the message
/// calls — never a key, only the roles it was given one for.
final class _RecordingMessageCore implements SigningCore, MessageSigningCore {
  _RecordingMessageCore(this.delegate);

  final SyncSigningCore delegate;
  int messageCalls = 0;
  List<KeyRole>? lastRoles;
  Set<KeyLocator>? lastUsedKeys;

  @override
  S sign<S extends SignResult>(
    Uint8List keylessInput, {
    required TransactionFamily<TransactionRequest, S> family,
    required Coin coin,
    required List<KeyRole> requiredRoles,
    required Map<KeyRole, PrivateKeyHandle> keys,
    required Set<KeyLocator> usedKeys,
  }) => throw StateError('this test signs messages only');

  @override
  S signMessage<S extends SignResult>(
    Uint8List keylessInput, {
    required MessageFamily<MessageRequest, S> family,
    required Coin coin,
    required List<KeyRole> requiredRoles,
    required Map<KeyRole, PrivateKeyHandle> keys,
    required Set<KeyLocator> usedKeys,
  }) {
    messageCalls++;
    lastRoles = List<KeyRole>.of(requiredRoles);
    lastUsedKeys = usedKeys;
    return delegate.signMessage(
      keylessInput,
      family: family,
      coin: coin,
      requiredRoles: requiredRoles,
      keys: keys,
      usedKeys: usedKeys,
    );
  }
}

void main() {
  final skip = hostLibrarySkipReason();

  group('EngineRequestHandler message signing', skip: skip, () {
    late Map<dynamic, dynamic> account;

    late EngineRequestHandler handler;
    _RecordingMessageCore? core;
    late int walletRef;
    var nextId = 1;

    setUpAll(() {
      account =
          vectorById(loadInventory(), 'ethereum-address-n/a-1').input as Map;
    });

    WorkerReply handle(WorkerRequest Function(int id) build) =>
        handler.handle(build(nextId++));

    void start(SigningCoreFactory factory) {
      handler = EngineRequestHandler(signingCore: factory);
      expect(
        handle(
          (id) => Init(
            id,
            queueLimit: 4,
            hostLibraryPath: findHostLibrary(),
            expectedIdentity: hostIdentity,
            sessionToken: _token,
          ),
        ),
        isA<InitOk>(),
      );
      final created = handle(
        (id) => ImportWallet.mnemonic(id, account['mnemonic'] as String),
      );
      walletRef = (created as WalletCreated).walletRef;
    }

    setUp(() {
      core = null;
      start(
        (context) => core = _RecordingMessageCore(SyncSigningCore(context)),
      );
    });

    tearDown(() {
      handle((id) => Shutdown(id, grace: const Duration(seconds: 1)));
      final tracker = handler.observer! as LeakTracker;
      final report = tracker.report;
      expect(report.live, 0, reason: '$report');
      expect(report.finalizedWithoutDispose, 0, reason: '$report');
    });

    HdLocatorSpec hd({int? token, Coin? coin, KeyRole? role}) => HdLocatorSpec(
      sessionToken: token ?? _token,
      walletRef: walletRef,
      coin: coin ?? Coin.ethereum,
      derivationPath: account['derivation_path'] as String,
      role: role,
    );

    EvmMessageRequest message({int? chainId}) => EvmMessageRequest.personal(
      Uint8List.fromList(utf8.encode('Foo')),
      coin: Coin.ethereum,
      chainId: chainId,
    );

    WorkerReply signMessage(
      Set<LocatorSpec> keys, {
      EvmMessageRequest? request,
    }) => handle(
      (id) => SignMessage(id, request: request ?? message(), keys: keys),
    );

    void expectRejectedBeforeDerivation(WorkerReply reply, Matcher matcher) {
      expect(reply, isA<Failed>().having((r) => r.error, 'error', matcher));
      expect(handler.keysDerived, 0, reason: 'no key may be derived');
      expect(core!.messageCalls, 0, reason: 'the core may not be called');
    }

    test('a valid request derives one key, reaches the core once with the '
        'primary role and empty usedKeys, and replies MessageSigned', () {
      final reply = signMessage({hd()});
      expect(reply, isA<MessageSigned>());
      final result = (reply as MessageSigned).result as EvmMessageSignResult;
      expect(result.signature, hasLength(65));
      expect(result.usedKeys, isEmpty);
      expect(result.messageType, EvmMessageType.personal);
      expect(handler.keysDerived, 1);
      expect(core!.messageCalls, 1);
      expect(core!.lastRoles, [KeyRole.primary]);
      expect(core!.lastUsedKeys, isEmpty);
      expect(handler.liveRefCount, 1);
      final tracker = handler.observer! as LeakTracker;
      expect(tracker.report.live, 1, reason: 'the wallet only');
    });

    test('an EIP-155 variant is UnsupportedOperationError before any '
        'derivation or core call', () {
      expectRejectedBeforeDerivation(
        signMessage({hd()}, request: message(chainId: 5)),
        isA<UnsupportedOperationError>().having(
          (e) => e.capability,
          'capability',
          'messageType:eip155',
        ),
      );
    });

    test('resolution failures are the transaction path\'s, typed, before any '
        'derivation', () {
      expectRejectedBeforeDerivation(
        signMessage(<LocatorSpec>{}),
        isA<KeyResolutionError>().having(
          (e) => e.reason,
          'reason',
          KeyResolutionReason.missingRole,
        ),
      );
      expectRejectedBeforeDerivation(
        signMessage({hd(token: _token + 1)}),
        isA<KeyResolutionError>().having(
          (e) => e.reason,
          'reason',
          KeyResolutionReason.foreignRef,
        ),
      );
      expectRejectedBeforeDerivation(
        signMessage({hd(coin: Coin.bitcoin)}),
        isA<InvalidInputError>().having((e) => e.inputName, 'input', 'keys'),
      );
      expectRejectedBeforeDerivation(
        signMessage({const ExternalLocatorSpec(deviceId: 'ledger-1')}),
        isA<UnsupportedOperationError>().having(
          (e) => e.capability,
          'capability',
          'external-signer',
        ),
      );
    });

    test('a soft native failure while signing a message is a SigningError '
        'with the malformed-output code, and the handler stays usable', () {
      final request = SignMessage(
        99,
        request: message(),
        keys: <LocatorSpec>{hd()},
      );
      final mapped = softNativeFailure(
        request,
        const NativeResultError('TWPrivateKeyData returned nullptr'),
      );
      expect(
        mapped,
        isA<SigningError>().having(
          (e) => e.upstreamCode,
          'code',
          SigningError.malformedOutputCode,
        ),
      );
      expect(signMessage({hd()}), isA<MessageSigned>());
    });

    test('a core that cannot sign messages is a defect: StateError, rethrown, before '
        'any key is derived', () {
      // Replace the handler with one whose core only signs transactions.
      handle((id) => Shutdown(id, grace: const Duration(seconds: 1)));
      start((context) => RecordingCore(SyncSigningCore(context)));
      expect(() => signMessage({hd()}), throwsStateError);
    });
  });
}
