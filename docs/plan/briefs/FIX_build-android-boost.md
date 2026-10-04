<task>
Fix the Android job of `build-native.yml` and re-dispatch (owner-authorized Phase C, 2026-10-03). Run 37149307861: Apple job succeeded (third time); Android job got through licences, NDK/CMake install, Rust and upstream's dependency scripts, built `wallet-core-rs`, then Gradle's `:wallet-core:configureCMakeRelease[arm64-v8a]` failed: `Could NOT find Boost (missing: Boost_INCLUDE_DIR)` from upstream's `CMakeLists.txt:42 find_host_package(Boost REQUIRED)`. Boost 1.92.0 WAS installed (`brew install boost` by upstream's `tools/install-sys-dependencies-mac`, poured to `/opt/homebrew/Cellar/boost/1.92.0`), but the Android SDK's CMake 3.18.1 does not search the Apple-Silicon brew prefix `/opt/homebrew`, and upstream's script only appends `export BOOST_ROOT=$(brew --prefix boost)` to `~/.zprofile`, which a CI shell never sources (upstream's own CI runs on Intel `macos-latest-large`, where brew lives in `/usr/local`, which CMake searches by default). Nothing was published or reserved (assemble skipped; `gh release list` empty), so `as_4.8.0_001` is reused.

Repository root /Users/yossefebrahim/Work/wallet-core-package, branch `main`, tip `2e76d59`. The tree may show the orchestrator's ` M docs/plan/PROGRESS.md` and untracked `docs/plan/briefs/*.md` — leave them; never `git add -A`.

Edit `tools/native_build/build_android.sh` only. In the dependency block (around lines 288–299: the subshell that runs `tools/install-sys-dependencies-mac` / `-linux`, `install-rust-dependencies`, `install-android-dependencies`, `install-dependencies`), the exported variable must be visible to the later `./gradlew --no-daemon assembleRelease` (around line 345), so set it in the main shell, not inside that subshell: immediately AFTER the dependency block (i.e. after the `fi` that closes `if (( skip_deps ))`), add:

```bash
# CMake must find Boost from the host, not the NDK sysroot (upstream's
# find_host_package). Upstream's install-sys-dependencies-mac writes
# BOOST_ROOT into ~/.zprofile, which a non-interactive shell never reads, and
# the Android SDK's CMake 3.18 does not search Apple Silicon's brew prefix
# (/opt/homebrew) on its own — upstream's CI runs on Intel runners where
# /usr/local is searched by default. So export it here for Gradle's CMake.
if [[ -z ${BOOST_ROOT:-} ]] && command -v brew >/dev/null 2>&1; then
  if boost_prefix=$(brew --prefix boost 2>/dev/null) && [[ -d $boost_prefix/include/boost ]]; then
    export BOOST_ROOT=$boost_prefix
  fi
fi
[[ -n ${BOOST_ROOT:-} ]] && wcf_log "BOOST_ROOT: $BOOST_ROOT"
```
Match the file's style (bash 3.2-compatible, `wcf_log` exists in `lib/common.sh`). Then `bash -n tools/native_build/build_android.sh`; `shellcheck tools/native_build/build_android.sh` if shellcheck is installed (paste; pre-existing warnings are fine, new ones are not); `git diff --stat` must show only that file.

Commit: `git add tools/native_build/build_android.sh`; message "native_build: export BOOST_ROOT from brew for the Android CMake configure" with body "build-native.yml run 37149307861: Gradle's configureCMakeRelease failed with 'Could NOT find Boost' although brew had installed boost 1.92.0 under /opt/homebrew — upstream's script only writes BOOST_ROOT to ~/.zprofile and CMake 3.18 does not search the Apple Silicon brew prefix. Owner-authorized Phase C fix." and the trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` after a blank line. `git push origin main` (plain; STOP on rejection). Wait 20 s, then:
  gh workflow run build-native.yml --ref main -f upstream_tag=4.8.0 -f upstream_commit=d692ac27749d0c615e17c751b70ab4f0aa75c59b -f artifact_set_id=as_4.8.0_001 -f xcode_version=26.3.0 -f publish_release=false
Wait 30 s; paste `gh run list --workflow=build-native.yml --limit 3` and the new run URL.
No rebase/reset/checkout/stash/amend/tag/force, no `publish_release=true`, no second dispatch, no other file, no other agent.
</task>
<structured_output_contract>Report: the diff, `bash -n`/shellcheck output, commit hash, push output, dispatch output + run id/URL, run list; anything failed/skipped.</structured_output_contract>
