// Running a system tool and recording the exact command that ran.
//
// Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
// Not affiliated with or endorsed by Trust Wallet.
//
// Every measurement in this package is "shell out to a tool, then parse". The
// Dart side decides pass/fail; the tool's exact invocation goes into the
// result row verbatim, in the same copy-pasteable form
// tools/native_build/lib/common.sh's wcf_run prints.

import 'dart:convert';
import 'dart:io';

class RunResult {
  RunResult({
    required this.command,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  /// Shell-quoted, copy-pasteable.
  final String command;
  final int exitCode;
  final String stdout;
  final String stderr;

  bool get ok => exitCode == 0;

  /// stdout and stderr joined, for tools that split their report across both
  /// (the native_build gate scripts log to stderr).
  String get combined => [stdout, stderr].where((s) => s.isNotEmpty).join('\n');
}

/// POSIX shell quoting: bare when the word is safe, single-quoted otherwise.
String shellQuote(String word) {
  if (word.isNotEmpty && RegExp(r'^[A-Za-z0-9_@%+=:,./-]+$').hasMatch(word)) {
    return word;
  }
  return "'${word.replaceAll("'", r"'\''")}'";
}

String formatCommand(String executable, List<String> arguments) =>
    [executable, ...arguments].map(shellQuote).join(' ');

/// Runs [executable] and captures both streams. Never throws on a non-zero
/// exit: a failing gate is a measurement, not an error.
RunResult run(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) {
  final command = formatCommand(executable, arguments);
  final ProcessResult result;
  try {
    result = Process.runSync(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  } on ProcessException catch (e) {
    return RunResult(
      command: command,
      exitCode: 127,
      stdout: '',
      stderr: 'could not run $executable: ${e.message}',
    );
  }
  return RunResult(
    command: command,
    exitCode: result.exitCode,
    stdout: result.stdout as String,
    stderr: result.stderr as String,
  );
}

/// Like [run], but asynchronous.
///
/// Anything that runs while the local package repository is serving must use
/// this: `Process.runSync` blocks the event loop, so the loopback HttpServer
/// would never answer the pub client and the run would deadlock.
Future<RunResult> runAsync(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) async {
  final command = formatCommand(executable, arguments);
  final ProcessResult result;
  try {
    result = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  } on ProcessException catch (e) {
    return RunResult(
      command: command,
      exitCode: 127,
      stdout: '',
      stderr: 'could not run $executable: ${e.message}',
    );
  }
  return RunResult(
    command: command,
    exitCode: result.exitCode,
    stdout: result.stdout as String,
    stderr: result.stderr as String,
  );
}

/// Runs [executable] and streams stdout line by line to [onLine].
///
/// The duplicate-symbol scan reads tens of thousands of lines per binary; this
/// keeps that O(n) in time and out of one giant string (DECISION-9 §5 sizes an
/// upstream-style build at 57 174 exports).
Future<RunResult> runStreaming(
  String executable,
  List<String> arguments,
  void Function(String line) onLine,
) async {
  final command = formatCommand(executable, arguments);
  final Process process;
  try {
    process = await Process.start(executable, arguments);
  } on ProcessException catch (e) {
    return RunResult(
      command: command,
      exitCode: 127,
      stdout: '',
      stderr: 'could not run $executable: ${e.message}',
    );
  }
  final stderrBuffer = StringBuffer();
  final stderrDone = process.stderr
      .transform(utf8.decoder)
      .forEach(stderrBuffer.write);
  await process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach(onLine);
  await stderrDone;
  final exitCode = await process.exitCode;
  return RunResult(
    command: command,
    exitCode: exitCode,
    stdout: '',
    stderr: stderrBuffer.toString(),
  );
}
