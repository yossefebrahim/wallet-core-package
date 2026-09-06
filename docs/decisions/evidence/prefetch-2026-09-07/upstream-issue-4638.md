Flutter : FFI Symbol Lookup Failure with Wallet Core v4.5.0 .aar
2026-01-29T20:24:02Z
I’m trying to integrate Wallet Core v4.5.0 into a Flutter project using the official .aar and Dart FFI bindings. I followed the standard instructions:
Cloned the official Wallet Core repo (v4.5.0).
Built the wallet-core.aar using the ./tools/android-build script.
Generated the Dart FFI bindings from the header files using ffigen.
The .aar seems to include libTrustWalletCore.so correctly, and Flutter is able to load the library.
However, when calling any function from Dart, I get errors like:

`Invalid argument(s): Failed to lookup symbol 'TWAnyAddressIsValid': undefined symbol: TWAnyAddressIsValid
`

It appears that several symbols are missing from the generated .aar library. I’ve verified that:
The native .so is present inside the .aar.
The Dart bindings are correctly pointing to the FFI symbols.
I’ve rebuilt the AAR and regenerated the Dart bindings multiple times.
Questions:
Is there an extra step needed to ensure all symbols are included in the AAR?
Could this be related to missing compilation flags, CMake configuration, or conditional compilation in Wallet Core?
Has anyone successfully used v4.5.0 with Dart/Flutter FFI bindings?

**Environment**:

Flutter  3.38.8
Dart  3.10.7
Wallet Core v4.5.0

**Expected behavior**
All Wallet Core functions, including TWAnyAddressIsValid, should be available through FFI in Dart.

**Actual behavior**
Dart cannot find certain symbols from the library, leading to runtime errors.
--- comments ---
patamarot-boop 2026-02-17: 1,000,000,000
patamarot-boop 2026-02-17: []()
