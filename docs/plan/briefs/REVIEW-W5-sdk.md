<task>
Independent code review — read-only. You are reviewing work other implementer sessions produced for the `wallet_core_flutter` repository (an unofficial Dart/Flutter SDK over the open-source Trust Wallet Core library; read `AGENTS.md` at the root of the tree first — its twelve rules are the contract). Nothing is committed: the work sits as uncommitted changes in this worktree on top of branch base `integration/W3`. Do not trust the implementers' own reports or tests; verify by reading the code and, where useful, running the existing gates and small experiments of your own in $TMPDIR.

Scope of this review: the SDK package as it stands in this tree (`task/T1.12`): `packages/wallet_core_flutter/lib/**` and `packages/wallet_core_flutter/test/**` — tasks T1.11 (errors, coin facade, account/address, engine, HD wallet, secret buffers, worker protocol/handler/transport/loop, session, wallet proxy, scope, mnemonic facade) and T1.12 (requests, EVM family encode/parse, key-field check, `SyncSigningCore`, `Sign` protocol path, `LocalSigner`, exports) — plus `docs/decisions/DECISION-1-approach-a.md`. Design documents: `docs/architecture/{lifecycle,signing,public_model}.md`, `docs/decisions/DECISION-11.md`, `-12.md`, `-13.md`; PRD §10, §11, §14.3. Also check `packages/wallet_core_flutter_bindings/lib/src/memory/**` only as far as the SDK's use of it requires.

How to review:
  - Read every file in scope fully. For each defect, establish a concrete failure scenario (inputs/state → wrong output, crash, leak, secret exposure, contract violation) and confirm it against the code — run a throwaway test under $TMPDIR if you can (the macOS host library is at `third_party/wcf-native/macos/arm64_x86_64/libTrustWalletCore.dylib`; `export PATH="$PATH:$HOME/.pub-cache/bin"`; gates: `melos run analyze`, `melos run test`, `melos run test:native`).
  - Priorities, in order: (1) anything that can expose, retain, log, or mis-handle key material or mnemonics, or sign something other than what the caller asked for; (2) memory-safety and lifetime errors across FFI (use-after-dispose, double free, leaks on error paths, finalizer races, views over freed native memory); (3) correctness against the design documents named in scope and the PRD (`docs/wallet_core_flutter_prd.md`), including behaviour that will break when the in-process executor is replaced by a worker isolate; (4) violations of AGENTS.md rules (public surface leaking FFI/generated/protobuf types, cryptography implemented in Dart, runtime network access, forbidden words in docs, claims the code does not back); (5) tests that cannot fail, assert the wrong thing, or leave a stated requirement uncovered; (6) factual errors in the documents in scope — check each claim against the code or the measurement it cites.
  - Do not report style preferences, naming, or formatting.
</task>

<action_safety>
Read-only: do not modify, create, or delete any file inside the worktree; scratch files go under $TMPDIR only. No git command that writes. No network.
</action_safety>

<structured_output_contract>
End with:
  1. Verdict in one line: ship as is / fix before commit / needs redesign.
  2. Findings, most severe first. Each: severity (critical / high / medium / low), `file:line`, one-sentence defect, the concrete failure scenario, whether you CONFIRMED it (how) or it is PLAUSIBLE (why unconfirmed), and the smallest fix.
  3. Claims in docs/reports you checked and found true (short list), so the orchestrator knows what was verified.
  4. What you did not review.
</structured_output_contract>
