/* wcf_build_info.c — the build-identity symbol of PRD §12.3 / DECISION-14 §2.
 *
 * Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
 * Not affiliated with or endorsed by Trust Wallet.
 *
 * This translation unit is linked into every native artifact this project
 * publishes: into the relinked Apple dynamic libraries (DECISION-9 Option A′)
 * and into the Android libraries built from source (Option B). It contains no
 * cryptography and calls nothing; it exists so that a loaded image can state
 * which upstream commit it came from and which artifact set it belongs to,
 * which upstream 4.8.0 provides no way to ask (DECISION-9 §1).
 *
 * THE THREE VALUES ARE INJECTED AT BUILD TIME, NOT HARD-CODED.
 * The build scripts pass them as preprocessor definitions:
 *
 *   clang -c wcf_build_info.c \
 *     -DWCF_UPSTREAM_COMMIT="\"d692ac27749d0c615e17c751b70ab4f0aa75c59b\"" \
 *     -DWCF_ARTIFACT_SET_ID="\"as_4.8.0_001\"" \
 *     -DWCF_BUILD_WORKFLOW="\"https://github.com/<org>/<repo>/actions/runs/<id>\""
 *
 * Injection rather than generation, for three reasons:
 *   1. The file in the repository is the file that is reviewed. A generator
 *      that writes a .c into a build directory means the reviewed source and
 *      the compiled source are two different texts.
 *   2. The values are per-run (the workflow-run URL and the artifact-set id
 *      are only known once the run exists), so they cannot live in a checked-in
 *      file without being stale or a lie.
 *   3. -D values are visible in the build log and in the compiler's own
 *      command line, so what was injected is recoverable from the run.
 *
 * A build that forgets to inject fails to compile (below) rather than shipping
 * a library that claims an identity it does not have. The values are also
 * checked for shape by the caller — see tools/native_build/lib/common.sh,
 * wcf_require_identity_values — because the preprocessor can only check length.
 */

#include "wcf_build_info.h"

#if !defined(WCF_UPSTREAM_COMMIT) || !defined(WCF_ARTIFACT_SET_ID) || \
    !defined(WCF_BUILD_WORKFLOW)
#  error "wcf_build_info.c: identity values were not injected. Define all of \
WCF_UPSTREAM_COMMIT, WCF_ARTIFACT_SET_ID and WCF_BUILD_WORKFLOW as quoted \
string literals on the compiler command line. tools/native_build/ does this."
#endif

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
/* A commit is 40 lowercase hex characters; the literal therefore occupies 41
 * bytes including the terminator. This catches an empty or truncated
 * injection — for example a shell that lost the inner quotes — at compile
 * time. It cannot check that the characters are hex; the scripts do that. */
_Static_assert(sizeof(WCF_UPSTREAM_COMMIT) == 41,
               "WCF_UPSTREAM_COMMIT must be exactly 40 characters");
/* "as_<tag>_<nnn>" is at least "as_0_000". */
_Static_assert(sizeof(WCF_ARTIFACT_SET_ID) >= 9,
               "WCF_ARTIFACT_SET_ID must look like as_<tag>_<nnn>");
_Static_assert(sizeof(WCF_BUILD_WORKFLOW) > 1,
               "WCF_BUILD_WORKFLOW must not be empty");
#endif

/* Static storage with static duration, assembled by the preprocessor so that
 * the JSON is a single string constant in __TEXT/.rodata. `strings` on the
 * shipped artifact finds it, which is the cheapest possible identity check.
 *
 * Key order follows DECISION-14 §2.1. Exactly three keys, no more. */
static const char kWcfBuildInfoJson[] =
    "{"
    "\"upstream_commit\":\"" WCF_UPSTREAM_COMMIT "\","
    "\"artifact_set_id\":\"" WCF_ARTIFACT_SET_ID "\","
    "\"build_workflow\":\"" WCF_BUILD_WORKFLOW "\""
    "}";

WCF_EXPORT const char *wcf_build_info(void) { return kWcfBuildInfoJson; }
