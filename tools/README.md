# tools/

Repository tooling. One directory per job, matching the layout of
[`docs/plan/EXECUTION_PLAN.md`](../docs/plan/EXECUTION_PLAN.md) §3. Nothing here
yet: this file is the index, and each entry names the task that creates it.

| Path | Purpose | Created by |
|---|---|---|
| `upstream/` | Pin the upstream commit and fetch its sources at that commit. | T1.1 |
| `gen/` | Registry transform and the protobuf generation script. | T1.4, T1.5 |
| `inventory/` | Compare the header symbol set against the generated symbol set. | T1.3 |
| `matrix/` | Generate the capability matrix from the vector inventory and probes. | T2.8 |
| `manifest/` | Read and validate `compat_manifest.json` (`melos run manifest:validate`). | T0.7 |
| `vectors/` | Load and validate the test-vector inventory, including provenance (`melos run vectors:validate`). | T0.8 |
| `probes/` | Probe upstream availability of SignJSON, the transaction compiler, and message signing. | T1.14, T2.9 |
| `lint/` | Public API type check (`melos run lint:public-api`). | T1.15 |
| `diff/` | API diff and behavioral diff between two upstream pins. | T4.1, T4.2 |
| `native_build/` | Scripts used by the CI native artifact build. | T1.2 |
| `consumer_check.sh` | Fresh `flutter create` consumer: add the dependency, then debug and release builds on both platforms. | T1.16 |
