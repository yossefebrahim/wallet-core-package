# Repository rules

This file is the single source of the rules that govern every change made in this repository, by a human or by a delegated agent. It exists because `wallet_core_flutter` is built by several implementer sessions working in parallel worktrees, none of which shares memory with the others: the only things they reliably hold in common are their brief and this file. It restates, verbatim, the twelve constraints of [`docs/plan/EXECUTION_PLAN.md`](docs/plan/EXECUTION_PLAN.md) §2.4, the canonical gate table of §2.5, and the target repository layout of §3, so that a session which reads nothing else still knows what it may touch, what it may never write by hand, and what must be green before it reports done. `CLAUDE.md` contains only `@AGENTS.md` so that Claude Code loads this file; Codex reads it natively. Some rules below describe code that does not exist yet — they are the contract that code will be held to when it is written.

## Rules

1. Generated directories (`**/lib/src/generated/**`, `docs/capability_matrix.*`) are never hand-edited. Regenerate with the `melos run gen:*` scripts. CI fails on a clean-regeneration diff once `gen:check` exists (T1.3); until then this rule is enforced by review.
2. No cryptography, key derivation, or signed-transaction serialization is implemented in this repository. Every such operation calls upstream through the generated bindings. Encoding upstream's *signing-input* protobuf in Dart is allowed; producing the signed transaction bytes is not. Standard integrity hashing — SHA-256 of artifacts, manifests, and generated inputs, as PRD §12.3 requires — is allowed; it is verification, not wallet cryptography.
3. No network access at runtime in SDK, bindings, or native-loader code. Artifact download happens only in the native package's build-time tooling.
4. `package:wallet_core_flutter/wallet_core_flutter.dart` exports no `dart:ffi` type, no generated `TW*` class, and no protobuf class in any public signature. Within the SDK package, `advanced.dart` is the only file that may export them; a consumer who accepts the ownership responsibilities of PRD §11 may also import the bindings package directly.
5. Every native-backed object implements the disposal contract of PRD §11.2: explicit `dispose()`, finalizer detach, double-dispose no-op, `DisposedError` after disposal, `finally`-released temporaries.
6. Requests (`*TransactionRequest`, message requests) never contain key material. Family code encodes key-less inputs and parses results; only the signer injects keys (PRD §11.4 family boundary). Raw protobuf signing exists only under `advanced.dart`.
7. Every test vector entry cites its provenance: upstream file path and commit, a standard (BIP/SLIP) reference, or a published transaction hash.
8. Docs and README never use the words "zeroization", "secret-free", or "audited" about this SDK; never use "reproducible" about its artifacts until PRD §12.4's independent-rebuild demonstration is recorded (M3, T4.4); and never make a legal claim about AGPL. Package names never contain "trust". The disclaimer "Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet." appears wherever the project is described.
9. Do not add a dependency without listing it, with version, in the final report.
10. Do not run `git add`, `git commit`, or `git push`. Do not start another agent session. Leave all work uncommitted for the orchestrator.
11. Touch only the owned paths named in the brief. No unrelated cleanup, renames, or formatting sweeps.
12. The default public SDK surface never exposes the generated `CoinType`; use the stable coin/network facade (PRD §8, DECISION-11). Public resources of the default surface close asynchronously; synchronous `dispose()` exists only on internal wrappers and on the same-isolate objects of `advanced.dart`, which follow the internal ownership contract (PRD §11.2, §14.3). Signers take a set of `KeyLocator`s and return sealed `SignResult`s (PRD §10.2, DECISION-13).

## Canonical gates

| Script | What it runs | Device |
|---|---|---|
| `melos bootstrap` | pub get for all packages (orchestrator pre-warms) | no |
| `melos run analyze` | `dart analyze --fatal-infos` in every package | no |
| `melos run format:check` | `dart format --set-exit-if-changed .` | no |
| `melos run test` | unit tests in every package (no native library required unless the test says so) | no |
| `melos run test:native` | unit tests that load the real native library on the host (macOS) | no |
| `melos run gen:all` | `gen:ffi`, `gen:proto`, `gen:registry`, `gen:matrix` | no |
| `melos run gen:check` | `gen:all` then `git diff --exit-code` on generated paths | no |
| `melos run lint:public-api` | public-surface type check (T1.15) | no |
| `melos run vectors:validate` | inventory schema + provenance check (T0.8) | no |
| `melos run manifest:validate` | compat manifest schema + checksum presence (T0.7) | no |
| `melos run test:android` | `integration_test` on the running Android emulator | yes |
| `melos run test:ios` | `integration_test` on the running iOS simulator | yes |
| `tools/consumer_check.sh` | fresh `flutter create` consumer + add dependency + debug and release builds on both platforms | yes |

Until a script exists (Phase 0), briefs name the underlying `dart`/`flutter` commands instead.

## Target repository layout

```
wallet-core-package/                      (repo root; rename is DECISION-5's business, not the plan's)
├── AGENTS.md                             single source of repo rules (plan §2.4)
├── CLAUDE.md                             "@AGENTS.md"
├── README.md                             disclaimer, counts placeholder, pointers
├── LICENSE                               MIT
├── THIRD_PARTY_NOTICES.md                upstream Apache 2.0 NOTICE preserved
├── melos.yaml / pubspec.yaml             workspace + canonical gate scripts (plan §2.5)
├── analysis_options.yaml                 strict lints, shared
├── compat_manifest.json                  PRD §15.3 (T0.7)
├── packages/
│   ├── wallet_core_flutter/              public SDK
│   │   ├── lib/wallet_core_flutter.dart  typed surface only
│   │   ├── lib/advanced.dart             bindings + protobuf re-export
│   │   ├── lib/src/{core,wallet,address,errors,lifecycle,requests,signing,worker,families,keys,keystore}/
│   │   ├── test/  integration_test/
│   ├── wallet_core_flutter_bindings/
│   │   ├── ffigen.yaml
│   │   ├── lib/src/generated/{ffi,proto,registry}/   never hand-edited
│   │   ├── lib/src/memory/               TWData/TWString wrappers, Disposable, leak tracker
│   └── wallet_core_flutter_native/
│       ├── lib/                          locate/load/verify
│       ├── tool/                         artifact fetch + verify (build time)
│       ├── hook/                         Option 1 (build hooks)        — eval branch until DECISION-2
│       ├── android/  ios/                Option 2 (Gradle / podspec)   — eval branch until DECISION-2
│       └── src/shim/                     Approach B adapter            — eval branch until DECISION-1
├── tools/
│   ├── upstream/    pin + fetch sources at the manifest commit
│   ├── gen/         registry transform, proto generation script
│   ├── inventory/   header vs generated symbol inventory
│   ├── matrix/      capability matrix generator
│   ├── manifest/    manifest validator
│   ├── vectors/     inventory loader + validator
│   ├── probes/      SignJSON / compiler / message-signing availability probes
│   ├── lint/        public API type check
│   ├── diff/        API diff, behavioral diff (Phase 4)
│   ├── native_build/  scripts used by the CI native build
│   └── consumer_check.sh
├── test_vectors/
│   ├── inventory.yaml                    or one file per coin under test_vectors/<coin>/, merged by the loader
│   └── exclusions.yaml
├── example/                              consumer app (Phase 1)
├── eval/                                 throwaway consumer apps for packaging evaluations (eval branches only)
├── third_party/                          git-ignored upstream checkout at the pinned commit
├── docs/
│   ├── wallet_core_flutter_prd.md
│   ├── plan/                             this plan, PROGRESS.md, briefs/
│   ├── decisions/                        DECISION-n.md + evidence/
│   ├── security/                         memory_contract.md, threat model
│   ├── cookbook/                         Phase 3
│   └── capability_matrix.md              generated
└── .github/workflows/                    ci.yml, build-native.yml, upstream-watch.yml, reproducibility.yml
```

---

Status of every task, decision, and phase lives in [`docs/plan/PROGRESS.md`](docs/plan/PROGRESS.md) and nowhere else.
