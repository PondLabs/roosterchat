// Where an update goes, from where the running build is: its own directory,
// the build left behind when it was started from the staging directory, or
// somewhere lasting when it runs out of a zip Explorer unpacked into temp.
import 'dart:io';

import 'package:rooster/utils/updater/self_updater_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  final exe = executableName(windows: Platform.isWindows);

  setUp(() => root = Directory.systemTemp.createTempSync('rooster-target-'));
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Directory build(String path) {
    final dir = Directory(p.join(root.path, path))..createSync(recursive: true);
    File(p.join(dir.path, exe)).writeAsStringSync('');
    return dir;
  }

  UpdateTarget targetOf(Directory dir, {String? tempDir}) => updateTargetFor(
        p.join(dir.path, exe),
        windows: Platform.isWindows,
        tempDir: tempDir ?? p.join(root.path, 'no-temp-here'),
        localAppData: p.join(root.path, 'local'),
        startMenu: p.join(root.path, 'start'),
      );

  test('a build is updated where it is, staged beside itself', () {
    final install = build(p.join('Downloads', 'rooster-v1', 'rooster-v1'));
    final target = targetOf(install);
    expect(target.install, install.path);
    expect(target.workRoot,
        p.join(root.path, 'Downloads', 'rooster-v1', '.rooster-update'));
    expect(target.moves, isFalse);
  });

  test('run from the staging directory, the build left behind is replaced', () {
    // The swap to v2 never happened; v2 was started from where it was
    // staged, and staged v3 inside itself, and v3 was started from there.
    final outer = p.join('Downloads', 'rooster-v1');
    final left = build(p.join(outer, 'rooster-v1'));
    final v3 = build(p.join(outer, '.rooster-update', 'unpacked',
        '.rooster-update', 'unpacked', 'rooster-v3'));

    final target = targetOf(v3);
    expect(target.install, left.path);
    // The outermost staging directory: the whole nest goes with the swap.
    expect(target.workRoot, p.join(root.path, outer, '.rooster-update'));
    expect(target.moves, isFalse);
  });

  // Builds from before the renames staged updates under their own name, and
  // the build left behind is only known by its old executable name.
  for (final (era, dir, exe) in [
    ('cockhouse', '.cockhouse-update', 0),
    ('roscord', '.roscord-update', 1),
  ]) {
    test('a $era nest staged before the rename is still recognised', () {
      final legacyExe = legacyExecutableNames(windows: Platform.isWindows)[exe];
      final outer = p.join('Downloads', '$era-v1');
      final left = Directory(p.join(root.path, outer, '$era-v1'))
        ..createSync(recursive: true);
      File(p.join(left.path, legacyExe)).writeAsStringSync('');
      final staged = build(p.join(outer, dir, 'unpacked', 'rooster-v2'));

      final target = targetOf(staged);
      expect(target.install, left.path);
      expect(target.workRoot, p.join(root.path, outer, dir));
    });
  }

  test('run from staging with nothing left behind, it moves out beside it', () {
    final staged =
        build(p.join('here', '.rooster-update', 'v2', 'unpacked', 'Rooster'));
    final target = targetOf(staged);
    expect(target.install, p.join(root.path, 'here', 'Rooster'));
    expect(target.workRoot, p.join(root.path, 'here', '.rooster-update'));
  });

  test(
      'run out of a zip Explorer unpacked into temp, it moves somewhere lasting',
      () {
    final temp = p.join(root.path, 'Temp');
    final inZip = build(p.join('Temp', 'Temp1_rooster-v1.zip', 'rooster-v1'));
    final target = targetOf(inZip, tempDir: temp);
    if (!Platform.isWindows) {
      // Only Windows opens zips that way.
      expect(target.install, inZip.path);
      return;
    }
    expect(target.install, p.join(root.path, 'local', 'Programs', 'Rooster'));
    expect(target.workRoot,
        p.join(root.path, 'local', 'Programs', '.rooster-update'));
    expect(target.shortcut, p.join(root.path, 'start', 'Rooster.lnk'));
    expect(target.moves, isTrue);
  });

  test('the Windows rules on Windows paths', () {
    final target = updateTargetFor(
      r'C:\Users\a\AppData\Local\Temp\Temp1_rooster.zip\rooster\rooster.exe',
      windows: true,
      tempDir: r'C:\Users\a\AppData\Local\Temp',
      localAppData: r'C:\Users\a\AppData\Local',
      startMenu:
          r'C:\Users\a\AppData\Roaming\Microsoft\Windows\Start Menu\Programs',
    );
    expect(target.install, r'C:\Users\a\AppData\Local\Programs\Rooster');
    expect(target.shortcut,
        r'C:\Users\a\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Rooster.lnk');

    final plain = updateTargetFor(r'D:\apps\Rooster\rooster.exe',
        windows: true,
        tempDir: r'C:\Users\a\AppData\Local\Temp',
        localAppData: r'C:\Users\a\AppData\Local',
        startMenu: r'C:\start');
    expect(plain.install, r'D:\apps\Rooster');
    expect(plain.workRoot, r'D:\apps\.rooster-update');
    expect(plain.moves, isFalse);
  });
}
