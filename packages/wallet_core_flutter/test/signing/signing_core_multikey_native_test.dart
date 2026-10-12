/// The multi-key seam of `SigningCore.sign` (T2.0), without a UTXO or Solana
/// family: a TEST-ONLY family over a real generated upstream message that has
/// the shapes the real families will need —
///
/// * Bitcoin's `SigningInput.private_key` is `repeated`: two roles
///   (`input(0)`, `input(1)`) into the **same** field, in order;
/// * Solana's `SigningInput` has `private_key` (1) and `fee_payer_private_key`
///   (17): two roles (`primary`, `feePayer`) into **different** fields.
///
/// The keys are the raw test keys of `test_vectors/bitcoin/vectors.yaml` (the
/// two keys of `bitcoin-sign-multi_input-1`) and
/// `test_vectors/solana/vectors.yaml` (`solana-sign-legacy-1`), made into
/// `PrivateKeyHandle`s with `TWPrivateKeyCreateWithData`.
///
/// What is inspected, and how: the core's `anySignerSign` seam captures the
/// keyed bytes upstream would receive, and the tests decode them as the
/// message. The capture and the decoded message are the **test's** copies of
/// the keys, made so that the assertion can be made, and are overwritten at
/// the end; the properties asserted about the SDK are about what it returns,
/// throws, allocates and releases.
///
/// Skips when the library is absent; `WCF_NATIVE_REQUIRED=1` turns that into
/// a failure (see `../support/host_library.dart`).
@Tags(['native'])
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' show calloc;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;
import 'package:wallet_core_flutter/advanced.dart';
import 'package:wallet_core_flutter/src/coin/chain_family.dart';
import 'package:wallet_core_flutter/src/engine/handles.dart';
import 'package:wallet_core_flutter/src/errors/errors.dart';
import 'package:wallet_core_flutter/src/families/evm/evm_family.dart';
import 'package:wallet_core_flutter/src/families/family.dart';
import 'package:wallet_core_flutter/src/requests/requests.dart';
import 'package:wallet_core_flutter/src/signing/key_locator.dart';
import 'package:wallet_core_flutter/src/signing/sign_result.dart';
import 'package:wallet_core_flutter/src/signing/signing_core.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart' show Coin;
// ignore: implementation_imports
import 'package:wallet_core_flutter_bindings/src/generated/proto/Bitcoin.pb.dart'
    as btc;
// ignore: implementation_imports
import 'package:wallet_core_flutter_bindings/src/generated/proto/Ethereum.pb.dart'
    as eth;
// ignore: implementation_imports
import 'package:wallet_core_flutter_bindings/src/generated/proto/Solana.pb.dart'
    as sol;

import '../support/fixtures.dart';
import '../support/host_library.dart';
import 'signing_support.dart';

// --- the reviewed key-field lists of the test families ----------------------

const _btcKey = KeyFieldEntry(
  messagePath: 'TW.Bitcoin.Proto.SigningInput',
  fieldName: 'private_key',
  fieldNumber: 6,
  repeated: true,
);

const _solKey = KeyFieldEntry(
  messagePath: 'TW.Solana.Proto.SigningInput',
  fieldName: 'private_key',
  fieldNumber: 1,
  repeated: false,
);
const _solFeePayerKey = KeyFieldEntry(
  messagePath: 'TW.Solana.Proto.SigningInput',
  fieldName: 'fee_payer_private_key',
  fieldNumber: 17,
  repeated: false,
);
const _solNonceKey = KeyFieldEntry(
  messagePath: 'TW.Solana.Proto.CreateNonceAccount',
  fieldName: 'nonce_account_private_key',
  fieldNumber: 3,
  repeated: false,
);

/// A family over a real generated message, with the roles and slots a test
/// gives it. Its output is an Ethereum one, because the sealed `SignResult`
/// has no other member yet: the tests' native-sign seam returns one.
final class _TestFamily
    implements TransactionFamily<EvmTransactionRequest, EvmSignResult> {
  _TestFamily({
    required this.chainFamily,
    required this.signingInputMessage,
    required this.keyFields,
    required this.roles,
    required this.slots,
    required this.keyless,
    required this.decode,
  });

  @override
  final ChainFamily chainFamily;

  @override
  final String signingInputMessage;

  @override
  final KeyFieldList keyFields;

  final List<KeyRole> roles;
  final Map<KeyRole, KeyFieldEntry> slots;
  final Uint8List keyless;
  final GeneratedMessage Function(Uint8List) decode;

  @override
  Uint8List encodeKeylessInput(EvmTransactionRequest request) => keyless;

  @override
  GeneratedMessage decodeSigningInput(Uint8List bytes) => decode(bytes);

  @override
  EvmSignResult parseSigningOutput(
    Uint8List bytes, {
    required Coin coin,
    required Set<KeyLocator> usedKeys,
  }) => evmFamily.parseSigningOutput(bytes, coin: coin, usedKeys: usedKeys);

  @override
  List<KeyRole> requiredRoles(EvmTransactionRequest request) => roles;

  @override
  KeyFieldEntry injectionField(KeyRole role) =>
      slots[role] ?? (throw ArgumentError.value(role, 'role', 'no slot'));
}

/// The native-sign seam: copies what upstream would receive, then answers with
/// a well-formed Ethereum `SigningOutput` — or throws.
final class _SignSeam {
  _SignSeam(this.bindings);

  final WalletCoreBindings bindings;
  Uint8List? captured;
  int calls = 0;
  bool failInstead = false;

  Pointer<Void> call(Pointer<Void> data, TWCoinType coin) {
    calls++;
    captured = Uint8List.fromList(
      bindings.TWDataBytes(data).asTypedList(bindings.TWDataSize(data)),
    );
    if (failInstead) throw StateError('the test seam refuses to sign');
    final output = eth.SigningOutput(encoded: <int>[1, 2, 3]).writeToBuffer();
    final buffer = calloc<Uint8>(output.length);
    try {
      buffer.asTypedList(output.length).setAll(0, output);
      return bindings.TWDataCreateWithBytes(buffer, output.length).cast<Void>();
    } finally {
      calloc.free(buffer);
    }
  }
}

/// `calloc`, recording every staging buffer's size and what it held at the
/// moment it was released — after the SDK overwrote it, before the memory goes
/// back to the allocator.
final class _RecordingAllocator implements Allocator {
  final Map<int, int> _live = <int, int>{};
  final List<int> allocatedSizes = <int>[];
  final List<Uint8List> heldAtFree = <Uint8List>[];

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount, {int? alignment}) {
    final pointer = calloc.allocate<T>(byteCount, alignment: alignment);
    _live[pointer.address] = byteCount;
    allocatedSizes.add(byteCount);
    return pointer;
  }

  @override
  void free(Pointer<NativeType> pointer) {
    final size = _live.remove(pointer.address);
    if (size != null) {
      heldAtFree.add(
        Uint8List.fromList(pointer.cast<Uint8>().asTypedList(size)),
      );
    }
    calloc.free(pointer);
  }

  bool get nothingLeaked => _live.isEmpty;
}

Uint8List _unhex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

Uint8List _unbase58(String text) {
  const alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
  var value = BigInt.zero;
  for (final char in text.split('')) {
    value = value * BigInt.from(58) + BigInt.from(alphabet.indexOf(char));
  }
  final bytes = <int>[];
  while (value > BigInt.zero) {
    bytes.insert(0, (value & BigInt.from(0xff)).toInt());
    value >>= 8;
  }
  final leadingZeros =
      text.length - text.replaceFirst(RegExp('^1+'), '').length;
  return Uint8List.fromList([...List<int>.filled(leadingZeros, 0), ...bytes]);
}

/// Whether [haystack] contains [needle] as a contiguous run. A boolean, so a
/// failing assertion prints neither.
bool _containsRun(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}

bool _allZero(List<int> bytes) => bytes.every((b) => b == 0);

void main() {
  final skip = hostLibrarySkipReason();

  group(
    'SyncSigningCore multi-key injection against the host library',
    skip: skip,
    () {
      late WalletCoreBindings bindings;
      late Uint8List btcKey0;
      late Uint8List btcKey1;
      late Uint8List solanaKey;

      late LeakTracker tracker;
      late _SignSeam seam;
      late _RecordingAllocator allocator;
      late SyncSigningCore core;
      final handles = <PrivateKeyHandle>[];
      final testCopies = <Uint8List>[];

      setUpAll(() {
        bindings = openHostBindings();
        final inventory = loadInventory();
        final utxos =
            vectorById(inventory, 'bitcoin-sign-multi_input-1').input['utxos']
                as List<dynamic>;
        btcKey0 = _unhex((utxos[0] as Map)['private_key'] as String);
        btcKey1 = _unhex((utxos[1] as Map)['private_key'] as String);
        solanaKey = _unbase58(
          vectorById(
                inventory,
                'solana-sign-legacy-1',
              ).input['private_key_base58']
              as String,
        );
        expect(solanaKey.length, 32);
        expect(btcKey0.length, 32);
        expect(btcKey1.length, 32);
      });

      setUp(() {
        tracker = LeakTracker.maybeCreate()!;
        seam = _SignSeam(bindings);
        allocator = _RecordingAllocator();
        core = SyncSigningCore(
          NativeContext(bindings, observer: tracker),
          anySignerSign: seam.call,
          stagingAllocator: allocator,
        );
      });

      tearDown(() {
        for (final handle in handles) {
          handle.dispose();
        }
        handles.clear();
        for (final copy in [...testCopies, ?seam.captured]) {
          copy.fillRange(0, copy.length, 0);
        }
        testCopies.clear();
        expect(allocator.nothingLeaked, isTrue);
        final report = tracker.report;
        expect(report.live, 0, reason: '$report');
        expect(report.finalizedWithoutDispose, 0, reason: '$report');
        tracker.stop();
      });

      PrivateKeyHandle handleOf(Uint8List raw) {
        final handle = privateKeyHandleOf(core.context, raw);
        handles.add(handle);
        return handle;
      }

      // --- Bitcoin shape: two roles, one repeated field ------------------------

      final btcKeyless = btc.SigningInput(
        hashType: 1,
        toAddress: '1Bp9U1ogV3A14FMvKbRJms7ctyso4Z4Tcx',
        changeAddress: '1FQc5LdgGHMHEN9nwkjmz6tWkxhPpxBvBU',
        useMaxAmount: true,
        utxo: [
          btc.UnspentTransaction(
            script: _unhex('00141d0f172a0ecb48aee1be1f2687d2963ae33f71a1'),
          ),
        ],
      ).writeToBuffer();

      _TestFamily btcFamily(List<KeyRole> roles) => _TestFamily(
        chainFamily: ChainFamily.utxo,
        signingInputMessage: 'TW.Bitcoin.Proto.SigningInput',
        keyFields: const KeyFieldList([_btcKey]),
        roles: roles,
        slots: {for (final role in roles) role: _btcKey},
        keyless: btcKeyless,
        decode: btc.SigningInput.fromBuffer,
      );

      final inputRoles = [KeyRole.input(0), KeyRole.input(1)];

      EvmSignResult signBtc(
        _TestFamily family,
        List<KeyRole> roles,
        Map<KeyRole, PrivateKeyHandle> keys,
      ) => core.sign(
        btcKeyless,
        family: family,
        coin: Coin.bitcoin,
        requiredRoles: roles,
        keys: keys,
        usedKeys: const <KeyLocator>{},
      );

      test('two roles into one repeated field: private_key holds exactly the '
          'two keys, in requiredRoles order, ahead of the key-less bytes', () {
        final keys = {
          // Inserted in reverse: the order of the map must not matter.
          KeyRole.input(1): handleOf(btcKey1),
          KeyRole.input(0): handleOf(btcKey0),
        };
        final disposedBefore = tracker.report.disposed;
        final result = signBtc(btcFamily(inputRoles), inputRoles, keys);

        expect(seam.calls, 1);
        final keyed = seam.captured!;
        final decoded = btc.SigningInput.fromBuffer(keyed);
        expect(decoded.privateKey.length, 2);
        expect(listEquals(decoded.privateKey[0], btcKey0), isTrue);
        expect(listEquals(decoded.privateKey[1], btcKey1), isTrue);
        expect(decoded.toAddress, '1Bp9U1ogV3A14FMvKbRJms7ctyso4Z4Tcx');
        expect(decoded.utxo.length, 1);

        // Byte level: header, key 0, header, key 1, then the key-less bytes.
        final header = lengthDelimitedHeader(6, 32);
        expect(keyed.length, 2 * (header.length + 32) + btcKeyless.length);
        expect(listEquals(keyed.sublist(0, header.length), header), isTrue);
        var at = header.length;
        expect(listEquals(keyed.sublist(at, at + 32), btcKey0), isTrue);
        at += 32;
        expect(
          listEquals(keyed.sublist(at, at + header.length), header),
          isTrue,
        );
        at += header.length;
        expect(listEquals(keyed.sublist(at, at + 32), btcKey1), isTrue);
        at += 32;
        expect(listEquals(keyed.sublist(at), btcKeyless), isTrue);

        expect(result.coin, Coin.bitcoin);
        // The key's two TWDatas, the keyed input and the output.
        expect(tracker.report.disposed - disposedBefore, 4);
        for (final handle in keys.values) {
          expect(handle.isDisposed, isFalse, reason: 'borrowed');
        }
      });

      test('the injection order is the family\'s requiredRoles order, not '
          'the map\'s', () {
        final swapped = [KeyRole.input(1), KeyRole.input(0)];
        signBtc(btcFamily(swapped), swapped, {
          KeyRole.input(0): handleOf(btcKey0),
          KeyRole.input(1): handleOf(btcKey1),
        });
        final decoded = btc.SigningInput.fromBuffer(seam.captured!);
        expect(listEquals(decoded.privateKey[0], btcKey1), isTrue);
        expect(listEquals(decoded.privateKey[1], btcKey0), isTrue);
      });

      test('the staging buffer held the whole keyed input and is all zeros '
          'when it is released — on success', () {
        signBtc(btcFamily(inputRoles), inputRoles, {
          KeyRole.input(0): handleOf(btcKey0),
          KeyRole.input(1): handleOf(btcKey1),
        });
        expect(allocator.allocatedSizes, [seam.captured!.length]);
        expect(allocator.heldAtFree.length, 1);
        expect(_allZero(allocator.heldAtFree.single), isTrue);
      });

      test('and when upstream\'s signer throws: staging zeroed, every TWData '
          'released, the error carries no key', () {
        seam.failInstead = true;
        final keys = {
          KeyRole.input(0): handleOf(btcKey0),
          KeyRole.input(1): handleOf(btcKey1),
        };
        final disposedBefore = tracker.report.disposed;
        Object? caught;
        try {
          signBtc(btcFamily(inputRoles), inputRoles, keys);
        } on Object catch (error) {
          caught = error;
        }
        expect(caught, isA<StateError>());
        expectRedacted(caught!, [_hexOf(btcKey0), _hexOf(btcKey1)]);
        expect(seam.calls, 1, reason: 'the throw came from the seam');
        expect(allocator.heldAtFree.length, 1);
        expect(_allZero(allocator.heldAtFree.single), isTrue);
        // Two key TWDatas and the keyed input; the signer never made an output.
        expect(tracker.report.disposed - disposedBefore, 3);
      });

      test('a handle disposed before the call fails typed after the first '
          'key was read: that copy is released, nothing is staged, upstream '
          'is never called', () {
        final first = handleOf(btcKey0);
        final second = handleOf(btcKey1);
        second.dispose();
        final disposedBefore = tracker.report.disposed;
        expect(
          () => signBtc(btcFamily(inputRoles), inputRoles, {
            KeyRole.input(0): first,
            KeyRole.input(1): second,
          }),
          throwsA(isA<Error>()),
        );
        expect(seam.calls, 0);
        expect(allocator.allocatedSizes, isEmpty, reason: 'nothing was staged');
        expect(tracker.report.disposed - disposedBefore, 1);
        expect(first.isDisposed, isFalse);
      });

      test('no key bytes in anything the SDK returned: the result and the '
          'key-less input', () {
        final keylessCopy = Uint8List.fromList(btcKeyless);
        final result = signBtc(btcFamily(inputRoles), inputRoles, {
          KeyRole.input(0): handleOf(btcKey0),
          KeyRole.input(1): handleOf(btcKey1),
        });
        for (final key in [btcKey0, btcKey1]) {
          expect(_containsRun(result.encoded, key), isFalse);
          expect(_containsRun(result.r, key), isFalse);
          expect(_containsRun(btcKeyless, key), isFalse);
          expect(_containsRun(result.toString().codeUnits, key), isFalse);
        }
        expect(
          listEquals(btcKeyless, keylessCopy),
          isTrue,
          reason: 'untouched',
        );
      });

      test('the key-field check still runs first, with several roles: a '
          'tampered key-less input fails before any key is read', () {
        final tampered = Uint8List.fromList([
          ...btcKeyless,
          ...lengthDelimitedHeader(6, 32),
          ...Uint8List(32)..fillRange(0, 32, 0x11),
        ]);
        testCopies.add(tampered);
        final keys = {
          KeyRole.input(0): handleOf(btcKey0),
          KeyRole.input(1): handleOf(btcKey1),
        };
        final disposedBefore = tracker.report.disposed;
        expect(
          () => core.sign(
            tampered,
            family: btcFamily(inputRoles),
            coin: Coin.bitcoin,
            requiredRoles: inputRoles,
            keys: keys,
            usedKeys: const <KeyLocator>{},
          ),
          throwsA(
            isA<InvalidInputError>().having(
              (e) => e.inputName,
              'inputName',
              'signingInput',
            ),
          ),
        );
        expect(seam.calls, 0);
        expect(allocator.allocatedSizes, isEmpty);
        expect(tracker.report.disposed - disposedBefore, 0);
      });

      // --- Solana shape: two roles, two fields ---------------------------------

      final solKeyless = sol.SigningInput(
        recentBlockhash: '11111111111111111111111111111111',
      ).writeToBuffer();

      _TestFamily solFamily({Map<KeyRole, KeyFieldEntry>? slots}) =>
          _TestFamily(
            chainFamily: ChainFamily.solana,
            signingInputMessage: 'TW.Solana.Proto.SigningInput',
            keyFields: const KeyFieldList([
              _solKey,
              _solFeePayerKey,
              _solNonceKey,
            ]),
            roles: [KeyRole.primary, KeyRole.feePayer],
            slots:
                slots ??
                {KeyRole.primary: _solKey, KeyRole.feePayer: _solFeePayerKey},
            keyless: solKeyless,
            decode: sol.SigningInput.fromBuffer,
          );

      EvmSignResult signSol(
        _TestFamily family,
        Map<KeyRole, PrivateKeyHandle> keys,
      ) => core.sign(
        solKeyless,
        family: family,
        coin: Coin.solana,
        requiredRoles: [KeyRole.primary, KeyRole.feePayer],
        keys: keys,
        usedKeys: const <KeyLocator>{},
      );

      test('two roles into two fields: private_key is the primary key and '
          'fee_payer_private_key the fee payer\'s, and no other key field is '
          'set', () {
        final family = solFamily();
        final keys = {
          KeyRole.primary: handleOf(solanaKey),
          KeyRole.feePayer: handleOf(btcKey0),
        };
        signSol(family, keys);
        final keyed = seam.captured!;
        final decoded = sol.SigningInput.fromBuffer(keyed);
        expect(listEquals(decoded.privateKey, solanaKey), isTrue);
        expect(listEquals(decoded.feePayerPrivateKey, btcKey0), isTrue);
        expect(decoded.recentBlockhash, '11111111111111111111111111111111');
        expect(
          family.keyFields.presentIn(decoded).map((e) => e.fieldName).toSet(),
          {'private_key', 'fee_payer_private_key'},
          reason: 'the nonce account key was not set',
        );
        final h1 = lengthDelimitedHeader(1, 32);
        final h17 = lengthDelimitedHeader(17, 32);
        expect(
          keyed.length,
          h1.length + 32 + h17.length + 32 + solKeyless.length,
        );
        expect(listEquals(keyed.sublist(0, h1.length), h1), isTrue);
        expect(
          listEquals(
            keyed.sublist(h1.length + 32, h1.length + 32 + h17.length),
            h17,
          ),
          isTrue,
        );
        expect(
          listEquals(
            keyed.sublist(h1.length + 32 + h17.length + 32),
            solKeyless,
          ),
          isTrue,
        );
        expect(allocator.allocatedSizes, [keyed.length]);
        expect(_allZero(allocator.heldAtFree.single), isTrue);
      });

      // --- defects of the caller, inside the SDK --------------------------------

      group(
        'a family or caller defect is a StateError, before any key is read',
        () {
          void expectDefect(
            _TestFamily family,
            Map<KeyRole, PrivateKeyHandle> keys,
          ) {
            final disposedBefore = tracker.report.disposed;
            expect(() => signSol(family, keys), throwsStateError);
            expect(seam.calls, 0);
            expect(allocator.allocatedSizes, isEmpty);
            expect(tracker.report.disposed - disposedBefore, 0);
          }

          Map<KeyRole, PrivateKeyHandle> twoKeys() => {
            KeyRole.primary: handleOf(solanaKey),
            KeyRole.feePayer: handleOf(btcKey0),
          };

          test('two roles injected into one singular field', () {
            expectDefect(
              solFamily(
                slots: {KeyRole.primary: _solKey, KeyRole.feePayer: _solKey},
              ),
              twoKeys(),
            );
          });

          test('a role injected into a field of a nested message, not of the '
              'signing input', () {
            expectDefect(
              solFamily(
                slots: {
                  KeyRole.primary: _solKey,
                  KeyRole.feePayer: _solNonceKey,
                },
              ),
              twoKeys(),
            );
          });

          test('a family with no slot for a listed role', () {
            expectDefect(
              solFamily(slots: {KeyRole.primary: _solKey}),
              twoKeys(),
            );
          });

          test(
            'a required role with no key, and a key for no required role',
            () {
              expectDefect(solFamily(), {KeyRole.primary: handleOf(solanaKey)});
              expectDefect(solFamily(), {
                ...twoKeys(),
                KeyRole.input(0): handleOf(btcKey1),
              });
            },
          );
        },
      );

      test('the test families\' key-field lists equal the generated '
          'key_fields.json for their messages', () {
        final generated = jsonDecode(
          File(
            '${repositoryRoot()!.path}/packages/'
            'wallet_core_flutter_bindings/lib/src/generated/proto/'
            'key_fields.json',
          ).readAsStringSync(),
        ) as Map<String, dynamic>;
        final messages = generated['messages'] as Map<String, dynamic>;
        Set<KeyFieldEntry> generatedFor(String message) => {
          for (final field
              in (messages[message] as Map<String, dynamic>)['fields']
                  as List<dynamic>)
            KeyFieldEntry(
              messagePath: message,
              fieldName: (field as Map<String, dynamic>)['protoName'] as String,
              fieldNumber: field['number'] as int,
              repeated: field['repeated'] as bool,
            ),
        };
        expect(generatedFor('TW.Bitcoin.Proto.SigningInput'), {_btcKey});
        expect(generatedFor('TW.Solana.Proto.SigningInput'), {
          _solKey,
          _solFeePayerKey,
        });
        expect(generatedFor('TW.Solana.Proto.CreateNonceAccount'), {
          _solNonceKey,
        });
      });
    },
  );
}

String _hexOf(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
