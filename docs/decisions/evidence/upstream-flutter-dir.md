# Evidence — upstream `trustwallet/wallet-core` `flutter/` directory

Facts only. No interpretation; interpretation lives in [`DECISION-8.md`](../DECISION-8.md).

Every row cites the pre-fetched file it came from. All pre-fetched files live in
[`prefetch-2026-09-07/`](prefetch-2026-09-07/) and were captured by the orchestrator with the GitHub CLI on **2026-09-07**;
they are read-only inputs and are quoted here verbatim. This task had no network access
(`gh api repos/trustwallet/wallet-core/pulls/4412` was refused by the sandbox on 2026-09-07), so every fact below comes
from those files. Facts that could not be captured are listed in §7.

**Second capture, 2026-09-07 (same day, after the first pass of this file).** The orchestrator fetched five further files
in response to the gap list in §7: `upstream-pr-4412.md` (PR body, review, comments), `upstream-tools-flutter-build.sh`
(the script the Flutter CI job runs), `upstream-flutter-ci-history.tsv` (every commit touching `flutter-ci.yml`),
`upstream-flutter-ci-runs.tsv` (recent `master` runs and their conclusions) and `upstream-flutter-CHANGELOG.md`. Facts from
them are folded into §1–§6 below and cited by file name like the rest; §7 now lists only what remains unknown.

Reference point used throughout: **upstream tag `4.8.0` = commit `d692ac27749d0c615e17c751b70ab4f0aa75c59b`, released 2026-08-28**
(`prefetch-2026-09-07/tag-4.8.0.txt`, `prefetch-2026-09-07/SUMMARY.md` §"Release 4.8.0"; https://github.com/trustwallet/wallet-core/releases/tag/4.8.0).

---

## 1. Commit history of `flutter/`

| Commit | Date (UTC) | Author | Subject | PR |
|---|---|---|---|---|
| `11bd2fba` | 2025-06-09T06:34:02Z | gupnik | `Adds flutter bindings (#4412)` | #4412 |

- Source: `prefetch-2026-09-07/upstream-flutter-dir-commits.tsv` (the file contains exactly this one row).
  `prefetch-2026-09-07/SUMMARY.md` line 17 records the query result as: "Single commit touching `flutter/`: 11bd2fba,
  2025-06-09, gupnik, 'Adds flutter bindings (#4412)'. **No later commits.**"
- PR #4412 "Adds flutter bindings" by gupnik was **created 2025-06-04 and merged 2025-06-09 by `satoshiotomakan`**
  (`prefetch-2026-09-07/upstream-pr-4412.md` line 1; https://github.com/trustwallet/wallet-core/pull/4412).
  The merge date equals the commit date on `master` (2025-06-09). This resolves the five-day gap noted in the first pass
  of this file: the date `2025-06-04` in `upstream-flutter-prs.tsv` is the PR's **creation** date, not its merge date
  (see §5.2). Full PR body, review and comments: §5.4.
- The commit sha is recorded at 8 characters only; the full sha was not captured.
- Elapsed time between the only commit (2025-06-09) and tag 4.8.0 (2026-08-28): **14 months and 19 days**, during which
  upstream published releases at a rate the PRD records as "multiple releases per month"
  (PRD §2, `docs/wallet_core_flutter_prd.md` line 45).

## 2. Directory contents at tag 4.8.0

From `prefetch-2026-09-07/upstream-flutter-dir-tree.tsv` (https://github.com/trustwallet/wallet-core/tree/4.8.0/flutter),
11 entries, listed here with the type recorded in the TSV:

| Entry | Type | What is known about it |
|---|---|---|
| `.gitignore` | file | Contents not fetched. |
| `CHANGELOG.md` | file | **Fetched in full.** Complete contents: `## 1.0.0` / `- Initial version.` (`prefetch-2026-09-07/upstream-flutter-CHANGELOG.md`; https://github.com/trustwallet/wallet-core/blob/4.8.0/flutter/CHANGELOG.md). It has exactly one entry and records no version after 1.0.0. |
| `README.md` | file | Fetched in full; see §3. |
| `analysis_options.yaml` | file | Contents not fetched. |
| `bin/` | dir | Contents not fetched. By Dart package convention `bin/` holds executables run by `dart run`; the `flutter/README.md` documents `dart run` (§3), and `tools/flutter-build` invokes `dart run` under the label "Verifying the build" (§4.2). |
| `config.yaml` | file | Contents not fetched. `prefetch-2026-09-07/SUMMARY.md` line 18 annotates this entry "`config.yaml` (ffigen)", and `tools/flutter-build` runs `dart run ffigen --config config.yaml` from inside `flutter/` (§4.2), so it is the ffigen configuration consumed at build time. Its declared output path and header inputs were not captured. |
| `include` | **symlink** | Symlink target not captured (§7). |
| `lib/` | dir | Checked-in contents not fetched. At build time `tools/flutter-build` **copies the freshly built native library into this directory** (`build/libTrustWalletCore.dylib` on macOS, `.so` on Linux, `.dll` on Windows) before running ffigen (§4.2). |
| `pubspec.lock` | file | Contents not fetched. A checked-in `pubspec.lock` is present. |
| `pubspec.yaml` | file | Fetched in full; see §3. |
| `test/` | dir | Contents not fetched; number and names of test files unknown. Neither `flutter-ci.yml` nor `tools/flutter-build` invokes `dart test` (§4.1, §4.2). |

No `android/`, `ios/`, `macos/`, `linux/`, `windows/`, or `example/` directory appears in the listing, and no
`LICENSE`, `NOTICE`, or `.pubignore` file appears in it.

## 3. The package's self-description

### 3.1 `flutter/pubspec.yaml`

Source: `prefetch-2026-09-07/upstream-flutter-pubspec.yaml` (https://github.com/trustwallet/wallet-core/blob/4.8.0/flutter/pubspec.yaml). Verbatim:

```yaml
name: flutter
description: A sample command-line application.
version: 1.0.0
# repository: https://github.com/my_org/my_repo

environment:
  sdk: ^3.8.1

# Add regular dependencies here.
dependencies:
  ffi: ^2.1.4
  path: ^1.9.1
  # path: ^1.8.0

dev_dependencies:
  ffigen: ^19.0.0
  lints: ^5.0.0
  test: ^1.24.0
```

Facts readable from that file:

- `name: flutter`; `description: A sample command-line application.`; `version: 1.0.0`.
- The `repository:` key is present only as a commented-out placeholder pointing at `https://github.com/my_org/my_repo`.
- There is **no `publish_to:` key**, no `homepage:`, no `issue_tracker:`, no `documentation:` key.
- The SDK constraint is a **Dart** constraint (`sdk: ^3.8.1`); there is **no `flutter:` SDK constraint, no `flutter:` section,
  no `plugin:` section**, and the Flutter SDK is not a dependency.
- Runtime dependencies are `ffi ^2.1.4` and `path ^1.9.1` only. Dev dependencies are `ffigen ^19.0.0`, `lints ^5.0.0`,
  `test ^1.24.0`.

### 3.2 `flutter/README.md`

Source: `prefetch-2026-09-07/upstream-flutter-README.md` (https://github.com/trustwallet/wallet-core/blob/4.8.0/flutter/README.md).
The complete file is 24 lines. Verbatim:

````markdown
Wallet Core Bindings for Flutter

## Installation

1. Install Dart SDK:
   - Visit [Dart SDK installation page](https://dart.dev/get-dart)
   - Follow the instructions for your operating system

2. Install dependencies:
   ```bash
   dart pub get
   ```

## Usage

### Running the App
```bash
dart run
```

### Test
```bash
dart test
```
````

Facts readable from that file:

- The title line is `Wallet Core Bindings for Flutter` (plain text, not a Markdown heading).
- The three sections are Installation, Usage ("Running the App", `dart run`), and Test (`dart test`).
- The file contains **no** support statement, maintenance statement, stability or beta label, platform matrix,
  supported-version statement, licence header, publication or installation-from-pub.dev instructions, code sample,
  API listing, or description of how the bindings are generated or released.
- It refers to the Dart SDK only; it gives no Flutter SDK, Android, or iOS instructions.

### 3.3 Publication status

`prefetch-2026-09-07/pubdev-names.tsv` (pub.dev API queried 2026-09-07) records the packages found under the names checked.
The names recorded as TAKEN are `wallet_core` (0.4.1, "Fuse wallet core Dart library…"), `wallet_core_bindings`
(4.8.0, "Dart bindings for trust wallet core, used in Flutter and Dart."), `flutter_trust_wallet_core` (0.0.1) and
`trust_wallet_core` (0.0.6). No pub.dev package published by upstream from this directory was found in that check; the
directory's own package name is `flutter`, which was not among the names queried (§7).

## 4. CI coverage

### 4.1 The workflow

Source: `prefetch-2026-09-07/upstream-flutter-ci.yml`
(https://github.com/trustwallet/wallet-core/blob/4.8.0/.github/workflows/flutter-ci.yml). The workflow exists at tag 4.8.0
and is listed in `prefetch-2026-09-07/workflows-4.8.0.txt` among the 13 workflows present at that tag.

- `name: Flutter CI`.
- Triggers: `push` to branches `dev`, `master`; `pull_request` targeting `dev`, `master`.
  Concurrency group per workflow+ref with `cancel-in-progress: true`. Job condition `github.event.pull_request.draft == false`.
- Runner: `ubuntu-24.04`. Single job, `build`.
- Steps, in order: `actions/checkout` → `tools/install-sys-dependencies-linux` and `tools/install-rust-dependencies` →
  cache `build/local` → `tools/install-dependencies` (CC/CXX = clang) → `Swatinem/rust-cache` for `rust` →
  **`tools/generate-files native`** (code generation) → `dart-lang/setup-dart` pinned to **`sdk: '3.8.1'`** with pub-cache caching →
  `cd flutter && dart pub get && dart pub upgrade` → **`tools/flutter-build`** (CC/CXX = clang).
- The workflow's **only** `flutter/`-specific commands are `dart pub get` and `dart pub upgrade`; the last step invokes the
  repository script `tools/flutter-build`, quoted in full in §4.2.
- The workflow contains **no** `dart test`, `dart analyze`, `dart format`, `flutter test`, `flutter build`,
  `dart pub publish`, or artifact-upload step, and no Android or iOS job. It does not run on tags or on `release` events.
- For contrast, in the same pre-fetch, `prefetch-2026-09-07/upstream-kotlin-ci.yml` ("Kotlin CI", same push/PR triggers)
  ends with two steps, `tools/kotlin-build` **and `tools/kotlin-test`** ("Run Kotlin Multiplatform tests"), and
  `prefetch-2026-09-07/upstream-android-ci.yml` exists as a separate Android workflow.
- The action pins in `flutter-ci.yml` are byte-identical to those in `kotlin-ci.yml` for the actions both use:
  `actions/checkout@8e8c483db84b4bee98b60c0593521ed34d9990e8 # v6.0.1`,
  `actions/cache@9255dc7a253b0ccc959486e2bca901246202afeb # v5.0.1`,
  `Swatinem/rust-cache@779680da715d629ac1d338a641029a2f4372abb5 # v2.8.2`
  (compare `upstream-flutter-ci.yml` lines 18, 25, 38 with `upstream-kotlin-ci.yml` lines 18, 53, 36). §4.3 gives the
  commit that set those pins.
- The main README at 4.8.0 carries CI badges for iOS, Android, Linux, Rust, Wasm, Kotlin and Docker CI plus a SonarCloud
  gate (`prefetch-2026-09-07/upstream-README-4.8.0.md` lines 9–16). There is **no Flutter CI badge**.

### 4.2 What the build step runs — `tools/flutter-build`

Source: `prefetch-2026-09-07/upstream-tools-flutter-build.sh`
(https://github.com/trustwallet/wallet-core/blob/4.8.0/tools/flutter-build). Complete file, verbatim:

```bash
#!/bin/bash

set -e

mkdir -p build

pushd build
cmake .. -DFLUTTER=ON
make -j12
popd

if [ "$(uname -s)" == "Darwin" ]; then
    cp build/libTrustWalletCore.dylib flutter/lib/
elif [ "$(uname -s)" == "Linux" ]; then
    cp build/libTrustWalletCore.so flutter/lib/
elif [ "$(uname -s)" == "Windows" ]; then
    cp build/libTrustWalletCore.dll flutter/lib/
fi

pushd flutter

echo "Generating bindings..."
dart run ffigen --config config.yaml


echo "Verifying the build..."
dart run

echo "Done"

popd
```

Facts readable from that file:

- It configures the C++ build with a dedicated CMake switch **`-DFLUTTER=ON`** and builds with `make -j12`.
- It copies the built shared library into **`flutter/lib/`**, per host OS: `libTrustWalletCore.dylib` (Darwin),
  `libTrustWalletCore.so` (Linux), `libTrustWalletCore.dll` (Windows). It has no Android or iOS branch.
- It then generates the Dart bindings in-place: **`dart run ffigen --config config.yaml`**, echoing
  `"Generating bindings..."`. The bindings are therefore (re)generated from headers on every CI run.
- Its final step is **`dart run`**, echoed as **`"Verifying the build..."`** — it executes the `bin/` entrypoint.
- It runs **no `dart test`**, no `dart analyze`, no packaging, publishing, or artifact-upload step. Combined with §4.1,
  nothing in the captured Flutter CI path executes `flutter/test/`.

### 4.3 Commit history of `.github/workflows/flutter-ci.yml`

Source: `prefetch-2026-09-07/upstream-flutter-ci-history.tsv`. The file contains exactly two rows — the workflow has been
touched **twice since it was created**:

| Commit | Date | Author | Subject |
|---|---|---|---|
| `a8ae6746` | 2025-12-31 | Sergei Boiko | `fix(ethereum-abi): Fix Ethereum ABI type parsing recursion + chore actions and toolchain (#4597)` |
| `11bd2fba` | 2025-06-09 | gupnik | `Adds flutter bindings (#4412)` |

- The creating commit is the same `11bd2fba` that created `flutter/` (§1).
- The only subsequent change came through **PR #4597**, whose subject describes it as an Ethereum-ABI fix plus a
  "chore actions and toolchain" sweep (that PR is listed as MERGED in `upstream-flutter-prs.tsv`, created 2025-12-30, by
  `sergei-boiko-trustwallet`). No commit has touched `flutter-ci.yml` for a Flutter- or Dart-specific reason since
  creation.

### 4.4 Recent run conclusions on `master`

Source: `prefetch-2026-09-07/upstream-flutter-ci-runs.tsv` (captured 2026-09-07). Complete contents:

| Date | Conclusion | Head commit |
|---|---|---|
| 2026-09-01 | success | `40616462` |
| 2026-09-01 | success | `424c7c7e` |
| 2026-08-28 | success | `d692ac27` |

- All three most recent captured runs concluded **success**.
- The 2026-08-28 run's head commit `d692ac27` is the **tag 4.8.0 commit** (`d692ac27749d0c615e17c751b70ab4f0aa75c59b`),
  i.e. the Flutter CI job passed at the released tag.
- The most recent captured success is **2026-09-01**, six days before the capture date.

## 5. Issues and pull requests mentioning Flutter or Dart

Sources: `prefetch-2026-09-07/upstream-flutter-issues.tsv` and `prefetch-2026-09-07/upstream-flutter-prs.tsv`, both captured
2026-09-07. The exact `gh search`/`gh issue list` query string used by the orchestrator was not recorded; some listed titles
do not themselves contain "Flutter" or "Dart", so the query evidently matched issue/PR bodies as well as titles. States are
as of the capture date. The date column of both TSVs is the **creation** date, not the close or merge date: proved for
#4412 (TSV `2025-06-04`; `upstream-pr-4412.md` records "created 2025-06-04 merged 2025-06-09") and consistent with #4597
(TSV `2025-12-30`; its commit landed 2025-12-31 per §4.3).

### 5.1 Issues

| # | State | Created | Title | One line |
|---|---|---|---|---|
| 4638 | OPEN | 2026-01-29 | Flutter : FFI Symbol Lookup Failure with Wallet Core v4.5.0 .aar | A Flutter user built the `.aar` with `tools/android-build` at v4.5.0, generated Dart bindings with ffigen, and got `Failed to lookup symbol 'TWAnyAddressIsValid': undefined symbol`; asks whether an extra step, compilation flag or CMake setting is needed. |
| 4652 | OPEN | 2026-02-13 | How can i clear HDWallet & StoredKey mnemonic string in memory? | Memory-clearing question (matched the query; body not fetched). |
| 2086 | CLOSED | 2022-03-18 | Functions are not exposed to dart.ffi | Dart FFI symbol-visibility report. |
| 1791 | CLOSED | 2021-11-19 | Dart FFI support | Request for Dart FFI support. |
| 1797 | CLOSED | 2021-11-23 | [Readme] Add other non official platform / bindings | Request to list non-official bindings in the README. |
| 2013 | CLOSED | 2022-02-11 | [Android] change set(CMAKE_CXX_VISIBILITY_PRESET hidden) to set(CMAKE_CXX_VISIBILITY_PRESET default) | Symbol-visibility change request for the Android build. |
| 2034 | CLOSED | 2022-02-20 | `## Description` (title as captured) | Title captured as a template fragment; body not fetched. |
| 2219 | CLOSED | 2022-05-17 | TrustWalletCore had not exported spec256k1Extended & nistp256Extended interface. | Missing exported interface report. |
| 2139 | CLOSED | 2022-04-09 | Solana sign tokenTransfer crash with error: Invalid address string | Solana signing crash. |
| 3942 | CLOSED | 2024-07-12 | [ADA] Current Ada support coin selector? | Cardano coin-selector question. |
| 3852 | CLOSED | 2024-05-23 | [ADA Private Formate] How can i convert ada privateKey to Ed25519KholawPrivateKey or Ed25519PrivateKey? | Cardano key-format question. |
| 3290 | CLOSED | 2023-07-06 | [Build Error] Build Android Error on M2 about cMake. | Android build error on Apple silicon. |
| 2338 | CLOSED | 2022-06-22 | walletconnect doesn't work for trust wallet ios app | WalletConnect/app issue. |
| 961 | CLOSED | 2020-05-18 | JNI crash in wallet.core.jni.HDWallet.mnemonic() | JNI crash report. |
| 1866 | CLOSED | 2021-12-22 | Mnemonic phrase is invalid, but it is real Trust Wallet test wallet. | Mnemonic validation report. |

Detail on the one open Flutter-specific issue, #4638 (source: `prefetch-2026-09-07/upstream-issue-4638.md`,
https://github.com/trustwallet/wallet-core/issues/4638, opened 2026-01-29T20:24:02Z):
reporter's environment is Flutter 3.38.8, Dart 3.10.7, Wallet Core v4.5.0. The captured comment thread contains exactly two
comments, both by `patamarot-boop` on 2026-02-17, with the bodies `1,000,000,000` and `[]()`. **No maintainer reply appears
in the capture**; the issue was still OPEN 7 months and 9 days after it was filed (2026-01-29 → 2026-09-07).

### 5.2 Pull requests

| # | State | Created | Author | One line |
|---|---|---|---|---|
| 4412 | MERGED | 2025-06-04 | gupnik | "Adds flutter bindings" — the PR that created `flutter/`; merged 2025-06-09 (§1, §5.4). |
| 4634 | OPEN | 2026-01-23 | Toby1009 | "docs: update Flutter binding repository reference" — one-line README change; see §5.3. |
| 4854 | OPEN | 2026-08-28 | nikotw | "ci: harden workflows, Dockerfiles, and Android manifests". |
| 4637 | OPEN | 2026-01-29 | sergei-boiko-trustwallet | "chore(actions): Use TW actions proxy". |
| 4832 | OPEN | 2026-07-28 | Toby1009 | "feat(sui): accept the TypeScript SDK v2 transaction JSON". |
| 4597 | MERGED | 2025-12-30 | sergei-boiko-trustwallet | "fix(ethereum-abi): Fix Ethereum ABI type parsing recursion + chore actions and toolchain". |
| 4489 | CLOSED | 2025-09-03 | memtopia | "Update README.md" (closed, not merged). |
| 2033 | MERGED | 2022-02-20 | hnord-vdx | Added `__attribute__((visibility("default")))` to methods in `TWString.h`. |

### 5.3 PR #4634 — the exact README change

Sources: `prefetch-2026-09-07/upstream-pr-4634.md` and `prefetch-2026-09-07/upstream-pr-4634.diff`
(https://github.com/trustwallet/wallet-core/pull/4634). Opened 2026-01-23T02:37:05Z by Toby1009, title
"docs: update Flutter binding repository reference", state OPEN as of 2026-09-07 (7 months and 15 days open).
Body: "Update the README to point the Flutter binding to the correct repository. No code changes are included in this PR."
Files changed: `README.md` only. The complete diff:

```diff
@@ -117,7 +117,7 @@ Projects using Trust Wallet Core. Add yours too!

 There are a few community-maintained projects that extend Wallet Core to some additional platforms and languages. Note this is not an endorsement, please do your own research before using them:

-- Flutter binding https://github.com/weishirongzhen/flutter_trust_wallet_core
+- Flutter binding https://github.com/xuelongqy/wallet_core_bindings.git
```

That is: the community "Flutter binding" pointer is proposed to change from `weishirongzhen/flutter_trust_wallet_core` to
`xuelongqy/wallet_core_bindings.git`. Both are repositories outside the `trustwallet` organisation; **neither the current
line nor the proposed line points at the in-tree `flutter/` directory.**

### 5.4 PR #4412 — the PR that created `flutter/`

Source: `prefetch-2026-09-07/upstream-pr-4412.md` (https://github.com/trustwallet/wallet-core/pull/4412).
Header line, verbatim: `Adds flutter bindings | gupnik | created 2025-06-04 merged 2025-06-09 by satoshiotomakan`.

- **Body.** The PR uses the repository's PR template. Its only authored prose, under `## Description`, is one sentence:
  **"This PR generates flutter bindings for Wallet Core"**. Under `## How to test` it says **"Run tests across
  platforms"**. Under `## Types of changes`, where the template supplies commented-out options, the uncommented entry is
  **"New feature"**. Every checkbox in the template `## Checklist` is left **unchecked**, including
  "Add tests to cover changes as needed" and "Update documentation as needed".
- The body contains **no** statement about support, publication, pub.dev, versioning, a roadmap, platform coverage, or
  whether the directory is a sample; it names no follow-up work and links no issue.
- **Review.** One review is recorded: **`satoshiotomakan` APPROVED 2025-06-09: "LGTM, thanks!"**. The same account merged
  the PR the same day. No other reviewer appears, and no review discussion or change request is recorded.
- **Comments.** One comment, posted by the `github-actions` bot on 2025-06-04: a "Binary size comparison" table listing
  `aarch64-apple-ios` 14.01 MB, `aarch64-apple-ios-sim` 14.01 MB, `aarch64-linux-android` 18.48 MB,
  `armv7-linux-androideabi` 15.46 MB, `wasm32-unknown-emscripten` 13.16 MB. No human comment is recorded on the PR.
- **Authorship.** `gupnik` is **not a public member of the `trustwallet` GitHub organisation** — orchestrator check,
  2026-09-07, reported in the T0.4 review delta; this check is not itself captured in a file in
  `prefetch-2026-09-07/`. The organisation membership of `satoshiotomakan` was not checked (§7); the recorded fact is
  that they approved and merged the PR.

## 6. How the main README positions Flutter

Source: `prefetch-2026-09-07/upstream-README-4.8.0.md` (https://github.com/trustwallet/wallet-core/blob/4.8.0/README.md),
143 lines, at tag 4.8.0.

- A case-insensitive search of that file for "flutter" or "dart" returns **exactly one line**, line 120.
- Line 6–7 (intro): "Most of the code is C++ with a set of strict C interfaces, and idiomatic interfaces for supported
  languages: **Swift for iOS and Java (Kotlin) for Android**."
- Section "Using from your project" (lines 42–99) has subsections **Android**, **iOS** (SPM, CocoaPods), **NPM (beta)**,
  **Go (beta)**, **Kotlin Multipleplatform (beta)** [sic]. There is **no Flutter or Dart subsection**, and no
  "(beta)" Flutter entry.
- Section "Community" (lines 116–122), verbatim:

  > There are a few community-maintained projects that extend Wallet Core to some additional platforms and languages.
  > Note this is not an endorsement, please do your own research before using them:
  >
  > - Flutter binding https://github.com/weishirongzhen/flutter_trust_wallet_core
  > - Python binding https://github.com/phuang/wallet-core-python
  > - Wallet Core on Windows https://github.com/kaetemi/wallet-core-windows

- The Flutter pointer on line 120 therefore targets an **external repository** (`weishirongzhen/flutter_trust_wallet_core`),
  under the heading "community-maintained projects" and the sentence "Note this is not an endorsement". It does not
  reference `flutter/`.
- The README **never mentions the in-tree `flutter/` directory** (it is absent from the single "flutter" hit, line 120).
- The badge block (lines 9–16) lists iOS, Android, Linux, Rust, Wasm, Kotlin, Docker CI and SonarCloud; no Flutter CI badge.
- The README's own "Disclaimer" (lines 134–138) says: "The Wallet Core project is led and managed by Trust Wallet with a
  large contributor community…". Licence (line 142): Apache 2.0.

## 7. Facts still not available

Recorded so the orchestrator can fetch them if a stronger record is wanted. None were reachable from this worktree
(no network). The second capture of 2026-09-07 closed the earlier gaps about PR #4412, `tools/flutter-build`, the
`flutter-ci.yml` history and run status, and `flutter/CHANGELOG.md`; those facts now live in §1, §2, §4.2–§4.4 and §5.4.
What remains open:

1. The checked-in contents of `flutter/lib/**`, `flutter/bin/**`, `flutter/test/**`, `flutter/config.yaml`,
   `flutter/analysis_options.yaml`, `flutter/pubspec.lock`, `flutter/.gitignore`, and the target of the
   `flutter/include` symlink. In particular: what `bin/` does (it is what `dart run` — CI's "Verifying the build" step —
   executes, so whether Flutter CI exercises real `TW*` calls or only loads the library is unknown), and which headers
   and output path `config.yaml` gives ffigen.
2. What the CMake switch **`-DFLUTTER=ON`** changes in the native build (for example symbol visibility or target
   selection) — the `CMakeLists.txt` handling of it was not captured.
3. Whether any workflow other than `flutter-ci.yml` runs `dart test` in `flutter/`. Only `flutter-ci.yml`,
   `kotlin-ci.yml` and `android-ci.yml` of the 13 workflows at 4.8.0 were fetched; neither of the three does.
4. Any maintainer statement about Dart/Flutter in release notes, the developer portal
   (developer.trustwallet.com/wallet-core), Discord/Telegram, or the closed issues #1791 and #2086 (their comment threads
   were not fetched). PR #4412's own body and review contain no such statement beyond what §5.4 records.
5. Whether a package named `flutter` (the in-tree package's own `name:`) or any package under a trustwallet-controlled
   publisher exists on pub.dev.
6. Whether `satoshiotomakan` (who approved and merged PR #4412) is a public member of the `trustwallet` organisation.
7. The full 40-character shas of `11bd2fba` and `a8ae6746`.
8. Run history for `flutter-ci.yml` older than the three runs of §4.4 — whether the job has ever failed and been fixed,
   or has been green since creation.
