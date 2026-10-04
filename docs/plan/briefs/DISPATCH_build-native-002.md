<task>
Re-dispatch the native build (owner-authorized 2026-10-03). Run 37148717861 failed in both macOS jobs at "Select the pinned Xcode": the default `xcode_version` 26.6 names `/Applications/Xcode_26.6.app`, which `ls` lists on the `macos-15` runner but `[[ -d ]]` rejects (a dangling link or placeholder); the newest real install is `Xcode_26.3.0.app`. Nothing was published or reserved (no release, no tag — `gh release list` is empty), so the set id is reusable.

From /Users/yossefebrahim/Work/wallet-core-package run exactly:
  gh workflow run build-native.yml --ref main -f upstream_tag=4.8.0 -f upstream_commit=d692ac27749d0c615e17c751b70ab4f0aa75c59b -f artifact_set_id=as_4.8.0_001 -f xcode_version=26.3.0 -f publish_release=false
Wait 30 seconds, then paste `gh run list --workflow=build-native.yml --limit 3` and the new run's URL (`gh run view <id> --json url -q .url`). Do not touch git, do not edit files, no second dispatch, no `publish_release=true`, no other agent.
</task>
<structured_output_contract>Report: the dispatch output, the run id and URL, the run list paste.</structured_output_contract>
