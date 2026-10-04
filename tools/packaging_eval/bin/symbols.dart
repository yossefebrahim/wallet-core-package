// PRD §12.2 step 4 — export presence and visibility of the shipped library.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.

import 'dart:io';

import 'package:wcf_tool_packaging_eval/cli.dart';
import 'package:wcf_tool_packaging_eval/host.dart';
import 'package:wcf_tool_packaging_eval/measurements.dart';
import 'package:wcf_tool_packaging_eval/results.dart';

const _usage = r'''
Usage: dart run tools/packaging_eval/bin/symbols.dart --artifact FILE \
           --format macho|elf --target ID [--no-expect-identity] \
           [--allow-extra NAME]...

Reconciles the exported symbols of a shipped library against the canonical
list, per architecture. Mach-O calls the build's own gate rather than
reimplementing it:

  tools/native_build/check_exports.sh --binary <artifact> \
      --symbol-list <derived> --format macho [--nm <llvm-nm>]

ELF reads the dynamic symbol table, the only one a stripped release .so keeps
and the one dlsym resolves against: the command the gate runs for ELF since
56560e8, run here so the result does not depend on the gate's version:

  <ndk>/toolchains/llvm/prebuilt/<host>/bin/llvm-nm --dynamic \
      --defined-only --extern-only <artifact>

The symbol list is derived at run time from
packages/wallet_core_flutter_bindings/lib/src/generated/inventory.json — the
464 `TW*` functions it records as declared and bound — and written to a
temporary file. No copy of the list is kept here: a hand-maintained one goes
stale silently.

Options:
  --artifact FILE        The library to check.
  --format macho|elf     Mach-O names carry a leading underscore.
  --target ID            The column the rows land in.
  --inventory FILE       Override the inventory.json location.
  --nm PATH              llvm-nm to use. Required for ELF on macOS: pass
                         $ANDROID_NDK/toolchains/llvm/prebuilt/<host>/bin/llvm-nm.
  --no-expect-identity   Do not require `wcf_build_info`. Set it for a library
                         we did not relink — upstream's own framework carries
                         no identity symbol, and that is a fact to record, not
                         a failure of a packaging option.
  --allow-extra NAME     ELF: a TW* export outside the list that is not a
                         failure (repeatable): upstream's Android JNI glue,
                         as tools/native_build/build_android.sh allows it.
  --out FILE             Append the JSON result rows to FILE.
  -h, --help             This text.

The *runtime* half of step 4 — DynamicLibrary.lookup over the full set — is
T1.7's `symbolLookupAll` and runs on a device. This command records that row as
`unmeasured` with the command; it does not run apps.
''';

void main(List<String> arguments) {
  final args = Args.parse(arguments, switches: {'no-expect-identity'});
  if (args.flag('help')) {
    stdout.write(_usage);
    return;
  }

  void usage() => stdout.write(_usage);
  final artifact = args.require('artifact', usage);
  final format = args.option('format') ?? 'macho';
  final target = args.option('target') ?? artifact;

  var nm = args.option('nm');
  if (format == 'elf' && nm == null) nm = ndkLlvmTool('llvm-nm');

  final rows = <ResultRow>[
    ...measureSymbols(
      artifact: artifact,
      format: format,
      target: target,
      inventoryPath: args.option('inventory'),
      nmPath: nm,
      expectIdentity: !args.flag('no-expect-identity'),
      allowExtra: args.options('allow-extra'),
    ),
  ];

  emit(rows, args.option('out'));
}
