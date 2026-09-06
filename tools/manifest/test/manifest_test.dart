import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:wcf_tool_manifest/manifest.dart';
import 'package:wcf_tool_manifest/validator.dart';

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
