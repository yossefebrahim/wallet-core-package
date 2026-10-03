# wallet_core_flutter

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

Status: pre-alpha, nothing published.

## Verified support

<!-- matrix-counts -->

## Documentation

- Product requirements: [docs/wallet_core_flutter_prd.md](docs/wallet_core_flutter_prd.md)
- Execution plan: [docs/plan/EXECUTION_PLAN.md](docs/plan/EXECUTION_PLAN.md)

<!-- memory-contract -->
### Memory and Lifecycle

Two pages describe how the SDK behaves as of task T1.12 (EVM signing):

- [Memory Contract](docs/security/memory_contract.md): where mnemonics, passphrases, entropy and private keys exist in memory, including during signing. It says which copies this SDK overwrites, which upstream overwrites, and which nobody overwrites as far as the sources show. The default API never returns private-key bytes.
- [Lifecycle](docs/security/lifecycle.md): proxies and internal handles, finalizers, session states, the errors `initialize()` can throw, scopes, deadlines, failures and shutdown.

Both pages describe behaviour and its limits. Neither promises a security property.
<!-- /memory-contract -->
