<task>
FMT-3.13 — mechanical formatting after a Dart SDK upgrade. No design, no logic change.

The machine's Flutter was upgraded to 3.47.5 (Dart 3.13.4). The new `dart format` changes the layout of a few existing files, so the repository gate `melos run format:check` now fails. Reformat exactly the affected files in three working trees. Formatting only: do not change any token, comment text, or behaviour.

Trees (absolute paths):
  A = /Users/yossefebrahim/Work/wallet-core-package.worktrees/W3-integration
  B = /Users/yossefebrahim/Work/wallet-core-package.worktrees/T1.11
  C = /Users/yossefebrahim/Work/wallet-core-package.worktrees/T1.14

In EACH of A, B and C, do this:
  1. `export PATH="$PATH:$HOME/.pub-cache/bin"` then `melos bootstrap` (this may rewrite `pubspec.lock`; that is expected).
  2. Run `dart format --output=none .` from the tree root and note every line starting with `Changed`.
  3. Run `dart format <file>` on exactly those files and no others. Do not format files under any `lib/src/generated/` directory by hand: if a generated file is listed, STOP and report it instead of formatting it.
  4. Run `melos run format:check` (must report 0 changed), `melos run analyze`, and `melos run test`. If `dart analyze` crashes once with `SocketException … www.google-analytics.com`, that is telemetry, not code: run it again.

Rules: touch no file other than the ones `dart format` lists and `pubspec.lock`. Do not run `git add`, `git commit`, `git push`, `git checkout`, `git stash`, `git reset` or any git command that writes. Do not start another agent session. Do not write outside these three trees.

Report, per tree: the list of files reformatted, whether `pubspec.lock` changed, and the tails of the three gate commands with test counts. Say explicitly if any listed file was under a `generated/` directory or if any gate is not green.
</task>
