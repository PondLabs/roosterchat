import 'dart:io';
import 'package:rooster/cache/file_cache.dart';
import 'package:rooster/config/app_config.dart';
import 'package:rooster/config/build_config.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/utils/database/multiple_database_server.dart';
import 'package:rooster/utils/rng.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'drift_file_cache.g.dart';

FileCache? getFileCacheImplementation() {
  return DriftFileCache();
}

class FileCacheEntry extends Table {
  TextColumn get id => text()();
  TextColumn get path => text()();

  IntColumn get lastAccessedTimestamp => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [FileCacheEntry])
class DriftFileCacheDatabase extends _$DriftFileCacheDatabase {
  DriftFileCacheDatabase(super.e);

  @override
  int get schemaVersion => 1;
}

class DriftFileCache implements FileCache {
  DriftFileCacheDatabase? database;

  static const String isolateName = "com.pondlabs.rooster.isolate.file_cache";

  @override
  Future<void> clean() async {
    Log.i("Cleaning files");
    final db = await get();
    var now = DateTime.now();
    var cutoffTime = now.subtract(const Duration(days: 5));
    var timeMs = cutoffTime.millisecondsSinceEpoch;

    var removeFiles = await (db.select(db.fileCacheEntry)
          ..where(
              (tbl) => tbl.lastAccessedTimestamp.isSmallerThanValue(timeMs)))
        .get();

    // A count, not every row: this runs at every launch on the database
    // isolate the Matrix database shares, and loading the whole table over
    // the port held up the room list behind it.
    final total = await (db.selectOnly(db.fileCacheEntry)
          ..addColumns([db.fileCacheEntry.id.count()]))
        .map((row) => row.read(db.fileCacheEntry.id.count()))
        .getSingle();

    Log.i("Found: ${removeFiles.length}/$total files for cleaning");

    // Only the entries whose file is gone: one that could not be deleted
    // (in use, on Windows) keeps its entry, for a later clean or logout
    // to find, instead of staying on disk unknown to the cache.
    final removedIds = (await Future.wait(removeFiles.map((entry) async {
      try {
        await _cleanFile(entry);
        return entry.id;
      } on FileSystemException catch (error) {
        Log.w("Could not delete a cached file: ${error.osError?.message}");
        return null;
      }
    })))
        .nonNulls
        .toList();
    await (db.delete(db.fileCacheEntry)
          ..where((tbl) => tbl.id.isIn(removedIds)))
        .go();
  }

  Future<void> _cleanFile(FileCacheEntryData entry) async {
    var file = File(entry.path);
    if (!await file.exists()) {
      return;
    }

    await deleteFile(file);
  }

  /// Deletes a cached [file]. Only tests replace it (a file in use).
  Future<void> deleteFile(File file) => file.delete();

  /// Writes a cached [file]. Only tests replace it (a write that stops).
  Future<void> writeBytes(File file, Uint8List bytes) =>
      file.writeAsBytes(bytes);

  /// Writes [bytes] to a new file and gives it the entry [identifier]. A
  /// write or an entry that fails takes the file with it: no file stays
  /// on disk without its entry.
  Future<Uri> _store(String identifier, Uint8List bytes) async {
    var path = await generateTempFilePath();
    if (BuildConfig.DEBUG) path += "_${Uri.encodeComponent(identifier)}";
    final db = await get();
    var file = File(path);
    try {
      await file.create(recursive: true);
      await writeBytes(file, bytes);

      var entry = FileCacheEntryCompanion.insert(
          id: identifier,
          path: path,
          lastAccessedTimestamp: DateTime.now().millisecondsSinceEpoch);
      await db.into(db.fileCacheEntry).insertOnConflictUpdate(entry);
    } catch (_) {
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // Nothing more to do: the error below is what matters.
      }
      rethrow;
    }

    return file.uri;
  }

  @override
  Future<void> removeFile(String identifier) =>
      _remove((tbl) => tbl.id.equals(identifier));

  @override
  Future<void> removeFilesStartingWith(String prefix) {
    // LIKE with its wildcards escaped: the prefix is matched as it is.
    final pattern = prefix
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    return _remove((tbl) => tbl.id.like('$pattern%', escapeChar: r'\'));
  }

  Future<void> _remove(
      Expression<bool> Function($FileCacheEntryTable tbl) where) async {
    final db = await get();
    final entries = await (db.select(db.fileCacheEntry)..where(where)).get();
    for (final entry in entries) {
      try {
        await _cleanFile(entry);
      } on FileSystemException catch (error) {
        // In use (Windows): its entry stays, for clean() to take later, and
        // the others go.
        Log.w("Could not delete a cached file: ${error.osError?.message}");
        continue;
      }
      await (db.delete(db.fileCacheEntry)
            ..where((tbl) => tbl.id.equals(entry.id)))
          .go();
    }
  }

  @override
  Future<void> close() async {
    return await database?.close();
  }

  @override
  Future<Uri> fetchFile(
      String identifier, Future<Uint8List> Function() getter) async {
    var existing = await getFile(identifier);
    if (existing != null) return existing;

    return _store(identifier, await getter());
  }

  /// How stale an entry's access time may get before a read writes it
  /// again: a hit is then one query, and [clean] (5 days) still sees
  /// every entry read in the last hour as used.
  static const accessTimeSlack = Duration(hours: 1);

  /// One query: the entry, then its file on disk. An entry whose file is
  /// gone is forgotten.
  @override
  Future<Uri?> getFile(String identifier) async {
    var entry = await _getByFileId(identifier);
    if (entry == null) return null;

    final db = await get();
    var file = File(entry.path);
    if (!await file.exists()) {
      (db.delete(db.fileCacheEntry)..where((tbl) => tbl.id.equals(entry.id)))
          .go();
      return null;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - entry.lastAccessedTimestamp > accessTimeSlack.inMilliseconds) {
      // An update, never an insert: an entry removed meanwhile stays
      // removed.
      (db.update(db.fileCacheEntry)..where((tbl) => tbl.id.equals(entry.id)))
          .write(FileCacheEntryCompanion(lastAccessedTimestamp: Value(now)));
    }

    return file.uri;
  }

  @override
  Future<bool> hasFile(String identifier) async {
    var file = await _getByFileId(identifier);
    if (file == null) return false;
    final db = await get();
    // if the file exists in the database but not on disk, we should remove it from db
    var exists = await File(file.path).exists();
    if (!exists)
      (db.delete(db.fileCacheEntry)..where((tbl) => tbl.id.equals(file.id)))
          .go();

    return exists;
  }

  @override
  Future<void> init() async {
    var tempDir = await getTemporaryDirectory();
    var temp = p.join(tempDir.path, "com.pondlabs.rooster", "file_cache");

    Log.i("Cache: $temp");

    final dir = p.join(await AppConfig.getDatabasePath(), "app");
    var directory = Directory(dir);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final file = File(p.join(dir, "app_data.db"));

    var connection = await DatabaseIsolate.connect(file.absolute.path);
    database = DriftFileCacheDatabase(connection);
  }

  @override
  Future<Uri> putFile(String identifier, Uint8List bytes) =>
      _store(identifier, bytes);

  Future<DriftFileCacheDatabase> get() async {
    if (database != null) {
      return database!;
    }

    await init();
    return database!;
  }

  Future<String> newPath() async {
    final dir = await getTemporaryDirectory();
    String fileName = RandomUtils.getRandomString(30);
    return p.join(dir.path, "com.pondlabs.rooster", "file_cache", fileName);
  }

  Future<String> generateTempFilePath() async {
    var path = "";
    for (path = await newPath();
        await File(path).exists();
        path = await newPath()) {}

    return path;
  }

  Future<FileCacheEntryData?> _getByFileId(String fileId) async {
    final db = await get();
    return (db.select(db.fileCacheEntry)
          ..where((tbl) => tbl.id.equals(fileId))
          ..limit(1))
        .getSingleOrNull();
  }
}
