/// [SessionState]: the states of a `WalletCore` session (DECISION-12 §3.1).
library;

/// Lifecycle of a `WalletCore` session. Operations are accepted only in
/// [ready].
///
/// Transitions, exhaustively (DECISION-12 §3.1): `initializing → ready`,
/// `initializing → failed`, `ready → closing`, `ready → failed`,
/// `closing → closed`, `closing → failed`, and `failed → closed`. There is no
/// transition out of [closed]; recovery is a new session.
///
/// Declared here, ahead of the session itself, because `SessionStateError`
/// carries one and the error hierarchy is sealed into a single library.
enum SessionState {
  /// `initialize()` has not returned yet.
  initializing,

  /// The session accepts operations.
  ready,

  /// `shutdown()` has been called; new operations are rejected.
  closing,

  /// The session has ended. Every reference it issued is invalid.
  closed,

  /// The session's owning isolate ended, or initialization failed.
  failed,
}
