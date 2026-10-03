<task>
Pin the `crypto` dependency in `tools/probes/pubspec.yaml` from `any` to the version already resolved in the workspace lockfile. One-line change.
</task>

<context>
Repository: a melos workspace (`pubspec.yaml` at the root with `workspace:` + `melos:` sections). You are in the `T1.14` worktree. The tree is deliberately uncommitted; leave it so. Read `AGENTS.md` before touching anything: rule 10 forbids `git add/commit/push` and starting any other agent; rule 11 limits you to owned paths.

Current line 9 of `tools/probes/pubspec.yaml`: `  crypto: any`. The root `pubspec.lock` resolves `crypto` to `3.0.7` (confirm with `awk '/^  crypto:/{f=1} f&&/version:/{print; exit}' pubspec.lock`).
</context>

<edits>
Change `crypto: any` to `crypto: ^3.0.7` in `tools/probes/pubspec.yaml`. Nothing else.
</edits>

<constraints>
- Owned path: `tools/probes/pubspec.yaml` only. Do not touch `pubspec.lock` or any other file. If `dart pub get` / `melos bootstrap` rewrites `pubspec.lock`, that is acceptable only if the diff is limited to the `crypto` entry — otherwise `git checkout -- pubspec.lock` and report it.
- No git writes other than that lockfile restore, no new dependencies, no other agent session, one shell command per call.
</constraints>

<gates>
export PATH="$PATH:$HOME/.pub-cache/bin"
melos bootstrap
melos run analyze
melos run format:check
dart test tools/probes
</gates>

<report>
The diff (`git diff tools/probes/pubspec.yaml pubspec.lock`), gate tails with counts, and anything unexpected.
</report>
