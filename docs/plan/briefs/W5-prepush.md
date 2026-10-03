<task>
Three pre-push housekeeping edits on `integration/W5`, decided by the owner on 2026-10-03 ("Go" on the orchestrator's list). You work in /Users/yossefebrahim/Work/wallet-core-package.worktrees/W5-integration (branch `integration/W5`, tip `0ac87c7`, clean). Read AGENTS.md first (rule 8 forbidden words; rule 10 no git writes; rule 11 owned paths). Leave everything uncommitted.
</task>

<edits>
1. **Remove the tracked compiled binary.** `rm tools/gen/bin/registry_transform.exe` (6 MB Mach-O, unreferenced — confirm first with `grep -rn "registry_transform.exe" --exclude-dir=third_party --exclude-dir=.dart_tool --exclude-dir=build .`, which must print nothing). Append to `.gitignore`, under a new comment line `# Compiled Dart executables (dart compile exe) are never tracked`, the two patterns `*.exe` and `tools/*/bin/*.exe`. Do NOT run `git rm`; the deletion is recorded at commit time.
2. **PRD §11.4 table** (`docs/wallet_core_flutter_prd.md`, the "Approach A — Dart-side, minimized" column, two cells), wording drafted from the code by the DEC-12-amend session and approved by the owner:
   - Row "Mechanism", Approach A cell — replace with exactly: `As built (T1.12, EVM): the SDK encodes the key-less \`SigningInput\` in Dart, reads the derived key through a \`Uint8List\` view over the \`TWData\` that \`TWPrivateKeyData\` returns, copies tag ‖ length ‖ key ‖ key-less input into one SDK-allocated \`calloc\` staging buffer, hands it to \`TWDataCreateWithBytes\` and \`TWAnySignerSign\`, then overwrites the staging buffer with zeros and frees it`
   - Row "Dart-managed secret copies", Approach A cell — replace with exactly: `As built (T1.12, EVM): **none on the Dart heap.** The key is never set on a protobuf message and no Dart list holds the keyed serialized input (view + one native staging buffer, zeroed and freed). Native copies remain — upstream's \`TWPrivateKey\`, the key's \`TWData\`, and the keyed-input \`TWData\` — each released before the reply is posted (upstream's deletes zero them); copies upstream makes while signing are not reachable from Dart (DECISION-1 evidence §2)`
   Leave the Approach B column and every other row untouched. Keep the table's pipe structure valid (one line per row).
3. **CI Flutter pin** (`.github/workflows/ci.yml`): `flutter-version: 3.44.1` → `flutter-version: 3.47.5` at both occurrences (lines ~31 and ~77); nothing else in the file. Reason: the host and every recorded gate run are on 3.47.5 / Dart 3.13.4, whose `dart format` re-laid-out files that 3.44.1's formatter would flag.
</edits>

<constraints>
Owned paths: `tools/gen/bin/registry_transform.exe` (delete), `.gitignore`, `docs/wallet_core_flutter_prd.md`, `.github/workflows/ci.yml`. No other file, no dependencies, no git writes, no other agent. One shell command per call.
</constraints>

<gates>
export PATH="$PATH:$HOME/.pub-cache/bin"
grep -rn "registry_transform.exe" --exclude-dir=third_party --exclude-dir=.dart_tool --exclude-dir=build .     # nothing
melos run gen:registry && git status --short                        # the registry generator still runs from source; status must show only your four paths (` D` for the exe)
melos run format:check
grep -niE "zeroiz|secret-free|audited" docs/wallet_core_flutter_prd.md | wc -l    # paste the count before and after your edit (must be equal)
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml')); print('ci.yml parses')"
sed -n 204,212p docs/wallet_core_flutter_prd.md
</gates>

<report>
`git status --short`, `git diff` of `.gitignore`, `ci.yml` and the PRD, the gate tails, anything unexpected.
</report>
