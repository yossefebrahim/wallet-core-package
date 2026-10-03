/// The one length ceiling every handle in this library validates against.
library;

/// The largest byte length this library will allocate for, or copy out of, a
/// native buffer: 64 MiB.
///
/// Every length that crosses the foreign-function boundary is validated against
/// this **before** anything is allocated or copied (threat model TM-17). Two
/// things make the check necessary:
///
/// * `TWDataSize` and `TWStringSize` return C `size_t`, which ffigen maps to a
///   Dart `int` — signed, 64-bit. A `SIZE_MAX` or any value above 2^63 arrives
///   here as a *negative* number, so negativity is checked as well as range.
/// * A length is upstream's answer, and everything returning from native code
///   is untrusted input to Dart. A corrupt or hostile size that is merely large
///   would otherwise become an allocation of that size.
///
/// 64 MiB is chosen to be far above anything this SDK legitimately moves and
/// far below anything worth allocating on a phone. The largest payload that
/// crosses is one serialized protobuf signing input or output, or one encoded
/// transaction: a Bitcoin transaction is bounded by consensus at 1 MB, a Solana
/// transaction at 1232 bytes, and addresses, mnemonics, keystore documents and
/// hashes are kilobytes at most. The ceiling therefore has roughly sixty times
/// the headroom over the largest real case, and cannot reject real work, while
/// still turning a malformed size into a typed failure rather than an
/// allocation.
///
/// It is a ceiling on a single buffer, not a budget: nothing here counts how
/// many buffers are live at once.
const int maxNativeBufferBytes = 64 * 1024 * 1024;

/// Returns [length] if it is a usable byte length, and throws [RangeError]
/// otherwise.
///
/// [resourceType] and [what] name where the length came from — a Dart type name
/// and an upstream function name, never any content (threat model TM-31).
int checkNativeLength(
  int length, {
  required String resourceType,
  required String what,
}) {
  if (length < 0 || length > maxNativeBufferBytes) {
    throw RangeError.range(
      length,
      0,
      maxNativeBufferBytes,
      'length',
      '$resourceType: $what is out of range',
    );
  }
  return length;
}
