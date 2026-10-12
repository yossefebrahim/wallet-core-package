# CI results (`test_vectors/results/<platform>.json`)

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

The evidence that a vector passed on a device: one file per platform, written by
CI from the device test runs (T2.8b), never by hand. No such file exists until
T2.8b lands. (The directory is not created yet: the vector loader rejects a
subdirectory of `test_vectors/` without a `vectors.yaml`; see `README.md`.)

```
test_vectors/results/android.json
test_vectors/results/ios.json
```

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
- `repository_sha` and `run_id` are non-empty strings that identify the run.
- `results[].id` is a vector id of `test_vectors/*/vectors.yaml`; `status` is
  `pass`, `fail` or `skipped`. A vector the run did not execute has no entry.

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
  the check, because no CI run can have produced the file yet.
- `matrix:check --strict` makes an unconfirmed claim fail. CI will pass
  `--strict` once T2.8b writes these files; until then no vector carries an
  `android` or `ios` claim, so nothing is unconfirmed.
- `host` is a valid `platforms_verified` value but is not a device run and never
  counts towards *Tested*; it is not checked against a results file.
