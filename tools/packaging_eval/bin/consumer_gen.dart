// PRD §12.2 step 11 — consume the packages the way a real app will.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.

import 'dart:io';

import 'package:wcf_tool_packaging_eval/cli.dart';
import 'package:wcf_tool_packaging_eval/consumer_gen.dart';

const _usage = '''
Usage: dart run tools/packaging_eval/bin/consumer_gen.dart --out-dir DIR

Generates a fresh Flutter app that depends on the three packages as **hosted**
packages, never by path, and asserts the one thing that proves it:

  the consumer's pubspec.lock shows wallet_core_flutter,
  wallet_core_flutter_bindings and wallet_core_flutter_native with
  `source: hosted` and `description.url` equal to the local repository's URL,
  and the lock has no `path` entry at all.

How:

  1. Each of packages/* is copied to a staging directory with two edits:
     `resolution: workspace` and `publish_to` dropped, and every dependency on
     a sibling rewritten to `hosted: http://127.0.0.1:<port>` at its exact
     pinned version. The exact cross-pins survive, so the consumer resolves the
     same one-version-per-package set PRD §15.4 requires.
  2. Each staged copy is tarred (`tar -czf`) and hashed.
  3. A dart:io HttpServer on 127.0.0.1 serves the two routes the pub client
     needs: `GET /api/packages/<name>` (the version listing, with the embedded
     pubspec pub resolves against) and
     `GET /packages/<name>/versions/<version>.tar.gz` (the archive).
  4. `flutter create`, then `wallet_core_flutter: {hosted: <url>, version: …}`
     in the app's pubspec, then `flutter pub get`.

Everything is written under --out-dir, which must be outside the repository.
Building the generated app is the evaluations' job (T1.8, T1.9); this command
does not run `flutter build`.

Options:
  --out-dir DIR       Where to write the staging area and the consumer app.
                      Default \$TMPDIR/wcf-consumer-gen.
  --project-name NAME Default wcf_eval_consumer.
  --package DIR       A package to serve. Repeatable; defaults to the three.
  --keep-pub-cache    Do not delete the loopback entry the run leaves in the
                      pub cache.
  --print-lock        Print the lock stanzas for the three packages.
  --out FILE          Append the JSON result rows to FILE.
  -h, --help          This text.
''';

Future<void> main(List<String> arguments) async {
  final args = Args.parse(
    arguments,
    switches: {'keep-pub-cache', 'print-lock'},
  );
  if (args.flag('help')) {
    stdout.write(_usage);
    return;
  }

  final base = Platform.environment['TMPDIR'] ?? '/tmp';
  final outDirectory = Directory(
    args.option('out-dir') ??
        '${base.endsWith('/') ? base.substring(0, base.length - 1) : base}'
            '/wcf-consumer-gen',
  );
  final packages = args.options('package');

  final outcome = await generateHostedConsumer(
    outDirectory: outDirectory,
    packageDirectories: packages.isEmpty ? null : packages,
    projectName: args.option('project-name') ?? 'wcf_eval_consumer',
    keepPubCacheEntry: args.flag('keep-pub-cache'),
  );

  if (args.flag('print-lock') && outcome.lockExcerpt.isNotEmpty) {
    stdout
      ..writeln('--- pubspec.lock (the three packages) ---')
      ..write(outcome.lockExcerpt)
      ..writeln('--- end ---');
  }

  emit(outcome.rows, args.option('out'));
}
