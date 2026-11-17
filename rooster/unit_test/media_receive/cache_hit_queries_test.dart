@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart'
    show ApplyInterceptor, QueryExecutor, QueryInterceptor, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/cache/drift_file_cache.dart';
import 'package:rooster/cache/file_cache.dart';
import 'package:rooster/client/matrix/matrix_mxc_image_provider.dart';
import 'package:rooster/main.dart';

import 'media_fakes.dart';

/// A file cache in a temporary folder that counts its lookups (`hasFile`,
/// `getFile`): on the app's cache each is a query to its database.
class CountingFileCache implements FileCache {
  CountingFileCache(this.dir);

  final Directory dir;
  final Map<String, File> files = {};
  int lookups = 0;

  @override
  Future<bool> hasFile(String identifier) async {
    lookups++;
    return files[identifier]?.existsSync() == true;
  }

  @override
  Future<Uri?> getFile(String identifier) async {
    lookups++;
    final file = files[identifier];
    return file != null && file.existsSync() ? file.uri : null;
  }

  @override
  Future<Uri> putFile(String identifier, Uint8List bytes) async {
    final file = File('${dir.path}/${files.length}')..writeAsBytesSync(bytes);
    files[identifier] = file;
    return file.uri;
  }

  @override
  Future<Uri> fetchFile(
          String identifier, Future<Uint8List> Function() getter) async =>
      putFile(identifier, await getter());

  @override
  Future<void> init() async {}
  @override
  Future<void> close() async {}
  @override
  Future<void> clean() async {}
  @override
  Future<void> removeFile(String identifier) async {}
  @override
  Future<void> removeFilesStartingWith(String prefix) async {}
}

/// Counts the statements the database runs.
class StatementCounter extends QueryInterceptor {
  final List<String> statements = [];

  @override
  Future<List<Map<String, Object?>>> runSelect(
      QueryExecutor executor, String statement, List<Object?> args) {
    statements.add('select');
    return super.runSelect(executor, statement, args);
  }

  @override
  Future<int> runInsert(
      QueryExecutor executor, String statement, List<Object?> args) {
    statements.add('insert');
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
      QueryExecutor executor, String statement, List<Object?> args) {
    statements.add('update');
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<int> runDelete(
      QueryExecutor executor, String statement, List<Object?> args) {
    statements.add('delete');
    return super.runDelete(executor, statement, args);
  }
}

/// A picture in the timeline whose sender's thumbnail is in the file
/// cache: showing it costs one lookup in the cache and no request.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // A database per test, each on its own in-memory executor.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dir;
  late List<String> requests;
  late matrix.Client client;
  late matrix.Event event;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('cache_hit');
    PaintingBinding.instance.imageCache.clear();
    requests = [];
    client = mediaClient(MockClient((request) async {
      requests.add(request.url.path);
      return http.Response('{"versions": ["v1.11"]}', 200);
    }), Uri.parse('https://hs.example'));
    final room = matrix.Room(id: '!room:hs.example', client: client);
    event = attachmentEvent(room,
        size: 2000000, thumbnail: 'mxc://hs.example/Thumb');
  });

  tearDown(() {
    fileCache = null;
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows: a file still held.
    }
  });

  /// Shows the picture of [event] in the timeline, as the chat does, until
  /// its first image arrives.
  Future<void> show() async {
    final picture = MatrixMxcImage(event.attachmentMxcUrl!, client,
        doThumbnail: true,
        doFullres: true,
        autoLoadFullRes: false,
        matrixEvent: event);
    final shown = Completer<void>();
    final stream = picture.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((_, __) {
      if (!shown.isCompleted) shown.complete();
    }, onError: (error, stack) => shown.completeError(error, stack));
    stream.addListener(listener);
    await shown.future.timeout(const Duration(seconds: 10));
    stream.removeListener(listener);
  }

  String thumbnailKey() =>
      MatrixMxcImage.getThumbnailIdentifier(event.attachmentMxcUrl!);

  test('a thumbnail cache hit is one lookup (fake cache)', () async {
    final cache = CountingFileCache(dir);
    await cache.putFile(thumbnailKey(), pngPicture());
    fileCache = cache;

    await show();

    // ignore: avoid_print
    print('cache lookups for one thumbnail hit: ${cache.lookups}; '
        'requests: ${requests.length}');
    expect(cache.lookups, 1);
    expect(requests, isEmpty);
  });

  test('a thumbnail cache hit is one query (drift)', () async {
    final counter = StatementCounter();
    final cache = DriftFileCache()
      ..database = DriftFileCacheDatabase(
          NativeDatabase.memory().interceptWith(counter));
    final file = File('${dir.path}/thumbnail')..writeAsBytesSync(pngPicture());
    final db = cache.database!;
    await db.into(db.fileCacheEntry).insert(FileCacheEntryCompanion.insert(
        id: thumbnailKey(),
        path: file.path,
        lastAccessedTimestamp: DateTime.now().millisecondsSinceEpoch));
    fileCache = cache;
    counter.statements.clear();

    await show();
    // Writes nobody awaits (the access time) land here.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // ignore: avoid_print
    print('statements for one thumbnail hit: ${counter.statements}');
    expect(counter.statements, ['select']);
    await cache.close();
  });

  test('an entry not read for an hour gets its access time written once',
      () async {
    final counter = StatementCounter();
    final cache = DriftFileCache()
      ..database = DriftFileCacheDatabase(
          NativeDatabase.memory().interceptWith(counter));
    final file = File('${dir.path}/thumbnail')..writeAsBytesSync(pngPicture());
    final db = cache.database!;
    final old = DateTime.now().subtract(const Duration(hours: 2));
    await db.into(db.fileCacheEntry).insert(FileCacheEntryCompanion.insert(
        id: thumbnailKey(),
        path: file.path,
        lastAccessedTimestamp: old.millisecondsSinceEpoch));
    counter.statements.clear();

    expect(await cache.getFile(thumbnailKey()), file.uri);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(counter.statements, ['select', 'update']);
    final row = await db.select(db.fileCacheEntry).getSingle();
    expect(row.lastAccessedTimestamp, greaterThan(old.millisecondsSinceEpoch));

    counter.statements.clear();
    expect(await cache.getFile(thumbnailKey()), file.uri);
    expect(counter.statements, ['select']);
    await cache.close();
  });

  test('an entry whose file is gone is no hit, and its row goes', () async {
    final cache = DriftFileCache()
      ..database = DriftFileCacheDatabase(NativeDatabase.memory());
    final db = cache.database!;
    await db.into(db.fileCacheEntry).insert(FileCacheEntryCompanion.insert(
        id: thumbnailKey(),
        path: '${dir.path}/gone',
        lastAccessedTimestamp: 0));
    expect(await cache.getFile(thumbnailKey()), isNull);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await db.select(db.fileCacheEntry).get(), isEmpty);
    await cache.close();
  });
}
