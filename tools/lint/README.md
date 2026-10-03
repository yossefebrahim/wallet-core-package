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

*Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.*
