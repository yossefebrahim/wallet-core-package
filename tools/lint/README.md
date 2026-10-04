# Public API Lint

`melos run lint:public-api` resolves, with `package:analyzer`, the export namespace of every public library of `packages/wallet_core_flutter` — each `lib/*.dart` except `lib/advanced.dart`, the one library allowed to expose these types — and fails when a public signature exposes a type the default surface must never expose (AGENTS.md rules 4 and 12). For every exported class, mixin, enum, extension, extension type, typedef, function and variable it walks supertypes, type-parameter bounds, typedef targets (every link of a chain) and every public member, inherited ones included with type arguments substituted, recursing into type arguments, nullable, `Future`, record and function types. A non-exported type met in a public position (`Future<Inner>`, `T extends Inner`, a private class returned by a getter, a typedef-exported class) is reachable by consumers, so it is checked the same way and its findings are reported under the exported name, with the path: `Api.inner→Inner.pointer`. SDK types are not descended into, and each type is visited once per exported name.

## Rules
- `ffi`: a `dart:ffi` or `package:ffi/…` type in a public signature.
- `generated`: a type from a library under `/src/generated/` (`CoinType`, `TW*` bindings, protobuf classes).
- `protobuf`: a `package:protobuf/…` or `package:fixnum/…` type.
- `pointer-field`: a stored instance field of any visibility, declared or inherited through `extends`/`with` (not `implements`), whose type mentions an FFI type, also behind an extension type.
- `sync-dispose`: a public instance `dispose` a caller can invoke — a method, or a getter/field of a callable type — declared, inherited, or added by an exported extension.

## How to run
```bash
dart run tools/lint/bin/public_api_lint.dart [--package packages/wallet_core_flutter] [--entry lib/x.dart]...
```
`--entry` is repeatable and replaces the default set. Output: the sorted violations of each entry followed by `public-api: <entry>: N exported elements checked, M violations`, then the total `public-api: N exported elements checked, M violations`.

## Exit codes
- `0`: no violations. `1`: violations.
- `2`: no verdict — an entry is missing or not a library, analysis reports errors in it, its parts, or any library it exports transitively, or a walked signature has an unresolved type.
- `64`: usage error.

# Runtime Dependency Check

`melos run lint:runtime-deps` computes the **transitive runtime dependency closure** of `packages/wallet_core_flutter`, `packages/wallet_core_flutter_bindings`, and `packages/wallet_core_flutter_native` (following only `dependencies:`, never `dev_dependencies:`). It enforces PRD §16 S4 by checking:

- Packages in the closure cannot be on the **deny list** (e.g., networking/telemetry packages like `http`, `dio`, `firebase_*`, `sentry*`).
- Packages must be explicitly on the **allow list**. Extending this allow list requires a reviewed decision.
  - `ffi`: Dart FFI is required for C interop.
  - `protobuf`: Required for Trust Wallet Core protobuf serialization.
  - `fixnum`: Required by protobuf for 64-bit integers.
  - `crypto`: Cryptographic hashing (SHA-256) for artifact/manifest verification.
  - `collection`: Collections utility used for Dart types.
  - `meta`: Dart meta annotations.
  - `typed_data`: Typed data wrappers.
  - `flutter`: Flutter SDK.
  - `sky_engine`: Flutter internal engine.
  - `characters`: Dart string characters utility.
  - `material_color_utilities`: Flutter material colors.
  - `vector_math`: Flutter vector math.
  - `wallet_core_flutter`, `wallet_core_flutter_bindings`, `wallet_core_flutter_native`: Sibling packages in workspace.
- The root `pubspec.lock` and `pubspec.yaml` are checked to ensure every package in the closure uses an allowed source (`hosted` on `https://pub.dev`, `sdk`, or a `path` to a workspace sibling). Custom hosted URLs, `git`, and other `path` sources are forbidden. Root `dependency_overrides` touching a closure package are forbidden unless it is a sibling.
- No `dart:io` networking symbols (`HttpClient`, `Socket`, `WebSocket`, etc.) or `package:http` usages appear in `lib/`. They are only permitted in `tool/` or `hook/` directories with a `// wcf: network-ok <reason>` marker, or implicitly allowed inside `packages/wallet_core_flutter_native/tool/` (the build-time artifact fetch tool, per rule 3). Note that the network symbol scan is a guard, not a proof.

A separate **build-time (hook)** category exists for packages reachable only from `hook/`. These packages run in the consumer's build and never ship in the application.

The listed build-time packages are `code_assets`, `hooks`, `logging`, `path`, `pub_semver`, `record_use`, `source_span`, `string_scanner`, `term_glyph`, and `yaml`. The deny list still applies to them, and any attempt to import one of these packages from a `lib/` directory will fail the lint.

## How to run
```bash
dart run tools/lint/bin/runtime_deps_check.dart [--root <dir>]
```
Output: the closure of each published package, violations, network symbol checks, and the exit code.

## Exit codes
- `0`: no violations. `1`: violations.

*Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.*
