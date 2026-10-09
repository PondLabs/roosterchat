// ignore_for_file: avoid_print

import 'dart:io';

Future<ProcessResult> getDependencies() async {
  var process = Process.runSync(
    "flutter",
    [
      "pub",
      "get",
    ],
    runInShell: true,
  );

  print(process.stdout);
  print(process.stderr);
  return process;
}

/// The translations (lib/generated/intl, lib/generated/l10n.dart) from the
/// ARB files in assets/l10n. See docs/localization.md.
Future<ProcessResult> intlUtilsGenerate() async {
  var process = await Process.run(
    "flutter",
    [
      "pub",
      "run",
      "intl_utils:generate",
    ],
    runInShell: true,
  );

  print(process.stdout);
  print(process.stderr);
  return process;
}

Future<ProcessResult> buildRunner() async {
  var process = await Process.run(
    "flutter",
    [
      "pub",
      "run",
      "build_runner",
      "build",
      "--delete-conflicting-outputs",
    ],
    runInShell: true,
  );

  print(process.stdout);
  print(process.stderr);
  return process;
}

void main() async {
  var result = await getDependencies();
  if (result.exitCode != 0) {
    exit(result.exitCode);
  }

  result = await intlUtilsGenerate();
  if (result.exitCode != 0) {
    exit(result.exitCode);
  }

  result = await buildRunner();
  if (result.exitCode != 0) {
    exit(result.exitCode);
  }
}
