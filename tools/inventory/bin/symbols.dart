import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wcf_tool_inventory/generated.dart';
import 'package:wcf_tool_inventory/headers.dart';
import 'package:wcf_tool_inventory/inventory.dart';
import 'package:wcf_tool_upstream/dist.dart';
import 'package:wcf_tool_upstream/hashing.dart';

const _bindingsPackage = 'packages/wallet_core_flutter_bindings';
const _defaultGenerated =
    '$_bindingsPackage/lib/src/generated/ffi/'
    'wallet_core_bindings.dart';
const _defaultOut = '$_bindingsPackage/lib/src/generated/inventory.json';

const _usage =
    '''
Usage: dart run tools/inventory/bin/symbols.dart [options]

Writes the generated symbol inventory (PRD §9): every function and enum
upstream's headers declare, every one the generated Dart binds, and the
provenance of the header set that produced them.

  --check              Do not write. Fail if inventory.json on disk is not
                       what this run would write.
  --dist-root <dir>    Release-asset headers (default: $defaultDistDestination)
  --generated <path>   ffigen output
                       (default: $_defaultGenerated)
  --out <path>         Inventory to write
                       (default: $_defaultOut)
  -h, --help           Print this help.

Exits non-zero when a symbol the headers declare is not bound.
''';

Future<void> main(List<String> args) async {
  var check = false;
  var distRoot = defaultDistDestination;
  var generatedPath = _defaultGenerated;
  var outPath = _defaultOut;

  String valueFor(String flag, int index) {
    if (index + 1 >= args.length) {
      stderr.writeln('$flag needs a value.');
      exit(2);
    }
    return args[index + 1];
  }

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--check':
        check = true;
      case '--dist-root':
        distRoot = valueFor(args[i], i);
        i++;
      case '--generated':
        generatedPath = valueFor(args[i], i);
        i++;
      case '--out':
        outPath = valueFor(args[i], i);
        i++;
      case '-h':
      case '--help':
        stdout.write(_usage);
        return;
      default:
        stderr.writeln('Unknown argument "${args[i]}".\n\n$_usage');
        exit(2);
    }
  }

  final distDirectory = Directory(distRoot);
  final headersDirectory = Directory(
    p.join(distRoot, p.joinAll(p.posix.split(distHeadersSubdirectory))),
  );

  final provenance = readDistProvenance(distDirectory);
  final declared = scanHeaders(headersDirectory);

  // The provenance record describes an extraction; the headers on disk are
  // what ffigen actually read. Recomputing T1.1's directory digest is what
  // makes the record a statement about *these* bytes rather than a label.
  final digest = hashDirectory(headersDirectory);
  if (digest.sha256 != provenance.dirSha256) {
    stderr.writeln(
      'The headers under ${headersDirectory.path} are not the ones\n'
      '$distProvenanceFile describes:\n'
      '  recorded ${provenance.dirSha256} (${provenance.fileCount} files)\n'
      '  on disk  ${digest.sha256} (${digest.fileCount} files)\n'
      'Re-run: melos run upstream:fetch -- --dist-only --from-dist <asset>',
    );
    exit(1);
  }

  final bound = scanGenerated(File(generatedPath));
  final inventory = buildInventory(
    headers: provenance,
    declared: declared,
    bound: bound,
    generatedPath: p.posix.joinAll(
      p.split(p.relative(generatedPath, from: _bindingsPackage)),
    ),
  );
  final rendered = inventory.render();

  final counts = inventory.toJson()['counts']! as Map<String, Object?>;
  stdout
    ..writeln(
      'headers:   ${provenance.archiveName} @ ${provenance.tag} '
      '(${provenance.fileCount} files, ${provenance.dirSha256})',
    )
    ..writeln('functions: ${counts['functions']}')
    ..writeln('enums:     ${counts['enums']}')
    ..writeln(
      'exported TW* functions: ${counts['exported_tw_functions']} '
      '(the list tools/native_build/check_exports.sh reconciles)',
    );

  if (bound.nonFunctionLookups.isNotEmpty) {
    stdout.writeln(
      'data symbols bound: ${bound.nonFunctionLookups.length} '
      '(${bound.nonFunctionLookups.take(5).join(', ')})',
    );
  }
  if (inventory.extra.isNotEmpty) {
    stdout.writeln(
      'bound but not declared in the headers (${inventory.extra.length}): '
      '${inventory.extra.join(', ')}',
    );
  }

  final outFile = File(outPath);
  if (check) {
    if (!outFile.existsSync()) {
      stderr.writeln('$outPath does not exist. Run `melos run gen:ffi`.');
      exit(1);
    }
    if (outFile.readAsStringSync() != rendered) {
      stderr.writeln(
        '$outPath is stale: it is not what this run would write.\n'
        'Run `melos run gen:ffi` and commit the result.',
      );
      exit(1);
    }
    stdout.writeln('$outPath: up to date');
  } else {
    outFile.parent.createSync(recursive: true);
    final changed =
        !outFile.existsSync() || outFile.readAsStringSync() != rendered;
    if (changed) outFile.writeAsStringSync(rendered);
    stdout.writeln('$outPath: ${changed ? "updated" : "unchanged"}');
  }

  // PRD §9: "any missing symbol fails the build". Checked after the file is
  // written, so the inventory naming the gap is on disk to look at.
  if (inventory.missing.isNotEmpty) {
    stderr
      ..writeln(
        '\n${inventory.missing.length} symbol(s) declared in the headers are '
        'not bound by the generated code:',
      )
      ..writeln(inventory.missing.map((s) => '  $s').join('\n'))
      ..writeln(
        '\nAdjust packages/wallet_core_flutter_bindings/ffigen.yaml and '
        'regenerate; never hand-edit lib/src/generated/.',
      );
    exit(1);
  }
}
