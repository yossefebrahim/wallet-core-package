# DECISION-8 — Status and intent of upstream's in-tree `flutter/` directory

**Status:** **Recorded 2026-09-07 - "sample (dormant)"** (Decision section at the end). Recommended by T0.4, adjudicated at D0, uncontested.
**Options considered (PRD §22):** sample · abandoned · planned official SDK.
**Evidence:** [`evidence/upstream-flutter-dir.md`](evidence/upstream-flutter-dir.md), from the orchestrator's
2026-09-07 pre-fetch of `trustwallet/wallet-core` at tag `4.8.0` (= `d692ac27749d0c615e17c751b70ab4f0aa75c59b`,
released 2026-08-28), including the **second capture of the same day** (PR #4412 body and review, `tools/flutter-build`,
`flutter-ci.yml` history and run conclusions, `flutter/CHANGELOG.md`), which closed five of the eight gaps the first pass
listed. This task had no network; every fact is from those captures, and everything they do not cover is listed in
evidence §7.
**Governs:** PRD §2, §3 (landscape row), §4 (positioning), §17 (wording), §21 (risk register), README.

---

## 1. Context

PRD §4 positions this project as "an MIT-licensed, **unofficial** Dart SDK for Trust Wallet Core, with verified
capability and automated upstream tracking". Three of its four differentiators (licence, designed public surface,
verified capability) assume that upstream itself does not ship a supported Dart/Flutter SDK. PRD §2 states the risk
plainly: "if upstream ships an official Flutter SDK the value of this project shrinks to 'permissive license + DX'",
and marks as **[UNVERIFIED]** both (a) whether upstream intends to develop `flutter/` further and (b) whether the main
README's community "Flutter binding" pointer refers to the in-tree directory or to an external project. PRD §3's
landscape table asserts that the in-tree directory "tracks master".

Two things therefore hang on this decision. First, whether the §3 landscape row and the §2 [UNVERIFIED] markers can be
corrected. Second, what the README may say about upstream's Flutter situation without asserting anything about
upstream's intentions — every claim we publish about a third party has to be a dated, checkable fact (repo rule 8, PRD §17).

## 2. Evidence

| # | Fact | Where |
|---|---|---|
| E1 | `flutter/` has **exactly one commit**: `11bd2fba`, 2025-06-09, gupnik, "Adds flutter bindings (#4412)" (PR created 2025-06-04, merged 2025-06-09). No later commits — 14 months and 19 days of no change up to tag 4.8.0 (2026-08-28), a period in which upstream released multiple times per month. | evidence §1 |
| E2 | The package declares itself `name: flutter`, `description: A sample command-line application.`, `version: 1.0.0`, with the `dart create` template's commented-out `# repository: https://github.com/my_org/my_repo` line left in place. | evidence §3.1 |
| E3 | It is a **Dart console package, not a Flutter package**: `sdk: ^3.8.1` only, no `flutter:` SDK constraint, no `flutter:`/`plugin:` section, no Flutter dependency, no `android/`/`ios/`/`example/` directories; `bin/` plus a README documenting `dart run`. Runtime deps are `ffi` and `path`. | evidence §2, §3.1 |
| E4 | Its 24-line README ("Wallet Core Bindings for Flutter") gives install/run/test commands only — no support statement, stability or beta label, platform matrix, versioning or publication instructions, code sample, or description of how the bindings are generated. | evidence §3.2 |
| E5 | `flutter-ci.yml` **exists and runs on every push and PR to `dev` and `master`**: it builds native, runs `tools/generate-files native`, pins Dart 3.8.1, runs `dart pub get && dart pub upgrade` in `flutter/`, then `tools/flutter-build`. It contains **no test, analyze, format, publish or artifact step** and no Android/iOS job — while `kotlin-ci.yml`, from the same capture, ends with `tools/kotlin-build` **and `tools/kotlin-test`**. | evidence §4 |
| E6 | The `flutter-ci.yml` action pins are byte-identical to `kotlin-ci.yml`'s for the actions both use (checkout v6.0.1, cache v5.0.1, rust-cache v2.8.2) — the workflow is carried along by repo-wide maintenance sweeps. **Confirmed by E13.** | evidence §4.1, §4.3 |
| E7 | The main README at 4.8.0 mentions "flutter" or "dart" on **exactly one line** (120), under "Community" — "There are a few community-maintained projects… Note this is not an endorsement" — and it points at the **external** `weishirongzhen/flutter_trust_wallet_core`. "Using from your project" has Android, iOS, NPM (beta), Go (beta), Kotlin Multiplatform (beta) and **no Flutter/Dart entry**; there is no Flutter CI badge among the eight badges. The in-tree `flutter/` directory is **never mentioned in the README**. | evidence §6 |
| E8 | Open PR #4634 (Toby1009, 2026-01-23, docs-only, still open after 7 months 15 days) proposes changing that one line from `weishirongzhen/flutter_trust_wallet_core` to `xuelongqy/wallet_core_bindings.git` — one external project for another. Neither the current nor the proposed line points at `flutter/`. | evidence §5.3 |
| E9 | Issue #4638 (2026-01-29), a Flutter user's FFI symbol-lookup failure against the upstream `.aar`, was still **open with no maintainer reply** 7 months and 9 days later (only two junk comments from a third party). Earlier Dart requests #1791 (2021-11) and #2086 (2022-03) are closed. | evidence §5.1 |
| E10 | No pub.dev package published by upstream from this directory was found in the 2026-09-07 name check; the directory's own package name is `flutter`, and the three names this project plans are free. | evidence §3.3 |
| E11 | **PR #4412's own words.** The whole authored body is "This PR generates flutter bindings for Wallet Core", how-to-test "Run tests across platforms", type "New feature"; **every checklist box is unchecked**, including "Add tests to cover changes as needed" and "Update documentation as needed". It says nothing about support, publication, versioning, platforms, or a roadmap. One review: `satoshiotomakan` APPROVED "LGTM, thanks!" and merged it the same day; the only comment is the binary-size bot. `gupnik` is not a public member of the `trustwallet` org (orchestrator check, 2026-09-07; not captured in a file). | evidence §5.4 |
| E12 | **What CI actually does to `flutter/`** (`tools/flutter-build`): `cmake .. -DFLUTTER=ON` → `make` → copy the built `libTrustWalletCore.{dylib,so,dll}` into `flutter/lib/` → `dart run ffigen --config config.yaml` ("Generating bindings…") → **`dart run`, echoed as "Verifying the build…"**. No `dart test`, no analyze, no packaging or publish step, no Android/iOS branch. The bindings are regenerated from headers on every run; upstream's own label for the Dart step is *verifying the build*. | evidence §4.2 |
| E13 | `flutter-ci.yml` has **exactly two commits**: its creation (`11bd2fba`, 2025-06-09) and `a8ae6746`, 2025-12-31, Sergei Boiko, "…+ chore actions and toolchain (#4597)" — a repo-wide sweep. No commit has ever touched it for a Flutter- or Dart-specific reason. | evidence §4.3 |
| E14 | The three most recent captured `master` runs of Flutter CI **all concluded `success`**: 2026-08-28 at head `d692ac27` — the **tag 4.8.0 commit itself** — and two on 2026-09-01, six days before capture. | evidence §4.4 |
| E15 | `flutter/CHANGELOG.md` reads, in full: `## 1.0.0` / `- Initial version.` No entry has been added since. | evidence §2 |

## 3. Interpretation

Everything in this section is **inference** from §2. Upstream's only recorded first-person statement about `flutter/` is
PR #4412's one-sentence description (E11); it declares neither support nor a plan, so no reading below rests on a
maintainer's statement of intent.

### Reading A — it is a sample / developer aid

**For (very strong).** E2 is close to decisive on self-description: the package still carries the `dart create` template's
description string, "A sample command-line application.", and the template's placeholder `repository:` comment, 14 months
after it landed. E3 shows it is not even shaped like a Flutter package — no Flutter SDK dependency, no plugin section, no
platform folders; it is a Dart console program that loads a native library through `ffi`. E4 shows the README documents
how to run it, nothing else. E15 shows its changelog never moved past "Initial version".

E12 is what turns this from a reading into upstream's own description of the artefact: the CI script regenerates the
bindings with ffigen on every run and then executes `dart run` under the printed label **"Verifying the build…"**. That is
a **code-generation and link smoke check** — does the freshly generated Dart FFI surface still build and run against the
freshly built native library — and upstream says so in its own echo string. My first pass inferred this from the absence
of a test step; it is now sourced.

**Against (weak).** A pure throwaway would not usually get a dedicated workflow on every push and PR to two branches (E5),
nor a `-DFLUTTER=ON` switch in the native build (E12). E11 shows the addition was deliberate and reviewed: labeled a
"New feature", approved and merged by an account with write access to the repository (inference: merging requires write
access). And upstream's own word for the contents is "bindings", not "sample" (E11, E4) — the "sample" wording comes from
the pubspec's untouched template string (E2). The honest formulation is that the artefact is *called* bindings and is
*used* as a build check.

### Reading B — it is an abandoned experiment

**For (moderate).** E1 is the core fact: one commit, then nothing across roughly 14 releases-per-month months. E9 adds
that the one open, Flutter-specific bug report has sat unanswered by maintainers for over seven months, and E8 that a
one-line docs correction about the Flutter binding link has been open for over seven months. E11 adds that the creating
PR left "Add tests to cover changes as needed" and "Update documentation as needed" unchecked, and nothing has been added
since (E13, E15). Nobody is tending the Flutter-facing surface.

**Against (now stronger than "for").** "Abandoned" normally implies the thing has stopped working or been dropped.
E14 settles this: Flutter CI **passed at the 4.8.0 tag commit itself** (2026-08-28) and again on 2026-09-01, six days
before capture. The job is not merely present, it is **green on current `master`** — and because E12 shows it regenerates
the bindings with ffigen and runs the program against a freshly built library, its passing is a real signal that the
directory still works against today's C API. E13 shows the workflow has needed exactly one edit since creation, and that
edit was a repo-wide action/toolchain sweep, not a repair.

This also explains why zero commits is not the anomaly it first appears: the Dart bindings are **generated at build
time** (E12), so the checked-in scaffolding need not change as upstream's C API grows.

The accurate word is therefore **dormant**, not abandoned: unchanged since creation, unowned in the issue tracker, and
demonstrably still building and running in CI. In the first pass this was an inference with a stated caveat about
unknown job status; with E13 and E14 it is **confirmed from run data**.

### Reading C — it is a planned official SDK

**For (weak — slightly stronger than the first pass judged).** Four facts point this way, none decisive: the directory's
title claims "Wallet Core Bindings for Flutter" (E4); it has dedicated CI with a `-DFLUTTER=ON` native build switch
(E5, E12); PR #4412 was classified by its author as a **"New feature"** whose purpose is to "generate flutter bindings"
(E11); and a maintainer with write access reviewed, approved and merged it (E11). This was a deliberate, sanctioned
addition to the repository — not something that drifted in — which is what a first step toward an official binding would
also look like.

**Against (strong).** Upstream has a demonstrated, visible pattern for announcing bindings before they are mature — the
README carries "NPM (beta)", "Go (beta)", "Kotlin Multiplatform (beta)" under "Using from your project" (E7). `flutter/`
received **no such entry, no badge, and no mention anywhere in the README** in the 14 months after it landed. More
pointedly, the one place the README does say "Flutter" sends readers to a **third-party** repository under an explicit
"this is not an endorsement" (E7), and the only pending change to that line swaps in **another** third-party repository
(E8) — after 20 months of `flutter/` existing, upstream's docs-facing answer to "where is the Flutter binding?" is still
"someone else's". Nothing in the package looks publishable: name `flutter`, template description, version 1.0.0, no
`publish_to`/`homepage`/`repository`, no licence file in the directory, no publish step in CI, nothing on pub.dev
(E2, E5, E10), and a changelog frozen at "Initial version" (E15).

The second capture sharpens the "against" further. If an official SDK were being prepared, the 14 months after the merge
were when it would show: instead the creating PR's checklist for tests and documentation was never completed (E11), the
workflow was touched once and only by a sweep (E13), and the build script gained no test, packaging or publish step
(E12). A deliberate first step that is then left untouched for 14 months while remaining green is evidence of a **kept
build check**, not of a programme in progress.

### Verdict

The evidence supports **Reading A, qualified by B: `flutter/` is an in-tree Dart FFI binding used as a code-generation
and build smoke check, dormant since the day it was added and still green in CI.** Confidence, revised after the second
capture:

- *"Not a supported, published, or announced Flutter SDK as of 4.8.0 / 2026-08-28"* — **very strong** (was: strong).
  Nine independent artefacts agree (E2, E4, E5, E7, E8, E10, E11, E12, E15) and none contradicts it; the creating PR
  itself claims no support, publication or roadmap (E11).
- *"Dormant rather than deleted or abandoned"* — **strong, and now confirmed rather than inferred** (was: moderate). The
  first pass had to hedge because the job's pass/fail state was unknown; E14 shows Flutter CI green at the 4.8.0 tag
  commit and again on 2026-09-01, and E13 shows the workflow has been touched exactly once since creation, by a
  repo-wide sweep. The directory is unmaintained in the sense that nobody develops it, and maintained in the sense that
  it must keep building.
- *"Upstream is not planning an official Flutter SDK"* — **weak, and we still do not assert it.** This remains an
  argument from silence, and the second capture cuts slightly against complacency: PR #4412 was labeled a "New feature",
  approved and merged by an account with write access (E11), so the directory exists by decision, not by accident.
  Its body simply says nothing about what comes next. Internal roadmaps are not observable. What we can assert is the
  dated negative: at tag 4.8.0 upstream published no Dart/Flutter package and announced none.

**Nothing in the second capture contradicts the recommendation of §5**; the two facts that could have — a maintainer
statement of intent in PR #4412, or a failing/removed CI job — resolved as "no statement" and "green", which is exactly
what "sample, dormant, still building" predicts.

One further inference worth recording for §3 of the PRD: E8, plus the fact that the currently-linked
`flutter_trust_wallet_core` is the abandoned 2020 package of PRD §3, suggests upstream's community list is itself
stale-but-being-corrected — and that the correction, if merged, would point readers at `wallet_core_bindings`, our named
competitor. That raises, mildly, the value of PRD §4's "secondary opportunity" (being listed there) and the cost of not
pursuing it. No action here; noted for D0.

## 4. Consequences

### 4.1 For the PRD

1. **§3, landscape table.** The row `Upstream flutter/ directory | tracks master` is **factually wrong** and should be
   corrected to something like: *one commit (2025-06-09, PR #4412), unchanged at tag 4.8.0; unpublished; Dart console
   package, not a Flutter plugin; its bindings are regenerated by ffigen in CI, which was green at the 4.8.0 tag commit*.
   **[VERIFIED 2026-09-07]** (E1, E2, E3, E12, E14). Note for whoever edits the row: "tracks master" is wrong about the
   *directory*, but the **generated bindings do** track master, because CI regenerates them from current headers on every
   run (E12) — the row should not swing to the opposite error.
2. **§2, first [UNVERIFIED].** "whether that pointer refers to the in-tree `flutter/` directory or to an external
   project" is **resolved: an external project** (E7, E8) → mark **[VERIFIED 2026-09-07]**.
3. **§2, second [UNVERIFIED].** "whether upstream intends to develop it further" **stays [UNVERIFIED]**, but should now
   record the dated negative rather than an open question: no announcement, no README entry, no publication, and — with
   the creating PR now read in full — **no statement of intent in PR #4412 either**, only "This PR generates flutter
   bindings for Wallet Core" (E5, E7, E10, E11). The gap is now known to be a silence, not an unread document.
4. **§2's interpretation sentence** ("upstream has a Flutter/Dart *sample or in-tree binding*, but it is not a supported,
   published, production-ready Flutter SDK") is **confirmed** — it can drop its hedge and cite this record.
5. **§4 positioning is unchanged in substance.** No differentiator rests on upstream never shipping Flutter; the word
   "unofficial" remains exactly right, and E7 means we may accurately say upstream lists Flutter only as
   community-maintained. §4's "secondary opportunity" (a listing in that community section) survives and, per §3 above,
   is contested by PR #4634.
6. **§21 risk register.** Keep "upstream ships an official Flutter SDK" as a live risk with an unchanged severity — the
   evidence lowers its *imminence*, not its impact — and attach the §5 revisit triggers as its detection mechanism.

### 4.2 For the README's positioning sentence

Proposed wording, to sit under `## Status` in `README.md` (or wherever the project is described), **in addition to and not
in place of** the PRD §17 disclaimer, which stays verbatim and unedited:

> Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.
>
> As of upstream release 4.8.0 (2026-08-28), Trust Wallet Core ships official bindings for Swift, Kotlin/Java,
> JavaScript/WebAssembly, Go and Kotlin Multiplatform, and lists Flutter only under community-maintained projects; its
> repository contains an in-tree `flutter/` directory that is not published as a package.

**Refinement after the second capture:** the first draft of this sentence ended "…an unpublished in-tree `flutter/`
sample, which is not a released package". "Sample" is sourced — it is the pubspec's own description (E2) — but E11 shows
upstream's own word for the artefact is "bindings", so leaning on "sample" invites an argument we do not need to win.
The wording above states only that it is not published, which no reading disputes.

Why this wording:

- Every clause is a dated, checkable fact from evidence §3, §6 — the release, the binding list, the community listing,
  the absence of a published package. It asserts **nothing about upstream's plans or intentions**.
- It uses none of the four claim-words that repo rule 8 bans from docs about this SDK, makes no AGPL or other legal
  claim, and does not name or compare against the AGPL-licensed competitor.
- It says "not published as a package" — verifiable — rather than "abandoned", "unsupported" or "dead", which would be
  claims about upstream's commitment that we cannot source, and which E14 (CI green at the 4.8.0 tag) would in fact
  embarrass.
- It is dated in-line, so it ages honestly and the revisit triggers below have something concrete to invalidate.

Shorter one-sentence variant, if the README wants less: *"As of upstream 4.8.0 (2026-08-28), Trust Wallet Core publishes
no Dart or Flutter package and lists Flutter only under community-maintained projects."*

**Do not publish** (unsourceable or rule-8/§17 risks): "upstream abandoned Flutter"; "upstream has no plans for Flutter";
"the official Flutter binding"; any framing of this package as endorsed, recommended, or a successor to `flutter/`; any
quotation of the `flutter/` pubspec's "A sample command-line application." string as commentary on upstream's competence
(it is fine in this evidence file; it reads as a jab in a README).

### 4.3 For tasks

- **T3.x `upstream-watch.yml`** (repo layout, `.github/workflows/`) should watch the paths and conditions in §6 below, not
  only the release feed. Cheap concrete checks it now has baselines for: the sha list for `flutter/` (one entry, E1), for
  `.github/workflows/flutter-ci.yml` (two entries, E13), and the text of `tools/flutter-build` (E12).
- **T0.9 / §4's audit qualification** is untouched by this record.
- No code, packaging, or capability-matrix task changes as a result of DECISION-8.

## 5. Recommendation

**Unchanged by the second capture.** Record DECISION-8 as: **sample (dormant)** — upstream's `flutter/` is an in-tree
Dart FFI binding that CI regenerates and runs as a build smoke check ("Verifying the build…", E12), added in one commit
on 2025-06-09 and unchanged at tag 4.8.0; it is not published, not announced, not documented as supported, and not what
the main README's "Flutter binding" line refers to. It is dormant but **not broken**: Flutter CI was green at the 4.8.0
tag commit and on 2026-09-01 (E14). Treat "upstream ships an official Flutter SDK" as an open risk with no current
evidence for or against — noting that the directory was added deliberately as a maintainer-approved "New feature"
(E11) — monitored by the triggers below rather than re-researched.

Concretely: apply the six PRD edits of §4.1, adopt the §4.2 README wording (two-sentence form, as refined there), and add
the §6 triggers to the upstream watcher. Nothing in the plan is blocked on this record.

## 6. Revisit trigger

Reopen DECISION-8 if any of the following is observed upstream (each is mechanically checkable at a pinned tag):

1. **Any new commit under `flutter/`** after `11bd2fba` — especially one changing `flutter/pubspec.yaml`'s `name` or
   `description` away from `flutter` / "A sample command-line application.", or adding `publish_to`, `homepage`, or
   `repository`.
2. **A Dart/Flutter package published by a trustwallet-controlled publisher on pub.dev**, or a `dart pub publish` /
   package-upload step appearing in any upstream workflow.
3. **A Flutter or Dart entry appearing in the main README's "Using from your project" section** (including a "(beta)"
   entry), a Flutter CI badge appearing in the badge block, or the README beginning to reference the in-tree `flutter/`
   directory.
4. **`flutter-ci.yml` or `tools/flutter-build` gaining a test, analyze, packaging or publish step** — today the build
   script ends at `dart run` "Verifying the build…" (E12) — or a **third commit to `flutter-ci.yml` made for a
   Flutter-specific reason** rather than a repo-wide sweep (baseline: two commits, E13). Likewise a Flutter/Dart section
   appearing on developer.trustwallet.com/wallet-core.
5. **Any maintainer statement** about a Dart or Flutter SDK in release notes, an issue, a PR, or the developer portal —
   including a maintainer reply on issue #4638. (PR #4412's body and review contain none, E11, so this would be new.)
6. **Deletion of `flutter/` or of `flutter-ci.yml`**, **or Flutter CI going persistently red on `master`** — either would
   overturn the "dormant but still building" finding that E14 currently supports, in opposite directions.
7. **Merge of PR #4634** — doc-only, but it changes which third-party project upstream points Flutter users at, which
   feeds PRD §3's competitor tracking and §4's "community listing" opportunity.

Triggers 1–4 and the deletion half of 6 are diffable between two upstream tags and belong in the upstream watcher; the
CI-status half of 6 needs the runs API; 5 and 7 need a human look at the issue/PR feed.

---

## Decision

**Upstream's in-tree `flutter/` directory is a sample, dormant.** T0.4's evidence and the D0 debate agree, and no
contrary position was argued.

Consequences, now settled facts for later tasks:

- The README and PRD section 4 describe upstream as having **"an in-tree `flutter/` directory that is not published as
  a package"** - the one-sentence wording of section 4.2, which both the record and the debate preferred. No stronger
  claim about upstream's intent is made anywhere, because the "no plans" reading is weak and was deliberately not
  asserted.
- Revisit triggers 1-4 and the deletion half of 6 belong to **T4.3**'s upstream watcher. The CI-status half of 6 needs
  the runs API; 5 and 7 need a human look at the issue and PR feed.
- **PR #4634**, if merged, repoints upstream's Flutter users at the `wallet_core_bindings` competitor. That is a live
  input to PRD section 3's competitor tracking, not to this record.

Recorded **2026-09-07 by the orchestrator**, under the repository owner's standing authorization to keep Phase 0 moving while they were unavailable, and **subject to the owner's ratification** (`docs/plan/PROGRESS.md` -> Needs your eyes -> "Decisions recorded on your behalf"). The choice is reversible at the cost stated in the revisit trigger; nothing is published.
