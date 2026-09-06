<task>
T1.5 — Registry transform → CoinType enum + metadata.
Goal: a versioned script turns upstream's registry.json into generated Dart so the SDK has a CoinType enum and per-coin metadata that is regenerated, never edited.
Current state: third_party/wallet-core/ holds the upstream checkout at the pinned commit (see compat_manifest.json → upstream.commit); third_party/wallet-core/registry.json is the input. packages/wallet_core_flutter_bindings/ has generated ffi and proto directories from T1.3 and T1.4; the registry directory does not exist yet.
Change:
  - Write tools/gen/registry_transform.dart: reads registry.json, writes packages/wallet_core_flutter_bindings/lib/src/generated/registry/coin_type.dart containing `enum CoinType` (one value per registry entry, value name derived from the upstream `id` in lowerCamelCase, with the numeric `coinId` as a field) and a `CoinInfo` class with: name, symbol, decimals, derivation paths (list; upstream may list several), curve, publicKeyType, blockchain family string, explorer URL templates (url, txPath, accountPath, sampleTx, sampleAccount where present). Expose `CoinType.info` as a lookup into a generated const map.
  - Emit a generated-file header comment naming the script and the manifest commit; the output must be deterministic (stable ordering by coinId).
  - Add a melos script `gen:registry` in melos.yaml that runs the transform, and extend the existing `gen:all` script to include it.
  - Add tools/gen/test/registry_transform_test.dart using a small fixture copy of three registry entries under tools/gen/test/fixtures/.
Owned paths (create or modify ONLY these): tools/gen/registry_transform.dart, tools/gen/test/registry_transform_test.dart, tools/gen/test/fixtures/registry_sample.json, packages/wallet_core_flutter_bindings/lib/src/generated/registry/, melos.yaml (the gen:registry and gen:all script entries only).
Leave untouched: the ffi and proto generated directories, ffigen.yaml, tools/inventory/, compat_manifest.json, every package pubspec.
Facts you cannot discover from the tree:
  - T1.3: generated directories are validated by `melos run gen:check`, which regenerates and fails on any diff; your output must be reproducible byte for byte.
  - T1.1: the pinned commit is recorded in compat_manifest.json → upstream.commit; cite it in the header comment by reading the manifest, do not hardcode it.
PRD sections that govern this task: §9 (registry transform requirement), §8 (bindings package must not contain hand-written business logic).
</task>

<repo_constraints>
1. Generated directories (**/lib/src/generated/**) are never hand-edited; the transform script is the only writer.
2. No business logic in the bindings package beyond the generated data and lookups.
3. package:wallet_core_flutter/wallet_core_flutter.dart is not touched by this task.
9. Do not add a dependency without listing it, with version, in your final report (prefer dart:convert; do not add a JSON or YAML package).
10. Touch only the owned paths above. No unrelated cleanup, renames, or formatting sweeps.
</repo_constraints>

<verification_loop>
Dependencies are already fetched; use --offline for any pub command.
Run these exact commands and make them green before finishing:
  melos run gen:registry
  melos run gen:check
  melos run analyze
  melos run format:check
  dart test tools/gen/test
Confirm git status shows only the owned paths changed, and that running gen:registry twice produces no diff.
</verification_loop>

<action_safety>
Keep changes within the task. Do not run git add, git commit, or git push. Do not start another agent session. Leave all work uncommitted for the orchestrator to review and land.
</action_safety>

<structured_output_contract>
End with a report in exactly this shape:
  1. What changed and why (state the naming rule you used for enum values and any registry field you could not map)
  2. Files touched (full paths)
  3. Gate outcomes with counts — paste the command output tails, including the registry entry count and the enum value count
  4. Deviations, open questions, dependencies added, and anything the orchestrator should decide
</structured_output_contract>
