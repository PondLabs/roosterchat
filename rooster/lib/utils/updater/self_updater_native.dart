// Desktop: download the release archive, check it, unpack it beside the
// install, and leave a script to put it in place once we are gone.
//
// The swap is a rename, not a copy over the top: a half-written install is
// the one outcome worth ruling out. The old directory is moved aside first
// and moved back if the new one will not go in, so a failure leaves the
// build that was already working.
import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:rooster/config/build_config.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/utils/updater/self_updater.dart';
import 'package:rooster/utils/updater/update_release.dart';
import 'package:rooster/utils/update_checker.dart';
import 'package:rooster/utils/windows_hidden_process.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

SelfUpdater createSelfUpdater() => NativeSelfUpdater();

/// Directories an update must not touch, because something else owns what is
/// in them. A flatpak is read only at `/app`, and a .deb or a distro package
/// lives under `/usr`.
const _managedPrefixes = ['/usr/', '/app/', '/snap/', '/nix/store/'];

/// Whether a build living at [executable] is ours to replace.
///
/// On macOS, not an app still on the disk image it came on (read only), nor
/// one macOS runs from a read only copy because it was opened where it was
/// downloaded (App Translocation): both have to be dragged to Applications
/// first.
///
/// Pulled out so it can be tested without an install to point at.
bool isSelfInstallable(String platform, String executable) {
  if (platform == 'macos') {
    return executable.contains('.app/Contents/MacOS/') &&
        !executable.startsWith('/Volumes/') &&
        !executable.contains('/AppTranslocation/');
  }
  if (platform != 'windows' && platform != 'linux') return false;
  final path = executable.replaceAll('\\', '/');
  return !_managedPrefixes.any(path.startsWith);
}

/// The architecture a build was made for, as the release names it (`x64` or
/// `arm64`), from the ABI the build runs as. An x64 build on an arm64
/// Windows runs under emulation and reports x64, so it keeps updating to the
/// x64 release it was installed from; the arm64 build is a separate
/// install.
String archName(Abi abi) => switch (abi) {
      Abi.windowsArm64 || Abi.linuxArm64 || Abi.macosArm64 => 'arm64',
      _ => 'x64',
    };

/// Unpacks [archive] into [into].
///
/// The system's own tar first: `archive`'s pure Dart gzip and tar take about
/// three minutes over a release build, against a second or two for the tool
/// every desktop already has (Windows has shipped bsdtar, which reads zip
/// too, since Windows 10 1803). The Dart one is kept for whatever does not
/// have it, slow but working.
///
/// On macOS, ditto: the zip is ditto's (`desktop-build.yml`), and only ditto
/// puts back the symlinks and resource data an .app needs to open.
Future<void> unpack(File archive, Directory into) async {
  if (Platform.isMacOS) {
    final ditto =
        await Process.run('ditto', ['-x', '-k', archive.path, into.path]);
    if (ditto.exitCode != 0) throw StateError('ditto: ${ditto.stderr}');
    return;
  }
  try {
    final tar =
        await _runQuietly('tar', ['-xf', archive.path, '-C', into.path]);
    if (tar == 0) return;
    Log.w('Update: tar exited $tar, unpacking in Dart instead');
  } catch (e, s) {
    Log.onError(e, s, content: 'Update: no system tar, unpacking in Dart');
  }
  // Leaves nothing half written for the Dart pass to trip over.
  for (final entry in into.listSync()) {
    entry.deleteSync(recursive: true);
  }
  await extractFileToDisk(archive.path, into.path);
}

Future<int> _runQuietly(String executable, List<String> arguments) async {
  if (!Platform.isWindows) {
    final result = await Process.run(executable, arguments);
    return result.exitCode;
  }
  // No console window for the user to watch flash past.
  final process = await startWindowsHidden(executable, arguments);
  return process.exitCode.timeout(const Duration(minutes: 5));
}

/// The one directory an archive holds, which is the new install.
///
/// `ci.yml` packs `rooster-<tag>-<platform>-<arch>-<mode>/` and nothing else.
/// Anything else is not an archive we made, and is refused rather than
/// guessed at.
Directory? singleRootOf(Directory unpacked) {
  final entries = unpacked.listSync();
  if (entries.length != 1) return null;
  final only = entries.first;
  return only is Directory ? only : null;
}

/// Where an update goes, worked out from where the running build is.
class UpdateTarget {
  const UpdateTarget(
      {required this.install, required this.workRoot, this.shortcut});

  /// The directory the new build takes the place of. It may not exist yet
  /// (a build that is moving somewhere lasting).
  final String install;

  /// [updateDirName] beside [install]: downloads are unpacked in there, so
  /// putting one in place is a rename, and the swap clears all of it,
  /// whatever earlier attempts left behind.
  final String workRoot;

  /// A Start menu shortcut to point at the new build, for one that moved.
  final String? shortcut;

  bool get moves => shortcut != null;
}

/// Name of the directory updates are staged in, beside the install.
const updateDirName = '.rooster-update';

/// What builds from before the renames staged updates in.
const _legacyUpdateDirNames = ['.cockhouse-update', '.roscord-update'];

/// What the Linux swap leaves in [workRoot] when the build it put in place
/// for [tag] would not start and the old one went back
/// ([linuxSwapScript]). That release is not installed again here; the next
/// one is, and a swap that works clears the whole of [workRoot].
String didNotStartMarker(String workRoot, String tag) =>
    p.join(workRoot, 'did-not-start-$tag');

/// The executable a release is started with, and the one an archive must
/// hold for this build to take it.
String executableName({required bool windows}) =>
    windows ? 'rooster.exe' : 'rooster';

/// What the executable was called before the renames (Cockhouse, and Commet
/// before it). Releases still carry them (copies on Windows, links on Linux,
/// from the CMake install step) so that builds from before, which look for
/// and start their own name, can update themselves to this one, and so their
/// shortcuts keep working.
List<String> legacyExecutableNames({required bool windows}) => windows
    ? const ['cockhouse.exe', 'commet.exe']
    : const ['cockhouse', 'commet'];

/// Where the build at [executable] is updated to.
///
/// - Run from inside [updateDirName] (an earlier swap never happened and the
///   staged build was started by hand, maybe more than once, each one
///   staging the next inside itself): the install is the build left beside
///   the outermost [updateDirName], and the whole nest goes with the swap.
/// - Run from a zip opened in Explorer, which unpacks it into the temp
///   directory ([tempDir]): the update goes to `Programs\Rooster` in
///   [localAppData], with a Start menu shortcut, since the next click on the
///   zip would start the old build again.
/// - A macOS app: the `.app` itself.
/// - Otherwise the build's own directory.
///
/// Reads the file system (the recovery looks for the build that was left
/// behind) but changes nothing, so it can be tried on directories that are
/// not an install.
UpdateTarget updateTargetFor(
  String executable, {
  required bool windows,
  required String tempDir,
  String? localAppData,
  String? startMenu,
}) {
  final context = windows ? p.windows : p.posix;
  final app =
      RegExp(r'^(.+\.app)/Contents/MacOS/[^/]+$').firstMatch(executable);
  if (!windows && app != null) {
    return UpdateTarget(
      install: app[1]!,
      workRoot: context.join(context.dirname(app[1]!), updateDirName),
    );
  }
  final exeNames = {
    context.basename(executable),
    executableName(windows: windows),
    ...legacyExecutableNames(windows: windows),
  };
  final installDir = context.dirname(executable);
  final parts = context.split(installDir);
  final stagingNames = [updateDirName, ..._legacyUpdateDirNames];

  final nested = parts.indexWhere(stagingNames.contains);
  if (nested > 0) {
    final outer = context.joinAll(parts.take(nested));
    String? left;
    try {
      for (final entry in Directory(outer).listSync()) {
        if (entry is Directory &&
            !stagingNames.contains(context.basename(entry.path)) &&
            exeNames.any(
                (name) => File(context.join(entry.path, name)).existsSync())) {
          left = entry.path;
          break;
        }
      }
    } catch (_) {}
    return UpdateTarget(
      install: left ?? context.join(outer, parts.last),
      // The nest it was found in, whichever name it has.
      workRoot: context.join(outer, parts[nested]),
    );
  }

  if (windows &&
      localAppData != null &&
      startMenu != null &&
      context.isWithin(tempDir, installDir)) {
    final programs = context.join(localAppData, 'Programs');
    return UpdateTarget(
      install: context.join(programs, 'Rooster'),
      workRoot: context.join(programs, updateDirName),
      shortcut: context.join(startMenu, 'Rooster.lnk'),
    );
  }

  return UpdateTarget(
    install: installDir,
    workRoot: context.join(context.dirname(installDir), updateDirName),
  );
}

class NativeSelfUpdater implements SelfUpdater {
  @override
  final ValueNotifier<UpdateProgress> progress =
      ValueNotifier(const UpdateProgress(UpdateStage.idle));

  /// Unpacked and waiting for the app to close.
  Directory? _staged;
  bool _running = false;

  /// Not a bool: a macOS build that called itself linux would pass
  /// [isSelfInstallable] and then download the Linux tarball.
  String get _platform => Platform.operatingSystem;

  /// `x64` or `arm64`: the build this one is, so an arm64 install never
  /// downloads the x64 archive, which would not start.
  String get _arch => archName(Abi.current());

  late final UpdateTarget _target = updateTargetFor(
    File(Platform.resolvedExecutable).absolute.path,
    windows: Platform.isWindows,
    tempDir: Directory.systemTemp.absolute.path,
    localAppData: Platform.environment['LOCALAPPDATA'],
    startMenu: Platform.environment['APPDATA'] == null
        ? null
        : p.join(Platform.environment['APPDATA']!, 'Microsoft', 'Windows',
            'Start Menu', 'Programs'),
  );

  /// What the swap clears up after itself: [UpdateTarget.workRoot], or the
  /// temp directory's when that could not be written.
  String? _workRoot;

  @override
  bool get canInstall =>
      UpdateChecker.shouldCheckForUpdates &&
      isSelfInstallable(_platform, Platform.resolvedExecutable);

  void _set(UpdateStage stage,
          {UpdateRelease? release, double? fraction, String? message}) =>
      progress.value = UpdateProgress(stage,
          release: release ?? progress.value.release,
          fraction: fraction,
          message: message);

  @override
  Future<void> checkAndPrepare({Duration? checkTimeout}) async {
    if (_running) return;
    _running = true;
    try {
      _set(UpdateStage.checking);
      final release = await UpdateRelease.fetchLatest(
          UpdateChecker.releasesApiUrl,
          timeout: checkTimeout ?? UpdateRelease.defaultTimeout);
      if (release == null) {
        _set(UpdateStage.failed,
            message: 'Could not reach GitHub to look for updates.');
        return;
      }
      if (!UpdateChecker.isNewer(release.tag, BuildConfig.VERSION_TAG)) {
        _set(UpdateStage.upToDate,
            release: release,
            message:
                '${BuildConfig.app} ${BuildConfig.VERSION_TAG} is the latest.');
        return;
      }
      if (!canInstall) {
        // Nothing to do but point at the download, as before.
        _set(UpdateStage.available, release: release);
        return;
      }
      await _prepare(release);
    } catch (e, s) {
      Log.onError(e, s, content: 'Update: could not prepare');
      _set(UpdateStage.failed, message: 'The update could not be prepared.');
    } finally {
      _running = false;
    }
  }

  Future<void> _prepare(UpdateRelease release) async {
    // Installed once already and it would not start, so the old build went
    // back. Again would mean the same download and the same two restarts
    // at every launch.
    if (_didNotStartHere(release.tag)) {
      _set(UpdateStage.failed,
          release: release,
          message: '${release.tag} would not start on this computer, so '
              '${BuildConfig.VERSION_TAG} was put back. The next release '
              'will be tried.');
      return;
    }
    final asset = release.assetFor(_platform, arch: _arch);
    if (asset == null) {
      _set(UpdateStage.available,
          release: release,
          message: 'That release has no build for this platform.');
      return;
    }
    if (asset.sha256 == null) {
      // Without a checksum there is no way to know what arrived, and this
      // unpacks over the app: the browser can have this one.
      _set(UpdateStage.available,
          release: release,
          message: 'That release is not checksummed, so it has to be '
              'installed by hand.');
      return;
    }

    await discard();
    // Beside the install, so putting it in place is a rename and not a copy
    // across filesystems. Falls back to the temp directory when the parent
    // is not ours to write in.
    final work = await _workDirectory(release.tag);
    try {
      final archive = File(p.join(work.path, asset.name));
      _set(UpdateStage.downloading, release: release, fraction: 0);
      await _download(asset, archive);

      _set(UpdateStage.verifying, release: release);
      final digest = await sha256.bind(archive.openRead()).first;
      final got = digest.toString();
      if (got != asset.sha256) {
        throw StateError('checksum is $got, expected ${asset.sha256}');
      }

      _set(UpdateStage.unpacking, release: release);
      final unpacked = Directory(p.join(work.path, 'unpacked'));
      await unpacked.create(recursive: true);
      await unpack(archive, unpacked);
      await archive.delete();

      final root = singleRootOf(unpacked);
      if (root == null) {
        throw StateError('the archive does not hold one directory');
      }
      final executable = File(p.join(root.path, _executableName));
      if (!await executable.exists()) {
        throw StateError('no $_executableName in the archive');
      }
      // The Dart unpacker drops the executable bit. Swapped in, a build that
      // cannot be started leaves nothing that opens, launcher entry included.
      // 0x49 is 0111, execute for anyone.
      if (!Platform.isWindows && (await executable.stat()).mode & 0x49 == 0) {
        throw StateError('$_executableName in the archive cannot be run');
      }
      _staged = root;
      _set(UpdateStage.ready,
          release: release,
          message: _target.moves
              ? '${release.tag} is ready. Restarting moves ${BuildConfig.app} to '
                  '${_target.install}, with a Start menu shortcut, so it no '
                  'longer runs from the zip.'
              : null);
      Log.i('Update: ${release.tag} is unpacked at ${root.path}');
    } catch (e, s) {
      Log.onError(e, s, content: 'Update: could not stage ${release.tag}');
      await _delete(work);
      _set(UpdateStage.failed,
          release: release,
          message: 'The update could not be downloaded. '
              'You can still install it from the release page.');
    }
  }

  /// The release's own name, not the one this build was started by: a build
  /// started through a legacy `cockhouse` or `commet` copy still updates to, and restarts
  /// as, `rooster`. On macOS, where the install is the `.app`, the binary in
  /// it.
  String get _executableName => Platform.isMacOS
      ? 'Contents/MacOS/Rooster'
      : executableName(windows: Platform.isWindows);

  /// A fresh directory for [tag] under the work root. Fresh, because the
  /// root may hold what earlier attempts left (the running build, even).
  Future<Directory> _workDirectory(String tag) async {
    Future<Directory> fresh(String root) async {
      final work = Directory(p.join(root, tag));
      if (await work.exists()) await work.delete(recursive: true);
      await work.create(recursive: true);
      // Writable in practice, not only on paper.
      final probe = File(p.join(work.path, '.probe'));
      await probe.writeAsString('');
      await probe.delete();
      _workRoot = root;
      return work;
    }

    try {
      return await fresh(_target.workRoot);
    } catch (_) {
      return fresh(_tempWorkRoot);
    }
  }

  /// The work root when the one beside the install cannot be written.
  String get _tempWorkRoot =>
      p.join(Directory.systemTemp.path, 'rooster-update');

  /// Whether the swap put [tag] in place here before and it would not
  /// start, in whichever work root that happened.
  bool _didNotStartHere(String tag) => [_target.workRoot, _tempWorkRoot]
      .any((root) => File(didNotStartMarker(root, tag)).existsSync());

  Future<void> _download(UpdateAsset asset, File target) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(asset.url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}', uri: request.uri);
      }
      final total = response.contentLength > 0
          ? response.contentLength
          : (asset.size > 0 ? asset.size : 0);
      var received = 0;
      final sink = target.openWrite();
      try {
        await for (final chunk
            in response.timeout(const Duration(seconds: 60))) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            _set(UpdateStage.downloading, fraction: received / total);
          }
        }
      } finally {
        await sink.close();
      }
    } finally {
      client.close();
    }
  }

  @override
  Future<bool> installAndRestart() async {
    final staged = _staged;
    if (staged == null || !await staged.exists()) return false;
    try {
      final script = await _writeSwapScript(staged);
      await startSwapScript(script);
      Log.i('Update: handed the swap to ${script.path}');
      return true;
    } catch (e, s) {
      Log.onError(e, s, content: 'Update: could not start the installer');
      _set(UpdateStage.failed,
          message: 'The update could not be started. Nothing was changed.');
      return false;
    }
  }

  @override
  Future<void> discard() async {
    final staged = _staged;
    _staged = null;
    if (staged == null) return;
    // The whole working directory, not only what was unpacked.
    await _delete(staged.parent.parent);
  }

  Future<void> _delete(Directory dir) async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e, s) {
      Log.onError(e, s, content: 'Update: could not clean up ${dir.path}');
    }
  }

  Future<File> _writeSwapScript(Directory staged) async {
    final install = _target.install;
    final exe = p.join(install, _executableName);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final work = staged.parent.parent;
    final workRoot = _workRoot ?? work.path;
    final script = File(
        p.join(work.path, Platform.isWindows ? 'install.ps1' : 'install.sh'));
    await script.writeAsString(Platform.isWindows
        ? windowsSwapScript(
            waitFor: pid,
            staged: staged.path,
            install: install,
            exe: exe,
            work: workRoot,
            stamp: stamp,
            shortcut: _target.shortcut,
            restart: Platform.resolvedExecutable)
        : linuxSwapScript(
            waitFor: pid,
            staged: staged.path,
            install: install,
            exe: exe,
            work: workRoot,
            stamp: stamp,
            restart: Platform.resolvedExecutable,
            // The work directory is named after the release's tag.
            didNotStart: didNotStartMarker(workRoot, p.basename(work.path)),
            open: Platform.isMacOS));
    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', script.path]);
    }
    return script;
  }
}

/// Starts the swap [script] so that it outlives the app.
///
/// In the temp directory, never the app's working directory: that is
/// usually the install itself (Explorer starts a program in its own folder),
/// and Windows will not rename a directory a process is working in. The
/// script inheriting it kept every swap on Windows from happening.
Future<void> startSwapScript(File script) async {
  final outside = Directory.systemTemp.path;
  if (Platform.isWindows) {
    // No console window: this outlives the app and the user should not
    // see a terminal flash up as it closes.
    await startWindowsHidden(
        'powershell.exe',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-WindowStyle',
          'Hidden',
          '-File',
          script.path,
        ],
        workingDirectory: outside);
  } else {
    await Process.start('/bin/sh', [script.path],
        mode: ProcessStartMode.detached, workingDirectory: outside);
  }
}

/// Single-quoted for PowerShell, where a quote is doubled to escape it.
String _ps(String value) => "'${value.replaceAll("'", "''")}'";

/// Single-quoted for the shell, where a quote ends the string, is escaped,
/// and the string starts again.
String _sh(String value) => "'${value.replaceAll("'", r"'\''")}'";

/// Swaps [install] for [staged] once the process [waitFor] is gone, starts
/// [exe] and clears up. The old install is moved aside first and moved back
/// if the new one will not go in, so a failure leaves what was working.
///
/// Pulled out of the updater so the scripts can be read, and run against a
/// directory that is not an install, in tests.
///
/// [install] need not exist (a build moving out of the temp directory);
/// [shortcut], when given, is a Start menu shortcut made to point at [exe].
/// When the swap fails, [restart] (the build that was running) is started
/// again, so restarting to update never leaves Rooster closed. What
/// happened goes in `install-<stamp>.log` in [work], which is only cleared
/// when the swap worked.
String windowsSwapScript({
  required int waitFor,
  required String staged,
  required String install,
  required String exe,
  required String work,
  required int stamp,
  String? shortcut,
  String? restart,
}) =>
    '''
\$ErrorActionPreference = 'Stop'
\$work = ${_ps(work)}
\$log  = Join-Path \$work 'install-$stamp.log'
function Say(\$what) {
  Add-Content -LiteralPath \$log -Value "\$(Get-Date -Format o) \$what" -ErrorAction SilentlyContinue
}
# Out of every directory this moves or deletes: Windows will not rename a
# directory some process, this one included, is working in.
Set-Location -LiteralPath ([System.IO.Path]::GetTempPath())

# Wait for Rooster to go: its directory cannot be renamed while it runs.
Say 'waiting for Rooster (process $waitFor) to close'
\$deadline = (Get-Date).AddSeconds(60)
while ((Get-Process -Id $waitFor -ErrorAction SilentlyContinue) -and
       ((Get-Date) -lt \$deadline)) {
  Start-Sleep -Milliseconds 200
}

# A rename, whole or not at all. Move-Item is not that: when a file inside
# is busy it moves the rest one by one and leaves half an install behind.
# The directory can stay busy for a moment after Rooster has gone (its
# browser helpers closing, a virus scanner looking at the new files), so
# the rename is tried again for a while.
function Rename-Patiently(\$from, \$to) {
  \$until = (Get-Date).AddSeconds(30)
  while (\$true) {
    try {
      [System.IO.Directory]::Move(\$from, \$to)
      return
    } catch {
      if ((Get-Date) -ge \$until) { throw }
      Start-Sleep -Milliseconds 500
    }
  }
}

\$install = ${_ps(install)}
\$staged  = ${_ps(staged)}
\$old     = ${_ps('$install.old-$stamp')}
try {
  \$hadOld = Test-Path -LiteralPath \$install
  if (\$hadOld) {
    Rename-Patiently \$install \$old
  } else {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent \$install) | Out-Null
  }
  try {
    if ([System.IO.Path]::GetPathRoot(\$staged) -eq [System.IO.Path]::GetPathRoot(\$install)) {
      Rename-Patiently \$staged \$install
    } else {
      # Staged on another drive (the install's own could not be written
      # to): a copy, which is not whole until it has finished.
      Copy-Item -LiteralPath \$staged -Destination \$install -Recurse
    }
  } catch {
    # Put back what was working and leave the update where it is.
    if (Test-Path -LiteralPath \$install) {
      Remove-Item -LiteralPath \$install -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (\$hadOld) { [System.IO.Directory]::Move(\$old, \$install) }
    throw
  }
} catch {
  Say "the swap failed: \$_"
${restart == null ? '' : '  Start-Process -FilePath ${_ps(restart)} -WorkingDirectory (Split-Path -Parent ${_ps(restart)})\n'}  exit 1
}
Say 'swapped'
${shortcut == null ? '' : '''try {
  \$link = (New-Object -ComObject WScript.Shell).CreateShortcut(${_ps(shortcut)})
  \$link.TargetPath = ${_ps(exe)}
  \$link.WorkingDirectory = \$install
  \$link.Save()
} catch {
  Say "no Start menu shortcut: \$_"
}
'''}Start-Process -FilePath ${_ps(exe)} -WorkingDirectory \$install
Remove-Item -LiteralPath \$old -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath \$work -Recurse -Force -ErrorAction SilentlyContinue
''';

/// Linux, and macOS with [open]: there [install] is the `.app`, which is
/// started through Launch Services rather than by running [exe].
///
/// [restart] is the build that was running. When the swap fails it is
/// started again, so restarting to update never leaves Rooster closed. On
/// Linux it also says which process is ours to end: one still there after
/// [patience], its window already gone, is stuck on the way out. What
/// happened goes in `install-<stamp>.log` in [work], which is only cleared
/// when the swap worked.
///
/// On Linux the new build is watched for [settle] once started. One that
/// exits with an error in that time did not start (a library it needs is
/// not on this computer, say): it is taken out, the old build is put back
/// and started again, and [didNotStart] is created, so the same release is
/// not installed again at every launch.
String linuxSwapScript({
  required int waitFor,
  required String staged,
  required String install,
  required String exe,
  required String work,
  required int stamp,
  String? restart,
  String? didNotStart,
  Duration patience = const Duration(seconds: 60),
  Duration settle = const Duration(seconds: 10),
  bool open = false,
}) {
  final ticks = patience.inMilliseconds ~/ 200;
  final settleTicks = settle.inMilliseconds ~/ 200;
  final relaunch = restart == null
      ? null
      : open
          ? 'open "\$install"'
          : '(cd ${_sh(p.posix.dirname(restart))} && exec ${_sh(restart)}) &';
  final start = open
      ? '''
open "\$install"
# Last, and from outside it: this script lives in there.
cd /
rm -rf "\$old" "\$work"
'''
      : '''
(cd "\$install" && exec ${_sh(exe)}) &
started=\$!
# Cleared now, from outside it (this script lives in there): the new build
# may stage an update of its own in there as soon as it starts.
cd /
rm -rf "\$work"

# A build that cannot start exits at once (127 when the loader cannot find a
# library it needs), and swapped in it would leave nothing that opens,
# launcher entry included. The old one stays beside it until the new one
# has been watched for a while.
i=0
while [ \$i -lt $settleTicks ] && alive \$started; do
  sleep 0.2
  i=\$((i + 1))
done
if ! alive \$started; then
  wait \$started
  status=\$?
  if [ \$status -ne 0 ]; then
    mkdir -p "\$work"
${didNotStart == null ? '' : '    : > ${_sh(didNotStart)}\n'}    if [ -e "\$old" ]; then
      rm -rf "\$install"
      mv "\$old" "\$install" ||
        fail "the new build exited with \$status as it started, and the old one could not be put back"
    fi
    fail "the new build exited with \$status as it started; the old one is back"
  fi
fi
rm -rf "\$old"
''';
  return '''
#!/bin/sh
work=${_sh(work)}
log="\$work/install-$stamp.log"
say() {
  echo "\$(date '+%Y-%m-%dT%H:%M:%S') \$*" >> "\$log" 2>/dev/null
}
install=${_sh(install)}
staged=${_sh(staged)}
old=${_sh('$install.old-$stamp')}

# Whether process \$1 runs. A zombie has gone already; only its parent has
# not noticed yet.
alive() {
  kill -0 "\$1" 2>/dev/null || return 1
  case "\$(sed 's/.*) //' "/proc/\$1/stat" 2>/dev/null)" in
    Z*) return 1 ;;
  esac
}

fail() {
  say "\$1"
${relaunch == null ? '' : '  $relaunch\n'}  exit 1
}

# Wait for Rooster to go, so the new build does not start beside the old one.
say 'waiting for Rooster (process $waitFor) to close'
i=0
while [ \$i -lt $ticks ] && alive $waitFor; do
  sleep 0.2
  i=\$((i + 1))
done
${restart == null || open ? '' : '''# Rooster closes its window as this starts waiting, so one still here is
# stuck on the way out, and would keep the old build in place for good. It
# is ended, but only while it runs the build being replaced, not when
# something else has taken its pid.
if alive $waitFor && [ "\$(readlink /proc/$waitFor/exe 2>/dev/null)" = ${_sh(restart)} ]; then
  say 'Rooster did not close in ${patience.inSeconds} seconds; ending it'
  kill -KILL $waitFor 2>/dev/null
  i=0
  while [ \$i -lt 25 ] && alive $waitFor; do
    sleep 0.2
    i=\$((i + 1))
  done
fi
'''}# Unlike Windows, a directory here can be moved out from under a running
# program. Not swapping under it: two Roosters sharing one account is worse
# than an update that did not happen.
if alive $waitFor; then
  fail 'Rooster is still running; nothing was changed'
fi

# The install may not be there: a recovered one can be moving out of the
# staging directory it was run from.
if [ -e "\$install" ]; then
  mv "\$install" "\$old" || fail "could not move \$install aside"
else
  mkdir -p "\$(dirname "\$install")" || fail "could not create \$install"
fi
if ! mv "\$staged" "\$install"; then
  # Across filesystems mv copies, and one that stopped half way leaves part
  # of a build there, which the old one would be moved into.
  rm -rf "\$install"
  [ -e "\$old" ] && mv "\$old" "\$install"
  fail 'could not move the new build in; the old one is back'
fi
$start''';
}
