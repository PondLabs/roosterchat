// Moving a user's data in from where builds from before the rename to
// Cockhouse kept it (docs/adr/0002-rename-to-cockhouse.md).
import 'dart:io';

import 'package:cockhouse/utils/legacy_data_migration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('cockhouse-legacy-'));
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  String at(String path) => p.join(root.path, path);

  Directory dataAt(String path, {String file = 'shared_preferences.json'}) {
    final dir = Directory(at(path))..createSync(recursive: true);
    File(p.join(dir.path, file)).writeAsStringSync('{"from":"$path"}');
    Directory(p.join(dir.path, 'db', 'account')).createSync(recursive: true);
    File(p.join(dir.path, 'db', 'account', 'drift')).writeAsStringSync('keys');
    return dir;
  }

  group('what moves where', () {
    test('Windows: the roaming data, the cache and the browser profiles', () {
      final moves = legacyMovesFor(
        platform: 'windows',
        env: {
          'APPDATA': r'C:\Users\a\AppData\Roaming',
          'LOCALAPPDATA': r'C:\Users\a\AppData\Local',
        },
        supportDir: r'C:\Users\a\AppData\Roaming\PondLabs\Cockhouse',
        cacheDir: r'C:\Users\a\AppData\Local\PondLabs\Cockhouse',
      );
      expect(moves.map((m) => m.to), [
        r'C:\Users\a\AppData\Roaming\PondLabs\Cockhouse',
        r'C:\Users\a\AppData\Local\PondLabs\Cockhouse',
        r'C:\Users\a\AppData\Local\Cockhouse',
      ]);
      // Newest name first: PondLabs\roscord replaced commet.chat\commet.
      expect(moves.first.from, [
        r'C:\Users\a\AppData\Roaming\PondLabs\roscord',
        r'C:\Users\a\AppData\Roaming\commet.chat\commet',
      ]);
      expect(moves.last.from, [r'C:\Users\a\AppData\Local\roscord']);
    });

    test('Linux: from the old application ID, following XDG', () {
      final moves = legacyMovesFor(
        platform: 'linux',
        env: {'HOME': '/home/a', 'XDG_DATA_HOME': '/data'},
        supportDir: '/data/com.pondlabs.cockhouse',
        cacheDir: '/home/a/.cache/com.pondlabs.cockhouse',
      );
      expect(moves.map((m) => m.from), [
        ['/data/chat.commet.commetapp'],
        ['/home/a/.cache/chat.commet.commetapp'],
        ['/data/roscord'],
      ]);
      expect(moves.last.to, '/data/cockhouse');
    });

    test('Linux flatpak: from the old app\'s own sandbox directory', () {
      final moves = legacyMovesFor(
        platform: 'linux',
        env: {
          'HOME': '/home/a',
          'FLATPAK_ID': 'com.pondlabs.cockhouse',
          'XDG_DATA_HOME': '/home/a/.var/app/com.pondlabs.cockhouse/data',
        },
        supportDir:
            '/home/a/.var/app/com.pondlabs.cockhouse/data/com.pondlabs.cockhouse',
      );
      expect(moves.first.from, [
        '/home/a/.var/app/chat.commet.commetapp/data/chat.commet.commetapp'
      ]);
    });

    test('nothing to do elsewhere', () {
      for (final platform in ['macos', 'android', 'web']) {
        expect(
            legacyMovesFor(
                platform: platform, env: const {}, supportDir: '/x'),
            isEmpty,
            reason: platform);
      }
    });
  });

  group('moving', () {
    test('the old directory takes the place of the new, empty one', () async {
      dataAt('old');
      Directory(at('new')).createSync(); // path_provider made it
      await migrateLegacyData([LegacyMove(at('new'), [at('old')])]);

      expect(File(at('new/shared_preferences.json')).readAsStringSync(),
          '{"from":"old"}');
      expect(File(at('new/db/account/drift')).readAsStringSync(), 'keys');
      expect(Directory(at('old')).existsSync(), isFalse);
    });

    test('the first old directory with anything in it wins', () async {
      Directory(at('newest')).createSync(); // left empty
      dataAt('older');
      dataAt('oldest');
      await migrateLegacyData([
        LegacyMove(at('new'), [at('newest'), at('older'), at('oldest')])
      ]);

      expect(File(at('new/shared_preferences.json')).readAsStringSync(),
          '{"from":"older"}');
      expect(Directory(at('oldest')).existsSync(), isTrue);
    });

    test('data already in the new place is never replaced', () async {
      dataAt('new');
      dataAt('old');
      await migrateLegacyData([LegacyMove(at('new'), [at('old')])]);

      expect(File(at('new/shared_preferences.json')).readAsStringSync(),
          '{"from":"new"}');
      expect(Directory(at('old')).existsSync(), isTrue);
    });

    test('with nothing to move, nothing happens', () async {
      await migrateLegacyData([LegacyMove(at('new'), [at('old')])]);
      expect(Directory(at('new')).existsSync(), isFalse);
    });

    test('a failure is logged, not thrown, and the rest still move', () async {
      dataAt('old');
      // The new path is a file: it cannot become a directory.
      File(at('blocked')).writeAsStringSync('');
      dataAt('other-old');
      await migrateLegacyData([
        LegacyMove(p.join(at('blocked'), 'inside'), [at('old')]),
        LegacyMove(at('other-new'), [at('other-old')]),
      ]);

      expect(Directory(at('old')).existsSync(), isTrue);
      expect(Directory(at('other-new')).existsSync(), isTrue);
    });
  });
}
