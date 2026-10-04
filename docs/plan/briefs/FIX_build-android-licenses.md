<task>
Fix the Android job of `build-native.yml` and re-dispatch (owner-authorized Phase C, 2026-10-03). Run 37149068493: Apple job succeeded again; Android job failed in "Build, gate, and record" because `sdkmanager --install ndk;28.0.12674087 cmake;3.18.1` stopped at `License android-sdk-preview-license: … Accept? (y/N)` — the NDK package sits behind a licence the runner image has not accepted, and headless `sdkmanager` cannot prompt. Nothing was published or reserved (assemble skipped; `gh release list` empty), so `as_4.8.0_001` is reused.

Repository root /Users/yossefebrahim/Work/wallet-core-package, branch `main`, tip `326823d`. The tree has the orchestrator's uncommitted ` M docs/plan/PROGRESS.md` and untracked `docs/plan/briefs/*.md` — expected; leave them alone; never `git add -A`.

Edits, `.github/workflows/build-native.yml` only:
1. In the **Android** job (the second "Select the pinned Xcode" step, around line 298), insert a new step immediately AFTER that step and BEFORE the comment block that precedes "Build, gate, and record":
```yaml
      # ndk;28.0.12674087 is behind android-sdk-preview-license on the macos-15
      # image and sdkmanager cannot prompt in CI: accept the SDK licences the
      # same way every Android CI does. No pipefail here on purpose — `yes`
      # exits by SIGPIPE once sdkmanager closes its stdin.
      - name: Accept the Android SDK licences the NDK install needs
        run: |
          set -eu
          sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
          yes | "$sdk/cmdline-tools/latest/bin/sdkmanager" --licenses >/dev/null
          echo "licences accepted under $sdk/licenses:"
          ls "$sdk/licenses"
```
   Match the file's indentation (6 spaces before `- name:`), keep YAML valid.
2. In the `workflow_dispatch.inputs.xcode_version` block, change `default: '26.6'` to `default: '26.3.0'` and append to its description one sentence: `On the macos-15 image Xcode_26.6.app is listed but not a real install (run 37148717861); 26.3.0 is the newest that is.`
Check: `python3 -c "import yaml;yaml.safe_load(open('.github/workflows/build-native.yml'));print('parses')"`; `git diff --stat` must show only that file.

Then: `git add .github/workflows/build-native.yml`; commit "ci(build-native): accept Android SDK licences before installing the NDK; Xcode default 26.3.0" with body "Run 37149068493 stopped at android-sdk-preview-license for ndk;28.0.12674087 (sdkmanager cannot prompt in CI); run 37148717861 showed Xcode_26.6.app is not a usable install on macos-15. Owner-authorized Phase C fix." and the trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` after a blank line. `git push origin main` (plain; STOP on rejection). Wait 20 s, then:
  gh workflow run build-native.yml --ref main -f upstream_tag=4.8.0 -f upstream_commit=d692ac27749d0c615e17c751b70ab4f0aa75c59b -f artifact_set_id=as_4.8.0_001 -f xcode_version=26.3.0 -f publish_release=false
Wait 30 s; paste `gh run list --workflow=build-native.yml --limit 3` and the new run URL.
No rebase/reset/checkout/stash/amend/tag/force, no `publish_release=true`, no second dispatch, no other file, no other agent.
</task>
<structured_output_contract>Report: the diff, the yaml-parse line, commit hash, push output, dispatch output + run id/URL, run list; anything failed/skipped.</structured_output_contract>
