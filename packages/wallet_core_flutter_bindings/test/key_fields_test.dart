/// Acceptance checks for the generated `key_fields.json`.
///
/// PRD §11.4's reviewed per-family key-field list starts from this file, and a
/// field missed here is a private key injected into a request nobody checked.
/// The assertions below are therefore about *completeness*, not shape: the
/// three families PRD §10.2 calls out by name, and the accounting of every
/// upstream `.proto` that mentions `private_key` at all.
///
/// The file is never hand-written; `melos run gen:proto` produces it.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

/// `lib/` of this package, resolved through the package config rather than
/// from the working directory, so the test behaves the same under
/// `melos run test` (cwd = package) and `dart test packages/...` (cwd = repo).
late final Uri libDir;
Uri get packageDir => libDir.resolve('../');
Uri get repoDir => packageDir.resolve('../../');

const keyFieldsPath = 'lib/src/generated/proto/key_fields.json';

Future<Map<String, Object?>> readKeyFields() async {
  libDir = (await Isolate.resolvePackageUri(
    Uri.parse('package:wallet_core_flutter_bindings/'),
  ))!;
  final file = File.fromUri(
    libDir.resolve('src/generated/proto/key_fields.json'),
  );
  expect(
    file.existsSync(),
    isTrue,
    reason: '$keyFieldsPath is missing; run `melos run gen:proto`',
  );
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

Map<String, Object?> messages(Map<String, Object?> doc) =>
    doc['messages']! as Map<String, Object?>;

Map<String, Object?> message(Map<String, Object?> doc, String qualifiedName) {
  final entry = messages(doc)[qualifiedName];
  expect(
    entry,
    isNotNull,
    reason: 'no key_fields.json entry for $qualifiedName',
  );
  return entry! as Map<String, Object?>;
}

List<Map<String, Object?>> fieldsOf(Map<String, Object?> entry) =>
    (entry['fields']! as List<Object?>).cast<Map<String, Object?>>();

Map<String, Object?> field(Map<String, Object?> entry, String protoName) {
  final matches = fieldsOf(
    entry,
  ).where((f) => f['protoName'] == protoName).toList();
  expect(matches, hasLength(1), reason: 'expected one $protoName field');
  return matches.single;
}

void main() {
  late Map<String, Object?> doc;

  setUpAll(() async => doc = await readKeyFields());

  group('Ethereum', () {
    test('SigningInput carries private_key, exposed in Dart as privateKey', () {
      final f = field(
        message(doc, 'TW.Ethereum.Proto.SigningInput'),
        'private_key',
      );
      expect(f['dartName'], 'privateKey');
      expect(f['type'], 'bytes');
      expect(f['repeated'], isFalse);
    });

    test('MessageSigningInput carries one too (PRD §11.1)', () {
      field(
        message(doc, 'TW.Ethereum.Proto.MessageSigningInput'),
        'private_key',
      );
    });
  });

  group('Bitcoin', () {
    test('private_key is listed and marked repeated', () {
      final f = field(
        message(doc, 'TW.Bitcoin.Proto.SigningInput'),
        'private_key',
      );
      expect(
        f['repeated'],
        isTrue,
        reason:
            'upstream declares `repeated bytes private_key`; a signer '
            'that assumes one key cannot spend an ordinary transaction',
      );
      expect(f['dartName'], 'privateKey');
    });
  });

  group('Solana', () {
    test('all three differently named key fields are listed', () {
      // Two sit on SigningInput; nonce_account_private_key sits on the nested
      // CreateNonceAccount message reached through SigningInput's transaction
      // oneof, which is why the generator walks the whole message tree rather
      // than the top level of SigningInput.
      final signingInput = message(doc, 'TW.Solana.Proto.SigningInput');
      expect(field(signingInput, 'private_key')['dartName'], 'privateKey');
      expect(
        field(signingInput, 'fee_payer_private_key')['dartName'],
        'feePayerPrivateKey',
      );

      final createNonce = message(doc, 'TW.Solana.Proto.CreateNonceAccount');
      expect(
        field(createNonce, 'nonce_account_private_key')['dartName'],
        'nonceAccountPrivateKey',
      );
    });

    test('every Solana key field is reachable from byFile', () {
      final byFile = doc['byFile']! as Map<String, Object?>;
      final names = (byFile['Solana.proto']! as List<Object?>).cast<String>();
      final protoNames = <String>{
        for (final n in names)
          for (final f in fieldsOf(message(doc, n))) f['protoName']! as String,
      };
      expect(
        protoNames,
        containsAll(<String>[
          'private_key',
          'nonce_account_private_key',
          'fee_payer_private_key',
        ]),
      );
    });
  });

  group('completeness', () {
    test('every mentioning .proto is accounted for, with one enum-only '
        'exception', () {
      final byFile = (doc['byFile']! as Map<String, Object?>).keys.toSet();
      final withoutFields =
          (doc['mentionsWithoutFieldMatches']! as Map<String, Object?>);

      // 46 of upstream's 60 .proto files contain the string `private_key`.
      expect(byFile.length + withoutFields.length, 46);

      // Exactly one of them declares no such field: Common.proto, where the
      // matches are SigningError *enum value* names, not key material. If this
      // set ever grows, a real key field has stopped being recognised and the
      // generator — not this expectation — is what must change.
      expect(withoutFields.keys, <String>['Common.proto']);
      expect(
        (withoutFields['Common.proto']! as List<Object?>).cast<String>(),
        <String>[
          'Error_missing_private_key = 5;',
          'Error_invalid_private_key = 15;',
        ],
      );
    });

    test('summary counts match the recorded entries', () {
      final summary = doc['summary']! as Map<String, Object?>;
      final byFile = doc['byFile']! as Map<String, Object?>;

      expect(summary['protoFilesScanned'], 60);
      expect(summary['protoFilesWithKeyFields'], byFile.length);
      expect(summary['messages'], messages(doc).length);
      expect(
        summary['fields'],
        messages(doc).values
            .map((m) => fieldsOf(m as Map<String, Object?>).length)
            .fold<int>(0, (a, b) => a + b),
      );
    });

    test('the document records no key values, only field names', () {
      // Rule 6: this file exists so that keys stay out of requests. It carries
      // names, numbers, and types — never a value.
      for (final entry in messages(doc).values) {
        for (final f in fieldsOf(entry as Map<String, Object?>)) {
          expect(f.keys.toSet(), <String>{
            'protoName',
            'dartName',
            'number',
            'repeated',
            'type',
          });
        }
      }
    });

    test('matches a fresh scan of the pinned upstream .proto files', () {
      // The direct form of the acceptance criterion, available only when the
      // upstream tree has been fetched. Skipped otherwise so the committed
      // bindings still test without third_party/.
      // Present only after `melos run upstream:fetch`; git-ignored, and absent
      // for a consumer who never fetches upstream.
      final dir = Directory.fromUri(
        repoDir.resolve('third_party/wallet-core/src/proto/'),
      );
      if (!dir.existsSync()) {
        markTestSkipped('run `melos run upstream:fetch` to enable this check');
        return;
      }

      final mentioning = <String>{};
      for (final entity in dir.listSync()) {
        if (entity is! File || !entity.path.endsWith('.proto')) continue;
        if (entity.readAsStringSync().contains('private_key')) {
          mentioning.add(entity.uri.pathSegments.last);
        }
      }

      final accounted = <String>{
        ...(doc['byFile']! as Map<String, Object?>).keys,
        ...(doc['mentionsWithoutFieldMatches']! as Map<String, Object?>).keys,
      };

      expect(mentioning, isNotEmpty);
      expect(
        accounted,
        mentioning,
        reason:
            'key_fields.json and the pinned .proto files disagree about '
            'which files mention private_key',
      );
    });
  });

  group('provenance', () {
    test('records the upstream pin it was generated from', () {
      final upstream = doc['upstream']! as Map<String, Object?>;
      final manifest =
          jsonDecode(
                File.fromUri(
                  repoDir.resolve('compat_manifest.json'),
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      final pinned = manifest['upstream']! as Map<String, Object?>;

      expect(upstream['commit'], pinned['commit']);
      expect(upstream['tag'], pinned['tag']);
      expect(upstream['repo'], pinned['repo']);
      expect(
        upstream['proto_dir_sha'],
        (manifest['schemas']! as Map<String, Object?>)['proto_dir_sha'],
      );
    });
  });
}
