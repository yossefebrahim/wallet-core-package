# Codex whole-project code review (gpt-5.5, xhigh, read-only) — main 672e09e, 2026-10-04

Brief: docs/plan/briefs/CODEX-REVIEW-project-code.md. Thread 01a10601-7b13-7971-8240-c23b211f5c2f. Report verbatim below; orchestrator triage in PROGRESS.md.

A. Findings, ordered by severity

- F1, blocking, [.github/workflows/build-native.yml:142](/Users/yossefebrahim/Work/wallet-core-package/.github/workflows/build-native.yml:142): `workflow_dispatch` inputs are interpolated directly into shell scripts before validation. This appears at the plan step and again in Xcode selection, build arguments, manifest splicing, release notes, and release creation. Failure scenario: `upstream_tag = 4.8.0'; printf 'INJECTED_BY_INPUT\n' >&2; #` expands to executable shell before the regex runs; my local reproduction printed `INJECTED_BY_INPUT`. In later publish steps this can run inside a job with `contents: write`. Suggested fix: pass every input through `env:` and reference only quoted shell variables; quote heredocs or generate notes via `printf`/`jq`; validate before use. Confidence: confirmed.

- F2, should-fix, [runtime_deps_check.dart:250](/Users/yossefebrahim/Work/wallet-core-package/tools/lint/lib/runtime_deps_check.dart:250): the runtime-deps lint misses real `dart:io` network APIs. The deny list catches `HttpClient`, `Socket`, `RawDatagramSocket`, etc., but not `InternetAddress.lookup`, `RawSocket`, or `SecureServerSocket`. Failure scenario: a `lib/` file can add `import 'dart:io'; Future<void> f() => InternetAddress.lookup('example.com');` and the scanner has no symbol to match, so a runtime DNS/network path can pass the canonical rule-3 gate. Suggested fix: move this lint to analyzer AST/import checks, or expand and test the blocked API set at least for all `dart:io` network entry points. Confidence: confirmed.

- F3, nit, [registry_transform.dart:256](/Users/yossefebrahim/Work/wallet-core-package/tools/gen/lib/registry_transform.dart:256): the registry generator writes generated files and `compat_manifest.json` in place, then formats after the writes. Failure scenario: if formatting, process death, or an I/O error happens after `coin_type.dart`/`coin_info.dart` or the manifest is truncated or rewritten, the workspace is left partially regenerated; `proto.sh` avoids this with staging and swap at [proto.sh:136](/Users/yossefebrahim/Work/wallet-core-package/tools/gen/proto.sh:136) and [proto.sh:380](/Users/yossefebrahim/Work/wallet-core-package/tools/gen/proto.sh:380). Suggested fix: stage registry output and manifest updates in a temp directory/file, format there, then rename atomically. Confidence: plausible.

B. Per question 1–10

1. Sound. Checked `submit`, `_send`, `_finishClosed`, `_onReply`, `_expire`, `InProcessTransport.send`, and `WorkerLoop._drainOne`; I did not find a request-after-close or late-secret reply race.
2. Sound. Checked secret payload `toString`s, error wrapping, zeroing of owned entropy, and searches for logging; no secret exposure found.
3. Sound. Requests stay keyless; EVM transaction `private_key` is field 9 in upstream [Ethereum.proto:258](/Users/yossefebrahim/Work/wallet-core-package/third_party/wallet-core/src/proto/Ethereum.proto:258), not field 15, and the SDK uses field 9.
4. Sound. `NativeResource.dispose()` marks disposed, releases once, detaches finalizer, and reports disposal; leak tracking is assert-only. Generic wrappers do not zero staging, but SDK secret paths use `secret_buffers`.
5. Sound. Default init runs identity comparisons 3 and 4 plus symbols; comparison 2 runs only when manifest bytes are supplied, and comparison 1 is documented as T3.11. No runtime env/path load on Android/iOS.
6. Defect found → F1. Script quoting is mostly array-safe, but workflow input interpolation is not.
7. Defect found → F3. `proto.sh` staging is sound and CI pins protoc 33.4 / protoc_plugin 25.0.0; registry generation is not staged.
8. Sound. `example/lib` imports only Flutter, public SDK, and local app files; `test/support/test_seam.dart` contains the internal imports and stays in tests.
9. Defect found → F2. Public API lint appears to catch direct bad signatures such as `Pointer<Void> get raw` or generated `CoinType get coinType`; runtime-deps lint has the network false negative above.
10. Defect found → F1/F2/F3. No additional confirmed SDK defect beyond these and the known manifest placeholder state.

C. Gate results you ran

- `dart run tools/lint/bin/public_api_lint.dart` → exit 1 → 0 elements checked; blocked before lint by read-only sandbox because Flutter tried to write `/Users/yossefebrahim/flutter/bin/cache/engine.stamp.tmp.*`.
- `dart run tools/lint/bin/runtime_deps_check.dart` → exit 1 → 0 packages checked; same Flutter cache write failure.
- `bash -n tools/gen/proto.sh tools/native_build/lib/common.sh tools/native_build/build_android.sh tools/native_build/build_apple.sh tools/native_build/check_exports.sh tools/native_build/check_alignment.sh tools/native_build/emit_artifact_record.sh tools/native_build/generate_symbol_list.sh tools/native_build/run_native_tests.sh tools/consumer_check.sh` → exit 0 → 10 shell scripts parsed.

D. Three things the project does well

- The session protocol is careful about copied secret buffers, timeout accounting, cancellation, and late wallet disposal.
- The signing boundary is clean: keyless family encoding, reviewed key-field lists, unknown-field rejection, and key injection only inside the signer.
- Native handles have a consistent disposal/finalizer pattern, with redacted diagnostics and debug-only leak tracking.

E. Ship verdict

I would not ship this as a 0.1 public alpha yet. The SDK core is in decent shape, but the native release workflow command injection is too sharp for an artifact pipeline, and the default native identity placeholders still make public initialization a known pre-release state. The single risk-reducing change I would make first is to harden `build-native.yml` so every manual input is treated as data, never shell syntax.