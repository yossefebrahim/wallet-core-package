/// The vocabulary the matrix is built on: operations, platforms, chain
/// families, the variants each family defines, and the blockchain → proto
/// package map.
library;

/// The matrix operations, in table order. `invalid_input` vectors exist in the
/// inventory but are not an operation of the matrix (PRD §13.1).
const List<String> operations = [
  'address',
  'sign',
  'sign_message',
  'plan',
  'compile',
];

/// The platforms CI confirms (`test_vectors/results/<platform>.json`) and a
/// *Tested* claim needs. `host` is a valid `platforms_verified` value but no
/// device run, so it never counts towards *Tested*.
const List<String> platforms = ['android', 'ios'];

/// The cell variant of an operation whose family defines no variants yet.
const String anyVariant = 'any';

/// The chain families of the matrix, in table order. Mirrors the SDK's
/// `familyOfBlockchain` (`packages/wallet_core_flutter/lib/src/coin/chain_family.dart`):
/// the tool never imports the SDK package, so the three rules are repeated
/// here, and a test over the real registry pins the resulting counts.
const List<String> families = ['evm', 'utxo', 'solana', 'other'];

String familyOfBlockchain(String blockchain) => switch (blockchain) {
  'Ethereum' => 'evm',
  'Bitcoin' => 'utxo',
  'Solana' => 'solana',
  _ => 'other',
};

const _evmTransactionVariants = ['legacy', 'eip1559', 'contract_call'];
const _utxoVariants = ['p2pkh', 'p2wpkh', 'taproot', 'multi_input'];
const _solanaVariants = ['legacy', 'versioned'];

/// The variants (PRD §13.1: a concrete transaction or message shape) each
/// (family, operation) defines, from `test_vectors/README.md`. A cell exists
/// for each of them wherever the operation is generated; an operation with no
/// entry has the single cell [anyVariant] until its family gains variants.
///
/// A vector, or an Exposed entry, naming a variant outside this table for its
/// coin's family is rejected — an Ethereum `taproot` vector fails here.
const Map<String, Map<String, List<String>>> variantCatalogue = {
  'evm': {
    'sign': _evmTransactionVariants,
    'sign_message': ['personal', 'eip712'],
    'compile': _evmTransactionVariants,
  },
  'utxo': {
    'sign': _utxoVariants,
    'plan': _utxoVariants,
    'compile': _utxoVariants,
  },
  'solana': {
    'sign': _solanaVariants,
    'sign_message': ['personal'],
    'compile': _solanaVariants,
  },
};

/// The variants of ([family], [operation]): `n/a` for `address`, the
/// catalogue entry, or just [anyVariant].
List<String> variantsOf(String family, String operation) {
  if (operation == 'address') return const ['n/a'];
  return variantCatalogue[family]?[operation] ?? const [anyVariant];
}

/// Registry blockchains whose signing input is another blockchain's proto
/// package, or whose own `.proto` defines none. The generated registry carries
/// only the `blockchain` string, and 13 of the 57 have no `.proto` of that name
/// (`third_party/wallet-core/src/proto/`); each entry below cites where
/// upstream binds the blockchain to a proto package.
///
/// * UTXO forks sign with `Bitcoin.proto`'s `SigningInput` and plan with its
///   `TransactionPlan`: `signTemplate<Signer, Bitcoin::Proto::SigningInput, …>`
///   in `src/{Verge,Zen,Groestlcoin,BitcoinDiamond,Decred}/Entry.cpp`,
///   `using SigningInput = Bitcoin::Proto::SigningInput` in
///   `src/Zcash/Signer.h`; BitcoinCash inherits `Bitcoin::Entry`
///   (`src/BitcoinCash/Entry.h`) and Komodo inherits `Zcash::Entry`
///   (`src/Komodo/Entry.h`). `Zcash.proto` and `Decred.proto` define no
///   `SigningInput` of their own.
/// * Ronin: `tw_proto::Ethereum::Proto` (`rust/chains/tw_ronin/src/entry.rs:23`).
/// * NativeEvmos, NativeInjective, Thorchain: `tw_proto::Cosmos::Proto`
///   (`rust/chains/tw_{native_evmos,native_injective,thorchain}/src/entry.rs`).
/// * Kusama dispatches to the Polkadot entry
///   (`rust/tw_coin_registry/src/dispatcher.rs:80`).
/// * OasisNetwork → `Oasis.proto`, Vechain → `VeChain.proto`: case and spelling
///   of the proto file name only.
const Map<String, String> protoAliases = {
  'BitcoinCash': 'Bitcoin',
  'BitcoinDiamond': 'Bitcoin',
  'Decred': 'Bitcoin',
  'Groestlcoin': 'Bitcoin',
  'Komodo': 'Bitcoin',
  'Verge': 'Bitcoin',
  'Zcash': 'Bitcoin',
  'Zen': 'Bitcoin',
  'Kusama': 'Polkadot',
  'NativeEvmos': 'Cosmos',
  'NativeInjective': 'Cosmos',
  'Thorchain': 'Cosmos',
  'OasisNetwork': 'Oasis',
  'Ronin': 'Ethereum',
  'Vechain': 'VeChain',
};

/// The proto package (file stem under `src/proto/`) the registry [blockchain]'s
/// messages live in.
String protoOfBlockchain(String blockchain) =>
    protoAliases[blockchain] ?? blockchain;
