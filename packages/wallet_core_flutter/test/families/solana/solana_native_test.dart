/// The Solana family against the real host library: `solana-sign-legacy-1`
/// byte for byte through the signing core, `solana-address-n/a-1` through the
/// public session, the HD-derived key through the session's signer, the
/// fee-payer slot through the multi-key seam, and every rejection before a key
/// is read or derived.
///
/// Skips when the library is absent; `WCF_NATIVE_REQUIRED=1` turns that into
/// a failure (see `../../support/host_library.dart`).
@Tags(['native'])
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;
// ignore: implementation_imports
import 'package:wallet_core_flutter_bindings/src/generated/proto/Solana.pb.dart'
    as sol;
import 'package:wallet_core_flutter/advanced.dart';
import 'package:wallet_core_flutter/src/engine/handles.dart';
import 'package:wallet_core_flutter/src/families/family.dart';
import 'package:wallet_core_flutter/src/families/solana/solana_family.dart';
import 'package:wallet_core_flutter/src/session/testing.dart';
import 'package:wallet_core_flutter/src/signing/key_locator.dart';
import 'package:wallet_core_flutter/src/signing/signing_core.dart';
import 'package:wallet_core_flutter/src/worker/handler.dart';
import 'package:wallet_core_flutter/src/worker/protocol.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';

import '../../signing/signing_support.dart';
import '../../support/fixtures.dart';
import '../../support/host_library.dart';
import 'solana_support.dart';

/// Whether [haystack] holds [needle] at [offset]. A boolean, so a failing
/// assertion prints neither.
bool _atOffset(List<int> haystack, int offset, List<int> needle) =>
    offset + needle.length <= haystack.length &&
    listEquals(haystack.sublist(offset, offset + needle.length), needle);

/// The Solana family with a separate fee payer's slot in use: the same
/// encoder and parser, `[primary, feePayer]` as the roles. **Test only** — the
/// public request cannot name a fee payer, so no real family says this; it
/// exercises T2.0's multi-key seam on the slot the family wires.
final class _FeePayerFamily
    implements TransactionFamily<SolanaTransactionRequest, SolanaSignResult> {
  const _FeePayerFamily(this.roles);

  final List<KeyRole> roles;

  @override
  ChainFamily get chainFamily => solanaFamily.chainFamily;

  @override
  String get signingInputMessage => solanaFamily.signingInputMessage;

  @override
  Uint8List encodeKeylessInput(SolanaTransactionRequest request) =>
      solanaFamily.encodeKeylessInput(request);

  @override
  GeneratedMessage decodeSigningInput(Uint8List bytes) =>
      solanaFamily.decodeSigningInput(bytes);

  @override
  SolanaSignResult parseSigningOutput(
    Uint8List bytes, {
    required Coin coin,
    required Set<KeyLocator> usedKeys,
  }) => solanaFamily.parseSigningOutput(bytes, coin: coin, usedKeys: usedKeys);

  @override
  List<KeyRole> requiredRoles(SolanaTransactionRequest request) => roles;

  @override
  KeyFieldList get keyFields => solanaFamily.keyFields;

  @override
  KeyFieldEntry injectionField(KeyRole role) =>
      solanaFamily.injectionField(role);
}

void main() {
  final skip = hostLibrarySkipReason();

  group('SyncSigningCore with the Solana family', skip: skip, () {
    late WalletCoreBindings bindings;
    late Map<dynamic, dynamic> input;
    late Map<dynamic, dynamic> expected;

    late LeakTracker tracker;
    late SyncSigningCore core;
    late int nativeSignCalls;
    Uint8List? received;
    final handles = <PrivateKeyHandle>[];

    setUpAll(() {
      bindings = openHostBindings();
      final vector = vectorById(loadInventory(), signVectorId);
      input = vector.input as Map;
      expected = vector.expected as Map;
    });

    setUp(() {
      tracker = LeakTracker.maybeCreate()!;
      final context = NativeContext(bindings, observer: tracker);
      nativeSignCalls = 0;
      received = null;
      core = SyncSigningCore(
        context,
        anySignerSign: (Pointer<Void> data, TWCoinType coin) {
          nativeSignCalls++;
          final size = bindings.TWDataSize(data);
          received = Uint8List.fromList(
            bindings.TWDataBytes(data).asTypedList(size),
          );
          return bindings.TWAnySignerSign(data, coin);
        },
      );
    });

    tearDown(() {
      received?.fillRange(0, received!.length, 0);
      for (final handle in handles) {
        handle.dispose();
      }
      handles.clear();
      final report = tracker.report;
      expect(report.live, 0, reason: '$report');
      expect(report.finalizedWithoutDispose, 0, reason: '$report');
      tracker.stop();
    });

    /// The vector's published base58 test key, converted by upstream, as a
    /// key handle the tearDown disposes. Tests only: the SDK never converts a
    /// key (AGENTS.md rule 2).
    PrivateKeyHandle vectorKeyHandle() {
      final raw = base58DecodeByUpstream(
        core.context,
        input['private_key_base58'] as String,
      );
      expect(raw, hasLength(32));
      final handle = privateKeyHandleOf(core.context, raw);
      raw.fillRange(0, raw.length, 0);
      handles.add(handle);
      return handle;
    }

    final usedKeys = {KeyLocator.imported(issueKeyRef(1))};
    const roles = [KeyRole.primary];

    test("reproduces the vector's encoded and unsigned_tx byte for byte "
        '(solana-sign-legacy-1)', () {
      final request = vectorRequest(input);
      final keys = {KeyRole.primary: vectorKeyHandle()};
      final disposedBefore = tracker.report.disposed;
      final result = core.sign(
        solanaFamily.encodeKeylessInput(request),
        family: solanaFamily,
        coin: request.coin,
        requiredRoles: roles,
        keys: keys,
        usedKeys: usedKeys,
      );
      expect(result.encoded, expected['encoded']);
      expect(result.unsignedTransaction, expected['unsigned_tx']);
      expect(result.encoding, SolanaEncoding.base58);
      expect(result.coin, Coin.solana);
      expect(result.usedKeys, usedKeys);
      expect(nativeSignCalls, 1);
      // The key's TWData, the keyed input and the output; the key handle is
      // borrowed and still the test's.
      expect(tracker.report.disposed - disposedBefore, 3);
      expect(keys[KeyRole.primary]!.isDisposed, isFalse);
    });

    test('signing again with the same borrowed handle gives the same '
        'bytes', () {
      final key = vectorKeyHandle();
      final keyless = solanaFamily.encodeKeylessInput(vectorRequest(input));
      SolanaSignResult sign() => core.sign(
        keyless,
        family: solanaFamily,
        coin: Coin.solana,
        requiredRoles: roles,
        keys: {KeyRole.primary: key},
        usedKeys: usedKeys,
      );
      final first = sign();
      expect(key.isDisposed, isFalse);
      expect(sign().encoded, first.encoded);
      expect(first.encoded, expected['encoded']);
    });

    test('the keyed input upstream receives is private_key (1), then the '
        'key-less bytes: the key is prepended', () {
      final request = vectorRequest(input);
      final keyless = solanaFamily.encodeKeylessInput(request);
      final key = base58DecodeByUpstream(
        core.context,
        input['private_key_base58'] as String,
      );
      core.sign(
        keyless,
        family: solanaFamily,
        coin: Coin.solana,
        requiredRoles: roles,
        keys: {KeyRole.primary: vectorKeyHandle()},
        usedKeys: usedKeys,
      );
      final header = lengthDelimitedHeader(1, key.length);
      final bytes = received!;
      expect(bytes.length, header.length + key.length + keyless.length);
      // Compared as booleans, so a failure prints no key byte.
      expect(_atOffset(bytes, 0, header), isTrue);
      expect(_atOffset(bytes, header.length, key), isTrue);
      expect(_atOffset(bytes, header.length + key.length, keyless), isTrue);
      key.fillRange(0, key.length, 0);
    });

    test('a second key in the feePayer role is injected as '
        'fee_payer_private_key (17), in requiredRoles order, and upstream '
        'signs with both (no vector: the bytes are not asserted)', () {
      final request = vectorRequest(input);
      final keyless = solanaFamily.encodeKeylessInput(request);
      final sender = base58DecodeByUpstream(
        core.context,
        input['private_key_base58'] as String,
      );
      // Any 32 bytes are an Ed25519 private key; this one is not a vector's.
      final payer = Uint8List.fromList(List<int>.filled(32, 0x11));
      final payerHandle = privateKeyHandleOf(core.context, payer);
      handles.add(payerHandle);
      final keys = {
        KeyRole.primary: vectorKeyHandle(),
        KeyRole.feePayer: payerHandle,
      };

      const family = _FeePayerFamily([KeyRole.primary, KeyRole.feePayer]);
      final result = core.sign(
        keyless,
        family: family,
        coin: Coin.solana,
        requiredRoles: family.roles,
        keys: keys,
        usedKeys: usedKeys,
      );
      final senderHeader = lengthDelimitedHeader(1, 32);
      final payerHeader = lengthDelimitedHeader(17, 32);
      var offset = 0;
      expect(_atOffset(received!, offset, senderHeader), isTrue);
      offset += senderHeader.length;
      expect(_atOffset(received!, offset, sender), isTrue);
      offset += 32;
      expect(_atOffset(received!, offset, payerHeader), isTrue);
      offset += payerHeader.length;
      expect(_atOffset(received!, offset, payer), isTrue);
      offset += 32;
      expect(_atOffset(received!, offset, keyless), isTrue);
      expect(received!.length, offset + keyless.length);
      // Upstream took the second key as the fee payer: it is a different
      // transaction from the single-signer vector's, with two signatures'
      // worth of account keys.
      expect(result.encoded, isNot(expected['encoded']));
      expect(result.unsignedTransaction, isNot(expected['unsigned_tx']));
      expect(result.encoded, isNotEmpty);
      expect(nativeSignCalls, 1);

      // The order is requiredRoles', not the map's.
      const swapped = _FeePayerFamily([KeyRole.feePayer, KeyRole.primary]);
      core.sign(
        keyless,
        family: swapped,
        coin: Coin.solana,
        requiredRoles: swapped.roles,
        keys: keys,
        usedKeys: usedKeys,
      );
      expect(_atOffset(received!, 0, payerHeader), isTrue);
      expect(
        _atOffset(received!, payerHeader.length + 32, senderHeader),
        isTrue,
      );
      sender.fillRange(0, 32, 0);
    });

    test('a role the family has no slot for is a defect of the caller, '
        'before any key is read', () {
      final keys = {
        KeyRole.primary: vectorKeyHandle(),
        KeyRole.input(0): vectorKeyHandle(),
      };
      expect(
        () => core.sign(
          solanaFamily.encodeKeylessInput(vectorRequest(input)),
          family: _FeePayerFamily([KeyRole.primary, KeyRole.input(0)]),
          coin: Coin.solana,
          requiredRoles: [KeyRole.primary, KeyRole.input(0)],
          keys: keys,
          usedKeys: usedKeys,
        ),
        throwsStateError,
      );
      expect(nativeSignCalls, 0);
    });

    test('key-less bytes already carrying a key field — including the nested '
        'nonce-account key — are rejected before the key is read', () {
      final keyless = solanaFamily.encodeKeylessInput(vectorRequest(input));
      final tampered = <Uint8List>[
        (sol.SigningInput.fromBuffer(
          keyless,
        )..privateKey = List.filled(32, 1)).writeToBuffer(),
        (sol.SigningInput.fromBuffer(
          keyless,
        )..feePayerPrivateKey = List.filled(32, 1)).writeToBuffer(),
        (sol.SigningInput.fromBuffer(keyless)
              ..createNonceAccount = sol.CreateNonceAccount(
                nonceAccount: input['to_address'] as String,
                nonceAccountPrivateKey: List.filled(32, 1),
              ))
            .writeToBuffer(),
      ];
      final key = vectorKeyHandle();
      final disposedBefore = tracker.report.disposed;
      for (final bytes in tampered) {
        expect(
          () => core.sign(
            bytes,
            family: solanaFamily,
            coin: Coin.solana,
            requiredRoles: roles,
            keys: {KeyRole.primary: key},
            usedKeys: usedKeys,
          ),
          throwsA(
            isA<InvalidInputError>().having(
              (e) => e.inputName,
              'inputName',
              'signingInput',
            ),
          ),
        );
      }
      expect(nativeSignCalls, 0);
      expect(tracker.report.disposed, disposedBefore, reason: 'no key copy');
    });

    test('a coin outside the family is refused before the key is read', () {
      expect(
        () => core.sign(
          solanaFamily.encodeKeylessInput(vectorRequest(input)),
          family: solanaFamily,
          coin: Coin.ethereum,
          requiredRoles: roles,
          keys: {KeyRole.primary: vectorKeyHandle()},
          usedKeys: usedKeys,
        ),
        throwsA(
          isA<InvalidInputError>().having(
            (e) => e.inputName,
            'inputName',
            'coin',
          ),
        ),
      );
      expect(nativeSignCalls, 0);
    });

    test("upstream's refusal of a blockhash that is not 32 bytes is a "
        'SigningError with its code and message, and nothing is left '
        'undisposed', () {
      // 33 characters of '1' are 33 zero bytes: base58 syntax the request
      // accepts, a length upstream does not.
      final request = SolanaTransactionRequest.transfer(
        to: input['to_address'] as String,
        lamports: 42,
        recentBlockhash: '1' * 33,
      );
      final keys = {KeyRole.primary: vectorKeyHandle()};
      final disposedBefore = tracker.report.disposed;
      expect(
        () => core.sign(
          solanaFamily.encodeKeylessInput(request),
          family: solanaFamily,
          coin: Coin.solana,
          requiredRoles: roles,
          keys: keys,
          usedKeys: usedKeys,
        ),
        throwsA(
          isA<SigningError>()
              .having((e) => e.upstreamCode, 'upstreamCode', isNot(0))
              .having(
                (e) => e.upstreamCode,
                'upstreamCode',
                isNot(SigningError.malformedOutputCode),
              )
              .having((e) => e.message, 'message', isNotEmpty),
        ),
      );
      expect(nativeSignCalls, 1);
      expect(tracker.report.disposed - disposedBefore, 3);
    });
  });

  group('EngineRequestHandler signing a Solana transfer', skip: skip, () {
    late Map<dynamic, dynamic> account;
    late Map<dynamic, dynamic> signInput;

    late EngineRequestHandler handler;
    late RecordingCore core;
    late int walletRef;
    var nextId = 1;
    const token = 7;

    setUpAll(() {
      final inventory = loadInventory();
      account = vectorById(inventory, addressVectorId).input as Map;
      signInput = vectorById(inventory, signVectorId).input as Map;
    });

    WorkerReply handle(WorkerRequest Function(int id) build) =>
        handler.handle(build(nextId++));

    setUp(() {
      handler = EngineRequestHandler(
        signingCore: (context) =>
            core = RecordingCore(SyncSigningCore(context)),
      );
      expect(
        handle(
          (id) => Init(
            id,
            queueLimit: 4,
            hostLibraryPath: findHostLibrary(),
            expectedIdentity: hostIdentity,
            sessionToken: token,
          ),
        ),
        isA<InitOk>(),
      );
      walletRef = (handle(
        (id) => ImportWallet.mnemonic(id, account['mnemonic'] as String),
      ) as WalletCreated).walletRef;
    });

    tearDown(() {
      handle((id) => Shutdown(id, grace: const Duration(seconds: 1)));
      final report = (handler.observer! as LeakTracker).report;
      expect(report.live, 0, reason: '$report');
      expect(report.finalizedWithoutDispose, 0, reason: '$report');
    });

    HdLocatorSpec hd({Coin? coin, KeyRole? role}) => HdLocatorSpec(
      sessionToken: token,
      walletRef: walletRef,
      coin: coin ?? Coin.solana,
      derivationPath: account['derivation_path'] as String,
      role: role,
    );

    WorkerReply sign(Set<LocatorSpec> keys, {String? to}) => handle(
      (id) => Sign(
        id,
        request: SolanaTransactionRequest.transfer(
          to: to ?? signInput['to_address'] as String,
          lamports: 42,
          recentBlockhash: signInput['recent_blockhash'] as String,
        ),
        keys: keys,
      ),
    );

    void expectRejectedBeforeDerivation(WorkerReply reply, Matcher matcher) {
      expect(reply, isA<Failed>().having((r) => r.error, 'error', matcher));
      expect(handler.keysDerived, 0, reason: 'no key may be derived');
      expect(core.calls, 0, reason: 'the core may not be called');
    }

    test('a valid request derives one key, hands the core one primary key, '
        'and returns a SolanaSignResult', () {
      final reply = sign({hd()});
      expect(reply, isA<Signed>());
      final result = (reply as Signed).result as SolanaSignResult;
      expect(result.coin, Coin.solana);
      expect(result.encoded, isNotEmpty);
      expect(result.unsignedTransaction, isNotEmpty);
      expect(result.usedKeys, isEmpty);
      expect(handler.keysDerived, 1);
      expect(core.calls, 1);
      expect(core.lastRoles, [KeyRole.primary]);
      expect(core.lastCoin, Coin.solana);
      final report = (handler.observer! as LeakTracker).report;
      expect(report.liveByType, {'HDWallet': 1}, reason: '$report');
    });

    test('a recipient upstream rejects is InvalidInputError(to), before any '
        'key is derived', () {
      // 33 characters of '1' are 33 zero bytes: base58, but not an address.
      expectRejectedBeforeDerivation(
        sign({hd()}, to: '1' * 33),
        isA<InvalidInputError>().having((e) => e.inputName, 'input', 'to'),
      );
    });

    test('a locator in the feePayer role is refused: the request names no '
        'fee payer, so no such key is used', () {
      expectRejectedBeforeDerivation(
        sign({hd(role: KeyRole.feePayer)}),
        isA<KeyResolutionError>().having(
          (e) => e.reason,
          'reason',
          KeyResolutionReason.unusedLocator,
        ),
      );
      expectRejectedBeforeDerivation(
        sign({hd(), hd(role: KeyRole.feePayer)}),
        isA<KeyResolutionError>().having(
          (e) => e.reason,
          'reason',
          KeyResolutionReason.unusedLocator,
        ),
      );
    });

    test('a locator for another coin, and an empty set, are typed errors '
        'before any key is derived', () {
      expectRejectedBeforeDerivation(
        sign({hd(coin: Coin.ethereum)}),
        isA<InvalidInputError>().having((e) => e.inputName, 'input', 'keys'),
      );
      expectRejectedBeforeDerivation(
        sign(const <LocatorSpec>{}),
        isA<KeyResolutionError>().having(
          (e) => e.reason,
          'reason',
          KeyResolutionReason.missingRole,
        ),
      );
    });
  });

  group('WalletCore through the public surface', skip: skip, () {
    late Map<dynamic, dynamic> accountVector;
    late Map<dynamic, dynamic> signInput;
    late Map<dynamic, dynamic> signExpected;
    late WalletCore core;

    setUpAll(() {
      final inventory = loadInventory();
      accountVector = vectorById(inventory, addressVectorId).input as Map;
      signInput = vectorById(inventory, signVectorId).input as Map;
      signExpected = vectorById(inventory, signVectorId).expected as Map;
    });

    setUp(() async {
      core = await initializeForTesting(
        hostLibraryPath: findHostLibrary(),
        expectedIdentity: hostIdentity,
      );
    });

    tearDown(() async {
      await core.shutdown();
      final after = debugLeakReportOf(core)!;
      expect(after.live, 0, reason: '$after');
      expect(after.finalizedWithoutDispose, 0, reason: '$after');
    });

    test('the vector mnemonic derives solana-address-n/a-1 through the '
        'public API', () async {
      final vector = vectorById(loadInventory(), addressVectorId);
      final wallet = await core.wallets.importMnemonic(
        accountVector['mnemonic'] as String,
      );
      final account = await wallet.account(
        Coin.byId(vector.coin),
        path: accountVector['derivation_path'] as String,
      );
      expect(account.address.value, (vector.expected as Map)['address']);
      expect(account.derivationPath, accountVector['derivation_path']);
      expect(
        await core.addresses.isValid(account.address.value, coin: Coin.solana),
        isTrue,
      );
      // The default derivation is the same path, as the vector's source says.
      final byDefault = await wallet.account(Coin.solana);
      expect(byDefault.address.value, account.address.value);
      await wallet.close();
    });

    test('signer.sign with the HD key signs as the address of '
        'solana-address-n/a-1: its public key is the first account key of '
        'the transaction', () async {
      final wallet = await core.wallets.importMnemonic(
        accountVector['mnemonic'] as String,
      );
      final locator = KeyLocator.hdPath(
        wallet.ref,
        Coin.solana,
        accountVector['derivation_path'] as String,
      );
      final request = vectorRequest(signInput);
      final result = await core.signer.sign(request, {locator});
      expect(result, isA<SolanaSignResult>());
      final solana = result as SolanaSignResult;
      expect(solana.coin, Coin.solana);
      expect(solana.usedKeys, {locator});
      expect(solana.encoding, SolanaEncoding.base58);
      expect(solana.toString(), isNot(contains(solana.encoded)));

      // The wire layout of a one-signer legacy transaction, per Solana's
      // transaction format: signature count (1), the 64-byte signature, the
      // message header (3 bytes), the account count, then the 32-byte account
      // keys, fee payer first. Checked on the vector's own transaction first,
      // so the layout this test reads is the one upstream writes.
      final context = NativeContext(openHostBindings());
      Uint8List decode(String text) => base58DecodeByUpstream(context, text);
      final vectorTx = decode(signExpected['encoded'] as String);
      expect(vectorTx[0], 1, reason: 'one signature');
      expect(vectorTx.sublist(65, 68), [1, 0, 1], reason: 'message header');
      final signedTx = decode(solana.encoded);
      expect(signedTx[0], 1);
      expect(signedTx.sublist(65, 68), [1, 0, 1]);
      final signerKey = signedTx.sublist(69, 101);
      final address =
          (vectorById(loadInventory(), addressVectorId).expected
                  as Map)['address']
              as String;
      expect(listEquals(signerKey, decode(address)), isTrue);
      expect(
        solana.unsignedTransaction,
        isNot(signExpected['unsigned_tx']),
        reason: 'another signer, another message',
      );
      await wallet.close();
    });

    test('a recipient that is not an address and a feePayer-role locator '
        'are typed errors through the public signer', () async {
      final wallet = await core.wallets.importMnemonic(
        accountVector['mnemonic'] as String,
      );
      final path = accountVector['derivation_path'] as String;
      await expectLater(
        core.signer.sign(
          SolanaTransactionRequest.transfer(
            to: '1' * 33,
            lamports: 1,
            recentBlockhash: signInput['recent_blockhash'] as String,
          ),
          {KeyLocator.hdPath(wallet.ref, Coin.solana, path)},
        ),
        throwsA(
          isA<InvalidInputError>().having((e) => e.inputName, 'input', 'to'),
        ),
      );
      await expectLater(
        core.signer.sign(vectorRequest(signInput), {
          KeyLocator.hdPath(
            wallet.ref,
            Coin.solana,
            path,
            role: KeyRole.feePayer,
          ),
        }),
        throwsA(
          isA<KeyResolutionError>().having(
            (e) => e.reason,
            'reason',
            KeyResolutionReason.unusedLocator,
          ),
        ),
      );
      await wallet.close();
    });
  });
}
