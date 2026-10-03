/// The request and reply types of the session protocol
/// (`docs/architecture/lifecycle.md` §6, DECISION-12 §3.2). **Internal**:
/// never exported from either public library.
///
/// The M0 subset, with transaction signing ([Sign], [Signed]). `SignMessage`,
/// `Plan`, `ImportKey` and their replies (`MessageSigned`, `Planned`,
/// `KeyImported`) join these families later (T2.7, T2.5, T3.4); both families
/// are `sealed`, so adding one is a compile error at every `switch` that must
/// handle it — the handler and the session — which is the point.
///
/// Every type here is a plain immutable value: no native pointer, no handle,
/// nothing that cannot cross an isolate boundary by copy. The values they hold
/// — `int`s, `String`s, [Coin], [Network], [AddressStyle], [Account],
/// [TransactionRequest]s, [SignResult]s, [LocatorSpec]s, typed
/// [WalletCoreException]s — are themselves plain values that compare by
/// content, so a copy that crossed an isolate equals the original.
///
/// That is why [Sign] carries [LocatorSpec]s and not the caller's
/// [KeyLocator]s: a locator's `WalletRef` holds its session and its `Wallet`
/// proxy, which cannot cross an isolate, so the session sends the names a
/// locator carries — the issuing session's token, the wallet reference's
/// number, the coin, the path, the role — exactly as [DeriveAddress] carries a
/// wallet reference's number rather than the `WalletRef`.
///
/// **Request ids** are allocated by the session, start at 1, increase by one
/// per request, and are never reused within a session. Every request receives
/// exactly one reply carrying its id, with two exceptions DECISION-12 §3.2
/// names: a [DisposeRef] posted by a proxy's finalizer and a [Cancel] posted
/// on a deadline are answered, but nobody awaits the answer.
///
/// **Secret-bearing payloads.** DECISION-12 §3.2 (amended 2026-10-03) closes
/// the set at eight. Requests: [CreateWallet] (a passphrase), [ImportWallet]
/// (a mnemonic or entropy, and a passphrase), `ImportKey` (planned, T3.4; not
/// declared here), [ValidateMnemonic] (a whole candidate mnemonic),
/// [ValidateMnemonicWord] (one word), [SuggestMnemonicWords] (a word prefix).
/// Replies: [MnemonicExported] (the mnemonic) and [MnemonicWordsSuggested]
/// (words sharing the caller's prefix). A ninth reopens that record
/// (DECISION-12 §8 trigger 6). Every secret-bearing type's `toString()` names
/// the fields it carries and never their values, and no type here puts a
/// secret into an error.
library;

import 'dart:developer' show Timeline;
import 'dart:typed_data';

import 'package:wallet_core_flutter_native/wallet_core_flutter_native.dart'
    show ManifestIdentity;

import '../account/account.dart';
import '../coin/coin.dart';
import '../coin/network.dart';
import '../errors/errors.dart';
import '../requests/requests.dart';
import '../signing/key_locator.dart';
import '../signing/sign_result.dart';

/// What `toString()` prints in place of a secret.
const String redacted = '<redacted>';

/// Microseconds on the process's monotonic clock — the clock `Timeline` uses,
/// which every isolate of the process reads alike, so a deadline taken in the
/// session's isolate means the same instant in the executor's.
int monotonicMicros() => Timeline.now;

/// When an operation's deadline passes (DECISION-12 §3.5): its [timeout], and
/// the instant [atMicros] on [monotonicMicros]'s clock, measured from
/// submission.
///
/// Sent beside each operation (`WorkerTransport.send`) so that the executor
/// can drop a result nobody will receive *before* posting it — DECISION-12
/// §3.9: "dropped without being posted, not posted and ignored" — instead of
/// relying on the session to throw it away after it crossed. A plain value.
final class OperationDeadline {
  /// A deadline [atMicros] on the shared clock, for an operation given
  /// [timeout].
  const OperationDeadline(this.timeout, this.atMicros);

  /// A deadline [timeout] from now.
  ///
  /// **Saturating**: a [timeout] too long to add to the clock without
  /// overflowing 64 bits — `Duration(microseconds: 0x7FFFFFFFFFFFFFFF)` given
  /// as "never time out" — gives [neverMicros], a deadline that never passes,
  /// rather than a wrapped negative instant that has always passed.
  factory OperationDeadline.after(Duration timeout) {
    final now = monotonicMicros();
    final micros = timeout.inMicroseconds;
    return OperationDeadline(
      timeout,
      micros > neverMicros - now ? neverMicros : now + micros,
    );
  }

  /// The largest instant the clock can name: a deadline at it never passes.
  static const int neverMicros = 0x7FFFFFFFFFFFFFFF;

  /// The operation's timeout, as [OperationTimeoutError.timeout] reports it.
  final Duration timeout;

  /// The instant it expires, in [monotonicMicros]; at most [neverMicros].
  final int atMicros;

  /// Whether the deadline has passed.
  bool get hasPassed => monotonicMicros() > atMicros;

  @override
  String toString() =>
      'OperationDeadline(${timeout.inMilliseconds} ms, at $atMicros µs)';
}

// --- requests ---------------------------------------------------------------

/// A message from the session to the executor that owns the native handles.
sealed class WorkerRequest {
  const WorkerRequest(this.id);

  /// Monotonic within a session, never reused. The reply carries the same id.
  final int id;

  /// The operation's name, as [SessionStateError.attempted] and
  /// [OperationTimeoutError.operation] report it.
  String get operation;

  /// Whether this is a control message — [DisposeRef], [Cancel], [Shutdown] —
  /// which is never rejected for a full queue and has no deadline
  /// (DECISION-12 §3.4, §3.5).
  bool get isControl => false;
}

/// Loads the native library in the owning isolate and checks it, in this
/// order: load, build identity (DECISION-14 §2.3 comparisons 3 and 4), the
/// shipped manifest's hash when [manifestBytes] is supplied (comparison 2),
/// and a symbol-lookup health check. Reply: [InitOk] or [Failed].
///
/// Sent once, before the session is `ready`. The isolate transport of T2.1
/// adds the reply port its worker answers on; that port belongs to the
/// transport, not to this value, which stays sendable as it is.
final class Init extends WorkerRequest {
  /// Creates the `Init` message.
  Init(
    super.id, {
    required this.queueLimit,
    this.expectedIdentity = ManifestIdentity.embedded,
    Uint8List? manifestBytes,
    this.hostLibraryPath,
    this.sessionToken = 0,
  }) : manifestBytes = manifestBytes == null
           ? null
           : Uint8List.fromList(manifestBytes).asUnmodifiableView();

  /// The session's operation bound, from which the executor sizes its
  /// reserved control capacity (DECISION-12 §3.4 rule 3).
  final int queueLimit;

  /// The token of the session this executor serves, which every
  /// [HdLocatorSpec] it accepts must carry (`KeyResolutionReason.foreignRef`
  /// otherwise). Sessions number themselves from 1; the default 0 names no
  /// session, so an executor initialized without one accepts no locator.
  final int sessionToken;

  /// The manifest snapshot comparisons 3 and 4 check the loaded library's
  /// identity against. [ManifestIdentity.embedded] unless a test injects one.
  final ManifestIdentity expectedIdentity;

  /// The bytes of the shipped manifest copy, for comparison 2, or `null` when
  /// the caller has none to supply — then comparison 2 does not run.
  final Uint8List? manifestBytes;

  /// A library file to try first on a development host. `null` from the
  /// public `WalletCore.initialize()`, which takes no path (threat model
  /// TM-13); only the internal test entry point sets it.
  final String? hostLibraryPath;

  @override
  String get operation => 'initialize';

  @override
  String toString() =>
      'Init(#$id, queueLimit: $queueLimit, $expectedIdentity, '
      'manifestBytes: ${manifestBytes?.length}, '
      'hostLibraryPath: $hostLibraryPath, session: $sessionToken)';
}

/// Creates a wallet with a new random mnemonic. Reply: [WalletCreated], which
/// carries a reference and no mnemonic.
///
/// **Carries a secret**: [passphrase] selects the seed (DECISION-12 §3.2).
final class CreateWallet extends WorkerRequest {
  /// Creates the request.
  const CreateWallet(super.id, {required this.strength, this.passphrase = ''});

  /// The mnemonic strength in bits.
  final int strength;

  /// The BIP-39 passphrase. Key material.
  final String passphrase;

  @override
  String get operation => 'createWallet';

  @override
  String toString() =>
      'CreateWallet(#$id, strength: $strength, passphrase: $redacted)';
}

/// Imports a wallet from a mnemonic **or** entropy. Reply: [WalletCreated].
///
/// **Carries a secret** (DECISION-12 §3.2). [entropy] is a copy this request
/// owns — taken when the request is made, so a caller mutating its own list
/// afterwards cannot change which wallet is imported — and the executor
/// overwrites it with zeros once the request has been handled.
final class ImportWallet extends WorkerRequest {
  /// Imports from [mnemonic].
  const ImportWallet.mnemonic(
    super.id,
    String this.mnemonic, {
    this.passphrase = '',
  }) : entropy = null;

  /// Imports from a private copy of [entropy].
  ImportWallet.entropy(super.id, Uint8List entropy, {this.passphrase = ''})
    : mnemonic = null,
      entropy = Uint8List.fromList(entropy);

  /// The mnemonic, when importing from one. Key material.
  final String? mnemonic;

  /// The entropy, when importing from it. Key material, owned by this request.
  final Uint8List? entropy;

  /// The BIP-39 passphrase. Key material.
  final String passphrase;

  @override
  String get operation => mnemonic != null ? 'importMnemonic' : 'importEntropy';

  @override
  String toString() =>
      'ImportWallet(#$id, ${mnemonic != null ? 'mnemonic' : 'entropy'}: '
      '$redacted, passphrase: $redacted)';
}

/// Asks for a wallet's mnemonic. Key-less itself; its reply,
/// [MnemonicExported], is one of the two replies that carry key material,
/// with [MnemonicWordsSuggested].
final class ExportMnemonic extends WorkerRequest {
  /// Creates the request for the wallet [walletRef].
  const ExportMnemonic(super.id, {required this.walletRef});

  /// The executor-issued id of the wallet.
  final int walletRef;

  @override
  String get operation => 'exportMnemonic';

  @override
  String toString() => 'ExportMnemonic(#$id, wallet: $walletRef)';
}

/// Derives an account descriptor. Reply: [AddressDerived].
final class DeriveAddress extends WorkerRequest {
  /// Creates the request.
  const DeriveAddress(
    super.id, {
    required this.walletRef,
    required this.coin,
    required this.network,
    required this.style,
    this.path,
  });

  /// The executor-issued id of the wallet.
  final int walletRef;

  /// The coin to derive for.
  final Coin coin;

  /// The network to derive for.
  final Network network;

  /// The address style to derive.
  final AddressStyle style;

  /// An explicit BIP-32 path, or `null` for the registry default. A path is
  /// not a secret.
  final String? path;

  @override
  String get operation => 'account';

  @override
  String toString() =>
      'DeriveAddress(#$id, wallet: $walletRef, ${coin.id}, ${network.id}, '
      '${style.id}, path: $path)';
}

/// Validates an address in the owning isolate (DECISION-12 §1). Reply:
/// [AddressValidated].
final class ValidateAddress extends WorkerRequest {
  /// Creates the request.
  const ValidateAddress(
    super.id, {
    required this.value,
    required this.coin,
    required this.network,
  });

  /// The address text. Public data.
  final String value;

  /// The coin to validate for.
  final Coin coin;

  /// The network to validate for.
  final Network network;

  @override
  String get operation => 'addresses.isValid';

  @override
  String toString() =>
      'ValidateAddress(#$id, ${coin.id}, ${network.id}, '
      '${value.length} characters)';
}

/// Asks upstream whether a text is a valid BIP-39 English mnemonic. Reply:
/// [MnemonicValidated].
///
/// **Carries a secret**: the candidate is very likely somebody's real
/// mnemonic. See this library's doc comment.
final class ValidateMnemonic extends WorkerRequest {
  /// Creates the request.
  const ValidateMnemonic(super.id, this.mnemonic);

  /// The candidate mnemonic. Key material.
  final String mnemonic;

  @override
  String get operation => 'mnemonics.isValid';

  @override
  String toString() => 'ValidateMnemonic(#$id, mnemonic: $redacted)';
}

/// Asks upstream whether one word is in the BIP-39 English list. Reply:
/// [MnemonicWordValidated].
///
/// **Carries part of a secret**: a word of a mnemonic being typed.
final class ValidateMnemonicWord extends WorkerRequest {
  /// Creates the request.
  const ValidateMnemonicWord(super.id, this.word);

  /// The word. Part of key material.
  final String word;

  @override
  String get operation => 'mnemonics.isValidWord';

  @override
  String toString() => 'ValidateMnemonicWord(#$id, word: $redacted)';
}

/// Asks upstream for the BIP-39 English words starting with a prefix. Reply:
/// [MnemonicWordsSuggested].
///
/// **Carries part of a secret**: the beginning of a word being typed.
final class SuggestMnemonicWords extends WorkerRequest {
  /// Creates the request.
  const SuggestMnemonicWords(super.id, this.prefix);

  /// The prefix. Part of key material.
  final String prefix;

  @override
  String get operation => 'mnemonics.suggest';

  @override
  String toString() => 'SuggestMnemonicWords(#$id, prefix: $redacted)';
}

/// Signs a transaction with the keys [keys] name. Reply: [Signed].
///
/// **Key-less**, like the request it carries (AGENTS.md rule 6): [request]
/// says what to sign and [keys] says with what, by name. The key itself
/// exists only inside the executor, for the duration of the one operation
/// that derives it, and never crosses the protocol in either direction.
///
/// An operation like any other: counted against the queue bound and given the
/// `signing` deadline (DECISION-12 §3.4, §3.5).
final class Sign extends WorkerRequest {
  /// Creates the request; [keys] is copied into an unmodifiable set.
  Sign(super.id, {required this.request, required Set<LocatorSpec> keys})
    : keys = Set<LocatorSpec>.unmodifiable(keys);

  /// What to sign. Validated when it was constructed.
  final TransactionRequest request;

  /// The names of the keys to sign with. The executor resolves them itself
  /// and does not rely on any check the session made first.
  final Set<LocatorSpec> keys;

  @override
  String get operation => 'sign';

  /// The request and every locator's names. Nothing here is a secret.
  @override
  String toString() => 'Sign(#$id, $request, keys: ${keys.join(', ')})';
}

/// How a [KeyLocator] crosses to the executor: the names it carries, as plain
/// values, with nothing that holds a session or a proxy.
///
/// Equal by content, so a duplicate the session did not fold is folded by the
/// executor.
sealed class LocatorSpec {
  const LocatorSpec({this.role});

  /// The slot the caller assigned, or `null` for the family's only slot.
  final KeyRole? role;
}

/// An [HdKeyLocator]: a wallet reference's number, the token of the session
/// that issued it, the coin, and the path.
final class HdLocatorSpec extends LocatorSpec {
  /// Creates the spec.
  const HdLocatorSpec({
    required this.sessionToken,
    required this.walletRef,
    required this.coin,
    required this.derivationPath,
    super.role,
  });

  /// The token of the session whose `WalletRef` this came from.
  final int sessionToken;

  /// The executor-issued id of the wallet, within that session.
  final int walletRef;

  /// The coin the key is derived for.
  final Coin coin;

  /// The full BIP-32 path. Not a secret.
  final String derivationPath;

  @override
  bool operator ==(Object other) =>
      other is HdLocatorSpec &&
      other.sessionToken == sessionToken &&
      other.walletRef == walletRef &&
      other.coin == coin &&
      other.derivationPath == derivationPath &&
      other.role == role;

  @override
  int get hashCode =>
      Object.hash(sessionToken, walletRef, coin, derivationPath, role);

  @override
  String toString() =>
      'hdPath(session: $sessionToken, wallet: $walletRef, ${coin.id}, '
      '$derivationPath${role == null ? '' : ', role: ${role!.id}'})';
}

/// An [ImportedKeyLocator]: the imported key's reference number.
final class ImportedLocatorSpec extends LocatorSpec {
  /// Creates the spec.
  const ImportedLocatorSpec({required this.keyRef, super.role});

  /// The session-scoped number of the imported key's `KeyRef`.
  final int keyRef;

  @override
  bool operator ==(Object other) =>
      other is ImportedLocatorSpec &&
      other.keyRef == keyRef &&
      other.role == role;

  @override
  int get hashCode => Object.hash(keyRef, role);

  @override
  String toString() =>
      'imported(key: $keyRef${role == null ? '' : ', role: ${role!.id}'})';
}

/// An [ExternalKeyLocator]: the device id. The public key is not carried —
/// no executor of this version signs with an external device.
final class ExternalLocatorSpec extends LocatorSpec {
  /// Creates the spec.
  const ExternalLocatorSpec({required this.deviceId, super.role});

  /// The device's identifier.
  final String deviceId;

  @override
  bool operator ==(Object other) =>
      other is ExternalLocatorSpec &&
      other.deviceId == deviceId &&
      other.role == role;

  @override
  int get hashCode => Object.hash(deviceId, role);

  @override
  String toString() =>
      'external($deviceId${role == null ? '' : ', role: ${role!.id}'})';
}

/// Releases one wallet. Reply: [Disposed], for an unknown, already-disposed,
/// or shutdown-freed reference too (DECISION-12 §3.7).
///
/// A control message: never rejected for a full queue, no deadline. At most
/// one is pending per reference; a repeat is folded into the pending one.
final class DisposeRef extends WorkerRequest {
  /// Creates the request for [walletRef].
  const DisposeRef(super.id, {required this.walletRef});

  /// The executor-issued id of the wallet.
  final int walletRef;

  @override
  String get operation => 'close';

  @override
  bool get isControl => true;

  @override
  String toString() => 'DisposeRef(#$id, wallet: $walletRef)';
}

/// Withdraws a queued operation. Reply: [Cancelled] when [target] had not
/// started, [NotCancellable] when it is running, finished, or unknown
/// (DECISION-12 §3.6).
///
/// A control message. Never queued: decided on arrival.
final class Cancel extends WorkerRequest {
  /// Creates the request to cancel [target].
  const Cancel(super.id, {required this.target});

  /// The request id to cancel.
  final int target;

  @override
  String get operation => 'cancel';

  @override
  bool get isControl => true;

  @override
  String toString() => 'Cancel(#$id, target: #$target)';
}

/// Ends the session: rejects every queued operation, lets the one in flight
/// finish, disposes every handle. Reply: [ShutdownComplete].
///
/// A control message, admissible always (DECISION-12 §3.4 rule 4).
final class Shutdown extends WorkerRequest {
  /// Creates the request.
  const Shutdown(super.id, {required this.grace});

  /// How long the session waits for [ShutdownComplete] before it forces the
  /// executor down. Informational to the executor, which cannot time itself.
  final Duration grace;

  @override
  String get operation => 'shutdown';

  @override
  bool get isControl => true;

  @override
  String toString() => 'Shutdown(#$id, grace: ${grace.inMilliseconds} ms)';
}

/// Overwrites with zeros the one secret buffer a request owns — an
/// [ImportWallet]'s entropy copy — once the request has been handled or
/// dropped unhandled. A `String` cannot be overwritten; references to it are
/// simply dropped (PRD §11.3).
void overwriteOwnedSecrets(WorkerRequest request) {
  if (request case ImportWallet(:final entropy?)) {
    entropy.fillRange(0, entropy.length, 0);
  }
}

/// The executor's own copy of [request], as an isolate boundary would make
/// it: a request that owns a secret buffer ([ImportWallet]'s entropy) is
/// copied with a buffer of its own; every other request is shared, since it
/// owns nothing that is overwritten.
///
/// With it the in-process transport behaves as an isolate transport does:
/// the sender overwrites its copy as soon as the request is handed over, and
/// the executor overwrites its copy once the request is handled.
WorkerRequest executorCopy(WorkerRequest request) => switch (request) {
  ImportWallet(:final id, :final entropy?, :final passphrase) =>
    ImportWallet.entropy(id, entropy, passphrase: passphrase),
  _ => request,
};

// --- replies ----------------------------------------------------------------

/// A message from the executor to the session: the one reply to the request
/// whose [id] it carries.
sealed class WorkerReply {
  const WorkerReply(this.id);

  /// The id of the request this answers.
  final int id;
}

/// The library is loaded, identified, and complete.
final class InitOk extends WorkerReply {
  /// Creates the reply.
  const InitOk(super.id, {required this.symbolCount});

  /// How many symbols the health check resolved.
  final int symbolCount;

  @override
  String toString() => 'InitOk(#$id, symbolCount: $symbolCount)';
}

/// A wallet exists in the owning isolate under [walletRef].
///
/// **A reference and nothing else** — no mnemonic, by construction
/// (DECISION-12 §3.2): a new wallet's mnemonic comes back through
/// [ExportMnemonic] like any other's.
final class WalletCreated extends WorkerReply {
  /// Creates the reply.
  const WalletCreated(super.id, {required this.walletRef});

  /// The executor-issued id. Positive, monotonic, never reused.
  final int walletRef;

  @override
  String toString() => 'WalletCreated(#$id, wallet: $walletRef)';
}

/// The wallet's mnemonic.
///
/// **One of the two replies that carry key material**, with
/// [MnemonicWordsSuggested] (DECISION-12 §3.2). Produced
/// only for an explicit [ExportMnemonic], never logged, never put into an
/// error, never kept by the executor after it is posted.
final class MnemonicExported extends WorkerReply {
  /// Creates the reply.
  const MnemonicExported(super.id, this.mnemonic);

  /// The mnemonic. Key material.
  final String mnemonic;

  @override
  String toString() => 'MnemonicExported(#$id, mnemonic: $redacted)';
}

/// The derived account: address, public key, path. No key, no handle.
final class AddressDerived extends WorkerReply {
  /// Creates the reply.
  const AddressDerived(super.id, this.account);

  /// The descriptor.
  final Account account;

  @override
  String toString() => 'AddressDerived(#$id, $account)';
}

/// Upstream's answer to [ValidateAddress].
final class AddressValidated extends WorkerReply {
  /// Creates the reply.
  const AddressValidated(super.id, {required this.isValid});

  /// Whether the address is valid for the coin and network asked about.
  final bool isValid;

  @override
  String toString() => 'AddressValidated(#$id, $isValid)';
}

/// Upstream's answer to [ValidateMnemonic]. A `bool`; carries no secret.
final class MnemonicValidated extends WorkerReply {
  /// Creates the reply.
  const MnemonicValidated(super.id, {required this.isValid});

  /// Whether the mnemonic is valid.
  final bool isValid;

  @override
  String toString() => 'MnemonicValidated(#$id, $isValid)';
}

/// Upstream's answer to [ValidateMnemonicWord]. A `bool`; carries no secret.
final class MnemonicWordValidated extends WorkerReply {
  /// Creates the reply.
  const MnemonicWordValidated(super.id, {required this.isValid});

  /// Whether the word is in the list.
  final bool isValid;

  @override
  String toString() => 'MnemonicWordValidated(#$id, $isValid)';
}

/// Upstream's suggestions for a prefix, in upstream's order.
///
/// Every word shares the prefix the caller typed, so the list says something
/// about a word being entered; `toString()` reports only how many there are.
final class MnemonicWordsSuggested extends WorkerReply {
  /// Creates the reply over an unmodifiable copy of [words].
  MnemonicWordsSuggested(super.id, List<String> words)
    : words = List<String>.unmodifiable(words);

  /// The suggestions.
  final List<String> words;

  @override
  String toString() =>
      'MnemonicWordsSuggested(#$id, ${words.length} words: $redacted)';
}

/// Upstream's signed transaction, parsed — and every key the operation
/// derived already released — before this reply was made (DECISION-12 §3.9).
///
/// **Not key-bearing**: a signed transaction carries signatures and public
/// data, never the private key that produced them.
///
/// [result]'s `usedKeys` is **empty on the wire**: the caller's locators hold
/// session-side objects that do not cross (see this library's doc comment),
/// so the session puts them back. That is exact, not approximate: resolution
/// fails with `KeyResolutionReason.unusedLocator` unless every locator fills a
/// role, so a successful signing used every locator it was given.
final class Signed extends WorkerReply {
  /// Creates the reply.
  const Signed(super.id, this.result);

  /// The signed transaction.
  final SignResult result;

  @override
  String toString() => 'Signed(#$id, $result)';
}

/// The wallet [walletRef] is released — or was never known, or was already
/// released; the answer is the same (DECISION-12 §3.7).
final class Disposed extends WorkerReply {
  /// Creates the reply.
  const Disposed(super.id, {required this.walletRef});

  /// The reference that was named.
  final int walletRef;

  @override
  String toString() => 'Disposed(#$id, wallet: $walletRef)';
}

/// [target] was still queued and has been withdrawn; it never ran. The target
/// itself is answered with [Failed] carrying [OperationCancelledError].
final class Cancelled extends WorkerReply {
  /// Creates the reply.
  const Cancelled(super.id, {required this.target});

  /// The withdrawn request.
  final int target;

  @override
  String toString() => 'Cancelled(#$id, target: #$target)';
}

/// [target] is running, has finished, or was never seen; it will be — or was
/// — answered normally.
final class NotCancellable extends WorkerReply {
  /// Creates the reply.
  const NotCancellable(super.id, {required this.target});

  /// The request that could not be withdrawn.
  final int target;

  @override
  String toString() => 'NotCancellable(#$id, target: #$target)';
}

/// Every handle the session owned is released.
final class ShutdownComplete extends WorkerReply {
  /// Creates the reply.
  const ShutdownComplete(super.id, {required this.disposedCount});

  /// How many wallets the shutdown itself released — those still live when it
  /// ran, not those closed before it.
  final int disposedCount;

  @override
  String toString() => 'ShutdownComplete(#$id, disposed: $disposedCount)';
}

/// The request failed with an already-typed [error]. The session never
/// rebuilds an exception from text.
final class Failed extends WorkerReply {
  /// Creates the reply.
  const Failed(super.id, this.error);

  /// The failure. Never carries a secret (`errors.dart`).
  final WalletCoreException error;

  @override
  String toString() => 'Failed(#$id, $error)';
}
