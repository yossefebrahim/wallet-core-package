// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Written by `melos run gen:manifest`
// (tools/manifest/bin/embed.dart) from the repository root's
// compat_manifest.json. Edit that file, then regenerate.

/// Values embedded from `compat_manifest.json`, the integrity root of
/// PRD §15.3.
///
/// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core
/// library. Not affiliated with or endorsed by Trust Wallet.
///
/// **Why constants and not the shipped asset at runtime.** The identity
/// and release-set check of DECISION-14 §2.3 runs in the worker isolate
/// during `Init`, before `initialize()` returns (DECISION-12 §5).
/// `rootBundle` is unavailable there: asset loading needs a binary
/// messenger, which a plain isolate does not have. The same loader must
/// also work from a pure-Dart CLI, which has no asset bundle at all. So
/// the few values the check needs are compiled in, and the manifest copy
/// under `assets/` exists for the build-time fetch tool and for PRD
/// §15.3's "shipped inside the package".
///
/// **What [manifestSha256] is.** The sha256 of `compat_manifest.json`'s
/// bytes **exactly as committed** — not of a canonical re-serialisation
/// of its JSON. Both sides of comparison 2 therefore hash bytes: this
/// constant, and the asset copy, which is a byte copy of the same file.
/// T3.11 compares its own embedded copies against this definition.
///
/// A `TBD-<task>` value is a placeholder naming the task that fills it,
/// copied through unchanged. It means "unknown" and never compares equal
/// to anything, including itself.
library;

/// Manifest `identity.artifact_set_id` — the expected value of comparison 3
/// (DECISION-14 §2.3): `wcf_build_info().artifact_set_id` must equal it.
const String identityArtifactSetId = 'as_4.8.0_001';

/// Manifest `identity.symbol` — the C name of the build-identity symbol the
/// loader looks up. Its absence is a load failure, not a mismatch.
const String identitySymbol = 'wcf_build_info';

/// Manifest `identity.upstream_commit` — the expected value of comparison 4
/// (DECISION-14 §2.3): `wcf_build_info().upstream_commit` must equal it.
const String identityUpstreamCommit =
    'd692ac27749d0c615e17c751b70ab4f0aa75c59b';

/// The sha256 of `compat_manifest.json`'s bytes as committed — the expected
/// value of comparison 2 (DECISION-14 §2.3), which hashes the shipped asset
/// copy of the same file. See this library's doc comment for why it is the
/// file's bytes rather than a canonical re-serialisation.
const String manifestSha256 =
    'e41050ed55e186d22646badad034eaf729407bb8775f08257d0624cd3007ff0b';

/// Manifest `release_set` — this package's side of comparison 1
/// (DECISION-14 §2.3), which requires all three packages to carry the same
/// value. The other two packages gain their copies in T3.11.
const String releaseSetId = 'TBD-T3.11';

/// Manifest `upstream.commit` — the upstream commit this package set is
/// generated and tested against.
const String upstreamCommit = 'd692ac27749d0c615e17c751b70ab4f0aa75c59b';

/// Manifest `upstream.repo` — the upstream repository, `owner/name`.
const String upstreamRepo = 'trustwallet/wallet-core';

/// Manifest `upstream.tag` — the upstream release tag this set tracks.
const String upstreamTag = '4.8.0';
