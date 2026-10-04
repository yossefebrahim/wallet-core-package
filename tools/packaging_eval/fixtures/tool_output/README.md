# Saved tool output

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not
affiliated with or endorsed by Trust Wallet.

Every parser in `lib/` is a pure function over the text a system tool printed,
and every one of them is tested against text that tool really printed — the way
`tools/native_build/check_alignment.sh --readelf-output` is testable without an
Android build. Absolute paths in these files were rewritten to `<repo>`,
`<tmp>`, `<scratch>`, `$ANDROID_SDK` and `<xcode-toolchain>` so the fixtures do
not carry one machine's layout; nothing else was edited.

| File | Produced by | Against |
|---|---|---|
| `lipo_detailed_info_fat.txt` | `lipo -detailed_info` | our macOS `arm64_x86_64` dylib |
| `lipo_info_thin.txt` | `lipo -info` ×2 | our iOS device dylib, then the fat macOS one |
| `vtool_show_build_ios_arm64.txt` | `vtool -arch arm64 -show-build` | our iOS device dylib |
| `vtool_show_build_macos_x86_64.txt` | `vtool -arch x86_64 -show-build` | our macOS dylib |
| `otool_L_relinked_ios_arm64.txt` | `otool -L -arch arm64` | our iOS device dylib |
| `otool_L_upstream_ios_arm64.txt` | `otool -L -arch arm64` | upstream's `WalletCore.framework` device slice |
| `otool_D_relinked_ios_arm64.txt` | `otool -D -arch arm64` | our iOS device dylib |
| `otool_l_head_relinked_ios_arm64.txt` | `otool -l -arch arm64`, first 80 lines | our iOS device dylib |
| `codesign_unsigned.txt` | `codesign -dv` (exit 1) | our iOS device dylib |
| `nm_u_relinked_ios_arm64_head.txt` | `nm -u -arch arm64`, first 60 lines | our iOS device dylib |
| `nm_gU_relinked_ios_arm64_head.txt` | `nm -gU -arch arm64`, first 20 lines | our iOS device dylib |
| `llvm_readelf_l_16k.txt` | NDK r28.2 `llvm-readelf -l` | NDK r28.2's `libc++_shared.so`, `arm64-v8a` |
| `llvm_readelf_l_4k.txt` | NDK r28.2 `llvm-readelf -l` | NDK **r21.4**'s `libc++_shared.so`, `arm64-v8a` — a real 4 KB-aligned ELF |
| `check_alignment_pass.txt` | `check_alignment.sh --readelf-output` | the 16 KB output above |
| `check_alignment_fail.txt` | `check_alignment.sh --readelf-output` | the 4 KB output above |
| `check_exports_pass.txt` | `check_exports.sh --format macho` | our macOS dylib: 464/464, `_wcf_build_info` yes |
| `check_exports_no_identity.txt` | `check_exports.sh --format macho` | upstream's device framework: 464/464, `_wcf_build_info` **no** |
| `llvm_nm_dynamic_android_arm64_excerpt.txt` | NDK r28.2 `llvm-nm --dynamic --defined-only --extern-only`, 11 whole lines selected by name | our `android/arm64-v8a` `.so` (as_4.8.0_001, stripped): listed TW* names, upstream JNI glue, `wcf_build_info` |
| `llvm_nm_symtab_stripped_android_arm64.txt` | NDK r28.2 `llvm-nm --defined-only --extern-only` (no `--dynamic`), stdout and stderr | the same `.so`: `no symbols` — the harness defect fixed in T1.8b-d1 |
| `zipalign_check_pass.txt` | `zipalign -c -P 16 -v 4` | a zip built here with `zipalign -P 16 -f 4` |
| `zipalign_check_fail.txt` | `zipalign -c -P 16 -v 4`, first 10 lines | the same zip before alignment |

## The two that are not real output

`otool_l_rpaths_synthetic.txt` and `gradle_libcxx_*_synthetic.txt` say so in
their first lines and in their names. Nothing at 4.8.0 carries an `LC_RPATH`,
and no Android build log of the `libc++_shared.so` collision can exist until an
Android artifact does (DECISION-9 §4). Replace them with real output the first
time an evaluation produces it.

## The zipalign fixtures

Built here, from real tools, because no APK exists yet:

```
zip -0 unaligned.apk lib/<abi>/libc++_shared.so       # stored, as an APK does
zipalign -P 16 -f 4 unaligned.apk aligned.apk
zipalign -c -P 16 -v 4 aligned.apk                    # -> pass
zipalign -c -P 16 -v 4 unaligned.apk                  # -> fail, exit 1
```

`-P 16` and `-p` cannot be combined; `-p` aligns `.so` entries to 4 KB, which
`-c -P 16` then reports as `BAD - 4096`. That is the trap this fixture pair
exists to keep an evaluation out of.
