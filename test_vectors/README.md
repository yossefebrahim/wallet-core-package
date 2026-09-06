# Test Vectors

This directory contains the machine-checked test vector inventory for `wallet_core_flutter`.

## Schema

Each test vector is stored in a YAML file at `test_vectors/<coin>/vectors.yaml`, which contains a top-level list `vectors:`.

Each vector in the list is a YAML map with exactly the following keys:

- `id`: (string) Unique identifier across the entire inventory. Must match the pattern `<coin>-<operation>-<variant>-<n>`.
- `coin`: (string) The upstream registry id (e.g., `ethereum`, `bitcoin`, `solana`).
- `operation`: (string) The operation being tested. Must be one of: `address`, `sign`, `sign_message`, `plan`, `compile`, `invalid_input`.
- `variant`: (string) The operation variant. Must be from the following per-family list:
  - EVM: `legacy`, `eip1559`, `contract_call`
  - Bitcoin: `p2pkh`, `p2wpkh`, `taproot`, `multi_input`
  - Solana: `legacy`, `versioned`
  - Messages: `personal`, `eip712`
  - For `address` and `invalid_input` operations, use `n/a`.
- `source`: (map) Provenance of the test vector (mandatory per plan rule 7). A vector without a valid source is rejected.
  - `kind`: (string) One of `upstream_test`, `standard`, `published_tx`.
  - `path`: (string) Required if `kind` is `upstream_test`.
  - `commit`: (string) Required if `kind` is `upstream_test`. Must be a 40-character hex string.
  - `reference`: (string) Required if `kind` is `standard` or `published_tx`.
  - `url`: (string) Optional.
- `input`: (map) Free-form inputs specific to the operation.
- `expected`: (map) Free-form expected outputs specific to the operation.
- `platforms_verified`: (list of strings) Platforms where the vector has been verified. Allowed values: `android`, `ios`, `host`. May be empty.

## Exclusions

The file `test_vectors/exclusions.yaml` contains a top-level list `exclusions:` specifying coins, operations, or variants we intentionally do not test (with rationale).

Each exclusion is a map with the following keys:
- `coin`: (string) The coin id.
- `operation`: (string) The operation.
- `variant`: (string) Optional variant.
- `reason`: (string) Rationale for the exclusion.
