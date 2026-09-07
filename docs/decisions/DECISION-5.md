# DECISION-5: Package Naming

*Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.*

## Context
PRD §8 establishes a three-package architecture (`SDK`, `bindings`, `native`). We must select a name family for these packages that complies with PRD §17 (trademark rules) and ensures clear visibility on pub.dev. The orchestrator performed an availability check on 2026-09-07.

## Availability

| Family | Name | Status | Notes |
|---|---|---|---|
| `wallet_core_flutter*` | `wallet_core_flutter` | FREE | |
| | `wallet_core_flutter_bindings` | FREE | |
| | `wallet_core_flutter_native` | FREE | |
| `flutter_wallet_core*` | `flutter_wallet_core` | FREE | |
| | `flutter_wallet_core_bindings` | FREE | |
| | `flutter_wallet_core_native` | FREE | |
| `walletcore*` | `walletcore` | FREE | |
| | `walletcore_bindings` | FREE | |
| | `walletcore_native` | FREE | |
| `wallet_core_sdk*` | `wallet_core_sdk` | FREE | |
| | `wallet_core_sdk_bindings` | FREE | |
| | `wallet_core_sdk_native` | FREE | |
| Other `wallet_core*` | `wallet_core` | TAKEN | 0.4.1, publisher fuse.io, "Fuse wallet core Dart library to interact with Ethereum based networks" |
| | `wallet_core_bindings` | TAKEN | 4.8.0, unverified publisher, "Dart bindings for trust wallet core, used in Flutter and Dart." (competitor named in PRD §3) |
| | `wallet_core_native` | FREE | |
| Other Free Names | `wallet_core_dart`, `wallet_core_ffi`, `twc_flutter` | FREE | |
| Excluded | `flutter_trust_wallet_core` | TAKEN | Excluded by PRD §17 (contains "trust"). |
| | `trust_wallet_core` | TAKEN | Excluded by PRD §17 (contains "trust"). |

## Considerations per Family

- **Collision or confusion risk:** The packages `wallet_core` and `wallet_core_bindings` (the direct competitor named in PRD §3) are taken. Any family starting with `wallet_core` risks search confusion, as users might see the competitor's bindings and mistake them for part of our package set. A family like `flutter_wallet_core*` mitigates this by placing `flutter` first.
- **Consistency of the three-suffix pattern:** All proposed families consistently support the `<base>`, `<base>_bindings`, and `<base>_native` pattern, maintaining the structural clarity mandated by PRD §8.
- **pub.dev search behavior for underscores:** pub.dev search tokenizes words separated by underscores. Searches for "wallet core" will match `wallet_core_flutter` and `flutter_wallet_core` well, but may rank `walletcore` lower since it is treated as a single token.
- **Trademark rule compliance:** PRD §17 explicitly forbids the use of "trust". The excluded packages contain "trust", but all candidate families are safely compliant.
- **Permanence:** pub.dev names are permanent once published. The chosen names must be durable and definitively represent the SDK without trademark infringement.

## Recommendation

**Recommended Family:** `wallet_core_flutter*`
- `wallet_core_flutter`
- `wallet_core_flutter_bindings`
- `wallet_core_flutter_native`

**Fallback Family:** `flutter_wallet_core*`
- `flutter_wallet_core`
- `flutter_wallet_core_bindings`
- `flutter_wallet_core_native`

*Deciding consideration:* The `wallet_core_flutter*` family are the current repository placeholders and effectively tokenize for search engines while clearly appending `_flutter` to avoid direct collision with the taken `wallet_core` package. 

## Status
**Recorded 2026-09-07 - the `wallet_core_flutter*` family is kept** (Decision section below); T0.10 is therefore skipped. Recommended by T0.6, contested at D0, recorded by the orchestrator under the owner's standing authorization and subject to their ratification.

**Note:** Publishing reserves nothing until T3.12. Availability must be re-checked immediately before the first publish.

---

## Decision

**Keep the placeholder family:** `wallet_core_flutter`, `wallet_core_flutter_bindings`, `wallet_core_flutter_native`.
All three were free on pub.dev on 2026-09-07. **T0.10 (rename) is skipped.**

**Why, against the contrary case.** D0 preferred `flutter_wallet_core*` on one real argument: a `wallet_core*` prefix
sits beside the taken competitor `wallet_core_bindings` in pub.dev search results, and our own
`wallet_core_flutter_bindings` is its closest neighbour of all. That argument is not dismissed, it is not yet
actionable. Search adjacency can only be measured once both package sets exist and are ranked, and acting on it today
costs a repo-wide rename of paths, imports, and every document that names them, paid before a single consumer exists.

The deciding fact is **when the name becomes permanent**: not now, but at the first publish (T3.12). Until then a
rename is a mechanical task the plan already holds ready. Keeping the placeholders costs nothing a later rename cannot
recover; renaming now spends the work up front for an unmeasured benefit.

**Revisit trigger, mandatory.** Availability must be re-checked immediately before the first publish, and **T3.12 must
re-open this record at that moment**, with whatever pub.dev search then shows for "wallet core". That is the last point
at which `flutter_wallet_core*` costs only a rename. After the first publish, pub.dev names are permanent and this
decision cannot be revisited at any price.

Recorded **2026-09-07 by the orchestrator**, under the repository owner's standing authorization to keep Phase 0 moving while they were unavailable, and **subject to the owner's ratification** (`docs/plan/PROGRESS.md` -> Needs your eyes -> "Decisions recorded on your behalf"). The choice is reversible at the cost stated in the revisit trigger; nothing is published.
