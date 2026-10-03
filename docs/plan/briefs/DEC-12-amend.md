<task>
DEC-12-amend — amend DECISION-12 §3.2/§3.5/§8 and `docs/architecture/lifecycle.md` §6 so that every statement about the worker protocol matches the code that now exists in this worktree (`packages/wallet_core_flutter/lib/src/worker/protocol.dart` and its users). The human decided on 2026-10-03: the secret-bearing payload set is amended from four to eight; the per-request `OperationDeadline` is recorded; §8 trigger 6 records this reopening with the date.

You are working in the `T1.12` worktree (`task/T1.12`). The tree is uncommitted on purpose; do not change that.
</task>

<context>
Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet. Read `AGENTS.md` first; its rules bind you (rule 8 forbids the words "zeroization", "secret-free", "audited", and "reproducible" about this SDK's artifacts; rule 10 forbids `git add/commit/push` and starting another agent session; rule 11 limits you to owned paths).

What the code says today (verify each item yourself before writing it into the docs; cite file:line in the report):
- `protocol.dart` declares these requests: `Init`, `CreateWallet`, `ImportWallet`, `ExportMnemonic`, `DeriveAddress`, `ValidateAddress`, `ValidateMnemonic`, `ValidateMnemonicWord`, `SuggestMnemonicWords`, `Sign`, `DisposeRef`, `Cancel`, `Shutdown` — and these replies: `InitOk`, `WalletCreated`, `MnemonicExported`, `AddressDerived`, `AddressValidated`, `MnemonicValidated`, `MnemonicWordValidated`, `MnemonicWordsSuggested`, `Signed`, `Disposed`, `Cancelled`, `NotCancellable`, `ShutdownComplete`, `Failed`. Count them; the "13 requests and 14 replies" sentence in lifecycle.md §6 and "Thirteen request types and fourteen reply types" in DECISION-12 §3.2 must state the real numbers and the real names. `ImportKey`, `SignMessage`, `Plan`, `KeyImported`, `MessageSigned`, `Planned` do NOT exist yet — keep them in the tables only if marked as planned (T2.5/T2.7/T3.4), never as present.
- The secret-bearing payloads are now **eight**: requests `CreateWallet` (passphrase), `ImportWallet` (mnemonic or entropy, passphrase), `ValidateMnemonic` (a mnemonic), `ValidateMnemonicWord` (a word of one), `SuggestMnemonicWords` (a prefix of one); replies `MnemonicExported` (mnemonic), `MnemonicWordsSuggested` (candidate words). Read each class's doc comment and `overwriteOwnedSecrets` / the worker loop to confirm which are treated as secret-bearing in code, and list exactly those. If the code treats a different set as secret-bearing than the eight above, STOP and report the discrepancy instead of writing either number.
- `Init` no longer carries timeouts. Each operation is sent beside an `OperationDeadline(timeout, atMicros)` built with `OperationDeadline.after(timeout)` on the process monotonic clock (`Timeline.now`, `monotonicMicros()`), measured from submission, saturating at `neverMicros`. The executor checks `hasPassed` before posting a reply and **drops the result without posting it** (DECISION-12 §3.9 "dropped without being posted, not posted and ignored"). Find where the deadline is created (`session.dart`), where it is checked (`in_process_executor.dart` or the worker loop), and what `WorkerTransport.send` carries.
- T2.1 (worker isolate transport, Phase 2) must carry the `OperationDeadline` in its envelope, and will add a public cancel-before-start so `OperationCancelledError` becomes reachable — that is a decision of 2026-10-03, record it as a forward note, not as something that exists.
</context>

<edits>
1. `docs/decisions/DECISION-12.md`
   - §3.2 message table: real request/reply names and counts; planned-but-absent messages marked as such.
   - §3.2 "Which payloads carry a secret, enumerated": four → eight, table updated with direction and what each carries; the "closed set" paragraph keeps its meaning with the new number.
   - §3.5 Timeouts: remove "overridable at `initialize()`" / `Init` carrying timeouts if the code no longer does that; describe `OperationDeadline` (what it is, monotonic clock, measured from submission, saturation, the dropped-not-posted rule, and what T2.1's envelope must carry). Keep the `Dispose`-has-no-deadline reasoning.
   - §8 trigger 6: append a dated note (2026-10-03) that the trigger fired, that the set was reopened and amended to eight, and why those five additions are accepted (they are mnemonic-validation and word-suggestion paths that must see the mnemonic; none of them returns or accepts a derived key).
   - Add a short "Amendment 2026-10-03" entry near the top or in the Decision section so a reader sees the record was amended.
2. `docs/architecture/lifecycle.md` §6: counts, the Dart sketch of the sealed families (add the five mnemonic-validation types and `OperationDeadline`; drop or mark-as-planned the absent ones), the eight payloads, the deadline rule.
3. Do NOT edit `docs/wallet_core_flutter_prd.md`. Instead, in your report, propose a replacement for PRD §11.4's row "Dart-managed secret copies | Yes: protobuf message field, serialized bytes, possibly builder intermediates…" as a unified diff: the Approach A code in this tree makes neither a protobuf message field nor a serialized-bytes copy of the key (read `packages/wallet_core_flutter/lib/src/signing/**` and `docs/decisions/DECISION-1-approach-a.md` and say precisely which Dart-side copies exist, if any).
</edits>

<constraints>
- Owned paths: `docs/decisions/DECISION-12.md`, `docs/architecture/lifecycle.md` only. No code edits, no other docs, no new files, no dependencies.
- Every factual statement you write cites the code; put the citations in the report (file:line), not necessarily in the docs.
- Forbidden-word check after editing: `grep -niE "zeroiz|secret-free|audited|reproducible" docs/decisions/DECISION-12.md docs/architecture/lifecycle.md` must print nothing new (if a pre-existing hit is already there, leave it and list it).
- No git writes, no other agent session.
</constraints>

<gates>
export PATH="$PATH:$HOME/.pub-cache/bin"
melos run format:check          # docs changes must not break it (it formats Dart only, but run it)
grep -niE "zeroiz|secret-free|audited|reproducible" docs/decisions/DECISION-12.md docs/architecture/lifecycle.md
</gates>

<report>
1. The real request/reply inventory (names, counts) with file:line.
2. The eight secret-bearing payloads with file:line of the code that treats each as secret-bearing; any discrepancy.
3. Where `OperationDeadline` is created, carried, and checked (file:line).
4. Diff summary of each edited section.
5. The proposed PRD §11.4 wording as a unified diff (not applied).
6. Gate tails; forbidden-word grep output.
7. Open questions.
</report>
