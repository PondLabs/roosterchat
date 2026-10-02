// Moves a user's data to where this build keeps it, from where builds from
// before the renames to Rooster and Cockhouse kept it.
//
// Where desktop builds keep their data comes from their identity: the Windows
// company and product name (`%APPDATA%\<company>\<product>`), the Linux
// application ID (`$XDG_DATA_HOME/<app id>`). Both changed with each rename
// (Commet to Cockhouse, Cockhouse to Rooster), and the product name had
// changed once before that (commet.chat\commet became PondLabs\roscord).
// Without this, an update would start logged out, with no settings, and
// without the account's encryption keys.
//
// Runs first thing on startup, before anything opens the data directory. See
// docs/adr/0002-rename-to-cockhouse.md and
// docs/adr/0003-rename-to-rooster.md.

import 'dart:io';

import 'package:rooster/debug/log.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A directory this build uses, and where earlier builds kept the same
/// thing, most recent first.
class LegacyMove {
  const LegacyMove(this.to, this.from);

  final String to;
  final List<String> from;

  @override
  String toString() => '$from -> $to';
}

/// The moves for a desktop build. Pure, so it can be tested on any machine:
/// [env] is the process environment, [supportDir] and [cacheDir] are what
/// path_provider gives this build.
List<LegacyMove> legacyMovesFor({
  required String platform,
  required Map<String, String> env,
  required String supportDir,
  String? cacheDir,
}) {
  switch (platform) {
    case 'windows':
      final context = p.windows;
      final roaming = env['APPDATA'];
      final local = env['LOCALAPPDATA'];
      return [
        if (roaming != null)
          LegacyMove(supportDir, [
            context.join(roaming, 'PondLabs', 'Cockhouse'),
            context.join(roaming, 'PondLabs', 'roscord'),
            context.join(roaming, 'commet.chat', 'commet'),
          ]),
        if (local != null && cacheDir != null)
          LegacyMove(cacheDir, [
            context.join(local, 'PondLabs', 'Cockhouse'),
            context.join(local, 'PondLabs', 'roscord'),
            context.join(local, 'commet.chat', 'commet'),
          ]),
        // The embedded browser's profiles (widget logins).
        if (local != null)
          LegacyMove(context.join(local, 'Rooster'), [
            context.join(local, 'Cockhouse'),
            context.join(local, 'roscord'),
          ]),
      ];
    case 'linux':
      final context = p.posix;
      final home = env['HOME'];
      String? xdg(String name, String fallback) {
        final value = env[name];
        if (value != null && value.isNotEmpty) return value;
        return home == null ? null : context.join(home, fallback);
      }

      final data = xdg('XDG_DATA_HOME', '.local/share');
      final cache = xdg('XDG_CACHE_HOME', '.cache');
      // Inside a flatpak, XDG_DATA_HOME is the sandbox's own; an old app's is
      // beside it, and the manifest grants access to it.
      final flatpak = env.containsKey('FLATPAK_ID') && home != null;
      // Where the app with [appId] kept [name] in [kind] (data or cache).
      String old(String appId, String kind, String base, String name) => flatpak
          ? context.join(home, '.var', 'app', appId, kind, name)
          : context.join(base, name);
      // The application IDs before this one, newest first.
      const cockhouseId = 'com.pondlabs.cockhouse';
      const commetId = 'chat.commet.commetapp';
      return [
        if (data != null)
          LegacyMove(supportDir, [
            old(cockhouseId, 'data', data, cockhouseId),
            old(commetId, 'data', data, commetId),
          ]),
        if (cache != null && cacheDir != null)
          LegacyMove(cacheDir, [
            old(cockhouseId, 'cache', cache, cockhouseId),
            old(commetId, 'cache', cache, commetId),
          ]),
        // The embedded browser's profiles (widget logins).
        if (data != null)
          LegacyMove(context.join(data, 'rooster'), [
            old(cockhouseId, 'data', data, 'cockhouse'),
            old(commetId, 'data', data, 'roscord'),
          ]),
      ];
    default:
      // macOS builds are sandboxed: the old container is out of reach. Web
      // keeps its database name. Android has no earlier releases.
      return const [];
  }
}

/// Moves this desktop build's data in from where earlier builds kept it.
Future<void> migrateLegacyDesktopData() async {
  if (!Platform.isWindows && !Platform.isLinux) return;
  try {
    await migrateLegacyData(legacyMovesFor(
      platform: Platform.isWindows ? 'windows' : 'linux',
      env: Platform.environment,
      supportDir: (await getApplicationSupportDirectory()).path,
      cacheDir: (await getApplicationCacheDirectory()).path,
    ));
  } catch (e, s) {
    Log.onError(e, s, content: 'Legacy data: could not look for it');
  }
}

/// Carries out [moves]. Never throws: startup goes on, and anything not
/// moved is tried again next time.
Future<void> migrateLegacyData(List<LegacyMove> moves) async {
  for (final move in moves) {
    try {
      await _carryOut(move);
    } catch (e, s) {
      Log.onError(e, s, content: 'Legacy data: could not move $move');
    }
  }
}

Future<void> _carryOut(LegacyMove move) async {
  final to = Directory(move.to);
  if (await _hasContent(to)) return;

  Directory? from;
  for (final path in move.from) {
    final candidate = Directory(path);
    if (await _hasContent(candidate)) {
      from = candidate;
      break;
    }
  }
  if (from == null) return;

  // path_provider makes the directory when it is asked for it, so an empty
  // one is in the way of the rename.
  if (await to.exists()) await to.delete();
  await to.parent.create(recursive: true);
  try {
    await from.rename(to.path);
    Log.i('Legacy data: moved ${from.path} to ${to.path}');
  } on FileSystemException {
    // Another drive, or a flatpak reaching across its sandbox: a copy,
    // leaving the old one where it is. Made beside the target and renamed
    // into place when whole, so an interrupted copy is not taken for a
    // finished one next time.
    final partial = Directory('${to.path}.migrating');
    if (await partial.exists()) await partial.delete(recursive: true);
    await _copy(from, partial);
    await partial.rename(to.path);
    Log.i('Legacy data: copied ${from.path} to ${to.path}');
  }
}

Future<bool> _hasContent(Directory dir) async {
  if (!await dir.exists()) return false;
  return !(await dir.list().isEmpty);
}

Future<void> _copy(Directory from, Directory to) async {
  await to.create(recursive: true);
  await for (final entry in from.list(followLinks: false)) {
    final target = p.join(to.path, p.basename(entry.path));
    if (entry is Directory) {
      await _copy(entry, Directory(target));
    } else if (entry is File) {
      await entry.copy(target);
    } else if (entry is Link) {
      await Link(target).create(await entry.target());
    }
  }
}
