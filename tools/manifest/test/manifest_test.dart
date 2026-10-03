import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:wcf_tool_manifest/manifest.dart';
import 'package:wcf_tool_manifest/validator.dart';

/// Tag 4.8.0 of trustwallet/wallet-core, the pin T1.1 resolved.
const pinnedCommit = 'd692ac27749d0c615e17c751b70ab4f0aa75c59b';

void main() {
  final manifestPath = '../../compat_manifest.json';

  test(
    'checked-in manifest loads and validates with zero problems in non-strict mode',
    () {
      final jsonStr = File(manifestPath).readAsStringSync();
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      final errors = validateManifest(decoded, strict: false);
      expect(errors, isEmpty);

      final manifest = Manifest.load(manifestPath);
      expect(manifest.upstream.repo, equals('trustwallet/wallet-core'));
    },
  );

  test('strict mode reports every placeholder', () {
    final jsonStr = File(manifestPath).readAsStringSync();
    final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
    final errors = validateManifest(decoded, strict: true);
    expect(errors.isNotEmpty, isTrue);
    expect(errors.any((e) => e.contains('Placeholder found')), isTrue);
  });

  test('fixture with an extra key produces expected problem', () {
    final jsonStr = File(manifestPath).readAsStringSync();
    final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
    decoded['extra_key'] = 'hello';
    final errors = validateManifest(decoded);
    expect(errors, contains(contains('Unexpected keys at root: extra_key')));
  });

  test('fixture with a missing key produces expected problem', () {
    final jsonStr = File(manifestPath).readAsStringSync();
    final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
    decoded.remove('packages');
    final errors = validateManifest(decoded);
    expect(errors, contains(contains('Missing keys at root: packages')));
  });

  test('fixture with a bad sha produces expected problem', () {
    final jsonStr = File(manifestPath).readAsStringSync();
    final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
    (decoded['artifacts']
            as Map<
              String,
              dynamic
            >)['android/arm64-v8a/libTrustWalletCore.so']['sha256'] =
        'bad_sha';
    final errors = validateManifest(decoded);
    expect(
      errors,
      contains(
        contains(
          'Invalid sha256 at artifacts["android/arm64-v8a/libTrustWalletCore.so"].sha256: bad_sha',
        ),
      ),
    );
  });

  // --- Semantic checks for the fields T1.1 resolves (D0 finding F15) ---

  Map<String, dynamic> resolvedManifest() {
    final decoded =
        jsonDecode(File(manifestPath).readAsStringSync())
            as Map<String, dynamic>;
    (decoded['upstream'] as Map<String, dynamic>)['commit'] = pinnedCommit;
    (decoded['identity'] as Map<String, dynamic>)['upstream_commit'] =
        pinnedCommit;
    final schemas = decoded['schemas'] as Map<String, dynamic>;
    for (final k in schemas.keys.toList()) {
      schemas[k] = 'a' * 64;
    }
    return decoded;
  }

  test('a resolved upstream/schemas block passes both modes', () {
    expect(validateManifest(resolvedManifest()), isEmpty);
    final strictErrors = validateManifest(resolvedManifest(), strict: true);
    expect(
      strictErrors.where(
        (e) => e.contains('upstream.') || e.contains('schemas.'),
      ),
      isEmpty,
    );
  });

  test('upstream.commit must be 40 lowercase hex once resolved', () {
    for (final bad in [
      'deadbeef',
      '${pinnedCommit}0',
      pinnedCommit.toUpperCase(),
      'not-a-sha',
    ]) {
      final decoded = resolvedManifest();
      (decoded['upstream'] as Map<String, dynamic>)['commit'] = bad;
      (decoded['identity'] as Map<String, dynamic>)['upstream_commit'] = bad;
      expect(
        validateManifest(decoded),
        contains(contains('Invalid commit sha at upstream.commit')),
        reason: bad,
      );
    }
  });

  test('upstream.commit placeholder is an error only under --strict', () {
    final decoded = resolvedManifest();
    (decoded['upstream'] as Map<String, dynamic>)['commit'] = 'TBD-T1.1';
    (decoded['identity'] as Map<String, dynamic>)['upstream_commit'] =
        'TBD-T1.1';
    expect(validateManifest(decoded), isEmpty);
    expect(
      validateManifest(decoded, strict: true),
      contains(contains('Placeholder found in strict mode at upstream.commit')),
    );
  });

  test('upstream.repo and upstream.tag must be non-empty', () {
    for (final key in ['repo', 'tag']) {
      final decoded = resolvedManifest();
      (decoded['upstream'] as Map<String, dynamic>)[key] = '   ';
      expect(
        validateManifest(decoded),
        contains(contains('Empty value at upstream.$key')),
        reason: key,
      );
    }
  });

  test('schemas.* must be 64 lowercase hex once resolved', () {
    for (final key in ['proto_dir_sha', 'registry_json_sha', 'headers_sha']) {
      for (final bad in ['abc', 'A' * 64, '${'a' * 64}0', 'g' * 64]) {
        final decoded = resolvedManifest();
        (decoded['schemas'] as Map<String, dynamic>)[key] = bad;
        expect(
          validateManifest(decoded),
          contains(contains('Invalid sha256 at schemas.$key')),
          reason: '$key = $bad',
        );
      }
    }
  });

  test('schemas.* placeholders are an error only under --strict', () {
    final decoded = resolvedManifest();
    (decoded['schemas'] as Map<String, dynamic>)['headers_sha'] = 'TBD-T1.1';
    expect(validateManifest(decoded), isEmpty);
    expect(
      validateManifest(decoded, strict: true),
      contains(
        contains('Placeholder found in strict mode at schemas.headers_sha'),
      ),
    );
  });

  test('identity.upstream_commit must agree with upstream.commit', () {
    final decoded = resolvedManifest();
    (decoded['identity'] as Map<String, dynamic>)['upstream_commit'] = '0' * 40;
    expect(
      validateManifest(decoded),
      contains(
        contains('identity.upstream_commit (${'0' * 40}) does not match'),
      ),
    );
  });

  test('fixture with a bad version produces expected problem', () {
    final jsonStr = File(manifestPath).readAsStringSync();
    final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
    (decoded['packages'] as Map<String, dynamic>)['wallet_core_flutter'] =
        'not-a-version';
    final errors = validateManifest(decoded);
    expect(
      errors,
      contains(
        contains(
          'Invalid semver at packages.wallet_core_flutter: not-a-version',
        ),
      ),
    );
  });
}
