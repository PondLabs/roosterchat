// The parts of the self updater that decide whether to touch an install,
// and the script that does the touching.
//
// The swap script is run for real here, against directories that are not an
// install: it is the one piece that can leave somebody without a working
// build, so "it looks right" is not enough.
@TestOn('linux')
library;

import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:rooster/utils/updater/self_updater_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// A pid that has already exited, so the script's wait loop falls straight
/// through. Started and reaped here rather than guessed at.
Future<int> deadPid() async {
  final process = await Process.start('/bin/sh', ['-c', 'exit 0']);
  await process.exitCode;
  return process.pid;
}

/// `install/` holding a file that says which build it is.
Directory buildDir(Directory parent, String name, String marker) {
  final dir = Directory(p.join(parent.path, name))..createSync(recursive: true);
  File(p.join(dir.path, 'which')).writeAsStringSync(marker);
  // Every bundle has the executable in it; the script starts it at the end.
  File(p.join(dir.path, 'rooster')).writeAsStringSync('');
  return dir;
}

Future<ProcessResult> runSwap({
  required Directory work,
  required String install,
  required String staged,
  String exe = '/bin/true',
  int? waitFor,
  String? restart,
  String? didNotStart,
  Duration patience = const Duration(seconds: 60),
  Duration settle = const Duration(seconds: 10),
}) async {
  final script = File(p.join(work.path, 'install.sh'));
  script.writeAsStringSync(linuxSwapScript(
    waitFor: waitFor ?? await deadPid(),
    staged: staged,
    install: install,
    exe: exe,
    work: work.path,
    stamp: 1234,
    restart: restart,
    didNotStart: didNotStart,
    patience: patience,
    settle: settle,
  ));
  return Process.run('/bin/sh', [script.path]);
}

/// A script standing in for a build that runs [body].
File program(Directory root, String name, String body) {
  final file = File(p.join(root.path, name))
    ..writeAsStringSync('#!/bin/sh\n$body\n');
  Process.runSync('chmod', ['+x', file.path]);
  return file;
}

/// A script standing in for a build: running it writes [marker].
File launcher(Directory root, String name, String marker) {
  final file = File(p.join(root.path, name))
    ..writeAsStringSync('#!/bin/sh\necho up > $marker\n');
  Process.runSync('chmod', ['+x', file.path]);
  return file;
}

/// Waits a little for a backgrounded launch to land.
Future<bool> appears(String path) async {
  for (var i = 0; i < 50 && !File(path).existsSync(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return File(path).existsSync();
}

void main() {
  test('the archive is named after the ABI the build runs as', () {
    // An arm64 build asks for the arm64 archive: the x64 one would not start.
    expect(archName(Abi.windowsArm64), 'arm64');
    expect(archName(Abi.linuxArm64), 'arm64');
    expect(archName(Abi.macosArm64), 'arm64');
    // An x64 build, even one emulated on an arm64 Windows, stays x64.
    expect(archName(Abi.windowsX64), 'x64');
    expect(archName(Abi.linuxX64), 'x64');
    expect(archName(Abi.macosX64), 'x64');
    // Whatever this test runs as, the name is one the release has.
    expect(['x64', 'arm64'], contains(archName(Abi.current())));
  });

  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('rooster-upd-'));
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  group('what may be replaced', () {
    test('a build unpacked into a home directory is ours', () {
      expect(isSelfInstallable('linux', '/home/lion/rooster/rooster'), isTrue);
      expect(isSelfInstallable('windows', r'C:\Users\lion\Rooster\rooster.exe'),
          isTrue);
    });

    test('anything a package manager owns is left alone', () {
      for (final path in [
        '/usr/bin/rooster',
        '/usr/lib/rooster/rooster',
        '/app/bin/rooster', // flatpak
        '/snap/rooster/current/rooster',
        '/nix/store/abc-rooster/bin/rooster',
      ]) {
        expect(isSelfInstallable('linux', path), isFalse, reason: path);
      }
    });

    test('only the desktop platforms install over themselves', () {
      expect(isSelfInstallable('android', '/data/app/rooster'), isFalse);
      expect(isSelfInstallable('web', '/rooster'), isFalse);
    });

    test('a macOS app installs over itself only once in a folder of its own',
        () {
      const exe = 'Rooster.app/Contents/MacOS/Rooster';
      expect(isSelfInstallable('macos', '/Applications/$exe'), isTrue);
      expect(isSelfInstallable('macos', '/Volumes/Rooster/$exe'), isFalse);
      expect(
          isSelfInstallable(
              'macos', '/private/var/folders/x/T/AppTranslocation/ABC/d/$exe'),
          isFalse);
    });
  });

  group('what an archive has to look like', () {
    test('the one directory it holds is the new build', () {
      final unpacked = Directory(p.join(root.path, 'unpacked'))..createSync();
      final inner = Directory(p.join(unpacked.path, 'rooster-v1-linux'))
        ..createSync();
      expect(singleRootOf(unpacked)?.path, inner.path);
    });

    test('loose files, or several, are not an archive we made', () {
      final unpacked = Directory(p.join(root.path, 'unpacked'))..createSync();
      expect(singleRootOf(unpacked), isNull, reason: 'empty');

      File(p.join(unpacked.path, 'rooster')).writeAsStringSync('');
      expect(singleRootOf(unpacked), isNull, reason: 'a bare file');

      unpacked.deleteSync(recursive: true);
      unpacked.createSync();
      Directory(p.join(unpacked.path, 'a')).createSync();
      Directory(p.join(unpacked.path, 'b')).createSync();
      expect(singleRootOf(unpacked), isNull, reason: 'two directories');
    });
  });

  group('unpacking', () {
    test('a tar.gz comes out whole, executable bits and all', () async {
      final source = buildDir(root, 'rooster-v2-linux', 'new');
      await Process.run('chmod', ['+x', p.join(source.path, 'rooster')]);
      final archive = File(p.join(root.path, 'release.tar.gz'));
      final packed = await Process.run(
          'tar', ['-czf', archive.path, '-C', root.path, 'rooster-v2-linux']);
      expect(packed.exitCode, 0, reason: packed.stderr.toString());

      final into = Directory(p.join(root.path, 'unpacked'))..createSync();
      await unpack(archive, into);

      final unpacked = singleRootOf(into);
      expect(unpacked, isNotNull);
      expect(File(p.join(unpacked!.path, 'which')).readAsStringSync(), 'new');
      // The Dart unpacker drops the mode, which would leave a build that
      // cannot be started.
      final exe = File(p.join(unpacked.path, 'rooster'));
      expect(exe.statSync().modeString(), contains('x'));
    });

    test('something that is not an archive does not half unpack', () async {
      final archive = File(p.join(root.path, 'release.tar.gz'))
        ..writeAsStringSync('this is not a tarball');
      final into = Directory(p.join(root.path, 'unpacked'))..createSync();

      // Both unpackers refuse it; what matters is that it throws rather
      // than leaving something that looks like a build.
      await expectLater(unpack(archive, into), throwsA(anything));
      expect(singleRootOf(into), isNull);
    });
  });

  group('the swap', () {
    test('puts the new build in place and clears the old one away', () async {
      final install = buildDir(root, 'Rooster', 'old');
      final work = Directory(p.join(root.path, '.rooster-update'))
        ..createSync();
      final staged = buildDir(work, 'unpacked/rooster-v2-linux', 'new');

      final result =
          await runSwap(work: work, install: install.path, staged: staged.path);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(File(p.join(install.path, 'which')).readAsStringSync(), 'new');
      // Neither the old build nor the working directory is left behind.
      expect(Directory('${install.path}.old-1234').existsSync(), isFalse);
      expect(work.existsSync(), isFalse);
    });

    test('leaves the working build alone when the new one will not go in',
        () async {
      final install = buildDir(root, 'Rooster', 'old');
      final work = Directory(p.join(root.path, '.rooster-update'))
        ..createSync();

      // Staged but never unpacked: the move cannot succeed.
      final result = await runSwap(
          work: work,
          install: install.path,
          staged: p.join(work.path, 'unpacked', 'not-there'));

      expect(result.exitCode, isNot(0));
      expect(install.existsSync(), isTrue);
      expect(File(p.join(install.path, 'which')).readAsStringSync(), 'old');
    });

    test('a swap that fails starts the build that was running, and says why',
        () async {
      final install = buildDir(root, 'Rooster', 'old');
      final work = Directory(p.join(root.path, '.rooster-update'))
        ..createSync();
      final started = p.join(root.path, 'started');
      final running = launcher(root, 'running.sh', started);

      final result = await runSwap(
          work: work,
          install: install.path,
          staged: p.join(work.path, 'unpacked', 'not-there'),
          restart: running.path);

      expect(result.exitCode, isNot(0));
      // Restarting to update never leaves Rooster closed.
      expect(await appears(started), isTrue);
      final log = File(p.join(work.path, 'install-1234.log'));
      expect(log.readAsStringSync(), contains('could not move the new build'));
    });

    test('starts the new build once it is in place', () async {
      final install = buildDir(root, 'Rooster', 'old');
      final work = Directory(p.join(root.path, '.rooster-update'))
        ..createSync();
      final staged = buildDir(work, 'unpacked/rooster-v2-linux', 'new');
      // Stands in for the app: writing the file is how it says it ran.
      final started = p.join(root.path, 'started');

      await runSwap(
          work: work,
          install: install.path,
          staged: staged.path,
          exe: launcher(root, 'launch.sh', started).path);

      expect(await appears(started), isTrue);
    });

    test(
        'a new build that will not start is taken out, and the old one is '
        'put back, started, and not replaced by that release again', () async {
      final install = buildDir(root, 'Rooster', 'old');
      final work = Directory(p.join(root.path, '.rooster-update'))
        ..createSync();
      final staged = buildDir(work, 'v2/unpacked/rooster-v2-linux', 'new');
      final started = p.join(root.path, 'started');
      final marker = didNotStartMarker(work.path, 'v2');

      // What the loader does when a library the build links is missing.
      final result = await runSwap(
          work: work,
          install: install.path,
          staged: staged.path,
          exe: program(root, 'broken.sh', 'exit 127').path,
          restart: launcher(root, 'running.sh', started).path,
          didNotStart: marker);

      expect(result.exitCode, isNot(0));
      expect(File(p.join(install.path, 'which')).readAsStringSync(), 'old');
      expect(Directory('${install.path}.old-1234').existsSync(), isFalse);
      expect(await appears(started), isTrue);
      expect(File(marker).existsSync(), isTrue);
      final log = File(p.join(work.path, 'install-1234.log'));
      expect(log.readAsStringSync(), contains('exited with 127'));
    });

    test(
        'a new build that starts and keeps running stays, and the old one goes',
        () async {
      final install = buildDir(root, 'Rooster', 'old');
      final work = Directory(p.join(root.path, '.rooster-update'))
        ..createSync();
      final staged = buildDir(work, 'v2/unpacked/rooster-v2-linux', 'new');
      final marker = didNotStartMarker(work.path, 'v2');

      final result = await runSwap(
          work: work,
          install: install.path,
          staged: staged.path,
          // Still running when the watch ends.
          exe: program(root, 'running.sh', 'sleep 2').path,
          didNotStart: marker,
          settle: const Duration(milliseconds: 600));

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(File(p.join(install.path, 'which')).readAsStringSync(), 'new');
      expect(Directory('${install.path}.old-1234').existsSync(), isFalse);
      expect(work.existsSync(), isFalse);
    });

    test('will not swap under a Rooster that is still running', () async {
      final install = buildDir(root, 'Rooster', 'old');
      final work = Directory(p.join(root.path, '.rooster-update'))
        ..createSync();
      final staged = buildDir(work, 'unpacked/rooster-v2-linux', 'new');

      // Something that outlives the script's patience, and is not the build
      // being replaced, so the script has no business ending it.
      final alive = await Process.start('sleep', ['120']);
      addTearDown(alive.kill);
      final result = await runSwap(
          work: work,
          install: install.path,
          staged: staged.path,
          waitFor: alive.pid,
          restart: '/not/what/is/running',
          patience: const Duration(seconds: 1));

      expect(result.exitCode, isNot(0));
      expect(File(p.join(install.path, 'which')).readAsStringSync(), 'old');
      expect(Directory('/proc/${alive.pid}').existsSync(), isTrue,
          reason: 'it was not the script\'s to end');
    });

    test('ends a Rooster stuck on its way out, then swaps', () async {
      final install = buildDir(root, 'Rooster', 'old');
      final work = Directory(p.join(root.path, '.rooster-update'))
        ..createSync();
      final staged = buildDir(work, 'unpacked/rooster-v2-linux', 'new');

      // Stands in for a Rooster whose window has gone but whose process has
      // not: it is the build being replaced, by what it runs.
      final stuck = await Process.start('sleep', ['120']);
      addTearDown(stuck.kill);
      final result = await runSwap(
          work: work,
          install: install.path,
          staged: staged.path,
          waitFor: stuck.pid,
          restart: Link('/proc/${stuck.pid}/exe').targetSync(),
          patience: const Duration(seconds: 1));

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(await stuck.exitCode.timeout(const Duration(seconds: 5)),
          -ProcessSignal.sigkill.signalNumber);
      expect(File(p.join(install.path, 'which')).readAsStringSync(), 'new');
    });

    test('a build with nothing where it goes is moved in all the same',
        () async {
      // Recovered from a staging directory with no install left beside it.
      final install = p.join(root.path, 'Rooster');
      final work = Directory(p.join(root.path, '.rooster-update'))
        ..createSync();
      final staged = buildDir(work, 'v2/unpacked/rooster-v2-linux', 'new');

      final result =
          await runSwap(work: work, install: install, staged: staged.path);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(File(p.join(install, 'which')).readAsStringSync(), 'new');
      expect(work.existsSync(), isFalse);
    });

    test('a path with a quote in it does not break the script', () async {
      final odd = Directory(p.join(root.path, "it's here"))
        ..createSync(recursive: true);
      final install = buildDir(odd, 'Rooster', 'old');
      final work = Directory(p.join(odd.path, '.rooster-update'))..createSync();
      final staged = buildDir(work, 'unpacked/rooster-v2-linux', 'new');

      final result =
          await runSwap(work: work, install: install.path, staged: staged.path);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(File(p.join(install.path, 'which')).readAsStringSync(), 'new');
    });
  });
}
