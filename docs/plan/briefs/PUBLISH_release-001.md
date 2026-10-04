<task>
Publish the draft release — owner decided 2026-10-05 (D1a, "Yes, publish now"): this creates the permanent tag `native-4.8.0-001`. One command per call, paste outputs. No other git/gh write operation, no file edits, no other agent.
1. `gh release view native-4.8.0-001 --json tagName,isDraft,targetCommitish,assets -q '{tagName,isDraft,targetCommitish,n:(.assets|length)}'` (expect draft, 9 assets).
2. `gh release edit native-4.8.0-001 --draft=false` (do NOT pass --latest or --prerelease flags beyond what exists; if gh asks about marking latest, leave the default).
3. `gh release view native-4.8.0-001 --json tagName,isDraft,isPrerelease,isLatest,url,targetCommitish -q .`; `git ls-remote --tags origin | grep native-4.8.0-001`.
4. Anonymous download check (no token): `curl -sSIL -o /dev/null -w '%{http_code} %{url_effective}\n' "https://github.com/yossefebrahim/wallet-core-package/releases/download/native-4.8.0-001/SHA256SUMS"` (expect 200 after redirects) and `curl -sSL "https://github.com/yossefebrahim/wallet-core-package/releases/download/native-4.8.0-001/SHA256SUMS" | head -3`.
</task>
<structured_output_contract>Report: the before/after JSON, the tag line from ls-remote, the curl results.</structured_output_contract>
