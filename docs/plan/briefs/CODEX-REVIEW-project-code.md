<task>
You are an adversarial code reviewer for wallet_core_flutter, an unofficial MIT-licensed Dart/Flutter SDK over the open-source Trust Wallet Core library (not affiliated with or endorsed by Trust Wallet). This is a READ-ONLY review of the whole code base at /Users/yossefebrahim/Work/wallet-core-package on branch `main` (HEAD = merge of integration/W6, 2026-10-04): do not create, edit, or delete any file. Your only deliverable is your final message. You may run `dart analyze`, `dart test`, `flutter test`, `melos run <gate>` (they write only under .dart_tool/ and build/) and read-only git commands.

Goal: find real defects, contract violations, and security problems in the code that the project's own reviews missed. Assume the previous reviewers (docs/plan/reviews/*.md) were competent and look for what they did NOT check. Prefer a small number of confirmed, reproducible findings over a long list of style remarks.
</task>

<context>
Read first: AGENTS.md (the twelve rules and the gate table), docs/wallet_core_flutter_prd.md §8, §10, §11, §12, §14, §15 (ownership/disposal contract, signing model, loader identity), docs/decisions/DECISION-11.md, -12.md, -13.md, -14.md, docs/security/memory_contract.md, docs/architecture/lifecycle.md.
Code under review (all of it): 
  packages/wallet_core_flutter/lib/** and test/** (public SDK: session, worker-isolate engine, proxies, facades, requests, EVM encoder, Approach A signing)
  packages/wallet_core_flutter_bindings/lib/src/memory/** (TWData/TWString wrappers, Disposable, leak tracker), lib/registry.dart, ffigen.yaml (generated/ is machine output: review its generator inputs, not its content)
  packages/wallet_core_flutter_native/lib/** (locate/load/verify, identity checks, generated manifest), src/**, tool/**
  example/** (M0 flow app + seam tests)
  tools/lint/** (public-api lint, runtime-deps lint), tools/probes/**, tools/gen/** (proto.sh, registry transform), tools/native_build/** (build_android.sh, build_apple.sh, check_exports.sh, lib/common.sh), tools/consumer_check/**, tools/consumer_check.sh
  .github/workflows/ci.yml and build-native.yml
third_party/ is git-ignored and holds the upstream checkout + a host dylib so `melos run test:native` can run on this Mac.
</context>

<questions>
1. Isolate transport & lifecycle (packages/wallet_core_flutter/lib/src/{session,worker,lifecycle}/**): can any request reach the engine after close()? Can a reply be delivered after the deadline (DECISION-12: result dropped unposted, key-less `Failed(OperationTimeoutError)`)? Is `Timeline.now` monotonic use correct across isolates? Are there races between `_finishClosed`, pending completers, and the states stream (`_states.close().timeout(shutdownGrace)`)? Does any error path leak a native handle or a Dart copy of key material? Write out the concrete interleaving for each problem you claim.
2. Secret-bearing payloads (DECISION-12 §3.2, eight payloads): do CreateWallet, ImportWallet, ValidateMnemonic, ValidateMnemonicWord, SuggestMnemonicWords, MnemonicExported, MnemonicWordsSuggested actually follow the handling rules (no logging, no toString exposure, overwrite after send where specified, never in error messages/stack traces)? Check `toString`, `==`/hashCode, error wrapping, and any `debugPrint`/`log` call.
3. Rule 6 / DECISION-13: can a `*TransactionRequest` or `MessageRequest` carry key material through any path (constructor, copyWith, JSON/protobuf encoding, advanced.dart)? Does the key-less EVM encoder (requests/ + signing/) ever emit a `private_key` field, and is the injected-key path confined to the signer? Check the protobuf field numbers it writes against upstream's `Ethereum.proto` under third_party (field 15 `private_key`) and look for group-wrapping or repeated-field tricks the hostile-input suite (T2.12, not yet written) would use.
4. Memory layer (bindings/lib/src/memory/**): disposal contract PRD §11.2 items 1–7 — explicit dispose, finalizer detach, double-dispose no-op, DisposedError after disposal, finally-released temporaries, leak tracker. Is there any path where a finalizer runs on an already-freed pointer, or where `TWDataDelete`/`TWStringDelete` is called twice? Is the leak tracker safe in release mode?
5. Native loader (native/lib/**): the three identity comparisons of DECISION-14 — which run on default `initialize()`, which are skipped (comparison 2 is documented as skipped when no manifest bytes are present), and can a wrong library pass? Does the loader read any environment variable or path a hostile app could influence? Rule 3: any network or download path reachable at runtime?
6. Build scripts and workflows (tools/native_build/**, .github/workflows/build-native.yml): shell-injection or quoting bugs with untrusted inputs (upstream_tag, artifact_set_id, xcode_version, allow-extra names), `set -euo pipefail` gaps, `sed -i` patches that could silently no-op on upstream changes (`-DFLUTTER=ON` into android/wallet-core/build.gradle), the export gate (`check_exports.sh --dynamic` for ELF, `--allow-extra`), SHA256SUMS generation, release-asset naming (`<set_id>__<sha256>__<flat_name>`), and whether a failed job can leave a half-published draft release or a reserved tag.
7. Generators (tools/gen/proto.sh staging/restore logic, registry transform): can a failed regeneration lose or corrupt generated output? Is `gen:check` actually comparing what CI would produce (protoc 33.4 / protoc_plugin 25.0.0 pins)?
8. Example app and seams (example/**): does the app import anything from `src/` of the SDK, does it depend on `dart:ffi`, and does the test seam (test/support/test_seam.dart) stay out of the shipped app?
9. Lints (tools/lint/**): false negatives — write down a public signature that would violate rule 4 or rule 12 and check whether the lint would catch it (read the lint code; do not edit tests).
10. Anything else you find that a maintainer would want to know before tagging Phase 1.
</questions>

<grounding_rules>
Ground every finding in file:line and, where possible, a command you ran and its output, or a minimal reproduction sketch. Label inferences. If you cannot confirm, say UNPROVEN and what would confirm it. No style nits unless they hide a bug. Do not propose features. Do not touch git write operations, do not dispatch workflows, do not start other agents.
</grounding_rules>

<structured_output_contract>
Report in exactly this shape:
  A. Findings, ordered by severity (blocking / should-fix / nit): id, severity, file:line, one-paragraph description, failure scenario (inputs/state → wrong behaviour), suggested fix, confidence (confirmed / plausible).
  B. Per question 1–10: a short verdict (sound / defect found → finding id / UNPROVEN) and what you checked.
  C. Gate results you ran (command → exit → counts).
  D. Three things the project does well that should not be regressed.
  E. One paragraph: would you ship this as a 0.1 public alpha? What single change would most reduce risk?
</structured_output_contract>
