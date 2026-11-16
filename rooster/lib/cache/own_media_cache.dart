/// The media an account sent from this device, kept so that showing it
/// again asks the homeserver for nothing.
///
/// Native: entries of the app's file cache under the account's own prefix.
/// Web, which has no file cache: an in-memory map for the session, 64 MB
/// for every account together, the oldest entry out first. Both are per
/// account and cleared on logout ([clear]).
library;

import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:rooster/cache/file_cache.dart';
import 'package:rooster/debug/log.dart';

abstract class OwnMediaCache {
  /// [account]'s cache: in [files] when there is a file cache (native), in
  /// [OwnMediaMemory.instance] otherwise (web).
  factory OwnMediaCache.forAccount(String account, {FileCache? files}) =>
      files == null
          ? MemoryOwnMediaCache(account, OwnMediaMemory.instance)
          : FileOwnMediaCache(account, files);

  /// Keeps [bytes] under [key]. What is written can be read at once, while
  /// it is still going to disk.
  Future<void> write(String key, Uint8List bytes);

  /// The bytes kept under [key], or null.
  Future<Uint8List?> read(String key);

  /// The file holding [key]'s bytes (native), once written; null when there
  /// is none (the web keeps no files).
  Future<Uri?> fileOf(String key);

  /// Forgets [key].
  Future<void> remove(String key);

  /// Forgets everything this account kept.
  Future<void> clear();
}

/// The web's map: entries of every account in the order they came, the
/// oldest taken out first while the whole is over [limitBytes]. A file
/// larger than the limit is not kept.
class OwnMediaMemory {
  OwnMediaMemory({this.limitBytes = 64 * 1024 * 1024});

  static final OwnMediaMemory instance = OwnMediaMemory();

  final int limitBytes;
  final LinkedHashMap<(String, String), Uint8List> _entries = LinkedHashMap();
  int _bytes = 0;

  /// The bytes held, for every account.
  int get bytes => _bytes;

  void put(String account, String key, Uint8List bytes) {
    _remove((account, key));
    if (bytes.length > limitBytes) return;
    while (_bytes + bytes.length > limitBytes) {
      _remove(_entries.keys.first);
    }
    _entries[(account, key)] = bytes;
    _bytes += bytes.length;
  }

  Uint8List? get(String account, String key) => _entries[(account, key)];

  void remove(String account, String key) => _remove((account, key));

  void removeAccount(String account) {
    for (final id in _entries.keys.where((id) => id.$1 == account).toList()) {
      _remove(id);
    }
  }

  void _remove((String, String) id) {
    final old = _entries.remove(id);
    if (old != null) _bytes -= old.length;
  }
}

class MemoryOwnMediaCache implements OwnMediaCache {
  MemoryOwnMediaCache(this.account, this.memory);

  final String account;
  final OwnMediaMemory memory;

  @override
  Future<void> write(String key, Uint8List bytes) async =>
      memory.put(account, key, bytes);

  @override
  Future<Uint8List?> read(String key) async => memory.get(account, key);

  @override
  Future<Uri?> fileOf(String key) async => null;

  @override
  Future<void> remove(String key) async => memory.remove(account, key);

  @override
  Future<void> clear() async => memory.removeAccount(account);
}

/// Entries of the app's file cache named `own_media/<account>/<key>`, so
/// that logging out removes exactly this account's. The bytes being
/// written are read from memory until they are on disk.
class FileOwnMediaCache implements OwnMediaCache {
  FileOwnMediaCache(this.account, this.files);

  final String account;
  final FileCache files;
  final Map<String, Uint8List> _writing = {};
  final Map<String, Future<void>> _writes = {};
  int _clears = 0;

  String get prefix => 'own_media/$account/';

  @override
  Future<void> write(String key, Uint8List bytes) {
    // An address is uploaded once: the same key holds the same bytes.
    final writing = _writes[key];
    if (writing != null) return writing;
    _writing[key] = bytes;
    final write = _write(key, bytes);
    _writes[key] = write;
    return write.whenComplete(() {
      if (identical(_writing[key], bytes)) _writing.remove(key);
      if (identical(_writes[key], write)) _writes.remove(key);
    });
  }

  Future<void> _write(String key, Uint8List bytes) async {
    final clears = _clears;
    // Kept already (the event sent again after it failed): writing it again
    // would leave the first file on disk with no entry.
    if (await files.hasFile(prefix + key)) return;
    await files.putFile(prefix + key, bytes);
    // Logged out while it was being written: not kept.
    if (clears != _clears) await files.removeFile(prefix + key);
  }

  @override
  Future<Uri?> fileOf(String key) async {
    try {
      await _writes[key];
    } catch (_) {
      // The write failed: there is no file.
      return null;
    }
    return files.getFile(prefix + key);
  }

  @override
  Future<Uint8List?> read(String key) async {
    final writing = _writing[key];
    if (writing != null) return writing;
    final uri = await files.getFile(prefix + key);
    if (uri == null) return null;
    try {
      return await File.fromUri(uri).readAsBytes();
    } on FileSystemException catch (error) {
      Log.w("Own media gone from the file cache: ${error.osError?.message}");
      return null;
    }
  }

  @override
  Future<void> remove(String key) async {
    try {
      await _writes[key];
    } catch (_) {
      // The write failed: whatever it left goes below.
    }
    _writing.remove(key);
    await files.removeFile(prefix + key);
  }

  @override
  Future<void> clear() async {
    _clears++;
    _writing.clear();
    await files.removeFilesStartingWith(prefix);
  }
}
