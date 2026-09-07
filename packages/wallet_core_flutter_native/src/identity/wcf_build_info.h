/* wcf_build_info.h — the build-identity symbol of PRD §12.3 / DECISION-14 §2.
 *
 * Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
 * Not affiliated with or endorsed by Trust Wallet.
 *
 * Upstream 4.8.0 exposes no library-version symbol (DECISION-9 §1, evidence
 * F6), so the identity of an artifact has to be ours. This header is compiled
 * into every native artifact this project publishes, on every platform, by the
 * scripts under tools/native_build/.
 */

#ifndef WCF_BUILD_INFO_H
#define WCF_BUILD_INFO_H

/* Export annotation, required by DECISION-14 §2.1 (D0 finding F9).
 *
 * The symbol must be exported *explicitly* rather than by default: the Android
 * build is tuned for JNI and may compile with -fvisibility=hidden (upstream
 * issue #4638), and a hidden identity symbol is indistinguishable at load time
 * from an artifact that was mirrored without a relink.
 *
 * __attribute__((visibility("default"))) is accepted identically by Apple's
 * clang (Mach-O) and the Android NDK's clang (ELF) — the NDK's own JNIEXPORT
 * expands to exactly it. The _WIN32 arm exists only so this file compiles
 * unchanged if a host build is ever added; no Windows artifact is published.
 *
 * The annotation does not replace the export gate, it is checked by it:
 * tools/native_build/check_exports.sh runs
 *   llvm-nm --defined-only --extern-only <artifact>
 * on every artifact and fails the build unless this symbol is present
 * (_wcf_build_info on Mach-O, wcf_build_info on ELF). A version script or
 * --gc-sections can still drop an annotated symbol; that is what the gate
 * exists to catch.
 */
#if defined(_WIN32)
#  define WCF_EXPORT __declspec(dllexport)
#else
#  define WCF_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Returns a NUL-terminated UTF-8 JSON object with exactly three keys:
 *
 *   {"upstream_commit":"<40 lowercase hex>",
 *    "artifact_set_id":"as_<upstreamTag>_<nnn>",
 *    "build_workflow":"<absolute workflow-run URL>"}
 *
 * The returned pointer is static storage owned by the library. The caller must
 * not free it, and it is NOT a TWString — upstream's delete functions must
 * never be called on it. It stays valid for the lifetime of the loaded image.
 *
 * A reader ignores keys it does not know, so the format can gain a field
 * without breaking an older loader (DECISION-14 §2.1).
 */
WCF_EXPORT const char *wcf_build_info(void);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* WCF_BUILD_INFO_H */
