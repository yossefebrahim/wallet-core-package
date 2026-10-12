/// UTXO planning and signing through the public session — `WalletCore.signer`
/// — against the host library: HD wallet, derived accounts, per-input
/// `KeyLocator`s, `signer.plan`, `signer.sign`.
///
/// **The two-input HD test** is the owner's open D2 question: no upstream
/// vector signs Bitcoin from two HD paths of one mnemonic, so none of this
/// file's signed bytes is compared with an expected transaction. It asserts
/// structural facts only: the transaction decodes, has two inputs and two
/// non-empty witnesses, upstream reports no error, the witness public key of
/// each input is the vector's public key of that input's derivation path
/// (`bitcoin-address-n/a-1` and `-2`, copied from upstream, not computed),
/// and the handler derived two keys. What it proves and does not is in the
/// task report: it shows the `KeyLocator` → role → derived-key chain carries
/// two different HD keys into one signing input and that upstream accepts and
/// uses both; it does not show that the signatures are the ones another
/// implementation would make, which only a vector can.
///
/// Skips when the library is absent; `WCF_NATIVE_REQUIRED=1` turns that into a
/// failure (see `../../support/host_library.dart`).
@Tags(['native'])
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core_flutter/advanced.dart'
    show NativeContext, TWDataHandle, runScope;
import 'package:wallet_core_flutter/src/engine/coin_bridge.dart';
import 'package:wallet_core_flutter/src/session/testing.dart';
import 'package:wallet_core_flutter/src/worker/handler.dart';
import 'package:wallet_core_flutter/wallet_core_flutter.dart';

import '../../signing/signing_support.dart';
import '../../support/fixtures.dart';
import '../../support/host_library.dart';
import 'utxo_vector.dart';

/// What a segwit transaction's bytes say, read and not interpreted.
final class _Tx {
  _Tx(this.bytes) {
    var at = 0;
    int u8() => bytes[at++];
    int varint() {
      final first = u8();
      if (first < 0xFD) return first;
      final width = first == 0xFD ? 2 : (first == 0xFE ? 4 : 8);
      var value = 0;
      for (var i = 0; i < width; i++) {
        value |= u8() << (8 * i);
      }
      return value;
    }

    Uint8List take(int n) {
      final out = Uint8List.sublistView(bytes, at, at + n);
      at += n;
      return out;
    }

    version = ByteData.sublistView(take(4)).getInt32(0, Endian.little);
    isSegwit = bytes[at] == 0 && bytes[at + 1] == 1;
    if (isSegwit) at += 2;
    final inputCount = varint();
    for (var i = 0; i < inputCount; i++) {
      inputHashes.add(take(32));
      take(4);
      final scriptLength = varint();
      take(scriptLength);
      take(4);
    }
    outputCount = varint();
    for (var i = 0; i < outputCount; i++) {
      take(8);
      final scriptLength = varint();
      take(scriptLength);
    }
    if (isSegwit) {
      for (var i = 0; i < inputCount; i++) {
        final items = <Uint8List>[];
        final count = varint();
        for (var j = 0; j < count; j++) {
          items.add(take(varint()));
        }
        witnesses.add(items);
      }
    }
    take(4);
    consumedAll = at == bytes.length;
  }

  final Uint8List bytes;
  late final int version;
  late final bool isSegwit;
  final List<Uint8List> inputHashes = [];
  late final int outputCount;
  final List<List<Uint8List>> witnesses = [];
  late final bool consumedAll;
}

void main() {
  final skip = hostLibrarySkipReason();

  group(
    'WalletCore.signer for UTXO requests against the host library',
    skip: skip,
    () {
      late String mnemonic;
      late String path0;
      late String path1;
      late String address0;
      late String address1;
      late String publicKey0;
      late String publicKey1;
      late String recipient;
      late Map<dynamic, dynamic> planInput;
      late Map<dynamic, dynamic> planExpected;

      setUpAll(() {
        final inventory = loadInventory();
        final first = vectorById(inventory, 'bitcoin-address-n/a-1');
        final second = vectorById(inventory, 'bitcoin-address-n/a-2');
        mnemonic = (first.input as Map)['mnemonic'] as String;
        expect((second.input as Map)['mnemonic'], mnemonic);
        path0 = (first.input as Map)['derivation_path'] as String;
        path1 = (second.input as Map)['derivation_path'] as String;
        address0 = (first.expected as Map)['address'] as String;
        address1 = (second.expected as Map)['address'] as String;
        publicKey0 = (first.expected as Map)['public_key'] as String;
        publicKey1 = (second.expected as Map)['public_key'] as String;
        final plan = vectorById(inventory, 'bitcoin-plan-p2wpkh-1');
        planInput = plan.input as Map<dynamic, dynamic>;
        planExpected = plan.expected as Map<dynamic, dynamic>;
        recipient = planInput['to_address'] as String;
      });

      late WalletCore core;
      late NativeContext helper;

      setUp(() async {
        core = await initializeForTesting(
          hostLibraryPath: findHostLibrary(),
          expectedIdentity: hostIdentity,
        );
        helper = NativeContext(openHostBindings());
      });

      tearDown(() async {
        final before = debugLeakReportOf(core)!;
        expect(before.finalizedWithoutDispose, 0, reason: '$before');
        await core.shutdown();
        final after = debugLeakReportOf(core)!;
        expect(after.live, 0, reason: '$after');
        expect(after.finalizedWithoutDispose, 0, reason: '$after');
      });

      int keysDerived() =>
          (debugHandlerOf(core) as EngineRequestHandler).keysDerived;

      /// The locking script upstream builds for [address]
      /// (`TWBitcoinScriptLockScriptForAddress`): fixtures come from upstream,
      /// not from this file.
      Uint8List lockScriptFor(String address) {
        final bindings = helper.bindings;
        return runScope(helper, (scope) {
          final text = scope.string(address);
          final script = bindings.TWBitcoinScriptLockScriptForAddress(
            text.pointer,
            twCoinTypeOf(Coin.bitcoin),
          );
          try {
            final data = scope.use(
              TWDataHandle.adopt(helper, bindings.TWBitcoinScriptData(script)),
            );
            return data.copyBytes();
          } finally {
            bindings.TWBitcoinScriptDelete(script);
          }
        });
      }

      UtxoInput inputAt(
        int n,
        String address,
        KeyLocator locator, {
        int amount = 60000,
        Uint8List? script,
        AddressStyle style = AddressStyle.segwit,
      }) => UtxoInput(
        outPoint: OutPoint(
          transactionId: n.toRadixString(16).padLeft(64, 'a'),
          index: n,
        ),
        amount: amount,
        script: script ?? lockScriptFor(address),
        addressStyle: style,
        keyLocator: locator,
      );

      UtxoTransactionRequest requestOf(
        List<UtxoInput> inputs, {
        String? to,
        String? change,
        int amount = 90000,
      }) => UtxoTransactionRequest(
        coin: Coin.bitcoin,
        toAddress: to ?? recipient,
        amount: amount,
        feeRatePerByte: 2,
        changeAddress: change ?? address0,
        inputs: inputs,
      );

      Matcher inputError(String name) => throwsA(
        isA<InvalidInputError>().having((e) => e.inputName, 'inputName', name),
      );

      Matcher resolution(KeyResolutionReason reason) => throwsA(
        isA<KeyResolutionError>().having((e) => e.reason, 'reason', reason),
      );

      group('two HD paths of one mnemonic', () {
        late Wallet wallet;
        late KeyLocator locator0;
        late KeyLocator locator1;

        setUp(() async {
          wallet = await core.wallets.importMnemonic(mnemonic);
          // The two public-surface address vectors.
          final account0 = await wallet.account(Coin.bitcoin, path: path0);
          final account1 = await wallet.account(Coin.bitcoin, path: path1);
          expect(account0.address.value, address0);
          expect(account1.address.value, address1);
          expect(hexOf(account0.publicKey), publicKey0);
          expect(hexOf(account1.publicKey), publicKey1);
          locator0 = KeyLocator.hdPath(wallet.ref, Coin.bitcoin, path0);
          locator1 = KeyLocator.hdPath(wallet.ref, Coin.bitcoin, path1);
        });

        tearDown(() => wallet.close());

        test('plan: key-less, selects both inputs, and is the request\'s own '
            'inputs', () async {
          final request = requestOf([
            inputAt(0, address0, locator0),
            inputAt(1, address1, locator1, amount: 70000),
          ]);
          final plan = await core.signer.plan(request);
          expect(plan.selectedInputs, hasLength(2));
          for (final selected in plan.selectedInputs) {
            expect(request.inputs, contains(selected));
          }
          expect(plan.amount, 90000);
          expect(plan.availableAmount, 130000);
          expect(plan.fee, greaterThan(0));
          expect(plan.change, plan.availableAmount - plan.amount - plan.fee);
          expect(keysDerived(), 0, reason: 'planning derives no key');
        });

        test('sign: two inputs from two paths — structural facts only', () async {
          final request = requestOf([
            inputAt(0, address0, locator0),
            inputAt(1, address1, locator1, amount: 70000),
          ]);
          expect(request.keyLocators, hasLength(2));
          final result = await core.signer.sign(
            request,
            request.keyLocators,
          ) as UtxoSignResult;

          expect(keysDerived(), 2, reason: 'one key per distinct path');
          expect(result.usedKeys, request.keyLocators);
          expect(result.coin, Coin.bitcoin);
          expect(result.transactionId, matches(RegExp(r'^[0-9a-f]{64}$')));

          // Upstream reported no error (it would have thrown SigningError) and
          // the bytes decode as a segwit transaction with two inputs and two
          // non-empty witnesses, each of a signature and a public key.
          final tx = _Tx(result.encoded);
          expect(tx.isSegwit, isTrue);
          expect(tx.consumedAll, isTrue);
          expect(tx.version, 1);
          expect(tx.inputHashes, hasLength(2));
          expect(tx.outputCount, inInclusiveRange(1, 2));
          expect(tx.witnesses, hasLength(2));
          for (final witness in tx.witnesses) {
            expect(witness, hasLength(2));
            expect(witness[0].length, inInclusiveRange(70, 73));
            expect(witness[1], hasLength(33));
          }
          // Each input was signed with the key of its own path: the witness
          // public key is the vector's public key for that path. (The inputs
          // are in the order the plan selected them, upstream's.)
          final plan = await core.signer.plan(request);
          final witnessKeys = tx.witnesses.map((w) => hexOf(w[1])).toList();
          final expectedKeys = plan.selectedInputs
              .map((i) => i.keyLocator == locator0 ? publicKey0 : publicKey1)
              .toList();
          expect(witnessKeys, expectedKeys);
          expect(witnessKeys.toSet(), {publicKey0, publicKey1});
        });

        test(
          'sign the plan: same inputs, same keys, structural facts',
          () async {
            final request = requestOf([
              inputAt(0, address0, locator0),
              inputAt(1, address1, locator1, amount: 70000),
            ]);
            final planned = request.withPlan(await core.signer.plan(request));
            final result = await core.signer.sign(
              planned,
              planned.keyLocators,
            ) as UtxoSignResult;
            final tx = _Tx(result.encoded);
            expect(tx.witnesses, hasLength(2));
            expect(tx.witnesses.map((w) => hexOf(w[1])).toSet(), {
              publicKey0,
              publicKey1,
            });
          },
        );

        test('two inputs on one path are one derived key', () async {
          final request = requestOf([
            inputAt(0, address0, locator0),
            inputAt(1, address0, locator0, amount: 70000),
          ]);
          expect(request.keyLocators, hasLength(1));
          final before = keysDerived();
          final result = await core.signer.signWithKey(
            request,
            locator0,
          ) as UtxoSignResult;
          expect(keysDerived() - before, 1);
          final tx = _Tx(result.encoded);
          expect(tx.witnesses, hasLength(2));
          expect(tx.witnesses.every((w) => hexOf(w[1]) == publicKey0), isTrue);
        });

        test(
          'keys that do not match the inputs fail before any key is derived',
          () async {
            final request = requestOf([
              inputAt(0, address0, locator0),
              inputAt(1, address1, locator1, amount: 70000),
            ]);
            final stamped = request.keyLocators.toList();
            // Nothing, or one of two: a role has no locator.
            await expectLater(
              core.signer.sign(request, const <KeyLocator>{}),
              resolution(KeyResolutionReason.missingRole),
            );
            await expectLater(
              core.signer.sign(request, {stamped.first}),
              resolution(KeyResolutionReason.missingRole),
            );
            // The request's own locators without their roles: with two keys a
            // role-less locator fills nothing.
            await expectLater(
              core.signer.sign(request, {locator0, locator1}),
              resolution(KeyResolutionReason.unusedLocator),
            );
            // One locator too many.
            final third = KeyLocator.hdPath(
              wallet.ref,
              Coin.bitcoin,
              "m/84'/0'/0'/0/5",
              role: KeyRole.input(2),
            );
            await expectLater(
              core.signer.sign(request, {...stamped, third}),
              resolution(KeyResolutionReason.unusedLocator),
            );
            expect(keysDerived(), 0);
          },
        );
      });

      group('what is refused before any key exists', () {
        late Wallet wallet;
        late KeyLocator locator;

        setUp(() async {
          wallet = await core.wallets.importMnemonic(mnemonic);
          locator = KeyLocator.hdPath(wallet.ref, Coin.bitcoin, path0);
        });

        tearDown(() => wallet.close());

        test('a recipient or change address upstream rejects', () async {
          final input = inputAt(0, address0, locator);
          for (final bad in [
            '1Bp9U1ogV3A14FMvKbRJms7ctyso4Z4Tcy', // a valid address, last digit changed
            'bc1qinvalid', // not an address
            'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx', // testnet
            'a' * 40,
          ]) {
            await expectLater(
              core.signer.plan(requestOf([input], to: bad)),
              inputError('toAddress'),
              reason: bad,
            );
            await expectLater(
              core.signer.sign(
                requestOf([input], to: bad),
                requestOf([input]).keyLocators,
              ),
              inputError('toAddress'),
              reason: bad,
            );
            await expectLater(
              core.signer.plan(requestOf([input], change: bad)),
              inputError('changeAddress'),
              reason: bad,
            );
          }
          expect(keysDerived(), 0);
        });

        test('a script type this SDK does not sign is unsupported, by name', () async {
          final bindings = helper.bindings;
          Uint8List uncompressedP2pk() => runScope(helper, (scope) {
            final key = scope.data(
              Uint8List.fromList([4, ...List.filled(64, 1)]),
            );
            final script = bindings.TWBitcoinScriptBuildPayToPublicKey(
              key.pointer,
            );
            try {
              return scope
                  .use(
                    TWDataHandle.adopt(
                      helper,
                      bindings.TWBitcoinScriptData(script),
                    ),
                  )
                  .copyBytes();
            } finally {
              bindings.TWBitcoinScriptDelete(script);
            }
          });

          final cases = <String, Uint8List>{
            'script:p2pkh': lockScriptFor('1Bp9U1ogV3A14FMvKbRJms7ctyso4Z4Tcx'),
            'script:p2sh': lockScriptFor('3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy'),
            'script:p2wsh': lockScriptFor(
              'bc1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3qccfmv3',
            ),
            'script:witness-program': lockScriptFor(
              'bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0',
            ),
            'script:p2pk-uncompressed': uncompressedP2pk(),
            'script:other': Uint8List.fromList([0x51]), // OP_1
          };
          for (final entry in cases.entries) {
            final request = requestOf([
              inputAt(0, address0, locator, script: entry.value),
            ]);
            await expectLater(
              core.signer.plan(request),
              throwsA(
                isA<UnsupportedOperationError>().having(
                  (e) => e.capability,
                  'capability',
                  entry.key,
                ),
              ),
              reason: entry.key,
            );
            await expectLater(
              core.signer.signWithKey(request, locator),
              throwsA(isA<UnsupportedOperationError>()),
              reason: entry.key,
            );
          }
          expect(keysDerived(), 0);
        });

        test(
          'an address style that cannot own the script is an InvalidInputError',
          () async {
            final request = requestOf([
              inputAt(0, address0, locator, style: AddressStyle.legacy),
            ]);
            await expectLater(core.signer.plan(request), inputError('inputs'));
            await expectLater(
              core.signer.signWithKey(request, locator),
              inputError('inputs'),
            );
            expect(keysDerived(), 0);
          },
        );

        test('a wallet closed before the sign is ClosedError, and derives '
            'nothing', () async {
          final request = requestOf([inputAt(0, address0, locator)]);
          await wallet.close();
          await expectLater(
            core.signer.signWithKey(request, locator),
            throwsA(isA<ClosedError>()),
          );
          expect(keysDerived(), 0);
        });
      });

      group('the plan of the vector, through the session', () {
        test('bitcoin-plan-p2wpkh-1 equals the vector — key-less, so with no '
            'wallet at all', () async {
          final vector = VectorRequest.of(planInput);
          final plan = await core.signer.plan(vector.request);
          expect(
            plan.selectedInputs.map((i) => i.amount.toString()).toList(),
            (planExpected['selected_utxo_amounts'] as List<dynamic>)
                .cast<String>(),
          );
          expect(plan.amount.toString(), planExpected['amount']);
          expect(plan.fee.toString(), planExpected['fee']);
          expect(
            plan.availableAmount.toString(),
            planExpected['available_amount'],
          );
          expect(plan.change.toString(), planExpected['change']);
          expect(keysDerived(), 0);
          expect(
            listEquals(plan.selectedInputs.map((i) => i.amount).toList(), [
              4863,
              30269,
            ]),
            isTrue,
          );
        });
      });

      test('20 plans and 20 signs in a loop leave zero undisposed', () async {
        final wallet = await core.wallets.importMnemonic(mnemonic);
        final locator = KeyLocator.hdPath(wallet.ref, Coin.bitcoin, path0);
        for (var i = 0; i < 20; i++) {
          final request = requestOf([inputAt(i, address0, locator)]);
          await core.signer.plan(request);
          await core.signer.signWithKey(request, locator);
          final report = debugLeakReportOf(core)!;
          expect(report.live, 1, reason: 'the wallet only: $report');
        }
        expect(keysDerived(), 20);
        await wallet.close();
        final report = debugLeakReportOf(core)!;
        expect(report.live, 0, reason: '$report');
      });
    },
  );
}
