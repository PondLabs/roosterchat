@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/cache/drift_file_cache.dart';

/// The native file cache forgets one account's own media by prefix, taken
/// as it is (LIKE's wildcards in it match only themselves), and deletes
/// the files.
void main() {
  late Directory dir;
  late DriftFileCache cache;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('file_cache');
    cache = DriftFileCache()
      ..database = DriftFileCacheDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await cache.close();
    dir.deleteSync(recursive: true);
  });

  Future<File> entry(String id) async {
    final file = File('${dir.path}/${id.hashCode}')..writeAsStringSync(id);
    final db = cache.database!;
    await db.into(db.fileCacheEntry).insert(FileCacheEntryCompanion.insert(
        id: id, path: file.path, lastAccessedTimestamp: 0));
    return file;
  }

  test('removes the prefix\'s entries and files, and nothing else', () async {
    final mine = [
      await entry('own_media/a_%/mxc://hs/1'),
      await entry('own_media/a_%/mxc://hs/2'),
    ];
    final others = [
      await entry('own_media/ab%/mxc://hs/1'), // "_" is not a wildcard
      await entry('own_media/a_x/mxc://hs/1'), // nor "%"
      await entry('matrix-mxc://hs/1'),
    ];

    await cache.removeFilesStartingWith('own_media/a_%/');

    final db = cache.database!;
    final left = await db.select(db.fileCacheEntry).get();
    expect(
        left.map((e) => e.id),
        unorderedEquals([
          'own_media/ab%/mxc://hs/1',
          'own_media/a_x/mxc://hs/1',
          'matrix-mxc://hs/1',
        ]));
    expect(mine.map((f) => f.existsSync()), [false, false]);
    expect(others.map((f) => f.existsSync()), [true, true, true]);
  });

  test('removes one entry and its file', () async {
    final file = await entry('own_media/a/mxc://hs/1');
    await entry('own_media/a/mxc://hs/10');
    await cache.removeFile('own_media/a/mxc://hs/1');
    expect(await cache.hasFile('own_media/a/mxc://hs/1'), isFalse);
    expect(await cache.hasFile('own_media/a/mxc://hs/10'), isTrue);
    expect(file.existsSync(), isFalse);
  });
}
