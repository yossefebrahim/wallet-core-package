<task>
Independent high-effort review of everything the orchestrator session of 2026-10-03 changed or caused to be changed in wallet_core_flutter (an unofficial MIT-licensed Dart/Flutter SDK over Trust Wallet Core; not affiliated with or endorsed by Trust Wallet). READ-ONLY: create, edit, or delete nothing; your final message is the only deliverable. Be adversarial: assume each change is wrong until the tree proves it right; reproduce claims rather than trusting reports.
</task>

<context>
Repository root (branch `main`, holds the plan docs): /Users/yossefebrahim/Work/wallet-core-package
Integration worktree to review (branch `integration/W5`, tip `b07f593` = `5e96a36` + the T1.2-d1 commit): /Users/yossefebrahim/Work/wallet-core-package.worktrees/W5-integration — bootstrapped; `third_party/` (git-ignored) holds the upstream checkout and the host library so every gate runs.
Rules: AGENTS.md (read first; rule 2 no crypto in Dart, rule 4 public surface, rule 6 key-less requests, rule 8 forbidden words, rule 12 facade/async close).
Plan of record for today: docs/plan/NEXT_STEPS.md (root). Status: docs/plan/PROGRESS.md (root) — the "Phase A/B of NEXT_STEPS.md running" block under "Needs your eyes → Wave 5 review pass" lists what was done and claims results.
Briefs the session wrote (root, docs/plan/briefs/): DEC-12-amend.md, A3-crypto-pin.md, LAND_W5.md, LAND_W5-d1.md, T1.2-d1.md.
Prior independent reviews, for what was already checked: docs/plan/reviews/W5-*.md (root).

What changed today, to be reviewed:
1. **A2 — documentation brought to the code** (commit `6d894ff` on `task/T1.12`, file set: docs/decisions/DECISION-12.md, docs/architecture/lifecycle.md, docs/security/threat_model.md lines 64/101, doc comments in packages/wallet_core_flutter/lib/src/worker/protocol.dart and lib/src/wallet/wallet.dart; and docs/security/memory_contract.md line 74 in `d04f621` on `task/T1.18`). Claims: 13 requests / 14 replies named correctly; secret-bearing set is eight (six requests incl. planned `ImportKey`, two replies); `OperationDeadline` description (created at submission in session.dart, carried beside the request by WorkerTransport.send, checked twice in worker_loop.dart, result dropped unposted and a key-less `Failed(OperationTimeoutError)` posted); §8 trigger 6 fired note; T2.1 forward note. Verify every statement against the code with file:line; look for anything in those docs that is still stale, and for any remaining "four"/"only reply" wording anywhere in the W5 tree (`grep -rn` over docs/ and packages/*/lib).
2. **A3** — tools/probes/pubspec.yaml `crypto: ^3.0.7` (in `42fea90`). Check the lockfile agrees and nothing else moved.
3. **LAND_W5 — the git landing.** Ten commits + three merges, listed in PROGRESS.md with hashes. Verify: each commit's file set matches the allowed set in LAND_W5.md; no file that AGENTS.md's layout or .gitignore says must not be tracked (third_party, build outputs, secrets, Apple team ids in eval/**/project.pbxproj, large binaries — note `tools/gen/bin/registry_transform.exe` predates today, say whether it's still a problem); the `integration/W5` merge of root pubspec.yaml is correct and complete (workspace list, scripts: `test:native` must be T1.11b's `run_native_tests.sh` form, plus `probe:sign-json`, `lint:public-api`); `task/T1.12`'s and `eval/approach-b`'s shared SDK files differ only by A2's doc comments (`git diff task/T1.12 eval/approach-b -- packages/wallet_core_flutter/lib/src/worker/protocol.dart packages/wallet_core_flutter/lib/src/wallet/wallet.dart` should be empty; list what else differs and whether that is the intended Approach B seam).
4. **Gates on integration/W5** — re-run yourself (`export PATH="$PATH:$HOME/.pub-cache/bin"`; `melos run analyze`, `format:check`, `test`, `test:native`, `inventory:check`, `gen:check`, `lint:public-api`, `vectors:validate`, `manifest:validate`, `probe:sign-json` twice and `cmp`). Expected per the plan: all green; SDK 270 tests; native 42 + 74; lint 0 violations over 49 elements. Report the actual numbers; a mismatch is a finding.
5. **T1.2-d1** (commit `b07f593` on `integration/W5`; its decision-doc note is `f53bd6b` on `eval/option1`): `-Wl,-headerpad_max_install_names` added in tools/native_build/build_apple.sh; README and DECISION-2-option1.md notes. Verify the flag is on the `-dynamiclib` line only and nothing else changed in the link line; if `${TMPDIR}/wcf-native/artifacts/macos/arm64_x86_64/libTrustWalletCore.dylib` exists, check `otool -l | grep -A3 LC_ID_DYLIB` and that `install_name_tool -id` with a 180-char id succeeds on a copy.
6. **The orchestrator's own edits** — docs/plan/PROGRESS.md and docs/plan/NEXT_STEPS.md (root). Check for forbidden words (AGENTS.md rule 8) and for claims that the tree does not support.
</context>

<grounding_rules>
Ground every claim in a file path with line numbers, a commit hash, a test name, or a pasted command output. Label inferences. If evidence is missing, say UNPROVEN. Do not propose new scope. Do not run any git command that writes (no add/commit/checkout/reset/stash/merge); `git diff`, `git log`, `git show`, `git status` are fine.
</grounding_rules>

<structured_output_contract>
Report in exactly this shape:
  A. Per item 1–6: verdict (OK / FINDINGS / UNPROVEN) with evidence.
  B. Findings, most severe first, each with severity (blocking / should-fix / nit), file:line or hash, description, suggested fix. Blocking = must not be pushed as is.
  C. Gate results table: gate, exit code, key counts, matches expectation yes/no.
  D. Anything you noticed in the W5 tree that is outside today's changes but would embarrass the project when pushed (max 10 lines).
  E. One paragraph: is `integration/W5` ready for the owner to push? Yes / No and the single most important reason.
</structured_output_contract>
