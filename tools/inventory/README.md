# `tools/inventory` — header symbols vs. generated symbols

Package `wcf_tool_inventory`. Build-time tooling; nothing here is shipped in
`wallet_core_flutter`, `wallet_core_flutter_bindings`, or
`wallet_core_flutter_native`, and nothing here is reachable from them.

```
melos run gen:ffi          # regenerates the bindings, then writes inventory.json
melos run inventory:check  # fails on a missing symbol or a stale inventory.json
```

It writes
`packages/wallet_core_flutter_bindings/lib/src/generated/inventory.json`, the
generated symbol inventory PRD §9 requires. That file answers two questions
that a reviewer would otherwise have to reconstruct by hand:

1. **What produced these bindings?** The `headers` block records the release
   asset's file name and SHA-256, the pinned tag and commit, the number of
   header files, and the directory digest of the header set — copied verbatim
   from `third_party/wallet-core-dist/dist_provenance.json`, which
   `melos run upstream:fetch -- --dist` writes.
2. **Does the binding set cover the header set?** `symbols` maps every name
   either side has to `{"kind", "in_headers", "in_generated"}`, and `missing`
   lists the names the headers declare that the bindings do not bind. A
   non-empty `missing` fails the build.

Before building the inventory the tool recomputes T1.1's directory digest over
the headers on disk and compares it with the recorded one. Without that, the
provenance block would be a label rather than a statement about the bytes
ffigen actually read.

## The two symbol lists, and why they must agree

| List | Produced by | Used for |
|---|---|---|
| Every function the headers declare (466 at 4.8.0) | `lib/headers.dart` | The coverage check: every one must be bound. |
| The `TW*` subset (464 at 4.8.0) | `tools/native_build/generate_symbol_list.sh` | The linker's `-u` list in `build_apple.sh`; the expected export set in `check_exports.sh`. |

`lib/headers.dart` is a Dart transcription of that shell script's grep with the
`TW` requirement dropped, and `test/agreement_test.dart` runs both
implementations over the same headers and requires the `TW*` subsets to be
identical — on a fixture built for the awkward cases (a name mentioned in
prose, a `static const char *` initialiser, a multi-word return type), and, when
the headers are present, on all 143 of them. If the two extractions disagreed,
the bindings and the shipped artifact's export set would disagree and one of the
two gates would be measuring a set that does not exist.

The two names outside the `TW*` subset are `stringForHRP` and `hrpForString` in
`TWHRP.h`. ffigen binds them because the headers declare them; the export gate
does not track them because it tracks `TW*`. `counts.exported_tw_functions`
records the 464 so the two numbers can be compared without re-deriving either.

## What counts as "bound"

Every native symbol the generated Dart reaches, it reaches through exactly one
`_lookup<T>('name')` call, so that call is what `lib/generated.dart` counts —
not the Dart method names, which are a rename away from the symbol they call.
The type argument spans several lines after `dart format`, so the scan matches
angle brackets rather than lines. A lookup whose type is not an
`ffi.NativeFunction` is a data symbol, counted separately: binding a global as
if it were a function would make the inventory lie.

## Layout

| File | Contents |
|---|---|
| `bin/symbols.dart` | Command-line entry point; `--check` verifies instead of writing. |
| `lib/headers.dart` | Header scan: declared functions and enums. |
| `lib/generated.dart` | ffigen-output scan: bound symbols and Dart enums. |
| `lib/inventory.dart` | The join, the counts, and the JSON rendering. |
