<task>
[TASK-ID] — [title from the phase file].
Goal: [one or two sentences: what exists after this task and why].
Current state: [what is in the tree today that matters for this task; name files].
Change: [the specifics, copied from the task note in docs/plan/phases/<phase>.md and expanded where needed].
Owned paths (create or modify ONLY these): [list].
Leave untouched: everything else, in particular [list the neighbours a careless implementer would touch].
Facts you cannot discover from the tree (decided by earlier tasks): [copy the relevant "Decided facts" lines from docs/plan/PROGRESS.md; for example "T1.6: the disposal base class is NativeResource in packages/wallet_core_flutter_bindings/lib/src/memory/native_resource.dart"].
PRD sections that govern this task: [§ numbers] in docs/wallet_core_flutter_prd.md — read them before you start.
</task>

<repo_constraints>
1. Generated directories (**/lib/src/generated/**, docs/capability_matrix.*) are never hand-edited; regenerate with melos run gen:*.
2. No cryptography, key derivation, hashing, or signed-transaction serialization is implemented here; every such operation calls upstream through the generated bindings. Encoding upstream's signing-input protobuf in Dart is allowed; producing signed transaction bytes is not.
3. No network access at runtime in SDK, bindings, or native-loader code.
4. package:wallet_core_flutter/wallet_core_flutter.dart exports no dart:ffi type, no generated TW* class, and no protobuf class in any public signature.
5. Every native-backed object implements the disposal contract of PRD §11.2 (explicit dispose, finalizer detach, double-dispose no-op, DisposedError after disposal, finally-released temporaries).
6. Requests never contain key material. Family code encodes key-less inputs (encodeKeylessInput) and parses results (parseSigningOutput → sealed SignResult); only the signer injects keys, after checking the generated key_fields.json list. Raw protobuf signing exists only under advanced.dart.
7. Every test vector entry cites provenance (upstream path + commit, a standard, or a published transaction).
8. Docs never use "zeroization", "secret-free", "reproducible", or "audited" about this SDK, never make legal claims about AGPL, and package names never contain "trust".
9. Do not add a dependency without listing it, with version, in your final report.
10. Touch only the owned paths above. No unrelated cleanup, renames, or formatting sweeps.
11. The public SDK never exposes the generated CoinType; use the stable coin/network facade (DECISION-11). Public resources close asynchronously (Future<void> close()); only internal wrappers have synchronous dispose() (PRD §11.2, §14.3). Signers take a Set<KeyLocator> and return sealed SignResults (DECISION-13).
[Add task-specific constraints here, for example "encodeKeylessInput must be a pure function with no isolate, pointer, or key access".]
</repo_constraints>

<verification_loop>
Dependencies are already fetched by the orchestrator; run pub commands with --offline if the network is unavailable.
Run these exact commands and make them green before finishing; fix failures caused by your change:
  melos run analyze
  melos run format:check
  melos run test
  [task-specific gates, for example: melos run gen:check · melos run vectors:validate · melos run lint:public-api · dart test packages/wallet_core_flutter_bindings/test/memory]
Confirm git status shows only the owned paths changed.
</verification_loop>

<action_safety>
Keep changes within the task. Do not perform unrelated cleanup. Do not run git add, git commit, or git push. Do not start another agent session or delegation. Leave all work uncommitted for the orchestrator to review and land.
</action_safety>

<structured_output_contract>
End with a report in exactly this shape:
  1. What changed and why (including any design decision you had to make and the alternative you rejected)
  2. Files touched (full paths)
  3. Gate outcomes with counts (tests run/passed, analyzer issues, format diffs) — paste the command output tails
  4. Deviations from the brief, open questions, dependencies added (name + version), and anything the orchestrator should decide
</structured_output_contract>
