/* wcf_sign.c — the Approach B signing adapter of DECISION-1 (T1.13 prototype).
 *
 * Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
 * Not affiliated with or endorsed by Trust Wallet.
 *
 * Plain C11 against upstream's public headers only. See wcf_sign.h for the
 * contract; this file adds the reasons for how it is met.
 *
 * NO BUFFER OF OUR OWN HOLDS THE KEY. The keyed input is assembled directly in
 * a TWData created by upstream at its final size (TWDataCreateWithSize), so
 * the only copies of the key this function causes are two upstream TWData
 * objects — the one TWPrivateKeyData returns and the keyed input — and both
 * are released with TWDataDelete, which at the pinned commit overwrites the
 * bytes before freeing them (src/interface/TWData.cpp, memzero). A malloc'd
 * staging buffer, as Approach A's Dart side uses, was the alternative; it
 * would be one more copy for this file to overwrite, and a fixed-size create
 * means no vector growth can leave an unwiped copy behind either.
 *
 * The one array this function owns, `header`, holds the field's tag and the
 * key's length, not key bytes; it is overwritten on every exit anyway, so that
 * "every byte buffer the adapter owns is overwritten" holds without a
 * qualification.
 *
 * NOT REACHABLE FROM HERE: copies upstream makes while signing (its protobuf
 * parse of the input, its PrivateKey, its Rust signer's buffers), and whatever
 * memcpy leaves in registers or on the stack. Those are the same under
 * Approach A.
 */

#include "wcf_sign.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include <TrustWalletCore/TWAnySigner.h>
#include <TrustWalletCore/TWBlockchain.h>

#if WCF_ETHEREUM_SIGNING_INPUT_PRIVATE_KEY_FIELD < 1 || \
    WCF_ETHEREUM_SIGNING_INPUT_PRIVATE_KEY_FIELD > 0x1FFFFFFF
#  error "WCF_ETHEREUM_SIGNING_INPUT_PRIVATE_KEY_FIELD is not a protobuf field number"
#endif

/* Protobuf wire type 2: length-delimited. */
#define WCF_WIRE_TYPE_LENGTH_DELIMITED 2u

/* A varint of a 32-bit tag is at most 5 bytes, of a length at most 10. */
#define WCF_HEADER_CAPACITY 16u

/* Overwrites `length` bytes at `buffer` with zeros through a volatile pointer,
 * so the stores are not removed as dead. memset_s would do the same on Apple
 * platforms; Android's bionic has no memset_s, and this file is meant to build
 * unchanged for both. */
static void wcf_overwrite(void *buffer, size_t length) {
  volatile unsigned char *bytes = (volatile unsigned char *)buffer;
  while (length > 0) {
    *bytes = 0;
    bytes++;
    length--;
  }
}

/* Writes `value` as a protobuf varint at `out` and returns how many bytes it
 * took. The caller guarantees room for 10. */
static size_t wcf_put_varint(uint8_t *out, uint64_t value) {
  size_t written = 0;
  while (value >= 0x80u) {
    out[written] = (uint8_t)((value & 0x7Fu) | 0x80u);
    written++;
    value >>= 7;
  }
  out[written] = (uint8_t)value;
  return written + 1;
}

TWData *wcf_sign_ethereum(TWData *keyless_input, struct TWPrivateKey *key,
                          enum TWCoinType coin) {
  uint8_t header[WCF_HEADER_CAPACITY];
  size_t header_length = 0;
  size_t input_length = 0;
  const uint8_t *input_bytes = NULL;
  TWData *key_data = NULL;
  size_t key_length = 0;
  const uint8_t *key_bytes = NULL;
  TWData *keyed = NULL;
  size_t keyed_length = 0;
  uint8_t *keyed_bytes = NULL;
  TWData *output = NULL;

  memset(header, 0, sizeof header);

  if (keyless_input == NULL || key == NULL) goto done;
  /* The Dart side checks the coin's family too. The adapter does not rely on
   * it: in another coin's schema, field 9 is some other field, and
   * the key could land where upstream echoes it. */
  if (TWCoinTypeBlockchain(coin) != TWBlockchainEthereum) goto done;

  input_length = TWDataSize(keyless_input);
  if (input_length > WCF_SIGN_MAX_INPUT_LENGTH) goto done;
  if (input_length > 0) {
    input_bytes = TWDataBytes(keyless_input);
    if (input_bytes == NULL) goto done;
  }

  key_data = TWPrivateKeyData(key);
  if (key_data == NULL) goto done;
  key_length = TWDataSize(key_data);
  if (key_length == 0 || key_length > WCF_SIGN_MAX_KEY_LENGTH) goto done;
  key_bytes = TWDataBytes(key_data);
  if (key_bytes == NULL) goto done;

  header_length = wcf_put_varint(
      header, ((uint64_t)WCF_ETHEREUM_SIGNING_INPUT_PRIVATE_KEY_FIELD << 3) |
                  WCF_WIRE_TYPE_LENGTH_DELIMITED);
  header_length += wcf_put_varint(header + header_length, (uint64_t)key_length);

  /* Bounded above: input <= 2 GiB - 1024, header <= 16, key <= 256. */
  keyed_length = input_length + header_length + key_length;
  keyed = TWDataCreateWithSize(keyed_length);
  if (keyed == NULL || TWDataSize(keyed) != keyed_length) goto done;
  keyed_bytes = TWDataBytes(keyed);
  if (keyed_bytes == NULL) goto done;

  /* THE LAYOUT, decided here and nowhere else in C: tag and length, key,
   * key-less bytes — the key field PREPENDED (wcf_sign.h says why). The Dart
   * side's one place is keyedInputParts in signing_core.dart, and
   * keyed_layout_native_test.dart holds the two to the same layout. */
  memcpy(keyed_bytes, header, header_length);
  memcpy(keyed_bytes + header_length, key_bytes, key_length);
  if (input_length > 0) {
    memcpy(keyed_bytes + header_length + key_length, input_bytes,
           input_length);
  }

  /* The key's own TWData is no longer needed: release it before signing so the
   * copy count during the upstream call is one, not two. */
  TWDataDelete(key_data);
  key_data = NULL;
  key_bytes = NULL;

  output = TWAnySignerSign(keyed, coin);

done:
  if (key_data != NULL) TWDataDelete(key_data);
  if (keyed != NULL) TWDataDelete(keyed);
  wcf_overwrite(header, sizeof header);
  return output;
}
