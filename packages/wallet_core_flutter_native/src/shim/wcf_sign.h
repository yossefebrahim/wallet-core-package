/* wcf_sign.h — the Approach B signing adapter of DECISION-1 (T1.13 prototype).
 *
 * Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
 * Not affiliated with or endorsed by Trust Wallet.
 *
 * EVALUATION ONLY. This adapter is compiled into a host library only when
 * tools/native_build/build_apple.sh is given --with-shim, which writes to a
 * path of its own. No published artifact contains it; whether one ever does is
 * DECISION-1's question, and this file is evidence for it, not its answer.
 *
 * WHAT IT IS FOR. Under Approach A the SDK's Dart code copies the private key
 * into the serialized signing input, in native memory the Dart side allocates.
 * Here the Dart side hands over the key-less input and a handle to upstream's
 * TWPrivateKey object, and the adapter does the injection: no buffer the Dart
 * side allocates ever holds the key, and no Dart code reads the key's bytes.
 *
 * WHAT IT IS NOT. It implements no signing, no key derivation and no
 * serialization of a signed transaction (AGENTS.md rule 2). It prepends one
 * length-delimited protobuf field to bytes it is given and calls upstream's
 * TWAnySignerSign.
 */

#ifndef WCF_SIGN_H
#define WCF_SIGN_H

#include <TrustWalletCore/TWCoinType.h>
#include <TrustWalletCore/TWData.h>
#include <TrustWalletCore/TWPrivateKey.h>

/* The same export annotation as wcf_build_info.h, for the same reason: the
 * build compiles this file with -fvisibility=hidden, so this attribute — and
 * only this attribute — exports the entry point, and check_exports.sh
 * --require-symbol proves it did. */
#if defined(_WIN32)
#  define WCF_SIGN_EXPORT __declspec(dllexport)
#else
#  define WCF_SIGN_EXPORT __attribute__((visibility("default")))
#endif

/* The field number of TW.Ethereum.Proto.SigningInput.private_key
 * (`bytes private_key = 9;` in Ethereum.proto at upstream commit
 * d692ac27749d0c615e17c751b70ab4f0aa75c59b, tag 4.8.0).
 *
 * Not generated. packages/wallet_core_flutter/test/signing/adapter/
 * field_number_test.dart reads this line and fails unless the number equals
 * the one in the generated
 * packages/wallet_core_flutter_bindings/lib/src/generated/proto/key_fields.json,
 * and the Dart side refuses to call the adapter unless the EVM family's
 * reviewed injection field carries the same number. */
#define WCF_ETHEREUM_SIGNING_INPUT_PRIVATE_KEY_FIELD 9

/* The longest key the adapter accepts. A secp256k1 key is 32 bytes; the bound
 * only keeps the length prefix to two bytes and rejects a corrupt size. */
#define WCF_SIGN_MAX_KEY_LENGTH 256u

/* The longest key-less input the adapter accepts: protobuf's own 2 GiB limit,
 * less room for the prepended field, so the keyed input never exceeds it and no
 * length arithmetic below can overflow. */
#define WCF_SIGN_MAX_INPUT_LENGTH (0x7FFFFFFFu - 1024u)

#ifdef __cplusplus
extern "C" {
#endif

/* Signs the key-less EVM signing input `keyless_input` with `key` for `coin`.
 *
 * PRECONDITION — the caller's, and not checked here: `keyless_input` is ONE
 * COMPLETE, WELL-FORMED serialized TW.Ethereum.Proto.SigningInput with its
 * private_key field absent. Well-formedness is the property that matters:
 * bytes that end inside a length-delimited field give whatever follows them a
 * meaning nobody chose. The Dart caller establishes it by decoding the bytes
 * (checkKeylessInput) before every call; any new caller must do the same.
 * See DECISION-1-approach-b.md §3 for what checking it natively would take.
 *
 * The key field is PREPENDED: the keyed input is the field's tag and length,
 * the key, then the key-less bytes. A complete field followed by a complete
 * message is that message with the field set. Prepended, the key is always a
 * field of its own even if the precondition is broken: it can never become
 * the payload of a field the key-less bytes left open (appended, after bytes
 * truncated inside a `data` field, it would be signed into the transaction as
 * calldata). A private_key already present in the key-less bytes would come
 * later and win — which is why the precondition still requires it absent.
 *
 * In this order: reads the key's bytes with TWPrivateKeyData; creates one
 * upstream TWData of the exact keyed size and writes into it, in that order,
 * the field's tag and length, the key, and the key-less bytes; deletes the
 * key's TWData (TWDataDelete overwrites it before freeing); calls
 * TWAnySignerSign; deletes the keyed TWData (overwritten likewise);
 * overwrites the adapter's own stack buffer; returns upstream's output.
 *
 * Returns the serialized TW.Ethereum.Proto.SigningOutput as a new TWData the
 * caller owns and releases with TWDataDelete, or NULL — never anything
 * partial — when:
 *   - `keyless_input` or `key` is NULL;
 *   - `coin` is not a coin whose upstream blockchain is TWBlockchainEthereum
 *     (the key must never be written as field 9 of some other schema);
 *   - the input is longer than WCF_SIGN_MAX_INPUT_LENGTH, or the key is empty
 *     or longer than WCF_SIGN_MAX_KEY_LENGTH;
 *   - an upstream call returns NULL or a buffer of the wrong size.
 * An upstream signing failure is NOT NULL: it is an output carrying upstream's
 * error code, exactly as TWAnySignerSign returns it.
 *
 * Neither argument is retained or modified, and `key` is not deleted: the
 * caller owns it. Nothing is logged.
 */
WCF_SIGN_EXPORT TWData *_Nullable wcf_sign_ethereum(
    TWData *_Nullable keyless_input,
    struct TWPrivateKey *_Nullable key,
    enum TWCoinType coin);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* WCF_SIGN_H */
