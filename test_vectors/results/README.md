# CI results (`test_vectors/results/<platform>.json`)

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

The evidence that a vector passed on a device: one file per platform, written by
CI from the device test runs (T2.8b), never by hand.

```
test_vectors/results/android.json
test_vectors/results/ios.json
```

This directory is the only subdirectory of `test_vectors/` that is not a coin:
the vector loader (`tools/vectors`, `Inventory.load`) skips a top-level
`results/` and reads no `vectors.yaml` from it. The schema below is the single
source for the files; `tools/matrix/RESULTS.md` links here.

## How CI writes them

1. Each device test of `example/integration_test` calls `recordVectorPass(id)`
   (`example/integration_test/vector_results.dart`) once every assertion for a
   vector has passed. That prints one line,
   `WCF_VECTOR_RESULT {"id":"<vector id>","status":"pass"}`, and nothing secret.
   A test that fails earlier prints nothing, so its vectors have no entry.
2. After the device test step, `melos run matrix:collect` (the collector,
   `tools/matrix/bin/collect_results.dart`) reads the logs
   (`flutter_test*.txt` of the diagnostics directory), keeps the
   `WCF_VECTOR_RESULT` lines, drops duplicates, sorts by id and writes
   `<platform>.json`. A vector id that is not in `test_vectors/*/vectors.yaml`
   is an error (exit 1) and nothing is written.
3. The `matrix` job downloads both files into this directory and runs
   `melos run matrix:check -- --strict --baseline-ref origin/main`.

## Schema

```json
{
  "schema": 1,
  "platform": "android",
  "upstream": { "tag": "4.8.0", "commit": "<40-hex upstream commit>" },
  "repository_sha": "<commit of this repository the run tested>",
  "run_id": "<CI run id>",
  "results": [
    { "id": "ethereum-sign-eip1559-1", "status": "pass" }
  ]
}
```

- `platform` is the file's own name: `android` or `ios`.
- `upstream.tag` and `upstream.commit` must equal the pin in
  `compat_manifest.json`; a results file for another pin is stale and fails
  `matrix:check`.
- `repository_sha` and `run_id` are non-empty strings that identify the run
  (`GITHUB_SHA`, `GITHUB_RUN_ID`).
- `results[].id` is a vector id of `test_vectors/*/vectors.yaml`; `status` is
  `pass`, `fail` or `skipped`. A vector the run did not execute has no entry.
  When one id appears with different statuses in the logs, the worst wins.
- Entries are sorted by id and the file ends with a newline; the same logs give
  the same bytes.

`tools/matrix/test/fixtures/results_example_android.json` is a complete example.

## How the files are used

`platforms_verified` in each vector entry is the reviewed, committed record of
where a vector passes; the capability matrix reads it, and a variant is *Tested*
when one vector for that exact variant lists both `android` and `ios`. These
files are what that record is checked against. `melos run matrix:check`, check
(a) of PRD §13.2: every `android` or `ios` entry in a vector's
`platforms_verified` must be `pass` for that vector in the matching file.

- A claim contradicted by the file (`fail`, `skipped`, no entry), a stale file or
  a malformed file fails the check.
- A claim with **no** results file is reported `unconfirmed` and does not fail
  the check, unless `--strict`. A local checkout has no files, so the `gates`
  job runs the plain check; the CI `matrix` job runs `--strict`.
- `host` is a valid `platforms_verified` value but is not a device run and never
  counts towards *Tested*; it is not checked against a results file.
