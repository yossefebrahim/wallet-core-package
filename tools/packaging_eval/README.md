# `tools/packaging_eval` — the packaging measurement harness

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not
affiliated with or endorsed by Trust Wallet.

One set of measurement commands, shared unchanged by the two DECISION-2
packaging evaluations — T1.8 (build hooks) and T1.9 (Gradle/podspec) — over
whatever artifacts and consumer apps each of them produces. Nothing here knows
what a build hook or a podspec is; it measures files and app bundles and renders
the single results table both `DECISION-2-option1.md` and
`DECISION-2-option2.md` embed.

This is build-time tooling. It ships in no package, it is a workspace member
only so the gates see it, and a run writes nothing inside the repository:
results, scratch copies and generated consumer apps all go under `$TMPDIR`.

## Running it

```sh
melos run packaging:measure
```

runs every measurement whose input exists on the machine, writes
`results.jsonl` and `table.md` under
`${WCF_PACKAGING_OUT:-${TMPDIR:-/tmp}/wcf-packaging}`, and prints the table.
`--skip-consumer-gen` drops PRD §12.2 step 11, which costs about a minute of
`flutter create` and `flutter pub get`.

Each measurement is also a standalone command with `--help`, so an evaluation
can run one check against one artifact and append the row to its own results
file:

```sh
dart run tools/packaging_eval/bin/size.dart --artifact <lib> --target <id> --out results.jsonl
dart run tools/packaging_eval/bin/report.dart results.jsonl --out table.md
```

## The commands, and the system command behind each

| Command | PRD §12.2 | What it measures | The exact system command |
|---|---|---|---|
| `bin/symbols.dart` | step 4 | Exported symbols of the shipped library reconciled both ways against the canonical list, per architecture, plus `wcf_build_info` presence | `tools/native_build/check_exports.sh --binary <lib> --symbol-list <derived> --format macho\|elf [--nm <llvm-nm>]` |
| `bin/size.dart` | step 5 | Size per artifact, thin-slice sizes of a universal Mach-O, sha256/size cross-check against the DECISION-14 §5.1 record, and the app-size delta between a baseline app and one with the SDK | `wc -c <lib>` ; `lipo -detailed_info <lib>` ; `lipo -info <lib>` ; `shasum -a 256 <lib>` |
| `bin/min_version.dart` | step 6 | The evidence step 6 is answered from: the host toolchain and the three packages' declared `environment:` constraints | `flutter --version --machine` ; the packages' `environment:` blocks |
| `bin/alignment.dart` | step 8 | 16 KB alignment, both halves: every ELF `LOAD` segment at `0x4000`, and the APK's uncompressed `.so` entries on 16 KB boundaries | `tools/native_build/check_alignment.sh --binary <so> --readelf <llvm-readelf>` ; `zipalign -c -P 16 -v 4 <apk>` |
| `bin/libcxx_conflict.dart` | step 9 | How the packaging option resolved two contributors that each bundle `lib/<abi>/libc++_shared.so`: a Gradle duplicate failure, a `pickFirst` rule, a single copy, or a version conflict | classifies `flutter build apk 2>&1 \| tee gradle.log` — see “The fixture plugin” below |
| `bin/ios_archive.dart` | step 10 | Per slice: minimum deployment target, exported-symbol visibility and counts, install name, `LC_RPATH`, linked libraries, code-signing state, and a required-reason API scan; across a set of libraries, the symbols defined in more than one of them | `vtool -arch <a> -show-build` ; `nm -gU -arch <a>` ; `nm -u -arch <a>` ; `otool -D/-l/-L -arch <a>` ; `codesign -dv` |
| `bin/consumer_gen.dart` | step 11 | A fresh Flutter app that depends on the three packages as **hosted** packages, never by path | `flutter create` ; `flutter pub get` against a loopback package repository |
| `bin/report.dart` | all | Renders the table: rows are the eleven steps, columns are the targets, cells are `pass`/`fail`/`skip`/`unmeasured` with the measured value and a footnote pointing at the command that produced it | — (pure) |
| `bin/measure_all.dart` | all | Runs every measurement with a real input on this machine and renders the table | the above |

`symbols` and `alignment` **call** `tools/native_build/`'s gate scripts rather
than reimplementing them, so the packaged library is checked by the same code
that checked the built artifact. The `check_exports.sh` symbol list is derived
at run time from
`packages/wallet_core_flutter_bindings/lib/src/generated/inventory.json` — the
464 `TW*` functions it records as declared and bound — and written to a temp
file. No copy of the list lives here: a hand-maintained one goes stale silently.

## What is real on this machine today, and what is `unmeasured`

A check that cannot run reports `unmeasured` and carries the exact command that
will produce it once the input exists. It never reports `pass`.

**Measured today**

| Row | Input |
|---|---|
| `symbols`, `size`, `ios-archive` on `ios/arm64`, `ios-simulator/arm64_x86_64`, `macos/arm64_x86_64` | the relinked artifacts under `third_party/wcf-native-all/` (git-ignored; T1.2 built them here) with their per-artifact records |
| `symbols`, `size`, `ios-archive` on `upstream/ios-arm64`, `upstream/ios-arm64_x86_64-simulator` | upstream's own `WalletCore.xcframework.zip` under `${WCF_UPSTREAM_CACHE:-~/.cache/wcf-upstream}/4.8.0/` — the library upstream users ship today |
| `ios-duplicate-symbols` on `ios/arm64` | our relinked device dylib against upstream's device slice |
| `alignment` (ELF `LOAD`) on `ndk/arm64-v8a`, `ndk/x86_64` | the NDK's own `libc++_shared.so` — the only real 64-bit ELF here, and the very file step 9's conflict is about |
| `min-version` on `host/toolchain` | `flutter --version --machine` and the three pubspecs |
| `consumer-gen` on `consumer/pub` | the three workspace packages, staged and served over loopback |

**`unmeasured` until an Android artifact exists.** No Android `.so` exists
anywhere: upstream publishes none and this machine can build none (no `cmake`,
no Rust toolchain), so `symbols` and `size` for `android-*`, `alignment` on our
own `.so`, `alignment-apk`, and `libcxx-conflict` all wait on the CI build
DECISION-9 §4 describes.

**`unmeasured` until a consumer app is built.** Steps 1, 2, 3, 6's floor, 7,
`app-size-delta`, and `ios-archive-link` need an app built and run by the
evaluation on a device or an emulator. So does the runtime half of step 4:
`DynamicLibrary.lookup` over the full 464 names is T1.7's `symbolLookupAll`,
run on device by the evaluation; the harness records the row and the command
and does not run apps.

`melos run packaging:measure` on this machine today produces 26 rows.

## How T1.8 and T1.9 call it

Both evaluations build their own consumer app under `$TMPDIR` and then point
these commands at what they produced, appending to one results file:

```sh
OUT="${TMPDIR:-/tmp}/wcf-eval-option1"

# per built library
dart run tools/packaging_eval/bin/symbols.dart \
    --artifact "$OUT/app/.../libTrustWalletCore.so" --format elf \
    --nm "$ANDROID_NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-nm" \
    --target android-device-arm64-v8a/release --out "$OUT/results.jsonl"

dart run tools/packaging_eval/bin/alignment.dart \
    --binary "$OUT/app/.../libTrustWalletCore.so" \
    --target android-device-arm64-v8a/release --out "$OUT/results.jsonl"

dart run tools/packaging_eval/bin/alignment.dart --apk "$OUT/app-release.apk" \
    --target android-device-arm64-v8a/release --out "$OUT/results.jsonl"

# per built app
dart run tools/packaging_eval/bin/size.dart \
    --baseline-app "$OUT/baseline.apk" --sdk-app "$OUT/app-release.apk" \
    --target android-device-arm64-v8a/release --out "$OUT/results.jsonl"

dart run tools/packaging_eval/bin/libcxx_conflict.dart \
    --gradle-output "$OUT/gradle.log" \
    --target android-device-arm64-v8a/debug --out "$OUT/results.jsonl"

# the table both option documents embed
dart run tools/packaging_eval/bin/report.dart "$OUT/results.jsonl" \
    --out docs/decisions/evidence/DECISION-2-option1-table.md
```

Rows an evaluation measures itself — a device run, a release launch, an offline
install — are written as result rows with the same schema and passed to
`report.dart` alongside; the step catalogue in `lib/steps.dart` already declares
them, so an unwritten row renders as `unmeasured` with its command rather than
as a gap.

## The results-row schema

One JSON object per line (JSON Lines). `report.dart` reads any number of these
files, or directories of them.

```json
{
  "check":   "size",
  "target":  "ios/arm64",
  "status":  "pass",
  "values":  {"size_bytes": 19721208, "summary": "18.81 MiB"},
  "command": "wc -c … ; lipo -detailed_info … ; shasum -a 256 …",
  "notes":   ""
}
```

- `check` — the measurement family: `size`, `app-size-delta`, `symbols`,
  `symbols-runtime-lookup`, `alignment`, `alignment-apk`, `libcxx-conflict`,
  `ios-archive`, `ios-duplicate-symbols`, `ios-archive-link`, `min-version`,
  `min-version-floor`, `consumer-gen`, `consumer-build`, `run-on-target`,
  `release-launch-and-sign`, `offline-install`.
- `target` — the column, as one flat string, so the schema has no second axis:
  an artifact slice (`ios/arm64`), an app target and configuration
  (`android-emulator-x86_64/release`), or a non-device target
  (`host/toolchain`, `consumer/pub`).
- `status` — `pass`, `fail`, `skip`, or `unmeasured`. `unmeasured` means the
  input does not exist on the machine that ran the check; the row still carries
  the command. Where several rows land in one cell the table shows the worst of
  them, ordered `fail` > `unmeasured` > `skip` > `pass`.
- `values` — the measured facts. `values["summary"]`, when present, is the short
  string the table cell shows; everything else is the detail behind it.
- `command` — the exact system command that produced the row, or, for an
  `unmeasured` row, the exact command that will produce it.
- `notes` — anything recorded but not judged: a code-signing state, an expected
  absence, a caveat.

## The local package repository (step 11)

`lib/local_pub_repository.dart` is a `dart:io` `HttpServer` on `127.0.0.1` and
an ephemeral port serving the two routes the pub client needs, and nothing else:

- `GET /api/packages/<name>` — the version listing, with `archive_url`,
  `archive_sha256`, and the embedded pubspec pub resolves against (it never
  downloads an archive to answer a version query).
- `GET /packages/<name>/versions/<version>.tar.gz` — the archive bytes.

Each of `packages/*` is copied to a staging directory under `$TMPDIR` with
exactly two edits — `resolution: workspace` and `publish_to` dropped, and every
dependency on a sibling rewritten to `hosted: http://127.0.0.1:<port>` at its
exact pinned version — then tarred and hashed. The consumer's `pubspec.yaml`
declares `wallet_core_flutter` with that `hosted:` URL, `flutter pub get` runs,
and the assertion is on the resulting `pubspec.lock`: all three packages
`source: hosted` with `description.url` equal to the local repository, and no
`path` entry anywhere in the lock. A path dependency resolves differently from a
published one, so an evaluation that only ever tested `path:` has not tested
what a consumer gets.

Nothing in the three packages reaches this server, or any network, at runtime
(AGENTS.md rule 3): it is build-time tooling on loopback.

## The fixture plugin (step 9)

`fixtures/libcxx_plugin/` is a stripped `flutter create --template=plugin
--platforms=android` skeleton whose only job is to bundle a second copy of
`libc++_shared.so` and so create the collision step 9 is about. The `.so` files
are **not committed** — they are 1 MB per ABI and they are the NDK's file.
Materialise them before a build:

```sh
tools/packaging_eval/fixtures/libcxx_plugin/tool/materialize_libcxx.sh
```

It copies `$ANDROID_NDK`'s own `libc++_shared.so` into
`android/src/main/jniLibs/<abi>/`, which is git-ignored. Then add the fixture
plugin and the SDK to the consumer app, build, and feed the log to
`bin/libcxx_conflict.dart`.

## Tests

```sh
dart test          # from tools/packaging_eval, or via `melos run test`
```

The parsers are unit-tested against saved real tool outputs under
`fixtures/tool_output/`, whose README tables the provenance of each file and
names the two synthetic ones. Tests that need a real artifact, the NDK, Xcode's
tools, or `flutter` run for real when it is there and skip with a message when
it is not.

The PRD §12.2 step 11 acceptance test in `test/consumer_gen_test.dart` is tagged
`slow` (it runs `flutter create` and `flutter pub get`) but is **not** excluded
from `melos run test`: it is the one thing this harness exists to prove.

## What this harness does not claim

It measures what is in front of it. It does not verify how an artifact was
produced: the artifacts it reads here are recorded as
`relinked_from_upstream_release_asset`, and PRD §12.4's independent-rebuild
demonstration has not happened. Artifact integrity is checked the one way it can
be — the sha256 in the DECISION-14 §5.1 record is compared against the bytes on
disk, and the manifest is checksum-pinned. Signing state is recorded, never
judged: our relinked dylibs are expected unsigned, and signing is the packaging
option's job. A required-reason API hit is reported as a fact — the app that
links the library needs a `PrivacyInfo.xcprivacy` declaring a reason for that
category — not as a failure.
