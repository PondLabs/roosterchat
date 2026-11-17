// The path provider's test mixin, as plugin tests use it.
// ignore_for_file: invalid_use_of_visible_for_testing_member
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:rooster/cache/drift_file_cache.dart';
import 'package:rooster/cache/own_media_cache.dart';

/// The temporary folder the app's file cache writes into.
class _TempPaths extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _TempPaths(this.dir);
  final String dir;
  @override
  Future<String?> getTemporaryPath() async => dir;
}

/// The app's file cache, whose writes stop half way (a full disk), and
/// which cannot delete the files in [held] (in use, on Windows).
class _FaultyCache extends DriftFileCache {
  bool failWrites = false;
  final Set<String> held = {};

  @override
  Future<void> writeBytes(File file, Uint8List bytes) async {
    if (!failWrites) return super.writeBytes(file, bytes);
    await file.writeAsBytes(bytes.sublist(0, bytes.length ~/ 2));
    throw const FileSystemException('No space left on device');
  }

  @override
  Future<void> deleteFile(File file) async {
    if (held.contains(file.path)) {
      throw FileSystemException('In use', file.path);
    }
    return super.deleteFile(file);
  }
}

/// The native file cache forgets one account's own media by prefix, taken
/// as it is (LIKE's wildcards in it match only themselves), and deletes
/// the files.
void main() {
  late Directory dir;
  late _FaultyCache cache;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('file_cache');
    PathProviderPlatform.instance = _TempPaths(dir.path);
    cache = _FaultyCache()
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

  int filesIn(Directory dir) =>
      dir.listSync(recursive: true).whereType<File>().length;

  test(
      'clean() keeps the entry of a file it could not delete, and drops the '
      'others', () async {
    final held = await entry('held');
    final free = await entry('free');
    cache.held.add(held.path);

    await cache.clean();

    final db = cache.database!;
    final left = await db.select(db.fileCacheEntry).get();
    // ignore: avoid_print
    print('clean() with one file in use: rows ${left.map((e) => e.id)}; '
        'files ${filesIn(dir)}');
    expect(left.map((e) => e.id), ['held']);
    expect(held.existsSync(), isTrue);
    expect(free.existsSync(), isFalse);

    // Free again: the next clean takes it.
    cache.held.clear();
    await cache.clean();
    expect(await db.select(db.fileCacheEntry).get(), isEmpty);
    expect(held.existsSync(), isFalse);
  });

  test('a write stopped half way leaves no file and no entry', () async {
    cache.failWrites = true;
    await expectLater(
        cache.putFile('matrix-mxc://hs/1', Uint8List(1000)), throwsA(anything));
    await expectLater(
        cache.fetchFile('matrix-mxc://hs/2', () async => Uint8List(1000)),
        throwsA(anything));
    // The account's own media writes through it too.
    final own = FileOwnMediaCache('account', cache);
    await expectLater(
        own.write('mxc://hs/3', Uint8List(1000)), throwsA(anything));

    final db = cache.database!;
    // ignore: avoid_print
    print('after 3 writes stopped half way: files ${filesIn(dir)}, rows '
        '${(await db.select(db.fileCacheEntry).get()).length}');
    expect(filesIn(dir), 0);
    expect(await db.select(db.fileCacheEntry).get(), isEmpty);

    // The disk has room again: the same key is written.
    cache.failWrites = false;
    await own.write('mxc://hs/3', Uint8List(1000));
    expect((await own.read('mxc://hs/3'))!.length, 1000);
    expect(filesIn(dir), 1);
  });
}
