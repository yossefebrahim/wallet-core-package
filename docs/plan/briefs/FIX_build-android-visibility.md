<task>
Fix the Android library's symbol visibility and re-dispatch the native build (owner-authorized Phase C, 2026-10-04). Run 37155340955: the Android `.so` built and the export gate (now reading `.dynsym`) reported `12063 defined external symbols, 27 of them TW*` → `expected 464, missing 437`; `wcf_build_info` exported: yes. Cause, verified in the pinned upstream tree: `cmake/StandardSettings.cmake:4-6` sets `CMAKE_CXX_VISIBILITY_PRESET hidden` unless the CMake variable `FLUTTER` is truthy; the 27 exported functions are exactly those annotated `TW_VISIBILITY_DEFAULT` (TWData/TWString/TWCardano). Upstream's own dart:ffi build passes `-DFLUTTER=ON` (`tools/flutter-build`). Its Android Gradle module (`android/wallet-core/build.gradle:14`) passes only `"-DCMAKE_BUILD_TYPE=Release", "-DTW_UNITY_BUILD=ON"`. Nothing was published or reserved (assemble skipped; `gh release list` empty), so `as_4.8.0_001` is reused.

Repository root /Users/yossefebrahim/Work/wallet-core-package, branch `main`, tip `56560e8`. The tree may show the orchestrator's ` M docs/plan/PROGRESS.md` / `?? docs/plan/briefs/*` — leave them; never `git add -A`. A copy of upstream's tree at the pinned commit is at /Users/yossefebrahim/Work/wallet-core-package.worktrees/W5-integration/third_party/wallet-core (read-only reference for you; the CI builds from a fresh checkout).

1. Edit `tools/native_build/build_android.sh` only. Before the `gradle assembleRelease` section (the subshell that runs `./gradlew --no-daemon assembleRelease`, around line 356), add a step that patches the Gradle module's CMake arguments in the checked-out upstream tree:
   ```bash
   # Upstream hides every C symbol on Android unless CMake sees FLUTTER=ON
   # (cmake/StandardSettings.cmake: CMAKE_CXX_VISIBILITY_PRESET hidden) — its
   # AAR serves the JNI binding, which never needed the TW* C API exported,
   # and only TWData/TWString/TWCardano carry TW_VISIBILITY_DEFAULT (27 of 464;
   # build-native run 37155340955). dart:ffi needs all of them, so pass the
   # same switch upstream's own tools/flutter-build passes. This is the one
   # edit we make to upstream's build files; the identity object is the only
   # other change to the tree, and both are stated in the record's notes.
   gradle_module="$source_dir/android/wallet-core/build.gradle"
   [[ -f $gradle_module ]] || wcf_die "no Gradle module at $gradle_module"
   if ! grep -q -- '-DFLUTTER=ON' "$gradle_module"; then
     wcf_run sed -i.wcf-orig 's/"-DTW_UNITY_BUILD=ON"/"-DTW_UNITY_BUILD=ON", "-DFLUTTER=ON"/' "$gradle_module"
     grep -q -- '-DFLUTTER=ON' "$gradle_module" || wcf_die "could not add -DFLUTTER=ON to $gradle_module (upstream's cmake arguments line changed?)"
     rm -f -- "$gradle_module.wcf-orig"
   fi
   wcf_log "gradle cmake arguments: $(grep -o 'arguments .*' "$gradle_module" | head -1)"
   ```
   (`sed -i.ext` is the bash-3.2/BSD-compatible form; the file lives in the checkout, which `git` later sees as modified — that is expected and harmless in CI.) Also read `cmake/StandardSettings.cmake:71` in the reference tree and report what else `FLUTTER` toggles there; if it changes anything beyond visibility that matters (deployment target, linkage), say so — do not work around it.
   Update the script's header comment (the paragraph that explains what we change in upstream's tree, near the top) to mention this second edit; and `tools/native_build/README.md`'s `build_android.sh` row with one clause: "passes `-DFLUTTER=ON` so the TW* C API is exported (upstream hides it on Android by default)".
2. `bash -n tools/native_build/build_android.sh`; `shellcheck` if present (no new warnings). Dry-check the sed against the reference tree without modifying it: `sed 's/"-DTW_UNITY_BUILD=ON"/"-DTW_UNITY_BUILD=ON", "-DFLUTTER=ON"/' /Users/yossefebrahim/Work/wallet-core-package.worktrees/W5-integration/third_party/wallet-core/android/wallet-core/build.gradle | grep -n FLUTTER` must print the patched line. `git diff --stat` must show only the two files.
3. Commit: `git add tools/native_build/build_android.sh tools/native_build/README.md`; message "native_build: pass -DFLUTTER=ON so the Android .so exports the TW* C API"; body "build-native.yml run 37155340955: the AAR's libTrustWalletCore.so exported 27 of 464 TW* functions — upstream's cmake/StandardSettings.cmake hides C++ symbols unless FLUTTER is set (its own flutter-build passes -DFLUTTER=ON). One-token patch of android/wallet-core/build.gradle in the checkout, logged. Owner-authorized Phase C fix." + blank line + trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. `git push origin main` (plain; STOP on rejection). Wait 20 s, then
   `gh workflow run build-native.yml --ref main -f upstream_tag=4.8.0 -f upstream_commit=d692ac27749d0c615e17c751b70ab4f0aa75c59b -f artifact_set_id=as_4.8.0_001 -f xcode_version=26.3.0 -f publish_release=false`
   Wait 30 s; paste `gh run list --workflow=build-native.yml --limit 3` and the new run URL.
No rebase/reset/checkout/stash/amend/tag/force, no `publish_release=true`, no second dispatch, no other file, no other agent.
</task>
<structured_output_contract>Report: the diff; what StandardSettings.cmake:71 toggles; the dry-run sed line; commit hash; push output; dispatch output + run id/URL; run list; anything failed/skipped.</structured_output_contract>
