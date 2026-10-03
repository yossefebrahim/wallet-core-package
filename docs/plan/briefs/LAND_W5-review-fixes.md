<task>
LAND W5-review-fixes — git bookkeeping only, one commit, no file content changes.
Worktree /Users/yossefebrahim/Work/wallet-core-package.worktrees/W5-integration (branch `integration/W5`, tip `b07f593`). `git status --short` must list exactly: ` M docs/decisions/DECISION-12.md`, ` M docs/security/memory_contract.md`, ` M docs/security/threat_model.md`, ` M pubspec.yaml` — anything else: STOP and report. Then `git add` those four files and commit:
"docs: threat model and memory contract match Approach A as built; DECISION-12 pointer; pubspec whitespace"
body: "Findings B.1, B.4, B.5, B.6, B.7 of docs/plan/reviews/W5-landing-fable.md: TM-01 and the derived-key asset row no longer claim a Dart-heap key copy (the key is a view over upstream's TWData staged in one zeroed calloc buffer); TM-06 names the only whole-mnemonic reply; memory_contract.md names the three mnemonic-check requests so all eight secret-bearing payloads of DECISION-12 §3.2 are covered; DECISION-12 'read before ratifying' pointer updated; duplicate blank line and EOF newline from the T1.15 merge removed. Implemented by agy-delegate on brief docs/plan/briefs/W5-review-fixes.md; reviewed by the orchestrator."
then a blank line and the trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
Paste `git log --oneline -1` and `git status --short | wc -l` (must be 0).
</task>
<action_safety>No push, tag, reset, checkout, merge, rebase, stash, amend, clean, branch deletion, `--force`, or edits to any file. No other agent.</action_safety>
<structured_output_contract>Report: status paste, the commit hash (or STOPPED: reason), the final pastes.</structured_output_contract>
