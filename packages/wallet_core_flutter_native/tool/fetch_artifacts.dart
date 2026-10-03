/// Downloads and verifies the native artifacts `compat_manifest.json` names
/// (PRD §12.3, DECISION-14 §3.1).
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
/// Not affiliated with or endorsed by Trust Wallet.
///
/// ```
/// dart run packages/wallet_core_flutter_native/tool/fetch_artifacts.dart --help
/// ```
///
/// **Build time only.** This file, and everything under `tool/`, is outside the
/// package's library API; nothing under `lib/` imports it and nothing here runs
/// in an application. AGENTS.md rule 3 forbids a socket in the SDK, the
/// bindings, and the loader; PRD §16 S4 allows one here and measures it
/// separately.
///
/// **What it trusts.** The manifest, and only the manifest. `compat_manifest.json`
/// is the integrity root for the artifacts (threat model TM-16): it is checked
/// into this repository, shipped inside this package, reviewed in the same pull
/// request that pins the checksums, and cross-checked at runtime by the three
/// packages' embedded copies. This tool therefore takes the digests it is given
/// as authoritative and spends its care on the bytes: every artifact is hashed
/// after it arrives and compared with the manifest's 64-hex `sha256` and its
/// recorded size, from every source — the network, the cache, a `--vendored`
/// directory — with no flag, environment variable, or code path that accepts a
/// mismatch (TM-14). What it will not do is act on a manifest that contradicts
/// itself: an `asset_name` whose embedded digest is not the record's `sha256`,
/// a `logical_name` that is not the map key, a base URL that is not `https://`.
/// Those cross-checks run before any socket is opened and duplicate
/// `tools/manifest/lib/validator.dart` deliberately, because a URL the manifest
/// contradicts is not a URL worth trying.
///
/// **Redirects: followed, up to 5, https on every hop.** GitHub Releases does
/// not serve asset bytes from `github.com`. A GET of
/// `https://github.com/<org>/<repo>/releases/download/<tag>/<asset>` answers
/// `302 Found` with a `Location` pointing at a short-lived signed URL on
/// `objects.githubusercontent.com`, and that is the documented, permanent shape
/// of the service — so a fetcher that refuses all redirects cannot download
/// from the primary at all, and a same-host allowlist would have to name a
/// second host we do not control the naming of. The two acceptable designs were
/// "follow redirects but verify the digest regardless" and an explicit host
/// allowlist; this tool takes the first. The digest is the control, not the
/// host: the manifest's sha256 is recomputed over whatever bytes arrive, from
/// whatever host finally serves them, and a redirect to an attacker's server
/// gains the attacker nothing it did not already have by controlling the
/// original response body. What is *not* relaxed is the scheme — every hop,
/// including the first, must be `https://`, so a redirect cannot downgrade the
/// transport, and the chain is capped at 5 hops rather than left to the client's
/// default. The one exception is `--allow-insecure-loopback`, which permits
/// plain `http` to `127.0.0.1`, `::1`, and `localhost` and nothing else; it
/// exists so the test suite can serve a fake artifact set from an `HttpServer`,
/// and it is refused for any routable host.
///
/// **Today it cannot fetch anything.** The shipped manifest is still the
/// placeholder shape: `retention.primary` is `TBD-T0.11`,
/// `identity.artifact_set_id` is `TBD-T1.2`, and each artifact record carries
/// only a `TBD-T1.2` digest and a zero size — none of the fourteen fields of
/// DECISION-14 §5.1 exists yet, because the CI native build (T1.2) has never
/// run. `--dry-run` prints exactly which fields stop it and which task fills
/// each one, and exits 2.
library;

import 'dart:io';

import 'src/fetcher.dart';

Future<void> main(List<String> args) async {
  exitCode = await runFetchArtifacts(
    args,
    scriptDir: File.fromUri(Platform.script).parent.path,
  );
}
