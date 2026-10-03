# `eval/option2` — DECISION-2 Option 2 evaluation

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not
affiliated with or endorsed by Trust Wallet.

**Evaluation branch only** (T1.9). Nothing here merges unless Option 2 wins
DECISION-2 at the D1a debate. The findings are in
[`docs/decisions/DECISION-2-option2.md`](../../docs/decisions/DECISION-2-option2.md).

Option 2 is conventional platform packaging: `wallet_core_flutter_native` is an
FFI plugin whose `android/build.gradle` packages each ABI's library from a
checksum-verified cache, and whose `ios/wallet_core_flutter_native.podspec`
vendors a `TrustWalletCore.xcframework` produced, at `pod install`, from
checksum-verified artifacts.

## What is here

| Path | What |
|---|---|
| `run_eval.sh` | Runs PRD §12.2 steps 1–11 for every target with an input on the machine, through `tools/packaging_eval`, and renders the table. `--help` for flags. |
| `eval_manifest.json` | **Evaluation-only.** A copy of the root `compat_manifest.json` whose Apple rows and identity are taken from the DECISION-14 §5.1 records of the locally built set `as_4.8.0_000` (`third_party/wcf-native-all/records/`). Never published, never shipped. |
| `consumer/` | A `flutter create` app plus two dependencies and one integration test. See below for exactly what changed after `flutter create`. |
| `tool/eval.dart` | Helpers `run_eval.sh` needs that are not measurements: build the eval manifest, read its identity, write the wrong-digest fixture, append an evaluation-owned result row. |
| `results/` | `results.jsonl` (the rows) and `table.md` (the rendered table), rewritten by every run and never edited by hand. Machine-specific path prefixes are rewritten to `$OUT`, `<repo>` and `~` before rendering. The same run rewrites the generated results block of `DECISION-2-option2.md` §2. |

## The evaluation manifest

Generated once, by hand, and reviewed:

```
dart eval/option2/tool/eval.dart make-manifest --root compat_manifest.json \
    --records third_party/wcf-native-all/records --out eval/option2/eval_manifest.json
```

It is the integrity root of the evaluation: `run_eval.sh` never regenerates it
from `third_party/`, which is untrusted input. Three values are not what a
published set would carry, and each says so in the validator's own grammar:

- `identity.build_workflow` and every Apple row's `build_workflow` are
  `https://local-build.eval-only.invalid/as_4.8.0_000`. The records say
  `"local"`; the validator requires an https URL once a digest is real; `.invalid`
  (RFC 6761) never resolves.
- `retention.primary` is `https://eval-only.invalid/native-4.8.0-000`, never
  contacted: every fetch in the evaluation is `--offline` from the vendored set.
- The Android rows stay `TBD-T1.2` (no Android artifact exists), and the root
  manifest's `ios/TrustWalletCore.xcframework.zip` row is dropped, because the
  local set ships dylibs and the iOS plan prefers that row whenever it is listed.

`dart run tools/manifest/bin/validate.dart eval/option2/eval_manifest.json`
passes.

## The consumer app

Created with Flutter **3.47.5** (Dart 3.13.4), from an empty `HOME` so that
`flutter create` finds no keychain identity and writes no `DEVELOPMENT_TEAM`
into `ios/Runner.xcodeproj/project.pbxproj`:

```
HOME=<empty dir> flutter create --no-pub --platforms=android,ios --org dev.wcf.eval \
    --project-name wcf_eval_option2 consumer
```

in `$TMPDIR` and copied here without the IDE files (`.idea/`, `*.iml`) that the
repository ignores anyway, because this session's sandbox refused `flutter
create`'s `.idea/` writes inside the repository. The 3.47.5 template sets iOS
15.0, `sdk: ^3.13.4`, AGP 9.1.0, Kotlin 2.4.0 and Gradle 9.3.1.

**Why 3.47.5.** Flutter 3.44.1 could not build any iOS app on this machine's
Xcode 27.0, an empty one included: its template set iOS 13.0 (macOS 10.15),
and Xcode 27.0 accepts deployment targets 15.0–27.0 (macOS 12.0–27.0). The
evaluation was regenerated and re-run on 3.47.5. `run_eval.sh` reads the
toolchain at run time (rows `min-version` / `host/toolchain` and `host/xcode`).

Changed after `flutter create`:

| File | Change |
|---|---|
| `pubspec.yaml` | added `wallet_core_flutter_bindings: 0.0.1`, `wallet_core_flutter_native: 0.0.1`, and the `integration_test` and `flutter_driver` SDK dev dependencies |
| `integration_test/symbol_lookup_test.dart` | new (carried over unchanged from the 3.44.1 consumer) |
| `test_driver/integration_test.dart` | new: the `integration_test` package's standard driver, for release-mode runs — `flutter test` has no `--release` option, so `run_eval.sh` runs release through `flutter drive` |
| `.gitignore` | added `pubspec.lock` and `pubspec_overrides.yaml` |
| `pubspec.lock` | not copied in (it would describe the pre-edit dependencies) |

No native file was edited: no Podfile (Flutter generates it at the first iOS
build, in the working copy), no Gradle file, no Xcode project.

`run_eval.sh` never builds this directory in place. It copies it to
`$TMPDIR/wcf-eval-option2/consumer`, writes a `pubspec_overrides.yaml` there
pointing at staged copies of the two packages, and builds the copy — so `pod
install` writes the xcframework under `$TMPDIR`, never into `packages/`.
Hosted consumption (step 11) is measured separately by
`tools/packaging_eval/bin/consumer_gen.dart`.

The integration test loads the library through the loader's default
locations, records which one provides `wcf_build_info`, runs `verifyIdentity`
against the identity injected from `eval_manifest.json`
(`--dart-define=WCF_EXPECT_ARTIFACT_SET_ID/WCF_EXPECT_UPSTREAM_COMMIT`),
resolves every name in `boundFunctionNames` and `exportedTwFunctionNames` plus
`wcf_build_info`, and calls `TWAnyAddressIsValid` on EIP-55's checksummed test
address.

## The wrong-digest fixtures (step 7)

`run_eval.sh` writes `$TMPDIR/wcf-eval-option2/eval_manifest.flipped.json`: the
evaluation manifest with the simulator dylib's `sha256` changed in its last hex
digit, and its `asset_name` changed to match, so the manifest still validates
and only the bytes disagree. With it, `pod install` must fail with the fetch
tool's mismatch report, and an Xcode build after a good `pod install` must fail
in the pod's `[CP-User] Verify TrustWalletCore.xcframework against the manifest`
phase. With the package's own shipped manifest (all `TBD-`), `pod install` must
fail with the manifest gate's blockers.

The offline half of step 7 is measured, not assumed. The builds' artifact
cache does not exist until their first `pod install` fills it, so that install
obtains the set from the vendored directory (the preflight verifies
`third_party/` into a cache of its own). A separate clean `pod install` runs
under `sandbox-exec` with every outbound connection denied, once a probe shows
the profile applies on the host. The probe is `tool/no_net_probe.sh`: the same
`nc -v -z` connect to a closed loopback port must say "Connection refused" run
plainly and "Operation not permitted" under the profile. Where it does not (a
nested sandbox, no `sandbox-exec`), that row is `unmeasured` with both outputs.
`tool/no_net_probe_test.sh` checks the classification and runs in the
preflight. An online `pub get` makes the
offline rows `unmeasured`.

## Running it

```
eval/option2/run_eval.sh                 # everything this machine can run
eval/option2/run_eval.sh --no-xcode      # stop the iOS side at pod install
```

It writes only `eval/option2/results/`, the block between
`<!-- BEGIN run_eval.sh results -->` and `<!-- END run_eval.sh results -->` in
`docs/decisions/DECISION-2-option2.md`, and `$TMPDIR/wcf-eval-option2/`, plus
the per-user caches the tools it drives always use.
