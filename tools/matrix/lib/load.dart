import 'dart:io';

import 'package:wcf_tool_vectors/inventory.dart';

import 'inputs.dart';
import 'protos.dart';
import 'registry.dart';

/// Reads every input named by [paths]. Throws [FormatException] with the path
/// and the remedy when one is absent or unreadable.
MatrixInputs loadInputs(MatrixPaths paths) => MatrixInputs(
  upstream: readUpstream(File(paths.manifestFile)),
  coins: readRegistry(Directory(paths.registryDir)),
  protoMessages: readProtoMessages(Directory(paths.protoDir)),
  evidence: readCoverageEvidence(File(paths.evidenceFile)),
  exposed: readExposed(File(paths.exposedFile)),
  inventory: Inventory.load(Directory(paths.vectorsDir)),
);
