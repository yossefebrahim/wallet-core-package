<task>
Small documentation fixes on `integration/W5` from the independent review `docs/plan/reviews/W5-landing-fable.md` (root checkout) — findings B.1, B.4, B.5, B.6, B.7. You work in /Users/yossefebrahim/Work/wallet-core-package.worktrees/W5-integration (branch `integration/W5`, tip `b07f593`, clean). Read AGENTS.md first (rule 8 forbidden words; rule 10 no git writes; rule 11 owned paths only). Leave the edits uncommitted.
</task>

<edits>
1. `docs/security/threat_model.md` line ~67 (assets table, derived-key row) and line ~98 (TM-01 residual): they still say the key is "serialized into the signing input under Approach A" / "the serialized `SigningInput` holds the key in a Dart `Uint8List`". The built code (`packages/wallet_core_flutter/lib/src/signing/signing_core.dart:116-141`, `lib/src/engine/secret_buffers.dart:106-139`, `docs/decisions/DECISION-1-approach-a.md` §2) makes **no Dart-heap copy**: the key is read through a `Uint8List` view over upstream's `TWData`, prepended to the key-less input in one SDK-allocated `calloc` staging buffer that is zeroed and freed after `TWDataCreateWithBytes` copies it; residual copies are upstream's own (`TWPrivateKey`, the key `TWData`, the keyed-input `TWData`, each released before the reply; plus the copies upstream's Rust signing path makes and frees unwiped). Reword both cells to say exactly that. Change only those cells' text — not owner, mitigation, or residual-risk *classification*.
2. `docs/security/threat_model.md` line ~103 (TM-06): "the one reply type that may carry it" → "the only reply that carries a whole mnemonic (`MnemonicWordsSuggested` carries words sharing a prefix)".
3. `docs/security/memory_contract.md`: add one short paragraph (next to the existing `WalletEngine.suggestMnemonicWords` mention near line 76) stating that the requests `ValidateMnemonic`, `ValidateMnemonicWord`, `SuggestMnemonicWords` carry a mnemonic, a word, or a prefix as Dart `String`s that cannot be overwritten, are redacted from `toString()`/errors, and are dropped by the executor after use (cite `packages/wallet_core_flutter/lib/src/worker/protocol.dart:328-377`), so that the contract names all eight payloads of DECISION-12 §3.2.
4. `docs/decisions/DECISION-12.md` line ~393: "section 3.2 (the four payloads)" → "section 3.2 (the secret-bearing payloads — eight since the amendment of 2026-10-03)".
5. Root `pubspec.yaml`: remove the second of the two consecutive blank lines after `  - tools/lint` (lines ~22-23) and the extra trailing newline at EOF (file must end with exactly one `\n`). No other change.
</edits>

<constraints>
Owned paths: exactly the four files above. No code, no other docs, no new files, no dependencies, no git writes, no other agent. One shell command per call.
</constraints>

<gates>
export PATH="$PATH:$HOME/.pub-cache/bin"
melos bootstrap            # proves pubspec.yaml still parses
melos run format:check
grep -niE "zeroiz|secret-free|audited|reproducible" docs/security/threat_model.md docs/security/memory_contract.md docs/decisions/DECISION-12.md   # must print nothing new
git status --short         # exactly the four files
git diff --stat
</gates>

<report>
The full `git diff`, the gate tails, anything unexpected.
</report>
