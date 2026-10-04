<task>
Delta to DEC-addenda-2026-10-04 (same two files, no commit, touch nothing else). In the new DECISION-14 §10 you copied the brief's instructions into the record. Rewrite these fragments as statements of fact/decision, same meaning, no imperative voice:
- item b: "Record as a deviation from "unmodified upstream build" with the patch logged in the artifact record." → "This is a deviation from an unmodified upstream build; the patch is logged in the artifact record and in the build log."
- item f: "State this as the operating rule consistent with §4.3's immutability; note that no run has yet reached the publish job." → "Operating rule, consistent with §4.3's immutability: a failed publish burns its set id. No run has yet reached the publish job."
- item g: "Record the two options for the owner: (i) … (ii) … Do not pick." → "Two options are open for the owner at D1a: (i) … (ii) …. Neither is chosen here." (keep the option texts).
- item a: if it contains "that P0 must drop or replace", keep (that is a fact about P0's scope).
Then re-read §10 once end to end for any other sentence addressed to an agent ("verify", "record", "do not") and fix it the same way. Paste the final §10 verbatim and `git diff --stat docs/decisions`.
</task>
<structured_output_contract>Report: final §10 verbatim; diff stat.</structured_output_contract>
