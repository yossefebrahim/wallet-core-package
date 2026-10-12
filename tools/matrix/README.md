# `tools/matrix` — capability matrix generator and coverage checks

Package `wcf_tool_matrix`. Build-time tooling (PRD §13, T2.8); nothing here is
shipped or reachable from the SDK packages.

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

```
melos run gen:matrix     # writes docs/capability_matrix.md and .json, and the README counts region
melos run matrix:check   # PRD §13.2 (a)–(c), and (d) README counts; exit 0 / 1 / 64
```

## Inputs

| Input | Used for |
|---|---|
| `packages/wallet_core_flutter_bindings/lib/src/generated/registry/` | the 167 coins, their `blockchain`, derivation count (read as text; the bindings package is Flutter-only) |
| `packages/wallet_core_flutter_bindings/lib/src/generated/proto/*.pb.dart` | which messages (`SigningInput`, `MessageSigningInput`, `TransactionPlan`) each proto package defines |
| `docs/decisions/evidence/compiler_and_message_coverage.json` | T2.9 probe rows: generic message signer, transaction compiler (written by `melos run probe:coverage -- --json-out <path>`) |
| `docs/capability_exposed.json` | the **Exposed** column: a snapshot of the SDK's `lib/src/capabilities.dart`, kept identical to it by `packages/wallet_core_flutter/test/capabilities_test.dart` |
| `test_vectors/**` | the **Tested** column (`platforms_verified`) and the exclusions |
| `test_vectors/results/<platform>.json` | check (a) only (schema in [`test_vectors/results/README.md`](../../test_vectors/results/README.md)); written by CI, absent in a local checkout |
| `compat_manifest.json` | the upstream tag and commit stamped on the outputs |
| `README.md` (`--readme`) | the file whose `matrix-counts` region `gen:matrix` rewrites and check (d) compares |

## Generated column

Per coin and operation, mechanically:

- `address` — the registry lists at least one derivation.
- `sign` — the coin's proto package defines `SigningInput`.
- `sign_message` — the proto package defines `MessageSigningInput` **and** the
  T2.9 generic message-signer evidence agrees; a disagreement is a `conflict`
  cell, listed under Conflicts in the markdown and in `conflicts` of the JSON.
- `plan` — the proto package defines `TransactionPlan` (`TWAnySignerPlan` is
  documented for UTXO chains only; the proto is the per-coin evidence).
- `compile` — the T2.9 compiler evidence: static source rules and runtime calls
  agree. A coin whose probe process died on malformed input (EOS, WAX) is
  generated with the distinct note `aborts on malformed input`.

The coin → proto package map is the registry `blockchain`, with the aliases of
`lib/variants.dart` (UTXO forks sign with `Bitcoin.proto`; Ronin with
`Ethereum.proto`; Cosmos-based chains with `Cosmos.proto`; …), each citing the
upstream source line that binds them. `TWAnySignerSign` is one global symbol and
is never evidence.

## Exposed and Tested

*Exposed*: `capability_exposed.json` groups `(operation, variant) → typed | generic`
for a coin list or for every coin. The tool reads the JSON snapshot, never the
Dart source and never the SDK package; the snapshot is committed so a change in
what the SDK exposes shows in review, and the SDK test fails when the snapshot is
stale (`flutter test --dart-define=WCF_UPDATE_CAPABILITY_SNAPSHOT=true
test/capabilities_test.dart` rewrites it).

*Tested*: a variant is Tested when **one** vector for that exact
(coin, operation, variant) lists both `android` and `ios` in
`platforms_verified`. A vector's variant must be one its coin's family defines
(`lib/variants.dart`): an Ethereum `taproot` vector is an error. Levels per
platform are 1 generated, 2 exposed, 3 verified on that platform.

## Checks

`matrix:check` runs `gen`'s computation first; inconsistent inputs are
violations.

- **(a)** each `android` / `ios` entry of a vector's `platforms_verified` must be
  `pass` in `test_vectors/results/<platform>.json`. No file → `unconfirmed`
  (printed, not a failure) unless `--strict`. CI's `matrix` job passes `--strict` (T2.8b); the
  `gates` job runs the plain check.
- **(b)** the committed `docs/capability_matrix.{md,json}` equal a fresh
  regeneration (written to a temp dir and compared byte for byte).
- **(c)** against the previous committed matrix — `git show HEAD:docs/capability_matrix.json`,
  another ref with `--baseline-ref <ref>`, or a file with `--baseline <path>` —
  no (coin, operation, variant, platform) level goes down, no Tested flag is
  lost, no cell and no vector disappears, unless `test_vectors/exclusions.yaml`
  has an entry (`coin`, `operation`, optional `variant`, non-empty `reason`)
  covering it. When the ref has no matrix (the commit that adds it), (c) is
  skipped with a note. In CI the baseline must be the PR's base
  (`--baseline-ref origin/main`): `HEAD` there already contains the PR's matrix.

- **(d)** (T2.11) the region of `README.md` between `<!-- matrix-counts -->` and
  `<!-- /matrix-counts -->` equals a fresh regeneration; a README with a missing,
  repeated or reversed marker fails too. Message:
  `(d) README.md differs from the regenerated matrix counts (first at line N); …
  run melos run gen:matrix`.

Exit codes: 0 all pass; 1 a check failed (one line per violation on stderr);
64 usage.

## Layout of `docs/capability_matrix.md`

Totals first (per operation, then per variant), then one section per operation.
An operation's tables are split by chain family where the variants differ (a
Bitcoin variant means nothing for an EVM chain), and within a table every coin
with the same cell texts shares one row. 167 coins × 5 operations as one table
would be 835 near-identical rows and unreadable; the per-coin detail with the
evidence behind each verdict is in `capability_matrix.json`.

## README counts (T2.11)

`lib/readme_counts.dart`, called by `bin/gen.dart` (so `gen:all` keeps it
current), rewrites only the text between `<!-- matrix-counts -->` and
`<!-- /matrix-counts -->` in `README.md`; every byte outside the markers is kept.
A missing README, a missing, repeated or reversed marker is an error (exit 1,
nothing written), never an append. The region is generated from the same
`Matrix` as `capability_matrix.json`, with no number typed by hand:

- the headline `N chains generated, M exposed, K tested` — a chain is a registry
  coin, counted at a level when at least one of its operations has a variant at
  that level (`Matrix.chainTotals`);
- while K is 0, the sentence "No variant is verified on a device yet"; when K is
  above 0, the per-variant caveat instead;
- the level meanings, shared constants with `capability_matrix.md` (`render.dart`);
- the per-variant table, one row per `totals.variants` entry, in JSON order.

`gen:check` includes `README.md` in its `git diff --exit-code` paths, and check
(d) above catches a hand edit.

## Results collection (T2.8b)

```
melos run matrix:collect -- --platform android --out test_vectors/results <log>...
```

`bin/collect_results.dart` reads device-test logs, keeps the
`WCF_VECTOR_RESULT {"id":...,"status":...}` lines the integration tests print
(`example/integration_test/vector_results.dart`) and writes
`<out>/<platform>.json`. The upstream pin comes from `compat_manifest.json`;
`repository_sha` and `run_id` from `--repository-sha` / `--run-id` or
`GITHUB_SHA` / `GITHUB_RUN_ID`. Exit 0 written; 1 a malformed line or an id that
is not in the inventory (nothing written); 64 usage. The vector loader skips a
top-level `test_vectors/results/`, so the files live there; the schema is in
[`test_vectors/results/README.md`](../../test_vectors/results/README.md).
